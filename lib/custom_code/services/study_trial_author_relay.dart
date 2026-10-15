// ====================================================================
// 🎟️📨 [TRIAL-RELAY] 체험 대화 제작 — 다른 폰에서 친 유저 대사를 호스트 서클톡에.
// --------------------------------------------------------------------
// 실장님 방식(2026-10-16): 호스트폰은 서클톡 AI 소리를 내고, 다른 폰은 관리자
// 웹(`admin_web/author.html`)에서 유저 대신 글자를 적는다.
//
//   trial_author/{uid}               호스트가 쓰는 상태 — 대화 기록·언어 짝
//   trial_author/{uid}/lines/{id}    웹이 쓰는 대사 — {text, createdAt, consumed}
//
// 호스트는 AI가 말을 끝내고 잠깐 조용해진 뒤에만 한 줄씩 꺼내 넣는다. AI가
// 말하는 중에 넣으면 [ONE-TURN] 가드가 그 줄을 말없이 버린다.
// 같은 관리자 계정(owner + admin 클레임)만 읽고 쓴다(firestore.rules).
// ====================================================================

import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

class StudyTrialAuthorRelay {
  StudyTrialAuthorRelay({
    required this.uid,
    required this.isIdle,
    required this.onLine,
    required this.log,
  });

  final String uid;

  /// AI가 말하지 않고, 처리 중인 턴도 없는가.
  final bool Function() isIdle;

  /// 꺼낸 대사를 유저 발화로 넣는다.
  final void Function(String text) onLine;
  final void Function(String tag, String message) log;

  /// AI가 말을 끝낸 뒤 이만큼 조용해야 다음 줄을 넣는다.
  static const Duration kSettle = Duration(milliseconds: 900);
  static const int kLogLimit = 40;

  DocumentReference<Map<String, dynamic>> get _state =>
      FirebaseFirestore.instance.doc('trial_author/$uid');
  CollectionReference<Map<String, dynamic>> get _lines =>
      _state.collection('lines');

  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _sub;
  Timer? _pump;
  final List<QueryDocumentSnapshot<Map<String, dynamic>>> _queue = [];
  final Set<String> _taken = <String>{};
  final List<Map<String, String>> _history = [];
  DateTime? _idleSince;
  bool _aiSpoke = false;

  Future<void> start({
    required String chatLang,
    required String learnLang,
    required bool aiAlreadySpoke,
  }) async {
    _history.clear();
    // 제작을 AI 첫 마디 뒤에 켰으면 바로 받을 수 있다.
    _aiSpoke = aiAlreadySpoke;
    try {
      await _state.set(<String, dynamic>{
        'active': true,
        'chatLang': chatLang,
        'learnLang': learnLang,
        'log': _tail(),
        'pending': 0,
        'updatedAt': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      log('❌ [TRIAL-RELAY]', 'state_write_failed $e');
    }
    _sub = _lines
        .where('consumed', isEqualTo: false)
        .snapshots()
        .listen(_onLines, onError: (Object e) {
      log('❌ [TRIAL-RELAY]', 'listen_failed $e');
    });
    _pump = Timer.periodic(const Duration(milliseconds: 300), (_) => _tick());
    log('🎟️ [TRIAL-RELAY]', 'start chat=$chatLang learn=$learnLang');
  }

  void _onLines(QuerySnapshot<Map<String, dynamic>> snap) {
    final fresh = snap.docs.where((d) => !_taken.contains(d.id)).toList()
      ..sort((a, b) => _millis(a.data()['createdAt'])
          .compareTo(_millis(b.data()['createdAt'])));
    _queue
      ..clear()
      ..addAll(fresh);
    unawaited(_state
        .update(<String, dynamic>{'pending': _queue.length})
        .catchError((Object _) {}));
  }

  static int _millis(Object? v) => v is Timestamp ? v.millisecondsSinceEpoch : 0;

  void _tick() {
    if (_queue.isEmpty) return;
    if (!_aiSpoke || !isIdle()) {
      _idleSince = null;
      return;
    }
    final now = DateTime.now();
    _idleSince ??= now;
    if (now.difference(_idleSince!) < kSettle) return;
    final doc = _queue.removeAt(0);
    _taken.add(doc.id);
    _idleSince = null;
    final text = (doc.data()['text'] ?? '').toString().trim();
    unawaited(doc.reference.update(<String, dynamic>{
      'consumed': true,
      'consumedAt': FieldValue.serverTimestamp(),
    }).catchError((Object e) => log('❌ [TRIAL-RELAY]', 'consume_failed $e')));
    if (text.isEmpty) return;
    log('🎟️ [TRIAL-RELAY]', 'inject len=${text.length}');
    // 이 줄의 AI 대답이 나오기 전까지는 다음 줄을 넣지 않는다.
    _aiSpoke = false;
    onLine(text);
  }

  /// 저장된 대화 줄을 웹 화면으로 올린다. 서클톡 `_saveHistoryMessages`가 부른다.
  void recordLines(List<Map<String, dynamic>> lines) {
    var changed = false;
    for (final line in lines) {
      final text = (line['original_text'] ?? '').toString().trim();
      if (text.isEmpty) continue;
      final role = line['role'] == 'HOST' ? 'USER' : 'AI';
      if (role == 'AI') _aiSpoke = true;
      _history.add(<String, String>{'role': role, 'text': text});
      changed = true;
    }
    if (!changed) return;
    unawaited(_state.update(<String, dynamic>{
      'log': _tail(),
      'updatedAt': FieldValue.serverTimestamp(),
    }).catchError((Object e) => log('❌ [TRIAL-RELAY]', 'log_failed $e')));
  }

  List<Map<String, String>> _tail() => _history.length <= kLogLimit
      ? List<Map<String, String>>.of(_history)
      : _history.sublist(_history.length - kLogLimit);

  Future<void> stop() async {
    _pump?.cancel();
    _pump = null;
    await _sub?.cancel();
    _sub = null;
    try {
      await _state.update(<String, dynamic>{
        'active': false,
        'updatedAt': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      debugPrint('[TRIAL-RELAY] stop $e');
    }
    log('🎟️ [TRIAL-RELAY]', 'stop');
  }
}
