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

# [KO-FRAG] 의미단위 읽기 — 청크별 한국어 직독 조각 부착

## 0. 목적 (한 줄)
`chat_history_master.dart`의 청크 연습 엔진(`_chunks` / `PracticeChunk`)에서, 영어 의미단위 청크 **밑에** 영어어순 한국어 직독 조각("…라고 생각해서", "…이니까")을 1:1로 달아 표시한다. `_langDisplayMode`(0=영+한, 2=한)에서만 보이고 1(영어만)에서는 숨긴다.

## 1. 대상 파일 (단 하나)
`F:\flutter_project\stealth_vox\lib\...\chat_history_master.dart`
(이 작업은 이 파일 **한 곳만** 수정한다. 다른 파일·다른 모드 파일은 절대 건드리지 않는다.)

## 2. 절대 건드리지 말 것 (CRITICAL — 손대면 롤백)
- **Box 7 통신 엔진** 전체: `DeepgramV2VoiceManager`, `TtsQueueManager`, `ChunkedTtsFetcher`, TTS/STT 내부 로직.
- **기존 영어 청크 분할·캐시**: `_splitSentenceIntoChunks`, `_splitByBreathGroupsGpt`, `_buildChunksLegacyList`, `_postProcessChunks`, `_readChunkCache`, `_writeChunkCache`, `_chunkTextHash`. → 이 작업은 **영어 청크 경로를 일절 변경하지 않는다.** 한국어는 별도 평행 레이어로만 추가한다.
- 방 나가기 / Firestore 저장 로직 (`_handleAutoSaveAndExit` 류) → 변경 없음.
- 과금/타이머/녹음(`BillingTicker`, idle timeout, `_audioRecorder`) → 변경 없음.

## 3. 설계 요약
- `PracticeChunk`에 `String? korean` 필드 **추가**(기존 필드 유지).
- 신규 GPT 메서드 1개(`_generateKoFragmentsGpt`) + 신규 디스크 캐시 2개(`_readKoFragCache` / `_writeKoFragCache`). **영어 청크 캐시와 파일명 분리**(`kofrag_v1_...`).
- `_buildChunks`에서 영어 청크 생성 직후, 캐시→GPT로 한국어 조각을 받아 청크에 1:1로 zip. **실패/개수 불일치 시 한국어 없이 영어만 정상 표시.**
- 렌더 헬퍼 `_buildChunkKoLine` 1개 추가 → 청크 텍스트 3개 렌더 사이트에 한 줄씩 삽입.

---

## 4. 변경 작업 (위→아래 순서대로 적용)

### [4-1] PracticeChunk 클래스 — `korean` 필드 추가
**위치 anchor:** `class PracticeChunk {` (파일 끝부분, 사전 기준 약 6253행)
아래 블록을 **통째로 교체**:

#### BEFORE
```dart
class PracticeChunk {
  final String text;
  Uint8List? aiAudio;
  String? userRecordPath;
  bool isDone;

  PracticeChunk({
    required this.text,
    this.aiAudio,
    this.userRecordPath,
    this.isDone = false,
  });
}
```

#### AFTER
```dart
class PracticeChunk {
  final String text;
  final String? korean; // 🆕 [KO-FRAG] 영어어순 직독 한국어 조각 (없으면 null)
  Uint8List? aiAudio;
  String? userRecordPath;
  bool isDone;

  PracticeChunk({
    required this.text,
    this.korean,
    this.aiAudio,
    this.userRecordPath,
    this.isDone = false,
  });
}
```

---

### [4-2] 신규 메서드 3개 삽입 (GPT + 캐시 read/write)
**위치:** `_writeChunkCache(...)` 메서드의 닫는 `}` **바로 다음 줄**, 그리고 `Future<void> _buildChunks(String sentence)` **바로 위**(사전 기준 약 1423행, `_ChatHistoryMasterState` 클래스 내부).
아래 3개 메서드를 **그 자리에 그대로 추가**(기존 코드 삭제 없음):

