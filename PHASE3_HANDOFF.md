> ⚠️ **이 문서는 낡았다 (커밋 `91ef3b78` 기준).**
> 이후 첫 턴 GPT-4.1 검수는 폐기됐고, secure realtime은 2턴이 아니라 1턴부터
> 적용되며, speech-first는 도입됐다가 다시 제거됐다.
> **최신 정본은 `REALTIME_ANYONE_PATTERN.md`다.** 충돌하면 그쪽이 맞다.
> 이 문서는 Phase 2~3 초기 경위 기록으로만 남긴다.

# Realtime 보안 WebRTC 이전 — 진행 상황 핸드오프

브랜치: `realtime-secure-webrtc` · 마지막 갱신 기준 커밋: `91ef3b78`
참고 지시문: `guide1.md` (전체 Phase 계획), 정책은 B안으로 확정.

---

## 1. 지금까지 완료 (커밋됨)

| 커밋 | 내용 |
|------|------|
| `bc73273` | 신규 보안 WebRTC 계층 최초 추가(이전 작업) |
| `02c9439b` | **Phase 2**: RT-* 로그 계측 + CloneTestPage 프로브. 실기기에서 App Check→client secret→PeerConnection→ICE→원격오디오 재생 **end-to-end 검증 성공** |
| `91ef3b78` | **Phase 3 Step 2**: `StealthVoxRealtimeSession.requestTranslatedTurn` + `RealtimeAnyoneAdapter` 턴 API. **아직 운영 파이프라인 미연결** |

### Phase 2 실기기 검증 결과 (성공)
`[RT-APPCHECK] success → [RT-SECRET] success → [RT-PC] created → [RT-SDP] offer/answer → [RT-ICE] connected/completed → [RT-AUDIO] remote_track_received → playback_started`
- 근본 원인이던 **App Check debug token 미등록**을 Firebase Console에 등록해 해결.
- 실기기: Samsung SM-S931N. debug 빌드로 설치. (USB 불안정 이력 있음)

---

## 2. 확정된 설계 (Phase 3 = B안)

**B안 = 유저 발화의 "번역 텍스트 + 번역 음성" 구간만 신규 보안 WebRTC로 교체.**
AI 클론 응답 / Nova TTS / 제어태그 / History / 과금 / 첫발화 문맥판정(`_firstUtteranceJudge`)은 **기존 구조 유지**. A안(지속형 대화 재설계)은 범위 제외.

- **첫 번째 정상 턴**: 기존 경로 유지. (Step 4에서 GPT-4.1 검수 추가 예정: Realtime text-only 초안 → GPT-4.1 검수 → 최종문 → **legacy TTS로 음성**, `[RT-FIRST-REVIEW] audio_path=legacy_tts_after_review`. Realtime는 검수본 verbatim 낭독 불가라 첫 턴 음성만 legacy TTS.)
- **두 번째 턴부터**: 신규 WebRTC 번역(text+audio), WebRTC 라이브 트랙 재생, `audioComplete` 후 AI 클론 재생. `[RT-PATH] anyone_secure_realtime`.
- **실패 폴백**: 해당 턴만 기존 gpt-4o-mini 번역 + TTS. **FirstTurnRealtimeVoice로 폴백 금지**. 세션 드롭 시 다음 턴 전 1회 재연결(무한루프 금지).
- **오디오 순서(1번 확정)**: 번역 오디오 완료(`audioComplete`)까지 AI 클론 Nova TTS 재생 보류. 5초 폴백 timeout이면 `[RT-AUDIO] completion_timeout` 로그 후 클론 진행.

### Step 3 착수 전 확정 필요했던 트레이드오프 (권장안, 사용자 최종확인 대기)
- **A. 턴2+ 텍스트 표시**: 권장 = `turn.done`까지 대기 후 **최종문 1회 표시**(폴백이 깨끗함). 실시간 델타 표시는 포기.
- **B. 턴2+ 제어태그 오디오 아티팩트**: WebRTC 라이브 트랙은 사전 차단 불가 → 번역문이 `[CORRECTION]`/`[EVAPORATE]` 등일 때 오디오가 먼저 잠깐 재생될 수 있음. 권장 = 수용 + 로그(드묾). 텍스트/로직 처리는 정상.
- **C. AI 클론 생성 병렬성**: 권장 = 순차(단순·안전). 병렬 준비는 후속 최적화.

---

## 3. Step 2에서 추가된 재사용 API

`lib/custom_code/services/stealth_vox_realtime_session.dart`
- `connect(..., bool captureMicrophone = true, bool disableServerVad = false)` — Anyone은 `captureMicrophone:false`(RecvOnly 트랜시버로 원격오디오만 수신) + `disableServerVad:true`(`audio.input.turn_detection=null`).
- `RealtimeTranslationTurn requestTranslatedTurn({turnId, sourceText, instructions, voice, suppressAudio, turnTimeout=20s, audioTailTimeout=5s, audioStabilization=250ms})`
  - `conversation.item.create`(input_text) + `response.create`(text-only=`['text']` / audio=`['audio']`).
  - 반환 핸들: `textStream`(delta), `finalText`, `audioComplete`, `done`(`RealtimeTurnOutcome`), `responseId`.
  - 동시 활성 응답 1개 강제(초과 시 StateError → 호출부 직렬화). 다른 response.id 이벤트는 stale 폐기.
- `cancelActiveTurn()`, `activeTurn` getter.

