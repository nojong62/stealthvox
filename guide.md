# StealthVox 프로젝트 가이드 (Flutter)

## 📂 구조
- 화면(Pages): `lib/` 아래 이름별 폴더
- 커스텀 액션: `lib/custom_code/actions/`
- 커스텀 위젯: `lib/custom_code/widgets/`
- 전역 상태: `lib/app_state.dart`
- 테마: `lib/flutter_flow/flutter_flow_theme.dart`

`lib/custom_code/widgets/img/`는 디자인 참고용 이미지 폴더다. pubspec assets에 등록돼 있지
않고 Dart 코드에서도 참조하지 않으므로 빌드에 영향이 없다. 이 폴더가 지저분해도 무시할 것.

## ⚙️ 작업 규칙

### 코드
- 직접 Flutter 코드를 수정한다. (FlutterFlow 웹 에디터는 더 이상 쓰지 않음)
- `lib/flutter_flow/` 아래 생성 코드는 구조를 크게 바꾸지 말 것.
- 색상·폰트·간격은 `flutter_flow_theme.dart`의 테마 변수를 최우선으로 쓴다. 하드코딩 금지.

### 백업 커밋
되돌리기 어려운 작업에서만 만든다. 만들 때는 **이번 작업과 관련된 파일만** 담을 것.
관계없는 작업 중인 파일을 "백업"이라며 같이 커밋하지 말 것 — 내 WIP를 멋대로 커밋하는 셈이다.

### 커밋 · 머지 · push
**요청받았을 때만** 한다. 알아서 main에 머지하거나 원격에 push하지 않는다.
단, 릴리스 빌드의 버전 변경은 출시본 추적이 끊기므로 커밋을 먼저 제안할 것.

## 📦 릴리스 빌드 (AAB)
- 버전: `pubspec.yaml`의 `version: 1.0.N+N` — versionName과 versionCode를 같이 올린다
- 빌드: `flutter build appbundle --release` (약 8분)
- 출력: `build/app/outputs/bundle/release/app-release.aab`
- 서명: `android/key.properties` + `android/app/code-stealth-vox-808wqy-keystore.jks`
  — 이미 설정 완료. 건드릴 필요 없다.
- 서명 확인은 AAB 안에 `META-INF/CODE-STE.RSA`가 있는지 보면 충분하다.
  버전 확인은 `base/manifest/AndroidManifest.xml`에서 versionName 문자열로 확인.
  그 이상 파고들지 말 것.

## ⚠️ 주의사항
- 기존 정상 작동 기능을 깨지 말 것
- 앱 실행/빌드 가능성을 최우선으로 할 것
- 불확실한 부분은 임의 삭제하지 말고 보고할 것
- 확인이 끝났으면 더 파지 말 것

StealthVox 진행 상황 관리 지시문

AI 지시문
"아래 체크리스트를 기준으로 내 진행 상황을 관리해줘.
내가 완료한 항목을 말하면 체크 표시해.
작업 단위(또는 매주)로 진행률을 요약해.
막혔던 부분은 별도 메모로 기록해."

1. 작업 기록
 큰 작업은 시작 전 계획 요약 + 동의
 되돌리기 어려운 작업은 관련 파일만 백업 커밋
 커밋 메시지에 "왜 바꿨는지" 한 줄 남기기
2. 검증
 수정 후 flutter analyze (error만 확인, 기존 warning 무시)
 새 기능은 로컬에서 실행 확인
 릴리스 빌드 전 버전(pubspec.yaml) 확인
3. 진행 상황 추적
 완료 항목 ✅ 표시
 작업 단위별 진행률 기록
 막혔던 부분/보류 이슈는 별도 메모
================
지시문

최종 점검에서 **기존 지시문의 중요한 부분 하나를 수정했습니다.** Android·모바일 클라이언트는 WebSocket과 별도 PCM 플레이어를 직접 만드는 것보다 **WebRTC를 기본 경로로 사용하는 것이 안전하고 일관된 성능에 유리**합니다. 공식 문서도 모바일 클라이언트에는 WebRTC를 권장하며, WebRTC 연결은 모델 음성을 원격 오디오 트랙으로 직접 전달하고 세부 오디오 청크 처리를 대신합니다. ([OpenAI Developers][1])

또한 `gpt-realtime-2.1-mini`는 현재 공식 모델이며 오디오·텍스트 입력과 출력을 지원합니다. Realtime 음성은 텍스트 final이나 저장 완료와 독립적으로 재생해야 하고, 추가 번역문은 기본 대화를 오염시키지 않는 text-only out-of-band 응답으로 생성할 수 있습니다. ([OpenAI Developers][2])

# StealthVox Realtime 통신 로직 전면 개편 — 최종 실행 지시문

## 0. 절대 원칙

이번 작업은 단순 모델 교체가 아니라 StealthVox의 핵심 음성 통신 경로를 전면 개편하는 작업이다.

다음 원칙을 반드시 지킨다.

1. 한 번에 모든 모드를 활성화하지 않는다.
2. 기존 통신 경로는 즉시 삭제하지 않고 비상 복구용으로 유지한다.
3. 각 모드는 독립된 기능 플래그로 활성화한다.
4. Realtime 음성은 원문·번역문·UI·Firestore 저장을 기다리지 않는다.
5. 모바일 기본 연결 방식은 WebRTC로 한다.
6. Realtime 음성을 기존 TTS-1 재생 큐에 넣지 않는다.
7. 표준 OpenAI API 키를 앱에 포함하지 않는다.
8. 실제 코드를 수정하기 전에 현재 통신 구조를 읽기 전용으로 조사한다.
9. 조사 결과와 실제 코드가 이 지시문의 가정과 다르면, 추측해서 구현하지 말고 실제 코드 구조에 맞춰 설계를 조정한다.
10. 과금·세션 시간·History·회원·체험 정책은 변경하지 않는다.

