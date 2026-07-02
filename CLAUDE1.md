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
- 앱 실행/빌드 가능성을 최우선으로 할 것
- 불확실한 부분은 임의 삭제하지 말고 보고할 것
- 완료후 관리자가 APK 라고 적으면, 날자와 시간이 이름에 들어간 APK만들어 줘. 

이 내용을 항상 기억하고 지시문에 포함해 줘.
=================================
지시문 

# 지시문: Duo 초대 라우팅 — isGuestSession 게이트 제거 및 인증 후 pending invite 우선 라우팅

## 목적
현재 Duo 초대 딥링크 라우팅이 `isGuestSession == true`인 비회원(게스트)에게만 작동합니다.
구글/카카오/이메일로 가입한 **정식 회원**도 Duo 초대를 받을 수 있으므로,
`isGuestSession` 조건을 제거하고, 모든 인증 완료 경로에서 pending invite를 먼저 확인하도록 수정합니다.

## 대상 파일
- `lib/custom_code/widgets/intro_master.dart` (이 파일 1개만 수정)

## 수정 요약
| # | 위치 | 내용 |
|---|------|------|
| A | 신규 헬퍼 추가 | `_routeAfterAuth()` — pending duo invite면 StealthRoom, 아니면 Lobby |
| B | `_onDuoInviteSignal()` | `isGuestSession &&` 조건 제거 |
| C | `_checkEntryStatus()` 1순위 | `isGuestSession &&` 조건 제거 |
| D | `_checkEntryStatus()` 3순위 | `context.goNamed('Lobby')` → `_routeAfterAuth()` |
| E | `_handleAuth()` | `context.goNamed('Lobby')` → `_routeAfterAuth()` |
| F | `_handleSocialAuth()` | `context.goNamed('Lobby')` → `_routeAfterAuth()` |

---

## Phase 0 — Savepoint

```bash
cd F:\flutter_project\stealth_vox
git add -A && git commit -m "savepoint: before duo invite routing fix"
```

---

## Phase 1 — Grep 검증 (각 앵커 count=1 확인)

```bash
cd F:\flutter_project\stealth_vox

# 앵커 A: 헬퍼 삽입 위치 (initAppsFlyer 닫는 부분)
grep -n "appId: 'com.aienglishpractice.stealthvox'," lib/custom_code/widgets/intro_master.dart
# 예상: 1줄 (count=1)

# 앵커 B: _onDuoInviteSignal의 isGuestSession
grep -n "duoInviteSignal - routing to StealthRoom" lib/custom_code/widgets/intro_master.dart
# 예상: 1줄 (count=1)

# 앵커 C: _checkEntryStatus 1순위의 isGuestSession
grep -n "routing to StealthRoom for Duo invite" lib/custom_code/widgets/intro_master.dart
# 예상: 1줄 (count=1)

# 앵커 D: _checkEntryStatus 3순위
grep -n "이미 로그인된 회원이면 로비로 이동" lib/custom_code/widgets/intro_master.dart
# 예상: 1줄 (count=1)

# 앵커 E: _handleAuth 내 goNamed('Lobby')
grep -n "} on FirebaseAuthException catch (e) {" lib/custom_code/widgets/intro_master.dart
# 예상: 1줄 (count=1)

# 앵커 F: _handleSocialAuth 내 goNamed('Lobby')
grep -c "await authFn();" lib/custom_code/widgets/intro_master.dart
# 예상: 1 (count=1)
```

**count=1이 아닌 앵커가 있으면 즉시 중단하고 보고할 것.**

---

## Phase 2 — str_replace 편집 (⚠️ 반드시 아래→위 순서로 실행)

### Edit F (최하단) — `_handleSocialAuth()`: Lobby → 헬퍼

```
파일: lib/custom_code/widgets/intro_master.dart

old_str:
      await authFn();
      if (mounted) context.goNamed('Lobby');

new_str:
      await authFn();
      if (mounted) _routeAfterAuth();
```

### Edit E — `_handleAuth()`: Lobby → 헬퍼

```
파일: lib/custom_code/widgets/intro_master.dart

old_str:
      if (mounted) context.goNamed('Lobby');
    } on FirebaseAuthException catch (e) {

new_str:
      if (mounted) _routeAfterAuth();
    } on FirebaseAuthException catch (e) {
```

### Edit D — `_checkEntryStatus()` 3순위: Lobby → 헬퍼

