StealthVox 프로젝트 가이드 (FlutterFlow)

 📂 파일 위치 및 위젯 리스트
 모든 화면(Pages): `lib/` 폴더 내 각 이름별 폴더
 커스텀 액션: `lib/custom_code/actions/`
 전역 상태: `lib/app_state.dart`

 🛠️ 커스텀 위젯 (`lib/custom_code/widgets/`)
현재 구현된 위젯 파일들 (새 작업 시 참고):

 ⚙️ AI 작업 규칙
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

StealthVox Billing 정책 및 BILLING DEBUG LOG 시스템 수정 지시문

목표:
현재 BillingTicker 기반 시간 차감 시스템을
StealthVox 실제 서비스 정책 기준으로 정리하고,
Billing 동작을 실시간 검증 가능한 DEBUG LOG 시스템 추가.

==================================================
1. 최종 Billing 정책
==================================================

[100% 차감]
실시간 AI 대화/훈련 모드:

- Duo
- Roleplay
- Clone
- Study Room 실시간 대화
- History 내부 Tutoring
- Keepers 내부 Tutoring

의미:
실제 경과 시간 그대로 차감.

예:
10분 사용 → 10분 차감

--------------------------------------------------

[25% 차감]
복습/히스토리 체류 계열:

- 일반 ChatHistory 보기
- History 재생/복습
- Keepers 일반 복습
- 대화 기록 읽기/듣기

의미:
실제 시간의 25%만 차감.
즉 4배 오래 사용 가능.

예:
10분 사용 → 2.5분 차감

--------------------------------------------------

[차감 정지]
- Lobby
- Intro
- Store
- 앱 백그라운드 상태
- 화면 OFF 상태
- 앱 minimized 상태

==================================================
2. 백그라운드 정책
==================================================

앱이 foreground를 벗어나면:
BillingTicker pause()

앱이 다시 foreground 복귀 시:
이전 모드 기준으로 resume()

즉:
사용자가 실제 앱을 사용하지 않는 시간은 차감하지 않음.

==================================================
3. BILLING DEBUG LOG 추가
==================================================

로그 목적:
Billing 동작 검증 및 실제 운영 디버깅.

--------------------------------------------------
로그 UI 위치
--------------------------------------------------

Lobby 화면:
REMAINING TIME 카드/숫자 영역 길게 누르기

동작:
BILLING DEBUG LOG 바텀시트 열기

--------------------------------------------------
바텀시트 기능
--------------------------------------------------

- 제목:
  BILLING DEBUG LOG

- 스크롤 가능

- 로그 없으면:
  "로그가 없습니다."

- 하단:
  "로그 복사" 버튼

- Clipboard.setData 지원

- 복사 성공 SnackBar:
  "✅ BILLING 로그가 복사되었습니다"

==================================================
4. 반드시 기록할 로그
==================================================

[BILLING]
resume

[BILLING]
pause

[BILLING]
rate=full

[BILLING]
rate=quarter

[BILLING]
tick before=XXXXX after=XXXXX

[BILLING]
foreground resumed

[BILLING]
background paused

[BILLING]
firestore save success

[BILLING]
firestore save error

[BILLING]
mode=duo

[BILLING]
mode=history

==================================================
5. Billing Rate 구조
==================================================

현재 구조 점검 후:
반드시 아래 2개 상태 지원:

BillingRate.full
BillingRate.quarter

50%/half 제거.
StealthVox 정책상 사용하지 않음.

==================================================
6. 현재 코드 점검
==================================================

현재:
initState → BillingTicker.resume()
dispose → BillingTicker.pause()

구조 유지 가능.

다만:
- foreground/background lifecycle 처리 추가
- 모드별 BillingRate 정확히 적용
- History 일반 복습은 quarter 적용

필수 확인.

==================================================
7. 수정 금지 사항
==================================================

- RevenueCat 결제 로직 수정 금지
- Store purchase 로직 수정 금지
- Firestore purchases 동기화 로직 수정 금지

이번 작업은:
Billing 정책 + DEBUG LOG만 수정.

==================================================
8. 작업 후 확인
==================================================

flutter analyze 실행.

APK/AAB 빌드 금지.

==================================================
9. 작업 후 보고 항목
==================================================

반드시 보고:

1. 어떤 화면이 full인지
2. 어떤 화면이 quarter인지
3. background pause 정상 여부
4. 로그 출력 예시
5. 로그 복사 동작 여부
6. BillingTicker 변경 내용