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

# 지시문 — StepExpand: 씨앗 말풍선 상단 이동 + 긴 대사 텔레프롬프터 스크롤

**대상 파일:** `routine_mode_step_expand.dart`
**원칙:** 최소 diff · 아래→위 편집 순서 · 텍스트 앵커 기반 · `dart format`은 **이 파일 단독**. Box 7 / TTS 엔진 **무수정**.

---

## 무엇을 / 왜

### A. 씨앗 안내 말풍선('질문과 다른 씨앗 문장…')을 화면 상단으로
- 현재 `Positioned(bottom: 8)` → 채팅영역 하단에 떠서 대사를 가림.
- `top: 8`로 변경 → 상단에 잠깐 떴다 사라짐(3초 자동 숨김·페이드아웃은 기존 그대로).

### B. 긴 대사 텔레프롬프터 스크롤 (A안: 추정 동기화 글라이드)
- 버그 원인: 긴 대사 표시 시 `_scrollToBottom()`(reverse 리스트 offset 0 = 맨 아래) 호출 → 대사가 화면보다 길면 **첫 줄이 위로 밀려 사라짐.**
- 해결: 새 메서드 `_revealForReading(index, text)`
  - 메시지 높이 ≤ 화면 → 기존 카톡식(`_scrollToBottom`).
  - 메시지 높이 > 화면 → **첫 줄을 상단 고정** 후, 글자 수로 추정한 읽는 시간 동안 **선형으로 맨 아래까지 글라이드**(`animateTo(0)`).
- 적용 범위: **AI 질문 / AI 재질문 / 유저 확장 / AI 확장** 4곳 모두.
- 제약(수용됨): TTS-1은 단어별 타임스탬프가 없어 *추정* 동기화. 추정이 빗나가도 글라이드는 항상 끝줄(하단)에서 멈춰 결과는 안전. 속도는 `_kReadCharsPerSec` 한 값으로 튜닝.

---

## 0. Git 세이브포인트

```bash
git add -A
git commit -m "savepoint: before stepexpand seedhint-top + teleprompter scroll"
```

---

## 편집 (아래→위 순서)

### [E1] 씨앗 말풍선 상단 이동 (≈3380)

**OLD:**
```dart
  Widget _buildSeedHintBalloon() {
    return Positioned(
      bottom: 8,
      left: 24,
      right: 24,
```

**NEW:**
```dart
  Widget _buildSeedHintBalloon() {
    return Positioned(
      top: 8,
      left: 24,
      right: 24,
```

---

### [E2] AI 확장 — 최종 텍스트 지점 (≈2715, `[PIPE-08]` 앵커)

**OLD:**
```dart
      if (mounted && aiIndex < _localMessages.length) {
        setState(() {
          _localMessages[aiIndex]['target'] = aiTargetText;
          _localMessages[aiIndex]['original'] = aiOriginalText;
        });
        _scrollToBottom();
      }
      _log('🧠 [PIPE-08]',
```

**NEW:**
```dart
      if (mounted && aiIndex < _localMessages.length) {
        setState(() {
          _localMessages[aiIndex]['target'] = aiTargetText;
          _localMessages[aiIndex]['original'] = aiOriginalText;
        });
        _revealForReading(aiIndex, aiTargetText); // 🆕 긴 대사 텔레프롬프터
      }
      _log('🧠 [PIPE-08]',
```

---

### [E3] AI 확장 — 소리 시작 지점 (≈2701, `[v3.8]` 앵커)

> 소리 시작 시 표시되는 텍스트가 짧으면 자동으로 카톡식, 길면 글라이드. 최종 텍스트는 E2에서 보정.

**OLD:**
```dart
      if (mounted && aiIndex < _localMessages.length) {
        setState(() {
          _localMessages[aiIndex]['target'] = aiTargetText;
          _localMessages[aiIndex]['original'] = aiOriginalText;
        });
        _scrollToBottom();
      }
      // [v3.8] AI 한국어 단일 호출 통합
```

