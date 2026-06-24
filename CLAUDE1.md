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

# 지시문 — Anyone 모드: 이용방법 팝업 잘림 수정 + 초/중/고급 UI 제거 (A안)

**대상 파일:** `routine_mode_anyone.dart`
**작업 성격:** 외관/UI 변경 (cosmetic). brain·프롬프트 파이프라인 무손상.
**핵심 원칙:** 최소 diff · 아래→위 편집 순서 · 앵커 문자열 기반 · `dart format`은 **이 파일 단독으로만**.

---

## 무엇을 / 왜

1. **이용방법 팝업 하단 잘림 수정**
   - 원인: 말풍선 오버레이(`_buildUsageGuide`)가 `Expanded > Stack` 안의 `Positioned.fill`이라 높이가 채팅영역으로 제한 → 본문이 가용 높이를 넘기면 하단 클리핑.
   - 해결: 말풍선 바깥 `Column`을 `SingleChildScrollView`로 래핑 → 작은 화면/폰트 확대에서도 넘치는 만큼 스크롤.

2. **초급/중급/고급 선택 UI 제거 (A안)**
   - 선택바 위젯·호출·load/save 메서드만 제거. `_freeTalkLevel`은 `"Intermediate"`로 **고정 상수**.
   - 프롬프트 파이프라인(`level: _freeTalkLevel` 3곳, `_freeTalkLevelInstruction`)은 **건드리지 않음**.
   - 엣지케이스 차단: 예전에 Beginner 등을 저장한 사용자가 `_loadFreeTalkLevel()` 때문에 그 값에 영구 고정되는 것을 막기 위해 load/save 호출·메서드도 함께 제거.

---

## 0. Git 세이브포인트 (실행 전 필수)

```bash
git add -A
git commit -m "savepoint: before anyone usageguide-scroll + remove level UI"
```

---

## 편집 (아래→위 순서, 라인 드리프트 방지)

### [E1] `_buildTopControls()` 메서드 전체 삭제 (≈1896~1954)

`_buildChatList()` 앵커로 메서드 전체 + 후행 빈 줄 제거.

**OLD:**
```dart
  Widget _buildTopControls() {
    const levels = ["Beginner", "Intermediate", "Advanced"];
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Container(
        height: 44,
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          color: const Color(0xFF1C1C1E),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
        ),
        child: Row(
          children: List.generate(levels.length, (i) {
            final bool selected = _freeTalkLevel == levels[i];
            return Expanded(
              child: GestureDetector(
                onTap: () => _setFreeTalkLevel(levels[i]),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  curve: Curves.easeInOut,
                  alignment: Alignment.center,
                  margin: const EdgeInsets.symmetric(horizontal: 2),
                  decoration: BoxDecoration(
                    color: Colors.transparent,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: selected
                          ? const Color(0xFF9333EA)
                          : Colors.transparent,
                      width: 1.5,
                    ),
                  ),
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: Text(
                        levels[i],
                        maxLines: 1,
                        softWrap: false,
                        style: TextStyle(
                          color: selected ? Colors.white : Colors.white38,
                          fontSize: 13,
                          fontWeight:
                              selected ? FontWeight.w700 : FontWeight.w400,
                          letterSpacing: -0.2,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            );
          }),
        ),
      ),
    );
  }

  Widget _buildChatList() {
```

**NEW:**
```dart
  Widget _buildChatList() {
```

---

### [E2] 스테일 주석에서 `_buildTopControls` 제거 (≈1809)

**OLD:**
```dart
  // ... (_buildTopBar, _buildTopControls, _buildChatList, _buildTextBlock, _buildControlArea는 기존과 동일하게 유지) ...
```

**NEW:**
```dart
  // ... (_buildTopBar, _buildChatList, _buildTextBlock, _buildControlArea는 기존과 동일하게 유지) ...
```

---

### [E3] 팝업: `SingleChildScrollView` 닫는 괄호 추가 (≈1803, _buildUsageGuide 끝부분)

> 닫는 괄호를 **먼저** 추가(아래쪽이므로). 외부 `Column` 닫힘 `),` 바로 다음에 `          ),` 한 줄 삽입.

**OLD:**
```dart
                    const Align(
                      alignment: Alignment.centerRight,
                      child: Text("(말풍선을 톡 누르면 닫혀요)",
                          style:
                              TextStyle(color: Colors.white38, fontSize: 11)),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
```

**NEW:**
```dart
                    const Align(
                      alignment: Alignment.centerRight,
                      child: Text("(말풍선을 톡 누르면 닫혀요)",
                          style:
                              TextStyle(color: Colors.white38, fontSize: 11)),
                    ),
                  ],
                ),
              ),
            ],
          ),
          ),
        ),
      ),
    );
  }
```

---

### [E4] 팝업: 바깥 `Column`을 `SingleChildScrollView`로 래핑 시작 (≈1742)

`fromLTRB(20, 6, 20, 20)` 앵커(파일 내 유일).