```dart
  // 🆕 [KO-FRAG] 영어 청크 리스트 → 영어어순 직독 한국어 조각 (개수·순서 1:1)
  Future<List<String>?> _generateKoFragmentsGpt(List<String> enChunks) async {
    if (_apiKey.isEmpty || enChunks.isEmpty) return null;
    try {
      const sysPrompt = """You are a Korean sight-translation (jikdokjikhae) helper.
You receive an English sentence already split into ordered chunks as a JSON array.
For EACH chunk, output ONE short Korean reading fragment that follows the English word order.
These are intentionally incomplete connecting fragments, NOT a polished full translation.

[RULES]
- Output ONLY a JSON array of Korean strings. No markdown, no extra text, no code fences.
- The array length MUST equal the number of input chunks, in the same order.
- Each fragment expresses ONLY that chunk, in English order. Do not reorder across chunks.
- Use natural Korean connective endings that fit each chunk role
  (reason: ~이니까/~여서, thinking: ~라고 생각해서, time: ~할 때, contrast: ~지만, purpose: ~하려고).
- Apply correct particles (이/가, 은/는, 을/를, 한테/에게). Use honorific ~시 only if present in English.
- Keep each fragment short, one breath. Do not add information not in the chunk.
- Korean only inside the strings.

Example input: ["I think","that the price","went up","because of the weather"]
Example output: ["나는 생각해","그 가격이","올랐다고","날씨 때문에"]""";
      final response = await http
          .post(
            Uri.parse("https://api.openai.com/v1/chat/completions"),
            headers: {
              "Authorization": "Bearer $_apiKey",
              "Content-Type": "application/json",
            },
            body: jsonEncode({
              "model": "gpt-4o-mini",
              "messages": [
                {"role": "system", "content": sysPrompt},
                {"role": "user", "content": jsonEncode(enChunks)},
              ],
              "temperature": 0.2,
              "max_tokens": 600,
            }),
          )
          .timeout(const Duration(seconds: 15));
      if (response.statusCode != 200) return null;
      final body =
          jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
      final content =
          ((body["choices"] as List).first["message"]["content"] as String)
              .trim();
      final jsonMatch = RegExp(r'\[[\s\S]*\]').firstMatch(content);
      if (jsonMatch == null) return null;
      final list = jsonDecode(jsonMatch.group(0)!) as List;
      final ko = list.map((e) => e.toString().trim()).toList();
      if (ko.length != enChunks.length) {
        _debugLogs +=
            "⚠️ [KO-FRAG] 개수 불일치 en=${enChunks.length} ko=${ko.length} → 스킵\n";
        return null;
      }
      _debugLogs += "✅ [KO-FRAG] 조각 생성 완료 n=${ko.length}\n";
      return ko;
    } catch (e) {
      debugPrint("[generateKoFragmentsGpt] $e");
      return null;
    }
  }

  // 🆕 [KO-FRAG] 디스크 캐시 읽기 (영어 청크 캐시와 파일명 분리: kofrag_v1)
  Future<List<String>?> _readKoFragCache(String variant, String sentence) async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final roomId = widget.historyDoc.id;
      final hash = _chunkTextHash(sentence);
      final file = File(
          '${dir.path}/chunk_cache/kofrag_v1_${roomId}_${variant}_$hash.json');
      if (!await file.exists()) return null;
      final list = jsonDecode(await file.readAsString()) as List;
      return list.map((e) => e.toString()).toList();
    } catch (e) {
      debugPrint("[readKoFragCache] $e");
      return null;
    }
  }

  // 🆕 [KO-FRAG] 디스크 캐시 쓰기
  Future<void> _writeKoFragCache(
      String variant, String sentence, List<String> ko) async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final roomId = widget.historyDoc.id;
      final hash = _chunkTextHash(sentence);
      final folder = Directory('${dir.path}/chunk_cache');
      if (!await folder.exists()) await folder.create(recursive: true);
      final file = File(
          '${folder.path}/kofrag_v1_${roomId}_${variant}_$hash.json');
      await file.writeAsString(jsonEncode(ko));
    } catch (e) {
      debugPrint("[writeKoFragCache] $e");
    }
  }
```

---

