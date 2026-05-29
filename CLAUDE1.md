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

routine_mode_step_expand.dart 의 첫 질문(_startSessionWithAiQuestion) 처리와 씨앗 조회를 수정합니다.

[해결할 문제]
1. 첫 질문에서 한국어가 두 번 나옴 (PART1/PART2 분리 안 됨 + generateCleanOriginal 중복)
2. 첫 질문 TTS가 한국어(PART2)까지 읽음 → 영어(PART1)만 읽어야 함
3. clone 발화가 씨앗으로 오면 화자(주어)가 꼬임 → step_expand 발화만 씨앗 사용

[절대 건드리지 말 것]
- 일반 턴(turn 1~4) 처리 로직, 최종 합성, 5턴 구조
- seedSysPrompt / newcomerSysPrompt 텍스트 (PART1 영어 + PART2 한국어 출력 유지)
- Box 7 엔진 (DeepgramV2VoiceManager, TtsQueueManager, ChunkedTtsFetcher)
- 뉴스 소재 폴백 로직

──────────────────────────────────────────────
[수정 1+2] 첫 질문 스트림 처리: PART1/PART2 분리 + 영어만 TTS + 한국어 중복 제거
──────────────────────────────────────────────

_startSessionWithAiQuestion() 안에서, aiStream을 await for로 받아 처리하는 블록 전체
(아래 "기존" 범위)를 교체합니다.

기존 (대략 line 445~476, "String aiText = '';" 부터
  generateCleanOriginal 호출까지 — 아래 내용과 일치하는 구간):

    String aiText = '';
    String buffer = '';
    final RegExp sp = RegExp(r'[,\.?!;:。、！？…，；：\n]');

    await for (final chunk in aiStream) {
      if (!mounted || !_isConversationActive) break;
      aiText += chunk;
      buffer += chunk;
      if (mounted && aiIdx < _localMessages.length) {
        setState(() => _localMessages[aiIdx]['target'] = aiText);
      }
      _scrollToBottom();
      final matches = sp.allMatches(buffer).toList();
      if (matches.isNotEmpty) {
        final lastIdx = matches.last.end;
        final toSpeak = buffer.substring(0, lastIdx).trim();
        buffer = buffer.substring(lastIdx);
        if (toSpeak.isNotEmpty) tts.addText(toSpeak);
      }
    }
    if (buffer.trim().isNotEmpty) tts.addText(buffer.trim());

    // 🌱 스트리밍 완료 즉시 번역 시작 — TTS 재생과 병렬로 실행
    StepExpandBrain.generateCleanOriginal(
            apiKey: _openAiKey, englishText: aiText)
        .then((kor) {
      if (mounted && _localMessages.length > aiIdx) {
        setState(() => _localMessages[aiIdx]['original'] = kor);
      }
    });

교체:

    // 🌱 [v3.9] 첫 질문도 "PART1(영어)\n\n PART2(한국어)" 구조로 출력됨.
    //   - 화면 target = PART1(영어), original = PART2(한국어)
    //   - TTS는 PART1(영어)만 재생. PART2(한국어)는 소리 안 냄.
    //   - PART2가 한국어 자막을 채우므로 generateCleanOriginal 중복 호출 제거.
    String aiText = '';          // 전체 누적(영어+\n\n+한국어)
    String buffer = '';          // TTS 송출용 버퍼 (PART1 영어 구간만)
    bool part2Started = false;   // \n\n 이후(한국어) 진입 여부
    final RegExp sp = RegExp(r'[,\.?!;:。、！？…，；：\n]');

    await for (final chunk in aiStream) {
      if (!mounted || !_isConversationActive) break;
      aiText += chunk;

      // 화면 표시: \n\n 기준으로 PART1→target, PART2→original 분리
      if (aiText.contains('\n\n')) {
        final idx = aiText.indexOf('\n\n');
        final part1 = aiText.substring(0, idx).trim();
        final part2 = aiText.substring(idx + 2).trim();
        if (mounted && aiIdx < _localMessages.length) {
          setState(() {
            _localMessages[aiIdx]['target'] = part1;
            _localMessages[aiIdx]['original'] = part2;
          });
        }
      } else {
        if (mounted && aiIdx < _localMessages.length) {
          setState(() => _localMessages[aiIdx]['target'] = aiText);
        }
      }
      _scrollToBottom();

      // TTS: PART1(영어)만 송출. \n\n 감지되면 그 이후(한국어)는 TTS 큐에 안 보냄.
      if (!part2Started) {
        if (aiText.contains('\n\n')) {
          // \n\n 이전(영어)까지 남은 buffer를 마저 송출하고 종료
          final idx = aiText.indexOf('\n\n');
          final part1Full = aiText.substring(0, idx);
          final remain = part1Full.length > (aiText.length - chunk.length)
              ? '' // 안전장치
              : '';
          // buffer에 아직 안 보낸 PART1 잔여분 송출
          final pending = buffer.trim();
          if (pending.isNotEmpty) tts.addText(pending);
          buffer = '';
          part2Started = true;
          continue;
        }
        buffer += chunk;
        final matches = sp.allMatches(buffer).toList();
        if (matches.isNotEmpty) {
          final lastIdx = matches.last.end;
          final toSpeak = buffer.substring(0, lastIdx).trim();
          buffer = buffer.substring(lastIdx);
          if (toSpeak.isNotEmpty) tts.addText(toSpeak);
        }
      }
      // part2Started == true 이후의 chunk(한국어)는 TTS로 보내지 않음 (화면 자막만)
    }

    // 루프 종료 후, \n\n 가 아예 없었던 경우(=PART2 미출력) buffer 잔여분 송출
    if (!part2Started && buffer.trim().isNotEmpty) {
      tts.addText(buffer.trim());
    }

    // ⚠️ generateCleanOriginal 호출 제거:
    //   PART2(한국어)가 이미 original 자막을 채우므로 중복 번역 불필요.
    //   만약 \n\n 가 없어 original 이 비어있는 폴백 상황이면, 그때만 번역 보강:
    if (mounted &&
        aiIdx < _localMessages.length &&
        ((_localMessages[aiIdx]['original'] ?? '').toString().trim().isEmpty)) {
      StepExpandBrain.generateCleanOriginal(
              apiKey: _openAiKey, englishText: aiText)
          .then((kor) {
        if (mounted && _localMessages.length > aiIdx) {
          setState(() => _localMessages[aiIdx]['original'] = kor);
        }
      });
    }

