# TTS 모델 교체 운영 절차

## 현재 프로필

| 프로필 | 기본 모델 | 옵션 계약 | 주요 용도 |
|---|---|---|---|
| conversation | `tts-1` | `speed` | 대화방, 일반 듣기, PCM 스트리밍 |
| expressiveStudy | `gpt-4o-mini-tts` | `instructions` | P2/P3, Keepers, Voice Lab |

모델 선택의 정본은 `lib/custom_code/services/tts_model_policy.dart`다. 호출부에 모델명을 새로 하드코딩하지 않는다.

## Remote Config 키

| 키 | 허용 예시 | 설명 |
|---|---|---|
| `OpenAITtsConversationModel` | 새 모델 ID | 대화용 모델 |
| `OpenAITtsConversationOptionMode` | `speed`, `instructions`, `none` | 대화용 요청 옵션 계약 |
| `OpenAITtsExpressiveModel` | 새 모델 ID | 표현형 학습 모델 |
| `OpenAITtsExpressiveOptionMode` | `speed`, `instructions`, `none` | 학습용 요청 옵션 계약 |
| `OpenAITtsCacheVersion` | `candidate-v1` | 모델 또는 프롬프트 변경 시 캐시 분리 |

빈 값이나 잘못된 값은 안전한 코드 기본값으로 내려간다. 모델을 바꿀 때는 모델·옵션 모드·캐시 버전을 한 묶음으로 변경한다.

## 권장 전환 순서

1. Voice Lab에서 후보 모델의 보이스, PCM/MP3, instructions 지원을 확인한다.
2. 내부 빌드에서 아래 `--dart-define` 강제값으로 검증한다.
3. Remote Config 조건부 대상에 소규모로 모델과 옵션 모드를 적용한다.
4. 첫 음성 지연, 실패율, 음질, 한국어/영어 속도, 실제 비용을 비교한다.
5. 전체 적용 후에도 이전 값을 기록해 즉시 롤백할 수 있게 유지한다.

## 빌드 강제값

Remote Config보다 우선한다. 원격 설정 장애나 긴급 롤백용이다.

- `OPENAI_TTS_CONVERSATION_MODEL`
- `OPENAI_TTS_CONVERSATION_OPTION_MODE`
- `OPENAI_TTS_EXPRESSIVE_MODEL`
- `OPENAI_TTS_EXPRESSIVE_OPTION_MODE`
- `OPENAI_TTS_CACHE_VERSION`

예시:

```text
flutter build apk \
  --dart-define=OPENAI_TTS_CONVERSATION_MODEL=future-tts \
  --dart-define=OPENAI_TTS_CONVERSATION_OPTION_MODE=instructions \
  --dart-define=OPENAI_TTS_EXPRESSIVE_MODEL=future-tts \
  --dart-define=OPENAI_TTS_EXPRESSIVE_OPTION_MODE=instructions \
  --dart-define=OPENAI_TTS_CACHE_VERSION=future-tts-v1
```

## 롤백

Remote Config의 다섯 키를 빈 값으로 되돌리면 현재 코드 기본값으로 복귀한다. 이미 생성된 후보 모델 음성은 캐시 버전이 분리되어 있으므로 기본 모델 캐시와 섞이지 않는다.