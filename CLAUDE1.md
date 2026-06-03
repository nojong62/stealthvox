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

---

## Claude Code 지시문

**파일:** `lib/custom_code/widgets/chat_history_master.dart`

---

### [변경 1] P/E 버튼 터치 영역 확대
**위치:** 약 5346~5376줄 — `// P/E 버튼 — Expanded ↔ Polished 전환` 블록의 `child: Container(` 시작부터 닫는 `),`까지

**삭제 시작:** 5346줄 `child: Container(`
**삭제 끝:** 5376줄 `),` (GestureDetector 닫는 괄호 바로 앞)

**교체 코드:**
```dart
                    child: Container(
                      width: 40,
                      height: 40,
                      margin: const EdgeInsets.only(right: 4),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: _practicingPolished
                              ? Colors.greenAccent
                              : (_polishedSentence.isNotEmpty
                                  ? Colors.amber
                                  : Colors.white24),
                          width: 1.5,
                        ),
                      ),
                      child: Center(
                        child: Text(
                          _practicingPolished ? 'E' : 'P',
                          style: TextStyle(
                            color: _practicingPolished
                                ? Colors.greenAccent
                                : (_polishedSentence.isNotEmpty
                                    ? Colors.amber
                                    : Colors.white24),
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
```

**변경 요약:** `width/height: 26 → 40`, `fontSize: 12 → 14`

---

### [변경 2] T(글자크기) 버튼 터치 영역 확대 — Chunk Practice 화면
**위치:** 약 5377~5397줄 — P/E 버튼 바로 아래 `GestureDetector(` 블록 전체

**삭제 시작:** 5377줄 `GestureDetector(`
**삭제 끝:** 5397줄 닫는 `),`

**교체 코드:**
```dart
                  GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => setState(() {
                      _fontScale = _fontScale == 1.0
                          ? 1.3
                          : _fontScale == 1.3
                              ? 0.8
                              : 1.0;
                    }),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 8),
                      child: Icon(
                        Icons.format_size,
                        color: _fontScale > 1.0
                            ? const Color(0xFFFBBF24)
                            : _fontScale < 1.0
                                ? Colors.white38
                                : Colors.white54,
                        size: 22,
                      ),
                    ),
                  ),
```

**변경 요약:** `behavior: HitTestBehavior.opaque` 추가, `padding horizontal: 6 → 10 + vertical: 8 추가`, `size: 20 → 22`

---

### [변경 3] T(글자크기) 버튼 터치 영역 확대 — 메인 히스토리 화면
**위치:** 약 3125~3142줄 — `_buildCustomAppBar` 내부 `IconButton(` (format_size 아이콘)

**삭제 시작:** 3125줄 `IconButton(`
**삭제 끝:** 3142줄 닫는 `),`

**교체 코드:**
```dart
          IconButton(
            icon: Icon(
              Icons.format_size,
              color: _fontScale > 1.0
                  ? const Color(0xFFFBBF24)
                  : _fontScale < 1.0
                      ? Colors.white38
                      : Colors.white70,
              size: 24,
            ),
            padding: const EdgeInsets.all(10),
            constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
            onPressed: () => setState(() {
              _fontScale = _fontScale == 1.0
                  ? 1.3
                  : _fontScale == 1.3
                      ? 0.8
                      : 1.0;
            }),
          ),
```

**변경 요약:** `padding: all(10)` + `constraints: minWidth/Height 44` 추가, `size: 22 → 24`

---

### 검증 체크리스트
```
□ flutter analyze → 0 errors
□ grep -n "width: 40" chat_history_master.dart   → 5346줄 부근 확인
□ grep -n "horizontal: 10" chat_history_master.dart → 5377줄 부근 확인
□ grep -n "minWidth: 44" chat_history_master.dart   → 3125줄 부근 + 기존 LangIcon 버튼(3157줄) 2개 확인
```

### 절대 건드리지 말 것
- Box 7 (`TtsQueueManager`, `DeepgramV2VoiceManager`) 관련 코드 일체
- `GestureDetector`의 `onTap` 로직 내부 (`_switchToPolishedPractice`, `_buildChunks` 호출 등)