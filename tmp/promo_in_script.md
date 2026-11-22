# 인도 쇼츠 대본 v1 (면접 / 대화=힌디어, 배울 언어=영어, 약 40초)

## 검수용 대사 (GPT·Gemini에 이 표를 그대로 붙여 확인)
힌디어가 자연스러운지, 영어 '세련된 버전'이 면접에서 어색하지 않은지 확인 요청.

| # | 힌디어 (평범하게 말함) | 평범한 영어 | 세련된 영어 |
|---|---|---|---|
| 1 | मैं आपकी टीम में पूरी मेहनत से काम करना चाहता हूँ। | I want to work hard in your team. | I'm eager to contribute my best to your team. |
| 2 | मेरी सबसे बड़ी ताकत यह है कि मैं दबाव में भी शांत रहता हूँ। | My biggest strength is that I stay calm under pressure. | My greatest strength is staying composed under pressure. |
| 3 | मैं अपनी हर गलती से कुछ सीखने की कोशिश करता हूँ। | I try to learn from my mistakes. | I treat every mistake as an opportunity to grow. |
| 4 | क्या आप इस भूमिका के बारे में थोड़ा और बता सकते हैं? | Can you tell me more about this role? | Could you tell me what success looks like in this role? |

## 구성 (1080x1920, v12 틀 + 세이프 존)
| 초 | 화면 | 자막 / 내레이션(영어) |
|---|---|---|
| 0~4 | 면접장, 질문 앞에서 말문 막힘 연출 | "You know the answer in Hindi." |
| 4~7 | 제목 카드 | "Say it. Sound polished in English." |
| 7~17 | 앱: 힌디어 #1 → 평범한 영어 → 세련된 영어 + AI 음성 | 세련된 영어 자막 강조 |
| 17~27 | #2 같은 흐름 + 쉐도잉(내가 따라 말함) | |
| 27~34 | #3·#4 빠른 컷 | "Every answer, upgraded." |
| 34~40 | Play 링크 + 앱 아이콘 + "First hour free", 아래 작은 글씨 "up to 3 hours with Standard voice" | "Your first hour is free. Choose Standard voice and it lasts up to three hours. StealthVox." (약 18단어) |

※ 3시간 문구는 기본 음성 기능이 Play 라이브 빌드에 있을 때만. 없으면 "Your first hour is free. StealthVox."로 되돌린다.
※ 영상 속 음성은 기본 음성(WaveNet)으로 녹화한다(3시간을 내세우므로).
※ 앱 안 문구: 로비 "같은 잔액으로 3배 오래 연습", 프리미엄 음성 = HD 음성으로 개명됨(11-10).

## 메모
- 지원 확인: 로비 언어 목록(14개)에 Hindi 있음, Chirp hi-IN 음성 있음(secure_ai_gateway.js).
- 실기기에서 힌디어 STT 인식과 화면 녹화 흐름은 아직 실제로 확인 전.
- 게시: 유튜브 쇼츠·인스타 릴스(틱톡은 인도 차단). 설명에 AI 음성 고지·Play 링크·1시간 무료, 쿠폰 없음.
