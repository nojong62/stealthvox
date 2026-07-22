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

================
지시문

1. **Google Play Console:** 실제 판매가격 변경
2. **앱 코드:** 현재 화면 가격이 하드코딩돼 있을 때 수정

RevenueCat Dashboard에는 보통 가격을 직접 입력하지 않습니다. RevenueCat의 Offering은 상품 연결을 관리하고, 앱은 스토어에서 전달받은 지역별 가격을 표시할 수 있습니다. 따라서 앱이 RevenueCat의 상품 가격을 동적으로 표시한다면 앱 코드도 수정하지 않고 Google Play Console만 바꾸면 될 가능성이 있습니다. ([RevenueCat][1])

## RevenueCat Webhook은 보통 어떻게 되나

RevenueCat의 일반적인 구매 Webhook에는 거래 관련 `product_id`, 가격 및 통화 정보가 포함될 수 있습니다. 따라서 Webhook 수신 코드가 전달된 값을 그대로 저장한다면 **가격 변경 작업은 필요 없습니다.** ([RevenueCat][2])

수정해야 하는 경우는 Webhook 처리 코드 안에 다음과 같은 고정 가격표가 있을 때입니다.

* 10분 상품 ID → 300원
* 1시간 상품 ID → 1,700원
* 5시간 상품 ID → 8,000원
* 10시간 상품 ID → 15,000원

즉, **Webhook 자체의 RevenueCat 설정에서 가격을 적는 경우는 일반적이지 않지만, 실장님 Firebase Function이 가격을 하드코딩했는지는 확인해야 합니다.**

또 하나 주의할 점은 RevenueCat의 가격 필드가 실제 소비자가 결제한 금액, 추정 매출, 세금·수수료 반영 금액 중 어떤 의미인지 설정과 필드에 따라 다를 수 있다는 것입니다. 시간 충전 판단은 금액이 아니라 **Product ID**로 처리하고, 가격은 매출 기록용으로만 사용하는 편이 안전합니다. RevenueCat은 세금과 스토어 수수료를 반영한 매출 보고 옵션도 제공합니다. ([RevenueCat][3])

---

# Codex 지시문

## StealthVox 시간권 가격 변경 사전 점검 및 수정

### 1. 작업 목적

StealthVox의 네 가지 Google Play 일회성 시간권 가격을 다음과 같이 변경한다.

| 상품    |   기존 가격 |       신규 가격 |
| ----- | ------: | ----------: |
| 10분권  |    300원 |    **400원** |
| 1시간권  |  1,700원 |  **2,000원** |
| 5시간권  |  8,000원 |  **9,000원** |
| 10시간권 | 15,000원 | **17,000원** |

기존 Google Play Product ID, RevenueCat Product, Package, Offering 및 시간 충전량은 변경하지 않는다.

---

## 2. 핵심 원칙

* 가격만 변경한다.
* Product ID는 변경하지 않는다.
* RevenueCat Offering과 Package 연결은 유지한다.
* 각 상품의 충전 시간은 변경하지 않는다.
* 구매 검증 및 시간 충전은 결제 금액이 아니라 Product ID를 기준으로 유지한다.
* 조사 없이 가격 숫자를 일괄 치환하지 않는다.
* 기존 가격과 우연히 같은 일반 숫자를 잘못 수정하지 않는다.
* 수정 전 savepoint를 생성한다.
* main 병합과 원격 push는 별도 승인 전 수행하지 않는다.

---

## 3. Phase 1 — 현재 가격 구조 조사

코드를 수정하기 전에 다음 내용을 조사해 보고한다.

### A. 스토어 화면 가격 표시 방식

현재 Store 화면에 표시되는 다음 가격이 어디에서 오는지 확인한다.

* ₩300
* ₩1,700
* ₩8,000
* ₩15,000

각 가격이 다음 중 어디에 해당하는지 구분한다.

1. Dart 코드 하드코딩
2. FlutterFlow 위젯 속성 하드코딩
3. 앱 상수 또는 App State
4. Firestore
5. Firebase Remote Config
6. 로컬 JSON
7. 다국어 문자열
8. RevenueCat Package 또는 StoreProduct에서 동적 조회
9. Google Play Billing 정보에서 동적 조회
10. 기타

RevenueCat 가격을 동적으로 표시한다면 실제 사용 필드도 확인한다.

예:

* `priceString`
* `formattedPrice`
* `price`
* `currencyCode`
* `storeProduct`
* `package.storeProduct`
* 이에 준하는 Flutter SDK 필드

### B. 전체 가격 참조 검색

프로젝트 전체에서 다음 값을 검색한다.

* `300`
* `1,700`
* `1700`
* `8,000`
* `8000`
* `15,000`
* `15000`
* `₩300`
* `₩1,700`
* `₩8,000`
* `₩15,000`
* `KRW`
* 상품 Product ID
* RevenueCat Package identifier

