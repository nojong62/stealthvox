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

## 🛠️ 개발 환경
- Flutter SDK: `C:\src\flutter` (`android/local.properties`의 `flutter.sdk`, 사용자 PATH 모두 이 경로).
  예전 `F:\flutter`는 디스크 오류(CRC)로 2026-11-26 제거했다. F: 경로를 쓰지 말 것.
- 셸 PATH가 예전 값이면 `C:\src\flutter\bin\flutter.bat`을 직접 부른다.

## 🎬 쇼츠 제작 (Flow)
- Flow 인물 영상은 **Omni 1.2 Flash 360p(1개 8 크레딧)**로 만든다. 720p(24)·Veo는 실장님이 따로 말할 때만.
- 생성 전 비용을 Flow 에이전트에게 먼저 묻고, 실장님 확인 후 만든다.
- 인물은 **사진 1장을 먼저** 만들어 확인받는다(한 장짜리·콜라주 아님·한국인으로 보이는지). 그 뒤 그 사진으로 영상을 만든다.
- 장면마다 인물의 자세·구도를 바꿔 요청한다(같은 사진에서 시작하면 자세가 똑같아진다).
- 360p 영상도 1080x1920 전체 화면에 써도 된다(lanczos 확대 + 약한 unsharp). 크게 확대·일부 잘라 쓸 때만 720p.
- 내려받기는 720p 원본. 작업 폴더 예: `tmp/shorts_freetalk/` (폰 녹화·대사 주입·조립 스크립트).

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
