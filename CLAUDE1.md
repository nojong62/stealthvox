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

Phase 2 — routine_mode_clone.dart
절대 보존: Box 7(TtsQueueManager/DeepgramV2VoiceManager/ChunkedTtsFetcher), generateCleanOriginal, dispose()/_forceSaveToFirestore(AI 생성 넣지 말 것). _handleAutoSaveAndExit 한 곳과 CloneBrain에 메서드 2개만 추가.
2-1) CloneBrain에 static 메서드 2개 추가
class CloneBrain { (3664행) 여는 중괄호 바로 다음 줄에 삽입:
dart  // 🆕 [EXPAND-EXIT] 대화 전체(AI+유저) → 종합 확장 문장 1개 (의미단위 ~5개, 문법 연결)
  static Future<String?> generateExpandedFromConversation(
      String apiKey, String transcript) async {
    if (apiKey.isEmpty || transcript.trim().isEmpty) return null;
    try {
      const sysPrompt = """You are an English speaking coach.
You are given a short conversation transcript between the user and an AI partner.
Your job: compose ONE long, natural English sentence that synthesizes the overall
content and gist of the WHOLE conversation.

[RULES]
- It must be ONE single sentence (do not split it into multiple sentences).
- Build it from about 5 meaning units joined with varied grammatical connectives
  (because, so, while, which, after, even though, and, etc.).
- Natural, speakable rhythm (commas for breath are fine).
- Capture the overall situation/idea of the conversation, not just one line.
- Common everyday vocabulary only. Do not add facts not in the transcript.
- Output exactly ONE sentence. No quotes, no prefixes, no explanation.""";
      final response = await http
          .post(
            Uri.parse('https://api.openai.com/v1/chat/completions'),
            headers: {
              'Authorization': 'Bearer $apiKey',
              'Content-Type': 'application/json; charset=utf-8',
            },
            body: jsonEncode({
              'model': 'gpt-4o-mini',
              'temperature': 0.2,
              'max_tokens': 250,
              'messages': [
                {'role': 'system', 'content': sysPrompt},
                {
                  'role': 'user',
                  'content':
                      "Conversation:\n$transcript\n\nOne synthesized sentence:"
                },
              ],
            }),
          )
          .timeout(const Duration(seconds: 15));
      if (response.statusCode != 200) return null;
      final body =
          jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
      String s =
          ((body['choices'] as List).first['message']['content'] as String)
              .trim();
      if (s.startsWith('"') && s.endsWith('"')) s = s.substring(1, s.length - 1);
      return s.isEmpty ? null : s;
    } catch (e) {
      debugPrint("[CloneBrain.generateExpandedFromConversation] $e");
      return null;
    }
  }

