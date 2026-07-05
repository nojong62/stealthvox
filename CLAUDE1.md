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
- 앱 실행/빌드 가능성을 최우선으로 하되, 빌드할지는 먼저 물어 봐.
- 불확실한 부분은 임의 삭제하지 말고 보고할 것

이 내용을 항상 기억하고 지시문에 포함해 줘.
=================================
지시문 

# StealthVox 멀티 에이전트 Architecture QA — Intro A/B 분리 전 진단

## 목적

현재 StealthVox의 `intro_master.dart`를 중심으로, 체험 인트로와 일반 로그인/회원가입 인트로를 분리하기 전에 발생 가능한 상태 충돌을 실제 코드 기준으로 진단해 주세요.

중요: 이번 작업에서는 코드를 수정하지 마세요.
먼저 실제 파일/함수/상태값을 추적해서 진단 리포트만 작성해 주세요.

---

# 현재 구조 이해

현재 인트로는 완전히 별도 페이지 2개가 아니라, `IntroMaster` 내부에서 체험 화면과 가입/로그인 화면이 전환되는 구조입니다.

앞으로 목표는 다음과 같습니다.

## Intro A — 체험 전용 인트로

* 신규 사용자 또는 비회원 대상
* 1분 Anyone 체험 시작
* 언어 설정
* anonymous auth 가능
* 체험용 history 생성
* StealthRoom 진입
* 체험 종료 후 공부방/History 체험
* 이후 가입 유도

## Intro B — 일반 로그인/회원가입 인트로

* 기존 회원 로그인
* 신규 회원가입
* Google/Kakao/email 로그인
* 회원은 Lobby 진입
* 체험 완료자는 가입 후 보너스 지급
* 일반 회원은 체험 플로우를 반복하지 못해야 함

---

# 반드시 확인할 현재 코드 포인트

다음 항목을 실제 코드 위치와 함께 확인해 주세요.

1. `_isSignupMode`

   * 체험 화면과 가입 화면을 어떻게 전환하는지
   * `FFAppState().trialCompleted`와 어떤 관계인지
   * Intro A/B 분리 시 이 상태가 어떤 문제를 만들 수 있는지

2. `_checkEntryStatus()`

   * pending invite 우선순위
   * 기존 로그인 사용자 라우팅
   * AppsFlyer 초기화 순서
   * Duo invite가 체험 플로우보다 우선되는지

3. `_startTrial()`

   * 기존 비익명 사용자가 있을 때 `signOut()`하는 구조
   * anonymous auth 생성 조건
   * 언어 설정 이후 StealthRoom 진입 순서
   * 정식 회원이 체험 버튼을 눌렀을 때 위험 여부

4. `_enterTrialAnyone()`

   * 체험 history 문서 생성 위치
   * history 문서 필드 구성
   * `TrialFlowState.instance.myHistoryRef`
   * `TrialFlowState.instance.advanceTo(1)`
   * StealthRoom으로 전달되는 `historyRef`

5. `_handleAuth()`

   * email 가입 시 anonymous user에 대해 `linkWithCredential()`을 사용하는지
   * link 실패 시 복구 경로가 있는지
   * 가입 보너스 지급이 email 가입에서도 되는지

6. `_handleSocialAuth()`

   * Google/Kakao 로그인 시 anonymous user와 연결되는지
   * 기존 anonymous UID가 유지되는지
   * 새 UID로 바뀌는지
   * 체험 history 소유권이 유지되는지
   * `grantSignupBonus` 호출 타이밍

7. `_grantSignupBonusIfPossible()`

   * 보너스 중복 지급 방지 여부
   * 실패 시 사용자 상태
   * `remainingTime`
   * `remainingTimeLoaded`
   * `LobbyBrain.lastSyncedUid`

8. `_routeAfterAuth()`

   * pending duo invite가 있을 때 StealthRoom으로 이동하는지
   * pending 값 초기화 시점
   * 일반 가입 후 Lobby 이동
   * 체험 후 가입 사용자가 엉뚱한 Room으로 이동할 가능성

9. `TrialFlowState`

   * trial step이 boolean 수준인지, 단계형 상태인지
   * 앱 재실행 후 복원 여부
   * 체험 대화방 완료와 공부방 완료를 구분할 수 있는지

10. FFAppState 관련

* `trialCompleted`
* `remainingTime`
* `remainingTimeLoaded`
* `pendingInviteType`
* `duoRoomId`
* `nativeLang`
* `targetLang`

---

# 멀티 에이전트 역할

아래 12개 에이전트 관점으로 같은 코드를 교차검증해 주세요.

## 1. UX Agent

사용자가 체험 → 공부방 → 가입 → Lobby 흐름에서 혼란을 느끼는 지점을 찾습니다.

