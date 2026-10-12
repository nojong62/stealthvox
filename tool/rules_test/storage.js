const fs = require("fs");
const path = require("path");
const {
  initializeTestEnvironment,
  assertSucceeds,
  assertFails,
} = require("@firebase/rules-unit-testing");
const { ref, uploadString, getBytes } = require("firebase/storage");

let passed = 0;
let failed = 0;

async function check(name, fn) {
  try {
    await fn();
    passed++;
    console.log(`  ✓ ${name}`);
  } catch (error) {
    failed++;
    console.log(`  ✗ ${name}`);
    console.log(`      ${String(error && error.message || error).split("\n")[0]}`);
  }
}

async function main() {
  const env = await initializeTestEnvironment({
    projectId: "stealth-vox-storage-rules-test",
    storage: {
      rules: fs.readFileSync(
        path.join(__dirname, "..", "..", "firebase", "storage.rules"),
        "utf8",
      ),
    },
  });
  const owner = env.authenticatedContext("owner-uid").storage();
  const other = env.authenticatedContext("other-uid").storage();
  const anon = env.unauthenticatedContext().storage();
  const objectPath = "users/owner-uid/private/audio.txt";

  console.log("\n── user storage ownership");
  await check("소유자는 자기 파일을 쓴다", () => assertSucceeds(
    uploadString(ref(owner, objectPath), "private audio"),
  ));
  await check("소유자는 자기 파일을 읽는다", () => assertSucceeds(
    getBytes(ref(owner, objectPath)),
  ));
  await check("다른 인증 사용자는 파일을 읽지 못한다", () => assertFails(
    getBytes(ref(other, objectPath)),
  ));
  await check("다른 인증 사용자는 파일을 덮어쓰지 못한다", () => assertFails(
    uploadString(ref(other, objectPath), "overwrite"),
  ));
  await check("비로그인 사용자는 파일을 읽지 못한다", () => assertFails(
    getBytes(ref(anon, objectPath)),
  ));
  await check("비로그인 사용자는 파일을 쓰지 못한다", () => assertFails(
    uploadString(ref(anon, objectPath), "anonymous"),
  ));

  await env.cleanup();
  console.log(`\n통과 ${passed} / 실패 ${failed}`);
  if (failed) process.exit(1);
}

main().catch(error => {
  console.error(error);
  process.exit(1);
});
