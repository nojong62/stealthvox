StealthVox 프로젝트 가이드 (FlutterFlow)

 📂 파일 위치 및 위젯 리스트
 모든 화면(Pages): `lib/` 폴더 내 각 이름별 폴더
 커스텀 액션: `lib/custom_code/actions/`
 전역 상태: `lib/app_state.dart`

 🛠️ 커스텀 위젯 (`lib/custom_code/widgets/`)
현재 구현된 위젯 파일들 (새 작업 시 참고):
"임시/ 폴더에는 적용하지 말 것"

 ⚙️ AI 작업 규칙

- 새 기능 추가 시 반드시 주제별 주석 블록으로 구분할 것.
- 기존 블록 내부에 의미 없이 이어붙이지 말 것.
- 기능이 커지면 private helper method로 분리할 것.
- build() 내부 코드를 계속 비대하게 만들지 말 것.
- 상태 변수도 기능별 블록으로 정리할 것.
- dispose(), timer, stream 정리 코드는 lifecycle 블록으로 모을 것.

1. 복사붙여넣기: FlutterFlow 웹 에디터에 바로 적용할 수 있게 `import`와 클래스 구조 전체를 제공한다.
2. 디자인: `lib/flutter_flow/flutter_flow_theme.dart`의 테마 변수를 최우선으로 사용한다.
3. 작업 시작 전에 반드시 다음 순서로 진행해 주세요.
0. 네가 이해한 지시문 내용을 요약해서 맞는지 동의를 받는다.
1. git status 확인
2. 현재 브랜치 확인
3. 새 작업 브랜치 생성
4. 현재 상태를 백업 커밋
5. 관련 파일 전체 분석
6. 수정 대상 파일과 수정 계획 먼저 요약
7. 코드 수정
8. flutter pub get 실행
9. flutter analyze 실행
10. 오류 발생 시 원인 분석 후 수정 반복
11. 최종적으로 git diff 확인
12. 수정된 파일 목록, 핵심 변경사항, 남은 이슈 보고
13. main 브랜치에 머지해 줘.
14. 원격 저장소에 push 해줘

주의사항:
- 기존 정상 작동 기능을 깨지 말 것
- FlutterFlow generated code 구조를 함부로 대규모 변경하지 말 것
- 앱 실행/빌드 가능성을 최우선으로 하되, 빌드할지는 먼저 물어 봐.
- 불확실한 부분은 임의 삭제하지 말고 보고할 것

이 내용을 항상 기억하고 지시문에 포함해 줘.
=================================
지시문 

# P0 — 계정 자동 병합 안전 차단 지시문

## 목적 (범위를 벗어나지 말 것)
로그아웃 → 다른 계정 로그인 시 **어떠한 자동 UID 전환/계정 병합도 발생하지 않게** 만드는 것이 유일한 목표다.
계정 연결 기능을 다시 잘 만드는 것은 이번 작업 범위가 **아니다** (P1로 별도 분리).

### 금지 사항 (반드시 준수)
- 범위 밖 리팩터링 금지
- 파일 전체/폴더 단위 포맷 변경 금지 (dart format은 항상 개별 파일 단위로만 실행 — 한글 깨짐 위험)
- 인증 구조 전면 개편 금지
- 아래 P1 항목은 이번 지시문에서 절대 구현하지 않는다:
  - 명시적 계정 연결 UI 복원 (`_showAccountLinkDialog` 등)
  - 재인증 로직
  - 이메일 소유권 검증(인증 메일 발송 등)
  - Google/Kakao 토큰 소유권 검증
  - 티켓 트랜잭션/멱등성(operationId) 설계
  - canonical UID 통합 정책
- **파일/함수명이 이 문서에 적힌 이름과 다르면 추측으로 진행하지 말고, Phase 0 결과를 먼저 보고한 뒤 다음 단계로 넘어갈 것.**

---

## Phase S — Savepoint
1. 현재 브랜치(`fix/cross-provider-linking-v2`)의 커밋되지 않은 변경사항 상태를 `git status`로 확인하고 보고
2. 안전 커밋 생성: `git add -A && git commit -m "savepoint: before P0 auto-merge block"`
3. 이 커밋 해시를 기록해 둘 것 (Phase 5 롤백용)
4. 작업은 새 브랜치에서 진행 (예: `fix/p0-block-auto-account-merge`)

---

## Phase 0 — 진단 (수정 금지, 확인만)
아래 항목을 grep/코드 열람으로 확인하고, **파일 경로 : 라인번호 : 실제 함수/변수명**을 표로 정리해서 보고할 것.

| # | 확인 대상 | 예상 위치 |
|---|---|---|
| 1 | `createProviderLinkTicket()` 호출부 | `lobby_master.dart` 로그아웃 핸들러 내부 |
| 2 | `consumeProviderLinkTicket` 함수 정의 | `firebase/functions/index.js` |
| 3 | `_consumePendingProviderLink` 정의 및 호출 횟수 | 인증 관련 파일 |
| 4 | `_consumePendingEmailLink` 정의 및 호출 횟수 | 인증 관련 파일 |
| 5 | 로컬 티켓 저장에 쓰이는 SharedPreferences 키 이름 (실제 문자열) | 로그아웃/로그인 관련 파일 |
| 6 | `updateUser(` 호출 중 email/password를 받는 지점 | `consumeProviderLinkTicket` 내부 |
| 7 | 티켓 Firestore 컬렉션 실제 이름 (`provider_link_tickets` 등) | Firestore |
| 8 | `_showAccountLinkDialog` 관련 코드가 완전 삭제됐는지, 죽은 코드로 남았는지 | lobby/auth 관련 파일 |
| 9 | 이 로직이 이미 배포/머지된 적 있는지 (`git log`) | 브랜치 히스토리 |

