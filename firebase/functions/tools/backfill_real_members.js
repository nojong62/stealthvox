"use strict";

const PROJECT_ID = "stealth-vox-3p3rq3";
const DATABASE = "(default)";
const token = process.env.GOOGLE_ACCESS_TOKEN;

if (!token) {
  throw new Error("GOOGLE_ACCESS_TOKEN is required.");
}

const headers = {
  Authorization: `Bearer ${token}`,
  "Content-Type": "application/json",
  "x-goog-user-project": PROJECT_ID,
};

async function jsonRequest(url, options = {}) {
  const response = await fetch(url, {...options, headers: {...headers, ...options.headers}});
  const body = await response.json().catch(() => ({}));
  if (!response.ok) {
    throw new Error(`${response.status} ${JSON.stringify(body)}`);
  }
  return body;
}

function stringValue(value) {
  return value ? {stringValue: String(value)} : {nullValue: null};
}

function timestampValue(milliseconds) {
  const value = Number(milliseconds);
  return Number.isFinite(value) && value > 0
    ? {timestampValue: new Date(value).toISOString()}
    : {nullValue: null};
}

function documentName(path) {
  return `projects/${PROJECT_ID}/databases/${DATABASE}/documents/${path}`;
}

async function listAuthUsers() {
  const users = [];
  let nextPageToken = "";
  do {
    const query = new URLSearchParams({maxResults: "1000"});
    if (nextPageToken) query.set("nextPageToken", nextPageToken);
    const result = await jsonRequest(
      `https://identitytoolkit.googleapis.com/v1/projects/${PROJECT_ID}/accounts:batchGet?${query}`
    );
    users.push(...(result.users || []));
    nextPageToken = result.nextPageToken || "";
  } while (nextPageToken);
  return users;
}

function isRealMember(user) {
  return Boolean((user.providerUserInfo || []).length || user.email);
}

function memberWrite(user) {
  const providers = [...new Set(
    (user.providerUserInfo || []).map((provider) => provider.providerId).filter(Boolean)
  )].sort();
  if (!providers.length && user.email) providers.push("custom");
  const fieldPaths = [
    "uid", "email", "displayName", "providers", "primaryProvider",
    "joinedAt", "lastSignInAt", "backfilledAt", "isRealMember",
  ];
  return {
    update: {
      name: documentName(`real_members/${user.localId}`),
      fields: {
        uid: {stringValue: user.localId},
        email: stringValue(user.email),
        displayName: stringValue(user.displayName),
        providers: {
          arrayValue: {values: providers.map((value) => ({stringValue: value}))},
        },
        primaryProvider: stringValue(providers[0] || "custom"),
        joinedAt: timestampValue(user.createdAt),
        lastSignInAt: timestampValue(user.lastLoginAt),
        backfilledAt: {timestampValue: new Date().toISOString()},
        isRealMember: {booleanValue: true},
      },
    },
    updateMask: {fieldPaths},
  };
}

async function commit(writes) {
  for (let index = 0; index < writes.length; index += 400) {
    await jsonRequest(
      `https://firestore.googleapis.com/v1/projects/${PROJECT_ID}/databases/${encodeURIComponent(DATABASE)}/documents:commit`,
      {method: "POST", body: JSON.stringify({writes: writes.slice(index, index + 400)})}
    );
  }
}

async function listUserPurchases(realUids) {
  const rows = await jsonRequest(
    `https://firestore.googleapis.com/v1/projects/${PROJECT_ID}/databases/${encodeURIComponent(DATABASE)}/documents:runQuery`,
    {
      method: "POST",
      body: JSON.stringify({
        structuredQuery: {from: [{collectionId: "purchases", allDescendants: true}]},
      }),
    }
  );
  const purchases = [];
  for (const row of rows) {
    const document = row.document;
    if (!document || !document.name) continue;
    const marker = "/documents/users/";
    const offset = document.name.indexOf(marker);
    if (offset < 0) continue;
    const relative = document.name.slice(offset + "/documents/".length);
    const parts = relative.split("/");
    if (parts.length !== 4 || parts[0] !== "users" || parts[2] !== "purchases") continue;
    if (!realUids.has(parts[1])) continue;
    purchases.push({uid: parts[1], id: parts[3], fields: document.fields || {}});
  }
  return purchases;
}

function integerField(fields, name) {
  return Number(fields[name] && fields[name].integerValue || 0);
}

function purchaseWrites(purchases) {
  const writes = [];
  const summaries = new Map();
  for (const purchase of purchases) {
    writes.push({
      update: {
        name: documentName(`real_members/${purchase.uid}/purchases/${purchase.id}`),
        fields: purchase.fields,
      },
    });
    const summary = summaries.get(purchase.uid) || {
      count: 0, seconds: 0, latest: null, productId: null, environment: null,
    };
    summary.count += 1;
    summary.seconds += integerField(purchase.fields, "seconds_added");
    const purchasedAt = purchase.fields.purchased_at && purchase.fields.purchased_at.timestampValue;
    if (purchasedAt && (!summary.latest || purchasedAt > summary.latest)) {
      summary.latest = purchasedAt;
      summary.productId = purchase.fields.product_id && purchase.fields.product_id.stringValue;
      summary.environment = purchase.fields.environment && purchase.fields.environment.stringValue;
    }
    summaries.set(purchase.uid, summary);
  }
  for (const [uid, summary] of summaries) {
    writes.push({
      update: {
        name: documentName(`real_members/${uid}`),
        fields: {
          hasPurchase: {booleanValue: summary.count > 0},
          purchaseCount: {integerValue: String(summary.count)},
          totalSecondsPurchased: {integerValue: String(summary.seconds)},
          lastPurchasedAt: summary.latest
            ? {timestampValue: summary.latest}
            : {nullValue: null},
          lastProductId: stringValue(summary.productId),
          lastPurchaseEnvironment: stringValue(summary.environment),
        },
      },
      updateMask: {fieldPaths: [
        "hasPurchase", "purchaseCount", "totalSecondsPurchased",
        "lastPurchasedAt", "lastProductId", "lastPurchaseEnvironment",
      ]},
    });
  }
  return writes;
}

async function main() {
  const allUsers = await listAuthUsers();
  const realUsers = allUsers.filter(isRealMember);
  const realUids = new Set(realUsers.map((user) => user.localId));
  await commit(realUsers.map(memberWrite));
  const purchases = await listUserPurchases(realUids);
  await commit(purchaseWrites(purchases));
  console.log(JSON.stringify({
    authUsers: allUsers.length,
    realMembersWritten: realUsers.length,
    anonymousExcluded: allUsers.length - realUsers.length,
    purchasesCopied: purchases.length,
  }));
}

main().catch((error) => {
  console.error(error.message);
  process.exitCode = 1;
});