모델 ID는 정확히 다음 값을 사용한다.

`gpt-realtime-2.1-mini`

유사 이름, deprecated alias 또는 기존 preview 모델을 사용하지 않는다.

---

# 1. 최종 적용 범위

## 1.1 Duo

Duo의 전체 음성 통역을 `gpt-realtime-2.1-mini`로 처리한다.

기본 경로:

사용자 음성
→ Realtime 직접 이해
→ 반대 언어 번역
→ 번역 음성 즉시 출력
→ 원문 및 번역문 병렬 표시
→ final 데이터 후처리 저장

Realtime 경로에서는 다음을 사용하지 않는다.

* Deepgram Nova-3
* GPT-4o mini 번역
* GPT-4.1 주어 판단
* TTS-1
* HybridTtsPlayer
* TtsQueueManager
* 기존 TTS 음성 캐시

Duo에서 모델은 사용자의 말에 답변하지 않는다.

모델 역할은 오직 다음과 같다.

* 화자의 말을 상대 언어로 통역
* 의미를 자연스럽게 전달
* 질문이면 질문 자체를 번역
* 설명이나 의견을 추가하지 않음
* 내용을 임의로 확장하거나 축약하지 않음

Duo의 기존 화자 구분, 호스트·게스트 상태, 언어 방향, 초대 세션, 과금 주체는 그대로 유지한다.

---

## 1.2 Anyone

Anyone의 모든 사용자 턴과 AI 답변을 `gpt-realtime-2.1-mini`로 처리한다.

기본 경로:

사용자 음성
→ Realtime 직접 이해
→ AI 답변 판단
→ AI 텍스트와 음성 즉시 출력
→ 원문·번역문 후처리
→ History 저장

Realtime이 담당한다.

* 음성 입력 이해
* 대화 문맥 유지
* 입력 언어 판단
* AI 답변 생성
* 음성 출력
* AI 발화 텍스트 출력
* 사용자 끼어들기 처리
* 진행 중 AI 답변 취소

Deepgram, GPT-4o mini, GPT-4.1, TTS-1을 중복 호출하지 않는다.

---

## 1.3 Roleplay

Roleplay의 모든 사용자 턴과 AI 역할 대사를 `gpt-realtime-2.1-mini`로 처리한다.

세션 시작 시 다음 정보를 instruction으로 전달한다.

* 역할극 상황
* 사용자 역할
* AI 역할
* 사용자 모국어
* 학습 대상 언어
* 난이도
* 역할극 목표
* 종료 조건
* 짧은 답변 규칙
* 역할 밖 설명 금지

AI는 설정된 역할의 대사만 말한다.

역할극 중 다음 행동을 하지 않는다.

* 장문의 문법 설명
* 사용자 말 전체 반복
* 역할 밖 해설
* 상황 요약
* 불필요한 학습 조언
* 여러 질문을 한꺼번에 제시
* 역할극을 AI 마음대로 종료

---

## 1.4 Step Expand

Step Expand는 하이브리드 구조를 유지한다.

### 첫 사용자 턴

첫 사용자 발화와 이에 대한 첫 AI 응답만 Realtime으로 처리한다.

사용자 첫 음성
→ `gpt-realtime-2.1-mini`
→ 사용자 원문 텍스트
→ 첫 AI 답변 텍스트·음성
→ 기존 Step Expand 상태에 전달

첫 턴에서는 다음을 호출하지 않는다.

* Deepgram
* GPT-4o mini
* GPT-4.1
* TTS-1

### 첫 턴 완료 이후

두 번째 사용자 턴부터는 기존 경로를 그대로 사용한다.

Deepgram Nova-3
→ GPT-4o mini
→ TTS-1

Step Expand의 다음 기능은 변경하지 않는다.

* 5턴 구성
* Part 1 / Part 2
* 기본 문장과 확장 문장
* 기존 프롬프트
* 기존 단계 전환
* 기존 저장 필드
* 기존 History 구조
* 기존 평가·튜터링 구조
* 기존 과금 로직

---

# 2. 논리적 시뮬레이션 결과와 필수 방어 설계

## 시나리오 A — 오디오가 먼저 도착하고 텍스트가 늦게 도착

### 잘못된 구현

첫 오디오 도착
→ 원문 final 대기
→ 타겟 텍스트 final 대기
→ UI 갱신
→ 저장
→ 음성 재생

결과:

* Realtime인데도 기존 파이프라인과 비슷하게 느려짐
* 첫 음성 반응 장점 소멸

### 올바른 구현

첫 원격 오디오 프레임 도착
→ 즉시 스피커 출력

동시에:

* 입력 전사 델타 → 원문 버블
* 출력 음성 transcript 델타 → AI 또는 번역 버블
* final 데이터 → 저장 준비

절대 규칙:

> 텍스트, UI, 저장은 음성 출력을 승인하거나 보류할 권한이 없다.

---

## 시나리오 B — 사용자가 AI 재생 중 다시 말함

필요한 처리:

1. 사용자 발화 시작 감지
2. 진행 중 Realtime response 취소
3. 재생되지 않은 출력 오디오 제거
4. 이전 response ID 무효화
5. 이전 텍스트 델타 추가 중단
6. 새 turn ID 발급
7. 새 사용자 발화 처리
8. 새 답변 생성

