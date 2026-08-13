// 기존 Google 회원 판정 규칙을 고정한다.
//
// 이 판정이 잘못되면 남의 계정을 Google 로그인으로 가져가거나, 살아 있는
// 회원을 새 UID로 다시 만들어 잔여시간·보너스를 잃는다. 그래서 여기서는
// "언제 커스텀 토큰이 나오면 안 되는가"를 집중적으로 본다.
//
//   node --test firebase/functions/test

const test = require("node:test");
const assert = require("node:assert");
const {
  resolveLegacyGoogleAccount,
} = require("../legacy_google_account");

const notFound = Object.assign(new Error("no user"), {
  code: "auth/user-not-found",
});

const never = () => {
  throw new Error("호출되면 안 된다");
};

test("등록되지 않은 Google sub → none (토큰 발급 금지)", async () => {
  const verdict = await resolveLegacyGoogleAccount({
    googleSub: "sub-unregistered",
    lookupMapping: async () => null,
    getUser: never,
  });
  assert.deepStrictEqual(verdict, { status: "none" });
});

test("sub가 없으면 매핑을 보지도 않고 none", async () => {
  const verdict = await resolveLegacyGoogleAccount({
    googleSub: null,
    lookupMapping: never,
    getUser: never,
  });
  assert.deepStrictEqual(verdict, { status: "none" });
});

test("유효 매핑 + Auth 계정 실재 → valid, 그 UID를 반환", async () => {
  const verdict = await resolveLegacyGoogleAccount({
    googleSub: "sub-1",
    lookupMapping: async (sub) => (sub === "sub-1" ? "uid-1" : null),
    getUser: async (uid) => ({ uid }),
  });
  assert.deepStrictEqual(verdict, { status: "valid", uid: "uid-1" });
});

test("stale 매핑(계정 없음) → stale. none으로 흘려보내지 않는다", async () => {
  const verdict = await resolveLegacyGoogleAccount({
    googleSub: "sub-stale",
    lookupMapping: async () => "uid-gone",
    getUser: async () => {
      throw notFound;
    },
  });
  assert.deepStrictEqual(verdict, { status: "stale" });
});

test("getUser가 빈 값을 주면 stale로 본다", async () => {
  const verdict = await resolveLegacyGoogleAccount({
    googleSub: "sub-stale",
    lookupMapping: async () => "uid-gone",
    getUser: async () => null,
  });
  assert.deepStrictEqual(verdict, { status: "stale" });
});

test("이메일이 같아도 매핑이 없으면 none — 이메일 폴백이 없다", async () => {
  // 이메일/비밀번호 회원과 이메일이 겹치는 상황을 흉내낸다. 매핑이 없으므로
  // 그 계정은 결코 선택되지 않아야 한다.
  let mappingCalls = 0;
  const verdict = await resolveLegacyGoogleAccount({
    googleSub: "sub-of-someone-else",
    lookupMapping: async () => {
      mappingCalls++;
      return null;
    },
    getUser: never, // 이메일로 계정을 찾으러 가면 여기서 터진다
  });
  assert.deepStrictEqual(verdict, { status: "none" });
  assert.strictEqual(mappingCalls, 1);
});

test("user-not-found 외의 오류는 삼키지 않고 올린다", async () => {
  await assert.rejects(
    () =>
      resolveLegacyGoogleAccount({
        googleSub: "sub-1",
        lookupMapping: async () => "uid-1",
        getUser: async () => {
          throw Object.assign(new Error("boom"), { code: "auth/internal-error" });
        },
      }),
    /boom/
  );
});
