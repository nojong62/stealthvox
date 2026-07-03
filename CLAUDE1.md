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

# 지시문: 카카오 로그인 플로우 임시 디버그 로그 삽입 (원인 특정용)

## 배경
adb 로그 분석 결과, 카카오 SDK 네이티브 로그인(`TalkAuthCodeActivity`)은 정상 완료되지만
그 이후 단계(Cloud Function 콜러블 호출 → `signInWithCustomToken`)가 로그에 전혀 나타나지 않음.
`_handleSocialAuth`/`SocialAuthService.signInWithKakao`에 디버그 출력이 없어서 블랙박스 상태.

**목적**: 임시 `debugPrint`를 추가해 정확히 어느 단계에서 끊기는지 한 번의 재현으로 특정한다.
**이 변경은 진단 전용이며, 원인 확인 후 제거하거나 정식 로깅으로 정리한다.**

## 대상 파일
- `lib/auth/social_auth_service.dart`
- `lib/custom_code/widgets/intro_master.dart`

---

## Phase 0 — Savepoint

```bash
cd F:\flutter_project\stealth_vox
git add -A && git commit -m "savepoint: before kakao debug logging"
```

---

## Phase 1 — social_auth_service.dart 확인 및 디버그 로그 삽입

### 1-A: 파일 확인

```bash
cat lib/auth/social_auth_service.dart
```

`signInWithKakao` 함수의 정확한 구조를 파악한다 (아래는 예상 구조 — 실제와 다르면 구조에 맞춰 적용).

### 1-B: 삽입할 디버그 로그 (5개 지점)

`signInWithKakao` 함수 내부에서, 아래 5개 지점에 각각 `debugPrint`를 추가한다.
**정확한 삽입 위치는 실제 코드 구조에 맞춰 코덱스가 판단**하되, 다음 순서와 의미를 반드시 지킨다:

```dart
// ① 함수 진입 + 현재 인증 상태
debugPrint('[KakaoAuth] ① signInWithKakao 시작, currentUser=${FirebaseAuth.instance.currentUser?.uid}, isAnonymous=${FirebaseAuth.instance.currentUser?.isAnonymous}');

// ② 익명 로그인 필요 시 (currentUser == null인 분기 안)
debugPrint('[KakaoAuth] ② signInAnonymously 실행');
// ... 기존 signInAnonymously 호출 ...
debugPrint('[KakaoAuth] ② signInAnonymously 완료, uid=${FirebaseAuth.instance.currentUser?.uid}');

// ③ Kakao SDK 로그인 성공 직후 (accessToken 획득 직후)
debugPrint('[KakaoAuth] ③ Kakao SDK 로그인 성공, accessToken 길이=${token.accessToken.length}');
// (Kakao SDK 로그인 실패 시 catch 블록에도 추가)
debugPrint('[KakaoAuth] ③-실패 Kakao SDK 로그인 실패: $e');

// ④ Cloud Function callable 호출 직전/직후
debugPrint('[KakaoAuth] ④ kakaoCustomAuth callable 호출 시작');
// ... 기존 callable 호출 ...
debugPrint('[KakaoAuth] ④ kakaoCustomAuth 응답 수신, token 존재=${result.data['token'] != null}');

// ⑤ signInWithCustomToken 직전/직후
debugPrint('[KakaoAuth] ⑤ signInWithCustomToken 호출 시작');
await FirebaseAuth.instance.signInWithCustomToken(customToken);
debugPrint('[KakaoAuth] ⑤ signInWithCustomToken 완료, 최종 uid=${FirebaseAuth.instance.currentUser?.uid}');
```

**전체를 감싸는 try-catch가 있다면, catch 블록에도 반드시 추가:**

```dart
} catch (e, stack) {
  debugPrint('[KakaoAuth] ❌ 예외 발생: $e');
  debugPrint('[KakaoAuth] ❌ 스택: $stack');
  rethrow; // 또는 기존 동작 유지
}
```

⚠️ **주의**: 기존 로직의 흐름(return 값, await 순서, catch 처리)은 절대 변경하지 않는다.
오직 `debugPrint` 라인만 추가한다.

---

## Phase 2 — intro_master.dart의 _handleSocialAuth에도 추가