발생하면 안 되는 문제:

* 이전 AI 답변이 나중에 다시 재생
* 취소된 문장이 History에 완성 문장으로 저장
* 이전 응답의 완료 이벤트가 새 턴을 종료
* 두 음성이 동시에 출력
* 마이크가 중복 활성화

WebRTC 경로에서는 Realtime 서버의 interruption 및 출력 버퍼 관리 기능을 활용하고, 앱은 현재 활성 response와 turn의 일치 여부를 추가 검증한다.

---

## 시나리오 C — 텍스트 final 이벤트가 순서와 다르게 도착

네트워크 상황에 따라 다음 이벤트의 순서가 항상 앱의 기대와 같다고 가정하지 않는다.

* 원문 transcript final
* AI 음성 transcript final
* response done
* Firestore 저장 완료
* UI 업데이트 완료

각 turn은 다음 독립 필드를 가진다.

* sourceTextPartial
* sourceTextFinal
* spokenTargetPartial
* spokenTargetFinal
* secondaryTranslation
* responseCompleted
* playbackStarted
* playbackCompleted
* saveCompleted
* cancelled

어떤 이벤트든 turn ID와 response ID가 일치할 때만 반영한다.

`response.done`이 왔다고 원문 transcript가 이미 완료되었다고 가정하지 않는다.

---

## 시나리오 D — Step Expand 첫 턴에서 기존 경로가 동시에 켜짐

가장 위험한 오류다.

발생 가능한 문제:

* Realtime과 Deepgram이 같은 마이크를 동시에 점유
* Realtime 음성과 TTS-1이 동시에 재생
* 첫 사용자 대사가 두 번 저장
* turn index가 두 번 증가
* AI 첫 답변이 두 번 생성
* Part 1 단계가 건너뛰어짐

이를 방지하기 위해 Step Expand에 명시적인 통신 경로 상태를 둔다.

* realtimeFirstTurnPreparing
* realtimeFirstTurnActive
* realtimeFirstTurnFinalizing
* switchingToLegacy
* legacyPreparing
* legacyActive

다음 조건이 모두 완료되기 전에는 기존 Deepgram 경로를 시작하지 않는다.

1. Realtime 입력 트랙 중단
2. Realtime 출력 중단 또는 정상 완료
3. 첫 turn 메모리 상태 확정
4. 첫 turn 중복 저장 방지 키 기록
5. Realtime listener 해제
6. Data channel 종료
7. PeerConnection 종료
8. 오디오 포커스 반납
9. 기존 turn index에 첫 턴 결과 전달
10. legacyReady 확인

그 후에만 두 번째 턴 마이크를 활성화한다.

---

## 시나리오 E — 네트워크 단절

Realtime 연결이 끊기면 자동으로 새 답변이 생성된 것처럼 처리하지 않는다.

처리 순서:

1. 현재 turn을 failed 또는 interrupted로 표시
2. 진행 중 오디오 출력 중단
3. 현재 응답과 텍스트 델타 폐기
4. 마이크 중단
5. 한 번의 제한된 재연결 시도
6. 성공하면 session instruction과 모드 상태 복원
7. 실패하면 사용자에게 짧은 재시도 안내 표시

같은 사용자 음성을 자동 재전송하지 않는다.

사용자에게 알리지 않고 중간 턴만 기존 GPT-4o mini 경로로 바꾸는 silent fallback은 사용하지 않는다.

전체 모드를 기존 경로로 되돌리는 것은 Remote Config 기능 플래그로만 수행한다.

---

## 시나리오 F — 화면 종료·백그라운드 이동

화면이 dispose 또는 inactive 상태가 되면 다음을 모두 종료한다.

* 마이크 트랙
* 원격 오디오 트랙
* RTCPeerConnection
* Data channel
* StreamSubscription
* Timer
* UI throttle
* 진행 중 response
* 미완료 텍스트 후처리
* 오디오 포커스

dispose 이후 도착한 이벤트는 무조건 무시한다.

`mounted` 확인만으로는 충분하지 않다.

각 서비스에 sessionGeneration을 두고, 현재 generation과 다른 이벤트를 폐기한다.

---

## 시나리오 G — AI 답변이 장황해짐

프롬프트만 믿고 무제한 출력을 허용하지 않는다.

다음 세 가지를 함께 적용한다.

1. 세션 instruction에 짧은 답변 규칙
2. response 수준의 출력 제한
3. 실제 로그에서 발화 길이 측정

기본 기준:

* 일반 AI 답변: 1~2문장
* 한 문장으로 충분하면 한 문장
* 보통 25단어 이내
* 설명이 필요한 경우에도 3문장 이내
* Duo 통역은 원문의 의미 범위를 초과하지 않음

---

# 3. 연결 방식

## 3.1 Android·모바일 기본 방식

WebRTC를 기본 연결 방식으로 사용한다.

구조:

StealthVox 앱
→ 자체 서버에서 단기 ephemeral token 발급
→ 앱이 WebRTC PeerConnection 생성
→ 로컬 마이크 트랙 연결
→ OpenAI Realtime 연결
→ 모델 원격 오디오 트랙을 직접 재생
→ Data channel로 이벤트 송수신

WebSocket은 다음 경우에만 검토한다.

* WebRTC가 실제 Android 환경에서 요구 기능을 제공하지 못함
* 서버 중계가 반드시 필요함
* PCM 데이터의 직접 변환이나 저장이 필수임
* 기술적 증거와 측정 결과가 있음

