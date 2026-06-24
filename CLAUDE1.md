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

# 지시문 — Anyone 모드 1차 (구조 리네임 + 이용방법 말풍선 UI)

> 대상 에이전트: **Claude Code**
> 작업 폴더: `F:\flutter_project\stealth_vox`
> 위젯 경로: `lib/custom_code/widgets/`
> 본 지시문 범위: **FreeTalk → Anyone 구조 리네임 + 이용방법 아이콘/말풍선 추가 + 연결 파일 갱신**
> **제외**: AI 대화 프롬프트(대화 방식) 재작성 → 별도 2차 지시문에서 처리 (이번 단계에서 손대지 말 것)

---

## 0. 확정된 설계 결정 (변경 금지)

- 외부 위젯 클래스만 리네임: `RoutineModeFreeTalk → RoutineModeAnyone` / `_RoutineModeFreeTalkState → _RoutineModeAnyoneState`
- **내부 클래스/상수는 그대로 유지**: `FreeTalkBrain`, `kFreeTalk*`, `TtsCache`, `TtsQueueManager` 등 일절 변경 금지
- **히스토리 저장 라벨 유지**: `mode:'free_talk'`, `room_name:"Free Talk"` 그대로 (수정 금지)
- **구 `routine_mode_free_talk.dart`는 삭제하지 않음** → index.dart export·stealth_room 라우팅만 끊어 휴면(orphan)화. git 안전망으로 보존
- 새 모드 표시명: **Anyone / "누구든 그 사람이 되어요" / `Icons.theater_comedy`**

---

## 1. 사전 안전장치 (필수)

```bash
cd F:\flutter_project\stealth_vox
git add -A
git commit -m "savepoint: before Anyone mode phase1"
```

---

## 2. STEP A — 파일 복제 (free_talk → anyone)

```bash
copy "lib\custom_code\widgets\routine_mode_free_talk.dart" "lib\custom_code\widgets\routine_mode_anyone.dart"
```

복제 직후 사전 검증 (기대값 표기):

```bash
findstr /C:"RoutineModeFreeTalk" "lib\custom_code\widgets\routine_mode_anyone.dart" | find /c /v ""
:: 기대: 4  (클래스 선언/생성자/State 참조/State 클래스 선언)
findstr /C:"_RoutineModeFreeTalkState" "lib\custom_code\widgets\routine_mode_anyone.dart" | find /c /v ""
:: 기대: 2
```

> 이후 STEP B의 모든 편집은 **새 파일 `routine_mode_anyone.dart`** 에만 적용한다. (free_talk.dart는 절대 건드리지 않는다.)

---

## 3. STEP B — `routine_mode_anyone.dart` 편집 (하단→상단 순서)

### B-1. 파일 맨 끝: 말풍선 꼬리 페인터 클래스 추가

`_LangIconPainter`의 마지막 닫는 중괄호 뒤(파일 끝)에 새 클래스를 **추가**한다.

**OLD**
```dart
  @override
  bool shouldRepaint(_LangIconPainter old) => old.active != active;
}
```

**NEW**
```dart
  @override
  bool shouldRepaint(_LangIconPainter old) => old.active != active;
}

// 🆕 [Anyone] 이용방법 말풍선 꼬리 페인터
class _BubbleTailPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xFF2A2A2E)
      ..style = PaintingStyle.fill;
    final path = Path()
      ..moveTo(0, size.height)
      ..lineTo(size.width / 2, 0)
      ..lineTo(size.width, size.height)
      ..close();
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
```

---

### B-2. `_buildTopBar()` 우측 아이콘 그룹에 "이용방법" 아이콘 추가

**OLD**
```dart
          Row(children: [
            IconButton(
              icon: Icon(
                Icons.format_size,
```

**NEW**
```dart
          Row(children: [
            // 🆕 [Anyone] 이용방법 말풍선 토글
            IconButton(
              icon: const Icon(Icons.help_outline,
                  color: Colors.amberAccent, size: 22),
              onPressed: () =>
                  setState(() => _showUsageGuide = !_showUsageGuide),
            ),
            IconButton(
              icon: Icon(
                Icons.format_size,
```

---

### B-3. `_buildUsageGuide()` 메서드 추가 (`_buildTopBar` 바로 앞)

**OLD**
```dart
  // ... (_buildTopBar, _buildTopControls, _buildChatList, _buildTextBlock, _buildControlArea는 기존과 동일하게 유지) ...
  Widget _buildTopBar() {
```

