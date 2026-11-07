"use strict";

const test = require("node:test");
const assert = require("node:assert/strict");
const {
  SIGNUP_BONUS_SECONDS,
  bonusDeviceKey,
  bonusSecondsFor,
} = require("../signup_bonus");

test("보너스는 1시간", () => {
  assert.equal(SIGNUP_BONUS_SECONDS, 3600);
});

test("기기 ID 형식이 틀리면 키가 없다", () => {
  assert.equal(bonusDeviceKey(undefined), null);
  assert.equal(bonusDeviceKey(""), null);
  assert.equal(bonusDeviceKey("short"), null);
  assert.equal(bonusDeviceKey("has/slash/in/it/xxxxxxxx"), null);
});

test("같은 기기 ID는 같은 해시, ID 원문은 키에 안 남는다", () => {
  const key = bonusDeviceKey("abcdef0123456789");
  assert.equal(key, bonusDeviceKey(" abcdef0123456789 "));
  assert.match(key, /^[0-9a-f]{64}$/);
});

test("새 폰만 1시간, 이미 받은 폰·ID 없음은 0", () => {
  const key = bonusDeviceKey("abcdef0123456789");
  assert.equal(bonusSecondsFor({key, deviceRecordExists: false}), 3600);
  assert.equal(bonusSecondsFor({key, deviceRecordExists: true}), 0);
  assert.equal(bonusSecondsFor({key: null, deviceRecordExists: false}), 0);
});
