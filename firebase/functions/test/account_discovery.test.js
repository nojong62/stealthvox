const test = require("node:test");
const assert = require("node:assert/strict");
const {resolveDiscoveryUid} = require("../account_discovery");

const fakeDb = (docs) => ({
  collection: (name) => ({
    doc: (id) => ({
      get: async () => {
        const value = docs[name + "/" + id];
        return {exists: value !== undefined, data: () => value};
      },
    }),
  }),
});

const fakeAuth = (googleUsers) => ({
  getUserByProviderUid: async (providerId, uid) => {
    assert.equal(providerId, "google.com");
    if (googleUsers[uid]) return {uid: googleUsers[uid]};
    throw Object.assign(new Error("no user"), {code: "auth/user-not-found"});
  },
});

test("Google accounts without a map entry are found in Auth", async () => {
  const deps = {db: fakeDb({}), auth: fakeAuth({"sub-1": "uid-1"})};
  assert.equal(await resolveDiscoveryUid(deps, "google", "sub-1"), "uid-1");
  assert.equal(await resolveDiscoveryUid(deps, "google", "sub-2"), null);
});

test("the legacy Google map still wins when present", async () => {
  const deps = {
    db: fakeDb({"provider_uid_map/google:sub-1": {uid: "legacy-uid"}}),
    auth: fakeAuth({"sub-1": "auth-uid"}),
  };
  assert.equal(await resolveDiscoveryUid(deps, "google", "sub-1"), "legacy-uid");
});

test("Kakao uses only its map, and Auth errors other than not-found surface", async () => {
  const deps = {db: fakeDb({"kakao_uid_map/k1": {uid: "uid-k"}}), auth: fakeAuth({})};
  assert.equal(await resolveDiscoveryUid(deps, "kakao", "k1"), "uid-k");
  assert.equal(await resolveDiscoveryUid(deps, "kakao", "k2"), null);

  const broken = {db: fakeDb({}), auth: {getUserByProviderUid: async () => {
    throw Object.assign(new Error("quota"), {code: "auth/internal-error"});
  }}};
  await assert.rejects(resolveDiscoveryUid(broken, "google", "s"), {code: "auth/internal-error"});
});
