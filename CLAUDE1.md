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

# 지시문 9: Auth 화면 문구 정리 + 탄생년 범위 확장

## 목적
1. 재방문 시 제목 중복 제거: "카카오 계정으로 계속하기" + "이전에 카카오 계정으로 가입했습니다" → "이전에..." 안내만 남기고 제목은 "계정으로 계속하기"로 통일
2. 탄생년 선택 범위를 1966년(currentYear-60)에서 1940년까지 확장

## 대상 파일
- **수정**: `lib/custom_code/widgets/intro_master.dart` (2곳)

---

## Phase 1: Savepoint

```bash
git add -A && git commit -m "savepoint: before auth title + birthYear range fix"
```

---

## Phase 2: 수정

### 수정 1: _buildAuthHeader — 제목 중복 제거

**앵커 (현재 코드):**
```dart
  List<Widget> _buildAuthHeader() {
    final lastProvider = FFAppState().lastAuthProvider;
    final providerLabel = switch (lastProvider) {
      'kakao' => '카카오',
      'google' => 'Google',
      'email' => '이메일',
      _ => '',
    };

    return [
      Text(
        lastProvider.isNotEmpty ? '$providerLabel 계정으로\n계속하기' : '계정으로 계속하기',
        textAlign: TextAlign.center,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 22,
          fontWeight: FontWeight.w800,
          height: 1.32,
        ),
      ),
      if (lastProvider.isNotEmpty) ...[
        const SizedBox(height: 8),
        Text(
          '이전에 $providerLabel 계정으로 가입했습니다',
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: Color(0xFF9C9CA6),
            fontSize: 13,
          ),
        ),
      ],
    ];
  }
```

**변경:**
```dart
  List<Widget> _buildAuthHeader() {
    final lastProvider = FFAppState().lastAuthProvider;
    final providerLabel = switch (lastProvider) {
      'kakao' => '카카오',
      'google' => 'Google',
      'email' => '이메일',
      _ => '',
    };

    return [
      const Text(
        '계정으로 계속하기',
        textAlign: TextAlign.center,
        style: TextStyle(
          color: Colors.white,
          fontSize: 22,
          fontWeight: FontWeight.w800,
          height: 1.32,
        ),
      ),
      if (lastProvider.isNotEmpty) ...[
        const SizedBox(height: 10),
        Text(
          '이전에 $providerLabel 계정으로 가입했습니다',
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: Color(0xFF9C9CA6),
            fontSize: 13,
          ),
        ),
      ],
    ];
  }
```

> **변경 포인트**: 제목은 항상 "계정으로 계속하기" 고정, lastProvider가 있으면 그 아래에 "이전에 카카오 계정으로 가입했습니다" 안내만 추가.

---

### 수정 2: _showBirthYearDialog — 탄생년 범위 1940년까지 확장

**앵커 (현재 코드, _showBirthYearDialog 내부에서 3곳):**

첫째, initialItem 계산:
```dart
                  controller: FixedExtentScrollController(
                    initialItem: 40, // currentYear-60 기준 +40 → 약 20세
                  ),
```

**변경:**
```dart
                  controller: FixedExtentScrollController(
                    initialItem: currentYear - 1940 - 20, // 기본값: 약 20세
                  ),
```

둘째, 연도 범위 하한:
```dart
                      final year = (currentYear - 60) + index;
                      if (year < currentYear - 60 || year > currentYear - 4) {
```

**변경:**
```dart
                      final year = 1940 + index;
                      if (year < 1940 || year > currentYear - 4) {
```

셋째, childCount:
```dart
                    childCount: 57, // currentYear-60 ~ currentYear-4
```

**변경:**
```dart
                    childCount: currentYear - 4 - 1940 + 1, // 1940 ~ currentYear-4
```

넷째, onSelectedItemChanged:
```dart
                  onSelectedItemChanged: (index) {
                    setDialogState(
                        () => selectedYear = (currentYear - 60) + index);
                  },
```

**변경:**
```dart
                  onSelectedItemChanged: (index) {
                    setDialogState(
                        () => selectedYear = 1940 + index);
                  },
```

---

## Phase 3: 검증

```bash
dart format lib/custom_code/widgets/intro_master.dart
flutter analyze lib/custom_code/widgets/intro_master.dart

# 중복 제목 제거 확인
grep "providerLabel.*계정으로.*계속하기" lib/custom_code/widgets/intro_master.dart
# 기대: 0줄 (provider 이름이 제목에 안 들어감)

# 1940 적용 확인
grep "1940" lib/custom_code/widgets/intro_master.dart
# 기대: 3줄 이상
```

---

## Phase 4: 커밋 및 머지

```bash
git add -A && git commit -m "fix: simplify auth title, extend birthYear range to 1940"
git checkout main
git merge fix/intro-auth-gates  # 또는 현재 브랜치 이름
git push origin main
```