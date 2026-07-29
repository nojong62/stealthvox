# Anyone Realtime 통신 로직 — 다른 모드 이식용 정리

브랜치 `realtime-secure-webrtc` · 최종 실기기 검증 2026-07-29 (Samsung SM-S931N)

이 문서는 **Anyone에서 실기기로 검증이 끝난 Realtime 통신 구조**를 다른 모드
(Duo / Roleplay / Step Expand)에 옮기기 위한 것이다. 설계안이 아니라 **동작이
확인된 사실**과 **실기기에서 직접 밟은 함정**을 적는다.

`PHASE3_HANDOFF.md`는 커밋 `91ef3b78` 기준이라 낡았다. 첫 턴 GPT-4.1 검수,
"2턴부터 secure realtime" 같은 서술은 이후 폐기됐다. **충돌하면 이 문서가 최신이다.**

---

## 1. 계층 구조

책임이 3층으로 갈린다. 다른 모드는 **3층만 새로 쓰면 된다.**

```
[1] realtime_client_secret_service.dart      (134줄)
    - App Check → Cloud Function createRealtimeClientSecret → client secret
    - RealtimeClientSecretPrewarm: 미리 받아둔 secret 보관/소비 (싱글턴)
    - 모드 무관. 그대로 재사용.

[2] stealth_vox_realtime_session.dart        (1333줄)
    - WebRTC PeerConnection / DataChannel / SDP / ICE / 원격 오디오
    - session.update, 턴 수명주기, 전사 모델 전환
    - UI·Firestore·과금·TTS를 일절 모른다. 그대로 재사용.

[3] realtime_anyone_adapter.dart             (266줄)
    - 세션 이벤트를 모드가 쓰기 쉬운 콜백으로 변환
    - 모드마다 얇게 새로 쓴다 (Duo용/Roleplay용).
      Anyone용을 복사해 콜백 이름만 바꾸는 수준이면 충분하다.

[4] routine_mode_<mode>.dart
    - UI, 말풍선, History, 과금, AI 클론 응답
    - 모드 고유. 여기가 실제 작업량이다.
```

**원칙: [2]에 UI/저장/과금을 절대 넣지 말 것.** 이 분리 덕분에 Anyone에서
검증한 전송 계층을 손대지 않고 다른 모드에 붙일 수 있다.

---

## 2. 검증된 통신 흐름

### 모델은 두 개다 — 헷갈리지 말 것

세션은 하나인데 그 안에 모델 칸이 둘이다. 둘 다 이름에 mini가 들어가서 자주 섞인다.

| 역할 | 설정 위치 | 모델 |
|---|---|---|
| 귀 (받아쓰기) | `session.audio.input.transcription.model` | `gpt-4o-mini-transcribe` |
| 입 (번역 + 음성) | `session.model` | `gpt-realtime-2.1-mini` |

**입 모델은 오디오를 직접 듣지만 글로 돌려주지 않는다.** 듣고 바로 대답만 한다.
그래서 받아쓰기 담당을 따로 붙인다. 전사 텍스트가 필요한 이유는 넷이다 —
번역 지시를 텍스트로 줘야 확인·정정 판정이 낄 자리가 생기고(4.4), 한국어 원문
말풍선/History가 필요하고, 턴 경계를 잡아야 하고, 빈 발화를 걸러야 한다(4.3).

번역 턴은 **오디오가 아니라 전사 텍스트**를 `input_text`로 넣는다
(`stealth_vox_realtime_session.dart` `conversation.item.create`).

실측 로그(2026-07-29 10:16) 기준. 괄호 안은 발화 종료 기준 경과.

