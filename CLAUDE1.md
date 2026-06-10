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

# [지시문] ChunkedTtsFetcher TTS 타임아웃 튜닝 (옵션 A) — 4개 모드 일괄 적용

## 0. 배경 및 목적

OpenAI TTS-1 API가 간헐적으로 10초 이상 지연되는 스파이크가 발생하며,
현재 `ChunkedTtsFetcher._fetch`의 timeout 10초 + 재시도 1회(무음 catch) 설정 때문에
사용자가 첫 청크 재생 후 최대 10.5초 이상의 공백을 듣게 되는 문제가 확인됨
(로그 증거: 22:48:05 addText → 22:48:17 API OK = 11.6초 등 3건).

**변경 내용 (이것만 변경, 다른 것 일절 금지):**
- HTTP timeout: `10초 → 5초`
- 총 시도 횟수: `2회 → 3회`
- 재시도 간 딜레이: `500ms → 300ms`
- 타임아웃/예외/최종실패 로그 추가 (기존 무음 `catch (_)` 제거)

**절대 건드리지 말 것:**
- `_pushReady()` 순서 보장 로직
- `_pendingCount` 증감 위치 (`_buffer[id] = result; _pendingCount--;` 이하 4줄은 원형 유지)
- `addText`, `reset`, 캐시 1단계 로직
- `HybridTtsPlayer.onStreamEnd`의 15초 타임아웃 (백그라운드 캐시 저장용 — 별개)
- Brain 클래스 내부의 다른 `attempt < 2` 루프 (GPT 호출용 — 수정 대상 아님)
- PIPE-04 10초 게이트 (의도된 설계 — `현_통신로직_및_개선.txt` 참조)

---

## 1. 대상 파일 (4개)

| # | 파일 | 삭제 블록 위치 (참고용) |
|---|------|------------------------|
| 1 | `lib/custom_code/widgets/routine_mode_step_expand.dart` | 약 4290줄 ~ 4327줄 |
| 2 | `lib/custom_code/widgets/routine_mode_free_talk.dart` | 약 2567줄 ~ 2604줄 |
| 3 | `lib/custom_code/widgets/routine_mode_roleplay.dart` | 약 3028줄 ~ 3065줄 |
| 4 | `lib/custom_code/widgets/routine_mode_clone.dart` | grep으로 위치 확인 (3단계 참조) |

⚠️ 줄번호는 참고용. 실제 편집은 반드시 아래 str_replace 앵커 텍스트 기준으로 수행.
⚠️ `lib/custom_code/임시/` 폴더는 절대 건드리지 말 것. 모든 편집은 `lib/custom_code/widgets/` 대상.

---

## 2. 사전 작업: git 세이브 포인트

```bash
cd F:\flutter_project\stealth_vox
git add -A
git commit -m "save point: before TTS timeout tuning (Option A)"
```

---

## 3. 사전 검증 (편집 전 필수 — 하나라도 불일치 시 중단하고 보고)

각 파일에서 수정 대상 블록이 정확히 1개씩 존재하는지 확인:

```bash
grep -c "\[2단계\] API 호출 (재시도 1회)" lib/custom_code/widgets/routine_mode_step_expand.dart
grep -c "\[2단계\] API 호출 (재시도 1회)" lib/custom_code/widgets/routine_mode_free_talk.dart
grep -c "\[2단계\] API 호출 (재시도 1회)" lib/custom_code/widgets/routine_mode_roleplay.dart
grep -c "\[2단계\] API 호출 (재시도 1회)" lib/custom_code/widgets/routine_mode_clone.dart
```

**기대값: 4개 파일 모두 `1`.**
- 0이면: 해당 파일은 이미 패치됐거나 구조가 다름 → 중단, 보고.
- 2 이상이면: 앵커가 유일하지 않음 → 중단, 보고.

추가로 clone 파일의 블록 내용이 다른 3개와 동일한지 확인:

```bash
grep -n "attempt < 2" lib/custom_code/widgets/routine_mode_clone.dart
```

`attempt < 2`가 2건 나와야 정상 (1건은 TTS용=수정 대상, 1건은 Brain GPT 호출용=수정 금지).
TTS용은 반드시 `[2단계] API 호출` 주석 직후의 루프만 해당됨.

---

## 4. 편집 내용 (str_replace — 4개 파일에 동일하게 적용)

파일당 편집은 1곳뿐이므로 줄번호 드리프트 없음.
적용 순서: ① step_expand → ② free_talk → ③ roleplay → ④ clone.
**파일 1개 편집 완료 시마다 5단계 검증을 통과한 후 다음 파일로 진행.**

### 삭제할 코드 (old_str)

시작: `    // [2단계] API 호출 (재시도 1회)`
끝: for 루프 닫는 중괄호 `    }` (catch 블록 닫힘 직후)

```dart
    // [2단계] API 호출 (재시도 1회)
    Uint8List result = Uint8List(0);
    for (int attempt = 0; attempt < 2; attempt++) {
      try {
        final res = await http
            .post(
              Uri.parse('https://api.openai.com/v1/audio/speech'),
              headers: {
                'Authorization': 'Bearer $apiKey',
                'Content-Type': 'application/json',
              },
              body: jsonEncode({
                'model': 'tts-1',
                'input': text,
                'voice': voice,
                'speed': 1.0,
                'response_format': 'mp3',
              }),
            )
            .timeout(const Duration(seconds: 10));

        if (res.statusCode == 200) {
          result = res.bodyBytes;
          final turnTag = isUser ? 'USER' : 'AI';
          onLog?.call('🔊 [TTS-02]',
              '[$turnTag] API OK (${result.length}B) for "$text"');
          // [3단계] 캐시 저장 (백그라운드)
          TtsCache.put(text, voice, result);
          break;
        } else {
          onLog?.call('❌ [TTS-API-ERR]', 'statusCode=${res.statusCode}');
        }
      } catch (_) {
        if (attempt == 0) {
          await Future.delayed(const Duration(milliseconds: 500));
        }
      }
    }
```

