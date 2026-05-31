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

[Duo 버그 수정] Whisper 환각(유튜브 자막) 필터 강화 — "AI 끼어듦" 착시 제거

파일: lib/custom_code/widgets/routine_mode_duo.dart

## 배경
Duo는 양방향 통역으로 정상 동작하지만, Whisper가 침묵/소음 구간에서
"Thank you so much for watching." 같은 유튜브 자막 환각을 출력하고,
이게 내 말풍선으로 떠서 마치 AI가 끼어드는 것처럼 보임.
원인: 기존 필터가 'transcript.length < 30' 조건 때문에 30자 이상 환각구를
모두 통과시킴 ("Thank you so much for watching."=31자).

## 수정 범위: _stopAndSendToWhisper 함수 내부의 환각 필터 블록 1곳만
(다른 로직/UI/DuoBrain 절대 건드리지 말 것)

### 삭제 대상
시작줄(약 333줄):  String transcript = jsonDecode(responseData)['text'] ?? "";
끝줄(약 360줄, if 블록 닫는 중괄호):        }

즉, "String transcript = ..." 줄부터
"if (lowerClean.isEmpty || isGhost || transcript.length <= 2) { ... }"
블록 전체(닫는 } 포함)까지를 삭제하고 아래 코드로 교체.

### 교체될 코드 (전체)
```dart
        String transcript = jsonDecode(responseData)['text'] ?? "";
        final String trimmed = transcript.trim();
        final String lowerRaw = trimmed.toLowerCase();
        // 영문/한글/공백만 남긴 정규화 문자열
        final String lowerClean = lowerRaw
            .replaceAll(RegExp(r'[^\w\s가-힣]'), '')
            .trim();
        // 공백까지 제거한 비교용 문자열 (짧은 환각 정확매칭용)
        final String collapsed = lowerClean.replaceAll(' ', '');

        // ① 길이 무관 강제 차단: 전형적 유튜브/자막 환각구 (부분 포함만 돼도 차단)
        const List<String> hardGhosts = [
          'thank you so much for watching',
          'thank you for watching',
          'thanks for watching',
          'please subscribe',
          'subtitles by',
          'share this video',
          '시청해 주셔서',
          '시청해주셔서',
          '구독과 좋아요',
          '감사합니다 시청',
        ];
        final bool isHardGhost =
            hardGhosts.any((g) => lowerRaw.contains(g));

        // ② 짧은 환각: 30자 미만 + 전체가 환각어와 정확히 일치할 때만 차단
        //    (contains 부분매칭의 오탐 방지 — "I am at home"의 'i' 같은 오탐 제거)
        const List<String> shortGhosts = [
          'thank you',
          'yeah',
          'okay',
          'mbc',
          'you',
          'also',
          'i',
          '감사합니다',
        ];
        final bool isShortGhost = trimmed.length < 30 &&
            shortGhosts.any((g) => collapsed == g.replaceAll(' ', ''));

        if (lowerClean.isEmpty ||
            isHardGhost ||
            isShortGhost ||
            trimmed.length <= 2) {
          await _handleContextualError();
          return;
        }
```

## 검증
1. dart analyze lib/custom_code/widgets/routine_mode_duo.dart — 에러 0
2. grep -c "transcript.length < 30" lib/custom_code/widgets/routine_mode_duo.dart — 결과 0 (옛 조건 제거 확인)
3. grep -c "hardGhosts\|shortGhosts" lib/custom_code/widgets/routine_mode_duo.dart — 결과 2 이상
4. grep -c "isHardGhost\|isShortGhost" lib/custom_code/widgets/routine_mode_duo.dart — 결과 4 이상

## 롤백
이 블록만 교체했으므로, 문제 시 위 "삭제 대상" 원본 블록으로 되돌리면 됨.