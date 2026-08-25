import 'package:flutter_test/flutter_test.dart';
import 'package:stealth_vox/custom_code/services/step_expansion_builder.dart';
import 'package:stealth_vox/custom_code/services/step_expansion_finalizer.dart';

/// 대화방 말풍선 → Builder 입력 transcript 변환.
///
/// Builder는 "생각이 실제로 자란 지점"을 찾는 일을 한다. 화면 부스러기가
///섞여 들어가면 그 판단이 통째로 흔들린다 — 확정 전 미리보기가 유저 턴으로
/// 세어지고, 빈 AI 말풍선이 대화 한 턴이 된다.
void main() {
  group('원어 대화만 추린다', () {
    test('HOST는 유저, SYSTEM은 AI로 간다', () {
      final turns = stepExpansionTranscriptFrom(<Map<String, dynamic>>[
        <String, dynamic>{'role': 'HOST', 'original': '회사 그만두고 싶어.'},
        <String, dynamic>{'role': 'SYSTEM', 'original': '일이 힘든 쪽이에요?'},
        <String, dynamic>{'role': 'HOST', 'original': '그건 아니야.'},
      ]);
      expect(turns.map((t) => t.isUser), <bool>[true, false, true]);
      expect(turns.first.text, '회사 그만두고 싶어.');
    });

    test('확정 전 미리보기(HOST_TEMP)는 대화가 아니다', () {
      final turns = stepExpansionTranscriptFrom(<Map<String, dynamic>>[
        <String, dynamic>{'role': 'HOST', 'original': '여행 가고 싶어.'},
        <String, dynamic>{'role': 'HOST_TEMP', 'target': '혼자 가고 싶은데'},
      ]);
      expect(turns, hasLength(1));
    });

    test('아직 글자가 안 온 말풍선과 자리표시자를 버린다', () {
      final turns = stepExpansionTranscriptFrom(<Map<String, dynamic>>[
        <String, dynamic>{'role': 'HOST', 'original': '여행 가고 싶어.'},
        <String, dynamic>{'role': 'SYSTEM', 'original': '', 'target': ''},
        <String, dynamic>{'role': 'SYSTEM', 'original': '', 'target': '...'},
        <String, dynamic>{'role': 'SYSTEM', 'original': '', 'target': '   '},
      ]);
      expect(turns, hasLength(1));
    });

    test('영어 칸(target)은 쳐다보지 않는다', () {
      // 방은 영어를 만들지 않는다. 옛 방 문서가 섞여 들어와도 원어만 읽는다.
      final turns = stepExpansionTranscriptFrom(<Map<String, dynamic>>[
        <String, dynamic>{
          'role': 'HOST',
          'original': '혼자 여행 가고 싶어.',
          'target': 'I want to travel alone.',
        },
      ]);
      expect(turns.single.text, '혼자 여행 가고 싶어.');
    });

    test('AI 대사는 target 칸에 산다 — 그걸 안 읽으면 AI 턴이 통째로 사라진다', () {
      // 실제 말풍선 모양이다. 유저는 original, AI는 target.
      final turns = stepExpansionTranscriptFrom(<Map<String, dynamic>>[
        <String, dynamic>{
          'role': 'HOST',
          'original': '회사 그만두고 싶어.',
          // 화면에 안 나오는 다리(그 턴까지 자란 문장). 유저 줄에서는 무시된다.
          'target': '회사를 그만두고 싶다.',
        },
        <String, dynamic>{
          'role': 'SYSTEM',
          'original': '',
          'target': '어느 쪽으로 가볼까요?',
        },
      ]);
      expect(turns.map((t) => t.isUser), <bool>[true, false]);
      expect(turns.first.text, '회사 그만두고 싶어.');
      expect(turns.last.text, '어느 쪽으로 가볼까요?');
    });

    test('AI 줄에 original이 채워진 옛 문서는 그쪽을 믿는다', () {
      final turns = stepExpansionTranscriptFrom(<Map<String, dynamic>>[
        <String, dynamic>{
          'role': 'SYSTEM',
          'original': '무슨 얘기 해볼까요?',
          'target': '엉뚱한 값',
        },
      ]);
      expect(turns.single.text, '무슨 얘기 해볼까요?');
    });

    test('유저 턴이 하나도 없으면 빈 목록이다', () {
      final turns = stepExpansionTranscriptFrom(<Map<String, dynamic>>[
        <String, dynamic>{'role': 'SYSTEM', 'original': '무슨 얘기 해볼까요?'},
      ]);
      expect(turns.any((t) => t.isUser), isFalse);
    });
  });

  group('상태 값', () {
    test('세 가지뿐이고 서로 다르다', () {
      final all = <String>{
        StepExpansionStatus.building,
        StepExpansionStatus.ok,
        StepExpansionStatus.failed,
      };
      expect(all, hasLength(3));
    });

    test('구 세션에는 이 필드가 없다는 전제를 지킨다', () {
      // 빈 문자열은 어떤 상태값과도 같지 않아야 한다 — 히스토리가 "필드 없음"
      // 하나로 구/신 방을 가른다.
      expect(all_(), isNot(contains('')));
    });
  });
}

Set<String> all_() => <String>{
      StepExpansionStatus.building,
      StepExpansionStatus.ok,
      StepExpansionStatus.failed,
    };
