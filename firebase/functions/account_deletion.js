"use strict";

// 회원 탈퇴(Auth 삭제) 뒤 남는 흔적을 지운다. users/{uid}는 onUserDeleted가
// 따로 통째로 지운다.
//
//   · real_members/{uid} 문서 — 관리자 웹 회원 목록에 탈퇴한 회원이 남지 않게.
//     문서만 지운다. 아래 purchases는 실제 결제 장부라 남긴다.
//   · kakao_uid_map / provider_uid_map 중 이 uid를 가리키는 것 — 남아 있으면
//     같은 카카오로 다시 가입할 때 지워진 uid가 되살아나고, 계정 찾기도
//     지워진 계정을 가리킨다.
//
// 쿠폰 사용 기록(coupons/{code}/redemptions·devices)은 남긴다. 탈퇴 후 재가입으로
// 같은 쿠폰을 또 받지 못하게 하는 장치다.
const IDENTITY_MAPS = ["kakao_uid_map", "provider_uid_map"];

async function cleanUpDeletedAccount(db, uid) {
  const refs = [db.doc("real_members/" + uid)];
  for (const name of IDENTITY_MAPS) {
    const snap = await db.collection(name).where("uid", "==", uid).get();
    snap.docs.forEach((d) => refs.push(d.ref));
  }
  const batch = db.batch();
  refs.forEach((ref) => batch.delete(ref));
  await batch.commit();
  return refs.map((ref) => ref.path);
}

module.exports = {cleanUpDeletedAccount, IDENTITY_MAPS};