## 2. State Machine Agent

Guest / Trial / Anonymous / Member / Paid User 상태 전이가 명확한지 봅니다.

## 3. Navigation Agent

Intro A → StealthRoom → History → Intro B → Lobby 이동이 안전한지 봅니다.

## 4. Authentication Agent

Anonymous auth, Email link, Google/Kakao auth, 기존 회원 로그인, 중복 계정 문제를 검토합니다.

## 5. Billing Agent

체험 중 과금 금지, 가입 보너스, Room 진입 전 과금 금지, remainingTime 동기화를 검토합니다.

## 6. History Agent

체험 history 생성, 소유권, 가입 후 보존, 고아 문서 발생 가능성을 검토합니다.

## 7. Audio Pipeline Agent

체험 중 STT → GPT → TTS → 재생 → History 저장 순서가 깨질 가능성을 검토합니다.

## 8. DeepLink Agent

pendingInviteType, duoRoomId, AppsFlyer deferred deep link, 체험 플로우 충돌을 검토합니다.

## 9. Firebase Agent

Firestore 문서 생성, Cloud Function 호출, user doc 생성, 보너스 지급, 마이그레이션 필요 여부를 검토합니다.

## 10. Security Agent

비회원 권한, history 접근 권한, API 호출 노출, 클라이언트 remainingTime 조작 가능성을 검토합니다.

## 11. Timing/Concurrency Agent

timer, auth callback, route transition, TTS 완료, billing tick, lifecycle pause/resume 간 경합 조건을 검토합니다.

## 12. Judge Agent

모든 에이전트 의견을 종합하여 위험도와 수정 우선순위를 판정합니다.

---

# 파일럿 시나리오: SV-INTRO-001

## 시나리오 이름

비회원 → 1분 체험 → 공부방 체험 → 회원가입 → 보너스 지급 → Lobby 진입

## 시작 상태

* 앱 신규 설치
* FirebaseAuth currentUser 없음
* `trialCompleted=false`
* `remainingTime=0` 또는 미로드
* `remainingTimeLoaded=false`
* `pendingInviteType=''`
* `duoRoomId=''`
* 체험 history 없음
* 앱은 Intro A 체험 화면 표시

## 행동 시퀀스

1. 사용자가 Intro A에서 “1분 무료 체험 시작”을 누른다.
2. 언어 설정 팝업에서 모국어와 학습 언어를 선택한다.
3. anonymous auth가 생성된다.
4. 체험용 history 문서가 생성된다.
5. StealthRoom 또는 Anyone 체험방으로 이동한다.
6. 사용자가 1분 동안 체험 대화를 한다.
7. 1분 체험이 종료된다.
8. 체험 history 또는 공부방으로 이동한다.
9. 공부방 체험이 종료된다.
10. Intro B 가입/로그인 화면으로 이동한다.
11. 사용자가 Google/Kakao/email 중 하나로 회원가입한다.
12. 가입 보너스가 지급된다.
13. Lobby로 이동한다.
14. 사용자가 Room 또는 Store로 이동하려고 한다.

## 기대 종료 상태

* 사용자는 정식 Member 상태
* anonymous 상태가 안전하게 정리되거나 정식 계정에 연결됨
* 체험 history가 회원 계정에 유지됨
* `trialCompleted=true`
* `remainingTime`은 가입 보너스 지급 후 값
* `remainingTimeLoaded=true`
* Intro A 재체험 불가
* Billing은 아직 시작되지 않음
* Room 진입 시에만 과금 시작 가능
* pending invite 값이 남아 있으면 안 됨

---

# 분기 시나리오

## SV-INTRO-001-a: 체험 중 앱 강제 종료

1. Intro A에서 체험 시작
2. anonymous auth 생성
3. StealthRoom 진입
4. 체험 30초 경과
5. 앱 강제 종료
6. 앱 재실행

확인:

* 체험 시간이 리셋되는가
* anonymous user가 유지되는가
* historyRef가 복원되는가
* Intro A로 다시 가는가, StealthRoom으로 복귀하는가, Intro B로 가는가
* 중복 체험 가능성이 생기는가

## SV-INTRO-001-b: 체험방 진입 후 아무 말도 하지 않고 종료

1. 체험 시작
2. history 문서 생성
3. 사용자가 아무 말도 하지 않음
4. 체험 종료

확인:

* 빈 history 문서가 남는가
* 공부방으로 보낼 수 있는 데이터가 있는가
* 빈 history를 삭제해야 하는가
* 가입 후 빈 history가 보이는가

## SV-INTRO-001-c: 회원가입 중 네트워크 끊김

1. 체험 완료
2. Intro B 이동
3. Google/Kakao/email 가입 시작
4. 인증 중 네트워크 끊김
5. 앱 재시작

