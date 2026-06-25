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

# P3 Echoing 오버레이 — 음성 게이트화 + 문구 변경 지시서

> 대상 파일: `lib/custom_code/widgets/chat_history_master.dart`
> 적용 범위: ChatHistory(Study Room) Expanded **P3 / chunkPractice 진입** 시 "Do Echoing!" 오버레이
> 영향 없음: Box 7, P1, P2, turnPractice, billing 로직 (전부 untouched)

---

## 0. 목적

현재 "Do Echoing!" 오버레이는 **장식**일 뿐이고, 첫 청크 음성은 `Future.delayed(Duration.zero)`로 **즉시** 재생됨 → 팝업이 떠 있는데 소리가 바로 나서 "급하고 복잡한" 느낌.

**변경 후 동작:**
1. 오버레이 표시 (≈1.6초)
2. 오버레이가 **사라지는 순간** 첫 청크 음성 시작 (게이트화)
3. 문구 `Do Echoing!` → `Echo it!`

부수 효과: 중복된 `Future.delayed(Duration.zero)` 블록 2곳 제거 → 코드 정리됨.

---

## 1. Savepoint (필수, 작업 전)

```bash
cd F:\flutter_project\stealth_vox
git add -A
git commit -m "savepoint: before P3 echoing gate + wording change"
```
> 이미 push된 상태에서 되돌릴 경우: `git revert <hash>`

---

## 2. Phase 1 — 사전 grep 확인 (편집 전 현재 상태)

```bash
grep -c "Do Echoing!" lib/custom_code/widgets/chat_history_master.dart
# 기대값: 1

grep -c "_triggerEchoingOverlay()" lib/custom_code/widgets/chat_history_master.dart
# 기대값: 2   (호출부 2곳, 빈 괄호)

grep -c "Future.delayed(Duration.zero" lib/custom_code/widgets/chat_history_master.dart
# 기대값: (출력값 메모 → Phase 3에서 -2 되어야 함)

grep -n "void _triggerEchoingOverlay" lib/custom_code/widgets/chat_history_master.dart
# 기대값: 정의부 1곳 (1767 부근)
```

위 값이 다르면 **중단하고 보고**. (파일이 이미 수정되었을 수 있음)

---

## 3. Phase 2 — str_replace 편집 (아래→위 순서로 적용)

> ⚠️ 반드시 **아래(큰 줄번호)부터 위로** 순서대로. 각 anchor는 고유 텍스트로 검증됨.

---

### [편집 1/4] 호출부 ② — `_goToChunkPractice` (≈6396행)

**old_str:**
```dart
    _triggerEchoingOverlay();
    Future.delayed(Duration.zero, () {
      if (mounted &&
          _phase == ShadowingPhase.chunkPractice &&
          _chunks.isNotEmpty &&
          _currentChunkIdx == -1) {
        _onChunkTapped(0);
      }
    });
  }
```

**new_str:**
```dart
    // 오버레이가 사라지는 순간 첫 청크 음성 시작 (게이트화)
    _triggerEchoingOverlay(onDismiss: () {
      if (mounted &&
          _phase == ShadowingPhase.chunkPractice &&
          _chunks.isNotEmpty &&
          _currentChunkIdx == -1) {
        _onChunkTapped(0);
      }
    });
  }
```

---

### [편집 2/4] 문구 변경 (≈5834행)

**old_str:**
```dart
                      'Do Echoing!',
```

**new_str:**
```dart
                      'Echo it!',
```

---

### [편집 3/4] 함수 정의 — `_triggerEchoingOverlay` (≈1767행)

**old_str:**
```dart
  void _triggerEchoingOverlay() {
    if (!mounted) return;
    setState(() => _showEchoingOverlay = true);
    _echoingOverlayTimer?.cancel();
    _echoingOverlayTimer = Timer(const Duration(milliseconds: 1600), () {
      if (mounted) setState(() => _showEchoingOverlay = false);
    });
  }
```

**new_str:**
```dart
  void _triggerEchoingOverlay({VoidCallback? onDismiss}) {
    if (!mounted) return;
    setState(() => _showEchoingOverlay = true);
    _echoingOverlayTimer?.cancel();
    _echoingOverlayTimer = Timer(const Duration(milliseconds: 1600), () {
      if (!mounted) return;
      setState(() => _showEchoingOverlay = false);
      onDismiss?.call(); // 오버레이 증발 시점에 첫 청크 음성 트리거
    });
  }
```

