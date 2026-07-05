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

이 내용을 항상 기억하고 지시문에 포함해 줘.
=================================
지시문 

# 지시문: 체험 완료 후 로그인 유도 하단 시트 (BottomSheet) 팝업

## 목표
TrialStudyPage(2분 공부방) 완료 시점에 `showModalBottomSheet`로 로그인 유도 팝업을 띄운다.
첫 줄: **"방금 전에 만든 공부방 내용부터 이어서 연습하기 원하시면"**
뒤로가기 차단 + 드래그 닫기 차단 (반드시 로그인 버튼으로만 진행).

---

## Phase 0: Git Savepoint + 진단

```powershell
cd F:\flutter_project\stealth_vox
git add -A && git commit -m "savepoint: before trial signup bottom sheet"
```

### 0-1. trial_study_page.dart 완료 콜백 앵커 탐색

```powershell
# 공부방 완료 후 네비게이션 또는 콜백 지점 찾기
Select-String -Path "lib\custom_code\widgets\trial\trial_study_page.dart" -Pattern "Navigator|goNamed|pushNamed|pushReplacement|pop|onComplete|_onFinish|_handleComplete|Store|Lobby|reset|advanceTo" | ForEach-Object { "$($_.LineNumber): $($_.Line.Trim())" }
```

> **⚠️ 중단점:** 위 결과를 확인하고, 공부방 타이머 종료 또는 완료 버튼 콜백 위치를 식별한다.
> 해당 지점이 Phase 2 편집의 타겟이 된다.
> 만약 결과가 여러 개면, `TrialFlowState.instance.reset()` 또는 `context.pushReplacementNamed('Store')` 등 **체험 종료 직후 네비게이션 라인**을 앵커로 선택한다.

### 0-2. 기존 로그인/회원가입 위젯 확인

```powershell
# 앱에 이미 있는 로그인 버튼 패턴 확인 (Kakao, Google)
Select-String -Path "lib\custom_code\widgets\trial\trial_study_page.dart" -Pattern "signIn|SignIn|kakao|google|Auth|login|Login|signup|SignUp" | ForEach-Object { "$($_.LineNumber): $($_.Line.Trim())" }
```

```powershell
# 기존 회원가입 페이지 파일 존재 여부
Get-ChildItem -Path "lib" -Recurse -Filter "*sign*" -Name
Get-ChildItem -Path "lib" -Recurse -Filter "*login*" -Name
Get-ChildItem -Path "lib" -Recurse -Filter "*auth*" -Name
```

> **기록:** 위 결과에서 기존 로그인 함수명(예: `signInWithGoogle()`, `kakaoLogin()` 등)을 메모한다.
> Phase 1에서 새 파일이 이 함수들을 import/호출해야 한다.

---

## Phase 1: 새 파일 생성 — `trial_signup_sheet.dart`

**경로:** `lib/custom_code/widgets/trial/trial_signup_sheet.dart`

```powershell
# 파일 미존재 확인
Test-Path "lib\custom_code\widgets\trial\trial_signup_sheet.dart"
# 결과: False 여야 함
```

아래 내용으로 **새 파일 생성**:

> **⚠️ 주의:** Phase 0-2에서 확인한 실제 로그인 함수명/import 경로로 `【로그인함수】` 부분을 치환할 것.
> 예: `signInWithGoogle()` → 실제 프로젝트 내 Google 로그인 함수
> 예: `kakaoLogin()` → 실제 프로젝트 내 Kakao 로그인 함수

