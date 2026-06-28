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

# 지시문서 — STT 모델 교체 (whisper-1 → gpt-4o-mini-transcribe) · 안전 2곳

## 목적
타임스탬프/prompt 의존이 없는 **영어 발음 STT 2곳**의 모델 문자열만
`whisper-1`($0.006/분) → `gpt-4o-mini-transcribe`($0.003/분, 절반)으로 교체한다.
엔진 클래스·응답 파싱·다운스트림 로직은 일절 건드리지 않는다. (콜사이트 인자 1줄만 변경)

## 대상
| 파일(실제 경로) | 함수 | 줄(업로드 기준) | 비고 |
|---|---|---|---|
| `lib/custom_code/widgets/chat_history_master.dart` | `_stopAppRecordAndProcess` (Box 18-C 자유발화) | ~2894 | LF 줄바꿈 |
| `lib/custom_code/widgets/chat_history_list_master.dart` | `_whisperTranscribe` (Keeper) | ~1507 | **CRLF 줄바꿈** — apply_patch 권장 |

## 제외(이번 배치 아님)
- `chat_history_master.dart` 채점(`1244`): `prompt: targetText` 의존 → 통과율 A/B 후 결정
- `routine_mode_duo.dart`(`396`): 한국어 자동감지 + 고스트 필터 → 실기기 검증 후 결정
- `api_calls.dart` `VoiceToTextCall`: FlutterFlow 자동생성 + 사용처 미확인 → 수동편집 금지

## 인코딩/포맷 규칙(절대)
- PowerShell `-replace` 금지. 적용은 `str_replace` 또는 `apply_patch`만.
- `dart format`은 **개별 파일만** 대상으로. 폴더 단위 format 절대 금지(한국어 UTF-8 문자열 깨짐).
- `chat_history_list_master.dart`는 CRLF이므로 앵커 매칭이 어긋나면 `apply_patch`로 전환.

---

## Phase 0 — Savepoint
```
git add -A && git commit -m "savepoint: before STT mini-transcribe swap (safe 2 sites)"
```
커밋 해시 기록(롤백용): `__________`

## Phase 1 — 앵커 유일성 검증 (각 명령 결과가 기대값과 일치해야 진행)
```
# 자유발화 파일: whisper-1 총 2곳(채점+자유발화) 중 자유발화만 교체 예정
grep -c "model'\] = 'whisper-1'" lib/custom_code/widgets/chat_history_master.dart        # 기대: 2

# Keeper 파일: whisper-1 1곳
grep -c "model'\] = 'whisper-1'" lib/custom_code/widgets/chat_history_list_master.dart   # 기대: 1

# 자유발화 앵커가 파일 내 유일한지(prompt 없음 + 15초 타임아웃 조합)
grep -c "seconds: 15" lib/custom_code/widgets/chat_history_master.dart                   # 기대: 1
```
세 결과가 각각 2 / 1 / 1 이 아니면 **중단**하고 보고.

## Phase 2 — 교체 (파일별 1곳, 바텀업 순서 무관 / 아래 순서대로)

### 2-1) chat_history_master.dart — 자유발화 (앵커: prompt 없음 + seconds:15 → 유일)
old_str:
```
      request.fields['model'] = 'whisper-1';
      request.fields['language'] = 'en';
      request.files.add(await http.MultipartFile.fromPath('file', path));
      final streamed =
          await request.send().timeout(const Duration(seconds: 15));
```
new_str:
```
      request.fields['model'] = 'gpt-4o-mini-transcribe';
      request.fields['language'] = 'en';
      request.files.add(await http.MultipartFile.fromPath('file', path));
      final streamed =
          await request.send().timeout(const Duration(seconds: 15));
```
> 채점(1244)은 중간에 `request.fields['prompt'] = targetText;`가 있고 타임아웃이 `seconds: 10`이라 이 앵커에 걸리지 않는다(= 채점은 whisper-1 유지).

### 2-2) chat_history_list_master.dart — Keeper (CRLF 주의)
old_str:
```
      request.fields['model'] = 'whisper-1';
      request.fields['language'] = 'en';
      request.files.add(http.MultipartFile.fromBytes('file', audioBytes,
          filename: 'audio.m4a'));
```
new_str:
```
      request.fields['model'] = 'gpt-4o-mini-transcribe';
      request.fields['language'] = 'en';
      request.files.add(http.MultipartFile.fromBytes('file', audioBytes,
          filename: 'audio.m4a'));
```
> str_replace가 CRLF 때문에 "not found"면 `apply_patch`로 동일 변경을 적용.

## Phase 3 — 카운트 검증 (기대값과 정확히 일치)
```
grep -c "whisper-1" lib/custom_code/widgets/chat_history_master.dart                 # 기대: 1 (채점만 잔존)
grep -c "gpt-4o-mini-transcribe" lib/custom_code/widgets/chat_history_master.dart    # 기대: 1
grep -c "whisper-1" lib/custom_code/widgets/chat_history_list_master.dart            # 기대: 0
grep -c "gpt-4o-mini-transcribe" lib/custom_code/widgets/chat_history_list_master.dart # 기대: 1
```
하나라도 어긋나면 Phase 5 롤백 후 보고.

## Phase 4 — 분석 + 포맷 (개별 파일만)
```
flutter analyze lib/custom_code/widgets/chat_history_master.dart lib/custom_code/widgets/chat_history_list_master.dart
dart format lib/custom_code/widgets/chat_history_master.dart
dart format lib/custom_code/widgets/chat_history_list_master.dart
```
analyze 신규 에러 0 확인. (폴더 format 금지)

## Phase 5 — 행동 검증 체크리스트 (실기기)
- [ ] 히스토리 **자유발화 튜터링**(Box 18-C): 영어 발화 → transcript 정상 표시 → GPT 교정 정상
- [ ] **Keeper** 발화: 영어 발화 → transcript 정상 → 교정 정상
- [ ] 빌링 틱 `history_tutoring_stt_result` 정상 기록
- [ ] (체감) 인식 지연/정확도가 whisper 대비 동등 이상인지
- [ ] **채점 모드는 변화 없음**(여전히 whisper-1, 통과율 동일) 확인

### 롤백
```
git checkout <Phase0 해시> -- lib/custom_code/widgets/chat_history_master.dart lib/custom_code/widgets/chat_history_list_master.dart
```

---

## 후속(별도 작업)
1. `VoiceToTextCall` 실사용 여부 확인 → dead면 정리 대상, 사용 중이면 FlutterFlow UI에서 처리:
   ```
   grep -rn "VoiceToTextCall" lib/
   ```
2. 채점(`1244`) prompt 의존 — mini-transcribe 통과율 A/B 후 결정
3. Duo(`396`) — 한국어 정확도 + 고스트 필터 실기기 검증 후 결정