```
[스텔스룸 진입]
  stealth_room_master.dart:118  _prewarmAnyoneRealtimeSecret()
  [RT-APPCHECK] success
  [RT-SECRET] success
  [RT-PREWARM] secret_ready mode=anyone      ← 여기서 3초를 미리 벌어둔다

[Anyone 진입]
  [RT-PATH] secure_webrtc mode=anyone
  [RT-PREWARM] secret_reused mode=anyone     ← 발급 대기 없음
  [RT-PC] created
  [RT-MIC] local_track_added                 (+0.19초)
  [RT-SDP] offer_created → answer_applied
  [RT-AUDIO] remote_track_received → speaker_on
  [RT-ICE] connected                         (+2.5초)
  [RT-SESSION] updated_confirmed valid=true
  [RT-TRANSCRIPTION] model=gpt-4o-mini-transcribe language=ko
  [TTS-ROUTE] voice_call=on                  ← AI 음성도 통화 오디오로
  🔐 [RT-TRANSLATE] session ready            (+2.9초, 완전 스탠바이)
  [ANY-RT-STT] listening_started

[유저 발화]
  speech_started / speech_stopped            (서버 VAD)
  [ANY-RT-STT] final_received len=23         (+0.34초)  ← 전사
  🎧 [STT-RAW] text="밥 먹지 말고 기다려…"    ← 전사 원문 (디버그 빌드만)
  🔀 [COMMIT-01] 확정                        (+0.46초)
  🧭 [FIRST-CONTEXT] first_normal_utterance judge=off
  [RT-PATH] anyone_secure_realtime turnId=N
  [RT-TURN] start
  [RT-AUDIO] stream_started                  (+1.79초)  ← 유저 영어 음성 시작
  [RT-AUDIO] text_ready → clone pipeline (parallel)     ← AI 생성 병렬 시작
  [RT-AUDIO] playback_done                   (+5.11초)
  [RT-PLAY] secure WebRTC 원격 오디오 사용
  [PIPE-07] setAiPaused(false)               (+5.36초)  ← AI 음성 (legacy gpt-4o-mini + tts-1)
```

**`[STT-RAW]`이 이 문서에서 가장 중요한 로그다.** 오역이 났을 때 귀가 틀렸는지
입이 틀렸는지 이것 없이는 못 가른다. 화면 한국어 자막은 영어 번역문을 역번역한
것이라 원문 대조에 쓸 수 없다(6-6). 다른 모드에도 반드시 같이 넣을 것.

### 하이브리드가 의도된 설계다

**유저 발화**만 Realtime이 담당한다. AI 클론 응답은 legacy `gpt-4o-mini` +
`tts-1(nova)`를 그대로 쓴다. 버그가 아니다 — 목소리를 갈라 화자를 구분하고,
모드별 페르소나 프롬프트를 기존 경로에서 그대로 쓰기 위함이다.

다른 모드도 이 경계를 그대로 가져가는 것을 권한다. AI 응답까지 Realtime으로
합치는 구조(단일 세션 대화)는 `_startAnyoneConversationSession`에 구현돼 있으나
**호출부가 없는 데드코드**이고 검증되지 않았다.

---

## 3. 다른 모드 이식 체크리스트

1. **Remote Config 게이트 추가** — `realtime_feature_flags.dart`에 모드 키.
   디버그 빌드는 `kDebugMode`로 우회할 수 있게 할 것(실기기 테스트가 막힌다).
2. **어댑터 작성** — `realtime_anyone_adapter.dart` 복사 후 콜백 정리.
3. **연결 시점 결정** — 모드 진입 시 1회. 방을 나갈 때까지 유지.
4. **secret 프리웜 연결** — `stealth_room_master.dart`에 모드용 프리웜 추가.
   진입 지연의 절반가량이 secret 발급이다. 이거 하나로 3초가 빠진다.
5. **voice 매핑 확인** — 아래 4.2 참조. 이걸 놓치면 세션이 통째로 죽는다.
6. **전사 언어 지정** — `transcriptionLanguage`에 모국어 코드.
7. **턴 경계 설계** — 전사 확정 후 파이프라인 시작(4.4 참조).
8. **teardown** — 방 종료 시 활성 턴 취소 → 마이크 해제 → PeerConnection 종료
   → 과금 정지. Anyone은 `[COST] reason=dispose` → `[ANY-MIC] owner_changed
   to=none` → `[BILLING] pause` 순으로 확인됐다.