```dart
// trial_signup_sheet.dart
// 체험 완료 후 로그인 유도 하단 시트
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';

/// 체험 완료 후 하단에서 올라오는 로그인 유도 시트.
/// [isDismissible: false] + [enableDrag: false] → 뒤로가기/드래그 닫기 차단.
/// 로그인 성공 시 [onLoginSuccess] 콜백 호출.
class TrialSignupSheet extends StatelessWidget {
  final VoidCallback onLoginSuccess;
  final VoidCallback? onSkip; // 나중에 하기 (선택적)

  const TrialSignupSheet({
    super.key,
    required this.onLoginSuccess,
    this.onSkip,
  });

  /// 외부에서 호출하는 편의 메서드
  static Future<void> show(
    BuildContext context, {
    required VoidCallback onLoginSuccess,
    VoidCallback? onSkip,
  }) {
    return showModalBottomSheet(
      context: context,
      isDismissible: false,
      enableDrag: false,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => TrialSignupSheet(
        onLoginSuccess: onLoginSuccess,
        onSkip: onSkip,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bottomPad = MediaQuery.of(context).viewPadding.bottom;
    return PopScope(
      canPop: false, // 뒤로가기 하드웨어 버튼 차단
      child: Container(
        padding: EdgeInsets.fromLTRB(24, 32, 24, bottomPad + 24),
        decoration: const BoxDecoration(
          color: Color(0xFF1E1E22),
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // ── 드래그 핸들 (시각적 힌트, 실제 드래그는 차단) ──
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.white24,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 24),

            // ── 메인 카피 ──
            const Text(
              '방금 전에 만든 공부방 내용부터\n이어서 연습하기 원하시면',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.w700,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 12),
            const Text(
              '무료 회원가입 후 바로 시작할 수 있어요',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Color(0xFF9E9E9E),
                fontSize: 14,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 28),

            // ── 카카오 로그인 버튼 ──
            _buildLoginButton(
              context: context,
              label: '카카오로 시작하기',
              bgColor: const Color(0xFFFEE500),
              textColor: const Color(0xFF3C1E1E),
              iconPath: 'assets/images/kakao_icon.png', // 【확인필요】 실제 에셋 경로
              onTap: () => _handleKakaoLogin(context),
            ),
            const SizedBox(height: 12),

            // ── Google 로그인 버튼 ──
            _buildLoginButton(
              context: context,
              label: 'Google로 시작하기',
              bgColor: Colors.white,
              textColor: Colors.black87,
              iconPath: 'assets/images/google_icon.png', // 【확인필요】 실제 에셋 경로
              onTap: () => _handleGoogleLogin(context),
            ),
            const SizedBox(height: 20),

            // ── 나중에 하기 (선택적) ──
            if (onSkip != null)
              GestureDetector(
                onTap: onSkip,
                child: const Text(
                  '나중에 할게요',
                  style: TextStyle(
                    color: Color(0xFF666666),
                    fontSize: 13,
                    decoration: TextDecoration.underline,
                    decorationColor: Color(0xFF666666),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildLoginButton({
    required BuildContext context,
    required String label,
    required Color bgColor,
    required Color textColor,
    required String iconPath,
    required VoidCallback onTap,
  }) {
    return SizedBox(
      width: double.infinity,
      height: 52,
      child: ElevatedButton(
        onPressed: onTap,
        style: ElevatedButton.styleFrom(
          backgroundColor: bgColor,
          foregroundColor: textColor,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Image.asset(iconPath, width: 22, height: 22,
                errorBuilder: (_, __, ___) => const SizedBox(width: 22)),
            const SizedBox(width: 10),
            Text(label,
                style: TextStyle(
                  color: textColor,
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                )),
          ],
        ),
      ),
    );
  }

  // 【치환필요】 Phase 0-2에서 확인한 실제 로그인 함수로 교체
  Future<void> _handleKakaoLogin(BuildContext context) async {
    try {
      // await 【실제_카카오_로그인_함수】();
      // 예: await kakaoLogin();
      final user = FirebaseAuth.instance.currentUser;
      if (user != null && !user.isAnonymous) {
        Navigator.pop(context); // 바텀시트 닫기
        onLoginSuccess();
      }
    } catch (e) {
      debugPrint('[TrialSignupSheet] Kakao login error: $e');
    }
  }

  Future<void> _handleGoogleLogin(BuildContext context) async {
    try {
      // await 【실제_구글_로그인_함수】();
      // 예: await signInWithGoogle();
      final user = FirebaseAuth.instance.currentUser;
      if (user != null && !user.isAnonymous) {
        Navigator.pop(context); // 바텀시트 닫기
        onLoginSuccess();
      }
    } catch (e) {
      debugPrint('[TrialSignupSheet] Google login error: $e');
    }
  }
}
```

생성 후 확인:

