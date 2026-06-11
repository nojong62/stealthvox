StealthVox 프로젝트 가이드 (FlutterFlow)

 📂 파일 위치 및 위젯 리스트
 모든 화면(Pages): `lib/` 폴더 내 각 이름별 폴더
 커스텀 액션: `lib/custom_code/actions/`
 전역 상태: `lib/app_state.dart`

 🛠️ 커스텀 위젯 (`lib/custom_code/widgets/`)
현재 구현된 위젯 파일들 (새 작업 시 참고):
"임시/ 폴더에는 적용하지 말 것"

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

# 리팩토링 지시문 2차 — C-1 (clean context 통합) + C-2 (isFiller 통합)

## 목적
- **C-1:** `_localMessages`에서 clean context 문자열을 빌드하는 패턴이 4곳에서 거의 동일하게 반복 → `_buildCleanContext()` 헬퍼 1개로 통합 (약 -80줄)
- **C-2:** 시드 수집에서 `fillerPatterns` + `complaintPatterns` + `isFiller` 함수가 2벌 중복 → `_isSeedFiller()` static 메서드 1개로 통합 (약 -40줄)
- **총 예상 감소:** 약 100~120줄

## 작업 전 필수
```bash
cd F:\flutter_project\stealth_vox
git add -A && git commit -m "save-point: before C1+C2 refactoring (cleanContext + isFiller)"
```

**대상 파일 (1개):**
- `lib/custom_code/widgets/routine_mode_step_expand.dart`

**절대 규칙:**
- Box 7 클래스 내부 수정 금지.
- 각 교체 지점에서 **교체 전후 동작이 완전히 동일**해야 한다 — 로직 변경 없는 순수 리팩토링.
- 줄번호는 참고용. 반드시 grep anchor로 위치 확정.
- **아래(줄번호 큰 곳)→위 순서로 편집** (줄번호 드리프트 방지).

---

# PHASE 0: 헬퍼 함수 2개 추가

## [P0-1] `_isSeedFiller` static 메서드 추가

`_isQuestionDissatisfactionRaw` 함수 바로 아래(약 151줄)에 삽입한다.

```bash
F=lib/custom_code/widgets/routine_mode_step_expand.dart
# 삽입 위치 찾기: _isQuestionDissatisfactionRaw 닫는 } 바로 다음의 구분선
TARGET=$(grep -n "^  // ──.*──$" $F | awk -F: 'prev{print prev; exit} {prev=$1}' | head -1)
# 또는 수동으로: "_isQuestionDissatisfactionRaw" 함수 끝 직후 "// ──────" 줄 바로 뒤
```

**찾기 (anchor — str_replace):**
```dart
    return false;
  }
  // ──────────────────────────────────────────────────────────────────

  Widget _buildIdleBanner() => const SizedBox.shrink();
```

**교체:**
```dart
    return false;
  }

  /// 시드 스니펫 필터: 필러/연결어/불만 발화 제외
  /// — _fetchFreeTalkUserSnippets, _fetchRoleplayUserSnippets 공통
  static bool _isSeedFiller(String s) {
    final t = s.replaceAll(RegExp(r'[\s\.,!?~…]'), '').toLowerCase();
    if (t.length < 6) return true;
    const fillerPatterns = [
      '네', '응', '어', '그래', '맞아', '맞아요', '좋아', '좋아요',
      '글쎄', 'ok', 'okay', '오케이', '음', '아', '오', '그래요',
      '그러니까', '그렇구나', '알겠어', '알겠습니다', '그럴까',
      '고마워', '고맙습니다', 'yes', 'yeah', 'sure', 'right',
      'thank you', 'thanks',
    ];
    if (fillerPatterns.contains(t)) return true;
    const complaintPatterns = [
      '질문', '물어봐', '물어본', '다시말', '이상한', '이상해', '이상하',
      '별로', '뭐야', '바꿔', '그런거말고', '딴거', '다른거', '다른걸',
      '마음에안', '맘에안', 'question', 'askme', 'weird',
    ];
    for (final p in complaintPatterns) {
      if (t.contains(p)) return true;
    }
    return false;
  }

  // ──────────────────────────────────────────────────────────────────

  Widget _buildIdleBanner() => const SizedBox.shrink();
```

## [P0-2] `_buildCleanContext` 헬퍼 메서드 추가

`_processRelayPipeline` 정의 바로 위에 삽입한다.

**찾기 (anchor — str_replace):**
```dart
  Future<void> _processRelayPipeline(String finalTranscript,
      {bool isCorrectionRetry = false}) async {
```

