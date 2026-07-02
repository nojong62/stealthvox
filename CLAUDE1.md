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

# 인트로 UI 카드 그룹핑(B형) + 언어설정 팝업 복귀 + 스크롤/Anyone 자동진입 통합 지시문

## 목표
1. **레이아웃(B형)**: 헤드라인+서브텍스트+웨이브폼을 하나의 카드로 묶고, 그 아래 온보딩 가이드 카드를 배치 — 두 카드가 같은 리듬으로 이어지는 구조. 헤드라인 폰트 28→22, 여백도 목업 비율에 맞게 축소.
2. **언어설정**: 인라인 카드 → 팝업으로 복귀 (틸 아이콘 + 골드 아웃라인 확인 버튼, 12개 언어 — 기존 5개 + Flux 언어 7개)
3. CTA 탭 → 팝업(언어설정) → 확인 → 팝업 없이 바로 Anyone 방 진입
4. "회원 가입" 클릭 시 스크롤 최상단부터 보이도록 수정
5. `StealthRoomMaster`가 트라이얼 Anyone 세션이면 메뉴 화면 없이 바로 Anyone 모드로 진입

## 영향 범위
- `lib/custom_code/widgets/intro_master.dart` (수정)
- `lib/custom_code/widgets/stealth_room_master.dart` (수정)
- `routine_mode_anyone.dart`는 **수정 없음** (이미 `TrialFlowState.instance.isTrialAnyone`을 스스로 체크)

---

## Phase 0 — savepoint + 앵커 사전 검증

```bash
git add -A && git commit -m "savepoint: before B-layout card grouping + language popup revert"

grep -n "const SizedBox(height: 8)," lib/custom_code/widgets/intro_master.dart
grep -n "Widget _buildLanguageSettingSection() {" lib/custom_code/widgets/intro_master.dart
grep -n "Future<void> _startTrial(BuildContext context) async {" lib/custom_code/widgets/intro_master.dart
grep -n "_isSignupMode = true;" lib/custom_code/widgets/intro_master.dart
grep -n "class _StealthRoomMasterState extends State<StealthRoomMaster>" lib/custom_code/widgets/stealth_room_master.dart
grep -n "^import 'trial/trial_flow_state.dart';" lib/custom_code/widgets/stealth_room_master.dart
```

`const SizedBox(height: 8),`는 파일 내 여러 곳에 있을 수 있으니, Phase 1-1의 old_str은 **아래 제시된 여러 줄 블록 전체**로 매칭할 것 (한 줄만 잘라서 매칭하지 말 것). `trial_flow_state.dart` import는 count=0이 정상(이번에 추가).

---

## Phase 1 — intro_master.dart (줄 번호 큰 것부터)

### 1-1. `_buildLanguageSettingSection()` → `_showLanguageSettingDialog()` 전체 교체

