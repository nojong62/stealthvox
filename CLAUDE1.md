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

# StepExpand — 마지막 턴 확장문장 "중복 낭독" 제거 (방안1)

## 목적
5턴(마지막 턴) 완료 직후, 유저 턴에서 이미 nova 음성으로 낭독한 확장문장을
**완성 카드에서 한 번 더 낭독**하는 중복을 제거한다.
- 화면 카드 표시는 그대로 유지 (결과 강조 박스 의도)
- 오디오 재낭독만 제거 → 같은 문장이 같은 목소리로 연달아 두 번 들리던 문제 해결
- 폴리시드 낭독(AUTO-FLOW 2)은 손대지 않음

## 영향 범위
- 단일 파일, 단일 수정 (1개 str_replace 블록)
- 글자(텍스트) 노출은 의도대로 유지 (버블 + 카드)
- 히스토리/Firestore 저장 로직 무관 (변경 없음)
- Box 7 무관

---

## 0. Git 세이브포인트 (필수, 실행 전)

```bash
git add -A
git commit -m "savepoint: before stepexpand dedup v1"
```

---

## 1. 대상 파일

```
routine_mode_step_expand.dart
```

---

## 2. 수정 (str_replace 1건)

### OLD (정확히 일치)

```dart
        _log('🌱 [DONE]', '5턴 완료 → 확장문장 표시 및 낭독 시작');

        // ── AUTO-FLOW 1: 완성된 확장 문장 별도 표시 후 낭독 ──
        if (hostExpanded.isNotEmpty && mounted) {
          setState(() {
            _expandedFinalSentence = hostExpanded;
            _showExpandedFinalCard = true;
          });
          _scrollToBottom();
          await _practiceSpeakText(hostExpanded, 'nova');
        }
```

### NEW

```dart
        _log('🌱 [DONE]', '5턴 완료 → 확장문장 카드 표시 (낭독은 유저 턴에서 완료)');

        // ── AUTO-FLOW 1: 완성된 확장 문장 별도 표시 (방안1: 재낭독 제거) ──
        // 🔧 [방안1-중복제거] 유저 턴에서 이미 동일 확장문장을 nova 음성으로
        //   낭독했으므로, 완성 카드는 화면 표시만 하고 재낭독하지 않는다.
        //   (글자는 버블 + 카드 2회 노출 유지 — 결과 강조용 카드 의도)
        if (hostExpanded.isNotEmpty && mounted) {
          setState(() {
            _expandedFinalSentence = hostExpanded;
            _showExpandedFinalCard = true;
          });
          _scrollToBottom();
        }
```

변경 핵심: `await _practiceSpeakText(hostExpanded, 'nova');` 1줄 제거 + DONE 로그 문구 정정 + 의도 주석 추가.

---

## 3. 검증 (수정 후)

```bash
# (1) hostExpanded 재낭독 호출이 완전히 사라졌는지 → 기대값 0
grep -c "_practiceSpeakText(hostExpanded" routine_mode_step_expand.dart

# (2) _practiceSpeakText 메서드는 살아있어야 함(다른 호출처 유지) → 기대값 4
grep -c "_practiceSpeakText" routine_mode_step_expand.dart

# (3) 완성 카드 표시 플래그는 그대로 유지 → 기대값 1
grep -c "_showExpandedFinalCard = true" routine_mode_step_expand.dart

# (4) 방안1 주석 마커 1개 삽입 확인 → 기대값 1
grep -c "방안1-중복제거" routine_mode_step_expand.dart

# (5) 폴리시드 낭독은 그대로(AUTO-FLOW 2) → 기대값 1
grep -c "_practiceSpeakText(polished" routine_mode_step_expand.dart
```

기대 결과 요약:
- (1) = 0
- (2) = 4
- (3) = 1
- (4) = 1
- (5) = 1

### 정적 분석

```bash
flutter analyze routine_mode_step_expand.dart
```
새로운 오류/경고 0건이어야 함. (제거된 `await` 1줄로 인한 unused 변수 없음 — `hostExpanded`는 카드 setState 및 `_autoPolishAndSpeak(hostExpanded)`에서 계속 사용.)

### dart format (개별 파일만)

```bash
dart format routine_mode_step_expand.dart
```
※ 폴더 단위 금지. 반드시 이 파일 하나만.

---

## 4. 동작 확인 (실기기/에뮬)

1. StepExpand 5턴까지 완주
2. 마지막 5턴 발화 후:
   - 유저 턴에서 확장문장이 **한 번** 낭독되는지
   - 완성 카드가 화면에 **뜨되, 다시 낭독하지 않는지** (이전엔 같은 문장 재낭독 → 이번엔 무음으로 카드만 등장)
   - 이어서 폴리시드 문장이 **한 번** 낭독되는지
3. 로그에서 `[DONE] 5턴 완료 → 확장문장 카드 표시 (낭독은 유저 턴에서 완료)` 확인
4. 히스토리(Study Room) 진입 → 확장문장/폴리시드 정상 저장·표시 확인 (변경 없음, 회귀만 점검)

---

## 5. 롤백

```bash
git checkout HEAD -- routine_mode_step_expand.dart
# 또는 커밋했다면
git revert <commit-hash>
```