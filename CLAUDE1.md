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

## Claude Code 지시문 — StepExpand 2턴+ 유저 버블 Part1 화면 숨김

**대상 파일:** `routine_mode_step_expand.dart`

**의도(목표):**
스텝 익스팬드 라이브 화면에서, 유저의 **2턴째 이후** 버블은 **확장문장(Part2)만** 표시한다. 짧은 1차 대답(Part1)과 Part1 한국어는 화면에서 숨긴다. (1턴째 첫 대답은 지금처럼 그대로 표시.) 저장·TTS 로직은 일절 변경하지 않는다. Part1 글자는 `translated_text`에 그대로 저장되어 히스토리에서 보이고, Part1 음성은 히스토리 첫 재생 시 API가 생성하므로 별도 작업 불필요.

---

### 수정 1 — HOST 버블 생성 시 turnId 태깅 (약 1616행)

**대상 줄(1줄):**
- 1616행: `_localMessages.add({'role': 'HOST', 'target': '', 'original': ''});`

**교체 후 (전체):**
```dart
          _localMessages.add({'role': 'HOST', 'target': '', 'original': '', 'turnId': currentTurnId});
```
> 이유: 스트리밍 중 Part1이 먼저 흘러들어올 때(아직 `\n\n` 미도착) 버블이 한순간 Part1을 노출하는 깜빡임을 막기 위해, 버블 생성 시점에 턴 번호를 박아둔다. `currentTurnId`는 1579행에서 정의되어 이 위치에서 사용 가능.

---

### 수정 2 — `_buildTextBlock` 렌더링 교체 (약 2893~2972행)

**삭제 대상 범위:**
- 시작 2893행: `  Widget _buildTextBlock(Map<String, dynamic> msg) {`
- 끝 2972행: `  }` (이 메서드의 닫는 중괄호)

**교체될 코드 (전체):**
```dart
  Widget _buildTextBlock(Map<String, dynamic> msg) {
    final role = (msg['role'] ?? '').toString();
    bool isHost = role == 'HOST' || role == 'HOST_TEMP';
    final targetRaw = (msg['target'] ?? '').toString();
    final originalRaw = (msg['original'] ?? '').toString();

    // Show '...' when AI is generating, user bubble is pending recognition,
    // or HOST bubble was just created with empty target (before streaming starts)
    final String displayTarget = ((role == 'SYSTEM' && targetRaw.isEmpty) ||
            (role == 'HOST_TEMP' && targetRaw == '...') ||
            (role == 'HOST' && targetRaw.isEmpty))
        ? '...'
        : targetRaw;

    final targetParts = targetRaw.split(RegExp(r'\n\s*\n'));

    // 🌱 [PART1-HIDE] 2턴+ 유저 버블은 확장문장(Part2)만 화면에 표시한다.
    //   - Part1(짧은 대답)과 Part1 한국어는 화면에서 숨긴다 (히스토리 저장값은 그대로).
    //   - 스트리밍 중 Part1만 들어온 구간(아직 \n\n 미도착)은 '...' placeholder만 노출.
    //   - turnId 우선 판단(스트리밍 깜빡임 방지), 없으면 파트 수로 후방호환.
    final int turnId = (msg['turnId'] is int) ? msg['turnId'] as int : 0;
    final bool isExpandTurn =
        role == 'HOST' && (turnId >= 2 || targetParts.length >= 2);

    final String effectiveOriginal = (role == 'HOST_TEMP') ? '' : originalRaw;

    return Align(
      alignment: isHost ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 8),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
            color: isHost
                ? const Color(0xFF2C2C2E)
                : const Color(0xFF9333EA).withOpacity(0.15),
            borderRadius: BorderRadius.circular(16)),
        constraints:
            BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.85),
        child: Column(
          crossAxisAlignment:
              isHost ? CrossAxisAlignment.end : CrossAxisAlignment.start,
          children: [
            if (isExpandTurn) ...[
              // 🌱 [PART1-HIDE] Part2(확장문장)만 표시. Part2 미도착 시 '...' placeholder.
              //   한국어는 표시하지 않는다 (Part2에는 원래 한국어가 없음).
              Text(
                  targetParts.length >= 2
                      ? targetParts.sublist(1).join('\n\n').trim()
                      : '...',
                  textAlign: isHost ? TextAlign.right : TextAlign.left,
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: 16 * _fontScale,
                      fontWeight: FontWeight.bold)),
            ] else ...[
              Text(displayTarget,
                  textAlign: isHost ? TextAlign.right : TextAlign.left,
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: 16 * _fontScale,
                      fontWeight: FontWeight.bold)),
              if (_showOriginal && effectiveOriginal.isNotEmpty) ...[
                const SizedBox(height: 6),
                Text(effectiveOriginal,
                    textAlign: isHost ? TextAlign.right : TextAlign.left,
                    style: TextStyle(
                        color: Colors.grey, fontSize: 10 * _fontScale)),
              ],
            ],
          ],
        ),
      ),
    );
  }
```

---

### 절대 건드리지 말 것 (CRITICAL)
- **Box 7** (`TtsQueueManager`, `DeepgramV2VoiceManager`, `ChunkedTtsFetcher`, `TtsCache`) 내부 로직 — 일절 수정 금지.
- 스트리밍 핸들러의 **Part1 TTS 스킵 / Part2 낭독 로직**(약 1748~1791행), **TtsCache 저장**(약 1942~1951행) — 수정 금지.
- **Firestore 저장부**(`hostLine`/`hostLineOnly`, `translated_text` 등 2300~2340·2014~2055행) — 수정 금지. (Part1 글자는 계속 통째로 저장되어야 함.)
- 프롬프트 내부 영어 문자열의 따옴표/URL 마크다운 규칙 — 이번 작업은 해당 없음(렌더링만 변경).

### 검증 체크리스트
1. `flutter analyze` — 에러 0개.
2. `grep -n "'turnId': currentTurnId" routine_mode_step_expand.dart` → 1616행 1건.
3. `grep -n "isExpandTurn" routine_mode_step_expand.dart` → 2건(정의·사용).
4. `grep -c "hasUserTwoParts" routine_mode_step_expand.dart` → **0** (기존 변수 완전 제거 확인).
5. 런타임: 1턴째 = 짧은 대답+한국어 표시 / 2턴째부터 = 확장문장만 표시, 스트리밍 중 Part1 비노출('...'만). 히스토리 들어가면 Part1+Part2 둘 다 글자 보이고 재생됨.

