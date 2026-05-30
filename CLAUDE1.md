StealthVox 프로젝트 가이드 (FlutterFlow)

 📂 파일 위치 및 위젯 리스트
 모든 화면(Pages): `lib/` 폴더 내 각 이름별 폴더
 커스텀 액션: `lib/custom_code/actions/`
 전역 상태: `lib/app_state.dart`

 🛠️ 커스텀 위젯 (`lib/custom_code/widgets/`)
현재 구현된 위젯 파일들 (새 작업 시 참고):

 ⚙️ AI 작업 규칙

- 새 기능 추가 시 반드시 주제별 주석 블록으로 구분할 것.
- 기존 블록 내부에 의미 없이 이어붙이지 말 것.
- 기능이 커지면 private helper method로 분리할 것.
- build() 내부 코드를 계속 비대하게 만들지 말 것.
- 상태 변수도 기능별 블록으로 정리할 것.
- dispose(), timer, stream 정리 코드는 lifecycle 블록으로 모을 것.

1. 복사붙여넣기: FlutterFlow 웹 에디터에 바로 적용할 수 있게 `import`와 클래스 구조 전체를 제공한다.
2. 디자인: `lib/flutter_flow/flutter_flow_theme.dart`의 테마 변수를 최우선으로 사용한다.
3. 작업 시작 전에 반드시 다음 순서로 진행해 주세요.
0. 네가 이해한 지시문 내용을 요약해서 맞는지 동의를 받는다.
1. git status 확인
2. 현재 브랜치 확인
3. 새 작업 브랜치 생성
4. 현재 상태를 백업 커밋
5. 관련 파일 전체 분석
6. 수정 대상 파일과 수정 계획 먼저 요약
7. 코드 수정
8. flutter pub get 실행
9. flutter analyze 실행
10. 오류 발생 시 원인 분석 후 수정 반복
11. 최종적으로 git diff 확인
12. 수정된 파일 목록, 핵심 변경사항, 남은 이슈 보고
13. main 브랜치에 머지해 줘.
14. 원격 저장소에 push 해줘

주의사항:
- 기존 정상 작동 기능을 깨지 말 것
- FlutterFlow generated code 구조를 함부로 대규모 변경하지 말 것
- 앱 실행/빌드 가능성을 최우선으로 할 것
- 불확실한 부분은 임의 삭제하지 말고 보고할 것

이 내용을 항상 기억하고 지시문에 포함해 줘.
=================================
지시문

routine_mode_step_expand.dart 에서 확장 문장이 매 턴 누적되지 않고 리셋되는 버그를 수정합니다.

[원인]
streamUserTranslation 의 CASE 2 프롬프트는 "(a) History의 가장 최근 확장 문장 + (b) 새 정보를 병합"
하도록 올바르게 설계돼 있다. 그러나 호출부가 넘기는 contextStr(History)에서
HOST 버블의 target이 "PART1(짧은말)\n\nPART2(확장문장)" 통째로 들어가고 AI 질문도 섞여,
GPT가 "가장 최근 확장 문장"을 정확히 집어내지 못해 매 턴 새로 짧게 만든다.

[해결]
contextStr 구성 시 HOST 버블에서 PART2(확장 문장)만 추출해 History에 명시한다.
특히 "가장 최근 확장 문장"을 별도 라벨로 강조해, CASE 2의 (a) 지시가 정확히 작동하게 한다.

[절대 건드리지 말 것]
- streamUserTranslation 의 CASE 1 / CASE 2 프롬프트 본문 (이미 올바름)
- 5턴 구조, 최종 합성, Polished 로직, Part1/Part2 화면/TTS 분리, Box 7 엔진
- 첫 질문(판단·추측형) 로직, FEELING FIRST / GO DEEPER / EMOTIONAL DEPTH

──────────────────────────────────────────────
[수정] contextStr 구성부 교체 — HOST 버블에서 PART2(확장 문장) 추출 + 최신 확장 문장 라벨링
──────────────────────────────────────────────

기존 (line 1740~1749 부근):

      var validMsgs = _localMessages.where((m) {
        if (m['role'] != 'HOST' && m['role'] != 'SYSTEM') return false;
        final target = (m['target'] ?? '').toString().trim();
        return target.isNotEmpty && target != '...';
      }).toList();
      if (validMsgs.length > 10)
        validMsgs = validMsgs.sublist(validMsgs.length - 10);
      String contextStr = validMsgs
          .map((m) => "${m['role'] == 'HOST' ? 'User' : 'AI'}: ${m['target']}")
          .join("\n");

교체:

      var validMsgs = _localMessages.where((m) {
        if (m['role'] != 'HOST' && m['role'] != 'SYSTEM') return false;
        final target = (m['target'] ?? '').toString().trim();
        return target.isNotEmpty && target != '...';
      }).toList();
      if (validMsgs.length > 10)
        validMsgs = validMsgs.sublist(validMsgs.length - 10);

      // 🌱 [EXPAND-FIX] HOST 버블의 target은 "PART1(짧은말)\n\nPART2(확장문장)" 구조.
      //   History에는 PART2(확장 문장)만 넣어 누적이 명확히 이어지게 한다.
      //   PART2가 없으면(첫 턴 등) PART1을 그대로 사용.
      String _extractExpanded(String target) {
        final t = target.trim();
        final idx = t.indexOf('\n\n');
        if (idx < 0) return t; // 분리 없음 → 통째로
        final part2 = t.substring(idx + 2).trim();
        return part2.isNotEmpty ? part2 : t.substring(0, idx).trim();
      }

      final List<String> lines = [];
      String latestExpanded = '';
      for (final m in validMsgs) {
        if (m['role'] == 'HOST') {
          final expanded = _extractExpanded((m['target'] ?? '').toString());
          lines.add("User: $expanded");
          latestExpanded = expanded; // 마지막 HOST 확장 문장 추적
        } else {
          lines.add("AI: ${m['target']}");
        }
      }

      String contextStr = lines.join("\n");
      // 🌱 가장 최근 확장 문장을 명시적으로 강조 → CASE 2 (a) 지시가 정확히 작동
      if (latestExpanded.isNotEmpty) {
        contextStr +=
            "\n\n[Most recent expanded sentence to grow from]: $latestExpanded";
      }

[검증]
1. dart analyze → 에러 0
2. grep -c "_extractExpanded" routine_mode_step_expand.dart → 최소 2 (정의 + 호출)
3. grep -c "Most recent expanded sentence to grow from" → 1
4. grep -c "latestExpanded" → 최소 3
5. 기존 CASE 2 프롬프트 보존: grep -c "the most recent expanded sentence from History" → 1
6. 런타임 테스트 (핵심):
   (a) 1턴: 짧은 확장
   (b) 2턴: 1턴 확장 문장 + 새 요소 한 절 추가 (더 길어짐)
   (c) 3턴: 2턴 확장 문장 유지 + 또 한 절 추가 (더 길어짐) — 이전 내용 사라지지 않음
   (d) 5턴까지 계속 누적 → Polished에서 긴 확장 문장을 다듬음
7. Box 7 클래스 diff 변경 0

⚠️ 주의: latestContextStr (line 2146 부근, "$contextStr\nUser: $userTargetText")는
   위에서 만든 contextStr을 그대로 받으므로 추가 수정 불필요.
   단, contextStr 끝에 [Most recent...] 라벨이 붙은 뒤 "\nUser: $userTargetText"가 이어지는
   순서가 자연스러운지 확인 (라벨 → 새 입력 순서는 GPT가 이해하는 데 문제 없음).