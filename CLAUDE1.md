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
- 완료후 관리자가 APK 라고 적으면, 날자와 시간이 이름에 들어간 APK만들어 줘. 

이 내용을 항상 기억하고 지시문에 포함해 줘.
=================================
지시문 

# [StepExpand] SCROLL-TOP 폭주 쓰로틀 지시서

## 배경 / 목적
StepExpand에서 `_scrollToCurrentTop(hostIndex)`가 **GPT 스트리밍 `await for` 루프 안**에서
청크 도착마다 호출된다. 매 호출이 `Scrollable.ensureVisible(... 220ms easeOut)`를 새로 예약해
**직전 220ms 애니메이션을 취소·재시작**하는 쓰래싱이 발생한다.
로그상 `🧭 [SCROLL-TOP] index=N`이 ~20ms 간격으로 수백 줄 찍히는 구간이 이것이며,
텍스트 스트리밍(가장 지연 민감한 순간)에 프레임 예산을 갉아먹어 버벅임으로 체감된다.

### 해결 방식 (최소 변경)
`_scrollToCurrentTop` 진입부에 **시간 기반 쓰로틀**을 둔다.
- 같은 `index` 연속 호출은 **150ms** 이내면 스킵 (스트리밍 폭주 차단).
- `index`가 바뀌면(새 버블) **즉시 통과** → 위치 정확도 유지.
- 루프 종료 후 별도 스크롤(`_revealForReading` / `_scrollToBottom`)이 최종 위치를 보정하므로 끝줄 정확도 영향 없음.

### 영향 범위 / 불변 보장
- 대상 파일: **`routine_mode_step_expand.dart` 1개**
- Box 7(`TtsQueueManager`/`DeepgramV2VoiceManager`/`ChunkedTtsFetcher`/`HybridTtsPlayer`/`TtsCache`) **미변경**
- 과금(BillingTicker), 파이프라인 순서, P1/P2/P3, Practice **미변경**
- 추가 위젯·의존성 **없음** (`DateTime` 기본 타입 + 필드 2개만)

---

## Phase 0 — 세이브포인트
```bash
git add -A && git commit -m "savepoint: before SCROLL-TOP throttle (step_expand)"
```
> 이미 push된 상태라면 롤백 시 `git revert <hash>` 사용.

## Phase 1 — 대상/앵커 사전 검증 (grep)
```bash
# 1) 대상 파일 경로 확인
grep -rln "_scrollToCurrentTop" lib/

# 2) 수정 전 기준 카운트 (반드시 아래 값과 일치해야 함)
grep -c "_scrollToCurrentTop"  <대상파일>   # 기대값: 2  (정의 1 + 호출 1)
grep -c "SCROLL-TOP"           <대상파일>   # 기대값: 1
grep -c "_lastScrollTopAt"     <대상파일>   # 기대값: 0
grep -c "_lastScrollTopIndex"  <대상파일>   # 기대값: 0
grep -c "SCROLL-THROTTLE"      <대상파일>   # 기대값: 0
```
> 위 5개 기준값이 다르면 **중단**하고 보고. (파일 버전 불일치 가능성)

---

## Phase 2 — 수정 (str_replace, 아래→위 순서)

### ✅ EDIT 1 — 메서드 진입부에 쓰로틀 가드 (위쪽 라인보다 먼저 적용)

**find:**
```dart
  void _scrollToCurrentTop(int index) {
    _log('🧭 [SCROLL-TOP]', 'index=$index');
    WidgetsBinding.instance.addPostFrameCallback((_) {
```

**replace:**
```dart
  void _scrollToCurrentTop(int index) {
    // 🔧 [SCROLL-THROTTLE] GPT 스트리밍 청크마다 호출되어 220ms 스크롤 애니메이션이
    //   매 청크마다 취소/재시작되던 폭주를 방지. 같은 index 연속 호출은 150ms로 제한.
    //   index가 바뀌면(새 버블) 즉시 통과시켜 위치 정확도는 유지한다.
    final now = DateTime.now();
    if (_lastScrollTopIndex == index &&
        _lastScrollTopAt != null &&
        now.difference(_lastScrollTopAt!).inMilliseconds < 150) {
      return;
    }
    _lastScrollTopAt = now;
    _lastScrollTopIndex = index;
    _log('🧭 [SCROLL-TOP]', 'index=$index');
    WidgetsBinding.instance.addPostFrameCallback((_) {
```

### ✅ EDIT 2 — 쓰로틀 상태 필드 선언 추가

**find:**
```dart
  final ScrollController _scrollController = ScrollController();
  final Map<int, GlobalKey> _itemKeys = {};
```

**replace:**
```dart
  final ScrollController _scrollController = ScrollController();
  // 🔧 [SCROLL-THROTTLE] 상단 고정 스크롤 과다 호출 억제용 상태
  DateTime? _lastScrollTopAt;
  int _lastScrollTopIndex = -1;
  final Map<int, GlobalKey> _itemKeys = {};
```

> 두 find 앵커는 각각 파일 내 **유일**함(사전 검증됨). 둘 다 정확히 1곳에서만 치환되어야 함.

---

## Phase 3 — 수정 후 검증 (grep, 기대 카운트)
```bash
grep -c "_lastScrollTopAt"     <대상파일>   # 기대값: 4
grep -c "_lastScrollTopIndex"  <대상파일>   # 기대값: 3
grep -c "SCROLL-THROTTLE"      <대상파일>   # 기대값: 2
grep -c "SCROLL-TOP"           <대상파일>   # 기대값: 1  (불변)
grep -c "_scrollToCurrentTop"  <대상파일>   # 기대값: 2  (불변)
```
- 5개 값이 위와 정확히 일치하면 성공.
- 하나라도 어긋나면 **롤백**(Phase 5) 후 보고.

## Phase 4 — 정적 분석 / 포맷
```bash
flutter analyze <대상파일>
dart format <대상파일>     # ⚠️ 폴더 대상 금지, 반드시 이 파일 1개만
```
> `analyze`에서 신규 경고/에러 0건이어야 함.

## Phase 5 — 롤백 절차
```bash
# 커밋만 한 상태(push 전)
git checkout -- <대상파일>
# 또는 세이브포인트 전체 복귀
git reset --hard HEAD~1
# 이미 push된 경우
git revert <savepoint_hash>
```

---

## 실기기 확인 포인트 (수정 후)
1. StepExpand 한 턴 진행 중 로그에서 `🧭 [SCROLL-TOP]`가 **턴당 수백 줄 → 한 자릿수**로 감소했는가.
2. 유저/AI 텍스트 스트리밍 중 상단 고정 버블이 **부드럽게** 따라오는가(끊김·튐 없음).
3. 새 버블 등장 시(인덱스 변경) 스크롤이 **즉시** 반응하는가(150ms 지연 없이).
4. 5턴 완료 후 확장문장 카드/낭독 위치가 기존과 동일한가.