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

Firebase Console의 dev_test_device FID 교체와 Remote Config 게시가 완료됐다.

지금 빌드 중인 debug APK 설치를 완료한 뒤 다음을 실행해라.

앱 강제 종료
필요하면 앱 데이터 삭제 또는 재설치
앱 실행
Remote Config fetchAndActivate() 완료 확인
realtime_anyone_enabled 실제값 확인
Anyone 모드 진입 후 5초 대기
한 문장 발화
Logcat으로 신규 경로 검증

반드시 다음 항목을 순서대로 보고해라.

realtime_anyone_enabled=true 여부
신규 Anyone WebRTC 분기 진입 여부
createRealtimeClientSecret 호출 여부
App Check 성공 또는 구체적인 오류
App Check Debug Token 출력 여부
PeerConnection 생성 여부
PEER_CONNECTED 여부
Remote audio track 수신 여부
Deepgram·GPT-4o mini·TTS-1 기존 경로가 실행됐는지

realtime_anyone_enabled=true여도 createRealtimeClientSecret과 PeerConnection 로그가 없으면 신규 Realtime 경로가 실행된 것으로 판단하지 마라.

App Check Debug Token이 나오면 실제 UUID 값만 별도로 보고해라. OpenAI API 키, client secret, Firebase 인증 토큰, UID, 이메일과 대화 내용은 출력하지 마라.

Roleplay, Duo, Step Expand와 guide.md는 수정하지 마라.

다음 결과에서 가장 먼저 볼 것은 Remote Config 값이 실제로 true로 읽히는지입니다. 그다음 App Check is required가 나오면 Debug Token 등록 단계로 넘어가면 됩니다.