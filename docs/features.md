# StealthVox 기능 지도 (2026-11-29 코드 기준)

말로 하는 외국어 연습 앱. AI와 음성 대화 → 대화가 저장되고 → 공부방에서 그 대화로 복습한다.
기능 질문을 받으면 추측하지 말고 아래 파일을 먼저 확인할 것.

## 화면 흐름
Intro(`intro_master`) → Lobby(`lobby_master`: 모국어 Origin / 배울 언어 Target, 음성 등급 선택)
→ StealthRoom(`stealth_room_master`: 모드 메뉴, 쇼츠 링크 팝업) → 각 대화방
→ 대화 기록·공부방(`chat_history_master`) / 스토어(`store_master`)

## 대화방 (3모드)
- **Circle Talk** `widgets/routine_mode_circle_talk.dart` — 서클(주제) 골라 AI와 자유 대화. 저장 id `circle_talk`.
- **Scenario Talk** `widgets/routine_mode_scenario_talk.dart` — 상황극(역할 있음). 저장 id `scenario_talk`.
- **Duo (Duo Call)** `widgets/routine_mode_duo.dart` — 사람 ↔ 사람 통화(WebRTC). 두 방식:
  - 직접 대화: 원음 통화 + 각자 전사. `duo_webrtc_*`, `duo_stt_pipeline`
  - 만능 통역: 상대 말을 내 언어로 번역해 들려줌. `duo_interpreter*`, 서버 `duo_interpreter.js`
  - Duo 게시판(`duo_board_sheet`, 서버 `duo_board.js`): 대화 상대 초대 글·요청·푸시. 비회원 초대 가능(홍보 기간 설정 `app_config/duo_board_promo`).
  - Duo 버디(`duo_buddy_sheet`, 서버 `duo_talk_host.js`): 여러 사람과 대화하겠다고 신청한 회원.
  - 통화 끝난 게스트는 `duo_guest_study_page`(5분 공부방)로 이동.
  - 요금(`duo_billing_policy`): 회원↔회원 각자, 회원↔비회원 회원이 양쪽, 비회원끼리 무료(기본 음성).

## 대화방 공통 기능
- **언어 단계**(`listening_practice`): Step 1 AI가 모국어로 말함 / Step 2 AI만 배울 언어로 답함(듣기 훈련).
- **Free Talk**(`free_talk*.dart`): 처음부터 배울 언어로 대화. 서클톡·시나리오톡 입장 직전에 고름.
  - 유저 문장 교정 [USER_FIX], 말이 막히면 [MEANING_CHECK]로 빠진 조각 하나만 질문(함께 조립, 최대 2번 후 예문).
  - 추론 강도: 막힌 줄만 medium, 나머지 low(`dialog_brain_model.dart`, `freeTalkLineNeedsThought`).
- **원문 복원**(`origin_restoration*`): 대화 후 의심 발화만 PCM 다시 들어 전사를 바로잡음.
- 전사: OpenAI 스트리밍 전사 / Deepgram. AI 응답: OpenAI(서버 `secure_ai_gateway.js` 경유).

## 공부방 (`chat_history_master`)
- 저장된 대화를 다시 보고 연습. P1·P2·P3 단계(P2: AI 다시 듣기, P3: Speaking Practice — Breath Echoing·Full Echo·Shadowing, `breath_echoing_engine`).
- 현지인 표현(`native_expression`), 다른 표현(`alt_style`), 역할 교환(이때만 Gemini TTS).
- 보기는 누구나 무료, 비용 드는 학습 동작은 잔액/체험 있을 때만(`study_access`).
- 방 만드는 다른 경로: 쇼츠 링크(`shorts_scenario_service`), 통화 녹음 가져오기(`recording_scenario_service`), 공부방 체험 10분(`study_trial*`, 관리자 계정 대화 복사).

## 요금·음성
- 잔액은 초 단위 하나(프리미엄 기준). 기본 등급(WaveNet)은 1/2 속도로 차감(`voice_tier`).
- 대화방 TTS: Chirp 3 HD / WaveNet. Gemini는 공부방 역할교환만.
- 구매: RevenueCat(`revenuecat_purchase.js`), 쿠폰·가입 보너스(`coupons.js`, `signup_bonus.js`), 차감 `deduct_time.js`.

## 서버 (`firebase/functions/`, 프로젝트 `stealth-vox-3p3rq3`)
AI 프록시 `secure_ai_gateway.js`(openAiProxy), Duo 관련 `duo_*.js`, 회원 `member_registry.js`·`account_*.js`, 관리자 `admin_ops.js`.

## 테스트 도구 (커밋 금지 WIP)
`services/debug_stt_inject.dart`: 폰에 텍스트 파일을 넣어 유저 발화를 대신 주입(마이크 막고 테스트).
