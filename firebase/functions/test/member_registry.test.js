const test = require("node:test");
const assert = require("node:assert/strict");
const {
  effectiveSignInProvider,
  isRealMemberProvider,
  normalizedProviderIds,
} = require("../member_registry");

const token = (signIn, extra = {}) => ({firebase: {sign_in_provider: signIn}, ...extra});

test("Kakao custom tokens are recorded as kakaocorp.com, not custom", () => {
  const signIn = effectiveSignInProvider(token("custom", {provider: "kakaocorp.com"}));
  assert.equal(signIn, "kakaocorp.com");
  assert.deepEqual(normalizedProviderIds({providerData: []}, signIn), ["kakaocorp.com"]);
});

test("other custom tokens keep their own provider claim", () => {
  // 계정 복구·옛 Google 연결도 커스텀 토큰이다. 카카오로 몰지 않는다.
  assert.equal(effectiveSignInProvider(token("custom", {provider: "google.com"})), "google.com");
  assert.equal(effectiveSignInProvider(token("custom")), "custom");
  assert.equal(effectiveSignInProvider(token("custom", {provider: "../x"})), "custom");
});

test("non-custom sign-ins are unchanged and anonymous stays out", () => {
  assert.equal(effectiveSignInProvider(token("google.com", {provider: "kakaocorp.com"})), "google.com");
  assert.equal(effectiveSignInProvider(token("anonymous")), "anonymous");
  assert.equal(isRealMemberProvider(effectiveSignInProvider(token("anonymous"))), false);
  assert.equal(effectiveSignInProvider(undefined), "");
});
