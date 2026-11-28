# StealthVox (Flutter)

@guide.md
@docs/features.md

기능에 대한 질문·쇼츠 기획은 추측하지 말고 `docs/features.md`와 해당 코드를 먼저 확인하고 답한다.

## 작업 패턴
- 호칭: 사용자는 "실장님". 한국어로 간결하게 답한다.
- 커밋 메시지: `feat:` / `fix:` / `refactor:` / `copy:` / `chore:` 접두사 + "왜 바꿨는지" 한 줄.
- 커밋·merge·push는 요청받았을 때만. 커밋은 이번 작업 관련 파일만 (`git add -A` 금지; `tmp/`, 로그, mp4, json 결과물 제외).
- 검증: 수정 후 `flutter analyze` (error만). 기존 warning 무시.
- 버전: 릴리스 빌드마다 `pubspec.yaml` `1.0.N+N`을 +1, 커밋 메시지 `chore: bump version to N`.
- 확인이 끝났으면 더 파지 않는다. 불확실한 것은 삭제하지 말고 보고.

## 작업 파일 위치
- 최종 결과물만 `C:\sv\stealth_vox\final\`에 보이게 둔다.
- 과정 파일(녹화·목소리·스크린샷·로그·스크립트·중간 영상)은 작업하는 동안 `C:\sv\work\<이름>\`에 두고,
  작업이 끝나면 `C:\sv\archive\<이름>_<날짜>.zip`으로 압축한 뒤 원본 폴더는 지운다.
- F:·G:에는 옮기지 않는다(고장 난 USB 디스크라 느리고 위험하다).

## 음성(TTS) 원칙
- 앱 대화방: Chirp 3 HD(기본 등급은 WaveNet). Gemini 2.5 Flash TTS는 공부방 역할교환(앱이 `engine: 'gemini'`를 보낼 때)만.
  서버 `secure_ai_gateway.js` 기본값이 이렇다(2026-11-28 배포). Gemini는 첫 소리까지 ~3초라 대화방에 쓰지 않는다.
- 쇼츠 제작: 한국어 내레이션 Chirp 3 HD, AI 대사 Gemini Leda.
- 음성 id는 OpenAI 이름이 아니라 `female`/`male` (Duo 상대 음성은 female).

## 슬래시 명령 (`.claude/commands/`)
`/check` 검증 · `/bump` 버전 · `/release` AAB 빌드 · `/commit` 관련 파일만 커밋 · `/deploy-fn` Firebase 배포 · `/log` 진행 요약

## 기억 규칙
- 세션 종료 전 `/log`로 진행·보류 이슈를 정리한다. 코드/git으로 알 수 없는 결정·보류 사유·선호만 메모리에 저장한다.
