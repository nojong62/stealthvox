"use strict";
const test = require("node:test");
const assert = require("node:assert/strict");
const {eligible, findUids, hasOwnedData, runCleanup} = require("../anonymous_cleanup");
const now = Date.now();
const old = new Date(now - 40 * 86400000).toISOString();
const recent = new Date(now - 86400000).toISOString();
const user = (extra = {}) => ({uid: "anonymous_test_uid", providerData: [],
  metadata: {creationTime: old, lastSignInTime: old}, ...extra});

test("only inactive unlinked users without email, phone or claims qualify", () => {
  assert.equal(eligible(user(), now), true);
  for (const extra of [{email: "a@example.com"}, {phoneNumber: "123"},
    {providerData: [{providerId: "google.com"}]}, {customClaims: {admin: true}},
    {metadata: {creationTime: old, lastSignInTime: recent}},
    {metadata: {creationTime: old, lastSignInTime: old, lastRefreshTime: recent}},
    {metadata: {creationTime: "invalid", lastSignInTime: old}}]) {
    assert.equal(eligible(user(extra), now), false);
  }
  const boundary = new Date(now - 30 * 86400000).toISOString();
  assert.equal(eligible(user({metadata:{creationTime:boundary,lastSignInTime:boundary}}), now), true);
  assert.equal(eligible(user({metadata:{creationTime:boundary,lastSignInTime:new Date(now-30*86400000+1).toISOString()}}), now), false);
});

test("nested arrays, references, metadata and UID paths protect ownership", () => {
  const ids = new Set(["uidA", "uidB"]);
  assert.deepEqual([...findUids({uidA: {count: 1}}, ids)], ["uidA"]);
  assert.deepEqual([...findUids({members:["uidA"], ref:{path:"users/uidB"},
    name:"users/uidA/audio.wav"}, ids)].sort(), ["uidA", "uidB"]);
});

test("missing user ancestor with surviving child references counts as data", async () => {
  const db={doc:()=>({get:async()=>({exists:false}),
    listCollections:async()=>[{listDocuments:async()=>[{}]}]})};
  assert.equal(await hasOwnedData(db, "uid"), true);
});

function environment({owned=false, storageOwner=false, storageFailure=false,
                      fresh=user(), identityLinked=false, external=false}={}) {
  const deleted=[];
  const ref={path:"users/anonymous_test_uid",get:async()=>({exists:owned}),
    listCollections:async()=>[]};
  const externalRef={path:"duo_sessions/missing/messages/message",
    listCollections:async()=>[]};
  const db={doc:()=>ref, listCollections:async()=>external?[{id:"duo_sessions",
    listDocuments:async()=>[externalRef]}]:[],
    getAll:async()=>[{exists:true,ref:externalRef,data:()=>({speakerUid:"anonymous_test_uid"})}],
    collection:()=>({where:()=>({limit:()=>({get:async()=>({empty:!identityLinked})})})})};
  const auth={listUsers:async()=>({users:[user()]}),getUser:async()=>fresh,
    deleteUser:async uid=>deleted.push(uid)};
  const storage={getBuckets:async()=>{if(storageFailure)throw Error("Storage unavailable");
    return [[{name:"stealth-vox-3p3rq3.firebasestorage.app",getFiles:async()=>[
      storageOwner?[{name:"users/anonymous_test_uid/voice.wav",metadata:{}}]:[],undefined]}]];}};
  return {auth,db,storage,project:"stealth-vox-3p3rq3",dryRun:false,now,deleted,log:()=>{}};
}

test("deletes eligible account only after checks; dry run never deletes", async()=>{
  const e=environment(); const r=await runCleanup(e);
  assert.deepEqual(e.deleted,["anonymous_test_uid"]);assert.equal(r.deletedUids.length,1);
  const d=environment();await runCleanup({...d,dryRun:true});assert.deepEqual(d.deleted,[]);
});

test("owned, external, Storage, custom mapping and newly linked data block deletion",async()=>{
  for(const options of [{owned:true},{external:true},{storageOwner:true},
    {identityLinked:true},{fresh:user({email:"new@example.com"})},
    {fresh:user({metadata:{creationTime:old,lastSignInTime:recent}})}]){
    const e=environment(options);await runCleanup(e);assert.deepEqual(e.deleted,[]);
  }
});

test("failed Storage read aborts before any deletion",async()=>{
  const e=environment({storageFailure:true});
  await assert.rejects(()=>runCleanup(e),/Storage unavailable/);assert.deepEqual(e.deleted,[]);
});

