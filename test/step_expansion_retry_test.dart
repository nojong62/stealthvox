import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:stealth_vox/custom_code/services/step_expansion_builder.dart';
import 'package:stealth_vox/custom_code/services/step_expansion_finalizer.dart';

/// 사다리를 다시 만들 수 있는 상태인지 가리는 규칙과, 저장된 사다리를 다시
/// 읽는 길을 고정한다.
///
/// 여기서 막으려는 사고는 둘이다.
/// 1. **`building`으로 영원히 굳는 문서.** Builder가 도는 중에 앱이 죽으면
///    아무도 다시 걸어 주지 않아 그 방은 P2/P3가 영영 안 열린다.
/// 2. **구/신 데이터가 한 화면에서 섞이는 것.** 새 방에 사다리가 없다고
///    옛 값으로 때우면, 유저는 자기가 어느 사다리를 보는지 알 수 없다.
void main() {
  final now = DateTime(2026, 8, 24, 12, 0);

  group('재시도 가능 판정', () {
    test('실패는 언제나 다시 걸 수 있다', () {
      expect(
        canRetryStepExpansion(
          status: StepExpansionStatus.failed,
          startedAt: now,
          now: now,
        ),
        isTrue,
      );
    });

    test('갓 시작한 building은 건드리지 않는다', () {
      expect(
        canRetryStepExpansion(
          status: StepExpansionStatus.building,
          startedAt: now.subtract(const Duration(seconds: 20)),
          now: now,
        ),
        isFalse,
      );
    });

    test('오래 묵은 building은 죽은 것으로 본다', () {
      expect(
        canRetryStepExpansion(
          status: StepExpansionStatus.building,
          startedAt: now.subtract(kStepExpansionStaleAfter),
          now: now,
        ),
        isTrue,
      );
    });

    test('앱 재실행 뒤 며칠 지난 building도 재시도 대상이다', () {
      expect(
        canRetryStepExpansion(
          status: StepExpansionStatus.building,
          startedAt: now.subtract(const Duration(days: 3)),
          now: now,
        ),
        isTrue,
      );
    });

    test('시작 시각을 모르면 열어 준다 — 되돌릴 근거가 없다', () {
      expect(
        canRetryStepExpansion(
          status: StepExpansionStatus.building,
          startedAt: null,
          now: now,
        ),
        isTrue,
      );
    });

    test('정상 완료된 방은 재시도 대상이 아니다', () {
      expect(
        canRetryStepExpansion(
          status: StepExpansionStatus.ok,
          startedAt: null,
          now: now,
        ),
        isFalse,
      );
    });

    test('구 세션(상태 필드 없음)은 이 판정 자체를 타지 않는다', () {
      expect(
        canRetryStepExpansion(status: '', startedAt: null, now: now),
        isFalse,
      );
    });
  });

  group('저장된 사다리 다시 읽기', () {
    final stored = jsonDecode(jsonEncode(<Map<String, dynamic>>[
      <String, dynamic>{
        'step': 1,
        'text': 'I need a break.',
        'added_meaning': '쉬고 싶다',
        'primary_morph': '',
        'chunks': <Map<String, dynamic>>[],
      },
      <String, dynamic>{
        'step': 2,
        'text': 'I need a break because work has been draining.',
        'added_meaning': '일이 지친다',
        'primary_morph': 'because work has been draining.',
        'chunks': <Map<String, dynamic>>[
          <String, dynamic>{
            'text': 'I need a break',
            'type': 'kept',
            'from': 'I need a break.',
          },
          <String, dynamic>{
            'text': 'because work has been draining.',
            'type': 'new',
          },
        ],
      },
    ])) as List<dynamic>;

    test('직전 칸을 비교 기준으로 들고 온다', () {
      final steps = parseStoredExpansions(stored);
      expect(steps, hasLength(2));
      expect(steps.first.previousText, isEmpty);
      expect(steps.last.previousText, 'I need a break.');
    });

    test('강조 좌표가 문장 안에 있을 때만 살아남는다', () {
      final steps = parseStoredExpansions(stored);
      expect(steps.last.primaryMorph, 'because work has been draining.');

      final broken = jsonDecode(jsonEncode(<Map<String, dynamic>>[
        <String, dynamic>{'text': 'I need a break.'},
        <String, dynamic>{
          'text': 'I need a break because work has been draining.',
          'primary_morph': 'totally exhausted',
        },
      ])) as List<dynamic>;
      expect(parseStoredExpansions(broken).last.primaryMorph, isEmpty);
    });

    test('마지막 칸이 최종문장이다', () {
      final steps = parseStoredExpansions(stored);
      expect(steps.last.text,
          'I need a break because work has been draining.');
    });

    test('배열이 아니거나 비면 빈 사다리다 — 옛 값으로 때우지 않는다', () {
      expect(parseStoredExpansions(null), isEmpty);
      expect(parseStoredExpansions('expanded sentence'), isEmpty);
      expect(parseStoredExpansions(<dynamic>[]), isEmpty);
    });
  });

  group('재시도의 원본은 그때 나눈 대화다', () {
    test('messages 문서에서 원어만 추린다', () {
      final turns =
          stepExpansionTranscriptFromMessages(<Map<String, dynamic>>[
        <String, dynamic>{'role': 'HOST', 'original_text': '회사 그만두고 싶어.'},
        <String, dynamic>{'role': 'SYSTEM', 'original_text': '일이 힘든 쪽이에요?'},
        <String, dynamic>{'role': 'HOST', 'original_text': '  '},
        <String, dynamic>{'role': 'SYSTEM', 'original_text': '...'},
      ]);
      expect(turns, hasLength(2));
      expect(turns.first.isUser, isTrue);
      expect(turns.last.text, '일이 힘든 쪽이에요?');
    });

    test('구경로 영어 필드는 쳐다보지 않는다', () {
      // 다시 만들 때의 원본은 대화지, 방이 계산해 뒀던 무엇이 아니다.
      final turns =
          stepExpansionTranscriptFromMessages(<Map<String, dynamic>>[
        <String, dynamic>{
          'role': 'HOST',
          'original_text': '혼자 여행 가고 싶어.',
          'translated_text': 'I want to travel alone.',
          'expanded_sentence': 'I want to travel alone because I need quiet.',
        },
      ]);
      expect(turns.single.text, '혼자 여행 가고 싶어.');
    });
  });
}