> 1600ms는 **그대로 유지** (1.6초 요청). `VoidCallback`은 material import에 포함되어 있어 별도 import 불필요.

---

### [편집 4/4] 호출부 ① — chunkPractice 진입부 (≈1214행)

**old_str:**
```dart
      _triggerEchoingOverlay();
    }
    _loadPolishedSentence();
    _prefetchAllChunkAI();
    Future.delayed(Duration.zero, () {
      if (mounted &&
          _phase == ShadowingPhase.chunkPractice &&
          _chunks.isNotEmpty &&
          _currentChunkIdx == -1) {
        _onChunkTapped(0);
      }
    });
  }
```

**new_str:**
```dart
      // 오버레이가 사라지는 순간 첫 청크 음성 시작 (게이트화)
      _triggerEchoingOverlay(onDismiss: () {
        if (mounted &&
            _phase == ShadowingPhase.chunkPractice &&
            _chunks.isNotEmpty &&
            _currentChunkIdx == -1) {
          _onChunkTapped(0);
        }
      });
    }
    _loadPolishedSentence();
    _prefetchAllChunkAI();
  }
```

> `_prefetchAllChunkAI()`는 그대로 즉시 실행됨 → 오버레이 1.6초 동안 첫 청크 미리 캐시 → 증발 직후 음성이 더 빠르게 나옴 (부수 이득).

---

## 4. Phase 3 — 편집 후 grep 검증 (기대 카운트)

```bash
grep -c "Do Echoing!" lib/custom_code/widgets/chat_history_master.dart
# 기대값: 0

grep -c "Echo it!" lib/custom_code/widgets/chat_history_master.dart
# 기대값: 1

grep -c "_triggerEchoingOverlay(onDismiss:" lib/custom_code/widgets/chat_history_master.dart
# 기대값: 2   (호출부 2곳 전환 완료)

grep -c "_triggerEchoingOverlay()" lib/custom_code/widgets/chat_history_master.dart
# 기대값: 0   (빈 괄호 호출 전부 사라짐. 정의부는 '({VoidCallback'이라 매칭 안 됨)

grep -c "onDismiss" lib/custom_code/widgets/chat_history_master.dart
# 기대값: 4   (정의 파라미터 1 + onDismiss?.call() 1 + 호출부 2)

grep -c "Future.delayed(Duration.zero" lib/custom_code/widgets/chat_history_master.dart
# 기대값: Phase 1 값 - 2
```

하나라도 불일치 → **중단 후 보고**.

---

## 5. 정적 분석 + 포맷 (게이트)

```bash
flutter analyze lib/custom_code/widgets/chat_history_master.dart
# 신규 error/warning 0 이어야 함

dart format lib/custom_code/widgets/chat_history_master.dart
```
> ⚠️ `dart format`은 **이 파일 하나만** 대상. 폴더 단위 금지 (한글 문자열 깨짐).

---

## 6. 동작 확인 (수동)

1. Study Room → 임의 대화 항목 → Expanded **P3** 진입
2. 확인:
   - 팝업이 **"Echo it!"** 로 표시
   - 팝업이 ≈1.6초 보이다 사라짐
   - 팝업이 **증발하는 순간**에 첫 청크 음성 시작 (팝업 떠 있는 중엔 무음)
3. 회화 빌드 경로(`buildExpandFromConversation` → `_goToChunkPractice`)로도 동일 동작 확인

---

## 7. 롤백 절차

```bash
# 커밋 전이면
git checkout -- lib/custom_code/widgets/chat_history_master.dart

# 이미 커밋했다면
git revert <commit_hash>
```

---

## 변경 요약

| # | 위치 | 내용 |
|---|------|------|
| 1 | `_goToChunkPractice` (~6396) | `Future.delayed(Duration.zero)` 제거 → `onDismiss` 콜백으로 이전 |
| 2 | 오버레이 UI (~5834) | `Do Echoing!` → `Echo it!` |
| 3 | `_triggerEchoingOverlay` 정의 (~1767) | `onDismiss` 파라미터 추가, 타이머 완료 시 호출 (1600ms 유지) |
| 4 | chunkPractice 진입부 (~1214) | `Future.delayed(Duration.zero)` 제거 → `onDismiss` 콜백으로 이전 |

**불변(untouched):** Box 7, P1, P2, turnPractice, billing, 오버레이 fade(600ms), 1600ms 노출시간.