### [4-3] `_buildChunks` — 한국어 조각 zip (전체 교체)
**위치 anchor:** `Future<void> _buildChunks(String sentence) async {` (사전 기준 약 1424행)
아래 블록을 **통째로 교체**:

#### BEFORE
```dart
  Future<void> _buildChunks(String sentence) async {
    if (sentence.isEmpty) {
      _chunks = [];
      _currentChunkIdx = 0;
      return;
    }
    final isPolished =
        _polishedSentence.isNotEmpty && sentence == _polishedSentence;
    final variant = isPolished ? 'polished' : 'expanded';
    final result = await _splitSentenceIntoChunks(sentence, variant);
    _chunks = result.map((t) => PracticeChunk(text: t)).toList();
    _currentChunkIdx = 0;
  }
```

#### AFTER
```dart
  Future<void> _buildChunks(String sentence) async {
    if (sentence.isEmpty) {
      _chunks = [];
      _currentChunkIdx = 0;
      return;
    }
    final isPolished =
        _polishedSentence.isNotEmpty && sentence == _polishedSentence;
    final variant = isPolished ? 'polished' : 'expanded';
    final result = await _splitSentenceIntoChunks(sentence, variant);

    // 🆕 [KO-FRAG] 영어 청크에 1:1 한국어 직독 조각 부착 (캐시 → GPT).
    //   실패/개수 불일치 시 ko=null → 영어 청크만 정상 표시 (영어 경로 영향 0).
    List<String>? ko = await _readKoFragCache(variant, sentence);
    if (ko == null || ko.length != result.length) {
      ko = await _generateKoFragmentsGpt(result);
      if (ko != null && ko.length == result.length) {
        await _writeKoFragCache(variant, sentence, ko);
      } else {
        ko = null;
      }
    }

    _chunks = List.generate(
      result.length,
      (i) => PracticeChunk(
        text: result[i],
        korean: (ko != null && i < ko.length) ? ko[i] : null,
      ),
    );
    _currentChunkIdx = 0;
  }
```

---

### [4-4] 렌더 헬퍼 `_buildChunkKoLine` 추가
**위치:** `_ChatHistoryMasterState` 클래스 내부 아무 곳(권장: `Widget _buildChunkPracticeScreen() {` 바로 위, 사전 기준 약 5141행).
아래 메서드를 **그대로 추가**:

```dart
  // 🆕 [KO-FRAG] 청크 한국어 직독 조각 한 줄 — _langDisplayMode 0(영+한)·2(한)에서만 표시
  Widget _buildChunkKoLine(PracticeChunk chunk) {
    if (_langDisplayMode == 1) return const SizedBox.shrink();
    final ko = chunk.korean;
    if (ko == null || ko.trim().isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 3),
      child: Text(
        ko,
        style: TextStyle(
          color: Colors.white54,
          fontSize: 12 * _fontScale,
          height: 1.3,
        ),
      ),
    );
  }
```

---

### [4-5] 렌더 사이트 삽입 ① — `_buildChunkPracticeScreen` (메인 읽기 화면, 약 5461행)
영어 청크 `Text` 바로 밑에 한 줄 삽입.

#### BEFORE
```dart
                                            Text(
                                              chunk.text,
                                              style: TextStyle(
                                                color: textColor,
                                                fontSize: 16 * _fontScale,
                                                fontWeight: isCurrent
                                                    ? FontWeight.bold
                                                    : FontWeight.normal,
                                                height: 1.45,
                                              ),
                                            ),
                                            if (isCurrent &&
                                                _aiChunkLoading) ...[
```

#### AFTER
```dart
                                            Text(
                                              chunk.text,
                                              style: TextStyle(
                                                color: textColor,
                                                fontSize: 16 * _fontScale,
                                                fontWeight: isCurrent
                                                    ? FontWeight.bold
                                                    : FontWeight.normal,
                                                height: 1.45,
                                              ),
                                            ),
                                            _buildChunkKoLine(chunk), // 🆕 [KO-FRAG]
                                            if (isCurrent &&
                                                _aiChunkLoading) ...[
```

---

