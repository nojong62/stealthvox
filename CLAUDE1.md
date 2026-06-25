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

# 실전 튜터링 시트 — STT 말풍선 잘림 해결 (B안: 패딩 + 말풍선 위치 이동)

## 목적
히스토리 실전 튜터링(`showModalBottomSheet` → `DraggableScrollableSheet`) 하단에서
**유저 STT 결과 말풍선(`_appTranscript`)이 시스템 네비게이션 바 뒤로 잘려** 끝까지 스크롤해도 안 보이는 문제 해결.

- 근본 원인 ①: `SingleChildScrollView`에 하단 SafeArea 패딩이 없어 시트 하단(네비바 영역)에서 마지막 자식이 잘림.
- 근본 원인 ②: 말풍선이 `Close / Another Sentence` 버튼 **아래**(스크롤 최하단)에 있어 구조적으로 항상 숨음.

→ 패딩 추가 + 말풍선을 버튼 **위**(교정 결과 아래)로 이동 = 스크롤·잘림 원천 차단.

## 적용 파일 (단 1개)
`chat_history_master.dart` (Box 17-B `_buildAccordion`, Box 17 `showModalBottomSheet` 부분)

## 건드리지 않는 것 (불변)
- Box 7 (`TtsQueueManager` / `DeepgramV2VoiceManager` / `ChunkedTtsFetcher` / `HybridTtsPlayer` / `TtsCache`)
- 빌링(`BillingTicker` / `BillingRate`), STT/교정 로직, GPT 프롬프트
- P1 / P2 / P3 / turnPractice 분기
- 말풍선의 스타일·텍스트 자체 (위치만 이동, 디자인 동일)

---

## 0. SAVEPOINT (필수 — 작업 전 커밋)
```bash
git add -A
git commit -m "savepoint: 튜터링 말풍선 잘림 수정 직전"
```

---

## Phase 1 — grep 발견 (기대 카운트 확인)
```bash
grep -n "initialChildSize: 0.65" chat_history_master.dart        # → 1
grep -nc "투명 말풍선" chat_history_master.dart                    # → 1
grep -nc "화면 최하단" chat_history_master.dart                    # → 1
grep -n "// 하단 버튼" chat_history_master.dart                    # → 1
grep -c "_appTranscript" chat_history_master.dart                # → 5 (불변 기준값)
```
위 카운트와 다르면 **중단**하고 보고. (특히 `_appTranscript` = 5 는 작업 후에도 그대로 유지되어야 함 — 이동만 하므로 순증감 0)

---

## Phase 2 — str_replace (아래→위 순서로 적용, 라인 밀림 방지)

### ▶ 편집 ① (파일 하단, ~2654행): 기존 말풍선 제거
하단 버튼 Row 아래의 "화면 최하단" 말풍선 블록을 삭제. Row 닫힘 `),` 과 spread 닫힘 `],` 만 남긴다.

**old_str**
```dart
            ),

            // 투명 말풍선 (STT 결과) - 화면 최하단
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: const BoxDecoration(
                color: Colors.transparent,
                borderRadius: BorderRadius.all(Radius.circular(16)),
              ),
              child: Text(
                _appTranscript,
                textAlign: TextAlign.center,
                style: const TextStyle(
                    color: Colors.white54,
                    fontSize: 13,
                    height: 1.4,
                    fontStyle: FontStyle.italic),
              ),
            ),
          ],
```

**new_str**
```dart
            ),
          ],
```

---

### ▶ 편집 ② (~2620행): 말풍선을 버튼 **위**로 이동 (+ 빈 값 가드)
`const SizedBox(height: 18),` 와 `// 하단 버튼` 사이에 말풍선 삽입.
`_appTranscript`가 비었을 땐 렌더 안 되도록 `if ... .isNotEmpty` 가드 추가(녹음 전 빈 여백 방지).

**old_str**
```dart
            const SizedBox(height: 18),

            // 하단 버튼
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
```