단순히 기존 WebSocket 코드가 있다는 이유로 WebSocket을 선택하지 않는다.

---

## 3.2 인증

표준 OpenAI API 키는 서버에만 둔다.

앱에는 다음을 절대 포함하지 않는다.

* 표준 API 키
* 장기 유효 토큰
* Firebase Remote Config 내 API 키
* Dart 상수에 직접 작성한 API 키
* 빌드 설정에 노출되는 평문 키

앱은 자체 서버 또는 Firebase Functions에서 발급한 짧은 수명의 ephemeral token만 사용한다.

토큰 발급 서버는 다음을 확인한다.

* Firebase Auth 사용자
* 익명 체험 사용자 허용 정책
* App Check
* 요청 빈도 제한
* 현재 허용된 앱 버전
* 현재 허용된 모드
* 사용자별 안전 식별자
* 실패 로그

토큰과 인증 헤더는 release 로그에 출력하지 않는다.

---

# 4. 공용 Realtime 계층

새 공용 서비스를 추가한다.

권장 역할명:

`StealthVoxRealtimeSession`

실제 파일명은 프로젝트 명명 규칙에 맞춘다.

## 책임

* ephemeral token 요청
* RTCPeerConnection 생성
* Data channel 생성
* 로컬 마이크 트랙 연결
* 원격 오디오 트랙 수신
* session update
* 모드별 instruction 적용
* turn 상태 관리
* response 상태 관리
* 입력 transcript 이벤트 처리
* 출력 transcript 이벤트 처리
* 오류 처리
* 연결 복구
* 중단 처리
* dispose
* 사용량 로그 수집

## 이 서비스가 하면 안 되는 일

* Firestore UI 모델 직접 변경
* 특정 페이지의 setState 직접 호출
* 과금 시간 차감
* 기존 History 스키마 변경
* Box 7 내부 TTS 실행
* 임의의 fallback 결정
* 모드별 비즈니스 규칙 직접 판단

서비스는 스트림이나 callback으로 정규화된 이벤트만 페이지 또는 controller에 전달한다.

---

# 5. 상태 머신

각 Realtime 세션은 명시적인 상태 머신으로 관리한다.

## 연결 상태

* disconnected
* requestingToken
* connecting
* configuring
* ready
* reconnecting
* closing
* closed
* failed

## 턴 상태

* idle
* listening
* userSpeaking
* turnEnding
* responseRequested
* responseStreaming
* audioPlaying
* interrupted
* finalizing
* completed
* cancelled
* failed

허용되지 않는 상태 전환은 무시하지 말고 진단 로그를 남긴다.

예:

* closed 상태에서 response 요청
* completed turn에 새로운 delta 수신
* 현재 turn과 다른 response의 오디오 수신
* legacyActive 상태에서 Realtime 마이크 활성화
* realtimeActive 상태에서 Deepgram 시작

---

# 6. 단일 소유권 규칙

항상 다음 불변 조건을 만족해야 한다.

## 마이크

한 시점에 마이크 소유자는 정확히 하나다.

* none
* realtime
* deepgram

두 소유자가 동시에 존재하면 오류로 처리한다.

## 오디오 출력

한 시점에 음성 출력 소유자는 정확히 하나다.

* none
* realtimeRemoteTrack
* legacyTts

Realtime 출력이 시작되기 전에 legacy TTS를 중단한다.

Legacy TTS가 시작되기 전에 Realtime remote track을 중단하거나 음소거한다.

## 턴

한 모드에서 활성 사용자 turn은 최대 하나다.

## 응답

활성 Realtime response는 최대 하나다.

## 저장

같은 turn은 History에 한 번만 저장한다.

---

# 7. 식별자

각 세션과 턴에 다음 식별자를 사용한다.

* modeSessionId
* connectionGeneration
* turnId
* responseId
* inputItemId
* outputItemId
* saveIdempotencyKey

이벤트를 처리하기 전에 항상 다음을 검증한다.

* 현재 modeSessionId와 같은가
* 현재 connectionGeneration과 같은가
* 현재 turnId와 같은가
* 취소된 response가 아닌가
* 화면이 아직 활성 상태인가

오래된 이벤트는 조용히 화면에 반영하지 말고, 진단 카운터를 증가시킨 뒤 폐기한다.

---

# 8. PTT와 VAD 결정

현재 모드의 실제 UI를 먼저 조사한다.

## 기존 모드가 PTT인 경우

PTT UX를 임의로 자동 VAD 방식으로 바꾸지 않는다.

* PTT 누름: 이전 입력 버퍼 정리
* 기존 응답이 있으면 취소
* 재생 중 출력 버퍼 정리
* 마이크 입력 시작
* PTT 해제: 입력 commit
* response 생성 요청

PTT는 사용자가 턴 종료를 직접 지정하므로 불필요한 VAD 대기시간을 줄일 수 있다.

## 기존 모드가 hands-free인 경우

Semantic VAD를 우선 검토한다.

* 발화 의미가 끝났다고 판단하면 응답 시작
* 사용자 끼어들기 허용
* 너무 적극적인 끊김이 생기면 eagerness 조정

단, 모든 모드에 동일한 VAD 설정을 강제하지 않는다.

모드별 실제 사용 패턴을 측정해 결정한다.

---

# 9. 음성 출력

## WebRTC 기본 경로

모델 음성은 WebRTC 원격 미디어 트랙으로 직접 재생한다.

