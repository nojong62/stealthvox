import 'package:flutter_test/flutter_test.dart';
import 'package:stealth_vox/custom_code/actions/billing_ticker.dart';
import 'package:stealth_vox/custom_code/services/duo_billing_policy.dart';
import 'package:stealth_vox/custom_code/services/voice_tier.dart';

DuoPayShare share({
  bool me = true,
  bool host = true,
  bool? partner = true,
  bool covers = false,
}) =>
    duoPayShareFor(
      iAmMember: me,
      iAmHost: host,
      partnerIsMember: partner,
      hostCoversPartner: covers,
    );

void main() {
  test('members pay their own share whoever invited', () {
    expect(share(host: true), DuoPayShare.own);
    expect(share(host: false), DuoPayShare.own);
  });

  test('a member with a guest who is not a member pays both shares', () {
    expect(share(host: true, partner: false), DuoPayShare.both);
    expect(share(host: false, partner: false), DuoPayShare.both);
  });

  test('non-members never pay', () {
    expect(share(me: false, partner: false), DuoPayShare.none);
    expect(share(me: false, partner: true), DuoPayShare.none);
  });

  test('host covering an empty partner pays both and the partner pays none',
      () {
    expect(share(host: true, covers: true), DuoPayShare.both);
    expect(share(host: false, covers: true), DuoPayShare.none);
  });

  test('an old app on the other side falls back to host pays', () {
    expect(share(host: true, partner: null), DuoPayShare.both);
    expect(share(host: false, partner: null), DuoPayShare.none);
  });

  test('rates: interpreter by tier and share, direct half per share', () {
    BillingRate? rate(DuoPayShare s, bool direct, VoiceTier t) =>
        duoBillingRateFor(s, direct: direct, tier: t);
    expect(rate(DuoPayShare.none, false, VoiceTier.premium), isNull);
    expect(rate(DuoPayShare.own, false, VoiceTier.premium), BillingRate.full);
    expect(rate(DuoPayShare.own, false, VoiceTier.basic), BillingRate.basic);
    expect(rate(DuoPayShare.both, false, VoiceTier.premium),
        BillingRate.interpPremium);
    expect(rate(DuoPayShare.both, false, VoiceTier.basic),
        BillingRate.interpBasic);
    expect(rate(DuoPayShare.own, true, VoiceTier.premium), BillingRate.direct);
    expect(rate(DuoPayShare.both, true, VoiceTier.basic), BillingRate.full);
  });
}
