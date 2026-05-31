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

[Duo PTT 전환] 자동 연속 녹음 → 누르고 말하는 무전기(Push-To-Talk) 방식으로 전면 개편

파일: lib/custom_code/widgets/routine_mode_duo.dart

## 문제
현재 Duo는 _startWhisperRecording()을 11곳에서 자동 재호출하여 마이크가 계속 열려 있다.
이 때문에 내 TTS 재생음·상대 폰 스피커 소리·주변 소음이 다시 STT로 들어가
에코/환각 문장이 끝없이 생성된다(예: "carriage", "Honey, is it expensive and painful?").
근본 해결: 자동 재시작을 전부 끊고, 사용자가 버튼을 누르는 동안만 녹음하는 PTT로 전환.

## 설계 원칙
- 녹음 시작은 사용자가 직접(버튼 누름). 종료/차단은 앱이 자동.
- _isConversationActive(세션 ON/OFF)와 "녹음 가능 상태"를 분리.
- 새 상태기계 _duoState: idle / recording / processing / playing / cooldown.
- TTS·상대 메시지 처리·쿨다운 중에는 버튼을 눌러도 녹음 시작 안 됨.

────────────────────────────────────────────────────────
## 수정 1: 상태 변수 추가
위치: 상태 변수 선언부 (약 56줄 "bool _isConversationActive = false;" 아래)
추가:
```dart
  // 🆕 [PTT] Duo 무전기 상태기계
  // idle: 대기 / recording: 녹음 중 / processing: STT·번역 중 / playing: TTS 재생 중 / cooldown: 재생 후 짧은 잠금
  String _duoState = 'idle';
  // 🆕 [PTT 에코 차단] 최근 앱이 생성/표시한 문장 보관 (target/original 혼합, 최대 5개)
  final List<String> _recentGenerated = [];
  void _rememberGenerated(String s) {
    final t = s.trim().toLowerCase();
    if (t.isEmpty) return;
    _recentGenerated.add(t);
    while (_recentGenerated.length > 5) _recentGenerated.removeAt(0);
  }
  bool _looksLikeEcho(String transcript) {
    final t = transcript.trim().toLowerCase();
    if (t.length < 4) return false;
    for (final g in _recentGenerated) {
      if (g.isEmpty) continue;
      if (g == t || g.contains(t) || t.contains(g)) return true;
    }
    return false;
  }
  void _setDuoState(String s) {
    if (!mounted) return;
    setState(() => _duoState = s);
  }
```

────────────────────────────────────────────────────────
## 수정 2: _startWhisperRecording() — PTT 진입 가드 + 무음 자동재시작 제거
위치: 약 265~305줄 (함수 전체 교체)
변경점:
- 진입부에 PTT 방어 조건 추가 (idle일 때만 시작, TTS·처리·녹음 중이면 무시).
- 무음 50회 도달 시 "stop 후 _startWhisperRecording() 재호출"하던 부분 제거 → 그냥 종료.
- 녹음 시작 성공 시 _duoState='recording'.
교체 코드:
```dart
  Future<void> _startWhisperRecording() async {
    if (_openAiKey.isEmpty) return;
    // 🆕 [PTT] idle 상태가 아니면 시작 금지 (TTS·처리·쿨다운·이미 녹음 중 차단)
    if (_duoState != 'idle') return;
    if (_isTtsActive || _isDrainingIncoming) return;
    if (await _audioRecorder.isRecording()) return;
    if (await _audioRecorder.hasPermission()) {
      _hasSpoken = false;
      _silenceCounter = 0;
      try {
        final dir = await getTemporaryDirectory();
        final path =
            '${dir.path}/whisper_stt_${DateTime.now().millisecondsSinceEpoch}.m4a';
        await _audioRecorder.start(
            const RecordConfig(
                encoder: AudioEncoder.aacLc, sampleRate: 16000, numChannels: 1),
            path: path);
        _setDuoState('recording');
        _silenceTimer?.cancel();
        // 침묵 자동 종료만 유지(누른 채로 말 끝나면 자동 전송). 자동 "재시작"은 제거.
        _silenceTimer =
            Timer.periodic(const Duration(milliseconds: 100), (timer) async {
          if (await _audioRecorder.isRecording()) {
            final amp = await _audioRecorder.getAmplitude();
            if (amp.current > -25.0) {
              _hasSpoken = true;
              _silenceCounter = 0;
            } else {
              _silenceCounter++;
              if (_hasSpoken && _silenceCounter >= 15) {
                timer.cancel();
                _stopAndSendToWhisper();
              } else if (!_hasSpoken && _silenceCounter >= 80) {
                // 말이 한 번도 없으면 그냥 종료(재시작 안 함)
                timer.cancel();
                await _audioRecorder.stop();
                _setDuoState('idle');
              }
            }
          } else {
            timer.cancel();
          }
        });
      } catch (e) {
        _setDuoState('idle');
      }
    }
  }
```