다음 구조를 만들지 않는다.

* Base64 오디오 델타 수집
* 전체 PCM 누적
* WAV 헤더 생성
* 임시 파일 저장
* audioplayers 파일 로드
* 문장 단위 재생
* TtsQueueManager 삽입

WebRTC에서 오디오 수신·재생이 정상이라면 별도 RealtimeAudioPlayer를 만들지 않는다.

## 예외

실제 기기 테스트에서 WebRTC 원격 트랙이 요구사항을 충족하지 못할 때만 별도 플레이어를 검토한다.

검토 전에 다음 측정값을 제출한다.

* 원격 오디오 트랙 수신 시각
* 실제 스피커 출력 시각
* 끊김 횟수
* Bluetooth 라우팅 문제
* 재생 중단 반응 시간
* 해당 문제를 WebRTC 설정으로 해결할 수 없는 근거

---

# 10. Box 7 처리

Realtime 모드에서는 Box 7 음성 경로를 우회한다.

기존 Box 7은 다음 용도로 그대로 유지한다.

* Step Expand 두 번째 턴 이후
* 기존 Deepgram + GPT-4o mini + TTS-1 경로
* Remote Config로 legacy 모드를 복원한 경우

초기 구현에서는 다음을 변경하지 않는다.

* HybridTtsPlayer 내부 청킹
* TtsQueueManager 큐 구조
* ChunkedTtsFetcher
* TTS 캐시
* TTS-1 API 호출 방식

필요한 최소 외부 제어만 추가할 수 있다.

* stop
* isPlaying
* playbackStarted
* playbackCompleted
* cancelCurrentGeneration

Realtime 전용 오디오 함수를 Box 7 내부에 넣지 않는다.

---

# 11. 오디오 경로 조정자

페이지별로 중복된 오디오 제어를 만들지 말고 공용 조정 계층을 둔다.

권장 역할명:

`AudioPathCoordinator`

담당:

* 현재 마이크 소유권
* 현재 출력 소유권
* Realtime과 legacy 충돌 차단
* 모드 전환
* Step Expand handoff
* 재생 중단
* Bluetooth·스피커 오디오 포커스
* 화면 종료 시 정리

이 계층은 실제 TTS 생성이나 Realtime 연결을 직접 수행하지 않는다.

두 음성 경로 사이의 소유권만 관리한다.

---

# 12. 두 언어 텍스트 처리

오리지널 글자와 타겟 글자를 모두 유지한다.

그러나 두 텍스트는 음성 재생과 분리한다.

## 12.1 사용자 원문

Realtime 입력 transcript delta를 임시 원문으로 표시한다.

final 도착 시 확정한다.

원문 final이 늦더라도 AI 음성을 막지 않는다.

## 12.2 Realtime이 실제로 말한 문장

모델의 출력 오디오 transcript delta를 해당 AI 또는 번역 버블에 표시한다.

이 텍스트가 실제 재생된 음성과 가장 가까운 기준 텍스트다.

## 12.3 추가 번역문

Anyone과 Roleplay에서 화면에 AI 답변의 다른 언어 번역문이 필요하면 별도의 text-only out-of-band 응답으로 만든다.

원칙:

* 기본 대화 conversation에 추가하지 않음
* 목적 metadata를 명시
* turnId와 responseId를 포함
* 음성 재생을 기다리게 하지 않음
* 음성 답변 생성과 혼동하지 않음
* 결과는 화면 표시와 저장에만 사용

예시 목적 구분:

* user_target_translation
* assistant_native_translation
* history_normalization

추가 번역 응답은 기본 대화 문맥에 새 AI 대사로 들어가면 안 된다.

## 12.4 Duo

Duo에서는 모델의 실제 출력 음성 transcript가 곧 타겟 번역문이므로 별도 타겟 번역 요청을 만들지 않는다.

필요한 것은:

* 입력 원문 transcript
* 출력 번역 음성 transcript
* 출력 번역 음성

---

# 13. UI 갱신

텍스트 델타가 들어올 때 전체 페이지를 매번 rebuild하지 않는다.

권장 방식:

* 델타 메모리 버퍼
* 해당 대화 버블만 갱신
* 약 50~100ms 단위 UI 반영
* 음성 재생 callback과 UI 갱신 분리
* 스크롤 애니메이션 중복 방지

중요:

UI throttle은 텍스트 표시 빈도만 제어한다.

오디오 재생과 response 처리를 지연시키면 안 된다.

---

# 14. Firestore와 History 저장

저장은 Realtime 음성 시작의 선행 조건이 아니다.

## 금지

* Firestore write await 후 음성 재생
* 세션 문서 생성 후 response 시작
* usage log 완료 후 다음 턴 허용
* History 저장 실패로 재생 취소

## 권장 흐름

1. 원격 오디오 즉시 재생
2. 원문·출력 텍스트 final 수집
3. 메모리 turn 상태 확정
4. 저장 payload 생성
5. 비차단 저장
6. 실패 시 재시도 큐 또는 오류 로그

## 중복 방지

`modeSessionId + turnId`를 기반으로 idempotency key를 만든다.

같은 키가 이미 저장 중이거나 저장 완료된 경우 다시 저장하지 않는다.

취소된 응답은 실제 재생된 범위와 저장 정책을 명확히 구분한다.

완전히 재생되지 않은 AI 답변을 완전한 답변으로 저장하지 않는다.

---

# 15. AI 답변 공통 규칙

모든 AI 대화 모드에 다음 원칙을 적용한다.

## 답변 길이