**NEW**
```dart
  // 🆕 [Anyone] 이용방법 말풍선 (배경/말풍선 어디든 톡 누르면 닫힘)
  Widget _buildUsageGuide() {
    return Positioned.fill(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => setState(() => _showUsageGuide = false),
        child: Container(
          color: Colors.black.withValues(alpha: 0.55),
          alignment: Alignment.topCenter,
          padding: const EdgeInsets.fromLTRB(20, 6, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Align(
                alignment: Alignment.topRight,
                child: Padding(
                  padding: const EdgeInsets.only(right: 22),
                  child: CustomPaint(
                    size: const Size(22, 11),
                    painter: _BubbleTailPainter(),
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: const Color(0xFF2A2A2E),
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(
                      color: Colors.amberAccent.withValues(alpha: 0.6),
                      width: 1.2),
                  boxShadow: [
                    BoxShadow(
                        color: Colors.black.withValues(alpha: 0.4),
                        blurRadius: 16,
                        offset: const Offset(0, 6)),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: const [
                      Icon(Icons.lightbulb_outline,
                          color: Colors.amberAccent, size: 20),
                      SizedBox(width: 8),
                      Text("이용 방법",
                          style: TextStyle(
                              color: Colors.amberAccent,
                              fontWeight: FontWeight.bold,
                              fontSize: 15)),
                    ]),
                    const SizedBox(height: 12),
                    const Text(
                      '대화하고 싶은 사람을 한 명 마음속에 떠올려 보세요. 그리고 그 사람이 바로 지금 눈앞에 있다고 생각하고, 하고 싶었던 말을 편하게 꺼내보세요. AI가 그 사람과 다르게 반응한다면, 그냥 넘기지 말고 "왜 그렇게 느껴?"하고 되물어 보세요. 묻고 답하다 보면, AI는 점점 더 그 사람에 가까워집니다. 진짜 그 사람과 마주 앉은 것처럼요.',
                      style: TextStyle(
                          color: Colors.white, fontSize: 14, height: 1.6),
                    ),
                    const SizedBox(height: 10),
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

  // ... (_buildTopBar, _buildTopControls, _buildChatList, _buildTextBlock, _buildControlArea는 기존과 동일하게 유지) ...
  Widget _buildTopBar() {
```

---

### B-4. `build()`의 Stack에 말풍선 오버레이 연결

**OLD**
```dart
          Expanded(
            child: Stack(children: [
              _buildChatList(),
              _buildIdleOverlay(),
            ]),
          ),
```

**NEW**
```dart
          Expanded(
            child: Stack(children: [
              _buildChatList(),
              _buildIdleOverlay(),
              if (_showUsageGuide) _buildUsageGuide(), // 🆕 [Anyone] 이용방법 말풍선
            ]),
          ),
```

---

### B-5. 상태 변수 `_showUsageGuide` 추가

**OLD**
```dart
  double _fontScale = 1.0;
  bool _showOriginal = true;
```

**NEW**
```dart
  double _fontScale = 1.0;
  bool _showOriginal = true;
  bool _showUsageGuide = false; // 🆕 [Anyone] 이용방법 말풍선 토글
```

---

### B-6. 외부 위젯 클래스 리네임 (이 파일의 마지막 편집)

**OLD**
```dart
class RoutineModeFreeTalk extends StatefulWidget {
  const RoutineModeFreeTalk({super.key, this.width, this.height});
  final double? width;
  final double? height;

  @override
  State<RoutineModeFreeTalk> createState() => _RoutineModeFreeTalkState();
}

class _RoutineModeFreeTalkState extends State<RoutineModeFreeTalk> {
```

**NEW**
```dart
class RoutineModeAnyone extends StatefulWidget {
  const RoutineModeAnyone({super.key, this.width, this.height});
  final double? width;
  final double? height;

  @override
  State<RoutineModeAnyone> createState() => _RoutineModeAnyoneState();
}

class _RoutineModeAnyoneState extends State<RoutineModeAnyone> {
```

---

## 4. STEP C — `lib/custom_code/widgets/stealth_room_master.dart` 편집 (하단→상단)

### C-1. 메뉴 카드 라벨 (라인 ~379)

**OLD**
```dart
            _buildMenuCard(2, "Free Talk", "AI와 자유 대화", Icons.forum,
                const Color(0xFF9333EA)),
```

**NEW**
```dart
            _buildMenuCard(2, "Anyone", "누구든 그 사람이 되어요",
                Icons.theater_comedy, const Color(0xFF9333EA)),
```

### C-2. 모드 라우팅 진입점 (라인 ~297)

**OLD**
```dart
      return RoutineModeFreeTalk(
          key: const ValueKey('RoutineModeFreeTalk'),
          width: widget.width,
          height: widget.height);
```

**NEW**
```dart
      return RoutineModeAnyone(
          key: const ValueKey('RoutineModeAnyone'),
          width: widget.width,
          height: widget.height);
```

---

## 5. STEP D — `lib/custom_code/widgets/index.dart` export 교체

> 이 파일은 미업로드 상태. 아래 패턴을 찾아 **교체**한다. (추가 아님 — 중복 Box7 클래스 충돌 방지)

먼저 확인:
```bash
findstr /N "routine_mode_free_talk" "lib\custom_code\widgets\index.dart"
```

해당 export 줄을 다음과 같이 교체한다.

**OLD**
```dart
export 'routine_mode_free_talk.dart';
```

**NEW**
```dart
export 'routine_mode_anyone.dart';
```