```
old_str:
  Widget _buildLanguageSettingSection() {
    const languages = ['Korean', 'English', 'Japanese', 'Chinese', 'Spanish'];
    return _buildBentoCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '언어 설정',
            style: TextStyle(
                color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 14),
          _languageDropdown(
            label: '모국어',
            value: _trialNativeLang,
            items: languages,
            onChanged: (value) => setState(() => _trialNativeLang = value),
          ),
          const SizedBox(height: 14),
          _languageDropdown(
            label: '학습 언어',
            value: _trialTargetLang,
            items: languages,
            onChanged: (value) => setState(() => _trialTargetLang = value),
          ),
        ],
      ),
    );
  }

new_str:
  Future<void> _showLanguageSettingDialog() async {
    const languages = [
      'Korean', 'English', 'Japanese', 'Chinese', 'Spanish',
      'French', 'German', 'Hindi', 'Russian', 'Portuguese', 'Italian', 'Dutch',
    ];
    String nativeLang = _trialNativeLang;
    String targetLang = _trialTargetLang;

    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (dialogContext, setDialogState) {
            return AlertDialog(
              backgroundColor: const Color(0xFF161616),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
                side: const BorderSide(color: Color(0xFF2A3A36), width: 1),
              ),
              title: const Row(
                children: [
                  Icon(Icons.translate, color: Color(0xFF5DCAA5), size: 20),
                  SizedBox(width: 8),
                  Text('언어 설정',
                      style: TextStyle(
                          color: Colors.white, fontWeight: FontWeight.bold)),
                ],
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _languageDropdown(
                    label: '모국어',
                    value: nativeLang,
                    items: languages,
                    onChanged: (value) =>
                        setDialogState(() => nativeLang = value),
                  ),
                  const SizedBox(height: 14),
                  _languageDropdown(
                    label: '학습 언어',
                    value: targetLang,
                    items: languages,
                    onChanged: (value) =>
                        setDialogState(() => targetLang = value),
                  ),
                ],
              ),
              actionsPadding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
              actions: [
                SizedBox(
                  width: double.infinity,
                  height: 46,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.transparent,
                      shadowColor: Colors.transparent,
                      elevation: 0,
                      side: const BorderSide(
                          color: Color(0xFFEF9F27), width: 1.5),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    onPressed: () {
                      setState(() {
                        _trialNativeLang = nativeLang;
                        _trialTargetLang = targetLang;
                      });
                      Navigator.of(dialogContext).pop();
                    },
                    child: const Text(
                      '확인',
                      style: TextStyle(
                          color: Color(0xFFFAC775),
                          fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }
```

`_languageDropdown()` 메서드는 재사용되므로 삭제하지 말 것.

### 1-2. 헤드라인 영역 → B형 카드 그룹핑으로 재구성 (언어설정 인라인 카드 제거 포함)

```
old_str:
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          const Icon(Icons.record_voice_over,
                              size: 22, color: Color(0xFF5DCAA5)),
                          const SizedBox(width: 8),
                          Text("StealthVox",
                              style: GoogleFonts.orbitron(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white)),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text("내 이야기로 배우는 영어",
                          style: GoogleFonts.roboto(
                              fontSize: 12, color: Colors.white38)),
                      const SizedBox(height: 28),
                      const Text(
                        "당신의 이야기가\n최고의 영어 교재가\n됩니다",
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 28,
                          fontWeight: FontWeight.bold,
                          height: 1.3,
                        ),
                      ),
                      const SizedBox(height: 12),
                      const Text(
                        "자율 학습 공부의 동반자",
                        style: TextStyle(color: Colors.white54, fontSize: 14),
                      ),
                      const SizedBox(height: 24),
                      Center(child: _buildWaveform()),
                      const SizedBox(height: 32),
                      _buildLanguageSettingSection(),
                      const SizedBox(height: 16),
                      const OnboardingGuideSection(),
                      const SizedBox(height: 28),

new_str:
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          const Icon(Icons.record_voice_over,
                              size: 22, color: Color(0xFF5DCAA5)),
                          const SizedBox(width: 8),
                          Text("StealthVox",
                              style: GoogleFonts.orbitron(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white)),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text("내 이야기로 배우는 영어",
                          style: GoogleFonts.roboto(
                              fontSize: 12, color: Colors.white38)),
                      const SizedBox(height: 20),
                      _buildBentoCard(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              "당신의 이야기가\n최고의 영어 교재가\n됩니다",
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 22,
                                fontWeight: FontWeight.bold,
                                height: 1.4,
                              ),
                            ),
                            const SizedBox(height: 8),
                            const Text(
                              "자율 학습 공부의 동반자",
                              style:
                                  TextStyle(color: Colors.white54, fontSize: 12),
                            ),
                            const SizedBox(height: 14),
                            _buildWaveform(),
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),
                      const OnboardingGuideSection(),
                      const SizedBox(height: 24),
```

주의: `_buildWaveform()`이 이제 `Center` 없이 카드 안에서 왼쪽 정렬로 보입니다 (B형 목업 기준 의도된 변경). 가운데 정렬을 유지하고 싶으면 `_buildWaveform()`을 `Center(child: _buildWaveform())`로 바꿔서 적용.

### 1-3. `_startTrial()`에 팝업 호출 삽입

