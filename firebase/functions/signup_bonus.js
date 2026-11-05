"use strict";

// 가입 보너스 — 폰 하나에 한 번(2026-11-06 실장님: 공부방 체험을 대신해 30분).
//
//   · 기기 ID(해시)로 `signup_bonus_devices/{hash}`를 남긴다. 이미 있으면 보너스 없음.
//   · 기기 ID가 없거나 형식이 틀리면 보너스 없음(옛 앱은 ID를 안 보낸다 = 지금처럼 0).
//   · 계정 쪽 멱등(signup_bonus_given)은 호출한 쪽이 먼저 본다.

const crypto = require("crypto");

const SIGNUP_BONUS_SECONDS = 30 * 60;
const DEVICE_COLLECTION = "signup_bonus_devices";

/** 형식이 맞으면 해시, 아니면 null. 에러를 던지지 않는다(보너스만 빠진다). */
function bonusDeviceKey(value) {
  const id = typeof value === "string" ? value.trim() : "";
  if (!/^[A-Za-z0-9_-]{8,128}$/.test(id)) return null;
  return crypto.createHash("sha256").update(id).digest("hex");
}

/** 이 호출이 받을 초. key가 없거나 기기 기록이 이미 있으면 0. */
function bonusSecondsFor({key, deviceRecordExists}) {
  if (!key || deviceRecordExists) return 0;
  return SIGNUP_BONUS_SECONDS;
}

module.exports = {
  SIGNUP_BONUS_SECONDS,
  DEVICE_COLLECTION,
  bonusDeviceKey,
  bonusSecondsFor,
};