```bash
grep -n "_handleSocialAuth" lib/custom_code/widgets/intro_master.dart
```

기존 함수:
```dart
Future<void> _handleSocialAuth(Future<dynamic> Function() authFn) async {
    setState(() => isLoading = true);
    try {
      await authFn();
      if (mounted) _routeAfterAuth();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('로그인 실패: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => isLoading = false);
    }
  }
```

다음과 같이 디버그 로그를 추가 (str_replace):

```
old_str:
  Future<void> _handleSocialAuth(Future<dynamic> Function() authFn) async {
    setState(() => isLoading = true);
    try {
      await authFn();
      if (mounted) _routeAfterAuth();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('로그인 실패: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => isLoading = false);
    }
  }

new_str:
  Future<void> _handleSocialAuth(Future<dynamic> Function() authFn) async {
    debugPrint('[KakaoAuth] _handleSocialAuth 진입');
    setState(() => isLoading = true);
    try {
      await authFn();
      debugPrint('[KakaoAuth] authFn 완료, currentUser=${FirebaseAuth.instance.currentUser?.uid}, pendingInviteType=${FFAppState().pendingInviteType}');
      if (mounted) _routeAfterAuth();
      debugPrint('[KakaoAuth] _routeAfterAuth 호출 완료');
    } catch (e, stack) {
      debugPrint('[KakaoAuth] _handleSocialAuth 예외: $e');
      debugPrint('[KakaoAuth] 스택: $stack');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('로그인 실패: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => isLoading = false);
    }
  }
```

---

## Phase 3 — 빌드 검증

```bash
flutter analyze lib/auth/social_auth_service.dart lib/custom_code/widgets/intro_master.dart
dart format lib/auth/social_auth_service.dart
dart format lib/custom_code/widgets/intro_master.dart
```

⚠️ 각각 단일 파일로 format (폴더 대상 금지)

---

## Phase 4 — 커밋 (진단용 임시 커밋)

```bash
git add -A
git commit -m "debug: temporary kakao auth flow logging"
```

이 커밋은 원인 특정 후 되돌리거나(`git revert`) 정식 로깅으로 정리할 예정임을 실장에게 안내.

---

## Phase 5 — 재현 및 로그 캡처 (실장 수행)

1. `flutter run` (또는 이미 빌드된 최신 APK 재설치 후 `adb logcat` 필터링)
2. 로그아웃 상태에서 카카오 로그인 버튼 탭
3. 터미널/logcat에서 `[KakaoAuth]` 태그로 필터링:
   ```bash
   adb logcat | grep "KakaoAuth"
   ```
4. ①→⑤ 중 **어디까지 출력되고 어디서 멈추는지** 캡처

---

## Phase 6 — 결과 해석 가이드

| 마지막 출력 지점 | 의미 |
|---|---|
| ①에서 멈춤 | 함수 진입 자체가 안 됨 → 버튼 onTap 연결 문제 |
| ②에서 멈춤 | signInAnonymously 자체가 실패/멈춤 |
| ③ 성공, ③-실패 없음, 그 다음 없음 | Kakao 토큰은 받았는데 콜러블 호출 코드에 도달 못 함 (코드 흐름 문제) |
| ④ "호출 시작"만 있고 "응답 수신" 없음 | **Cloud Function 호출이 걸린 채 응답을 못 받음** — 네트워크, App Check, 타임아웃, 또는 리전 설정 불일치 의심 |
| ④ 완료, ⑤ "호출 시작"만 있고 "완료" 없음 | `signInWithCustomToken` 자체에서 예외 (토큰 형식, 만료 등) |
| ⑤까지 전부 출력됨 | 로그인은 성공 — 문제는 그 이후 라우팅/캐시 쪽 (별도 조사 필요) |
| ❌ 예외 로그 출력됨 | 그 예외 메시지와 스택을 그대로 실장에게 전달 |

---

## Phase 7 — 정리 (원인 특정 후)

원인이 특정되면 이 디버그 로그들은:
- 제거하거나
- 실장 승인 하에 정식 `functions.logger` 스타일 로깅으로 전환

```bash
git log --oneline -5   # 진단용 커밋 해시 확인
git revert <해당 커밋 해시>   # 필요 시 되돌리기
```