const test = require("node:test");
const assert = require("node:assert/strict");
const {
  effectiveSignInProvider,
  isRealMemberProvider,
  kakaoMemberFields,
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

function fakeKakaoMap(docs) {
  return {
    collection: (name) => {
      assert.equal(name, "kakao_uid_map");
      return {
        where: (field, op, value) => ({
          limit: () => ({
            get: async () => {
              const hits = docs.filter((d) => d.data[field] === value)
                .map((d) => ({id: d.id, data: () => d.data}));
              return {empty: hits.length === 0, docs: hits};
            },
          }),
        }),
      };
    },
  };
}

test("Kakao members get their member number and nickname from kakao_uid_map", async () => {
  const db = fakeKakaoMap([
    {id: "3141592653", data: {uid: "u1", kakao_id: "3141592653", kakao_nickname: "홍길동"}},
    {id: "2718281828", data: {uid: "u2", kakao_id: "2718281828"}},
  ]);
  assert.deepEqual(await kakaoMemberFields(db, "u1"), {kakaoId: "3141592653", kakaoNickname: "홍길동"});
  // 닉네임 동의가 없던 회원은 회원번호만 적는다.
  assert.deepEqual(await kakaoMemberFields(db, "u2"), {kakaoId: "2718281828"});
  assert.deepEqual(await kakaoMemberFields(db, "nobody"), {});
});
