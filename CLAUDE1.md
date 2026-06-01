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

[Duo 마무리] 과금 시점 정렬 + PTT 버튼 정리 + 녹음 중단 UX 보완 + 에코 차단 강화

파일: lib/custom_code/widgets/routine_mode_duo.dart

## 참고
사전 점검 결과, 평가서가 1순위로 지목한 _listenForPartnerJoined() 세미콜론 누락은
실제로는 존재하지 않음(887/955/994줄 모두 정상). 문법 수정은 하지 말 것.
아래 4개 항목만 수정한다.

────────────────────────────────────────────────────────
## 수정 1: Duo 과금 시점 — "게스트 입장 시 시작" 정책 정렬
정책: 다른 모드는 입장 즉시 과금(60초 무활동 오토포즈 유지). Duo만 예외 —
호스트가 초대장 만들고 대기하는 동안은 과금 정지, 게스트 입장 확정 시 과금 시작,
게스트 퇴장/종료 시 정지.

### 1-A. initState 즉시 resume 제거
위치: 약 187~189줄
기존:
    BillingTicker.instance.setRate(BillingRate.full);
    BillingTicker.instance.resume();
    BillingTicker.instance.logMode('duo');
교체:
    // 🆕 [과금정책] Duo는 게스트 입장 시점에 과금 시작 — 진입 시엔 rate만 설정하고 pause 유지
    BillingTicker.instance.setRate(BillingRate.full);
    BillingTicker.instance.pause();
    _billingStarted = false;

### 1-B. 과금 시작 플래그 + 헬퍼 추가
위치: 상태 변수 선언부(_recentGenerated 근처)
추가:
```dart
  // 🆕 [과금정책] 게스트 입장 후에만 과금 시작 (호스트 대기 중 정지)
  bool _billingStarted = false;
  void _startDuoBilling() {
    if (_billingStarted) return;
    _billingStarted = true;
    BillingTicker.instance.resume();
    BillingTicker.instance.logMode('duo');
  }
  void _stopDuoBilling() {
    _billingStarted = false;
    BillingTicker.instance.pause();
  }
```

### 1-C. _resetIdleTimer의 자동 resume 가드
위치: 약 136~145줄 _resetIdleTimer
기존 if (_isIdlePaused) 블록 내부:
      BillingTicker.instance.resume();
      BillingTicker.instance.logMode('duo');
교체:
      // 🆕 [과금정책] 게스트 입장(과금 시작) 상태일 때만 resume — 대기 중엔 재개 금지
      if (_billingStarted) {
        BillingTicker.instance.resume();
        BillingTicker.instance.logMode('duo');
      }

### 1-D. 게스트 입장 확정 시 과금 시작 (호스트 측 리스너)
위치: _listenForPartnerJoined 내부, setState 블록(약 963~971줄)
기존:
        // 🆕 [PTT] 입장 시 자동 녹음 제거 — 버튼으로만 시작
        // 게스트 퇴장 → 호스트 강제 종료 (1:1 대칭 종료 모델)
        if (guestJustLeft) _handleAutoSaveAndExit();
교체:
        // 🆕 [과금정책] 게스트 입장 확정 시 과금 시작 / 퇴장 시 정지
        if (partnerJoined) {
          _startDuoBilling();
        } else {
          _stopDuoBilling();
        }
        // 🆕 [PTT] 입장 시 자동 녹음 제거 — 버튼으로만 시작
        // 게스트 퇴장 → 호스트 강제 종료 (1:1 대칭 종료 모델)
        if (guestJustLeft) _handleAutoSaveAndExit();

### 1-E. 게스트 본인 합류 성공 시 과금 시작 (게스트 측)
위치: _joinAsGuest 성공부, "_isPartnerOnline = true;" setState 직후(약 930줄, PTT 주석 위)
추가:
      // 🆕 [과금정책] 게스트 본인 입장 성공 → 과금 시작
      _startDuoBilling();

