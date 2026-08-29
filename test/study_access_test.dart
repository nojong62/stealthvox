import 'package:flutter_test/flutter_test.dart';
import 'package:stealth_vox/custom_code/services/study_access.dart';

/// 회원 여부와 Duo 게스트 여부는 **다른 축이다.** 넷 다 성립한다.
///   A. 로그인 회원 + Duo 게스트
///   B. 익명      + Duo 게스트
///   C. 로그인 회원 + 일반
///   D. 익명      + 일반
StudyAccess a() => resolveStudyAccess(
    isTrial: false, isDuoGuest: true, isSignedInMember: true);
StudyAccess b() => resolveStudyAccess(
    isTrial: false, isDuoGuest: true, isSignedInMember: false);
StudyAccess c() => resolveStudyAccess(
    isTrial: false, isDuoGuest: false, isSignedInMember: true);
StudyAccess d() => resolveStudyAccess(
    isTrial: false, isDuoGuest: false, isSignedInMember: false);

void main() {
  group('보기는 누구에게도 막지 않는다', () {
    test('네 상태 모두 자기 대화를 볼 수 있다', () {
      for (final access in <StudyAccess>[a(), b(), c(), d()]) {
        expect(access.canReadConversation, isTrue);
      }
    });

    test('isDuoGuest만으로 내용을 막지 않는다 — 비용 기능만 잠긴다', () {
      expect(a().canReadConversation, isTrue);
      expect(a().canUsePaidStudy, isFalse);
      expect(a().reason, StudyBlockReason.duoGuest);
    });
  });

  group('Duo 게스트 — 회원이든 아니든 통화 중에는 비용을 만들지 않는다', () {
    test('로그인 회원 게스트도 잠긴다 (케이스 1·7)', () {
      expect(a().canUsePaidStudy, isFalse);
    });

    test('익명 게스트도 잠긴다 (케이스 2)', () {
      expect(b().canUsePaidStudy, isFalse);
      expect(b().reason, StudyBlockReason.duoGuest);
    });

    test('두 게스트 모두 차감 대상이 아니다', () {
      expect(isDuoBillingSuppressed(isTrial: false, isDuoGuest: true), isTrue);
    });
  });

  group('통화가 끝난 뒤', () {
    test('로그인 회원의 일반 History는 열린다 (케이스 1 후반·8)', () {
      expect(c().canUsePaidStudy, isTrue);
      expect(c().reason, StudyBlockReason.none);
    });

    test('일반 회원 구간은 차감이 돈다', () {
      expect(isDuoBillingSuppressed(isTrial: false, isDuoGuest: false), isFalse);
    });
  });

  group('비회원', () {
    test('Duo가 아니어도 비용 기능은 못 쓴다 (케이스 2 후반)', () {
      expect(d().canUsePaidStudy, isFalse);
      expect(d().reason, StudyBlockReason.notSignedIn);
    });

    test('잠긴 이유마다 안내 문구가 있다 — 눌러도 조용한 버튼을 만들지 않는다', () {
      expect(b().gateLabel, isNotEmpty);
      expect(d().gateLabel, isNotEmpty);
      expect(c().gateLabel, isEmpty);
    });
  });

  group('맛보기는 의도된 무료', () {
    test('익명이어도 열린다 — 막으면 맛보기가 성립하지 않는다', () {
      final trial = resolveStudyAccess(
          isTrial: true, isDuoGuest: false, isSignedInMember: false);
      expect(trial.canUsePaidStudy, isTrue);
    });

    test('맛보기 Duo 게스트도 열린다 — 맛보기가 먼저다', () {
      final trial = resolveStudyAccess(
          isTrial: true, isDuoGuest: true, isSignedInMember: false);
      expect(trial.canUsePaidStudy, isTrue);
    });
  });

  group('로그인 후 복원된 History (케이스 7)', () {
    test('게스트 딱지가 떨어지면 그 방은 일반 회원 방이다 — 무료 구간이 남지 않는다', () {
      // 로그인 직후 isGuestSession을 내리는 것이 곧 이 전환이다.
      final duringCall = resolveStudyAccess(
          isTrial: false, isDuoGuest: true, isSignedInMember: false);
      final afterLogin = resolveStudyAccess(
          isTrial: false, isDuoGuest: false, isSignedInMember: true);
      expect(duringCall.canUsePaidStudy, isFalse);
      expect(afterLogin.canUsePaidStudy, isTrue);
      expect(isDuoBillingSuppressed(isTrial: false, isDuoGuest: true), isTrue);
      expect(isDuoBillingSuppressed(isTrial: false, isDuoGuest: false), isFalse);
    });

    test('딱지가 남으면 회원인데도 잠긴다 — 그래서 복구보다 먼저 내린다', () {
      final stale = resolveStudyAccess(
          isTrial: false, isDuoGuest: true, isSignedInMember: true);
      expect(stale.canUsePaidStudy, isFalse);
      expect(stale.reason, StudyBlockReason.duoGuest);
    });
  });

  group('🔒 불변식 — 버튼과 과금이 어긋나지 않는다', () {
    test('맛보기가 아닌데 버튼만 열린 조합은 없다', () {
      for (final isTrial in <bool>[true, false]) {
        for (final isDuoGuest in <bool>[true, false]) {
          for (final isMember in <bool>[true, false]) {
            final access = resolveStudyAccess(
              isTrial: isTrial,
              isDuoGuest: isDuoGuest,
              isSignedInMember: isMember,
            );
            final suppressed = isDuoBillingSuppressed(
                isTrial: isTrial, isDuoGuest: isDuoGuest);
            if (access.canUsePaidStudy && !isTrial) {
              // 버튼이 열렸다면 차감도 돈다. 아니면 그 구간이 무료 API가 된다.
              expect(suppressed, isFalse,
                  reason: 'trial=$isTrial guest=$isDuoGuest member=$isMember');
            }
          }
        }
      }
    });

    test('차감이 막힌 구간에서 열리는 것은 맛보기뿐이다', () {
      expect(
        resolveStudyAccess(
                isTrial: false, isDuoGuest: true, isSignedInMember: true)
            .canUsePaidStudy,
        isFalse,
      );
      expect(
        resolveStudyAccess(
                isTrial: false, isDuoGuest: true, isSignedInMember: false)
            .canUsePaidStudy,
        isFalse,
      );
    });
  });
}