---

## 4. 실기기에서 밟은 함정

이 절이 이 문서의 핵심이다. 전부 실제로 겪은 것들이다.

### 4.1 릴리스 사이드로드는 App Check를 통과 못 한다

```
W/FirebaseContextProvider: Error getting App Check token.
  code: 403 body: App attestation failed.
→ [RT-SECRET] failed reason=FirebaseFunctionsException
```

릴리스 빌드는 Play Integrity로 검증한다. `adb install`로 넣은 릴리스는
스토어를 안 거쳐서 무조건 실패한다. **실기기 검증은 디버그 빌드로 할 것.**

디버그 빌드는 `AndroidProvider.debug`로 자동 전환된다
(`realtime_client_secret_service.dart:100`, `debugAppCheck || kDebugMode`).
토큰은 **설치·실행 후** logcat에 찍힌다. 순서가 반대가 아니다.

```
D/DebugAppCheckProvider: Enter this debug secret into the allow list ... <UUID>
→ Firebase Console → App Check → 앱 ⋮ → 디버그 토큰 관리에 등록
```

**앱을 재설치하면 토큰이 새로 발급된다. 매번 재등록해야 한다.**

또한 디버그는 debug keystore, 릴리스는 `code-stealth-vox-*.jks`로 서명된다.
서로 덮어쓸 수 없으므로 `adb uninstall`이 필요하고, **앱 데이터가 지워진다**
(로그인 풀림. Firestore 데이터는 재로그인하면 복구).

### 4.2 legacy TTS voice 이름을 Realtime에 보내면 세션이 통째로 죽는다

`fable` / `onyx` / `nova`는 `tts-1` 전용이다. 그대로 보내면 서버가
`session.update` **전체**를 `invalid_value`로 거부하고, 세션이 Deepgram legacy로
폴백된다. 증상이 "Realtime이 안 켜진다"로 나타나 원인을 찾기 어렵다.

`stealth_vox_realtime_session.dart`의 `_supportedRealtimeVoices` /
`_legacyVoiceAliases`가 이미 매핑한다. 다른 모드도 반드시 이 경로를 탈 것.
로비에서 voice를 고르게 한다면 목록 자체를 Realtime 지원 값으로 제한할 것.

### 4.3 빈 전사(잡음)를 fallback 사유로 삼지 말 것

server VAD는 숨소리·에어컨·AI TTS 꼬리도 발화로 잡는다. 그때 전사가 빈 문자열로
온다. 이걸 실패로 처리하면 **아무도 말하지 않았는데 대화가 진행되고 과금이
깎인다.** 실제로 조용한 방에서 5턴이 진행되고 32초가 소모됐다.

빈 전사는 조용히 버리고 다시 듣는다. `_commitAndProcess`의
`[COMMIT-00] 빈 발화 → 마이크 재시작`이 그 처리다.

### 4.4 speech-first(전사 대기 없이 발사)는 쓰지 말 것

발화 종료 즉시 오디오만으로 번역 턴을 발사하면 약 0.4초 빨라진다. 그러나:

- 모델이 오디오를 직접 듣고 **곧바로 말해버려서**, "제가 잘못 들었나요?" 확인
  질문·되묻기·정정 판정이 끼어들 자리가 없다.
- 오인식이 그대로 음성으로 나간다. 실측에서 F등급 오역이 나왔다.
- 잡음 턴이 매번 legacy fallback으로 떨어졌다.

전사(0.4초)를 기다린 뒤 텍스트로 번역하도록 되돌리자 **AI 첫 음성이
11.5초 → 8.2초, legacy fallback 2회 → 0회**가 됐다. 느려지지 않고 빨라졌다.
번역문이 짧고 정확해져 음성 길이 자체가 줄었기 때문이다.