### 1-F. 종료 시 과금 정지
위치: _handleAutoSaveAndExit 시작부(약 977줄, _isExiting=true 직후)
추가:
    _stopDuoBilling();

────────────────────────────────────────────────────────
## 수정 2: PTT 버튼 이벤트 정리 (tap+longPress 중복 → Listener 포인터 단일화)
위치: _buildControlArea 내 GestureDetector(약 1221~1230줄)
변경: GestureDetector의 onTapDown/onTapUp/onTapCancel/onLongPressStart/onLongPressEnd 5개를
      Listener의 onPointerDown/onPointerUp/onPointerCancel 로 교체(중복 호출 원천 제거).
기존(예시):
          GestureDetector(
            onTapDown: (_) => _onPttStart(),
            onTapUp: (_) => _onPttEnd(),
            onTapCancel: () => _onPttEnd(),
            onLongPressStart: (_) => _onPttStart(),
            onLongPressEnd: (_) => _onPttEnd(),
            child: Container( ... ),
          ),
교체:
          Listener(
            behavior: HitTestBehavior.opaque,
            onPointerDown: (_) => _onPttStart(),
            onPointerUp: (_) => _onPttEnd(),
            onPointerCancel: (_) => _onPttEnd(),
            child: Container( ... ), // 기존 Container child 그대로 유지
          ),
주의: child의 Container(크기/색/아이콘) 코드는 그대로 둘 것. 래퍼 위젯만 교체.

────────────────────────────────────────────────────────
## 수정 3: 상대 메시지 도착 시 "녹음 중인 내 발화" 보호 (UX)
문제: 내가 버튼 누르고 말하는 중(_duoState=='recording')에 상대 메시지가 도착하면
      _handleIncomingMessage가 내 녹음을 즉시 stop시켜 발화가 끊김.
해결: 내가 recording 중이면 상대 메시지를 큐에 둔 채 처리 보류,
      내가 손 떼고 idle/cooldown이 된 뒤 처리.

### 3-A. _drainIncoming에 recording 가드 추가
위치: _drainIncoming 함수(약 567~576줄)
기존 while 루프 진입부에 조건 추가:
```dart
  Future<void> _drainIncoming() async {
    if (_isDrainingIncoming) return;
    _isDrainingIncoming = true;
    while (_incomingQueue.isNotEmpty) {
      // 🆕 내가 녹음 중이면 상대 메시지 처리 보류 — 내 발화 끊김 방지
      if (_duoState == 'recording') break;
      final data = _incomingQueue.removeAt(0);
      await _handleIncomingMessage(data);
    }
    _isDrainingIncoming = false;
  }
```

### 3-B. 내 발화 처리 종료 후 보류된 상대 메시지 재가동
위치: _processRelayPipeline 끝부분, idle 복귀 직후(쿨다운 후 _setDuoState('idle') 다음 줄)
추가:
    // 🆕 내 발화 처리 끝 → 보류돼 있던 상대 메시지 처리 재개
    if (_incomingQueue.isNotEmpty) _drainIncoming();

### 3-C. _onPttEnd에서도 큐 재가동 보장
위치: _onPttEnd 함수
_stopAndSendToWhisper() 호출은 그대로 두되, 그 처리 흐름이 idle로 끝난 뒤
보류 메시지가 처리되도록 _processRelayPipeline 쪽 3-B로 커버됨(추가 변경 불필요).
단, 녹음이 아니었던 경우(빈 transcript로 즉시 idle)에도 큐가 남아있으면 처리되도록
_stopAndSendToWhisper의 각 _setDuoState('idle') 직후에 다음 한 줄을 추가:
    if (_incomingQueue.isNotEmpty) _drainIncoming();

────────────────────────────────────────────────────────
## 수정 4: 에코 차단 강화 (완전일치 → 정규화 유사도)
문제: 현재는 같음/포함 관계만 검사. "I haven't checked." vs "I haven't checked yet" 같은
      변형 에코를 놓침.