  // 🆕 [EXPAND-EXIT] 확장 문장 → 쉽고 세련된 한 문장 (Polished)
  static Future<String?> polishSentence(
      String apiKey, String originalSentence) async {
    if (apiKey.isEmpty || originalSentence.trim().isEmpty) return null;
    try {
      const sysPrompt = """You are an English speaking coach.
Rewrite the given long English sentence as ONE "easy but elegant" spoken sentence.

[GOALS]
- Natural spoken rhythm (not written/academic)
- Common vocabulary (no SAT words, no bookish phrases)
- Smooth flow (pause-friendly, commas for breath)
- Same meaning as the original (do not add new facts)
- Easier to pronounce and say out loud

[OUTPUT]
- Exactly ONE sentence. No explanation, no quotes, no prefixes.""";
      final response = await http
          .post(
            Uri.parse('https://api.openai.com/v1/chat/completions'),
            headers: {
              'Authorization': 'Bearer $apiKey',
              'Content-Type': 'application/json; charset=utf-8',
            },
            body: jsonEncode({
              'model': 'gpt-4o-mini',
              'temperature': 0.2,
              'max_tokens': 150,
              'messages': [
                {'role': 'system', 'content': sysPrompt},
                {
                  'role': 'user',
                  'content':
                      'Original sentence:\n$originalSentence\n\nPolished version:'
                },
              ],
            }),
          )
          .timeout(const Duration(seconds: 15));
      if (response.statusCode != 200) return originalSentence;
      final body =
          jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
      String p =
          ((body['choices'] as List).first['message']['content'] as String)
              .trim();
      if (p.startsWith('"') && p.endsWith('"')) p = p.substring(1, p.length - 1);
      return p.isEmpty ? originalSentence : p;
    } catch (e) {
      debugPrint("[CloneBrain.polishSentence] $e");
      return originalSentence;
    }
  }
2-2) _handleAutoSaveAndExit() 전체 교체
메서드 전체를 아래로 교체 (기존 delete/마지막메시지 로직 유지 + else 분기에 오버레이·생성·저장 추가):
dart  Future<void> _handleAutoSaveAndExit() async {
    bool overlayShown = false;
    try {
      if (_myHistoryRef != null) {
        final hasUserTurn = _localMessages.any((m) => m['role'] == 'HOST');
        if (!hasUserTurn) {
          await _myHistoryRef!.delete();
          _log('🗑️ [HIST-DEL]', '빈 방 삭제 완료');
        } else {
          String lastText = "대화 기록 저장";
          for (int i = _localMessages.length - 1; i >= 0; i--) {
            final t = (_localMessages[i]['target'] ?? '').toString().trim();
            if (t.isNotEmpty && t != '...') {
              lastText = t;
              break;
            }
          }

          // 🆕 [EXPAND-EXIT] 전체 대화 종합 → Expanded + Polished 생성 (오버레이 표시)
          String expanded = "";
          String polished = "";
          final convoLines = _localMessages
              .where((m) {
                if (m['role'] != 'HOST' && m['role'] != 'SYSTEM') return false;
                final t = (m['target'] ?? '').toString().trim();
                return t.isNotEmpty && t != '...';
              })
              .map((m) => "${m['role'] == 'HOST' ? 'User' : 'AI'}: ${m['target']}")
              .toList();
          final transcript = convoLines.join("\n");

          if (transcript.isNotEmpty && _openAiKey.isNotEmpty && mounted) {
            showDialog(
              context: context,
              barrierDismissible: false,
              builder: (_) => const Center(
                child: Card(
                  color: Color(0xFF1E1E1E),
                  child: Padding(
                    padding: EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        CircularProgressIndicator(color: Colors.amber),
                        SizedBox(height: 16),
                        Text("확장 문장 만드는 중...",
                            style: TextStyle(color: Colors.white70)),
                      ],
                    ),
                  ),
                ),
              ),
            );
            overlayShown = true;

            final gen = await CloneBrain.generateExpandedFromConversation(
                _openAiKey, transcript);
            if (gen != null && gen.isNotEmpty) {
              expanded = gen;
              final pol = await CloneBrain.polishSentence(_openAiKey, expanded);
              polished = (pol != null && pol.trim().isNotEmpty) ? pol.trim() : "";
            }

            if (overlayShown && mounted &&
                Navigator.of(context, rootNavigator: true).canPop()) {
              Navigator.of(context, rootNavigator: true).pop();
            }
            overlayShown = false;
          }

          await _myHistoryRef!.update({
            'last_message': lastText,
            'last_message_time': FieldValue.serverTimestamp(),
            'msg_count': _localMessages.length,
            'last_active': FieldValue.serverTimestamp(),
            'mode': 'clone',
            if (expanded.isNotEmpty) 'expanded_sentence': expanded,
            if (polished.isNotEmpty) 'polished_sentence': polished,
            if (expanded.isNotEmpty) 'has_practice': true,
            if (expanded.isNotEmpty) 'expand_source': 'exit',
            if (expanded.isNotEmpty)
              'expand_generated_at': FieldValue.serverTimestamp(),
          });
          _log('💾 [HIST-UPD]',
              'last_message + expand 저장 (expanded=${expanded.isNotEmpty})');
        }
      }
    } catch (e) {
      _log('❌ [HIST-EXIT-ERR]', '$e');
    } finally {
      // 오버레이가 남아있으면 정리
      if (overlayShown &&
          mounted &&
          Navigator.of(context, rootNavigator: true).canPop()) {
        Navigator.of(context, rootNavigator: true).pop();
      }
      if (mounted) {
        if (StealthRoomMaster.exitCurrentMode != null) {
          StealthRoomMaster.exitCurrentMode!();
        } else if (Navigator.canPop(context)) {
          Navigator.pop(context);
        } else {
          context.goNamed('Lobby');
        }
      }
    }
  }
Phase 2 검증
bashflutter analyze
grep -c "CloneBrain.generateExpandedFromConversation" lib/**/routine_mode_clone.dart  # 2 (정의1+호출1)
grep -c "static Future<String?> polishSentence" lib/**/routine_mode_clone.dart        # 1
grep -c "'expand_source': 'exit'" lib/**/routine_mode_clone.dart                      # 1
grep -c "확장 문장 만드는 중" lib/**/routine_mode_clone.dart                          # 1