* 기본 1~2문장
* 한 문장으로 충분하면 한 문장
* 보통 25단어 이내
* 불가피한 설명도 최대 3문장
* 사용자의 질문보다 답변이 지나치게 길어지지 않음

## 답변 품질

* 문법적으로 정확함
* 자연스러운 원어민 표현
* 사용자의 수준에 적합함
* 실제 대화에서 사용할 수 있는 표현
* 핵심부터 말함
* 모범적이지만 교과서처럼 딱딱하지 않음

## 금지

* 사용자 말을 장황하게 반복
* 불필요한 요약
* 과도한 칭찬
* 매번 추가 질문
* 매번 “더 도와드릴까요?”와 같은 마무리
* 긴 서론
* 같은 뜻 반복
* 필요 없는 문법 강의
* AI 내부 판단 설명
* 불필요한 preamble
* “잠시 생각해 볼게요” 같은 지연성 발화

---

# 16. 모드별 instruction 규칙

## Duo

* 현재 화자의 말을 지정된 상대 언어로 통역한다.
* 질문에 답하지 말고 질문 자체를 번역한다.
* 설명, 의견, 조언을 추가하지 않는다.
* 원문의 의미와 말투를 최대한 보존한다.
* 원문이 불명확하면 짧게 다시 말해 달라고 요청한다.
* 번역 이외의 대화를 생성하지 않는다.

## Anyone

* 자연스러운 영어 대화 상대 역할을 한다.
* 사용자가 이어서 말할 공간을 남긴다.
* 일반 답변은 1~2문장으로 한다.
* 사용자가 요청하지 않으면 문법을 설명하지 않는다.
* 사용자의 말을 그대로 반복하지 않는다.
* 사용자가 틀리더라도 대화 흐름을 우선한다.
* 필요한 교정은 짧고 자연스럽게 한다.

## Roleplay

* 지정된 역할을 끝까지 유지한다.
* 역할 속 대사만 말한다.
* 한 턴당 1~2문장으로 응답한다.
* 역할 밖 설명을 하지 않는다.
* 상황을 혼자 길게 전개하지 않는다.
* 사용자가 대화에 참여할 여지를 남긴다.

## Step Expand 첫 턴

* 사용자의 첫 문장을 정확히 이해한다.
* Step Expand 다음 단계에 적합한 첫 AI 답변만 생성한다.
* 장황한 튜터링을 하지 않는다.
* 첫 턴 완료 후 기존 상태 머신으로 넘길 수 있는 텍스트를 남긴다.

---

# 17. Step Expand 원자적 전환

첫 Realtime 턴에서 legacy 경로로 전환하는 절차는 하나의 원자적 작업처럼 처리한다.

## 완료 조건

다음 정보가 준비되어야 한다.

* 첫 사용자 원문
* 첫 AI 실제 발화 transcript
* 첫 turn ID
* 첫 response ID
* 첫 턴 저장 상태
* Step Expand의 현재 단계
* 다음 legacy turn index

## 전환 절차

1. 새 사용자 입력 차단
2. 진행 중 Realtime 응답 완료 또는 명시적 종료
3. 첫 턴 데이터 메모리에 확정
4. 첫 턴 저장 요청 시작
5. Realtime 입력 트랙 중단
6. Realtime 원격 출력 트랙 중단
7. Data channel 정리
8. PeerConnection 종료
9. Realtime listener 정리
10. 오디오 소유권 none 확인
11. Deepgram 초기화
12. legacy TTS 경로 준비
13. legacyReady 확인
14. 두 번째 턴 입력 활성화

저장 완료를 기다릴 필요는 없지만, 저장 idempotency key가 메모리에 등록된 뒤 전환한다.

---

# 18. 기능 플래그와 롤백

모드별 독립 Remote Config 플래그를 추가한다.

* realtime_duo_enabled
* realtime_anyone_enabled
* realtime_roleplay_enabled
* realtime_step_first_turn_enabled

추가로 전체 긴급 중단 플래그를 둔다.

* realtime_global_kill_switch

기본값은 모두 false로 시작한다.

플래그가 false면 기존 경로를 사용한다.

앱 실행 중 같은 세션의 통신 경로를 임의로 전환하지 않는다.

플래그 변경은 다음 새 모드 진입부터 적용한다.

Production 검증이 끝날 때까지 기존 통신 코드를 삭제하지 않는다.

---

# 19. 작업 순서

## Phase 0 — Savepoint

작업 전 반드시 수행한다.

* 현재 branch 확인
* origin과 동기화 확인
* 작업트리 확인
* 기존 변경사항 분리
* savepoint commit
* 기존 debug APK 보관
* 기존 핵심 모드 타이밍 로그 보관

---

## Phase 1 — 읽기 전용 구조 조사

아직 코드를 수정하지 않는다.

다음을 실제 코드에서 확인해 보고한다.

* 각 모드의 마이크 시작·종료 위치
* PTT 또는 VAD 방식
* Deepgram 시작·종료 위치
* GPT-4o mini 호출 위치
* GPT-4.1 호출 위치
* TTS-1 호출 위치
* Box 7 호출 경로
* audioplayers 사용 위치
* 기존 Realtime 클래스
* FirstTurnRealtimeVoice 구조
* History 생성 위치
* Firestore await 위치
* turn index 증가 위치
* generation ID 유무
* cancel·barge-in 로직
* dispose·pause·resume 로직
* 과금 타이머 연결 위치
* Step Expand 첫 턴 분기 위치