`routine_mode_anyone.dart`의 `_kSpeechFirstEnabled = false`. 되돌리려면 이 값만
바꾸면 되지만, 되돌리지 말 것.

### 4.5 제어 태그는 음성 응답과 함께 쓸 수 없다

`[CLARIFY]` `[CORRECTION]` `[MISHEARD]` `[EVAPORATE]` 같은 대괄호 태그는
**텍스트 먼저 → 검사 → 그 다음 TTS** 구조를 전제로 설계됐다. Realtime은
텍스트와 음성을 동시에 만들어 즉시 재생하므로, 앱이 태그를 발견했을 때는
이미 스피커로 나간 뒤다. 게다가 `output_modalities: ["audio"]`라 모델 입장에서
대괄호 태그는 "소리 내어 읽으라"는 뜻이 된다.

**태그 대신 말해야 할 문장을 직접 지시할 것.** 확인 질문은 이미 그렇게 돼 있다.

```
Output EXACTLY in Korean: 제가 잘못 들었나요? '<들은 단어>'라고 말씀하신 게 맞나요?
```

앱은 `startsWith('제가 잘못 들었나요?')`로 잡는다. 이 방식은 음성으로 나가도
문제가 없다. `[CLARIFY]`는 아직 태그 형태라 **미해결 과제**다.

### 4.6 `output_audio_buffer.stopped`는 올 때도 있고 안 올 때도 있다

WebRTC 오디오 종료 신호다. 대부분 정상 도착하지만 놓친 사례가 있었다
(`[RT-AUDIO] completion_timeout`). 고정 상한만 두면 그 상한이 **긴 음성을
잘라** AI 응답이 유저 음성 꼬리를 덮을 수 있다.

현재는 낭독문 단어수로 남은 시간을 추정해 대기를 좁히되, 5초 상한을 유지한다
(`_estimateRemainingAudio`). **상한이 실제 음성보다 짧아질 수 있다는 점은
아직 미해결이다.**

### 4.7 전사 language를 비워 두면 서버가 언어부터 추측한다

`transcription: {language: null}`이면 언어 판별 단계가 추가된다. 모국어를
못 박을 것. 다만 **동음 오인식은 language로 못 잡는다** — "밥 먹지"가
"겁 먹지"로 인식된 사례가 있다(둘 다 한국어).

어휘 힌트(`prompt`)는 **쓰지 않기로 했다.** 특정 표현으로 인식이 쏠려 사용자가
다른 말을 해도 힌트 쪽에 붙을 위험이 있고, speech-first를 끈 뒤로 전사가
임계 경로라 프롬프트 길이가 그대로 지연이 된다.

현재 구성은 **전 턴 `gpt-4o-mini-transcribe`(경량)**다. 정밀 모델은 쓰지 않는다.

**정밀 모델 논쟁은 2026-07-29 실측으로 종결됐다.** 같은 문장을 같은 톤으로
양쪽에 넣어 나란히 비교한 결과:

| 문장 | 경량 | 정밀 |
|---|---|---|
| 왜 어제 안 왔어? | "왜 오지 않았어?" ❌ | "왜 오지 않았어?" ❌ (2회 모두 동일) |
| 나 아까 밥 먹었어 | ✅ | **"나가 밥 먹었어."** ❌ |
| 전사 지연 | 0.51초 | 0.51초 |

정밀 모델은 **경량이 틀리는 문장을 똑같이 틀렸고**(글자 하나 다르지 않았다),
**경량이 맞히던 문장은 퇴행시켰다.** 지연 차이도 없었다. 비싸기만 하다.

과거에 "정밀이 0.24초 느리다"고 기록해 뒀으나 이번 조건에서는 재현되지 않았다.
어느 쪽이든 정밀을 쓸 이유는 없다.

**등급으로 못 넘는 벽이 있다.** "어제 안 왔어"[어제아놔써]와 "오지 않았어"
[오지아나써]는 음향적으로 거의 겹친다. 모델은 단어를 흘린 게 아니라 문법적으로
더 매끄러운 쪽으로 재분절한다. 두 등급이 같은 답을 내놓는 것이 그 증거다.
이런 구간은 모델을 바꿔서 해결되지 않는다.