해결: 보관 개수 5→10, 정규화(소문자+구두점/공백 제거) 후 포함관계 + 토큰 자카드 유사도 검사,
      그리고 TTS 재생 직후 1.2초간은 더 엄격히(낮은 임계값) 필터.

### 4-A. 보관 개수 확대 + 정규화/유사도 헬퍼 교체
위치: _rememberGenerated / _looksLikeEcho (약 62~80줄)
교체:
```dart
  final List<String> _recentGenerated = [];
  DateTime? _lastTtsEndAt; // 🆕 마지막 TTS 종료 시각(엄격 필터 윈도우용)

  String _normForEcho(String s) =>
      s.toLowerCase().replaceAll(RegExp(r'[^\w가-힣]'), '');

  void _rememberGenerated(String s) {
    final t = s.trim();
    if (t.isEmpty) return;
    _recentGenerated.add(t);
    while (_recentGenerated.length > 10) _recentGenerated.removeAt(0);
  }

  // 토큰 자카드 유사도 (0~1)
  double _jaccard(String a, String b) {
    final sa = a.toLowerCase().split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toSet();
    final sb = b.toLowerCase().split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toSet();
    if (sa.isEmpty || sb.isEmpty) return 0.0;
    final inter = sa.intersection(sb).length;
    final uni = sa.union(sb).length;
    return uni == 0 ? 0.0 : inter / uni;
  }

  bool _looksLikeEcho(String transcript) {
    final t = transcript.trim();
    if (t.length < 4) return false;
    final tn = _normForEcho(t);

    // TTS 종료 직후 1.2초는 엄격 모드(임계값 완화 → 더 잘 버림)
    final bool strict = _lastTtsEndAt != null &&
        DateTime.now().difference(_lastTtsEndAt!).inMilliseconds < 1200;
    final double simThreshold = strict ? 0.6 : 0.8;

    for (final g in _recentGenerated) {
      if (g.isEmpty) continue;
      final gn = _normForEcho(g);
      if (gn.isEmpty) continue;
      // ① 정규화 포함 관계
      if (gn == tn || gn.contains(tn) || tn.contains(gn)) return true;
      // ② 토큰 자카드 유사도
      if (_jaccard(g, t) >= simThreshold) return true;
    }
    return false;
  }
```

### 4-B. TTS 종료 시각 기록
위치: _playSerialized 또는 _playAudioAndWait에서 재생 완료 후(_isTtsActive=false로 만드는 지점)
추가 한 줄(재생이 끝나는 곳):
    _lastTtsEndAt = DateTime.now();
(가장 안전한 위치: _playAudioAndWait의 await 종료 직후, _isTtsActive=false 라인 옆)

────────────────────────────────────────────────────────
## 자기 검증 (flutter analyze 까지만 — APK/AAB 빌드 금지)
1. flutter analyze lib/custom_code/widgets/routine_mode_duo.dart → 에러 0
2. grep -c "_billingStarted" routine_mode_duo.dart            → 5 이상
3. grep -c "_startDuoBilling\|_stopDuoBilling" routine_mode_duo.dart → 5 이상
4. grep -c "onPointerDown" routine_mode_duo.dart              → 1
5. grep -c "onLongPressStart\|onTapDown" routine_mode_duo.dart → 0 (구 방식 제거 확인)
6. grep -c "_jaccard\|_normForEcho\|_lastTtsEndAt" routine_mode_duo.dart → 다수
7. grep -c "length > 10" routine_mode_duo.dart                → 1 (보관 10개 확인)
8. grep -c "if (_duoState == 'recording') break;" routine_mode_duo.dart → 1 (녹음보호 확인)

## 롤백
각 함수 단위 교체이므로 문제 시 해당 함수만 이전 버전으로 복원.