조사 보고 후 실제 설계와 이 지시문의 불일치를 정리한다.

---

## Phase 2 — 변경 없는 기준 계측

기존 동작을 바꾸지 않고 현재 기준 속도를 기록한다.

필수 로그:

* MIC_START
* MIC_LAST_FRAME
* TURN_END_REQUESTED
* STT_FINAL
* GPT_REQUEST
* GPT_FIRST_DELTA
* GPT_DONE
* TTS_REQUEST
* TTS_FIRST_BYTES
* PLAYBACK_START
* PLAYBACK_DONE

각 모드 최소 20턴을 측정한다.

---

## Phase 3 — 인증과 WebRTC 기반 구축

* ephemeral token 서버
* 사용자 인증
* App Check
* RTCPeerConnection
* 마이크 로컬 트랙
* 모델 원격 트랙
* Data channel
* session update
* dispose
* 오류 로그

이 단계에서는 기존 모드에 연결하지 않는다.

독립 테스트 화면 또는 내부 진단 경로로 검증한다.

---

## Phase 4 — 공용 상태 머신과 AudioPathCoordinator

* 연결 상태
* 턴 상태
* 마이크 소유권
* 출력 소유권
* response ID
* turn ID
* stale event 차단
* dispose 안전성

가짜 이벤트 순서를 이용한 테스트를 먼저 통과시킨다.

---

## Phase 5 — Anyone 내부 테스트 적용

가장 단순한 AI 대화 모드인 Anyone부터 적용한다.

검증 통과 전까지 Roleplay, Duo, Step Expand를 수정하지 않는다.

---

## Phase 6 — Roleplay 적용

Anyone 기반 연결이 안정화된 후 역할 instruction과 상황 문맥을 추가한다.

---

## Phase 7 — Duo 적용

양방향 언어 방향, 화자 구분, 질문을 번역만 하는지 집중 검증한다.

---

## Phase 8 — Step Expand 첫 턴 적용

마지막으로 하이브리드 전환을 적용한다.

이 단계는 가장 복잡하므로 별도 commit으로 분리한다.

---

## Phase 9 — 내부 테스트 롤아웃

플래그를 다음 순서로 활성화한다.

1. 개발자 단일 계정
2. 내부 테스터 소수
3. Anyone
4. Roleplay
5. Duo
6. Step Expand 첫 턴
7. 전체 비공개 테스트

각 단계의 기준을 통과하기 전 다음 단계로 넘어가지 않는다.

---

# 20. 필수 로그

개인정보가 없는 진단 로그를 추가한다.

* REALTIME_TOKEN_REQUEST_START
* REALTIME_TOKEN_READY
* WEBRTC_CONNECT_START
* WEBRTC_CONNECTED
* SESSION_UPDATED
* MIC_TRACK_STARTED
* SPEECH_STARTED
* SPEECH_STOPPED
* RESPONSE_CREATED
* REMOTE_AUDIO_TRACK_RECEIVED
* AUDIO_PLAYBACK_STARTED
* SOURCE_TRANSCRIPT_FIRST_DELTA
* SOURCE_TRANSCRIPT_FINAL
* OUTPUT_TRANSCRIPT_FIRST_DELTA
* OUTPUT_TRANSCRIPT_FINAL
* OOB_TRANSLATION_STARTED
* OOB_TRANSLATION_DONE
* RESPONSE_DONE
* RESPONSE_CANCELLED
* STALE_EVENT_DROPPED
* TURN_SAVE_STARTED
* TURN_SAVE_DONE
* WEBRTC_CLOSED
* LEGACY_HANDOFF_START
* LEGACY_HANDOFF_DONE

로그에 실제 발화 문장, 이메일, 이름, 토큰, API 키를 출력하지 않는다.

---

# 21. 속도 측정 기준

각 턴마다 다음 시간을 계산한다.

* 발화 종료 요청 → response 생성
* 발화 종료 요청 → 첫 원격 오디오 수신
* 첫 원격 오디오 수신 → 실제 스피커 출력
* 발화 종료 요청 → 실제 스피커 출력
* 첫 transcript delta → transcript final
* response 완료 → History 저장 완료

절대 수치만 보지 말고 기존 파이프라인과 비교한다.

초기 목표:

* 기존 대비 발화 종료→재생 시작 평균 30% 이상 단축
* 첫 원격 오디오 수신→실제 출력 지연 300ms 이하
* 텍스트 final 때문에 오디오가 지연된 턴 0건
* Firestore 때문에 오디오가 지연된 턴 0건

네트워크와 기기 차이가 있으므로 평균, 중앙값, p95를 모두 보고한다.

---

# 22. 실제 기기 테스트

에뮬레이터 결과만으로 완료 처리하지 않는다.

최소 테스트:

* Android 실제 기기
* Wi-Fi
* LTE 또는 5G
* 유선 이어폰
* Bluetooth 이어폰
* 휴대폰 스피커
* 작은 목소리
* 빠른 말
* 주변 소음
* 긴 문장
* 문장 중간 멈춤
* 자기 수정
* 사용자 끼어들기
* 20턴 연속
* 30분 연속 세션
* 화면 잠금
* 앱 백그라운드
* 전화·알림으로 오디오 포커스 상실
* 네트워크 끊김과 복구
* 화면 종료 후 늦은 이벤트
* 모드 이동
* Step Expand Realtime→legacy 전환

---

# 23. 품질 테스트 문장

한국어와 영어 각각 다음 유형을 포함해 최소 100턴을 테스트한다.