**교체:**
```dart
  /// Clean context 빌드 헬퍼 — FAST/DISSATISFIED/MISHEARD/정상 파이프라인 공통 로직
  /// [removeLastSystem] 마지막 SYSTEM(거절된 질문) 제거 여부
  /// [captureRejected] 제거할 SYSTEM의 target을 rejectedQuestion으로 반환할지
  /// [maxMessages] >0이면 최근 N건만 사용 (0=제한 없음)
  Map<String, String> _buildCleanContext({
    bool removeLastSystem = false,
    bool captureRejected = false,
    int maxMessages = 0,
  }) {
    var msgs = _localMessages.where((m) {
      if (m['role'] != 'HOST' && m['role'] != 'SYSTEM') return false;
      final target = (m['target'] ?? '').toString().trim();
      return target.isNotEmpty && target != '...';
    }).toList();

    if (maxMessages > 0 && msgs.length > maxMessages) {
      msgs = msgs.sublist(msgs.length - maxMessages);
    }

    String rejected = '';
    if (removeLastSystem) {
      final sysIdx = msgs.lastIndexWhere((m) => m['role'] == 'SYSTEM');
      if (sysIdx != -1) {
        if (captureRejected) {
          rejected = (msgs[sysIdx]['target'] ?? '').toString().trim();
        }
        msgs.removeAt(sysIdx);
      }
    }

    final List<String> lines = [];
    String latestExp = '';
    for (final m in msgs) {
      final t = (m['target'] ?? '').toString().trim();
      if (m['role'] == 'HOST') {
        final idx = t.indexOf('\n\n');
        final exp = idx < 0
            ? t
            : (t.substring(idx + 2).trim().isNotEmpty
                ? t.substring(idx + 2).trim()
                : t.substring(0, idx).trim());
        lines.add("User: $exp");
        latestExp = exp;
      } else {
        lines.add("AI: $t");
      }
    }

    String ctx = lines.join("\n");
    if (latestExp.isNotEmpty) {
      ctx += "\n\n[Most recent expanded sentence to grow from]: $latestExp";
    }

    return {
      'contextStr': ctx,
      'latestExpanded': latestExp,
      'rejectedQuestion': rejected,
    };
  }

  Future<void> _processRelayPipeline(String finalTranscript,
      {bool isCorrectionRetry = false}) async {
```

---

# PHASE 1 (C-1): clean context 빌드 4곳 교체 (아래→위)

각 교체는 **시작줄 grep → 끝줄 grep → sed 범위삭제 → sed 삽입** 순서이다.
교체 전후 동작이 동일한지 확인하기 위해, 교체 후 주변 코드와의 연결점을 명시한다.

## [C1-1] MISHEARD context 빌드 (약 2450~2482줄)

**시작 anchor (이 줄 포함 삭제):**
```
        var cleanMsgs = _localMessages.where((m) {
```

**끝 anchor (이 줄 포함 삭제):**
```
          cleanContextStr +=
              "\n\n[Most recent expanded sentence to grow from]: $cleanLatestExpanded";
        }
```

**교체 코드 (삭제 후 시작 위치에 삽입):**
```dart
        final _mishResult = _buildCleanContext(
            removeLastSystem: true, maxMessages: 10);
        final String cleanContextStr = _mishResult['contextStr']!;
```

**연결점 확인:** 바로 다음 줄이 `await _handleRetryQuestion(cleanContextStr, targetLangName,` 이어야 한다.

**실행 방법:**
```bash
F=lib/custom_code/widgets/routine_mode_step_expand.dart
# 1. 시작줄 찾기 (MISHEARD 블록 내부, "var cleanMsgs" — 파일에서 유일한 "var cleanMsgs")
S=$(grep -n "var cleanMsgs = _localMessages.where" $F | head -1 | cut -d: -f1)
# 2. 끝줄 찾기 (시작줄 이후 첫 "cleanLatestExpanded" + 닫는 })
E=$(awk "NR>=$S && /cleanLatestExpanded/{found=NR} found && /^        \}/{print NR; exit}" $F)
echo "삭제 범위: $S ~ $E"
# 3. 삭제할 내용 확인
sed -n "${S},${E}p" $F
# 4. 삭제 + 삽입
sed -i "${S},${E}c\\
        final _mishResult = _buildCleanContext(\\
            removeLastSystem: true, maxMessages: 10);\\
        final String cleanContextStr = _mishResult['contextStr']!;" $F
```

## [C1-2] GPT DISSATISFIED context 빌드 (약 2330~2382줄)

**시작 anchor (이 줄 포함 삭제):**
```
        var dissCleanMsgs = _localMessages.where((m) {
```