### 교체할 코드 (new_str)

```dart
    // [2단계] API 호출 (5초 타임아웃, 최대 3회 시도) — TTS 지연 스파이크 대응
    Uint8List result = Uint8List(0);
    for (int attempt = 0; attempt < 3; attempt++) {
      try {
        final res = await http
            .post(
              Uri.parse('https://api.openai.com/v1/audio/speech'),
              headers: {
                'Authorization': 'Bearer $apiKey',
                'Content-Type': 'application/json',
              },
              body: jsonEncode({
                'model': 'tts-1',
                'input': text,
                'voice': voice,
                'speed': 1.0,
                'response_format': 'mp3',
              }),
            )
            .timeout(const Duration(seconds: 5));

        if (res.statusCode == 200) {
          result = res.bodyBytes;
          final turnTag = isUser ? 'USER' : 'AI';
          onLog?.call('🔊 [TTS-02]',
              '[$turnTag] API OK (${result.length}B) for "$text"');
          // [3단계] 캐시 저장 (백그라운드)
          TtsCache.put(text, voice, result);
          break;
        } else {
          onLog?.call('❌ [TTS-API-ERR]',
              'statusCode=${res.statusCode} (attempt=${attempt + 1}/3)');
        }
      } catch (e) {
        onLog?.call('⚠️ [TTS-RETRY]',
            'attempt=${attempt + 1}/3 실패 (${e.runtimeType}) for "$text"');
        if (attempt < 2) {
          await Future.delayed(const Duration(milliseconds: 300));
        }
      }
    }
    if (result.isEmpty) {
      onLog?.call('❌ [TTS-FAIL]', '3회 모두 실패 — 청크 스킵: "$text"');
    }
```

**주의사항:**
- old_str/new_str 직후의 `    _buffer[id] = result;` ~ `if (_pendingCount == 0) onAllComplete?.call();` 4줄은 **절대 포함하지도, 수정하지도 말 것** (pending 카운트 보장 로직).
- `result.isEmpty` 시 빈 데이터는 기존 `_pushReady()`의 `data.isNotEmpty` 가드가 자동으로 재생 스킵 처리하므로 추가 처리 불필요 — 순서 카운터(`_readyCounter`)는 정상 진행됨.
- 프롬프트/문자열 내 URL은 순수 텍스트 유지 (마크다운 링크 변환 금지).
- PowerShell로 파일을 직접 쓸 경우 `[IO.File]::WriteAllText` + UTF-8 명시 필수 (한글 주석 깨짐 방지).

---

## 5. 편집 후 검증 (파일별)

각 파일 편집 직후 아래 3개 grep 실행:

```bash
# (a) 새 블록 적용 확인 — 기대값 1
grep -c "5초 타임아웃, 최대 3회 시도" lib/custom_code/widgets/routine_mode_step_expand.dart

# (b) 구 블록 잔존 확인 — 기대값 0
grep -c "\[2단계\] API 호출 (재시도 1회)" lib/custom_code/widgets/routine_mode_step_expand.dart

# (c) TTS-RETRY 로그 추가 확인 — 기대값 1
grep -c "TTS-RETRY" lib/custom_code/widgets/routine_mode_step_expand.dart
```

(free_talk, roleplay, clone도 파일명만 바꿔 동일 실행)

**4개 파일 전부 완료 후 전체 분석:**

```bash
flutter analyze
```

에러 0건이어야 함. 에러 발생 시 즉시 중단하고 에러 전문 보고.

---

## 6. 기대 효과 및 실기기 검증 포인트

- 최악 공백: 기존 10.5초+ → 약 5.3~6초 (1차 재시도 성공 시).
- 스파이크 발생 시 로그에 `⚠️ [TTS-RETRY]`가 찍혀 향후 추적 가능해짐.
- 비용: 평상시 변화 없음. 스파이크 순간에만 타임아웃된 요청 + 재시도 요청이 중복 과금될 수 있으나 미미함.

**실기기 테스트 (Step Expand 기준):**
1. 5턴 대화 진행 → AI 질문이 "몇 단어 후 장시간 침묵" 없이 이어지는지 확인.
2. 로그에서 `[TTS-RETRY]` 발생 시 후속 `API OK`까지의 간격이 6초 이내인지 확인.
3. `[PIPE-TIMEOUT] 유저 TTS fetch 10초 초과` 발생 빈도가 줄었는지 확인.
4. 확장문장 반복 낭독(캐시 히트 경로)이 기존과 동일하게 즉시 재생되는지 확인.

---

## 7. 롤백 절차

```bash
# 커밋 전이면:
git restore lib/custom_code/widgets/routine_mode_step_expand.dart
git restore lib/custom_code/widgets/routine_mode_free_talk.dart
git restore lib/custom_code/widgets/routine_mode_roleplay.dart
git restore lib/custom_code/widgets/routine_mode_clone.dart

# 커밋 후라면:
git revert <패치 커밋 해시>
```