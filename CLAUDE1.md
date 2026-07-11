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

최종 결론

Codex의 B안 선택은 맞습니다. Phase 2로 진행해도 되지만, 구현 목표는 단순한 조회 함수 하나가 아니라 다음 구조여야 합니다.

Google·카카오 기존 계정 조회 전용 함수
발견 계정 최종 로그인 전용 함수
이메일 계정 확인 시 기본 Auth 세션을 건드리지 않는 방식
조회·로그인 어느 단계에서도 생성·연결·매핑 변경 금지
신규가입은 기존 계정 탐색과 완전히 분리

다음 지시문을 Codex에 전달하는 것이 좋습니다.

StealthVox 계정 찾기 Phase 2 구현 지시문

Phase 0·1 진단 결과를 승인한다. 권장한 B안인 서버 토큰 검증 기반으로 Phase 2를 진행한다.

단, 구현 전에 아래 보완 원칙을 설계에 반영하고, 이 원칙을 벗어나는 변경이 필요하면 코드를 수정하기 전에 보고하라.

1. 핵심 목표

‘내 계정 찾아보기’에서는 기존 StealthVox 계정의 존재와 자료 요약만 확인한다.

계정 찾기 과정에서는 다음 부수효과가 절대 발생하지 않아야 한다.

Firebase Auth 신규 사용자 생성
provider UID 매핑 생성 또는 변경
이메일 기반 자동 연결
Google·카카오 계정 연결
익명 계정 연결
정식 users 문서 생성
가입 보너스 지급
birthYear 또는 보호자 동의 흐름 자동 실행
RevenueCat 사용자 전환
Lobby 이동
잔여시간 또는 히스토리 변경
2. 기존 함수 재사용 제한

다음 기존 함수는 계정 찾기 단계에서 직접 호출하지 않는다.

linkOrCreateAccount
kakaoCustomAuth
linkProviderToCurrentAccount
createProviderLinkTicket
consumeProviderLinkTicket
기타 신규 사용자 생성·provider 연결·매핑 변경 가능성이 있는 함수

최종 계정 선택 후에도 위 함수가 신규 생성이나 자동 연결을 수행할 가능성이 있다면 그대로 재사용하지 않는다.

기존 계정 전용 로그인 함수를 별도로 구현한다.

3. Google·카카오 조회 전용 callable

Google과 카카오의 계정 확인에는 조회 전용 callable을 추가한다.

개념적 역할:

사용자가 직접 제공자 인증을 완료
전달받은 provider 토큰 검증
provider 고유 사용자 ID 추출
기존 provider_uid_map 또는 kakao_uid_map 조회
기존 매핑이 있는 경우에만 Firebase UID 확인
users/{uid} 및 관련 자료를 읽기 전용으로 조회
마스킹된 계정 요약과 발견 계정 티켓 반환
매핑이 없으면 not_found 반환

이 callable에서는 다음을 금지한다.

Firebase Auth 사용자 생성
getUserByEmail을 이용한 다른 계정 자동 탐색
이메일이 같다는 이유로 기존 UID 선택
provider 매핑 생성
provider 매핑 수정
anonymous UID 연결
Custom Token 발급
users 문서 생성
Firestore 데이터 수정
4. 발견 계정 티켓

조회 결과에 Firebase UID, provider UID, Google sub, Kakao ID 또는 내부 문서 경로를 그대로 노출하지 않는 방식을 우선한다.

서버가 짧은 유효기간의 서명된 discovery ticket 또는 동등한 불투명 토큰을 반환하도록 설계한다.

티켓에는 최소한 다음 검증 정보가 서버 측에서 확인 가능해야 한다.

provider
발견된 기존 Firebase UID
provider 고유 ID
발급 시각
만료 시각
일회성 또는 재사용 제한 정보

클라이언트에는 다음과 같은 표시용 정보만 반환한다.

로그인 제공자
마스킹된 계정 정보
남은 시간
히스토리 개수 또는 존재 여부
마지막 사용일이 확인 가능하면 해당 값
discovery ticket

현재 프로젝트 구조에서 서명 티켓보다 서버 저장형 단기 세션 문서가 더 안전하면 그 방식을 선택할 수 있다. 선택 이유를 보고한다.

5. 최종 로그인 전용 callable

