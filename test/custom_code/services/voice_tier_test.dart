import 'package:flutter_test/flutter_test.dart';
import 'package:stealth_vox/custom_code/actions/billing_ticker.dart';
import 'package:stealth_vox/custom_code/services/tts_model_policy.dart';
import 'package:stealth_vox/custom_code/services/voice_tier.dart';

void main() {
  tearDown(() =>
      VoiceTierSession.activate(VoiceTier.premium, reason: 'test_reset'));

  test('unknown or missing tier values read as premium', () {
    expect(parseVoiceTier('basic'), VoiceTier.basic);
    expect(parseVoiceTier(' BASIC '), VoiceTier.basic);
    expect(parseVoiceTier('premium'), VoiceTier.premium);
    expect(parseVoiceTier(null), VoiceTier.premium);
    expect(parseVoiceTier(3), VoiceTier.premium);
  });

  test('billing rates follow the 2026-11-09 policy', () {
    expect(billingRateFor(VoiceTier.premium).multiplier, 1.0);
    expect(billingRateFor(VoiceTier.basic).multiplier, closeTo(1 / 2, 1e-9));
    expect(billingRateFor(VoiceTier.premium, interp: true).multiplier, 2.0);
    expect(billingRateFor(VoiceTier.basic, interp: true).multiplier,
        closeTo(1.0, 1e-9));
    // 통역은 몫만큼이다: 기본 음성 두 몫 = 한 몫의 2배.
    expect(billingRateFor(VoiceTier.basic, interp: true).multiplier,
        closeTo(2 * billingRateFor(VoiceTier.basic).multiplier, 1e-9));
    expect(BillingRate.direct.multiplier, 0.5);
  });

  test('one premium hour is two basic hours', () {
    expect(secondsUsableAt(3600, VoiceTier.premium), 3600);
    expect(secondsUsableAt(3600, VoiceTier.basic), 7200);
    expect(secondsUsableAt(0, VoiceTier.basic), 0);
  });

  test('two basic ticks deduct one second', () {
    var debt = 0.0;
    var deducted = 0;
    for (var i = 0; i < 300; i++) {
      debt += BillingRate.basic.multiplier;
      final whole = debt.floor();
      debt -= whole;
      deducted += whole;
    }
    expect(deducted, inInclusiveRange(149, 150));
  });

  test('speech payload carries voice_tier only for the basic tier', () {
    const profile = TtsModelProfile(
      model: 'tts-1',
      optionMode: TtsOptionMode.speed,
      cacheVersion: 'v1',
    );
    Map<String, dynamic> payload() =>
        profile.speechPayload(input: '안녕', voice: 'shimmer', language: 'Korean');

    expect(payload().containsKey('voice_tier'), isFalse);
    VoiceTierSession.activate(VoiceTier.basic, reason: 'test');
    expect(payload()['voice_tier'], 'basic');
  });

  test('study handoff is taken once and only for the same room', () {
    VoiceTierSession.handOffToStudy('users/u/chat_history/a');
    expect(VoiceTierSession.takeHandoff('users/u/chat_history/b'), isFalse);
    // 다른 방이 열리며 지워졌으므로 원래 방도 이제는 이어받지 않는다.
    expect(VoiceTierSession.takeHandoff('users/u/chat_history/a'), isFalse);
    VoiceTierSession.handOffToStudy('users/u/chat_history/a');
    expect(VoiceTierSession.takeHandoff('users/u/chat_history/a'), isTrue);
    expect(VoiceTierSession.takeHandoff('users/u/chat_history/a'), isFalse);
  });
}
