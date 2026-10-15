const test = require("node:test");
const assert = require("node:assert/strict");
const {
  addNote,
  deleteNote,
  requireAdmin,
  requireRequestId,
  requireUid,
  setTestAccount,
} = require("../admin_ops");

class FakeDb {
  constructor(docs = {}) {
    this.docs = new Map(Object.entries(docs));
  }
  doc(path) {
    return {path};
  }
  async runTransaction(run) {
    // 트랜잭션 도중 실패하면 아무것도 반영되지 않아야 한다.
    const staged = new Map(this.docs);
    const result = await run({
      get: async (ref) => {
        const value = staged.get(ref.path);
        return {exists: value !== undefined, data: () => value};
      },
      set: (ref, value, options) => {
        const base = options && options.merge ? staged.get(ref.path) || {} : {};
        staged.set(ref.path, {...base, ...value});
      },
    });
    this.docs = staged;
    return result;
  }
  get(path) {
    return this.docs.get(path);
  }
  paths(prefix) {
    return [...this.docs.keys()].filter((p) => p.startsWith(prefix));
  }
}

const base = {adminUid: "admin-1", now: "server-time"};

test("requireAdmin accepts only the admin claim", () => {
  assert.equal(requireAdmin({auth: {uid: "a", token: {admin: true}}}), "a");
  assert.throws(() => requireAdmin({}), {code: "unauthenticated"});
  assert.throws(() => requireAdmin({auth: {uid: "a", token: {}}}), {code: "permission-denied"});
  assert.throws(() => requireAdmin({auth: {uid: "a", token: {admin: "true"}}}),
    {code: "permission-denied"});
});

test("uid and requestId validation rejects path tricks", () => {
  assert.equal(requireUid(" z3MxTp8WZ3ZHXAKMa93zn68tbXi2 "), "z3MxTp8WZ3ZHXAKMa93zn68tbXi2");
  assert.throws(() => requireUid("a/b/c/d"), {code: "invalid-argument"});
  assert.throws(() => requireUid(""), {code: "invalid-argument"});
  assert.equal(requireRequestId("0b6f3c1e-1111-4222-8333-944455556666"),
    "0b6f3c1e-1111-4222-8333-944455556666");
  assert.throws(() => requireRequestId("../x"), {code: "invalid-argument"});
});

test("addNote writes the note and one audit row, and a retry writes nothing more", async () => {
  const db = new FakeDb();
  const input = {...base, db, uid: "user-1", text: "  환불 문의  ", requestId: "req-00001"};
  assert.deepEqual(await addNote(input), {duplicate: false, noteId: "req-00001"});
  assert.deepEqual(await addNote(input), {duplicate: true, noteId: "req-00001"});

  assert.deepEqual(db.get("admin_notes/user-1/notes/req-00001"),
    {text: "환불 문의", adminUid: "admin-1", createdAt: "server-time", deleted: false});
  assert.equal(db.paths("admin_audit/").length, 1);
  assert.equal(db.get("admin_audit/add_note_req-00001").targetUid, "user-1");
});

test("addNote rejects empty and oversized notes", async () => {
  const db = new FakeDb();
  for (const text of ["   ", "x".repeat(2001), null]) {
    await assert.rejects(addNote({...base, db, uid: "user-1", text, requestId: "req-00001"}),
      {code: "invalid-argument"});
  }
  assert.equal(db.docs.size, 0);
});

test("deleteNote soft-deletes once and keeps the text in the audit row", async () => {
  const db = new FakeDb({
    "admin_notes/user-1/notes/req-00001": {text: "메모", deleted: false},
  });
  const input = {...base, db, uid: "user-1", noteId: "req-00001"};
  assert.deepEqual(await deleteNote(input), {duplicate: false});
  assert.deepEqual(await deleteNote(input), {duplicate: true});

  const note = db.get("admin_notes/user-1/notes/req-00001");
  assert.equal(note.deleted, true);
  assert.equal(note.text, "메모");
  assert.deepEqual(db.get("admin_audit/delete_note_req-00001").before,
    {noteId: "req-00001", text: "메모"});
  await assert.rejects(deleteNote({...input, noteId: "missing-1"}), {code: "not-found"});
});

test("setTestAccount adds the uid to the sandbox allowlist and keeps other fields", async () => {
  const db = new FakeDb({
    "billing_config/revenuecat_sandbox": {enabled: true, allowed_uids: ["other-1"]},
  });
  const result = await setTestAccount({
    ...base, db, uid: "user-1", isTest: true, label: "QA 폰", requestId: "req-00001",
  });
  assert.deepEqual(result, {duplicate: false, isTest: true, testLabel: "QA 폰", sandboxAllowed: true});
  assert.deepEqual(db.get("billing_config/revenuecat_sandbox"),
    {enabled: true, allowed_uids: ["other-1", "user-1"]});
  assert.deepEqual(db.get("user_flags/user-1"),
    {isTest: true, testLabel: "QA 폰", updatedAt: "server-time"});

  const audit = db.get("admin_audit/set_test_account_req-00001");
  assert.deepEqual(audit.before, {isTest: false, testLabel: "", sandboxAllowed: false});
  assert.deepEqual(audit.after, {isTest: true, testLabel: "QA 폰", sandboxAllowed: true});
});

test("setTestAccount off removes the uid, and a retried request is a no-op", async () => {
  const db = new FakeDb({
    "billing_config/revenuecat_sandbox": {allowed_uids: ["user-1", "other-1"]},
    "user_flags/user-1": {isTest: true, testLabel: "QA", blocked: true},
  });
  const input = {...base, db, uid: "user-1", isTest: false, label: "무시됨", requestId: "req-00002"};
  await setTestAccount(input);
  assert.deepEqual(db.get("billing_config/revenuecat_sandbox").allowed_uids, ["other-1"]);
  // 다른 플래그(blocked)는 건드리지 않는다.
  assert.deepEqual(db.get("user_flags/user-1"),
    {isTest: false, testLabel: "", blocked: true, updatedAt: "server-time"});

  // 같은 requestId 재시도: 그사이 다시 켜졌더라도 덮어쓰지 않는다.
  db.docs.set("billing_config/revenuecat_sandbox", {allowed_uids: ["other-1", "user-1"]});
  assert.deepEqual(await setTestAccount(input), {duplicate: true});
  assert.deepEqual(db.get("billing_config/revenuecat_sandbox").allowed_uids, ["other-1", "user-1"]);
});

test("setTestAccount creates the allowlist doc when it does not exist", async () => {
  const db = new FakeDb();
  await setTestAccount({...base, db, uid: "user-1", isTest: true, requestId: "req-00003"});
  assert.deepEqual(db.get("billing_config/revenuecat_sandbox"), {allowed_uids: ["user-1"]});
  await assert.rejects(
    setTestAccount({...base, db, uid: "user-1", isTest: "yes", requestId: "req-00004"}),
    {code: "invalid-argument"});
});