단순 숫자 검색 결과는 반드시 문맥을 확인한다. 가격과 무관한 타이머, 크기, 시간, 색상, 제한값 등은 수정하지 않는다.

### C. 확인 대상 화면과 기능

다음 위치에 기존 가격이 표시되거나 저장되는지 확인한다.

* Store 상품 카드
* 구매 버튼
* 구매 확인 팝업
* Google 결제 시작 전 안내문
* 구매 완료 팝업 또는 SnackBar
* 영수증 화면
* Usage/Receipt 화면
* Billing Log
* 구매 내역
* 관리자용 매출 화면
* FAQ 및 이용 안내
* 테스트 안내문
* 다국어 문자열
* 앱 내부 홍보 이미지 또는 설명
* Google Play 상품 설명과 상품명

---

## 4. Phase 2 — RevenueCat 구조 확인

RevenueCat 관련 코드와 설정 참조를 확인한다.

### 확인 사항

1. 현재 Offering identifier
2. 네 상품의 Package identifier
3. Google Play Product ID
4. 각 Package와 Product의 연결 관계
5. 상품 유형이 일회성 소모성 상품인지
6. 동일 상품 재구매가 가능한 구조인지
7. 앱에서 Offering을 불러오는 위치
8. Offering 캐시 또는 새로고침 방식
9. 가격 문자열을 RevenueCat에서 동적으로 받는지
10. RevenueCat Dashboard에 별도의 가격 메타데이터를 저장해 사용하는지

### 변경 원칙

기존 Product ID가 유지된다면 다음 항목은 변경하지 않는다.

* RevenueCat Product 생성
* Package 재생성
* Offering 교체
* Entitlement 변경
* API Key 변경
* Webhook URL 변경

RevenueCat Dashboard에서 가격을 직접 입력하는 별도 설정이 없다면 Dashboard 변경은 하지 않는다.

---

## 5. Phase 3 — RevenueCat Webhook 및 Firebase Functions 점검

RevenueCat Webhook 수신 코드를 찾아 다음을 확인한다.

### 확인할 내용

1. Webhook 이벤트에서 실제 가격과 통화를 읽는지
2. `product_id`를 기준으로 충전 시간을 결정하는지
3. 상품별 가격을 코드에 고정 매핑했는지
4. Firestore 영수증에 가격을 어떤 값으로 저장하는지
5. 세금·수수료 전후 가격 중 어떤 값을 저장하는지
6. 원화 외 지역 결제도 처리 가능한지
7. Webhook 재전송 또는 중복 이벤트 방지 방식
8. Product ID별 충전 시간 매핑은 기존대로 유지되는지

### 수정 기준

다음 구조라면 수정하지 않는다.

* RevenueCat 이벤트가 제공한 가격과 통화를 그대로 저장
* Product ID로 10분·1시간·5시간·10시간을 판정
* 가격과 무관하게 충전 시간을 부여

다음 구조라면 신규 가격으로 수정한다.

* 상품 ID별 가격이 고정값으로 저장됨
* 300, 1700, 8000, 15000원을 직접 매핑함
* 실제 Webhook 가격을 무시하고 자체 가격표를 기록함

신규 고정값이 반드시 필요한 경우:

* 10분권: 400원
* 1시간권: 2,000원
* 5시간권: 9,000원
* 10시간권: 17,000원

단, 충전 시간 판정 로직을 가격 기준으로 변경하지 않는다.

---

## 6. Phase 4 — 앱 코드 수정

### 앱 가격이 하드코딩인 경우

화면 표시 가격을 다음과 같이 변경한다.

* `₩300` → `₩400`
* `₩1,700` → `₩2,000`
* `₩8,000` → `₩9,000`
* `₩15,000` → `₩17,000`

다음 위치에 같은 가격이 존재한다면 일관되게 수정한다.

* Store 카드
* 결제 확인 문구
* 영수증 표시
* 구매 완료 안내
* Billing Log의 표시용 가격
* 다국어 문자열
* 테스트용 가격 목록
* Firestore 또는 Remote Config 기본값

### 앱 가격이 RevenueCat에서 동적 조회되는 경우

가격 하드코딩을 새 가격으로 바꾸지 않는다.

대신 다음을 확인한다.

* Store 카드가 RevenueCat의 지역화된 가격을 사용함
* 로딩 전 임시값이 옛 가격으로 표시되지 않음
* RevenueCat 조회 실패 시 옛 가격을 fallback으로 표시하지 않음
* 대한민국에서는 원화와 천 단위 구분이 정상 표시됨
* Google 결제창 가격과 앱 화면 가격이 일치함

가격이 동적이라면 가능한 한 해당 구조를 유지한다.

---

## 7. Phase 5 — Google Play Console 수동 변경 안내

