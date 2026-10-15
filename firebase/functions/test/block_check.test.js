const test = require("node:test");
const assert = require("node:assert/strict");
const {createBlockedCache, readBlocked} = require("../block_check");
const {resolveAiAccess} = require("../ai_access");
const {createInterpretUtteranceHandler} = require("../duo_interpreter");

function fakeDb(docs, counter = {reads: 0}) {
  return {
    doc(path) {
      return {
        async get() {
          counter.reads += 1;
          if (docs.fail) throw new Error("unavailable");
          const value = docs[path];
          return {exists: value !== undefined, data: () => value};
        },
      };
    },
  };
}

test("readBlocked is true only for blocked == true", async () => {
  const db = fakeDb({
    "user_flags/a": {blocked: true},
    "user_flags/b": {blocked: false},
    "user_flags/c": {blocked: "true"},
  });
  assert.equal(await readBlocked(db, "a"), true);
  assert.equal(await readBlocked(db, "b"), false);
  assert.equal(await readBlocked(db, "c"), false);
  assert.equal(await readBlocked(db, "missing"), false);
  assert.equal(await readBlocked(db, ""), false);
});

test("blocked cache reads once per ttl and sees a block after expiry", async () => {
  let t = 0;
  const docs = {};
  const counter = {reads: 0};
  const db = fakeDb(docs, counter);
  const isBlocked = createBlockedCache({ttlMs: 15000, now: () => t});

  assert.equal(await isBlocked(db, "u"), false);
  docs["user_flags/u"] = {blocked: true};
  t = 14999;
  assert.equal(await isBlocked(db, "u"), false);
  assert.equal(counter.reads, 1);
  t = 15000;
  assert.equal(await isBlocked(db, "u"), true);
  assert.equal(counter.reads, 2);
});

test("blocked cache fails open on read errors", async () => {
  const errors = [];
  const isBlocked = createBlockedCache({onError: (e) => errors.push(e.message)});
  assert.equal(await isBlocked(fakeDb({fail: true}), "u"), false);
  assert.deepEqual(errors, ["unavailable"]);
});

test("resolveAiAccess denies a blocked user even with paid time", async () => {
  const db = fakeDb({
    "users/u": {remainingTime: 3600},
    "user_flags/u": {blocked: true},
  });
  assert.deepEqual(await resolveAiAccess({db, uid: "u"}),
    {allowed: false, reason: "blocked"});

  const unblocked = fakeDb({"users/u": {remainingTime: 3600}, "user_flags/u": {blocked: false}});
  assert.equal((await resolveAiAccess({db: unblocked, uid: "u"})).allowed, true);
});

test("interpretUtterance rejects a blocked caller before reserving anything", async () => {
  const handler = createInterpretUtteranceHandler({
    db: {doc() { throw new Error("must not touch the room"); }},
    isBlocked: async (_db, uid) => uid === "blocked-guest",
  });
  await assert.rejects(handler({roomId: "room-1"}, {auth: {uid: "blocked-guest"}}),
    {code: "permission-denied"});
});
