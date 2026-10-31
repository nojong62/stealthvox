// ====================================================================
// 🎫 [INTERP-HANDOFF] 익명으로 한 **통역** 통화를 기존 회원 계정에서 되찾는 표.
// --------------------------------------------------------------------
// 직접 대화는 공유 결과(canonical)로 다시 짓는다(`duo_guest_handoff.dart`).
// 통역 통화에는 공유 결과가 없어서 그 길을 못 탄다 — 그래서 비회원이 통화를
// 마치고 **원래 쓰던 회원 계정**으로 로그인하면 방금 대화가 사라졌다.
//
// 통화가 끝날 때 서버에서 표를 받아 이 폰에만 둔다. 로그인 뒤 uid가 바뀌었으면
// 표를 내고, 서버가 기록을 새 계정 공부방으로 복사한다
// (`firebase/functions/duo_history_handoff.js`).
//
// 처음 가입(익명 계정에 그대로 연결, uid 유지)이면 옮길 것이 없어 표만 버린다.
// ====================================================================

import 'dart:convert';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

const String _kTicketsKey = 'duo_interp_handoff_tickets';

/// 30일이 지난 표는 서버에서도 만료다. 폰에서도 그만큼만 들고 있는다.
const Duration _kTicketTtl = Duration(days: 30);

Future<List<Map<String, dynamic>>> _readTickets(SharedPreferences prefs) async {
  final raw = prefs.getStringList(_kTicketsKey) ?? const <String>[];
  final now = DateTime.now().millisecondsSinceEpoch;
  final out = <Map<String, dynamic>>[];
  for (final item in raw) {
    try {
      final map = Map<String, dynamic>.from(jsonDecode(item) as Map);
      final savedAt = (map['savedAtMs'] as num?)?.toInt() ?? 0;
      if (now - savedAt <= _kTicketTtl.inMilliseconds) out.add(map);
    } catch (_) {}
  }
  return out;
}

Future<void> _writeTickets(
    SharedPreferences prefs, List<Map<String, dynamic>> tickets) async {
  await prefs.setStringList(
      _kTicketsKey, tickets.map((t) => jsonEncode(t)).toList());
}

/// 익명으로 통역 통화를 마친 직후에 부른다. 실패해도 통화 마무리를 막지 않는다.
Future<void> issueDuoInterpHandoffTicket(String historyId) async {
  final user = FirebaseAuth.instance.currentUser;
  if (user == null || !user.isAnonymous || historyId.isEmpty) return;
  try {
    final result = await FirebaseFunctions.instance
        .httpsCallable('issueDuoHistoryHandoff')
        .call({'historyId': historyId}).timeout(const Duration(seconds: 10));
    final ticket =
        Map<String, dynamic>.from(result.data as Map)['ticket']?.toString();
    if (ticket == null || ticket.isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    final tickets = await _readTickets(prefs);
    tickets.add({
      'ticket': ticket,
      'anonUid': user.uid,
      'historyId': historyId,
      'savedAtMs': DateTime.now().millisecondsSinceEpoch,
    });
    await _writeTickets(prefs, tickets);
    debugPrint('[INTERP-HANDOFF] ticket saved history=$historyId');
  } catch (error) {
    debugPrint('[INTERP-HANDOFF] issue failed: ${error.runtimeType}');
  }
}

/// 회원 로그인 직후에 부른다. uid가 바뀐 표만 내고, 같은 uid의 표는 버린다.
Future<void> redeemDuoInterpHandoffTickets() async {
  final user = FirebaseAuth.instance.currentUser;
  if (user == null || user.isAnonymous) return;
  final prefs = await SharedPreferences.getInstance();
  final tickets = await _readTickets(prefs);
  if (tickets.isEmpty) return;
  final keep = <Map<String, dynamic>>[];
  for (final t in tickets) {
    if (t['anonUid'] == user.uid) continue; // 가입으로 uid가 이어졌다.
    try {
      final result = await FirebaseFunctions.instance
          .httpsCallable('redeemDuoHistoryHandoff')
          .call({'ticket': t['ticket']}).timeout(const Duration(seconds: 20));
      debugPrint('[INTERP-HANDOFF] redeemed ${result.data}');
    } on FirebaseFunctionsException catch (error) {
      // 표 자체가 틀렸거나 만료면 버린다. 일시 장애면 다음 로그인에 다시.
      final permanent = error.code == 'not-found' ||
          error.code == 'deadline-exceeded' ||
          error.code == 'invalid-argument';
      debugPrint('[INTERP-HANDOFF] redeem failed: ${error.code}');
      if (!permanent) keep.add(t);
    } catch (error) {
      debugPrint('[INTERP-HANDOFF] redeem failed: ${error.runtimeType}');
      keep.add(t);
    }
  }
  await _writeTickets(prefs, keep);
}