코드 작업과 별도로 사람이 Google Play Console에서 수행해야 할 작업을 정확히 정리해 보고한다.

경로:

> Google Play Console
> → StealthVox
> → 수익 창출
> → 제품
> → 일회성 제품
> → 각 상품의 구매 옵션

대한민국 가격:

* 10분권: ₩400
* 1시간권: ₩2,000
* 5시간권: ₩9,000
* 10시간권: ₩17,000

각 상품에서 다음을 확인한다.

* 신규 가격 저장
* 구매 옵션 활성 상태
* 변경사항 활성화 또는 게시
* 판매 대상 국가
* 자동 환산된 해외 가격
* 수동 지정된 지역 가격
* 연결된 할인 또는 Offer
* 상품 상태가 활성인지
* Product ID가 기존과 동일한지

Google Play Console은 Codex가 직접 변경하지 않는다. 필요한 조작 순서만 보고한다.

---

## 8. 분석 및 매출 이벤트 점검

다음 서비스가 실제 결제 가격을 동적으로 사용하는지 확인한다.

* Firebase Analytics
* AppsFlyer
* RevenueCat integration
* Firestore receipt 기록
* 관리자 매출 집계
* 기타 구매 이벤트

확인 필드 예:

* `value`
* `currency`
* `price`
* `revenue`
* `af_revenue`
* `af_currency`
* `product_id`

실제 결제 응답이나 RevenueCat 이벤트의 가격을 사용한다면 수정하지 않는다.

옛 가격이 고정 입력돼 있다면 신규 가격으로 수정한다.

---

## 9. 검증

### 정적 검증

* 변경 파일에 대해 `flutter analyze`
* Firebase Functions가 변경됐다면 해당 lint 또는 테스트 수행
* 기존 가격 문자열이 가격 관련 코드에 남았는지 재검색
* Product ID 및 시간 충전량이 변경되지 않았는지 diff 확인

### 실기기 또는 내부 테스트 검증

가격이 Google Play에 반영된 후 다음을 확인한다.

1. 앱 완전 종료 후 재실행
2. Store 화면 신규 가격 확인
3. Google 결제창 신규 가격 확인
4. 앱 화면과 결제창 가격 일치
5. 10분권 구매 시 10분 충전
6. 1시간권 구매 시 1시간 충전
7. 5시간권 구매 시 5시간 충전
8. 10시간권 구매 시 10시간 충전
9. 동일 소모성 상품 재구매 가능
10. RevenueCat Customer History에 거래 기록
11. RevenueCat Webhook 정상 수신
12. Firestore Receipt 및 Usage Log 정상 기록
13. Firebase Analytics와 AppsFlyer 가격·통화 확인
14. 기존 Entitlement 및 시간 차감 로직 정상

네 상품을 실제로 모두 결제하기 어렵다면 테스트 구매 또는 라이선스 테스터 환경에서 가능한 범위를 명확히 보고한다.

---

## 10. 최종 보고 형식

작업 완료 후 다음을 보고한다.

### 조사 결과

* 앱 가격이 하드코딩인지 동적 가격인지
* 가격의 실제 원본이 어디인지
* RevenueCat Dashboard 수정 필요 여부
* Webhook 코드에 고정 가격이 있는지
* Firebase 또는 AppsFlyer에 고정 가격이 있는지

### 변경 내용

* 변경 파일
* 함수 또는 위젯 위치
* 기존 값
* 신규 값
* 변경 이유

### 변경하지 않은 항목

* Product ID
* RevenueCat Product
* Package
* Offering
* Entitlement
* 충전 시간
* Webhook URL

### 검증 결과

* analyze 결과
* 검색 결과
* Google Play 반영 확인 여부
* 앱 표시 가격
* 결제창 가격
* 충전 시간
* Webhook 및 영수증 기록

### Git 상태

* savepoint 커밋
* 작업 커밋
* 현재 브랜치
* 작업트리 상태
* main 병합 및 push 여부

main 병합과 원격 push는 승인 전 수행하지 않는다.

---

## 실제로 수정될 가능성이 높은 범위

현재 캡처를 보면 가격 표시가 정적인 텍스트일 가능성도 있지만, 화면만으로는 확정할 수 없습니다.

* **하드코딩 가격이면:** 앱 코드 + Google Play Console
* **RevenueCat 동적 가격이면:** Google Play Console만
* **Webhook에 고정 가격표가 있으면:** 앱 코드 + Google Play Console + Firebase Function
* **Remote Config나 Firestore 가격표가 있으면:** 해당 데이터도 변경

따라서 Codex에는 먼저 **“수정 전에 가격의 원본을 조사하라”**고 시키는 것이 안전합니다. RevenueCat Webhook은 일반적으로 가격을 별도로 설정하는 곳은 아니므로, 대시보드를 수정하기보다 **수신 코드 안에 옛 가격이 박혀 있는지만 확인**하면 됩니다.

