const auth = require('C:/Users/u/AppData/Roaming/npm/node_modules/firebase-tools/lib/auth');
async function main() {
  const account = auth.getProjectDefaultAccount(process.cwd());
  if (!account) throw new Error('Firebase CLI login required');
  const token = await auth.getAccessToken(account.tokens.refresh_token,
    ['https://www.googleapis.com/auth/cloud-platform']);
  const headers = {Authorization: 'Bearer ' + token.access_token,
    'Content-Type': 'application/json'};
  const base = 'https://firestore.googleapis.com/v1/projects/stealth-vox-3p3rq3/databases/(default)/documents';
  const res = await fetch(base + ':runQuery', {method: 'POST', headers,
    body: JSON.stringify({structuredQuery: {
      from: [{collectionId: 'duo_board_posts'}],
      where: {fieldFilter: {field: {fieldPath: 'topic'}, op: 'EQUAL',
        value: {stringValue: '한국어 배울 분'}}}, limit: 5,
      select: {fields: ['ownerUid','active','discoverable','ownerPaused','state']
        .map(fieldPath => ({fieldPath}))}
    }})});
  if (!res.ok) throw new Error('Board read HTTP ' + res.status);
  const rows = await res.json();
  for (const row of rows) {
    if (!row.document) continue;
    const doc = row.document;
    const fields = doc.fields;
    const uid = fields.ownerUid.stringValue;
    const id = doc.name.split('/').pop();
    if (fields.active?.booleanValue === true) {
      const lookup = await fetch(base + ':runQuery', {method: 'POST', headers,
        body: JSON.stringify({structuredQuery: {
          from: [{collectionId: 'duo_board_posts'}],
          where: {compositeFilter: {op: 'AND', filters: [
            {fieldFilter: {field: {fieldPath: 'ownerUid'}, op: 'EQUAL',
              value: {stringValue: uid}}},
            {fieldFilter: {field: {fieldPath: 'active'}, op: 'EQUAL',
              value: {booleanValue: true}}}
          ]}}, limit: 1
        }})});
      const result = await lookup.json();
      console.log(JSON.stringify({ownPostQueryStatus: lookup.status,
        found: Array.isArray(result) && result.some(r => !!r.document),
        error: result.error?.message}));
    }
    const roomRes = await fetch(base + '/duo_sessions/' + id +
      '?mask.fieldPaths=hostUid&mask.fieldPaths=isDuoEnabled&mask.fieldPaths=isPartnerJoined',
      {headers});
    const room = roomRes.ok ? await roomRes.json() : null;
    const presenceRes = await fetch(
      'https://stealth-vox-3p3rq3-default-rtdb.asia-southeast1.firebasedatabase.app/duo_board_hosts/' +
      encodeURIComponent(uid) + '.json', {headers});
    const presence = presenceRes.ok ? await presenceRes.json() : null;
    console.log(JSON.stringify({
      active: fields.active?.booleanValue, discoverable: fields.discoverable?.booleanValue,
      ownerPaused: fields.ownerPaused?.booleanValue, state: fields.state?.stringValue,
      roomExists: !!room, ownerMatchesRoom: room?.fields?.hostUid?.stringValue === uid,
      isDuoEnabled: room?.fields?.isDuoEnabled?.booleanValue,
      isPartnerJoined: room?.fields?.isPartnerJoined?.booleanValue,
      presenceReadStatus: presenceRes.status,
      connections: Object.values(presence || {}).map(c => ({
        foreground: c.foreground, ageSeconds: Math.round((Date.now() - c.lastSeen)/1000)
      }))
    }));
  }
}
main().catch(error => { console.error(error.message); process.exitCode = 1; });