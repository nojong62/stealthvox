// ====================================================================
// 💰 [DUO-PAY] Duo 요금을 누가 얼마나 내는가 — 2026-11-10 실장님 결정
// --------------------------------------------------------------------
//   · 회원 ↔ 회원      각자 자기 몫(누가 초대했든)
//   · 회원 ↔ 비회원    회원이 양쪽 몫
//   · 비회원 ↔ 비회원  아무도 안 낸다(공개 추천 대화, 서버 부담·기본 음성)
//   · 상대 회원 잔액이 없을 때 초대자가 승인하면(hostCoversPartner) 초대자가
//     양쪽 몫, 상대는 0.
//
// 배율: 통역은 등급 배율(HD 1, 기본 1/2)을 몫만큼, 직접통화는 한 몫이 1/2.
//
// 상대 회원 여부를 모르는 방(옛 앱이 만든 방·옛 앱 게스트)은 예전 규칙
// "초대자가 낸다"로 떨어진다 — 그래야 양쪽이 다 안 내거나 둘 다 내지 않는다.
// ====================================================================

import '../actions/billing_ticker.dart';
import 'voice_tier.dart';

enum DuoPayShare { none, own, both }

/// [partnerIsMember]가 null이면 상대 앱이 이 칸을 모른다(옛 앱).
DuoPayShare duoPayShareFor({
  required bool iAmMember,
  required bool iAmHost,
  required bool? partnerIsMember,
  required bool hostCoversPartner,
}) {
  if (!iAmMember) return DuoPayShare.none;
  if (partnerIsMember == null) {
    return iAmHost ? DuoPayShare.both : DuoPayShare.none;
  }
  if (!partnerIsMember) return DuoPayShare.both;
  if (hostCoversPartner) {
    return iAmHost ? DuoPayShare.both : DuoPayShare.none;
  }
  return DuoPayShare.own;
}

/// 몫과 통화 방식·등급으로 배율을 고른다. [DuoPayShare.none]이면 null.
BillingRate? duoBillingRateFor(
  DuoPayShare share, {
  required bool direct,
  required VoiceTier tier,
}) {
  switch (share) {
    case DuoPayShare.none:
      return null;
    case DuoPayShare.own:
      return direct ? BillingRate.direct : billingRateFor(tier);
    case DuoPayShare.both:
      return direct ? BillingRate.full : billingRateFor(tier, interp: true);
  }
}
