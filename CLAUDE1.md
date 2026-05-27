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



StealthVox 사용자 Usage 화면 요약형 개편 지시문

수정 대상:

lib/custom_code/widgets/store_master.dart

목표:

현재 사용자용 Usage 화면이 초 단위 로그처럼 너무 자세하게 보인다.
정식 앱 기준으로 사용자에게는 상세 로그가 아니라 요약형 사용 내역을 보여주도록 변경한다.

단, 관리자용 Admin Time Log는 기존처럼 초 단위 상세 로그를 유지한다.


---

1. 기본 방향

사용자용 Usage는 다음 3개 중심으로 개편한다.

1. 오늘 사용 시간
2. 이번 주 사용 시간
3. 최근 세션

그리고 사용 시간을 다음 2개 그룹으로 구분한다.

대화방
공부방


---

2. 그룹 분류 기준

usage_logs의 mode 값을 기준으로 분류한다.

대화방 그룹

다음 mode는 대화방으로 분류한다.

duo
stealth_room

사용자 표시명:

대화방

영어 UI면:

Talk Room


---

공부방 그룹

다음 mode는 공부방으로 분류한다.

roleplay
clone
step_expand
study_room
history
history_list
chat_history
ai_practice

사용자 표시명:

공부방

영어 UI면:

Study Room


---

3. 사용자 Usage에서 숨길 정보

사용자용 Usage에는 아래 정보를 직접 표시하지 않는다.

초 단위 세부 로그
2s 사용 같은 짧은 기록
rate
before_seconds
after_seconds
room_id
mode 원문
Firestore 경로
debug 문구

이 정보는 관리자용 Admin Time Log에만 유지한다.


---

4. 짧은 기록 숨김

사용자용 Usage에서는 너무 짧은 기록을 숨긴다.

기준:

actual_seconds < 10

또는 actual_seconds가 없으면:

seconds_used < 10

이 기록은 사용자 Usage 목록/요약에서 제외한다.

단, 관리자용 Admin Time Log에서는 그대로 보여준다.


---

5. 오늘 사용 시간 요약

Usage 상단에 오늘 사용 시간 요약 카드를 추가한다.

표시 예:

Today
대화방 12m
공부방 28m

영어 UI면:

Today
Talk Room 12m
Study Room 28m

계산 기준:

created_at이 오늘인 usage_logs
actual_seconds 기준 합산
actual_seconds가 없으면 seconds_used 기준
10초 미만 기록은 제외

주의:

사용자 입장에서는 “실제 사용 시간” 기준이 자연스럽다.
차감 시간은 할인 모드 때문에 실제 시간과 다를 수 있으므로, 요약에는 기본적으로 실제 사용 시간을 쓴다.


---

6. 이번 주 사용 시간 요약

오늘 요약 아래에 이번 주 사용 시간 요약 카드를 추가한다.

표시 예:

This Week
대화방 1h 10m
공부방 2h 35m

계산 기준:

이번 주 월요일 00:00부터 현재까지
actual_seconds 기준 합산
actual_seconds가 없으면 seconds_used 기준
10초 미만 기록 제외


---

7. 최근 세션

요약 아래에 최근 세션을 보여준다.

표시 개수:

최근 5개

표시 예:

Recent Sessions

공부방 · 14m
2026.05.26 16:33

대화방 · 7m
2026.05.26 15:10

공부방 · 실제 10m 사용 · 5m 차감
2026.05.26 14:20

최근 세션 기준:

created_at 최신순
10초 미만 기록 제외
최대 5개


---

8. 할인/차감 시간 표시 방식

일반 세션은 단순히 실제 사용 시간만 표시한다.

공부방 · 14m
대화방 · 7m

다만 실제 사용 시간과 차감 시간이 다르면 이렇게 표시한다.

공부방 · 실제 10m 사용 · 5m 차감

조건:

actual_seconds != seconds_used

단, 초 단위가 너무 자세히 보이지 않게 1분 이상은 분 단위 중심으로 반올림 또는 자연 표시한다.

예:

29s → 30s
74s → 1m
134s → 2m
3600s → 1h


---

9. 시간 표시 함수

사용자용 시간 표시 함수는 기존 초 단위 상세 함수와 분리한다.

추가 함수 예:

String _formatUsageDurationForUser(int seconds)

표시 규칙:

0~59초 → 30s, 45s 정도로 표시 가능
1분 이상 → 1m, 2m, 14m
1시간 이상 → 1h 20m

단, 10초 미만은 Usage에서 제외하므로 거의 표시되지 않는다.

관리자용 Admin Time Log는 기존 상세 _formatDurationFromSeconds()를 유지한다.


---

10. UI 구조

사용자용 Usage 시트 구조를 다음처럼 만든다.

📊 Usage

[Today]
Talk Room    12m
Study Room   28m

[This Week]
Talk Room    1h 10m
Study Room   2h 35m

[Recent Sessions]
Study Room · 14m
2026.05.26 16:33

Talk Room · 7m
2026.05.26 15:10

현재 앱이 한국어 중심이면:

📊 Usage

[Today]
대화방    12m
공부방    28m

[This Week]
대화방    1h 10m
공부방    2h 35m

[Recent Sessions]
공부방 · 14m
2026.05.26 16:33

버튼명은 기존처럼 Usage 유지.


---

11. 데이터 조회

기존과 동일하게:

users/{uid}/usage_logs

최신순 조회는 유지한다.

요약 계산을 위해 충분한 기간을 가져온다.

권장:

최근 200개 또는 최근 30일

현재 구현이 최신순 100건이면 우선 200건으로 늘려도 된다.

단, 과도한 읽기 비용이 생기지 않도록 무제한 조회 금지.


---

12. 빈 상태

사용자용 Usage에 표시할 유효 기록이 없으면:

No usage history yet.
Your usage will appear here after a session.

또는 한국어:

아직 사용 내역이 없습니다.
대화를 시작하면 사용 시간이 이곳에 표시됩니다.


---

13. 관리자 Time Log 유지

중요:

_openAdminTimeLogSheet()는 기존대로 유지한다.

관리자용에서는 계속 다음 정보를 볼 수 있어야 한다.

mode 원문
rate
actual_seconds
seconds_used
before_seconds
after_seconds
room_id
created_at
10초 미만 기록

사용자용 Usage 개편 때문에 관리자용 검증 기능이 깨지면 안 된다.


---

14. 완료 기준

1. 사용자 Usage 화면이 초 단위 로그 나열 방식이 아니라 요약형으로 보인다.


2. Today 요약에 대화방/공부방 사용 시간이 구분되어 표시된다.


3. This Week 요약에 대화방/공부방 사용 시간이 구분되어 표시된다.


4. Recent Sessions는 최근 5개만 표시된다.


5. 10초 미만 기록은 사용자 Usage에서 숨겨진다.


6. 관리자용 Admin Time Log에는 10초 미만 기록도 그대로 보인다.


7. 사용자용 Usage에는 rate, before_seconds, after_seconds, room_id, mode 원문이 노출되지 않는다.


8. 실제 사용 시간과 차감 시간이 다르면 “실제 Xm 사용 · Ym 차감” 형태로 표시된다.


9. 기존 Receipt 기능은 그대로 작동한다.


10. BillingTicker와 usage_logs 저장 로직은 건드리지 않는다.


11. 신규 flutter analyze 오류가 없어야 한다.


12. APK/AAB 빌드는 하지 않는다.




---

핵심은 이겁니다.

사용자 Usage = 요약 리포트
관리자 Time Log = 상세 검증 로그

이렇게 나누면 정식 앱에서도 부담 없이 유지할 수 있습니다.