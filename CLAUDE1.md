StealthVox 프로젝트 가이드 (FlutterFlow)

 📂 파일 위치 및 위젯 리스트
 모든 화면(Pages): `lib/` 폴더 내 각 이름별 폴더
 커스텀 액션: `lib/custom_code/actions/`
 전역 상태: `lib/app_state.dart`

 🛠️ 커스텀 위젯 (`lib/custom_code/widgets/`)
현재 구현된 위젯 파일들 (새 작업 시 참고):

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

대상 파일: lib/.../routine_mode_clone.dart (4077줄 파일)
목표: Clone 생성 화면에 '추천 클론 생성' 버튼과 30개 가상 시나리오 자동 생성 기능 추가.
제약: Box 7 통신 엔진(DeepgramV2VoiceManager / TtsQueueManager / ChunkedTtsFetcher)은 절대 수정 금지.
      모든 URL은 순수 문자열로 유지(마크다운 링크 금지). 프롬프트 문자열은 삼중따옴표(''') 사용, 내부는 큰따옴표 위주로 이스케이프 에러 방지.

────────────────────────────────────────
[작업 1] 힌트 텍스트 교체 (line 927 부근)
아래 한 줄을 찾아서:
  hintText: "상대방과 이어서 말하고 싶은 카톡 대화를 PC에서 복사해서 붙여 넣기 합니다. - 대화 순서 그대로",
다음으로 교체:
  hintText: "상대방과 이어서 말하고 싶은 카톡 대화를 PC에서 복사해서 붙여 넣기 합니다. - 대화 순서 그대로\n\n추천 클론을 원할 경우 대화 시나리오 성격을 적으면 AI가 30개의 가상 시나리오를 적어 줍니다. 물론 내용 수정 가능합니다.",

────────────────────────────────────────
[작업 2] 버튼 영역 교체 (line 940 ~ 1037)
시작 줄: "SizedBox(" (line 940, child: _isCreatingClone 으로 시작하는 블록)
끝 줄  : 해당 SizedBox 를 닫는 "),"  (line 1037, 바로 아래가 "]," 인 지점)
→ 이 SizedBox(...) 블록 전체를 아래 코드로 통째로 교체:

                              SizedBox(
                                width: double.infinity,
                                child: _isCreatingClone
                                    ? const Center(
                                        child: Padding(
                                          padding: EdgeInsets.all(8),
                                          child: CircularProgressIndicator(
                                              color: Color(0xFF9333EA),
                                              strokeWidth: 2),
                                        ),
                                      )
                                    : Column(
                                        children: [
                                          // ── 기존: 카톡 붙여넣기 기반 클론 생성 ──
                                          ElevatedButton.icon(
                                            icon: const Icon(
                                                Icons.add_circle_outline,
                                                size: 18),
                                            label: const Text("Create Clone"),
                                            style: ElevatedButton.styleFrom(
                                              backgroundColor:
                                                  const Color(0xFF9333EA),
                                              foregroundColor: Colors.white,
                                              minimumSize: const Size(
                                                  double.infinity, 0),
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                      vertical: 13),
                                              shape: RoundedRectangleBorder(
                                                  borderRadius:
                                                      BorderRadius.circular(10)),
                                            ),
                                            onPressed: () async {
                                              final newName =
                                                  _cloneNameController.text
                                                      .trim();
                                              if (newName.isEmpty ||
                                                  _kakaoTextController
                                                      .text.isEmpty) return;
                                              final isDuplicate = _clones.any(
                                                (c) => (c['name'] as String)
                                                        .trim() ==
                                                    newName,
                                              );
                                              if (isDuplicate) {
                                                ScaffoldMessenger.of(ctx)
                                                    .showSnackBar(
                                                  SnackBar(
                                                    content: Text(
                                                        '⚠️ "$newName" 이름의 클론이 이미 존재합니다.'),
                                                    backgroundColor:
                                                        const Color(0xFFEF4444),
                                                    duration: const Duration(
                                                        seconds: 2),
                                                  ),
                                                );
                                                return;
                                              }
                                              setStateDialog(() =>
                                                  _isCreatingClone = true);
                                              String persona = await CloneBrain
                                                  .generatePersonaFromChat(
                                                apiKey: _openAiKey,
                                                chatLog:
                                                    _kakaoTextController.text,
                                                cloneName: newName,
                                              );
                                              persona = await CloneBrain
                                                  .confirmCloneIdentity(
                                                apiKey: _openAiKey,
                                                cloneName: newName,
                                                persona: persona,
                                              );
                                              final String newId =
                                                  await _createCloneInFirestore(
                                                name: newName,
                                                personality: persona,
                                                originalText:
                                                    _kakaoTextController.text,
                                              );
                                              setState(() {
                                                _clones.add({
                                                  'id': newId,
                                                  'name': newName,
                                                  'characteristics': persona,
                                                  'original_text':
                                                      _kakaoTextController.text,
                                                });
                                                _selectedCloneId = newId;
                                                _selectedCloneContext = persona;
                                                _cloneSummary = '';
                                                _recentHistory = [];
                                                _memoryTurnCount = 0;
                                                _localMessages.clear();
                                              });
                                              Navigator.pop(dialogContext);
                                              Future.delayed(
                                                  const Duration(seconds: 2),
                                                  () {
                                                if (mounted)
                                                  _generateAndPlayAiOpener();
                                              });
                                            },
                                          ),
                                          const SizedBox(height: 10),
                                          // ── 신규: 추천 클론 생성 (성격 설명 → 30개 시나리오 자동 생성 → 즉시 채팅) ──
                                          OutlinedButton.icon(
                                            icon: const Icon(
                                                Icons.auto_awesome,
                                                size: 18),
                                            label: const Text("추천 클론 생성"),
                                            style: OutlinedButton.styleFrom(
                                              foregroundColor:
                                                  const Color(0xFFD8B4FE),
                                              side: const BorderSide(
                                                  color: Color(0xFF9333EA),
                                                  width: 1.2),
                                              minimumSize: const Size(
                                                  double.infinity, 0),
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                      vertical: 13),
                                              shape: RoundedRectangleBorder(
                                                  borderRadius:
                                                      BorderRadius.circular(10)),
                                            ),
                                            onPressed: () async {
                                              final newName =
                                                  _cloneNameController.text
                                                      .trim();
                                              final scenarioHint =
                                                  _kakaoTextController.text
                                                      .trim();
                                              if (newName.isEmpty ||
                                                  scenarioHint.isEmpty) {
                                                ScaffoldMessenger.of(ctx)
                                                    .showSnackBar(
                                                  const SnackBar(
                                                    content: Text(
                                                        '클론 이름과 시나리오 성격을 입력해 주세요.'),
                                                    backgroundColor:
                                                        Color(0xFFEF4444),
                                                    duration:
                                                        Duration(seconds: 2),
                                                  ),
                                                );
                                                return;
                                              }
                                              final isDuplicate = _clones.any(
                                                (c) => (c['name'] as String)
                                                        .trim() ==
                                                    newName,
                                              );
                                              if (isDuplicate) {
                                                ScaffoldMessenger.of(ctx)
                                                    .showSnackBar(
                                                  SnackBar(
                                                    content: Text(
                                                        '⚠️ "$newName" 이름의 클론이 이미 존재합니다.'),
                                                    backgroundColor:
                                                        const Color(0xFFEF4444),
                                                    duration: const Duration(
                                                        seconds: 2),
                                                  ),
                                                );
                                                return;
                                              }
                                              setStateDialog(() =>
                                                  _isCreatingClone = true);
                                              // 1) 30개 가상 시나리오 생성
                                              final String scenarios =
                                                  await CloneBrain
                                                      .generateRecommendedScenarios(
                                                apiKey: _openAiKey,
                                                scenarioHint: scenarioHint,
                                                cloneName: newName,
                                              );
                                              // 2) 성격 설명 + 시나리오로 페르소나 추출
                                              String persona = await CloneBrain
                                                  .generatePersonaFromChat(
                                                apiKey: _openAiKey,
                                                chatLog:
                                                    '성격 설명:\n$scenarioHint\n\n연습 시나리오:\n$scenarios',
                                                cloneName: newName,
                                              );
                                              persona = await CloneBrain
                                                  .confirmCloneIdentity(
                                                apiKey: _openAiKey,
                                                cloneName: newName,
                                                persona: persona,
                                              );
                                              // 3) Firestore 저장 (original_text=30개 시나리오 → Edit에서 수정 가능)
                                              final String newId =
                                                  await _createCloneInFirestore(
                                                name: newName,
                                                personality: persona,
                                                originalText: scenarios,
                                              );
                                              setState(() {
                                                _clones.add({
                                                  'id': newId,
                                                  'name': newName,
                                                  'characteristics': persona,
                                                  'original_text': scenarios,
                                                });
                                                _selectedCloneId = newId;
                                                _selectedCloneContext = persona;
                                                _cloneSummary = '';
                                                _recentHistory = [];
                                                _memoryTurnCount = 0;
                                                _localMessages.clear();
                                              });
                                              Navigator.pop(dialogContext);
                                              Future.delayed(
                                                  const Duration(seconds: 2),
                                                  () {
                                                if (mounted)
                                                  _generateAndPlayAiOpener();
                                              });
                                            },
                                          ),
                                        ],
                                      ),
                              ),

────────────────────────────────────────
[작업 3] Brain 함수 추가 (CloneBrain 클래스 내부)
generatePersonaFromChat 메서드가 끝나는 지점(line 3986, "print('generatePersonaFromChat error: $e');" 이 포함된 메서드의 닫는 '}' 다음)과
클래스 닫는 '}'(line 3987) 사이에 아래 static 메서드를 추가:

  // ==================================================================
  // 📦 [Box 7-1-F] generateRecommendedScenarios — 추천 클론용 30개 가상 시나리오
  // ------------------------------------------------------------------
  // 유저가 적은 "대화 시나리오 성격" + 클론 이름 → 30개 짧은 가상 대화 상황 생성.
  // 결과는 original_text 로 저장되며 generatePersonaFromChat 의 입력으로도 재사용됨.
  // ==================================================================
  static Future<String> generateRecommendedScenarios({
    required String apiKey,
    required String scenarioHint,
    String cloneName = '',
  }) async {
    final client = http.Client();
    try {
      final nameLine = cloneName.isNotEmpty
          ? 'The clone character is named "$cloneName".'
          : '';
      final sysPrompt = '''You are a creative scenario writer for a Korean language-learning roleplay app.
$nameLine
The user gives a short description of the character and the conversation style they want.
Generate EXACTLY 30 short, varied, realistic everyday conversation scenarios in which the user could practice talking with this character.

Rules:
- Write in Korean.
- Number each line from 1 to 30.
- One scenario per line, concise (about 30 Korean characters or fewer each).
- Keep them varied: daily life, emotions, plans, small talk, light conflict, fun topics.
- Make them feel natural for the described character and relationship.
- Output ONLY the numbered list. No title, no preamble, no closing remarks.''';

      final res = await client
          .post(
            Uri.parse('https://api.openai.com/v1/chat/completions'),
            headers: {
              'Authorization': 'Bearer $apiKey',
              'Content-Type': 'application/json; charset=utf-8',
            },
            body: jsonEncode({
              'model': 'gpt-4o-mini',
              'temperature': 0.7,
              'max_tokens': 1500,
              'messages': [
                {'role': 'system', 'content': sysPrompt},
                {
                  'role': 'user',
                  'content': 'Character and conversation style:\n\n$scenarioHint',
                },
              ],
            }),
          )
          .timeout(const Duration(seconds: 40));

      if (res.statusCode == 200) {
        final data = jsonDecode(utf8.decode(res.bodyBytes));
        final out =
            data['choices'][0]['message']['content'].toString().trim();
        if (out.isNotEmpty) return out;
      }
    } catch (e) {
      print('generateRecommendedScenarios error: $e');
    } finally {
      client.close();
    }

    // 실패 시 폴백: 클론 생성이 막히지 않도록 최소 시나리오 제공
    return '''1. 오늘 하루 어땠는지 가볍게 묻기
2. 주말 계획 이야기하기
3. 좋아하는 음식 추천받기
4. 최근에 본 영화나 드라마 이야기
5. 스트레스 푸는 방법 나누기
6. 요즘 빠져 있는 취미 소개하기
7. 가고 싶은 여행지 이야기
8. 점심 메뉴 같이 정하기
9. 어제 있었던 웃긴 일 공유하기
10. 듣고 있는 음악 추천하기''';
  }

────────────────────────────────────────
[검증]
1. dart analyze 로 에러 0 확인 (특히 괄호/콤마 매칭).
2. grep -n "generateRecommendedScenarios" 로 함수 1개(정의) + 호출 1개 확인.
3. grep -n "추천 클론 생성" 로 버튼 라벨 1개 확인.
4. grep -n "DeepgramV2VoiceManager\|TtsQueueManager\|ChunkedTtsFetcher" 결과가 작업 전후 동일한지(미변경) 확인.
5. "Create Clone" 버튼과 onPressed 로직이 그대로 보존됐는지 확인.