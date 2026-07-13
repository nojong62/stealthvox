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

코덱스가 관련 파일을 직접 추적하고, 로그로 효과를 검증하며, 이벤트 기반 뼈대를 훼손하지 않도록 지시문을 구성했습니다.

# StealthVox Anyone 첫 턴 반응속도 개선

## 방 입장 시 번역·TTS·오디오 경로 사전 예열

## 목표

Anyone 모드에서 사용자가 첫 발화를 마친 뒤,

* 번역된 영어 문장이 화면에 나타나기까지의 시간
* 사용자 영어 TTS가 재생되기 시작하기까지의 시간

이 이후 턴보다 현저히 느린 문제를 개선한다.

현재 로그 기준 첫 턴은 대략 다음과 같다.

* 발화 종료 → 영어 문장 표시: 약 3.2초
* 발화 종료 → 사용자 영어 음성 시작: 약 5.9초
* 이후 턴의 번역 및 TTS 호출은 첫 턴보다 빠름

따라서 첫 호출에서 발생하는 번역 경로, TTS 경로, 오디오 재생 경로의 초기화 비용을 방 입장 직후 미리 처리해 첫 실사용 턴의 지연을 줄인다.

---

# 가장 중요한 원칙

## 1. 기존 이벤트 기반 통신 뼈대를 유지한다

이번 작업은 통신 로직을 다시 설계하는 작업이 아니다.

다음 기준은 절대 훼손하지 않는다.

* 작업 완료 여부는 고정 시간 추측이 아니라 실제 완료 이벤트로 판단
* 사용자 TTS 재생 완료 이벤트 이후에만 AI 재생 게이트 개방
* AI TTS 재생 완료 이벤트 이후에만 마이크 재시작
* 이전 턴의 늦은 비동기 결과는 turn ID 또는 generation guard로 폐기
* Deepgram의 중복 `speech_final`, `UtteranceEnd` 이벤트는 한 번만 처리
* 특수 태그 및 correction/evaporate 계열 로직 유지
* `Future.delayed`를 실제 완료 판정 수단으로 사용하지 않음
* 예열 실패가 실제 대화 파이프라인 실패로 이어지지 않게 함

핵심 원칙:

> 완료 판정은 이벤트 기반으로 유지하고, 첫 실사용 전에 준비 가능한 자원만 선행 초기화한다.

---

# 작업 방식

관련 코드 위치를 미리 단정하지 말고 프로젝트 전체를 검색하여 실제 호출 경로를 먼저 파악한다.

특히 다음 파일과 연관 구조를 조사한다.

* `lib/custom_code/widgets/routine_mode_anyone.dart`
* `FreeTalkBrain`
* `streamUserTranslation`
* 사용자 TTS 큐
* AI TTS 큐
* TTS API 호출 서비스
* 오디오 플레이어 또는 MediaPlayer 래퍼
* Deepgram 연결 및 VoiceManager
* Anyone 화면의 `initState`, 모드 입장, 마이크 시작 경로
* Remote Config, Firebase Functions, API 클라이언트 초기화 경로
* 공통 HTTP client 또는 OpenAI client 재사용 여부

파일명이 다르거나 코드가 분리되어 있으면 실제 참조 관계를 따라간다.

---

# Phase 0. 현재 구조 진단

먼저 코드를 수정하지 말고 다음을 확인한다.

## A. 첫 턴 번역 호출이 느린 이유

확인 항목:

* 번역 호출마다 새 HTTP client를 생성하는지
* Cloud Function callable 또는 HTTPS 연결 객체를 매번 새로 만드는지
* 첫 호출에서만 Firebase Auth token을 가져오는지
* Remote Config를 첫 호출 시점에 읽는지
* API 키나 설정값을 첫 호출에서 lazy load 하는지
* 첫 요청에서 DNS, TLS, HTTP/2 연결이 새로 생성되는지
* `streamUserTranslation` 내부에서 최초 1회 초기화되는 객체가 있는지
* 첫 번역 호출 전에 불필요한 Firestore 또는 설정 조회가 있는지
* 번역 결과 스트림이 완료될 때까지 UI가 아무 반응도 하지 않는지

