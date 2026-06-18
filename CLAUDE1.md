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

# 텔레프롬프터 스크롤 수정 지시문 — Roleplay & Step Expand

**목표:** "글 많으면 빠르게 / 적으면 천천히 / 현재 말하는 부분이 화면 중앙을 지나가도록" — 텔레프롬프터 방식 스크롤 적용.

**원리:** `_scrollToBottom()` 메서드 **정의 자체를 교체**하여, `animateTo(maxScrollExtent)` → `Scrollable.ensureVisible(alignment: 0.45)` + 텍스트 길이 기반 동적 duration. 기존 10+곳의 호출부는 수정 없이 자동 전파.

**대상 파일:**
- `lib/custom_code/widgets/routine_mode_roleplay.dart` (1편집)
- `lib/custom_code/widgets/routine_mode_step_expand.dart` (2편집)

**하단→상단 순서 적용. Box 7 미수정.**

---

## 파일 1) routine_mode_roleplay.dart — 1편집

### R-1: `_scrollToBottom()` 메서드 본문 교체

> 사전 검증: `grep -c "void _scrollToBottom()" routine_mode_roleplay.dart` → **1** 확인

```
OLD:
  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        // 첫 메시지(오프너)일 때는 상단 고정 → 시작 대사 전체가 보이게
        if (_localMessages.length <= 1) return;
        _scrollController.animateTo(_scrollController.position.maxScrollExtent,
            duration: const Duration(milliseconds: 300), curve: Curves.easeOut);
      }
    });
  }
```
```
NEW:
  // [텔레프롬프터 v1] 현재 버블을 화면 중앙(0.45)으로 부드럽게 이동.
  //   텍스트 길이 기반 동적 duration: 짧으면 느긋(700ms), 길면 빠르게(150ms).
  //   key/context 미확보 시 기존 maxScrollExtent fallback.
  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) return;
      if (_localMessages.length <= 1) return;

      final lastIdx = _localMessages.length - 1;
      final key = _itemKeys[lastIdx];
      final ctx = key?.currentContext;

      if (ctx == null) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
        return;
      }

      final text = (_localMessages[lastIdx]['target'] ?? '').toString();
      final ms = (800 - text.length * 3).clamp(150, 700);

      Scrollable.ensureVisible(
        ctx,
        alignment: 0.45,
        duration: Duration(milliseconds: ms),
        curve: Curves.easeOut,
      );
    });
  }
```

**Roleplay 적용 후 검증:**
```bash
grep -c "alignment: 0.45" routine_mode_roleplay.dart                # 1 기대
grep -c "text.length \* 3" routine_mode_roleplay.dart               # 1 기대
grep -c "animateTo(_scrollController.position.maxScrollExtent" routine_mode_roleplay.dart  # 1 기대 (fallback)
```

---

## 파일 2) routine_mode_step_expand.dart — 2편집 (하단→상단)

### S-1 (하단): ListView 항목에 GlobalKey 부여 — ensureVisible 타겟 확보

> 사전 검증: `grep -c "return _buildTextBlock(_localMessages\[idx\]);" routine_mode_step_expand.dart` → **1** 확인

```
OLD:
      itemBuilder: (context, idx) {
        if (idx < _localMessages.length) {
          return _buildTextBlock(_localMessages[idx]);
        }
```
```
NEW:
      itemBuilder: (context, idx) {
        if (idx < _localMessages.length) {
          _itemKeys[idx] ??= GlobalKey(); // [텔레프롬프터 v1] ensureVisible 타겟
          return Container(
              key: _itemKeys[idx],
              child: _buildTextBlock(_localMessages[idx]));
        }
```

### S-2 (상단): `_scrollToBottom()` 메서드 본문 교체

> 사전 검증: `grep -c "void _scrollToBottom()" routine_mode_step_expand.dart` → **1** 확인

```
OLD:
  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        if (_localMessages.length <= 1) return;
        _scrollController.animateTo(_scrollController.position.maxScrollExtent,
            duration: const Duration(milliseconds: 300), curve: Curves.easeOut);
      }
    });
  }
```
```
NEW:
  // [텔레프롬프터 v1] 현재 버블을 화면 중앙(0.45)으로 부드럽게 이동.
  //   텍스트 길이 기반 동적 duration: 짧으면 느긋(700ms), 길면 빠르게(150ms).
  //   key/context 미확보 시 기존 maxScrollExtent fallback.
  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) return;
      if (_localMessages.length <= 1) return;

      final lastIdx = _localMessages.length - 1;
      final key = _itemKeys[lastIdx];
      final ctx = key?.currentContext;

      if (ctx == null) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
        return;
      }

      final text = (_localMessages[lastIdx]['target'] ?? '').toString();
      final ms = (800 - text.length * 3).clamp(150, 700);

      Scrollable.ensureVisible(
        ctx,
        alignment: 0.45,
        duration: Duration(milliseconds: ms),
        curve: Curves.easeOut,
      );
    });
  }
```

**Step Expand 적용 후 검증:**
```bash
grep -c "alignment: 0.45" routine_mode_step_expand.dart                # 1 기대
grep -c "key: _itemKeys\[idx\]" routine_mode_step_expand.dart          # 1 기대
grep -c "text.length \* 3" routine_mode_step_expand.dart               # 1 기대
```

---

## 마무리 검증 (공통)
```bash
flutter analyze lib/custom_code/widgets/routine_mode_roleplay.dart
flutter analyze lib/custom_code/widgets/routine_mode_step_expand.dart
```

## 실기기 체감 테스트 체크리스트
1. AI 짧은 대사(1~2문장): 느긋하게 중앙으로 올라오는가
2. AI 긴 대사(3문장+): 빠르게 중앙을 지나가는가
3. 사용자 발화 표시: 버블이 중앙에 안정적으로 위치하는가
4. 오프너(첫 발화): 화면 상단에 머무는가 (<=1 가드)
5. 대화 5턴 이상 축적 시: 이전 버블이 위로 자연스럽게 밀려나는가

## duration 튜닝 가이드
체감이 아직 느리면 → `800`을 `600`으로, `clamp(150, 700)`를 `clamp(120, 500)`으로 줄이기.
중앙보다 약간 위를 원하면 → `alignment: 0.45`를 `0.35`로 변경.
이 값들은 `_scrollToBottom()` 메서드 안 한 곳에만 있으므로, 한 줄 수정으로 즉시 반영.

## 롤백
- OLD 블록 복원 (3곳).
- 또는 `git revert <hash>`.