**끝 anchor (이 줄 포함 삭제):**
```
          dissCleanCtx +=
              "\n\n[Most recent expanded sentence to grow from]: $dissLatestExpanded";
        }
```

**교체 코드:**
```dart
        final _dissResult = _buildCleanContext(
            removeLastSystem: true, captureRejected: true);
        final String dissCleanCtx = _dissResult['contextStr']!;
        final String dissRejected = _dissResult['rejectedQuestion']!;
```

**연결점 확인:** 바로 다음 줄이 `if (mounted) {` → `setState(() {` → `_localMessages.removeWhere` 이어야 한다.

**실행 방법:**
```bash
S=$(grep -n "var dissCleanMsgs = _localMessages.where" $F | head -1 | cut -d: -f1)
E=$(awk "NR>=$S && /dissLatestExpanded/{found=NR} found && /^        \}/{print NR; exit}" $F)
echo "삭제 범위: $S ~ $E"
sed -n "${S},${E}p" $F
sed -i "${S},${E}c\\
        final _dissResult = _buildCleanContext(\\
            removeLastSystem: true, captureRejected: true);\\
        final String dissCleanCtx = _dissResult['contextStr']!;\\
        final String dissRejected = _dissResult['rejectedQuestion']!;" $F
```

## [C1-3] 정상 파이프라인 context 빌드 (약 2097~2134줄)

**시작 anchor (이 줄 포함 삭제):**
```
      var validMsgs = _localMessages.where((m) {
```

**끝 anchor (이 줄 포함 삭제):**
```
        contextStr +=
            "\n\n[Most recent expanded sentence to grow from]: $latestExpanded";
      }
```

**교체 코드:**
```dart
      final _pipeResult = _buildCleanContext(maxMessages: 10);
      String contextStr = _pipeResult['contextStr']!;
```

**연결점 확인:** 바로 다음 줄이 빈 줄 → `String userTargetText = "";` 이어야 한다.

**실행 방법:**
```bash
S=$(grep -n "var validMsgs = _localMessages.where" $F | head -1 | cut -d: -f1)
E=$(awk "NR>=$S && /latestExpanded/{found=NR} found && /^      \}/{print NR; exit}" $F)
echo "삭제 범위: $S ~ $E"
sed -n "${S},${E}p" $F
sed -i "${S},${E}c\\
      final _pipeResult = _buildCleanContext(maxMessages: 10);\\
      String contextStr = _pipeResult['contextStr']!;" $F
```

## [C1-4] FAST 레인 context 빌드 (약 2048~2087줄)

**시작 anchor (이 줄 포함 삭제):**
```
      // Clean context: 거절된 질문(마지막 SYSTEM) 제거
      var _fastCleanMsgs = _localMessages.where((m) {
```

**끝 anchor (이 줄 포함 삭제 — `_fclCtx +=` 블록의 닫는 `}`):**
```
        _fclCtx +=
            "\n\n[Most recent expanded sentence to grow from]: $_fclLatestExp";
      }
```

**교체 코드:**
```dart
      // Clean context: 헬퍼로 빌드
      final _fclResult = _buildCleanContext(
          removeLastSystem: true, captureRejected: true);
      final String _fclCtx = _fclResult['contextStr']!;
      final String _fclRejected = _fclResult['rejectedQuestion']!;
```

**연결점 확인:** 바로 다음 줄이 `final String _fclLang = FFAppState()...` 이어야 한다.

**실행 방법:**
```bash
S=$(grep -n "// Clean context: 거절된 질문(마지막 SYSTEM) 제거" $F | head -1 | cut -d: -f1)
E=$(awk "NR>=$S && /_fclLatestExp/{found=NR} found && /^      \}/{print NR; exit}" $F)
echo "삭제 범위: $S ~ $E"
sed -n "${S},${E}p" $F
sed -i "${S},${E}c\\
      // Clean context: 헬퍼로 빌드\\
      final _fclResult = _buildCleanContext(\\
          removeLastSystem: true, captureRejected: true);\\
      final String _fclCtx = _fclResult['contextStr']!;\\
      final String _fclRejected = _fclResult['rejectedQuestion']!;" $F
```

---

# PHASE 2 (C-2): isFiller 2곳 교체 (아래→위)

## [C2-1] 롤플레이 시드 isFiller (약 587~618줄)

**시작 anchor (이 줄 포함 삭제):**
```
      const fillerPatterns = [
        '네', '응', '음', '그래', '맞아', '맞아요', '좋아', '좋아요',
```

**끝 anchor (이 줄 포함 삭제):**
```
        return false;
      }
```

