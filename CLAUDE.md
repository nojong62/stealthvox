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

### 절차는 작업 크기에 맞춘다
모든 작업에 브랜치를 파고 백업 커밋을 만들 필요는 없다.

**작은 작업** — 한두 파일 수정, 버전 변경, 오타, 포맷, 빌드:
> 뭘 할지 한 줄 요약 → 수정 → `flutter analyze` → 보고

**일반 작업** — 기능 추가·수정:
> 계획 요약하고 동의 받기 → 관련 파일 분석 → 수정 → `flutter pub get` → `flutter analyze`
> → `git diff` 확인 → 수정 파일 목록·핵심 변경사항·남은 이슈 보고

**큰 작업** — 여러 화면에 걸치거나 되돌리기 어려운 변경:
> 위 절차 + 작업 브랜치 생성

### 백업 커밋
되돌리기 어려운 작업에서만 만든다. 만들 때는 **이번 작업과 관련된 파일만** 담을 것.
관계없는 작업 중인 파일을 "백업"이라며 같이 커밋하지 말 것 — 내 WIP를 멋대로 커밋하는 셈이다.

### 커밋 · 머지 · push
**요청받았을 때만** 한다. 알아서 main에 머지하거나 원격에 push하지 않는다.
단, 릴리스 빌드의 버전 변경은 출시본 추적이 끊기므로 커밋을 먼저 제안할 것.

### flutter analyze
이 저장소엔 warning/info가 600건 넘게 누적돼 있다 (대부분 생성 코드의 unused_import).
**error만 해결 대상**이다. 내 작업이 새로 만든 게 아닌 기존 warning은 건드리지 말 것.

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