```
파일: lib/custom_code/widgets/intro_master.dart

old_str:
    // 3순위: 이미 로그인된 회원이면 로비로 이동
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      context.goNamed('Lobby');
      return;
    }

new_str:
    // 3순위: 이미 로그인된 회원 → pending invite 우선 체크
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      _routeAfterAuth();
      return;
    }
```

### Edit C — `_checkEntryStatus()` 1순위: isGuestSession 제거

```
파일: lib/custom_code/widgets/intro_master.dart

old_str:
    if (FFAppState().isGuestSession &&
        FFAppState().pendingInviteType == 'duo' &&
        FFAppState().duoRoomId.isNotEmpty) {
      debugPrint('[Intro] routing to StealthRoom for Duo invite');

new_str:
    if (FFAppState().pendingInviteType == 'duo' &&
        FFAppState().duoRoomId.isNotEmpty) {
      debugPrint('[Intro] routing to StealthRoom for Duo invite');
```

### Edit B — `_onDuoInviteSignal()`: isGuestSession 제거

```
파일: lib/custom_code/widgets/intro_master.dart

old_str:
    if (FFAppState().isGuestSession &&
        FFAppState().pendingInviteType == 'duo' &&
        FFAppState().duoRoomId.isNotEmpty) {
      debugPrint('[Intro] duoInviteSignal - routing to StealthRoom');

new_str:
    if (FFAppState().pendingInviteType == 'duo' &&
        FFAppState().duoRoomId.isNotEmpty) {
      debugPrint('[Intro] duoInviteSignal - routing to StealthRoom');
```

### Edit A (최상단) — `_routeAfterAuth()` 헬퍼 추가

```
파일: lib/custom_code/widgets/intro_master.dart

old_str:
  Future<void> _initAppsFlyer() async {
    await AppsFlyerManager.initialize(
      devKey: 'SQUmDTB2VzuPjrJGiy5SSC',
      appId: 'com.aienglishpractice.stealthvox',
    );
  }

new_str:
  /// pending Duo 초대가 있으면 StealthRoom, 없으면 Lobby로 라우팅
  void _routeAfterAuth() {
    if (FFAppState().pendingInviteType == 'duo' &&
        FFAppState().duoRoomId.isNotEmpty) {
      debugPrint('[Intro] _routeAfterAuth → StealthRoom (pending duo invite)');
      context.pushReplacementNamed('StealthRoom');
    } else {
      context.goNamed('Lobby');
    }
  }

  Future<void> _initAppsFlyer() async {
    await AppsFlyerManager.initialize(
      devKey: 'SQUmDTB2VzuPjrJGiy5SSC',
      appId: 'com.aienglishpractice.stealthvox',
    );
  }
```

---

## Phase 3 — 사후 Grep 검증

```bash
# isGuestSession이 intro_master.dart에서 완전히 제거되었는지 확인
grep -c "isGuestSession" lib/custom_code/widgets/intro_master.dart
# 예상: 0

# _routeAfterAuth 호출 횟수 (헬퍼 정의 1 + 호출 3 = 총 4)
grep -c "_routeAfterAuth" lib/custom_code/widgets/intro_master.dart
# 예상: 4

# goNamed('Lobby')가 intro_master.dart에서 제거되었는지 확인
grep -c "goNamed('Lobby')" lib/custom_code/widgets/intro_master.dart
# 예상: 1 (헬퍼 내부의 1개만 남아야 함)
```

---

## Phase 4 — 빌드 검증

```bash
cd F:\flutter_project\stealth_vox
flutter analyze lib/custom_code/widgets/intro_master.dart
dart format lib/custom_code/widgets/intro_master.dart
```

⚠️ `dart format`은 반드시 이 **단일 파일**만 대상으로 실행 (폴더 대상 금지 — 한글 UTF-8 깨짐 위험)

---

## Phase 5 — 롤백

문제 발생 시:
```bash
git revert HEAD
```

---

## 참고: isGuestSession 자체를 삭제하는 건 아님

`isGuestSession`은 `intro_master.dart`의 라우팅 조건에서만 제거합니다.
이 플래그는 Duo 방 내부(`duo_routine.dart` 등)에서 게스트/호스트 구분, 과금 면제 등
다른 용도로 사용될 수 있으므로 FFAppState에서 필드 자체를 삭제하지 않습니다.