### [4-6] 렌더 사이트 삽입 ② — `_buildShadowingPracticeBody` (약 3710행)

#### BEFORE
```dart
                    Text(
                      chunk.text,
                      style: TextStyle(
                        color: _chunkTextColor(i), // 🆕 [P2-INDICATOR]
                        fontSize: 18 * _fontScale,
                        fontWeight:
                            isCurrent ? FontWeight.bold : FontWeight.normal,
                        height: 1.5,
                      ),
                    ),
                    if (isCurrent) ...[
```

#### AFTER
```dart
                    Text(
                      chunk.text,
                      style: TextStyle(
                        color: _chunkTextColor(i), // 🆕 [P2-INDICATOR]
                        fontSize: 18 * _fontScale,
                        fontWeight:
                            isCurrent ? FontWeight.bold : FontWeight.normal,
                        height: 1.5,
                      ),
                    ),
                    _buildChunkKoLine(chunk), // 🆕 [KO-FRAG]
                    if (isCurrent) ...[
```

---

### [4-7] 렌더 사이트 삽입 ③ — `_buildReviewScreen` (완료 후 리뷰 리스트, 약 3859행)
여긴 `Row` 안 `Expanded(child: Text(...))` 구조라 **`Column`으로 감싸서** 한국어를 밑에 붙인다.

#### BEFORE
```dart
                    Expanded(
                      child: Text(
                        chunk.text,
                        style: TextStyle(
                            color: Colors.white,
                            fontSize: 14 * _fontScale,
                            height: 1.4),
                      ),
                    ),
```

#### AFTER
```dart
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            chunk.text,
                            style: TextStyle(
                                color: Colors.white,
                                fontSize: 14 * _fontScale,
                                height: 1.4),
                          ),
                          _buildChunkKoLine(chunk), // 🆕 [KO-FRAG]
                        ],
                      ),
                    ),
```

---

## 5. 검증 체크리스트 (반드시 전부 통과 후 보고)
1. `flutter analyze` → **에러 0** (warning 도 신규로 늘지 않을 것).
2. grep 확인:
   - `grep -n "korean" chat_history_master.dart` → `PracticeChunk` 필드 + `_buildChunks` 사용 확인.
   - `grep -nc "_buildChunkKoLine(chunk)" chat_history_master.dart` → **3** (렌더 3곳).
   - `grep -nc "_buildChunkKoLine(PracticeChunk" chat_history_master.dart` → **1** (헬퍼 정의).
   - `grep -nc "_generateKoFragmentsGpt" chat_history_master.dart` → **2** (정의 1 + 호출 1).
   - `grep -nc "kofrag_v1_" chat_history_master.dart` → **2** (read/write 캐시).
3. 영어 청크 경로 무변경 확인: `grep -nc "_splitByBreathGroupsGpt\|_readChunkCache\|_writeChunkCache" chat_history_master.dart` 의 정의 라인들이 **수정되지 않았는지** 육안 확인(시그니처·본문 동일).
4. 완료 보고는 표로: [항목 | 적용행 | 통과여부].

## 6. 런타임 기대 동작
- 히스토리 방 → 연습 진입(확장/세련) → 청크 화면에서 각 영어 청크 밑에 회색 작은 한국어 조각 표시.
- `_langDisplayMode` 토글: 0(영+한)·2(한) → 보임 / 1(영어만) → 숨김.
- 첫 진입 시 GPT 1회(~1초), 이후 같은 문장은 `kofrag_v1` 캐시 히트 → 호출 0.
- GPT 실패/개수 불일치 → 한국어 줄 없이 영어 청크만(에러 없이) 표시.

## 7. 롤백 노트
- 모든 변경에 `🆕 [KO-FRAG]` 주석. 문제 시:
  - 렌더 3줄(`_buildChunkKoLine(chunk),`) 제거 + 4-7의 `Column` 래핑 원복.
  - 4-2/4-4 신규 메서드 4개 삭제.
  - 4-1 `korean` 필드 / 4-3 `_buildChunks` zip 블록 원복.
- 디스크 `kofrag_v1_*.json` 파일은 남아도 무해(다음 빌드에서 안 읽힘).