────────────────────────────────────────────────────────
## 수정 3: _stopAndSendToWhisper() — 자동 재녹음 전부 제거 + 에코 차단 + 상태전이
위치: 약 312~399줄 (함수 전체 교체)
변경점:
- 함수 진입 시 _setDuoState('processing').
- 모든 실패/빈결과/타임아웃/환각/에코 → _startWhisperRecording() 호출하지 말고 _setDuoState('idle').
- 정상 transcript는 _processRelayPipeline로 넘김(거기서 상태 처리).
- 환각 필터는 기존 hardGhosts/shortGhosts 유지하고, _looksLikeEcho() 검사 추가.
교체 코드:
```dart
  Future<void> _stopAndSendToWhisper() async {
    _silenceTimer?.cancel();
    _resetIdleTimer();
    _setDuoState('processing');
    final path = await _audioRecorder.stop();
    if (path == null) {
      _setDuoState('idle');
      return;
    }
    try {
      Uri uri = Uri.parse('https://api.openai.com/v1/audio/transcriptions');
      var request = http.MultipartRequest('POST', uri);
      request.headers['Authorization'] = 'Bearer $_openAiKey';
      request.fields['model'] = 'whisper-1';
      request.files.add(await http.MultipartFile.fromPath('file', path));
      var response = await request.send().timeout(const Duration(seconds: 10));
      var responseData = await response.stream.bytesToString();
      if (response.statusCode == 200) {
        String transcript = jsonDecode(responseData)['text'] ?? "";
        final String trimmed = transcript.trim();
        final String lowerRaw = trimmed.toLowerCase();
        final String lowerClean =
            lowerRaw.replaceAll(RegExp(r'[^\w\s가-힣]'), '').trim();
        final String collapsed = lowerClean.replaceAll(' ', '');
        const List<String> hardGhosts = [
          'thank you so much for watching',
          'thank you for watching',
          'thanks for watching',
          'please subscribe',
          'subtitles by',
          'share this video',
          '시청해 주셔서',
          '시청해주셔서',
          '구독과 좋아요',
          '감사합니다 시청',
        ];
        final bool isHardGhost = hardGhosts.any((g) => lowerRaw.contains(g));
        const List<String> shortGhosts = [
          'thank you','yeah','okay','mbc','you','also','i','감사합니다',
        ];
        final bool isShortGhost = trimmed.length < 30 &&
            shortGhosts.any((g) => collapsed == g.replaceAll(' ', ''));
        // 🆕 에코 차단: 최근 앱이 만든 문장과 거의 같으면 버림
        final bool isEcho = _looksLikeEcho(trimmed);
        if (lowerClean.isEmpty ||
            isHardGhost ||
            isShortGhost ||
            isEcho ||
            trimmed.length <= 2) {
          _setDuoState('idle'); // 조용히 대기 복귀(자동 재녹음 금지)
          return;
        }
        if (trimmed.isNotEmpty) {
          await _processRelayPipeline(trimmed);
        } else {
          _setDuoState('idle');
        }
      } else {
        _setDuoState('idle');
      }
    } catch (e) {
      _setDuoState('idle');
    }
  }
```

────────────────────────────────────────────────────────
## 수정 4: _handleContextualError() — 자동 재녹음 제거
위치: _handleContextualError 함수(약 401줄 부근)
기존: if (_isConversationActive) _startWhisperRecording();
교체:
```dart
  Future<void> _handleContextualError() async {
    _setDuoState('idle'); // AI 사과 없음, 자동 재녹음 없음 — 조용히 대기 복귀
  }
```