## B. 첫 사용자 TTS 호출이 느린 이유

확인 항목:

* TTS API client가 첫 호출 시 생성되는지
* 첫 TTS에서만 인증 또는 Firebase Function 초기화가 발생하는지
* TTS 큐 worker가 첫 `addText()` 호출 때 만들어지는지
* 오디오 캐시 폴더나 임시 파일 경로가 첫 호출 때 생성되는지
* 오디오 디코더 또는 플레이어가 첫 재생 시 초기화되는지
* 오디오 포커스 확보가 첫 재생 때만 수행되는지
* 플레이어 객체가 매 문장마다 새로 생성되는지
* TTS 응답을 전부 받은 뒤에야 오디오 객체를 준비하는지

## C. Anyone 입장 시점의 라이프사이클

확인 항목:

* 화면 진입 직후 `initState`
* 마이크 시작 직전
* 빌링 시작 직전 또는 직후
* Trial Anyone 진입
* 일반 회원 Anyone 진입
* 화면 재진입
* 앱 background → foreground 복귀
* dispose 후 재생성

예열을 어느 시점에 시작해야 실제 첫 발화를 방해하지 않는지 판단한다.

---

# Phase 1. 계측 로그 추가

수정 전후를 비교할 수 있도록 예열 전용 로그를 추가한다.

로그 태그 예시:

* `[WARMUP-START]`
* `[WARMUP-TRANSLATION-START]`
* `[WARMUP-TRANSLATION-OK]`
* `[WARMUP-TRANSLATION-SKIP]`
* `[WARMUP-TTS-START]`
* `[WARMUP-TTS-OK]`
* `[WARMUP-PLAYER-START]`
* `[WARMUP-PLAYER-OK]`
* `[WARMUP-FAIL]`
* `[WARMUP-END]`
* `[WARMUP-ALREADY-DONE]`

또한 첫 실사용 턴에서 다음 구간을 명확히 측정한다.

* 발화 종료 이벤트
* commit 완료
* 번역 요청 시작
* 번역 첫 결과 또는 최종 결과
* 사용자 TTS 요청
* 사용자 TTS 응답 완료
* 사용자 오디오 재생 시작
* 사용자 오디오 재생 완료
* AI 첫 청크
* AI 첫 TTS 준비
* AI 재생 시작
* AI 재생 완료

예열 작업이 실제 사용자 턴이나 채팅 기록으로 들어가지 않았다는 로그도 남긴다.

---

# Phase 2. 예열 설계

코드 구조를 확인한 뒤 가장 안전한 방식을 선택한다.

## 2-1. 번역 경로 예열

우선순위는 다음과 같다.

### 권장안 A: 실제 번역 요청 없이 연결과 설정만 초기화

가능하면 다음만 준비한다.

* 공용 HTTP client 생성
* Firebase Auth token 선조회
* Remote Config 또는 설정값 선조회
* Cloud Function callable 객체 준비
* 번역 서비스 singleton 초기화
* 스트림 파서 또는 API client 초기화

실제 OpenAI 번역 요청을 보내지 않고도 콜드 스타트 대부분을 제거할 수 있다면 이 방식을 사용한다.

### 대안 B: 최소한의 무해한 warm-up 요청

연결만 초기화할 수 없다면 아주 작은 예열 요청을 보낸다.

조건:

* 실제 대화 기록에 저장하지 않음
* UI에 표시하지 않음
* TTS 재생하지 않음
* AI conversation history에 추가하지 않음
* billing usage 또는 사용자 사용량으로 기록하지 않음
* 특수 태그 로직을 발동시키지 않음
* turn counter를 증가시키지 않음
* 실제 대화 큐에 넣지 않음
* 실패해도 사용자에게 오류를 표시하지 않음
* 취소 가능한 별도 warm-up context로 실행

예열용 문장은 실제 학습 대화와 혼동되지 않는 내부 값으로 사용하되, 번역 결과를 절대 사용자 상태에 반영하지 않는다.

---

## 2-2. TTS 경로 예열

다음 순서로 안전한 방식을 선택한다.