**NEW:**
```dart
      if (mounted && aiIndex < _localMessages.length) {
        setState(() {
          _localMessages[aiIndex]['target'] = aiTargetText;
          _localMessages[aiIndex]['original'] = aiOriginalText;
        });
        _revealForReading(aiIndex, aiTargetText); // 🆕 긴 대사 텔레프롬프터
      }
      // [v3.8] AI 한국어 단일 호출 통합
```

---

### [E4] 유저 확장 — onStreamEnd 직후 (≈2417)

**OLD:**
```dart
      await userHybridTts.onStreamEnd(
        fullSentence: _part2FullSentence,
        remainderBuffer: userBuffer,
        fetcher: userTtsFetcher,
        swSpeechEnd: _swTTS,
      );
```

**NEW:**
```dart
      await userHybridTts.onStreamEnd(
        fullSentence: _part2FullSentence,
        remainderBuffer: userBuffer,
        fetcher: userTtsFetcher,
        swSpeechEnd: _swTTS,
      );
      _revealForReading(hostIndex, _part2FullSentence); // 🆕 긴 대사 텔레프롬프터
```

---

### [E5] AI 재질문 — onStreamEnd 직후 (≈1875, `// TTS 재생 완료 대기` 앵커)

**OLD:**
```dart
    await questionHybridTts.onStreamEnd(
      fullSentence: aiText.trim(),
      remainderBuffer: aiBuffer,
      fetcher: questionTts,
      swSpeechEnd: _swTTS,
    );

    // TTS 재생 완료 대기
```

**NEW:**
```dart
    await questionHybridTts.onStreamEnd(
      fullSentence: aiText.trim(),
      remainderBuffer: aiBuffer,
      fetcher: questionTts,
      swSpeechEnd: _swTTS,
    );
    _revealForReading(aiIdx, aiText.trim()); // 🆕 긴 대사 텔레프롬프터

    // TTS 재생 완료 대기
```

---

### [E6] 새 메서드 추가 — `_scrollToCurrentTop` 바로 뒤 (≈1601)

> `_scrollToCurrentTop`의 꼬리(`alignment: 0.98 ...`)를 앵커로, 그 닫는 `}` 다음에 두 메서드 삽입.

**OLD:**
```dart
      Scrollable.ensureVisible(
        ctx,
        alignment: 0.98,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOut,
      );
    });
  }
```

**NEW:**
```dart
      Scrollable.ensureVisible(
        ctx,
        alignment: 0.98,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOut,
      );
    });
  }

  // 🆕 긴 대사 텔레프롬프터: 화면보다 길면 첫 줄을 상단에 고정한 뒤,
  //    읽는 시간(추정) 동안 서서히 맨 아래(끝줄)로 선형 글라이드.
  //    화면에 다 들어오면 기존 카톡식(_scrollToBottom) 유지.
  void _revealForReading(int index, String spokenText) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) return;
      final ctx = _itemKeys[index]?.currentContext;
      if (ctx == null) {
        _scrollToBottom();
        return;
      }
      final renderObj = ctx.findRenderObject();
      final double itemH = (renderObj is RenderBox) ? renderObj.size.height : 0;
      final double viewH = _scrollController.position.viewportDimension;
      // 화면에 다 들어오면 기존 동작
      if (itemH <= 0 || itemH <= viewH * 0.85) {
        _scrollToBottom();
        return;
      }
      // 1) 첫 줄을 화면 상단에 고정 (즉시)
      Scrollable.ensureVisible(ctx, alignment: 0.98, duration: Duration.zero);
      // 2) 읽는 시간 동안 끝줄까지 선형 글라이드
      //    (reverse 리스트에서 offset 0 = 맨 아래)
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!_scrollController.hasClients) return;
        _scrollController.animateTo(
          0,
          duration: Duration(milliseconds: _estimateReadMs(spokenText)),
          curve: Curves.linear,
        );
      });
    });
  }

  // 읽는 시간 추정 (OpenAI TTS-1 영어 ≈ 14자/초). 살짝 짧게 잡아 끝줄이 약간 먼저 도착.
  // 글라이드가 너무 빠르면 값을 낮추고, 너무 느리면 값을 올린다.
  static const double _kReadCharsPerSec = 14.0;
  int _estimateReadMs(String text) {
    final int n = text.trim().length;
    if (n <= 0) return 1500;
    final int ms = (n / _kReadCharsPerSec * 1000).round();
    return ms.clamp(1500, 25000);
  }
```

