const test = require("node:test");
const assert = require("node:assert/strict");
const {crashMail, queueCrashMail} = require("../crash_alert");

const issue = {id: "abc123", title: "NullPointerException", subtitle: "lobby_master.dart:420", appVersion: "1.0.263 (263)"};

test("a new fatal issue becomes a mail with the title, place and version", () => {
  const mail = crashMail("fatal", {issue});
  assert.match(mail.subject, /새 치명 오류/);
  assert.match(mail.subject, /NullPointerException/);
  assert.match(mail.text, /위치: lobby_master\.dart:420/);
  assert.match(mail.text, /앱 버전: 1\.0\.263/);
  assert.match(mail.text, /crashlytics/);
});

test("a velocity alert carries the crash count and share", () => {
  const mail = crashMail("velocity", {issue, crashCount: 12, crashPercentage: 1.2345, firstVersion: "1.0.262"});
  assert.match(mail.text, /12건/);
  assert.match(mail.text, /1\.23%/);
  assert.match(mail.text, /1\.0\.262/);
});

test("a missing payload still produces a readable mail", () => {
  const mail = crashMail("anr", undefined);
  assert.match(mail.text, /제목 없음|\(제목 없음\)/);
});

test("long text is cut so one alert cannot flood the mail", () => {
  const mail = crashMail("fatal", {issue: {title: "x".repeat(500), subtitle: "y".repeat(900)}});
  assert.ok(mail.subject.length < 140);
  assert.ok(mail.text.length < 900);
});

test("queueing writes to the mail collection and never throws", async () => {
  const added = [];
  const ok = {collection: (name) => ({add: async (doc) => { added.push([name, doc]); return {id: "m1"}; }})};
  assert.deepEqual(await queueCrashMail(ok, "fatal", {issue}), {sent: true, mailId: "m1"});
  assert.equal(added[0][0], "mail");
  assert.deepEqual(added[0][1].to, ["nisiekorea@gmail.com"]);
  const broken = {collection: () => ({add: async () => { throw new Error("down"); }})};
  assert.deepEqual(await queueCrashMail(broken, "fatal", {issue}), {sent: false});
});