### 권장안 A: TTS 클라이언트와 큐만 초기화

가능하다면 다음만 수행한다.

* TTS API client 생성
* 인증 토큰 준비
* TTS worker 또는 queue 생성
* 캐시 폴더 확인 및 생성
* 오디오 파일 처리 경로 준비
* 음성 설정값 로드
* player 객체 준비

실제 TTS API 호출이나 음성 재생은 하지 않는다.

### 대안 B: 최소 TTS 요청 후 즉시 폐기

실제 요청이 필요하다면:

* 매우 짧은 문자열 사용
* 생성된 오디오는 재생하지 않음
* 사용자/AI TTS 큐에 넣지 않음
* 캐시 기록과 히스토리에 남기지 않음
* 비용 로그가 있다면 warm-up으로 구분
* 실제 턴의 pending count에 포함하지 않음
* completion event가 실제 파이프라인의 gate를 열지 않음
* 예열 오디오가 실제 음성 큐에 섞이지 않음

가능하면 무음 문자열이나 punctuation-only 요청은 피한다. 서비스에서 거부하거나 기존 punctuation skip 로직과 충돌할 수 있기 때문이다.

---

## 2-3. 오디오 플레이어 예열

현재 플레이어 구조를 분석한 후 다음을 검토한다.

* 플레이어 객체 선생성
* 오디오 포커스 경로 선초기화
* 임시 오디오 소스 로딩 없이 decoder 초기화 가능 여부
* 첫 재생 때만 수행되는 setup 최소화
* 플레이어 singleton 또는 pool 재사용 가능 여부
* 매 조각마다 MediaPlayer가 새로 생성되는 구조가 필요한지

단, 빈 오디오나 무음 파일을 실제로 재생해서 사용자의 음악이나 통화 오디오 포커스를 빼앗지 않는다.

오디오 포커스를 선점해야만 예열되는 구조라면 무리하게 실행하지 말고, 첫 실제 재생 시점의 초기화만 최소화한다.

---

# Phase 3. 예열 실행 시점

Anyone 화면 진입 직후 비동기로 시작하되 다음 조건을 만족해야 한다.

* UI 렌더링을 block하지 않음
* 마이크 시작을 block하지 않음
* 사용자가 바로 말해도 실제 턴이 우선됨
* 예열 중 실제 발화가 시작되면 예열을 취소하거나 실제 요청과 자원을 안전하게 공유
* 실제 요청이 시작됐는데 예열이 같은 client를 점유해 기다리게 하지 않음
* 화면 dispose 시 예열 결과 무시
* 같은 화면 인스턴스에서 중복 실행하지 않음
* background 복귀마다 반복하지 않음
* 실제로 client가 재생성되었을 때만 재예열 검토
* trial과 정식 사용자 모두 동일한 안전 기준 적용

추천 상태 예시:

* `_warmupStarted`
* `_warmupCompleted`
* `_warmupCancelled`
* `_warmupFuture`
* `_warmupGeneration`

다만 기존 구조에 맞는 최소한의 상태만 추가하고 불필요한 상태 변수를 늘리지 않는다.

---

# Phase 4. 실제 발화와의 경쟁 조건 방지

이 부분을 가장 엄격하게 검증한다.

다음 상황을 시뮬레이션한다.

## 상황 A

방 입장 직후 0.5초 이내에 사용자가 말하기 시작

기대 결과:

* 실제 Deepgram listening 정상
* 실제 번역 요청이 예열 때문에 지연되지 않음
* 실제 사용자 TTS가 예열 큐 뒤에 대기하지 않음
* 예열 결과가 화면에 나타나지 않음

## 상황 B

예열 번역 요청 중 실제 번역 요청 시작

기대 결과:

* 실제 요청 우선
* client thread 또는 connection pool deadlock 없음
* 예열과 실제 스트림 데이터가 섞이지 않음
* 실제 turn ID 유지

## 상황 C

예열 TTS 중 실제 사용자 TTS 요청 시작

기대 결과:

