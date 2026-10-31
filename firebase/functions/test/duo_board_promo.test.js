const test = require("node:test");
const assert = require("node:assert/strict");
const admin = require("firebase-admin");
const {_test} = require("../duo_board");

const {promoConfigFrom, kstDayKey, pairKey, isTopicFlagged, distinctRecentReporters} = _test;

test("promo is closed unless the switch is exactly true", () => {
  assert.equal(promoConfigFrom(null).guestPostsEnabled, false);
  assert.equal(promoConfigFrom({guestPostsEnabled: "true"}).guestPostsEnabled, false);
  assert.equal(promoConfigFrom({guestPostsEnabled: true}).guestPostsEnabled, true);
});

test("promo defaults are 3 minutes and 50 guest calls a day", () => {
  const config = promoConfigFrom({guestPostsEnabled: true});
  assert.equal(config.guestCallSeconds, 180);
  assert.equal(config.dailyGuestCallLimit, 50);
  const custom = promoConfigFrom({guestCallSeconds: 240, dailyGuestCallLimit: 0});
  assert.equal(custom.guestCallSeconds, 240);
  assert.equal(custom.dailyGuestCallLimit, 50);
});

test("the daily guest counter rolls over at KST midnight", () => {
  // 2026-10-30 14:59:59Z = 23:59:59 KST, 15:00:00Z = next day in KST.
  assert.equal(kstDayKey(Date.UTC(2026, 9, 30, 14, 59, 59)), "2026-10-30");
  assert.equal(kstDayKey(Date.UTC(2026, 9, 30, 15, 0, 0)), "2026-10-31");
});

test("a pair block is the same in both directions", () => {
  assert.equal(pairKey("b", "a"), pairKey("a", "b"));
});

test("only distinct reporters inside 24 hours count", () => {
  const now = Date.UTC(2026, 9, 30, 12);
  const at = (hoursAgo) => admin.firestore.Timestamp.fromMillis(now - hoursAgo * 3600 * 1000);
  const reports = [
    {reporterUid: "r1", createdAt: at(1)},
    {reporterUid: "r1", createdAt: at(2)},
    {reporterUid: "r2", createdAt: at(3)},
    {reporterUid: "r3", createdAt: at(30)},
  ];
  assert.equal(distinctRecentReporters(reports, now), 2);
  reports.push({reporterUid: "r4", createdAt: at(23)});
  assert.equal(distinctRecentReporters(reports, now), 3);
});

test("topic moderation passes when the API is unavailable", async () => {
  const failing = async () => { throw new Error("offline"); };
  assert.equal(await isTopicFlagged("hello", {apiKey: "k", fetchImpl: failing}), false);
  assert.equal(await isTopicFlagged("hello", {apiKey: ""}), false);
});

test("topic moderation follows the flagged result", async () => {
  const reply = (flagged) => async () => ({ok: true, json: async () => ({results: [{flagged}]})});
  assert.equal(await isTopicFlagged("x", {apiKey: "k", fetchImpl: reply(true)}), true);
  assert.equal(await isTopicFlagged("x", {apiKey: "k", fetchImpl: reply(false)}), false);
});

test("one phone gets 3 guest calls a day by default", () => {
  assert.equal(promoConfigFrom({}).perGuestDailyCalls, 3);
  assert.equal(promoConfigFrom({perGuestDailyCalls: 5}).perGuestDailyCalls, 5);
});

test("guest call limits: daily total first, then requester, then host", () => {
  const {guestCallBlockReasonFrom} = _test;
  const promo = promoConfigFrom({guestPostsEnabled: true});
  const ok = {dailyCalls: 0, requesterCalls: 0, ownerCalls: 0};
  assert.equal(guestCallBlockReasonFrom(promo, ok), null);
  assert.equal(guestCallBlockReasonFrom(promo, {...ok, dailyCalls: 50}), "daily_guest_limit");
  assert.equal(guestCallBlockReasonFrom(promo, {...ok, requesterCalls: 3}), "guest_daily_limit_personal");
  assert.equal(guestCallBlockReasonFrom(promo, {...ok, ownerCalls: 3}), "host_daily_limit");
  assert.equal(guestCallBlockReasonFrom(promo, {...ok, requesterCalls: 2, ownerCalls: 2}), null);
});

test("handoff tickets are stored only as a hash", () => {
  const {hashTicket} = require("../duo_history_handoff")._test;
  const ticket = "a".repeat(64);
  assert.equal(hashTicket(ticket).length, 64);
  assert.notEqual(hashTicket(ticket), ticket);
  assert.equal(hashTicket(ticket), hashTicket(ticket));
});