사용자가 발견된 계정에서 ‘이 계정으로 계속하기’를 선택하면 기존 계정 전용 로그인 callable을 사용한다.

개념적 역할:

discovery ticket 검증
만료·위변조·provider 일치 여부 검증
Google 또는 카카오 토큰을 다시 검증
현재 provider 고유 ID가 조회 당시 계정과 동일한지 확인
기존 매핑이 여전히 동일한 Firebase UID를 가리키는지 재확인
기존 users/{uid} 회원 상태 재확인
해당 기존 UID에 대한 Firebase Custom Token 발급
클라이언트가 Custom Token으로 기본 Firebase Auth에 최종 1회 로그인

최종 로그인 callable에서도 다음을 금지한다.

신규 Firebase Auth 사용자 생성
provider 매핑 생성·변경
이메일 기반 자동 연결
다른 UID 선택
기존 계정이 없을 때 신규가입으로 자동 전환
데이터 병합 또는 이전

조회 이후 매핑이나 회원 상태가 달라졌으면 로그인하지 말고 명확한 오류를 반환한다.

6. 이메일 계정 확인

이메일 계정 확인 때문에 기본 Firebase Auth 세션과 RevenueCat 사용자가 변경되면 안 된다.

우선 다음 방식을 검토한다.

계정 찾기 전용 secondary Firebase App/FirebaseAuth 인스턴스 생성
secondary Auth에서 signInWithEmailAndPassword 수행
인증된 UID로 기존 회원 자료 조회
기본 Auth와 main.dart auth stream에는 영향 없음
확인 완료 또는 화면 종료 시 secondary Auth 로그아웃 및 안전한 정리
사용자가 이메일 계정을 최종 선택하면 기본 Auth에서 다시 정식 로그인

secondary Firebase Auth가 현재 Flutter/Firebase 초기화 구조와 안정적으로 공존하지 못하면 임의로 비밀번호를 Cloud Function에 전달하지 말라.

그 경우 이메일 계정 확인은 다음 중 더 안전한 방식으로 제한할 수 있다.

이메일 로그인 성공 시 해당 이메일 계정으로 바로 계속하는 별도 흐름
P1에서는 Google·카카오 계정 비교만 제공하고 이메일은 기존 로그인·비밀번호 재설정 경로로 안내

선택한 방식과 이유를 보고한다.

7. 기존 회원 판정

users/{uid} 문서가 없으면 기존 StealthVox 회원으로 표시하지 않는다.

현재 확인된 필드를 기준으로 기존 회원 판정 기준을 명확히 정의한다.

최소한 다음을 구분한다.

Firebase Auth만 존재하고 users 문서가 없는 계정
users 문서와 실제 회원 자료가 있는 계정
birthYear가 미완료인 가입 중 계정
parentConsentPending 상태
remainingTime이 0이지만 히스토리가 있는 계정
remainingTime과 히스토리가 모두 없는 빈 계정
anonymous 체험 계정

현재 필드만으로 정식 회원과 빈 계정을 안전하게 구분할 수 없다면 Phase 2 구현 전에 최소 보강안을 보고한다.

임의의 signupCompleted 또는 accountStatus 필드를 바로 추가하지 않는다.

8. 히스토리 요약

users/{uid}/chat_history를 전부 내려받지 않는다.

서버에서 다음 중 현재 Firestore 구조와 비용에 적합한 방식을 선택한다.

count aggregate
제한된 최신 문서 조회
기존 요약 필드 사용
자료 존재 여부만 확인

마지막 사용일 전용 필드가 없으면 최신 chat_history.created_at을 제한 조회할 수 있다.

대규모 읽기가 발생하지 않도록 한다.

9. RevenueCat

계정 찾기 단계에서는 기본 Firebase Auth 세션을 변경하지 않으므로 main.dart의 RevenueCat auth stream이 작동하지 않아야 한다.

최종 계정 선택 후 Custom Token 로그인에 성공했을 때만 기존 auth stream 또는 명시적 보강 로직으로 RevenueCat을 해당 Firebase UID에 동기화한다.

다음을 테스트한다.

계정 찾기 중 RevenueCat App User ID 변경 없음
최종 선택 전 CustomerInfo 변경 없음
최종 로그인 후 선택한 Firebase UID로 동기화
이전 사용자의 entitlement 또는 캐시가 화면에 노출되지 않음
10. UI

