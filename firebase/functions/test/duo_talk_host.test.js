const test = require("node:test");
const assert = require("node:assert/strict");
const admin = require("firebase-admin");
const {_test: board} = require("../duo_board");
const {_test: host} = require("../duo_talk_host");
const {activeTalkHostRoom} = require("../ai_access");

test("talk host daily cap is off unless configured", () => {
  assert.equal(board.promoConfigFrom(null).talkHostDailyCallLimit, 0);
  assert.equal(board.promoConfigFrom({talkHostDailyCallLimit: 12}).talkHostDailyCallLimit, 12);
});

test("push hours accept only the dropdown values", () => {
  for (const hours of [0, 1, 2, 4, 8]) assert.equal(board.pushHoursFrom(hours), hours);
  assert.equal(board.pushHoursFrom(undefined), 0);
  assert.throws(() => board.pushHoursFrom(3));
  assert.throws(() => board.pushHoursFrom(24));
});

test("push window is open only before pushUntil", () => {
  const now = Date.UTC(2026, 9, 31, 3);
  const at = ms => admin.firestore.Timestamp.fromMillis(ms);
  assert.equal(board.isPushWindowOpen({pushUntil: at(now + 1000)}, now), true);
  assert.equal(board.isPushWindowOpen({pushUntil: at(now - 1)}, now), false);
  assert.equal(board.isPushWindowOpen({}, now), false);
});

test("push copy never falls through to an empty message", () => {
  assert.match(board.pushCopyFor("Korean")[1], /대화/);
  assert.match(board.pushCopyFor("ja")[1], /話/);
  assert.equal(board.pushCopyFor("Swahili")[0], "StealthVox · Duo");
});

test("guest limits skip the owner when the owner is a talk host", () => {
  const promo = board.promoConfigFrom({guestPostsEnabled: true});
  assert.equal(board.guestCallBlockReasonFrom(promo,
      {dailyCalls: 0, requesterCalls: 0, ownerCalls: 0}), null);
  assert.equal(board.guestCallBlockReasonFrom(promo,
      {dailyCalls: 0, requesterCalls: 3, ownerCalls: 0}), "guest_daily_limit_personal");
});

test("joining as a talk host requires hours and the pledge", () => {
  assert.deepEqual(host.talkHostChange({enabled: false}), {active: false});
  assert.throws(() => host.talkHostChange({enabled: true, dailyHours: 2}));
  assert.throws(() => host.talkHostChange({enabled: true, dailyHours: 5, pledge: true}));
  const ok = host.talkHostChange({enabled: true, dailyHours: 4, pledge: true});
  assert.equal(ok.active, true);
  assert.equal(ok.dailyHours, 4);
});

test("an admin-disabled talk host is not active", () => {
  assert.equal(host.isActiveTalkHostData({active: true}), true);
  assert.equal(host.isActiveTalkHostData({active: true, adminDisabled: true}), false);
  assert.equal(host.isActiveTalkHostData(null), false);
});

test("talk host AI access needs its own live room", () => {
  const room = {isDuoEnabled: true, talkHostRoom: true, hostUid: "h"};
  assert.equal(activeTalkHostRoom(room, "h"), true);
  assert.equal(activeTalkHostRoom(room, "g"), false);
  assert.equal(activeTalkHostRoom({...room, isDuoEnabled: false}, "h"), false);
  assert.equal(activeTalkHostRoom({...room, talkHostRoom: false}, "h"), false);
});
