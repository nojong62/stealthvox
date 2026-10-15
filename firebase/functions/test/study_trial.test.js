const test = require("node:test");
const assert = require("node:assert/strict");
const {
  FIXED_PRACTICE_SETTINGS,
  chatLangForSystem,
  copyRoomData,
  deviceKey,
  judgeDevice,
  learnLangFor,
  pickMasterRoom,
} = require("../study_trial");

test("language pairs: Korean and Chinese learn English, the other 10 learn Korean", () => {
  assert.equal(learnLangFor("Korean"), "English");
  assert.equal(learnLangFor("Chinese"), "English");
  assert.equal(learnLangFor("English"), "Korean");
  assert.equal(learnLangFor("Japanese"), "Korean");
  assert.equal(learnLangFor("French"), "Korean");
  assert.equal(chatLangForSystem("Dutch"), "Dutch");
  assert.equal(chatLangForSystem("Thai"), "English");
  assert.equal(chatLangForSystem(undefined), "English");
});

test("device ids are validated and never used raw as a path", () => {
  const key = deviceKey("a1b2c3d4e5f60718");
  assert.match(key, /^[0-9a-f]{64}$/);
  assert.equal(deviceKey(" a1b2c3d4e5f60718 "), key);
  assert.throws(() => deviceKey("../../users"), {code: "invalid-argument"});
  assert.throws(() => deviceKey("short"), {code: "invalid-argument"});
});

test("one trial per device; same account resumes within the window", () => {
  const now = 1_000_000;
  assert.deepEqual(judgeDevice(null, "u1", now), {kind: "new"});
  assert.deepEqual(
    judgeDevice({uid: "u1", status: "ready", roomId: "r", expiresAtMs: now + 90_500}, "u1", now),
    {kind: "resume", roomId: "r", remainingSeconds: 91});
  assert.equal(judgeDevice({uid: "u1", status: "ready", expiresAtMs: now - 1}, "u1", now).kind, "used");
  assert.equal(judgeDevice({uid: "u2", status: "ready", expiresAtMs: now + 9_000}, "u1", now).kind, "used");
  assert.equal(judgeDevice({uid: "u1", status: "copying"}, "u1", now).kind, "busy");
  assert.equal(judgeDevice({uid: "u2", status: "copying"}, "u1", now).kind, "used");
});

test("master room must be admin-owned, tagged, finalized, and correctly paired", () => {
  const ts = (ms) => ({toMillis: () => ms});
  const base = {study_trial: true, study_trial_chat_lang: "French", target_lang: "Korean",
    history_state: "finalized"};
  const rooms = [
    {ownerUid: "admin", roomId: "old", data: {...base, history_finalized_at: ts(1)}},
    {ownerUid: "admin", roomId: "new", data: {...base, history_finalized_at: ts(2)}},
    {ownerUid: "admin", roomId: "draft", data: {...base, history_state: "draft", history_finalized_at: ts(9)}},
    {ownerUid: "admin", roomId: "wrongpair", data: {...base, target_lang: "English", history_finalized_at: ts(9)}},
    {ownerUid: "mallory", roomId: "forged", data: {...base, history_finalized_at: ts(9)}},
  ];
  const admins = new Set(["admin"]);
  assert.equal(pickMasterRoom(rooms, "French", admins).roomId, "new");
  assert.equal(pickMasterRoom(rooms, "German", admins), null);
  assert.equal(pickMasterRoom(rooms, "French", new Set()), null);
});

test("copy drops master tags and fixes practice settings", () => {
  const copy = copyRoomData({
    study_trial: true, study_trial_chat_lang: "Korean", native_lang: "Korean",
    is_pinned: true, practice_settings: {echoing: {voice: "google-male", repeat: 1}},
  }, {sourcePath: "users/a/chat_history/r", now: "server-time"});
  assert.equal(copy.study_trial, undefined);
  assert.equal(copy.study_trial_chat_lang, undefined);
  assert.equal(copy.native_lang, "Korean");
  assert.equal(copy.is_pinned, false);
  assert.equal(copy.study_trial_copy, true);
  assert.equal(copy.study_trial_source, "users/a/chat_history/r");
  assert.deepEqual(copy.practice_settings, FIXED_PRACTICE_SETTINGS);
  assert.deepEqual(FIXED_PRACTICE_SETTINGS, {
    echoing: {voice: "google-female", repeat: 2},
    shadowing: {voice: "google-male", speed: 0.87},
  });
});