**new_str**
```dart
            const SizedBox(height: 18),

            // 투명 말풍선 (STT 결과) - 교정 결과 아래 고정 노출
            if (_appTranscript.isNotEmpty) ...[
              Container(
                width: double.infinity,
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                decoration: const BoxDecoration(
                  color: Colors.transparent,
                  borderRadius: BorderRadius.all(Radius.circular(16)),
                ),
                child: Text(
                  _appTranscript,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      color: Colors.white54,
                      fontSize: 13,
                      height: 1.4,
                      fontStyle: FontStyle.italic),
                ),
              ),
              const SizedBox(height: 16),
            ],

            // 하단 버튼
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
```

---

### ▶ 편집 ③ (~2374행): 하단 SafeArea 패딩 + 초기 높이 상향
`SingleChildScrollView`에 네비바 인셋만큼 하단 패딩을 줘서 마지막 자식이 항상 위로 올라오게 함. 초기 높이 0.65 → 0.72(드래그 없이 더 보이게).

**old_str**
```dart
          return DraggableScrollableSheet(
            initialChildSize: 0.65,
            minChildSize: 0.45,
            maxChildSize: 0.95,
            expand: false,
            builder: (_, scrollController) => SingleChildScrollView(
              controller: scrollController,
              child: _buildAccordion(
```

**new_str**
```dart
          return DraggableScrollableSheet(
            initialChildSize: 0.72,
            minChildSize: 0.45,
            maxChildSize: 0.95,
            expand: false,
            builder: (_, scrollController) => SingleChildScrollView(
              controller: scrollController,
              padding: EdgeInsets.only(
                  bottom: MediaQuery.of(ctx).padding.bottom + 24),
              child: _buildAccordion(
```
> 참고: `ctx`는 바로 위 `showModalBottomSheet(builder: (ctx) => ...)`의 컨텍스트로 스코프 내 사용 가능. 새 import 불필요.

---

## Phase 3 — grep 검증 (기대 카운트)
```bash
grep -c "화면 최하단" chat_history_master.dart                       # → 0  (구 주석 제거됨)
grep -c "교정 결과 아래 고정 노출" chat_history_master.dart          # → 1  (신 주석)
grep -c "if (_appTranscript.isNotEmpty)" chat_history_master.dart   # → 1  (가드 추가)
grep -c "_appTranscript" chat_history_master.dart                  # → 5  (불변 — 이동만)
grep -c "MediaQuery.of(ctx).padding.bottom" chat_history_master.dart # → 1
grep -c "initialChildSize: 0.72" chat_history_master.dart          # → 1
grep -c "initialChildSize: 0.65" chat_history_master.dart          # → 0
grep -c "투명 말풍선" chat_history_master.dart                       # → 1
```
하나라도 어긋나면 **롤백** 후 보고.

---

## Phase 4 — 정적 분석 / 포맷 (개별 파일만)
```bash
flutter analyze chat_history_master.dart
dart format chat_history_master.dart
```
> ⚠️ `dart format`은 반드시 **이 파일 하나만** 대상. 폴더 단위 금지(한글 문자열 UTF-8 깨짐).

`flutter analyze`에 신규 error/warning 0 확인.

---

## 동작 확인 체크리스트
1. 히스토리 → 튜터링 진입 시 시트가 약 72% 높이로 열림.
2. 녹음 → 교정 결과 표시 후, **내가 말한 문장 말풍선이 `Close / Another Sentence` 버튼 바로 위에** 보임.
3. 시트를 끝까지 드래그/스크롤했을 때 말풍선이 네비게이션 바에 **안 잘림**.
4. 녹음 전(=transcript 비어있음)에는 말풍선 자리에 빈 여백 없음.
5. `Another Sentence` 누르면 말풍선 사라짐(`_appTranscript=""` 리셋 정상).
6. 빌링·TTS·쉐도잉 동작 이상 없음.

---

## 롤백
```bash
# 아직 push 전:
git reset --hard HEAD~1
# 이미 push 했다면:
git revert <savepoint_hash>
```