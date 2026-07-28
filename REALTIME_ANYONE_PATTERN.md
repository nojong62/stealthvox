# Anyone Realtime 통신 로직 — 다른 모드 이식용 정리

브랜치 `realtime-secure-webrtc` · 기준 커밋 `bdab867f` · 최종 실기기 검증 2026-07-28 (Samsung SM-S931N)

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

실측 로그(2026-07-28 21:11) 기준. 괄호 안은 발화 종료 기준 경과.

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
  [RT-AUDIO] remote_track_received
  [RT-ICE] connected                         (+2.5초)
  [RT-SESSION] updated_confirmed valid=true
  🔐 [RT-TRANSLATE] session ready            (+2.9초, 완전 스탠바이)
  [ANY-RT-STT] listening_started

[유저 발화]
  speech_started / speech_stopped            (서버 VAD)
  [ANY-RT-STT] final_received len=23         (+0.43초)  ← 전사
  🔀 [COMMIT-01] 확정                        (+0.53초)
  [RT-PATH] anyone_secure_realtime turnId=N
  [RT-TURN] start suppress_audio=false
  [RT-AUDIO] stream_started                  (+2.10초)  ← 유저 영어 음성 시작
  [RT-AUDIO] stop_signal=output_audio_buffer.stopped (+5.14초)
  [RT-AUDIO] playback_done                   (+5.40초)
  [RT-PLAY] secure WebRTC 원격 오디오 사용
  → clone pipeline (AI 응답은 legacy gpt-4o-mini + tts-1)
  AI 첫 음성                                  (+8.15초)
```

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

현재 구성은 **첫 발화만 `gpt-4o-transcribe`, 이후 `gpt-4o-mini-transcribe`**다.
첫 문장이 상대와 상황을 정하므로 거기만 비용을 더 쓴다.
(`setTranscriptionModel`, `_accurateTranscriptionSpent`)

**단, 정밀 모델이 실제로 필요한지는 아직 확정되지 않았다.** 같은 문장
("밥 먹지 말고 기다려. 나 곧 도착하니까.")으로 측정한 결과:

| 시각 | 모델 | language | 결과 |
|---|---|---|---|
| 21:11 | mini | **없음** | "Don't panic…" ❌ (겁 먹지로 오인식) |
| 21:44 | 정밀 | ko | ✅ |
| 21:51 1턴 | 정밀 | ko | ✅ |
| 21:51 2턴 | **mini** | ko | **✅** |

성공/실패를 가른 변수는 모델이 아니라 **`language` 지정**으로 보인다. mini도
언어만 못 박으면 정확했고 **0.24초 더 빨랐다**(전사 0.41초 vs 0.65초).

표본이 조건당 1개뿐이라 단정하지 않았다. 같은 세션에서 4~5턴 반복해 mini가
계속 정확하면 정밀 모델을 빼도 된다(비용↓, 첫 턴 0.24초↓, 코드 단순화).

### 4.8 session.updated 검증을 과하게 하지 말 것

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

1. **AI 응답 생성이 순차적이다.** 유저 음성이 재생되는 3~5초 동안 AI 생성이
   시작되지 않는다. 병렬로 돌리면 약 2.7초가 통째로 사라진다. 원래 설계 의도는
   "AI **재생** 보류"였는데 구현은 "**생성**까지 보류"다. **가장 큰 남은 레버.**
2. `[CLARIFY]` 태그가 음성으로 읽힐 수 있다 (4.5).
3. 오디오 종료 5초 상한이 긴 음성을 자를 수 있다 (4.6).
4. **첫 발화 정밀 전사 모델이 정말 필요한지 미확정** (4.7). 실측에서 mini도
   `language`만 지정하면 정확했고 오히려 0.24초 빨랐다. 조건당 표본 1개라
   결론을 못 냈다. **같은 세션에서 4~5턴 반복하면 답이 나온다** — 1턴만
   정밀이고 나머지는 전부 mini이므로, mini가 계속 정확하면 정밀을 빼도 된다.
5. `_costTracker.recordRealtimeResponse`가 WebRTC 경로에서 토큰을 못 받는다
   (`realtime_request_count=0`으로 찍힘). 과금 집계가 실제와 다르다.
6. 한국어 자막(`original`)을 `generateCleanOriginal`이 gpt-4o-mini로 영→한
   역번역해 매 턴 만든다. 전사가 이미 원문을 주므로 중복이다.

---

## 7. 로그 태그 사전

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
