"use strict";
const test = require("node:test");
const assert = require("node:assert/strict");
const {inactive, designated, runDesignatedGoogleCleanup} = require("../designated_google_cleanup");
const old = new Date(Date.now() - 40 * 86400000).toISOString();
const recent = new Date(Date.now() - 86400000).toISOString();
const user = (extra = {}) => ({uid:"testGoogle", email:"approved@gmail.com", providerData:[{providerId:"google.com"}],
  metadata:{creationTime:old, lastSignInTime:old}, ...extra});
function environment({fresh=user(), kakao=false, legacy=false, failedRead=false}={}) {
  const deleted=[];
  const doc=value=>({data:()=>value});
  const db={doc:()=>({get:async()=>({exists:true,data:()=>({emails:["approved@gmail.com"]})})}),
    collection:name=>({
      get:async()=>{if(failedRead)throw Error("mapping unavailable");return {docs:name==="provider_uid_map"?
        (legacy?[doc({uid:"testGoogle",provider:"google"})]:[]):(kakao?[doc({uid:"testGoogle"})]:[])};},
      where:()=>({limit:()=>({get:async()=>({empty:!kakao})})})
    })};
  const initial=legacy?user({providerData:[]}):user();
  const auth={listUsers:async()=>({users:[initial]}),getUser:async()=>fresh,
    deleteUser:async uid=>deleted.push(uid)};
  return {auth,db,dryRun:false,deleted,log:()=>{}};
}
test("only designated emails with a Google provider or legacy mapping qualify",()=>{
  const emails=new Set(["approved@gmail.com"]), maps=new Set(["testGoogle"]);
  assert.equal(designated(user(),emails,maps),true);
  assert.equal(designated(user({email:"Approved@gmail.com"}),emails,maps),true);
  assert.equal(designated(user({email:"randomname.12345@gmail.com"}),emails,maps),false);
  assert.equal(designated(user({providerData:[]}),emails,maps),true);
  assert.equal(designated(user({providerData:[]}),emails,new Set()),false);
  assert.equal(designated(user({providerData:[{providerId:"password"}]}),emails,maps),false);
  assert.equal(designated(user({customClaims:{admin:true}}),emails,maps),false);
});
test("30-day inactivity includes token refresh and rejects invalid metadata",()=>{
  assert.equal(inactive(user()),true);
  assert.equal(inactive(user({metadata:{creationTime:old,lastSignInTime:old,lastRefreshTime:recent}})),false);
  assert.equal(inactive(user({metadata:{creationTime:old,lastSignInTime:"invalid"}})),false);
});
test("designated Google account deletes without requiring empty application data",async()=>{
  const e=environment();const result=await runDesignatedGoogleCleanup(e);
  assert.deepEqual(e.deleted,["testGoogle"]);assert.equal(result.deletedUids.length,1);
  const legacy=environment({legacy:true,fresh:user({providerData:[]})});
  await runDesignatedGoogleCleanup(legacy);assert.deepEqual(legacy.deleted,["testGoogle"]);
});
test("Kakao, recent activity and changed email block deletion",async()=>{
  for(const options of [{kakao:true},{fresh:user({email:"real@gmail.com"})},
    {fresh:user({metadata:{creationTime:old,lastSignInTime:recent}})}]){
    const e=environment(options);await runDesignatedGoogleCleanup(e);assert.deepEqual(e.deleted,[]);
  }
});
test("dry run and failed mapping reads cannot delete",async()=>{
  const dry=environment();await runDesignatedGoogleCleanup({...dry,dryRun:true});assert.deepEqual(dry.deleted,[]);
  const fail=environment({failedRead:true});await assert.rejects(runDesignatedGoogleCleanup(fail),/unavailable/);
  assert.deepEqual(fail.deleted,[]);
});