### 4.8 발화 앞부분이 잘리면 모델이 앞을 지어낸다 (prefix_padding)

**오인식의 가장 큰 원인은 모델이 아니라 VAD 설정이었다.**

server VAD는 발화 시작을 감지한 시점부터 오디오를 보내되, 그 **앞의 일정 구간을
같이 담아** 첫 음절이 잘리지 않게 한다. 그 길이가 `prefix_padding_ms`다.
기본 300ms로는 **말을 툭 던지듯 시작할 때 첫 음절이 잘려 나갔고, 모델이 잘린
앞을 통째로 지어냈다.**

| 발화 | padding 300 | **padding 600** |
|---|---|---|
| 왜 어제 안 왔어? | "배우 있지 않아서?" / "악사 왜 오지 않아서" | "왜 오지 않았어?" |
| 밥 먹지 | "밟" | **"밥 먹지." ✅** |
| 나 아까 밥 먹었어 | — | ✅ |
| 너 방금 뭐라고 했어? | — | ✅ |
| 내일 학교 안 가? | — | ✅ |

문장 **앞**이 살아나자 나머지가 따라왔다. 실측 6문장 중 5문장이 정확해졌다.
`stealth_vox_realtime_session.dart`의 `turnDetection['prefix_padding_ms'] = 600`.

**공짜다.** 이미 지나간 소리를 더 담는 것이라 응답이 늦어지지 않는다. 전사 지연은
padding 300일 때와 같은 0.51초였다.

주의: 이 값은 `_autoRespond` 분기 **밖**에 둬야 한다. 안에 두면 음성 직결 모드
에서만 적용되고 전사 경로에는 안 걸린다(실제로 그렇게 잘못 들어가 있었다).

진단 요령 — 오인식이 났을 때 **틀린 자리가 문장 앞이면 padding을 의심**하고,
가운데·뒤가 흔들리면 padding으로 해결되지 않는다(4.7).

### 4.9 session.updated 검증을 과하게 하지 말 것

서버가 요청한 설정을 전부 에코하지 않는다. 선택 필드가 없다고 실패 처리하면
멀쩡한 세션이 Deepgram으로 폴백된다. 성공 조건은 **세션 객체 정상 + turn
detection이 실제로 server_vad**까지다. 반대로 명백히 다른 값이 돌아오면 계속
실패 처리한다. `_confirmSessionUpdated` 참조.

---

## 5. 측정 기준선 (Anyone, 디버그 빌드, Wi-Fi)

같은 문장을 반복 측정한 값이다. 다른 모드를 붙일 때 비교하면 어디가 새는지
바로 보인다.

| 구간 | 값 |
|---|---|
| 스텔스룸 진입 → secret 준비 | 약 3.3초 (프리웜, 백그라운드) |
| Anyone 진입 → 세션 스탠바이 | 2.6~2.9초 |
| 마이크 활성화 | 진입 +0.19초 |
| 발화 종료 → 전사 확정 | 0.41초 (mini) / 0.65초 (정밀) |
| 발화 종료 → 유저 영어 음성 시작 | 1.2~1.8초 |
| 발화 종료 → 유저 음성 재생 완료 | 5.0~5.7초 |
| **발화 종료 → AI 첫 음성** | **6.9~7.6초** |

### 구조를 바꾸며 줄어든 이력

| 구성 | AI 첫 음성 | 번역 품질 |
|---|---|---|
| speech-first (전사 대기 없음) | 11.5초 | F — 구조 붕괴 |
| 전사 기반 + mini, language 없음 | 8.15초 | 오인식(겁 먹지) |
| 전사 기반 + 정밀, language=ko | 8.36초 | ✅ |
| **전사 기반 + 정밀/mini, language=ko** | **6.87초** | ✅ |