기존 Intro를 전면 재작성하지 말고 현재 구조를 최대한 유지한다.

추가 기능:

‘내 계정 찾아보기’ 진입
Google 계정 확인
카카오 계정 확인
이메일 계정 확인 또는 안전한 대체 경로
확인된 계정별 결과 카드
복수 계정 별도 표시
사용자가 직접 계정 선택
기록 없는 계정 안내
신규 계정 만들기 확인
고객지원 안내

복수 계정을 자동 선택하거나 정렬 결과를 추천 계정으로 표현하지 않는다.

11. 기존 provider linking 코드

기존 provider linking 관련 코드는 이번 Phase 2에서 무조건 삭제하지 않는다.

다음 두 유형으로 분류해 보고한다.

A. 정식 Google·카카오·이메일 계정을 서로 연결하거나 병합하는 코드
B. anonymous 체험 사용자가 명시적으로 신규가입할 때만 사용되는 전환 코드

A 유형은 새 정책과 충돌하므로 호출 차단·비활성 또는 후속 제거 대상으로 분류한다.

B 유형은 현재 체험 정책과 실제 동작을 확인한 뒤 유지 또는 제거를 판단한다.

이름에 link가 포함됐다는 이유만으로 일괄 삭제하지 않는다.

12. 구현 권한

위 안전 원칙 안에서 Codex는 현재 코드 구조에 가장 적합한 세부 구현을 선택할 수 있다.

허용:

account discovery 전용 서비스·모델·위젯 파일 추가
조회 및 최종 로그인 callable 분리
짧은 수명의 discovery ticket 구조 추가
필요한 보안 검증과 오류 타입 추가
최소한의 상태 관리 리팩터링
테스트 코드 및 안전한 진단 로그 추가
Intro 내 상태 방식 또는 독립 페이지 방식 선택

사전 보고가 필요한 변경:

기존 UID 구조 변경
사용자 데이터 마이그레이션
기존 provider 매핑 형식 변경
RevenueCat App User ID 변경
기존 정식 회원 데이터 수정·삭제
provider linking 재도입
계정 병합
이메일·전화번호 동일인 추정
인증 provider 설정 변경
13. 구현 순서
구현 전 세부 설계 확정
조회 전용 callable
발견 계정 티켓
최종 로그인 전용 callable
Google 계정 확인 클라이언트 흐름
카카오 계정 확인 클라이언트 흐름
이메일 확인 안전 방식
결과 카드 및 복수 계정 UI
최종 선택 로그인
신규가입 확인 분기
RevenueCat 및 로컬 상태 검증
계정 연결 잔존 코드 호출 차단 점검
자동 테스트
실기기 테스트 항목 보고
14. 완료 조건
계정 조회 과정에서 Firebase Auth 신규 사용자가 생성되지 않음
계정 조회 과정에서 provider 매핑이 생성·변경되지 않음
계정 조회 과정에서 기본 Firebase 세션이 변경되지 않음
계정 조회 과정에서 RevenueCat 사용자가 변경되지 않음
복수 계정이 독립적으로 표시됨
자동 병합·합산·이전이 없음
최종 선택한 기존 계정으로만 Firebase 로그인됨
최종 로그인 함수가 신규 사용자를 만들지 않음
이메일 확인이 기본 Auth 세션을 오염시키지 않음
네트워크·권한·토큰 오류를 기록 없음으로 처리하지 않음
기존 로그인·체험·보호자 동의 흐름에 회귀 오류가 없음
flutter analyze 통과
관련 자동 테스트 통과
Google·카카오·RevenueCat 실기기 검증 결과 또는 미검증 항목이 명확히 보고됨

Phase 2를 진행하되, 먼저 위 보완사항을 반영한 세부 구현 계획을 짧게 보고한 다음 작업하라. 안전 원칙 안의 파일 분리, 상태 관리 및 함수 구조는 현재 코드에 맞춰 Codex가 선택할 수 있다.

이 지시문이면 Codex에게 충분한 구현 권한을 주면서도, 가장 위험한 자동 생성·자동 연결·Auth 세션 오염은 확실히 차단할 수 있습니다.