⚠️ 구현 노트: 위 교체 블록에서 'remain' 변수는 불필요하면 제거해도 됨(안전장치 흔적).
   핵심은 (a) \n\n로 PART1/PART2를 화면 분리, (b) part2Started 이후 chunk는 tts.addText 호출 안 함,
   (c) original 이 PART2로 채워지면 generateCleanOriginal 안 부름.
   dart analyze 에서 미사용 변수 경고가 나면 remain/part1Full 등 정리할 것.

──────────────────────────────────────────────
[수정 3] 씨앗 소스를 step_expand 발화로만 한정 (clone 제외)
──────────────────────────────────────────────

_fetchRandomPastUserLine() 안의 _isSeedSourceRoom 판정 함수를 수정합니다.
clone을 씨앗 소스에서 제외 — clone의 HOST 발화는 "유저가 클론 캐릭터에게 건넨 말"이라
회상형 질문("지난번에 네가 ~라고 했지")에서 주어가 꼬이기 때문.

기존:
      bool _isSeedSourceRoom(Map<String, dynamic> data) {
        final String mode = (data['mode'] ?? '').toString();
        final String roomName = (data['room_name'] ?? '').toString();
        // A 경로: mode 필드가 박힌 새 방
        if (mode == 'step_expand' || mode == 'clone') return true;
        // B 경로: mode 없는 기존 방 → room_name으로 판정
        if (roomName.contains('Step.Ex') || roomName.contains('Clone')) {
          return true;
        }
        return false;
      }

교체 (step_expand만 허용):
      bool _isSeedSourceRoom(Map<String, dynamic> data) {
        final String mode = (data['mode'] ?? '').toString();
        final String roomName = (data['room_name'] ?? '').toString();
        // step_expand 발화만 씨앗으로 사용 (유저 본인의 확장 문장이라 회상이 자연스러움).
        // clone/roleplay/duo 는 화자·맥락이 복잡해 제외.
        // A 경로: mode 필드가 박힌 새 방
        if (mode == 'step_expand') return true;
        // B 경로: mode 없는 기존 방 → room_name 으로 판정
        if (roomName.contains('Step.Ex')) return true;
        return false;
      }

[검증]
1. dart analyze → 에러 0, 미사용 변수 경고 정리
2. grep -c "part2Started" → 최소 3 (선언 + \n\n 분기 + 잔여 송출 가드)
3. grep -c "generateCleanOriginal" 첫 질문부 주변 → 폴백 1회만 남았는지 확인
   (전체 파일에서는 일반 턴용 호출이 따로 있을 수 있으니, _startSessionWithAiQuestion 함수 범위 내에서 1회)
4. grep -c "mode == 'clone'" → 0 (씨앗 조회에서 clone 제거 확인)
5. grep -c "roomName.contains('Clone')" → 0
6. grep -c "mode == 'step_expand'" → 최소 1 (씨앗 조회 step_expand 허용 유지)
7. 런타임 테스트:
   (a) 첫 질문 화면: 영어(큰 글씨) + 한국어(작은 글씨) 각 1회씩, 한국어 중복 없음
   (b) 첫 질문 소리: 영어만 재생, 한국어 안 읽음
   (c) 씨앗: step_expand 과거 발화에서만 옴 (clone 발화 안 옴)
8. Box 7 클래스 diff 변경 0 확인