`lib/custom_code/services/realtime_anyone_adapter.dart`
- `connectForTranslation({modeSessionId, voice, allowWhenDisabled})`, `requestTranslatedTurn(...)`, `cancelActiveTurn()`. 생성자 optional `logger`. 기존 bare-conversation API는 보존.

### 미검증 런타임 위험 (실기기 확인 필요)
1. `output_audio_buffer.started/stopped`(WebRTC 오디오 완료 신호)가 gpt-realtime-2.1-mini에서 실제 오는지. 안 오면 5s 폴백으로 동작(지연).
2. 텍스트 이벤트명: text-only=`response.output_text.*`, audio=`response.output_audio_transcript.*` (둘 다 수집하도록 방어됨).
3. 마이크 미첨부(RecvOnly)로 원격 오디오 트랙 실제 수신되는지.

---

## 4. Step 3 실제 수정 지점 (아직 미구현)

파일: `lib/custom_code/widgets/routine_mode_anyone.dart` (+ 필요 시 adapter 최소 보완)

1. **필드**: `RealtimeAnyoneAdapter? _translateAdapter;` `bool _translateReconnectTried = false;`
2. **`_ensureTranslateSession()`**: 1회 연결(`connectForTranslation`, `allowWhenDisabled:true`, logger `_log`). 1회 재연결 가드.
3. **경로 게이트** (`_startFreeTalkSession`, ~L569): `RealtimeFeatureFlags.enabledFor('anyone')` ON → bare `_startRealtimeAnyoneSession()` **대신** `_ensureTranslateSession()` + `_startDeepgramListening()`. (bare 메서드는 삭제 말고 호출만 제거)
4. **파이프라인** (`_processRelayPipeline`, ~L1391–2303):
   - `usingSecureRealtime = enabledFor('anyone') && currentTurnId >= 2 && _translateAdapter?.session.isReady == true`.
   - `realtimeVoice`를 **nullable**로 (secure면 생성 안 함, `_cancelPrewarmedRealtimeVoice()`).
   - `userStream` 소스 분기 (secure = adapter 경유).
   - tts-1 발사 억제 가드(~L1660 `!realtimeVoice.active` → `... && !usingSecureRealtime`).
   - post-loop 오디오(~L1977–2008): secure면 유저 오디오 큐 적재 skip(WebRTC 자동재생), 실패 시 legacy 폴백.
   - **오디오 게이트 핵심**(~L2190–2193 `realtimeVoice.playbackDone`): secure에선 `secureTurn.audioComplete` 기반. (권장 A 채택 시 streamUserTranslation 내부에서 이미 done까지 await → 여기선 `realtimeVoice?.playbackDone ?? Future.value()`)
   - 산재한 `realtimeVoice.cancel()`(1667/1684/1957/1983)에 `?.` + `_translateAdapter?.cancelActiveTurn()`.
   - `_costTracker.recordRealtimeResponse`(1998)는 WebRTC라 토큰 취득 불가 → 0 또는 별도 처리.
5. **`streamUserTranslation`** (~L4548): optional 파라미터 `secureAdapter, secureTurnId, secureVoice, onSecureTurn` 추가. secure면 sysPrompt/userContent 빌드 후 `requestTranslatedTurn` → (권장 A) `await turn.done` → 성공 시 `yield finalText; return`, 실패 시 기존 gpt-4o-mini 코드(4659+)로 **fall through**(폴백). 프롬프트 빌드는 이 함수 한 곳에 유지.
6. **dispose/정리**: `_translateAdapter?.dispose()` 추가.

### 절대 수정 금지
`first_utterance_context_judge.dart`, `first_turn_realtime_voice.dart`(파일 자체), Step Expand, Duo, Roleplay, History 스키마, 과금 정책, AI 클론 응답 구조.

---

## 5. Step 3 검증 체크리스트
1. 변경파일 `flutter analyze` error 0
2. 첫 턴 기존 경로 정상
3. 2턴+ `[RT-PATH] anyone_secure_realtime`
4. 2턴+ 기존 번역 TTS 중복 실행 없음
5. Realtime 번역 오디오 종료 후 AI 클론 음성 시작
6. 3턴+ 동일 WebRTC 세션 재사용(새 PeerConnection 생성 안 함)
7. 턴 실패 시 레거시 폴백 1회만
8. 세션 종료 시 활성 턴 + WebRTC 세션 정상 정리

이후: **Step 4**(첫 턴 GPT-4.1 검수), Step 5(레거시 폴백 마감), Step 6(실기기 1/2/다중 턴 검증) → Phase 4(Step Expand) → Phase 5(Duo) → Phase 6(Roleplay) → Phase 7(폴백/중복차단 총점검) → 마지막에 `FirstTurnRealtimeVoice` 제거 판단.

---

## 6. 미커밋 WIP (내 작업 아님, 손대지 말 것)
`.flutter-plugins-dependencies`, `guide.md`, `lib/main.dart`, `lib/custom_code/widgets/routine_mode_anyone.dart`(기존 7줄 변경), `guide1.md` — 세션 시작 시점부터 존재한 사용자 WIP.

## 7. 기타
- 실기기 debug 빌드에 등록한 App Check debug token은 바탕화면 `appcheck_debug_token.txt`에 있었음(등록 후 삭제 권장). 재설치 시 토큰 재발급되므로 Console 재등록 필요.
- 커밋/푸시는 요청 시에만. 현재 미푸시.
