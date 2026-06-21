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

# 프리톡 + 듀오 — `reverse: true` 카톡 방식 적용

> 롤플레이·스탭익스팬드는 이미 적용 완료.
> 이 지시문은 **프리톡**과 **듀오** 2개 파일만 대상.
>
> 원칙:
> - `ListView.builder(reverse: true)` — 최신 메시지 하단 고정
> - `_scrollToBottom()` → `animateTo(0)` — position 0 = 하단
> - `_scrollToCurrentTop` alignment `0.02` → `0.98` — reverse에서 화면 상단
> - `_scrollToCurrent` alignment `0.5` — 변경 없음 (센터는 모드 무관)
> - 패딩 top ↔ bottom 교환

---

## 1. routine_mode_free_talk.dart (3건, bottom-to-top)

### 1-3. ListView.builder — `reverse: true` + 인덱스 역전 + 패딩 교환

```
str_replace
OLD >>>
        ListView.builder(
          controller: _scrollController,
          padding: EdgeInsets.fromLTRB(16, 16, 16, bottomPad),
          itemCount: _localMessages.length,
          itemBuilder: (context, idx) {
            _itemKeys[idx] ??= GlobalKey();
            return Container(
                key: _itemKeys[idx],
                child: _buildTextBlock(_localMessages[idx]));
          },
        ),
<<< OLD

NEW >>>
        ListView.builder(
          reverse: true,
          controller: _scrollController,
          padding: EdgeInsets.fromLTRB(16, bottomPad, 16, 16),
          itemCount: _localMessages.length,
          itemBuilder: (context, idx) {
            final realIdx = _localMessages.length - 1 - idx;
            _itemKeys[realIdx] ??= GlobalKey();
            return Container(
                key: _itemKeys[realIdx],
                child: _buildTextBlock(_localMessages[realIdx]));
          },
        ),
<<< NEW
```

### 1-2. `_scrollToCurrentTop` alignment 변경 (0.02 → 0.98)

```
str_replace
OLD >>>
  void _scrollToCurrentTop(int index) {
    _log('🧭 [SCROLL-TOP]', 'index=$index');
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final key = _itemKeys[index];
      if (key == null) return;
      final ctx = key.currentContext;
      if (ctx == null) return;
      Scrollable.ensureVisible(
        ctx,
        alignment: 0.02,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOut,
      );
    });
  }
<<< OLD

NEW >>>
  void _scrollToCurrentTop(int index) {
    _log('🧭 [SCROLL-TOP]', 'index=$index');
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final key = _itemKeys[index];
      if (key == null) return;
      final ctx = key.currentContext;
      if (ctx == null) return;
      Scrollable.ensureVisible(
        ctx,
        alignment: 0.98, // reverse: true에서 화면 상단
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOut,
      );
    });
  }
<<< NEW
```

### 1-1. `_scrollToBottom` 교체

```
str_replace
OLD >>>
  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        if (_localMessages.length <= 1) return;
        _scrollController.animateTo(_scrollController.position.maxScrollExtent,
            duration: const Duration(milliseconds: 300), curve: Curves.easeOut);
      }
    });
  }
<<< OLD

NEW >>>
  // [reverse: true] 최신 메시지(position 0 = 하단)로 스크롤
  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(0,
            duration: const Duration(milliseconds: 300), curve: Curves.easeOut);
      }
    });
  }
<<< NEW
```

---

## 2. routine_mode_duo.dart (3건, bottom-to-top)

### 2-3. ListView.builder — `reverse: true` + 인덱스 역전 + 패딩 교환

```
str_replace
OLD >>>
                          : ListView.builder(
                              controller: _scrollController,
                              physics: const BouncingScrollPhysics(),
                              padding: EdgeInsets.only(
                                  left: 8,
                                  right: 8,
                                  top: 40,
                                  bottom:
                                      MediaQuery.of(context).size.height * 0.4),
                              itemCount: _localMessages.length,
                              itemBuilder: (context, index) {
                                if (!_itemKeys.containsKey(index))
                                  _itemKeys[index] = GlobalKey();
                                return Container(
                                  key: _itemKeys[index],
                                  child: _buildTextBlock(_localMessages[index]),
                                );
                              }),
<<< OLD

NEW >>>
                          : ListView.builder(
                              reverse: true,
                              controller: _scrollController,
                              physics: const BouncingScrollPhysics(),
                              padding: EdgeInsets.only(
                                  left: 8,
                                  right: 8,
                                  top:
                                      MediaQuery.of(context).size.height * 0.4,
                                  bottom: 40),
                              itemCount: _localMessages.length,
                              itemBuilder: (context, index) {
                                final realIdx =
                                    _localMessages.length - 1 - index;
                                if (!_itemKeys.containsKey(realIdx))
                                  _itemKeys[realIdx] = GlobalKey();
                                return Container(
                                  key: _itemKeys[realIdx],
                                  child:
                                      _buildTextBlock(_localMessages[realIdx]),
                                );
                              }),
<<< NEW
```

