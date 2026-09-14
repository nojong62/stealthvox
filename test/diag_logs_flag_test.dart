// 🔬 [DIAG-LOGS] 진단 빌드에서만 로그를 연다.
//
// 실기기에서 재야 하는 것은 대개 순서와 시각이다(마이크가 언제 섰나, 문이
// 언제 열렸나). debug 빌드는 JIT라 그 숫자가 왜곡되고, profile은 속도가
// 릴리스에 가까운데 `kDebugMode`가 거짓이라 로그가 같이 닫혔다.
// 그래서 profile로 올려도 아무것도 못 보고 코드로 되짚어야 했다(2026-09-14).
//
// ⚠️ **기본은 꺼짐이다.** 플래그를 안 주면 릴리스 동작이 한 글자도 안 바뀐다.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:stealth_vox/main.dart' show kDiagLogs;

void main() {
  final String main = File('lib/main.dart')
      .readAsStringSync()
      .replaceAll('\r\n', '\n');

  test('기본은 꺼짐 — 릴리스는 예전 그대로다', () {
    expect(kDiagLogs, isFalse,
        reason: '기본이 켜지면 릴리스 로그가 대화록이 된다');
    expect(
        main,
        contains(
            "bool.fromEnvironment('DIAG_LOGS', defaultValue: false)"));
  });

  test('문을 닫는 조건에 플래그가 걸려 있다', () {
    expect(main, contains('if (!kDebugMode && !kDiagLogs) {'),
        reason: '플래그를 봐도 debugPrint가 비워지면 진단 빌드가 조용하다');
    // 예전 조건이 그대로 남아 있으면 플래그가 무력해진다.
    expect(main.contains('if (!kDebugMode) {\n    debugPrint ='), isFalse);
  });

  test('debugPrint를 비우는 자리는 한 곳뿐이다', () {
    final int places =
        RegExp(r'debugPrint = \(String\? message').allMatches(main).length;
    expect(places, 1,
        reason: '두 곳에서 비우면 한쪽만 플래그를 봐서 조용히 닫힌다');
  });
}