* 생략된 주어
* 존댓말
* 반말
* 부정문
* 이중부정
* 숫자
* 날짜
* 시간
* 가격
* 주소
* 이름
* 회사명
* 약어
* 영어 고유명사
* 문장 중간 정정
* 애매한 대명사
* 긴 수식어
* 감정 표현
* 관용 표현
* 주변 소음
* 불완전한 문장

Duo에서는 번역 정확성을 평가하고, Anyone과 Roleplay에서는 답변 적절성·길이·자연스러움을 평가한다.

---

# 24. 완료 승인 기준

다음 조건을 모두 만족해야 완료로 인정한다.

## 공통

* analyze 신규 오류 0
* debug build 성공
* release build 성공
* 실제 기기 테스트 성공
* 표준 API 키 앱 노출 0
* transcript release 로그 노출 0
* 중복 마이크 0
* 중복 음성 재생 0
* 중복 AI 응답 0
* 중복 History 저장 0
* 화면 종료 후 오디오 재생 0
* stale event 화면 반영 0

## Anyone

* 모든 턴 Realtime 경로
* 답변 기본 1~2문장
* barge-in 정상
* 원문·번역문 저장 정상

## Roleplay

* 역할 이탈 없음
* 장문 설명 없음
* 상황 문맥 유지
* 원문·번역문 저장 정상

## Duo

* 질문에 대신 답하지 않음
* 언어 방향 오류 없음
* 번역 외 부연 설명 없음
* 원문과 번역문 뒤바뀜 없음

## Step Expand

* 첫 사용자 턴만 Realtime
* 두 번째 턴부터 legacy
* 첫 턴 중복 생성 없음
* 첫 턴 중복 저장 없음
* turn index 오류 없음
* Part 1 / Part 2 정상
* 마이크 충돌 없음
* 음성 출력 충돌 없음

---

# 25. 각 Phase 완료 보고 형식

각 Phase마다 다음을 보고한다.

## 조사 또는 변경 내용

* 확인한 파일
* 변경한 파일
* 실제 호출 경로
* 변경 이유

## 검증

* analyze
* build
* 테스트 시나리오
* 실제 측정값
* 실패 항목

## 위험

* 남은 위험
* 기존 코드와 충돌 가능성
* 롤백 방법

## Git

* commit hash
* 작업트리 상태
* origin 동기화 상태

한 Phase의 결과를 숨기거나 묶어서 보고하지 않는다.

---

# 26. 금지 사항

* 모든 모드를 한 commit에서 변경
* 기존 통신 코드 즉시 삭제
* 앱에 표준 API 키 포함
* 모바일에서 근거 없이 WebSocket 우선 선택
* WebRTC 음성을 TtsQueueManager에 전달
* 음성을 파일로 완성한 뒤 재생
* 텍스트 final 후 음성 재생
* Firestore 저장 후 음성 재생
* UI build 후 음성 재생
* transcript를 모델 이해의 승인 조건으로 사용
* Realtime과 Deepgram 동시 마이크 점유
* Realtime 음성과 TTS-1 동시 출력
* Step Expand에서 두 경로 동시 활성화
* 실패 시 조용히 다른 모델로 전환
* release 로그에 대화 내용 출력
* 실제 기기 확인 없이 완료 판정
* 기존 과금·세션 정책 변경
* 사용자 승인 없이 UI 재설계
* 사용자 승인 없이 다른 모델로 교체

---

# 27. 최종 목표 구조

## Duo

음성 입력
→ `gpt-realtime-2.1-mini`
→ 번역 음성 즉시 출력
→ 원문 transcript와 번역 transcript 병렬 표시
→ 비차단 저장

## Anyone

음성 입력
→ `gpt-realtime-2.1-mini`
→ 짧고 모범적인 AI 답변 음성 즉시 출력
→ 원문·AI 문장·추가 번역문 병렬 처리
→ 비차단 저장

## Roleplay

음성 입력
→ `gpt-realtime-2.1-mini`
→ 역할에 맞는 짧은 대사 음성 즉시 출력
→ 원문·AI 문장·추가 번역문 병렬 처리
→ 비차단 저장

## Step Expand 첫 턴

음성 입력
→ `gpt-realtime-2.1-mini`
→ 첫 AI 답변
→ Realtime 완전 종료
→ 상태 원자적 전달

## Step Expand 이후

Deepgram Nova-3
→ GPT-4o mini
→ TTS-1
→ 기존 Box 7 재생

---

# 최종 핵심 문장

> Realtime 모델이 생성한 음성은 텍스트, UI, 저장, 기존 게이트의 승인을 기다리지 않고 WebRTC 원격 오디오 트랙으로 즉시 재생한다.

> 앱은 모델의 답변을 허가하는 역할을 하지 않고, 마이크·오디오 소유권, 턴 식별, 취소, 기록, 과금 상태만 안전하게 관리한다.

> 전체 개편은 코드상 완성하되, 실제 활성화는 모드별 기능 플래그와 단계별 검증을 통해 진행한다.

이 버전은 이전 지시문보다 **WebRTC 직접 음성 경로, 두 언어 텍스트 후처리, Step Expand 원자적 전환, 롤백 및 단계별 활성화**를 명확히 보강한 최종안입니다.

[1]: https://developers.openai.com/api/docs/guides/realtime-webrtc "
  Realtime API with WebRTC | OpenAI API
"
[2]: https://developers.openai.com/api/docs/models/gpt-realtime-2.1-mini "
  GPT-Realtime-2.1 mini Model | OpenAI API
"