### 2-2. `_scrollToCurrentTop` alignment 변경 (0.02 → 0.98)

```
str_replace
OLD >>>
  // 현재 말풍선을 화면 상단에 고정 — 내 발화 추가 시 사용 (Roleplay 이식)
  void _scrollToCurrentTop(int index) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final key = _itemKeys[index];
      if (key == null) return;
      final ctx = key.currentContext;
      if (ctx == null) return;
      Scrollable.ensureVisible(
        ctx,
        alignment: 0.02,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOut,
      );
    });
  }
<<< OLD

NEW >>>
  // 현재 말풍선을 화면 상단에 고정 — 내 발화 추가 시 사용 (Roleplay 이식)
  // reverse: true에서 alignment 0.98 ≈ 화면 상단 2%
  void _scrollToCurrentTop(int index) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final key = _itemKeys[index];
      if (key == null) return;
      final ctx = key.currentContext;
      if (ctx == null) return;
      Scrollable.ensureVisible(
        ctx,
        alignment: 0.98,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOut,
      );
    });
  }
<<< NEW
```

### 2-1. `_scrollToBottom` 교체

```
str_replace
OLD >>>
  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) return;
      if (_localMessages.length <= 1) return;
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    });
  }
<<< OLD

NEW >>>
  // [reverse: true] 최신 메시지(position 0 = 하단)로 스크롤
  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(0,
            duration: const Duration(milliseconds: 300), curve: Curves.easeOut);
      }
    });
  }
<<< NEW
```

---

## 검증

```bash
# reverse: true 4개 파일 전부 확인
for f in routine_mode_free_talk routine_mode_roleplay routine_mode_step_expand routine_mode_duo; do
  echo "=== $f ==="
  grep -c "reverse: true" lib/custom_code/widgets/$f.dart
done
# → 각 1건씩, 총 4건

# maxScrollExtent 완전 제거 확인
for f in routine_mode_free_talk routine_mode_roleplay routine_mode_step_expand routine_mode_duo; do
  echo "=== $f ==="
  grep -c "maxScrollExtent" lib/custom_code/widgets/$f.dart
done
# → 각 0건

# animateTo(0) 확인
for f in routine_mode_free_talk routine_mode_roleplay routine_mode_step_expand routine_mode_duo; do
  echo "=== $f ==="
  grep -c "animateTo(0" lib/custom_code/widgets/$f.dart
done
# → 각 1건

# alignment: 0.98 확인 (_scrollToCurrentTop 안)
for f in routine_mode_free_talk routine_mode_roleplay routine_mode_step_expand routine_mode_duo; do
  echo "=== $f ==="
  grep -c "alignment: 0.98" lib/custom_code/widgets/$f.dart
done
# → 각 1건

# alignment: 0.5 잔존 확인 (_scrollToCurrent 안, 변경 불필요)
for f in routine_mode_free_talk routine_mode_roleplay routine_mode_duo; do
  echo "=== $f ==="
  grep -n "alignment: 0.5" lib/custom_code/widgets/$f.dart
done
# → 각 1건 (_scrollToCurrent 안, 정상)

flutter analyze lib/custom_code/widgets/routine_mode_free_talk.dart
flutter analyze lib/custom_code/widgets/routine_mode_duo.dart
```

## 변경하지 않는 것

- `_scrollToCurrent(alignment: 0.5)` — 센터 정렬은 reverse 무관, 변경 없음
- `_scrollToBottomThrottled()` — `_scrollToBottom()` 호출하므로 자동 반영
- `_scrollToCurrentTop` 호출 지점 — 프리톡·듀오 기존 호출 위치 유지
- 롤플레이·스탭익스팬드 — 이미 적용 완료, 이번 지시문 대상 아님
- Box 7 — 변경 금지
- `billing_ticker.dart` — 변경 없음

## 디바이스 테스트 (4개 모드 전체)

- [ ] 프리톡: 3턴 대화 → 메시지가 화면 하단에 자연스럽게 쌓이는지
- [ ] 프리톡: AI 응답 후 유저 대사 + AI 대사 모두 화면 안에 보이는지
- [ ] 듀오: PTT 3회 → 메시지가 하단에 쌓이는지
- [ ] 롤플레이: 기존 v4 동작 유지 확인
- [ ] 스탭익스팬드: 기존 v4 동작 유지 확인 (4턴 긴 문장 처음부터 보이는지)