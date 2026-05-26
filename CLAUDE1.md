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

StealthVox 스토어 사용시간 이력 버튼 추가 지시문

현재 파일:

lib/custom_code/widgets/store_master.dart

목표:

스토어 화면 상단 우측에 현재 있는 Receipt 버튼 옆 또는 아래에 사용시간 이력(Usage) 버튼을 추가한다.
사용자는 스토어에서 결제 내역뿐 아니라 실제로 시간이 언제, 어떤 모드에서, 얼마나 차감되었는지도 확인할 수 있어야 한다.

중요:

APK/AAB 빌드 명령은 실행하지 말 것.
코드 수정 후에는 flutter analyze 또는 정적 체크 수준까지만 확인할 것.
기존 결제 로직, RevenueCat 로직, 구매 복원 로직은 건드리지 말 것.
기존 Receipt 버튼과 _openReceiptSheet() 구조는 유지할 것.
새 기능은 기존 디자인 톤과 맞춰서 다크 Bento UI 스타일로 구현할 것.
1. 현재 구조 확인

store_master.dart에는 이미 다음 구조가 있다.

상단 헤더 중앙: STORE
우측: Receipt 버튼
_openReceiptSheet() 함수에서 currentUserReference!.collection('purchases')를 조회하여 구매 내역 표시
잔여시간 카드: FFAppState().remainingTime
구매 성공 시 users/{uid}/purchases에 결제 기록 저장

이 구조를 참고해서 사용시간 이력도 같은 패턴의 바텀시트로 추가한다.

2. 추가할 버튼

상단 우측 Row 내부에 Receipt 버튼 옆에 새 버튼을 추가한다.

버튼 예시:

Usage

아이콘:

Icons.history_rounded

또는

Icons.timer_outlined

버튼 색상:

Color(0xFF60A5FA)

권장 배치:

현재 구조가 좁은 화면에서 깨질 수 있으므로, 우측 Row에는 다음 순서로 둔다.

[로그 복사 아이콘] [Usage] [Receipt]

단, 화면 폭이 좁아 Overflow가 나면 TextButton.icon 대신 IconButton + tooltip 방식으로 바꿔도 된다.

3. 새 함수 추가

_openReceiptSheet() 아래 또는 위에 다음 목적의 함수를 추가한다.

void _openUsageHistorySheet()

역할:

바텀시트를 연다.
높이는 화면의 약 65~75% 정도로 한다.
제목은 ⏱ Usage History 또는 ⏱ 사용시간 이력
닫기 버튼 제공
로그인 상태가 아니면 “접근 권한이 없습니다.” 표시
사용 기록이 없으면 “사용시간 이력이 없습니다.” 표시
4. Firestore 조회 경로

우선 다음 경로를 기준으로 조회한다.

users/{uid}/usage_logs

조회 방식:

currentUserReference!
  .collection('usage_logs')
  .orderBy('created_at', descending: true)
  .limit(100)
  .snapshots()

단, 현재 프로젝트에서 실제 사용시간 차감 기록 컬렉션명이 이미 다르면, 기존 BillingTicker 또는 사용시간 차감 로직에서 쓰는 컬렉션명을 우선 사용한다.

중요:

store_master.dart 안에서 사용시간 기록을 새로 만들어내지 말고, 이미 BillingTicker 또는 방 종료 로직에서 저장한 사용 기록을 읽어서 보여주는 구조로 만든다.

5. usage_logs 문서 필드 기준

다음 필드를 우선 지원한다.

created_at: Timestamp
mode: String
seconds_used: int
rate: double 또는 String
room_id: String optional
reason: String optional
before_seconds: int optional
after_seconds: int optional

필드가 일부 없어도 화면이 깨지지 않게 기본값을 넣는다.

예시 표시:

Duo / Stealth Room
2026.05.26 18:30
- 3m 20s
잔여 42m → 38m 40s

AI 연습 모드처럼 할인 차감이 있으면 다음처럼 표시한다.

AI Practice · 0.5x
- 2m 30s charged
6. 시간 표시 유틸 함수 추가

초 단위를 보기 좋게 표시하는 내부 헬퍼를 추가한다.

기능:

65초 → 1m 5s
3600초 → 1h 0m
0초 이하 → 0s

함수명 예시:

String _formatDurationFromSeconds(int seconds)

기존 intl import는 이미 있으므로 날짜 포맷은 DateFormat('yyyy.MM.dd HH:mm')를 그대로 사용한다.

7. 바텀시트 UI 요구사항

_openReceiptSheet()와 동일한 톤으로 만든다.

스타일:

배경: Color(0xFF222222)
카드 배경: Colors.black
테두리: Colors.white10
제목: GoogleFonts.orbitron
주요 차감 시간: 파란색 또는 amber
보조 텍스트: Colors.white38, Colors.white54

각 사용 기록 카드는 다음 정보를 보여준다.

필수 표시:

mode 또는 reason
created_at
seconds_used

있으면 표시:

before_seconds → after_seconds
rate
room_id
8. 데이터가 아직 없을 때 처리

현재 앱에 usage_logs 저장 로직이 아직 없다면, 화면은 먼저 만들어두고 빈 상태 메시지를 보여준다.

빈 상태 문구:

사용시간 이력이 없습니다.
대화방 사용 후 이곳에 차감 기록이 표시됩니다.

이 경우 코드 주석으로 다음 TODO를 남긴다.

// TODO: BillingTicker 또는 방 종료 로직에서 users/{uid}/usage_logs 기록 저장 연결 필요
9. 사용시간 기록 저장 로직은 별도 파일에서 확인

이번 작업에서 store_master.dart만 수정해도 되지만, 실제 데이터가 안 뜨면 아래 파일을 확인한다.

lib/custom_code/actions/billing_ticker.dart

또는 실제 차감이 일어나는 파일.

확인 목표:

시간이 차감될 때마다 또는 세션 종료 시점에 users/{uid}/usage_logs에 기록이 저장되는지 확인
없다면 다음 필드로 저장하도록 별도 수정이 필요함

권장 저장 예시:

users/{uid}/usage_logs/{autoId}

created_at: serverTimestamp
mode: 'duo' | 'roleplay' | 'ai_practice' | 'stealth_room'
seconds_used: 실제 차감 초
actual_seconds: 실제 이용 초
rate: 1.0 또는 0.5
before_seconds: 차감 전 잔여 시간
after_seconds: 차감 후 잔여 시간
room_id: optional
reason: optional

주의:

초마다 Firestore에 쓰면 비용과 성능 문제가 생길 수 있으므로, 매초 저장하지 말 것.
권장 방식은 “세션 종료 시 1회 저장” 또는 “30~60초 단위 배치 저장”이다.
Store 화면은 읽기 전용이어야 한다.
10. 완료 기준

수정 완료 후 다음을 확인한다.

스토어 상단 우측에 Usage 버튼이 보인다.
버튼 클릭 시 사용시간 이력 바텀시트가 열린다.
로그인하지 않은 상태에서는 접근 권한 없음 메시지가 나온다.
기록이 없으면 빈 상태 메시지가 나온다.
기록이 있으면 최신순으로 표시된다.
기존 Receipt 버튼과 구매 내역 기능은 그대로 작동한다.
flutter analyze에서 새 오류가 없어야 한다.
APK/AAB 빌드는 하지 않는다.

덧붙이면, 버튼 이름은 앱 사용자 입장에서는 Usage보다 Time Log가 더 직관적입니다.
생활영어 느낌으로는 “Time Log”가 “사용시간 기록”이라는 뜻으로 짧고 자연스럽습니다.