**OLD:**
```dart
          padding: const EdgeInsets.fromLTRB(20, 6, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
```

**NEW:**
```dart
          padding: const EdgeInsets.fromLTRB(20, 6, 20, 20),
          child: SingleChildScrollView(
            child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
```

> 들여쓰기가 어긋나 보이지만 정상입니다. 마지막 `dart format`(단일 파일)에서 자동 정렬됩니다.

---

### [E5] `build()` 내 `_buildTopControls()` 호출 + 인접 SizedBox 삭제 (≈1719~1720)

**OLD:**
```dart
          _buildTopBar(),
          const SizedBox(height: 10),
          _buildTopControls(),
          const SizedBox(height: 10),
          Expanded(
```

**NEW:**
```dart
          _buildTopBar(),
          const SizedBox(height: 10),
          Expanded(
```

---

### [E6] `initState`의 `_loadFreeTalkLevel()` 호출 삭제 (≈262)

**OLD:**
```dart
    _initPermissions();
    _loadFreeTalkLevel();
    _fetchKeys();
```

**NEW:**
```dart
    _initPermissions();
    _fetchKeys();
```

---

### [E7] `_loadFreeTalkLevel` + `_setFreeTalkLevel` 메서드 삭제 (≈215~228)

`// 오디오 및 UI` 앵커로 두 메서드 + 후행 빈 줄 제거.

**OLD:**
```dart
  // 언어 수준 로드/저장 (SharedPreferences)
  Future<void> _loadFreeTalkLevel() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString('free_talk_level');
    if (saved != null && saved.isNotEmpty && mounted) {
      setState(() => _freeTalkLevel = saved);
    }
  }

  Future<void> _setFreeTalkLevel(String level) async {
    if (mounted) setState(() => _freeTalkLevel = level);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('free_talk_level', level);
  }

  // 오디오 및 UI
```

**NEW:**
```dart
  // 오디오 및 UI
```

---

### [E8] `_freeTalkLevel` 필드 주석 갱신 + `final` 고정 (≈209~210)

**OLD:**
```dart
  // Free Talk 언어 수준 (대화 중 토글 가능: Beginner / Intermediate / Advanced)
  String _freeTalkLevel = "Intermediate";
```

**NEW:**
```dart
  // 언어 수준 고정값 (초/중/고급 선택 UI 제거 — 내부 프롬프트 파이프라인용 Intermediate 고정)
  final String _freeTalkLevel = "Intermediate";
```

---

## 검증 (편집 후, 이 파일 기준)

```bash
# 1) 제거 대상 — 모두 0이어야 함
grep -c "_buildTopControls"   routine_mode_anyone.dart   # 기대: 0
grep -c "_setFreeTalkLevel"   routine_mode_anyone.dart   # 기대: 0
grep -c "_loadFreeTalkLevel"  routine_mode_anyone.dart   # 기대: 0
grep -c "free_talk_level"     routine_mode_anyone.dart   # 기대: 0
grep -c "Beginner"            routine_mode_anyone.dart   # 기대: 0

# 2) 보존 대상 — 그대로 유지
grep -c "level: _freeTalkLevel"        routine_mode_anyone.dart   # 기대: 3
grep -cE "_freeTalkLevel\b"            routine_mode_anyone.dart   # 기대: 4 (필드1 + 사용처3)
grep -c "_freeTalkLevelInstruction"    routine_mode_anyone.dart   # 기대: 3 (변동 없음)

# 3) 팝업 래핑 확인 — fromLTRB 다음 줄에 SingleChildScrollView
grep -n -A2 "fromLTRB(20, 6, 20, 20)" routine_mode_anyone.dart
#   기대: child: SingleChildScrollView( 가 보일 것

# 4) 정적 분석 (괄호 균형/미사용 심볼 최종 확인)
flutter analyze
#   기대: No issues found  (최소한 본 파일 관련 error/warning 0)
```

> `flutter analyze`가 통과하면 `SingleChildScrollView` 괄호 균형이 맞은 것입니다(불균형 시 컴파일 에러로 즉시 검출).

---

## 포맷 (반드시 단일 파일)

```bash
dart format routine_mode_anyone.dart
```
⚠️ **폴더 대상 금지** — 한글 문자열 UTF-8 손상 위험. 항상 이 파일만 지정.

---

## 롤백

```bash
# 전체 되돌리기
git checkout HEAD -- routine_mode_anyone.dart
# 또는 커밋했다면
git revert <commit-hash>
```

---

## (선택) 빌드/설치

```bash
flutter build appbundle
# 또는 단말 직접 설치
flutter build apk --release && adb install -r build/app/outputs/flutter-apk/app-release.apk
```

---

## 기대 결과

- 이용방법 팝업: 본문이 길거나 폰트를 키워도 잘리지 않고 필요 시 스크롤됨.
- 상단 초/중/고급 선택바 사라짐. 세로 공간 약 54px 추가 확보.
- 대화 동작/난이도: 내부적으로 Intermediate 고정 유지 → 사용자 체감 변화 없음.