**교체 코드 (없음 — 삭제만):** 이 블록을 삭제하고, 아래쪽 사용처의
`!isFiller(s)` 를 `!_isSeedFiller(s)` 로 변경.

**실행 방법:**
```bash
# 롤플레이 시드 함수 내의 fillerPatterns (두 번째 발생)
S=$(grep -n "      const fillerPatterns = \[" $F | tail -1 | cut -d: -f1)
E=$(awk "NR>=$S && /bool isFiller/{start=NR} start && /return false;/{found=NR} found && /^      \}/{print NR; exit}" $F)
echo "삭제 범위: $S ~ $E"
sed -n "${S},${E}p" $F
# 삭제
sed -i "${S},${E}d" $F
# isFiller → _isSeedFiller 교체 (롤플레이 함수 내)
# 이 시점에서 "!isFiller(s)" 가 1곳만 남아있어야 함 (프리톡 것)
# → 먼저 프리톡도 교체할 것이므로, 아래 C2-2 후에 일괄 치환
```

## [C2-2] 프리톡 시드 isFiller (약 408~466줄)

**시작 anchor (이 줄 포함 삭제):**
```
      // 필러 판정
      const fillerPatterns = [
        '네',
```

**끝 anchor (이 줄 포함 삭제):**
```
        return false;
      }
```

**실행 방법:**
```bash
# 프리톡 시드 함수 내의 fillerPatterns (첫 번째 발생)
S=$(grep -n "      // 필러 판정" $F | head -1 | cut -d: -f1)
E=$(awk "NR>=$S && /bool isFiller/{start=NR} start && /return false;/{found=NR} found && /^      \}/{print NR; exit}" $F)
echo "삭제 범위: $S ~ $E"
sed -n "${S},${E}p" $F
sed -i "${S},${E}d" $F
```

## [C2-3] isFiller 호출부 일괄 치환

두 곳의 정의를 삭제한 후, 사용부 `!isFiller(s)` → `!_isSeedFiller(s)` 로 변경.

```bash
# 변경 전 카운트 확인
grep -c "!isFiller(s)" $F  # 기대값: 2 (FT 1 + RP 1)

# 일괄 치환
sed -i 's/!isFiller(s)/!_isSeedFiller(s)/g' $F

# 변경 후 확인
grep -c "!_isSeedFiller(s)" $F  # 기대값: 2
grep -c "!isFiller(s)" $F       # 기대값: 0
```

---

# 검증

```bash
F=lib/custom_code/widgets/routine_mode_step_expand.dart

echo "=== C-1 검증 ==="
grep -c "_buildCleanContext" $F         # 기대값: 5 (정의1 + 호출4)
grep -c "var validMsgs" $F             # 기대값: 0 (정상 파이프라인 인라인 제거됨)
grep -c "var dissCleanMsgs" $F         # 기대값: 0
grep -c "var _fastCleanMsgs" $F        # 기대값: 0
grep -c "var cleanMsgs" $F             # 기대값: 0
grep -c "extractExpanded" $F           # 기대값: 0 (로컬 함수 제거됨)

echo "=== C-2 검증 ==="
grep -c "_isSeedFiller" $F             # 기대값: 3 (정의1 + 호출2)
grep -c "bool isFiller" $F             # 기대값: 0 (인라인 정의 제거됨)
grep -c "fillerPatterns" $F            # 기대값: 1 (_isSeedFiller 내부만)
grep -c "complaintPatterns" $F         # 기대값: 1 (_isSeedFiller 내부만)

echo "=== 줄수 감소 ==="
wc -l $F
# 기대값: 원본 대비 약 100~120줄 감소

flutter analyze $F
# 에러 0건이어야 한다
```

---

# 실기기 회귀 테스트 (필수)

이 리팩토링은 로직 변경이 아닌 순수 구조 정리이므로, **기존 동작이 전부 동일**해야 한다.

1. **[정상 5턴 완주]** 세션 시작 → 5턴 확장 → polish 저장까지 정상 동작
2. **[FAST 불만]** "질문이 뭐 이래" → 즉시 다른 질문 생성 (직전 질문과 다른 내용)
3. **[GPT 불만]** "별로네" → 직전 삭제 + 다른 질문 생성
4. **[MISHEARD]** "잘못 들었어" → 이전 턴 삭제 + 재질문
5. **[시드 질문]** 프리톡+롤플레이 기록이 있는 계정 → 시드 질문 정상 생성 (필러/불만 발화 제외 확인)
6. **[시드 폴백]** 프리톡 기록 없는 계정 → 고정 안내 정상 출력

## 롤백
```bash
git restore lib/custom_code/widgets/routine_mode_step_expand.dart
# 또는 커밋했다면
git revert <hash>
```