> 만약 export 표기가 `export '/custom_code/widgets/routine_mode_free_talk.dart';` 처럼 절대경로 형식이면, 그 형식을 그대로 유지하며 파일명만 `routine_mode_anyone.dart`로 바꾼다.

---

## 6. STEP E (선택) — `lib/custom_code/widgets/intro_master.dart` 도움말 문구 (라인 ~335)

> 메뉴가 "Anyone"으로 바뀌므로 도움말의 "[Free Talk]" 안내도 일치시키는 것을 권장. **선택 사항** — 실장 승인 시에만 적용.

**OLD**
```dart
            "• [Free Talk] AI와 자유롭게 영어 대화를 나누며 실전 회화를 연습하세요.\n\n"
```

**NEW**
```dart
            "• [Anyone] 마음속에 떠올린 그 사람에게 말하듯 대화하면, AI가 점점 그 사람이 되어 응답합니다.\n\n"
```

---

## 7. 사후 검증 (필수)

```bash
:: 1) anyone 파일에 구 클래스명이 0이어야 함
findstr /C:"RoutineModeFreeTalk" "lib\custom_code\widgets\routine_mode_anyone.dart" | find /c /v ""
:: 기대: 0
findstr /C:"_RoutineModeFreeTalkState" "lib\custom_code\widgets\routine_mode_anyone.dart" | find /c /v ""
:: 기대: 0

:: 2) 새 클래스명 정상 존재
findstr /C:"RoutineModeAnyone" "lib\custom_code\widgets\routine_mode_anyone.dart" | find /c /v ""
:: 기대: 4

:: 3) UI 추가 요소 확인
findstr /C:"_showUsageGuide" "lib\custom_code\widgets\routine_mode_anyone.dart" | find /c /v ""
:: 기대: 4  (선언 1 + 토글 onPressed 1 + build의 if 1 + _buildUsageGuide 내부 onTap 1)
findstr /C:"_buildUsageGuide" "lib\custom_code\widgets\routine_mode_anyone.dart" | find /c /v ""
:: 기대: 2  (정의 1 + 호출 1)
findstr /C:"_BubbleTailPainter" "lib\custom_code\widgets\routine_mode_anyone.dart" | find /c /v ""
:: 기대: 2  (정의 1 + 사용 1)

:: 4) stealth_room 라우팅/메뉴 갱신 확인
findstr /C:"RoutineModeAnyone" "lib\custom_code\widgets\stealth_room_master.dart" | find /c /v ""
:: 기대: 2
findstr /C:"RoutineModeFreeTalk" "lib\custom_code\widgets\stealth_room_master.dart" | find /c /v ""
:: 기대: 0

:: 5) index.dart export 교체 확인
findstr /C:"routine_mode_anyone" "lib\custom_code\widgets\index.dart" | find /c /v ""
:: 기대: 1
findstr /C:"routine_mode_free_talk" "lib\custom_code\widgets\index.dart" | find /c /v ""
:: 기대: 0
```

포맷 + 분석 (**폴더 전체 금지, 개별 파일만**):

```bash
dart format "lib\custom_code\widgets\routine_mode_anyone.dart"
dart format "lib\custom_code\widgets\stealth_room_master.dart"
dart format "lib\custom_code\widgets\index.dart"
flutter analyze
```

- `flutter analyze`: **errors 0** 목표 (기존 warning 잔존은 허용)
- 특히 `Duplicate definition` / `is defined in libraries` 류 에러가 없는지 확인 → 있으면 index.dart export 교체(STEP D)가 누락된 것

---

## 8. 동작 확인 (수동)

1. 앱 실행 → StealthRoom 메뉴에 **Anyone / "누구든 그 사람이 되어요"** 카드(연극가면 아이콘) 표시
2. Anyone 진입 → 상단 우측에 **전구(?) 아이콘** 표시
3. 아이콘 탭 → 상단에서 **말풍선 가이드** 펼쳐짐(꼬리가 아이콘 쪽을 향함)
4. 말풍선/배경 아무 곳이나 탭 → 사라짐
5. 대화 시작/종료/히스토리 저장이 기존 FreeTalk와 동일하게 동작(이번 단계는 로직 무변경)

---

## 9. 롤백

문제 발생 시:
```bash
git reset --hard HEAD~1
```
(STEP 1 savepoint 커밋으로 복귀. 새로 생성된 `routine_mode_anyone.dart`도 함께 제거됨)

---

## 10. 다음 단계 (2차 지시문 예고 — 이번엔 미실행)

- `routine_mode_anyone.dart`의 대화 프롬프트(응답: ~L3517 / 오프너: ~L3592) 재작성
- 핵심 원칙: **"유저 발화에서 관계·성격·감정·호칭 단서를 내부적으로만 누적 추정, 추론은 절대 출력하지 말고 오직 그 인물의 자연스러운 반응으로만 응답"**
- 프롬프트 문구 확정 후 별도 지시문으로 진행