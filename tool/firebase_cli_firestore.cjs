"use strict";
const {Client} = require("C:/Users/u/AppData/Roaming/npm/node_modules/firebase-tools/lib/apiv2");
const client = new Client({urlPrefix: "https://firestore.googleapis.com", apiVersion: "v1"});
const project = "stealth-vox-3p3rq3";
const root = "/projects/" + project + "/databases/(default)/documents";
const cache = new Map();
function decode(v) {
  if ("stringValue" in v) return v.stringValue;
  if ("referenceValue" in v) return {path:v.referenceValue.split("/documents/")[1]};
  if ("mapValue" in v) return Object.fromEntries(Object.entries(v.mapValue.fields || {}).map(([k,x])=>[k,decode(x)]));
  if ("arrayValue" in v) return (v.arrayValue.values || []).map(decode);
  if ("booleanValue" in v) return v.booleanValue;
  if ("integerValue" in v) return Number(v.integerValue);
  if ("doubleValue" in v) return v.doubleValue;
  if ("timestampValue" in v) return v.timestampValue;
  return null;
}
function encode(v) {
  if (v === null || v === undefined) return {nullValue:null};
  if (typeof v === "string") return {stringValue:v};
  if (typeof v === "boolean") return {booleanValue:v};
  if (typeof v === "number") return {integerValue:String(v)};
  if (Array.isArray(v)) return {arrayValue:{values:v.map(encode)}};
  return {mapValue:{fields:Object.fromEntries(Object.entries(v).map(([k,x])=>[k,encode(x)]))}};
}
function snap(raw, path) {
  return {exists:!!raw.createTime,ref:doc(path),
    data:()=>Object.fromEntries(Object.entries(raw.fields || {}).map(([k,x])=>[k,decode(x)]))};
}
async function listCollections(path) {
  const ids=[];let pageToken;
  do {
    const r=await client.post(root+(path?"/"+path:"")+":listCollectionIds",
      {pageSize:1000,...(pageToken?{pageToken}:{})});
    ids.push(...(r.body.collectionIds || []));pageToken=r.body.nextPageToken;
  } while(pageToken);
  return ids.map(id=>collection((path?path+"/":"")+id));
}
function doc(path) {
  return {path,async get() {
    try { const r=await client.get(root+"/"+path);return snap(r.body,path); }
    catch(e){if(e.status===404)return {exists:false,ref:doc(path),data:()=>({})};throw e;}
  },listCollections:()=>listCollections(path)};
}
function collection(path) {
  return {id:path.split("/").at(-1),async listDocuments() {
    const refs=[];let pageToken;
    do {
      const r=await client.get(root+"/"+path,{queryParams:{pageSize:1000,showMissing:true,...(pageToken?{pageToken}:{})}});
      for(const raw of r.body.documents || []) {
        const p=raw.name.split("/documents/")[1];
        refs.push(doc(p));cache.set(p,snap(raw,p));
      }
      pageToken=r.body.nextPageToken;
    }while(pageToken);
    return refs;
  },where(field,op,value){if(op!=="==")throw Error("Unsupported operator");
    return {limit(n){return {async get(){
      const r=await client.post(root+":runQuery",{structuredQuery:{
        from:[{collectionId:path}],where:{fieldFilter:{field:{fieldPath:field},op:"EQUAL",value:encode(value)}},limit:n}});
      return {empty:!(r.body || []).some(row=>row.document)};
    }}}};
  },async add(value) {
    await client.post(root+"/"+path,{fields:Object.fromEntries(Object.entries(value).map(([k,x])=>[k,encode(x)]))});
  }};
}
module.exports={doc,collection,listCollections:()=>listCollections(""),
  getAll:async(...refs)=>Promise.all(refs.map(ref=>cache.get(ref.path)||ref.get()))};