* 실제 사용자 TTS가 warm-up pending 뒤에 대기하지 않음
* warm-up completion이 `PIPE-05`, `PIPE-06`, `PIPE-07` 이벤트를 발생시키지 않음
* 사용자 큐와 AI 큐 상태가 변하지 않음

## 상황 D

예열 도중 화면 나가기

기대 결과:

* setState after dispose 없음
* player leak 없음
* HTTP stream leak 없음
* TTS worker leak 없음
* warm-up 결과 무시
* billing 또는 history에 기록 없음

## 상황 E

앱 background 전환 후 복귀

기대 결과:

* 예열이 대화 재개 흐름을 방해하지 않음
* 기존 lifecycle billing/pause/resume 규칙 유지
* 마이크 중복 시작 없음

---

# Phase 5. 체감 반응 개선

예열만으로 충분하지 않다면, 발화 종료 직후 사용자가 앱이 멈춘 것으로 느끼지 않도록 최소한의 상태 표시를 검토한다.

가능한 개선:

* Deepgram에서 확정된 원문을 즉시 화면에 표시
* 영어 문장이 준비되기 전 임시 상태 표시
* “영어로 바꾸는 중”과 같은 짧은 처리 상태
* 사용자 말풍선 영역에 인식된 원문을 먼저 표시하고 번역 완료 후 영어 문장 추가

단, UI 변경은 현재 구조를 확인한 뒤 최소 범위로 적용한다.

다음은 금지한다.

* 같은 발화를 두 개의 chat line으로 저장
* 임시 원문이 history에 중복 저장
* 임시 UI가 최종 메시지로 남음
* 스크롤 인덱스가 두 번 증가
* AI conversation history에 임시 텍스트 삽입

---

# 성능 목표

현재 로그를 기준으로 최소 목표를 설정한다.

## 첫 턴 목표

발화 종료 이벤트 기준:

* 영어 문장 표시: 기존 약 3.2초 → 목표 2.0초 이하
* 사용자 영어 음성 시작: 기존 약 5.9초 → 목표 4.0초 이하

가능하면 이후 턴과 비슷한 수준을 목표로 한다.

다만 정확성, 턴 안정성, 오디오 순서 보장을 희생하면서 수치를 맞추지 않는다.

---

# 검증 방법

## 정적 검증

관련 수정 파일에 대해:

* `flutter analyze`
* lint 오류 확인
* 미사용 상태 변수 확인
* dispose 이후 callback 가능성 확인
* 비동기 unawaited 작업 예외 처리 확인

## 실제 로그 검증

최소 다음 시나리오를 각각 3회 실행한다.

1. 앱 새 실행 후 Anyone 첫 진입
2. Anyone 나갔다가 다시 진입
3. 방 입장 직후 바로 발화
4. 방 입장 후 3초 기다렸다가 발화
5. 짧은 문장
6. 긴 문장
7. 예열 중 화면 나가기
8. 예열 중 background 전환
9. trial Anyone
10. 정식 회원 Anyone

각 실행에서 다음을 표로 정리한다.

* warm-up 시작 시각
* warm-up 완료 시각
* 발화 종료
* commit
* 번역 완료
* 사용자 TTS 완료
* 사용자 음성 시작
* 사용자 음성 완료
* AI 음성 시작
* AI 음성 완료
* 오류 또는 race condition 여부

---

# 회귀 방지 항목

다음 기능이 기존과 동일하게 동작하는지 반드시 확인한다.

* 사용자 영어 echo가 AI 답변보다 먼저 재생
* 사용자와 AI 음성 겹침 없음
* AI 재생 중 마이크 켜지지 않음
* AI 재생 완료 후 마이크 정상 재시작
* 첫 턴과 이후 턴 모두 저장 정상
* 특수 태그 정상
* correction 정상
* evaporate 정상
* dissatisfied/misheard 처리 정상
* turn counter 정상
* generation guard 정상
* trial 종료 타이머 정상
* billing resume/pause 정상
* history 저장 정상
* 화면 나가기 후 음성 재생 없음
* warm-up 데이터가 history에 남지 않음
* warm-up 요청이 chat context에 포함되지 않음

---

# 구현 판단 권한