확인:

* anonymous user가 남는가
* 정식 user가 생성됐는데 Firestore user doc이 없는 반쪽 계정이 생기는가
* 보너스 지급이 중복될 수 있는가
* 사용자는 다시 가입 버튼을 눌러야 하는가

## SV-INTRO-001-d: email linkWithCredential 실패

1. anonymous user 상태
2. email 회원가입 시도
3. 이미 사용 중인 email이어서 `linkWithCredential` 실패

확인:

* historyRef가 유지되는가
* 사용자는 기존 계정 로그인으로 전환 가능한가
* 기존 계정 로그인 후 체험 history를 마이그레이션하는가
* 그냥 실패 메시지만 뜨고 체험 기록이 고아가 되는가

## SV-INTRO-001-e: Google/Kakao 로그인 후 UID 변경

1. anonymous user 상태에서 체험 완료
2. Google 또는 Kakao로 가입
3. 로그인 후 FirebaseAuth UID가 변경됨

확인:

* 체험 history가 이전 anonymous UID 아래에 남는가
* 새 회원 계정에서 history를 볼 수 있는가
* migration 함수가 있는가
* 없다면 구조적 위험도는 어느 정도인가

## SV-INTRO-001-f: 보너스 지급 Cloud Function 실패 또는 지연

1. 회원가입 성공
2. `grantSignupBonus` 호출
3. Cloud Function 실패 또는 5초 이상 지연
4. 사용자는 Lobby로 이동

확인:

* remainingTime이 0으로 보이는가
* 나중에 보너스가 반영되는가
* 사용자가 Store로 오해해서 이동하는가
* 중복 호출 시 보너스가 두 번 지급되는가

## SV-INTRO-001-g: 기존 회원이 체험 버튼을 누름

1. 이미 로그인된 정식 회원
2. Intro A 접근
3. “1분 무료 체험 시작” 클릭

확인:

* 현재 코드처럼 signOut 후 anonymous로 바뀌는가
* 기존 회원 세션이 끊기는가
* 기존 회원의 remainingTime/History 접근에 문제가 생기는가
* 정식 회원은 체험 Intro A 접근 자체를 막아야 하는가

## SV-INTRO-001-h: pending duo invite가 남아 있는 상태에서 체험 시작

1. `pendingInviteType='duo'`
2. `duoRoomId` 존재
3. 사용자가 Intro A에서 체험 시작
4. 체험 후 가입

확인:

* 체험 중 갑자기 StealthRoom Duo로 이동하는가
* 가입 후 Lobby가 아니라 Duo Room으로 이동하는가
* 체험 플로우 진입 시 pending invite를 초기화해야 하는가
* 또는 duo invite가 체험보다 우선되어야 하는가

## SV-INTRO-001-i: 체험 완료 후 뒤로가기

1. 체험 완료
2. Intro B 가입 화면 진입
3. 사용자가 뒤로가기 시도

확인:

* Intro A로 돌아가 재체험 가능한가
* `trialCompleted`일 때 뒤로가기 버튼이 막히는가
* 시스템 back 버튼은 어떻게 동작하는가
* Navigation stack에 StealthRoom이 남아 있는가

---

# 출력 형식

다음 형식으로 리포트를 작성해 주세요.

## 1. 관련 파일 목록

실제 확인한 파일과 역할을 적어 주세요.

## 2. 현재 코드 흐름 요약

정상 경로를 함수 단위로 요약해 주세요.

## 3. 에이전트별 검증 결과

각 에이전트가 발견한 문제를 분리해서 적어 주세요.

## 4. 치명/높음/중간/낮음 위험 목록

각 위험에 대해 다음을 포함해 주세요.

* 위험명
* 발생 조건
* 영향
* 실제 코드 근거
* 수정 필요 위치
* 권장 수정 방향

## 5. 상태 머신 제안

Intro A/B 분리 후 필요한 상태값을 제안해 주세요.

예:

* trialStep
* anonymousUid
* trialHistoryDocId
* trialStartedAt
* trialRoomCompletedAt
* trialStudyCompletedAt
* trialMigratedToUid
* trialMigrationStatus

## 6. Codex 판단

각 시나리오에 대해 다음 중 하나로 판정해 주세요.

* PASS: 현재 코드상 안전함
* FAIL: 현재 코드상 오류 가능성 높음
* UNKNOWN: 관련 코드가 부족하거나 추적 불가
* DESIGN GAP: 코드 문제가 아니라 설계 정의가 없음

## 7. 다음 수정 지시문에 포함해야 할 항목

아직 코드는 수정하지 말고, 다음 단계에서 수정 지시문을 만들기 위해 필요한 항목만 정리해 주세요.