---

### [E7] 초기 AI 질문 — onStreamEnd 직후 (≈706, `while (questionTts...` 앵커)

**OLD:**
```dart
    await questionHybridTts.onStreamEnd(
      fullSentence: aiText.trim(),
      remainderBuffer: aiBuffer,
      fetcher: questionTts,
      swSpeechEnd: _swTTS,
    );

    int ticks = 0;
    while (questionTts.pendingRequests > 0 || _ttsQueueManager.isBusy) {
```

**NEW:**
```dart
    await questionHybridTts.onStreamEnd(
      fullSentence: aiText.trim(),
      remainderBuffer: aiBuffer,
      fetcher: questionTts,
      swSpeechEnd: _swTTS,
    );
    _revealForReading(aiIdx, aiText.trim()); // 🆕 긴 대사 텔레프롬프터

    int ticks = 0;
    while (questionTts.pendingRequests > 0 || _ttsQueueManager.isBusy) {
```

---

## 검증

```bash
# 1) 새 메서드/호출 개수
grep -c "_revealForReading" routine_mode_step_expand.dart   # 기대: 6 (정의1 + 호출5)
grep -c "_estimateReadMs"   routine_mode_step_expand.dart   # 기대: 2 (정의1 + 호출1)

# 2) 말풍선 상단 이동 확인
grep -n -A3 "_buildSeedHintBalloon" routine_mode_step_expand.dart
#   기대: return Positioned( 다음 줄에 top: 8,

# 3) AI 확장 2곳이 교체됐는지 (PIPE-08 / v3.8 앵커 주변)
grep -n -B1 "_log('🧠 \[PIPE-08\]'" routine_mode_step_expand.dart   # 위에 _revealForReading
grep -n -B1 "// \[v3.8\] AI 한국어 단일 호출 통합" routine_mode_step_expand.dart  # 위에 _revealForReading

# 4) 정적 분석
flutter analyze
#   기대: No issues found
```

> `RenderBox` 미정의 에러가 나면(드뭄) 파일 상단 import에 `import 'package:flutter/rendering.dart';` 한 줄 추가. 보통 `material.dart`/`widgets.dart`가 이미 re-export 하므로 불필요.

---

## 포맷 (반드시 단일 파일)

```bash
dart format routine_mode_step_expand.dart
```
⚠️ 폴더 대상 금지(한글 문자열 UTF-8 손상 위험).

---

## 롤백

```bash
git checkout HEAD -- routine_mode_step_expand.dart
```

---

## 기기 테스트 체크리스트 / 튜닝

1. **짧은 대사**: 평소처럼 카톡식으로 자연스럽게 하단 표시되는지(글라이드 미발동).
2. **화면보다 긴 대사**(작은 폰): 첫 줄이 화면 최상단에 잡힌 뒤 읽는 동안 서서히 위로 올라가 끝줄에서 멈추는지.
3. **동기화 미세 조정**: 글라이드가 소리보다 빠르면 `_kReadCharsPerSec`를 **낮추고**(예 12), 느리면 **올린다**(예 16).
4. **첫 줄 고정 위치**: 너무 위/아래면 `_revealForReading`의 `alignment: 0.98` 값을 조정(0.9~1.0).
5. **발동 임계값**: 살짝 넘치는 대사도 글라이드시키려면 `viewH * 0.85`의 0.85를 낮춘다.

## 알려진 한계 (의도된 동작)

- 스트리밍 중에는 기존 `_scrollToBottom`이 텍스트를 따라가고, 스트림 완료 시점에 첫 줄 고정→글라이드가 시작됩니다(짧은 점프 1회).
- AI 확장은 소리가 글자보다 먼저 시작될 수 있어, 생성이 많이 지연되는 긴 답변에선 글라이드가 소리보다 약간 뒤처질 수 있습니다(추정 동기화의 본질적 한계). 끝줄 정렬은 항상 보장됩니다.