────────────────────────────────────────────────────────
## 수정 5: _processRelayPipeline() 끝부분 — 자동 재녹음 제거 + 상태/에코 반영
위치: _processRelayPipeline 내부
변경점:
- TTS 재생 직전 _setDuoState('playing'), 생성 문장 _rememberGenerated(tgt)/_rememberGenerated(org) 호출.
- 마지막의 "if (_isConversationActive && _turnCounter == currentTurnId) { _startWhisperRecording(); }" 블록을 삭제하고,
  쿨다운 후 idle 복귀로 교체.
해당 끝부분(약 478~488줄) 교체:
```dart
    _rememberGenerated(tgt);
    _rememberGenerated(org);
    final Uint8List? bytes = await _fetchTTSBytes(tgt, _myVoice());
    if (bytes != null && _isConversationActive && _turnCounter == currentTurnId) {
      _setDuoState('playing');
      await _playSerialized(bytes);
    }
    // 🆕 [PTT] 자동 재녹음 제거 — 쿨다운 후 대기 상태로 복귀
    _setDuoState('cooldown');
    await Future.delayed(const Duration(milliseconds: 800));
    _setDuoState('idle');
```

────────────────────────────────────────────────────────
## 수정 6: _handleIncomingMessage() — 수신 시 내 녹음 즉시 중단 + 끝부분 자동재녹음 제거
위치: _handleIncomingMessage 내부
변경점 (앞부분): 이미 _audioRecorder.stop()과 _silenceTimer cancel이 있다면 그 직후 _setDuoState('playing') 추가. 없으면 추가.
변경점 (끝부분, 약 588~592줄): 마지막의
   if (_isConversationActive && !_isExiting) { _startWhisperRecording(); }
블록을 삭제하고 아래로 교체:
```dart
    _rememberGenerated(tgt);
    _rememberGenerated(org);
    final Uint8List? bytes = await _fetchTTSBytes(tgt, _myVoice());
    if (bytes != null && _isConversationActive && !_isExiting) {
      _setDuoState('playing');
      await _playSerialized(bytes);
    }
    // 🆕 [PTT] 상대 발화 재생 후에도 자동 재녹음 금지 — 쿨다운 후 대기 복귀
    _setDuoState('cooldown');
    await Future.delayed(const Duration(milliseconds: 800));
    _setDuoState('idle');
```
또한 이 함수 앞부분에서 내 녹음을 멈추는 부분에 다음을 보장:
```dart
    _silenceTimer?.cancel();
    try { await _audioRecorder.stop(); } catch (_) {}
    _setDuoState('processing');
```

────────────────────────────────────────────────────────
## 수정 7: _joinAsGuest() / _listenForPartnerJoined() — 입장 시 자동 녹음 제거
변경점:
- _joinAsGuest(): "setState(() { _isConversationActive = true; _isPartnerOnline = true; });" 는 유지하되,
  바로 아래 "_startWhisperRecording();" (약 888줄) 줄을 삭제. (세션만 열고 녹음은 버튼으로)
- _listenForPartnerJoined(): "if (shouldStartRecording) _startWhisperRecording();" (약 925줄) 줄을 삭제.
  단 "_isConversationActive = true" 세팅은 유지(세션 활성).
즉 입장하면 화면은 활성화되지만 마이크는 버튼 누를 때만 켜진다.

────────────────────────────────────────────────────────
## 수정 8: _handleMicTap 제거 → PTT 핸들러 신설
위치: _handleMicTap 함수(약 678~688줄) 전체 교체
교체 코드:
```dart
  // 🆕 [PTT] 버튼 누름 — 녹음 시작
  void _onPttStart() {
    _resetIdleTimer();
    if (!_isConversationActive) {
      setState(() => _isConversationActive = true);
    }
    // idle일 때만 시작(재생/처리/쿨다운 중이면 무시)
    if (_duoState == 'idle') {
      _startWhisperRecording();
    }
  }

  // 🆕 [PTT] 버튼 뗌 — 녹음 종료 후 전송
  void _onPttEnd() {
    _resetIdleTimer();
    if (_duoState == 'recording') {
      _silenceTimer?.cancel();
      _stopAndSendToWhisper();
    }
  }

  // 🆕 [PTT] 버튼 상태별 표시 문구
  String _pttLabel() {
    switch (_duoState) {
      case 'recording':
        return 'Release to send';
      case 'processing':
        return 'Processing…';
      case 'playing':
        return 'Playing…';
      case 'cooldown':
        return '…';
      default:
        return 'Hold to talk';
    }
  }
```