```
old_str:
      await TrialDeviceGate.markUsed();

      FFAppState().nativeLang = _trialNativeLang;
      FFAppState().targetLang = _trialTargetLang;

      if (!mounted) return;
      await _enterTrialAnyone();

new_str:
      await TrialDeviceGate.markUsed();

      if (!mounted) return;
      await _showLanguageSettingDialog();

      FFAppState().nativeLang = _trialNativeLang;
      FFAppState().targetLang = _trialTargetLang;

      if (!mounted) return;
      await _enterTrialAnyone();
```

### 1-4. 회원가입 스크롤 top 고정

```
old_str:
                          onPressed: () => setState(() {
                            _isSignupMode = true;
                            _showEmailInSignup = false;
                          }),

new_str:
                          onPressed: () {
                            if (_scrollController.hasClients) {
                              _scrollController.jumpTo(0);
                            }
                            setState(() {
                              _isSignupMode = true;
                              _showEmailInSignup = false;
                            });
                          },
```

---

## Phase 2 — stealth_room_master.dart

### 2-1. import 추가

```
old_str:
import '/custom_code/actions/billing_ticker.dart';

new_str:
import '/custom_code/actions/billing_ticker.dart';
import 'trial/trial_flow_state.dart';
```

(경로가 다르면 Phase 0 grep 결과 기준으로 상대경로 보정)

### 2-2. initState에 트라이얼 자동진입 로직 추가

```
old_str:
    if (FFAppState().isGuestSession && FFAppState().duoRoomId.isNotEmpty) {
      final String consumedRoomId = FFAppState().duoRoomId;
      debugPrint('[StealthRoom] Duo invite detected — roomId: $consumedRoomId');
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          setState(() {
            _pendingDuoRoomId = consumedRoomId;
            _currentMode = 1;
          });
        }
      });
    }
  }

new_str:
    if (FFAppState().isGuestSession && FFAppState().duoRoomId.isNotEmpty) {
      final String consumedRoomId = FFAppState().duoRoomId;
      debugPrint('[StealthRoom] Duo invite detected — roomId: $consumedRoomId');
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          setState(() {
            _pendingDuoRoomId = consumedRoomId;
            _currentMode = 1;
          });
        }
      });
    }

    // 트라이얼 Anyone 자동 진입 — 메뉴 화면을 건너뛰고 바로 Anyone 모드로
    TrialFlowState.instance.restoreFromAppState();
    if (TrialFlowState.instance.isTrialAnyone) {
      _currentMode = 2;
    }
  }
```

---

## Phase 3 — 검증

```bash
grep -c "_showLanguageSettingDialog\|_buildLanguageSettingSection" lib/custom_code/widgets/intro_master.dart
# _showLanguageSettingDialog 2회(정의+호출), _buildLanguageSettingSection 0회

grep -c "_buildBentoCard" lib/custom_code/widgets/intro_master.dart
# 기존 사용처 + 신규 헤드라인 카드 1개 추가되어 카운트 +1

grep -c "TrialFlowState" lib/custom_code/widgets/stealth_room_master.dart

flutter analyze lib/custom_code/widgets/intro_master.dart
flutter analyze lib/custom_code/widgets/stealth_room_master.dart
dart format lib/custom_code/widgets/intro_master.dart
dart format lib/custom_code/widgets/stealth_room_master.dart
```

---

## Phase 4 — 실기기 체크리스트

- [ ] 헤드라인+서브텍스트+웨이브폼이 하나의 카드 안에 있고, 바로 아래 온보딩 가이드 카드가 같은 톤으로 이어짐
- [ ] 헤드라인 글자 크기가 이전보다 작아지고 여백이 좁아져서 숏츠 비율에서도 답답해 보이지 않음
- [ ] CTA 탭 → 팝업(틸 아이콘 + 12개 언어 + 골드 아웃라인 확인 버튼) → 확인 → 팝업 없이 바로 Anyone 대화 화면
- [ ] "회원 가입" 클릭 시 다음 화면이 스크롤 맨 위부터 보임
- [ ] Duo 초대링크 진입은 기존처럼 정상 동작 (회귀 확인)

**롤백**: `git revert <savepoint 이후 커밋>` 또는 `git reset --hard <savepoint>`