**정확도가 곧 속도였다.** 오역이 나오면 번역문이 길어지고(17단어), 그만큼
음성이 길어져(5.3초) 턴 전체가 늘어진다. 정확해지자 9단어/2.5초로 줄었다.

---

## 6. 아직 안 풀린 것

1. ~~AI 응답 생성이 순차적이다.~~ → **구현됨(`3a806241`), 단 실기기 미검증.**
   `turn.done`이 오디오 재생 완료까지 기다려 번역문 도착 자체가 3~5초 늦었다.
   텍스트 확정 시점을 `textOutcome`으로 분리해 AI 생성·TTS를 유저 음성 뒤에
   숨긴다. 예상 −2.7초.
   **다음 세션에서 반드시 확인할 것: AI 음성이 유저 음성 위에 겹치지 않는가.**
   재생 게이트는 STEP 5(`waitUserDrained` + `audioComplete`)가 그대로 막고
   있어야 한다. 겹치면 이 커밋을 되돌리는 것이 가장 빠르다.
2. `[CLARIFY]` 태그가 음성으로 읽힐 수 있다 (4.5).
3. 오디오 종료 5초 상한이 긴 음성을 자를 수 있다 (4.6).
4. ~~첫 발화 정밀 전사 모델이 정말 필요한지 미확정.~~ → **종결(2026-07-29).**
   정밀 모델은 개선이 없고 오히려 퇴행시켰다. 전 턴 경량으로 확정 (4.7).
   남은 오인식은 동음에 가까운 구간의 재분절이라 모델 등급으로 못 넘는다.
5. `_costTracker.recordRealtimeResponse`가 WebRTC 경로에서 토큰을 못 받는다
   (`realtime_request_count=0`으로 찍힘). 과금 집계가 실제와 다르다.
6. 한국어 자막(`original`)을 `generateCleanOriginal`이 gpt-4o-mini로 영→한
   역번역해 매 턴 만든다. 전사가 이미 원문을 주므로 중복이다.

---

## 7. 모드별 이식 현황 — Step Expand 점검 (2026-07-29)

Step Expand는 이미 `RealtimeAnyoneAdapter`를 쓰고 있다. 계층 구조는 맞게 탔고,
**세션 계층([2])을 공유하므로 4.8 prefix_padding 600은 자동으로 적용된다.**
아래는 코드 대조로 찾은 차이다. 실기기 실측은 아직 안 했다.

### 그대로 따라간 것

| 항목 | 상태 |
|---|---|
| 계층 분리 ([1][2] 재사용, 어댑터 경유) | ✅ |
| secret 프리웜 (`_prewarmStepExpandRealtimeSecret`) | ✅ |
| voice 매핑 (세션 계층 경유, `echo` 기본) | ✅ |
| 전사 모델 (인자 생략 → 경량 기본값) | ✅ 결과적으로 일치 |
| prefix_padding 600 | ✅ 세션 계층에서 자동 |

### 고쳐야 할 차이

**① `transcriptionLanguage`를 안 넘긴다 — 확정 결함 (4.7 정면 위반)**

`routine_mode_step_expand.dart:1957` `connectForMicrophoneTranscription(...)`에
`transcriptionLanguage` 인자가 없다. 어댑터 기본값이 `null`이라 **서버가 언어부터
추측한다.** Anyone에서 오인식("밥 먹지" → "겁 먹지")을 만든 바로 그 조건이다.

```dart
// Anyone (routine_mode_anyone.dart:1485)
transcriptionLanguage: _mapLanguageToCode(
  FFAppState().nativeLang.isNotEmpty ? FFAppState().nativeLang : 'Korean'),

// Step Expand — 이 줄이 없다
```

Step Expand에는 `_mapLanguageToCode`가 이미 있다(Deepgram 경로에서 쓴다).
한 줄 추가면 끝난다. **가장 먼저 고칠 것.**

**② `[STT-RAW]` 로그가 없다**