────────────────────────────────────────────────────────
## 수정 9: _buildControlArea() — 무전기 버튼 UI 교체
위치: 약 1158~1198줄 (함수 전체 교체)
변경점:
- 좌측 "Duo Connect" 텍스트 → _pttLabel() 상태 문구로 교체.
- 버튼: GestureDetector onTap → onTapDown/onLongPressStart=_onPttStart, onTapUp/onTapCancel/onLongPressEnd=_onPttEnd.
- 색/아이콘은 _duoState 기준(recording이면 빨강+mic, 그 외 파랑/회색).
교체 코드:
```dart
  Widget _buildControlArea(double bottomPadding) {
    final bool isRec = _duoState == 'recording';
    final bool isBusy = _duoState == 'processing' ||
        _duoState == 'playing' ||
        _duoState == 'cooldown';
    final Color accent = isRec
        ? Colors.redAccent
        : (isBusy ? Colors.white38 : const Color(0xFF2563EB));
    return Container(
      padding: EdgeInsets.fromLTRB(24, 16, 24, bottomPadding),
      decoration: const BoxDecoration(color: Color(0xFF121212)),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(_pttLabel(),
              style: const TextStyle(
                  color: Colors.white54,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.0)),
          GestureDetector(
            onTapDown: (_) => _onPttStart(),
            onTapUp: (_) => _onPttEnd(),
            onTapCancel: () => _onPttEnd(),
            onLongPressStart: (_) => _onPttStart(),
            onLongPressEnd: (_) => _onPttEnd(),
            child: Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                    color: accent.withOpacity(0.15),
                    shape: BoxShape.circle,
                    border: Border.all(color: accent, width: 2.5)),
                child: Icon(
                    isRec ? Icons.mic_rounded : Icons.mic_none_rounded,
                    color: accent,
                    size: 38)),
          ),
        ],
      ),
    );
  }
```

────────────────────────────────────────────────────────
## 수정 10: dispose / 종료 시 상태 초기화 (안전)
_handleAutoSaveAndExit 시작부 또는 dispose에서 _silenceTimer cancel은 이미 있음.
추가로 종료 시 _duoState='idle'로 두면 충분(별도 setState 불필요).

────────────────────────────────────────────────────────
## DuoBrain 프롬프트 (수정 11)
이미 번역 전용으로 되어 있으므로 변경 없음. 단, 결과가 비거나 입력과 무관한 새 문장을
만들지 않도록 system 규칙 1줄만 추가(있으면 생략):
"If the utterance is unclear or empty, output an empty string for both fields. Never invent content."

────────────────────────────────────────────────────────
## 자기 검증 (flutter analyze 까지만, 빌드 명령 금지)
1. flutter analyze lib/custom_code/widgets/routine_mode_duo.dart  → 에러 0
2. grep -c "_startWhisperRecording()" routine_mode_duo.dart
   → 호출 횟수가 크게 줄어야 함(약 2~3곳: _onPttStart, (옵션)초기 1곳). 11곳에서 감소 확인.
3. grep -c "_duoState" routine_mode_duo.dart  → 다수(상태기계 사용)
4. grep -c "onTapDown\|onLongPressStart" routine_mode_duo.dart  → 1 이상(PTT 버튼)
5. grep -c "_handleMicTap" routine_mode_duo.dart  → 0 (구 토글 제거 확인)
6. grep -c "_looksLikeEcho\|_rememberGenerated" routine_mode_duo.dart  → 각 2 이상

## 롤백
함수 단위 교체이므로, 문제 시 각 함수를 이전 버전으로 되돌리면 됨.
APK/AAB 빌드는 절대 실행하지 말 것.