구체적인 구현 방식은 실제 코드를 확인한 후 가장 안전하고 단순한 방법을 선택한다.

다음 중 하나로 미리 제한하지 않는다.

* singleton client
* reusable HTTP client
* Firebase callable pre-initialization
* auth token prefetch
* Remote Config prefetch
* queue worker startup
* TTS client initialization
* player preparation
* minimal warm-up request

단, 선택한 방식은 다음 기준을 만족해야 한다.

1. 이벤트 기반 게이트 유지
2. 실제 사용자 턴보다 예열 우선순위가 낮음
3. 예열 실패가 사용자 대화를 막지 않음
4. 예열 결과가 실제 상태에 섞이지 않음
5. 불필요한 API 비용 최소화
6. 코드 중복 최소화
7. 공통 서비스 계층에서 해결 가능하면 화면 파일에 임시 우회 로직을 넣지 않음
8. Anyone만의 문제인지 공통 TTS/번역 서비스 문제인지 구분
9. 다른 모드에 안전하게 이점이 적용될 수 있으면 공통 개선 검토
10. 다른 모드에 회귀 위험이 있으면 Anyone 범위로 제한

---

# 금지 사항

* 완료 이벤트를 고정 delay로 대체
* 900ms commit gate를 이번 작업에서 임의로 변경
* 250ms user-AI gap을 이번 작업에서 임의로 변경
* 사용자 echo 생략
* 사용자와 AI 동시 재생
* 예열 음성 실제 재생
* warm-up을 실제 채팅 턴으로 처리
* 예열 데이터를 Firestore에 저장
* 예열 요청 때문에 billing 차감
* API 키를 클라이언트 코드에 추가
* 인증 우회
* 오류를 숨기기 위해 catch만 추가
* 로그 없이 성능 개선됐다고 판단
* 한 파일에 모든 예열 로직을 임시로 몰아넣기
* 기존 통신 파이프라인 전체 재작성
* 테스트 없이 main 병합

---

# 작업 완료 보고 형식

완료 후 다음 순서로 보고한다.

## 1. 원인

첫 턴 지연의 실제 원인을 코드 기준으로 설명한다.

예:

* 첫 HTTP client 생성
* Firebase Auth token fetch
* callable 초기화
* Remote Config lazy load
* TTS worker lazy start
* player lazy init
* 캐시 경로 생성

추측과 확인된 사실을 구분한다.

## 2. 변경 파일

파일별 변경 내용을 정리한다.

## 3. 구현 방식

어떤 자원을 언제 예열했는지 설명한다.

## 4. 이벤트 기반 구조 보존 여부

다음이 그대로인지 명시한다.

* 사용자 재생 완료 → AI 큐 개방
* AI 재생 완료 → 마이크 재시작
* turn/generation guard
* 특수 태그 처리

## 5. 성능 비교

수정 전과 수정 후의 첫 턴 실측값을 표로 비교한다.

## 6. 회귀 테스트 결과

통과/실패를 명확히 표시한다.

## 7. 잔여 위험

완전히 제거하지 못한 위험이나 추가 개선 후보를 적는다.

---

# 최종 완료 조건

다음 조건을 모두 만족해야 완료로 본다.

* 첫 턴 영어 문장 표시 시간이 실측으로 개선됨
* 첫 턴 사용자 영어 음성 시작 시간이 실측으로 개선됨
* 이벤트 기반 완료 게이트 유지
* 사용자/AI 음성 순서 유지
* 마이크 재시작 조건 유지
* 예열 데이터가 UI, history, AI context에 남지 않음
* 예열 실패 시 실제 대화 정상
* 빠른 첫 발화에서도 race condition 없음
* 화면 나가기 및 background 전환 안전
* `flutter analyze` 통과
* 로그캣 실측 결과 첨부
* 관련 테스트 완료 전 main 병합 금지

핵심은 코덱스가 단순히 “무음 TTS를 한 번 호출”하는 식으로 처리하지 않고, **실제 콜드 스타트의 원인을 먼저 찾아 가장 비용이 적고 안전한 계층에서 예열하도록 한 것**입니다.