```powershell
Test-Path "lib\custom_code\widgets\trial\trial_signup_sheet.dart"
# 결과: True
```

---

## Phase 2: `trial_study_page.dart` 편집 — 완료 지점에 바텀시트 호출 삽입

### 2-1. import 추가

파일 상단 import 블록 끝에 추가:

```
import 'trial_signup_sheet.dart';
```

**grep 검증:**

```powershell
Select-String -Path "lib\custom_code\widgets\trial\trial_study_page.dart" -Pattern "trial_signup_sheet"
# 예상: 1건 (방금 추가한 import)
```

### 2-2. 완료 콜백에 바텀시트 호출 삽입

> **⚠️ Phase 0-1 결과 참조 필수**
> 아래는 **예시 앵커**입니다. Phase 0-1에서 식별한 실제 완료 지점의 코드를 old_str로 사용하세요.

**패턴 A — 기존에 `context.pushReplacementNamed('Store')` 또는 유사 네비게이션이 있는 경우:**

```
old_str: 기존_네비게이션_코드_라인 (Phase 0-1에서 확인한 그대로)

new_str:
    // 🆕 체험 완료 → 로그인 유도 바텀시트
    if (TrialFlowState.instance.isTrial || TrialFlowState.instance.trialStep >= 3) {
      if (!mounted) return;
      await TrialSignupSheet.show(
        context,
        onLoginSuccess: () {
          TrialFlowState.instance.reset();
          if (mounted) context.pushReplacementNamed('Lobby');
        },
        onSkip: () {
          Navigator.pop(context); // 바텀시트 닫기
          TrialFlowState.instance.reset();
          if (mounted) context.pushReplacementNamed('Store');
        },
      );
      return;
    }
    기존_네비게이션_코드_라인 (비체험 유저용 기존 로직 유지)
```

**패턴 B — 타이머 종료 콜백에서 직접 처리하는 경우:**

> 공부방 타이머가 끝나는 함수(예: `_onTimerEnd`, `_handleFinish` 등) 내부의
> 마지막 네비게이션 라인을 위 `TrialSignupSheet.show(...)` 호출로 교체.

### 2-3. 편집 후 grep 검증

```powershell
Select-String -Path "lib\custom_code\widgets\trial\trial_study_page.dart" -Pattern "TrialSignupSheet"
# 예상: 2건 (import 1 + show 호출 1)

# 기존 네비게이션이 비체험 분기로 남아있는지 확인
Select-String -Path "lib\custom_code\widgets\trial\trial_study_page.dart" -Pattern "pushReplacementNamed|goNamed"
# 예상: 1건 이상 (비체험 유저용 기존 로직)
```

---

## Phase 3: 음성 네거티브 체크

```powershell
# 새 파일에 하드코딩된 API 키 없는지 확인
Select-String -Path "lib\custom_code\widgets\trial\trial_signup_sheet.dart" -Pattern "sk-|apiKey|Bearer"
# 예상: 0건
```

---

## Phase 4: 빌드 검증

```powershell
dart format lib\custom_code\widgets\trial\trial_signup_sheet.dart
dart format lib\custom_code\widgets\trial\trial_study_page.dart
flutter analyze
flutter build appbundle --build-name=0.0.0 --build-number=1
```

---

## Phase 5: 커밋

```powershell
git add -A && git commit -m "feat: trial signup bottom sheet after study room completion"
git push origin main
```

---

## Phase 6: 롤백

```powershell
git log --oneline -3
# savepoint 커밋 해시 확인 후:
git reset --hard 【savepoint_해시】
```

---

## 【Codex 실행 전 확인사항】

| # | 항목 | 상태 |
|---|------|------|
| 1 | Phase 0-1 grep 결과로 실제 완료 앵커 식별 | ⬜ |
| 2 | Phase 0-2 grep 결과로 실제 로그인 함수명 확인 | ⬜ |
| 3 | `trial_signup_sheet.dart` 내 `【치환필요】` 주석 3곳 실제 함수로 교체 | ⬜ |
| 4 | `【확인필요】` 아이콘 에셋 경로 실제 경로로 교체 | ⬜ |
| 5 | Phase 2 old_str을 실제 코드로 확정 | ⬜ |