`[STEP-RT-STT] final_received len=23`처럼 길이만 찍는다. 2절에 적었듯 오역이
났을 때 귀가 틀렸는지 입이 틀렸는지 이것 없이는 못 가른다. Step Expand는 오늘 같은
padding 실측 자체가 불가능한 상태다. Anyone과 같은 형식으로 넣을 것.

**③ 잡음·추임새 필터가 두 군데서 다 약하다**

- 어댑터 콜백(`:1916`): `clean.length < 2`만 본다. **"음."은 2자라 통과한다.**
  Anyone에서 이게 "Um."으로 번역돼 유저 목소리로 나갔다.
- 파이프라인(`:2690`): `ghostWords` 하드코딩 목록. Anyone은 이 목록을
  `_isNoiseTranscript` 하나로 통합했다(같은 사고의 재발 방지).

**④ 연결 후 ready 대기가 없다 — 마이크가 안 열린 채 멈출 수 있다**

`:1967`에서 connect 직후 `_startUserListening()`을 다시 부르는데, 이때
`_stepRealtimeConnecting`이 아직 `true`다(`finally`가 그 뒤에 돈다).
세션이 그 시점에 `ready`가 아니면 `_isStepRealtimeUsable`이 false →
`if (_stepRealtimeConnecting) return;`에 걸려 **조용히 빠져나가고 아무도 다시
부르지 않는다.** Anyone은 `_waitForTranslateSessionUsable` 후 실패 시 명시적으로
fallback한다. 같은 구조를 넣을 것.

**⑤ `onError`면 무조건 Deepgram으로 떨어진다**

Step Expand도 `cancelActiveTurn()`을 쓰므로(`:3048`, `:6149`) 이미 끝난 응답에
취소가 나가 서버 error가 올 수 있다. 그 한 번에 세션이 legacy로 내려가고 이후
모든 턴이 Deepgram이 된다. 세션 계층의 benign 에러 무시가 들어가면 이 건은
공유로 해결되지만, **그 외 에러에 대한 즉시 폴백은 여전히 과하다**(4.9의 정신).

### 권장 순서

1. ① `transcriptionLanguage` 한 줄 — 즉시, 효과 확실
2. ② `[STT-RAW]` 로그 — 이게 있어야 나머지를 측정할 수 있다
3. 실기기 실측 (Anyone과 같은 문장 6개로 대조)
4. ③④⑤ — 측정 결과 보고 판단

---

## 8. 로그 태그 사전

| 태그 | 의미 |
|---|---|
| `[RT-APPCHECK]` | App Check 초기화. success여도 토큰 발급은 별개 |
| `[RT-SECRET]` | client secret 발급 |
| `[RT-PREWARM]` | secret 미리 받기 / 재사용 |
| `[RT-PATH]` | 이 턴이 실제로 탄 경로. `anyone_secure_realtime`이 정상 |
| `[RT-PC]` `[RT-SDP]` `[RT-ICE]` | WebRTC 연결 단계 |
| `[RT-SESSION]` | session.update 확인 |
| `[RT-TRANSCRIPTION]` | 전사 모델·언어 설정, 모델 전환 |
| `[RT-TURN]` | 턴 시작/완료/취소 |
| `[RT-AUDIO]` | 원격 오디오 시작·종료·타임아웃 |
| `[RT-PLAY]` | 실제 재생 경로 (WebRTC인지 legacy TTS인지) |
| `[ANY-RT-STT]` | Anyone 전사 상태 |
| `[ANY-MIC]` | 마이크 소유권 이동 |
| `[COMMIT-00/01]` | 발화 확정 / 빈 발화 폐기 |
| `[RT-FALLBACK]` `[ANY-RT-FALLBACK]` | legacy 전환. **정상 테스트에서는 0회여야 한다** |

정상 세션이면 `[RT-FALLBACK]`, `[DG-]`, `[TTS-01] [USER]`가 찍히지 않는다.
AI 응답의 `[TTS-01] [AI]`는 정상이다(하이브리드 설계).