Phase 0 보고 없이 Phase 1로 넘어가지 말 것.

---

## Phase 1 — 최소 수정 (P0 범위만)

**1) 로그아웃 시 자동 티켓 생성 제거**
- 로그아웃 핸들러에서 `createProviderLinkTicket()` 호출 제거
- 관련 SharedPreferences 저장 로직 제거
- 로그아웃은 세션 종료(로컬 상태 clear + Firebase signOut)만 수행하도록 축소

**2) 모든 일반 로그인 경로에서 자동 소비 제거**
- `_consumePendingProviderLink` 호출부 제거 (함수 정의 자체는 롤백 용이성을 위해 일단 남겨두고 호출만 끊음 — 완전 삭제 여부는 Phase 4에서 판단)
- `_consumePendingEmailLink` 호출부 동일하게 제거
- Google/Kakao/이메일 **정상 로그인 함수 자체는 손대지 않음** (예: `signInWithGoogle`, `kakaoCustomAuth`)

**3) 이메일 미검증 계정 연결 서버 분기 차단**
- `consumeProviderLinkTicket`의 email 분기에서 `updateUser(email, password)` 직접 호출을 제거하고, 대신 명시적 오류(`functions.https.HttpsError('failed-precondition', ...)`)를 반환하도록 수정
- 비밀번호 값이 다음 위치에 로그로 남는지 확인 후 있으면 제거:
  - Cloud Functions 로그 (console.log 등)
  - 예외 메시지
  - Crashlytics/Analytics

**4) 잔존 티켓 정리**
- 로컬: 앱 진입 시 기존에 저장돼 있던 pending ticket류 SharedPreferences 키를 1회성으로 정리하는 로직 추가 (제거 목적이므로 P0 범위 포함)
- 서버: 기존 `provider_link_tickets` 문서는 **삭제하지 말고 그대로 보존** (Phase 6 오염 진단에 필요). 소비 경로 자체가 끊기므로 방치해도 안전함.

---

## Phase 2 — 정적 검증
- 수정한 파일 각각에 대해 `dart format` **개별 실행** (폴더 단위 절대 금지)
- `flutter analyze` 실행 — 신규 warning/error 없는지 확인
- firebase functions eslint(있다면) 실행

---

## Phase 3 — 테스트 (수동 시나리오)
1. 계정 A 로그인 → 정상 로그아웃 → 10분 이내 계정 B로 로그인 → **B의 UID/데이터로 진입하는지** 확인 (Google/Kakao/이메일 조합 각각 반복)
2. 로그아웃 후 앱 재시작 → 재로그인 → 동일 결과 확인
3. 신규 이메일 회원가입이 예전 티켓 잔존 여부와 무관하게 정상 성공하는지 확인
4. 기존 온보딩/체험(trial) 흐름에 회귀가 없는지 확인

---

## Phase 4 — Diff 검토
- 전체 diff를 사람이 읽을 수 있게 요약
- 각 변경이 "자동 병합 차단"이라는 P0 목표와 직접 관련 있는지 확인, 범위 밖 수정 섞였는지 점검
- 삭제 vs 주석처리 여부 명확히 구분해서 보고

---

## Phase 5 — 결과 보고
- 변경 파일 목록 + 각 파일 grep 검증 카운트 (before/after)
- 커밋 해시
- Phase 3 테스트 결과 (통과/실패)
- Phase 0에서 실제 이름이 이 문서 예상과 달랐던 부분이 있었다면 명시
- 롤백 커맨드: `git reset --hard <Phase S 커밋 해시>`

---

## Phase 6 — 기존 오염 여부 진단 (읽기 전용, 수정 금지)
> 이번 자동 병합 로직이 테스트 중 실제로 실행된 적이 있는지 확인하는 별도 진단. **자동 복구 절대 금지, 보고만.**

- `provider_link_tickets`(실제 이름) 중 `consumed: true` 문서 개수와 목록 (uid, timestamp)
- Firebase Auth `providerData` vs Firestore `users` 문서의 provider 정보 불일치 사례
- `kakao_uid_map` / `provider_uid_map`에서 동일 provider UID가 예상 밖 canonical UID로 매핑된 경우
- RevenueCat `app_user_id`가 실제 Firebase UID와 다르게 기록된 사례 (확인 가능한 범위에서)

---

## P0 성공 기준 (요약)
- 로그아웃 후 어떤 계정으로 재로그인해도 **그 계정 자체로만** 진입한다
- provider mapping, 채팅 기록, remainingTime(잔여 시간), RevenueCat 사용자 식별자 중 무엇도 다른 계정으로 바뀌지 않는다
- 네트워크 재시도·앱 재시작 상황에서도 동일하게 유지된다