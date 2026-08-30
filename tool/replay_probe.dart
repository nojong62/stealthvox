// 🎬 Replay 규칙을 **실제 통화 기록에 돌려 보는** 도구.
//
//   dart run tool/replay_probe.dart tool/replay_samples/sample_call.txt
//   dart run tool/replay_probe.dart my_call.json
//
// 🔑 키는 **환경변수 OPENAI_API_KEY로만** 받는다. 명령줄 인자로 받지 않는다 —
//    인자로 두면 셸 히스토리·프로세스 목록·화면 캡처·붙여넣기로 새어 나간다.
//    앱은 Remote Config로 받지만 이 도구는 앱을 거치지 않으므로 손으로 준다.
//
//      PowerShell  $env:OPENAI_API_KEY = "..."   (그 창에서만 산다)
//      bash        export OPENAI_API_KEY=...
//      파일로 두려면  tool/.openai_key  (.gitignore에 있다)
//
// 넣는 글의 두 가지 모양:
//
//   ① .txt  한 줄에 한 발화. Firestore 콘솔에서 눈으로 옮겨 적기 좋다.
//              HOST: 내일... 어, 내일 몇 시쯤 올 거야?
//              GUEST: 글쎄. 아마... 한 여섯 시?
//
//   ② .json canonical 문서의 turns 배열을 그대로 붙여 넣은 것.
//              [{"role":"HOST","text":"...","source_ids":["abc"]}, ...]
//              또는 {"turns":[ ... ]}
//
// 내는 것: 원본 · Replay · 걷어낸 줄 · 검토 경고. **판단은 사람이 한다.**
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import 'package:stealth_vox/custom_code/services/duo_replay_rules.dart';

const String _model = 'gpt-4.1-mini';

Future<void> main(List<String> args) async {
  final files = args.where((a) => !a.startsWith('--')).toList();
  if (files.isEmpty) {
    stderr.writeln('사용법: dart run tool/replay_probe.dart <통화기록...> [--dry-run]');
    stderr.writeln('키: 환경변수 OPENAI_API_KEY 또는 tool/.openai_key 파일');
    exitCode = 64;
    return;
  }
  // 명령줄로는 받지 않는다. 인자에 키를 적는 순간 셸 히스토리에 남는다.
  if (args.any((a) => a.startsWith('--key'))) {
    stderr.writeln('키를 명령줄로 주지 말 것 — OPENAI_API_KEY 환경변수를 쓴다.');
    exitCode = 64;
    return;
  }
  final key = _readKey();
  final dryRun = args.contains('--dry-run');

  for (final path in files) {
    final source = _readSource(File(path));
    if (source.isEmpty) {
      stderr.writeln('$path: 읽을 발화가 없다');
      continue;
    }
    stdout.writeln('\n══════ $path ══════');
    _printSection('ORIGINAL CALL (${source.length}줄)');
    for (final line in source) {
      stdout.writeln('  ${_role(line.role)}  ${line.text}');
    }

    if (dryRun) {
      stdout.writeln('\n(--dry-run: 모델을 부르지 않는다)');
      continue;
    }
    if (key.isEmpty) {
      stderr.writeln('\n키가 없다. OPENAI_API_KEY 환경변수를 두거나 '
          'tool/.openai_key 파일에 넣을 것.');
      exitCode = 78;
      return;
    }

    final content = await _ask(key: key, source: source);
    if (content == null) {
      stderr.writeln('모델 호출 실패');
      exitCode = 70;
      continue;
    }
    final result = parseReplayResponse(content: content, source: source);

    _printSection('CONVERSATION REPLAY (${result.turns.length}줄)');
    for (final turn in result.turns) {
      final joined = turn.sourceIds.length > 1 ? '  ⟵ ${turn.sourceIds.length}줄 이음' : '';
      stdout.writeln('  ${_role(turn.role)}  ${turn.text}$joined');
    }

    _printSection('걷어낸 줄 (${result.dropped.length})');
    final byId = <String, ReplaySourceLine>{for (final s in source) s.id: s};
    for (final drop in result.dropped) {
      stdout.writeln('  ${drop.reason.padRight(10)} "${byId[drop.id]?.text ?? ''}"');
    }
    if (result.dropped.isEmpty) stdout.writeln('  (없음)');

    // A(의미 보존)는 **글자가 바뀐 줄에서만** 생길 수 있다. 여기만 읽으면 된다.
    final edits = replayEdits(result: result, source: source);
    _printSection('고친 줄 (${edits.length}) — A. 의미가 바뀌었는가');
    for (final e in edits) {
      stdout.writeln('  − ${e.before}');
      stdout.writeln('  + ${e.after}');
      stdout.writeln('');
    }
    if (edits.isEmpty) stdout.writeln('  (없음 — 지운 것 말고는 원문 그대로다)');

    _printSection('검토 (${result.warnings.length})');
    if (result.warnings.isEmpty) {
      stdout.writeln('  ✓ 지어낸 줄·화자 뒤바뀜·빠진 원본 없음');
    } else {
      for (final w in result.warnings) {
        stdout.writeln('  ⚠ $w');
      }
    }

    final verdict = judgeReplay(result: result, sourceCount: source.length);
    _printSection('판정');
    stdout.writeln(verdict.useReplay
        ? '  ✅ USE REPLAY'
        : '  ↩️  FALL BACK TO CANONICAL — ${verdict.reasons.join(", ")}');
  }
}

/// 키를 읽는 자리는 여기 하나뿐이다. 어느 쪽에서 왔든 **화면에도 로그에도
/// 찍지 않는다.**
String _readKey() {
  final env = (Platform.environment['OPENAI_API_KEY'] ?? '').trim();
  if (env.isNotEmpty) return env;
  final file = File('tool/.openai_key');
  if (file.existsSync()) return file.readAsStringSync().trim();
  return '';
}

void _printSection(String title) {
  final bar = '─' * (52 - title.length).clamp(0, 52);
  stdout.writeln('\n── $title $bar');
}

String _role(String role) => role == 'HOST' ? 'HOST ' : 'GUEST';

List<ReplaySourceLine> _readSource(File file) {
  final text = file.readAsStringSync();
  if (file.path.toLowerCase().endsWith('.json')) {
    final decoded = jsonDecode(text);
    final list = decoded is Map ? decoded['turns'] : decoded;
    final out = <ReplaySourceLine>[];
    var i = 0;
    for (final raw in (list as List? ?? const <dynamic>[])) {
      if (raw is! Map) continue;
      final body = (raw['text'] ?? '').toString().trim();
      if (body.isEmpty) continue;
      final ids = (raw['source_ids'] as List?)?.map((e) => e.toString()).toList();
      out.add(ReplaySourceLine(
        id: (ids != null && ids.isNotEmpty) ? ids.first : 'L${++i}',
        role: (raw['role'] ?? 'HOST').toString(),
        text: body,
      ));
    }
    return out;
  }

  final out = <ReplaySourceLine>[];
  var i = 0;
  for (final raw in const LineSplitter().convert(text)) {
    final line = raw.trim();
    if (line.isEmpty || line.startsWith('#')) continue;
    final sep = line.indexOf(':');
    if (sep <= 0) continue;
    final role = line.substring(0, sep).trim().toUpperCase();
    final body = line.substring(sep + 1).trim();
    if (body.isEmpty) continue;
    out.add(ReplaySourceLine(
      id: 'L${++i}',
      role: role == 'GUEST' ? 'GUEST' : 'HOST',
      text: body,
    ));
  }
  return out;
}

Future<String?> _ask({
  required String key,
  required List<ReplaySourceLine> source,
}) async {
  try {
    final res = await http
        .post(
          Uri.parse('https://api.openai.com/v1/chat/completions'),
          headers: <String, String>{
            'Authorization': 'Bearer $key',
            'Content-Type': 'application/json; charset=utf-8',
          },
          body: jsonEncode(<String, dynamic>{
            'model': _model,
            'temperature': 0.1,
            'max_tokens': 4000,
            'response_format': <String, String>{'type': 'json_object'},
            'messages': <Map<String, String>>[
              <String, String>{'role': 'system', 'content': kReplayPrompt},
              <String, String>{
                'role': 'user',
                'content': jsonEncode(buildReplayPayload(source)),
              },
            ],
          }),
        )
        .timeout(const Duration(seconds: 60));
    if (res.statusCode != 200) {
      stderr.writeln('HTTP ${res.statusCode}: ${utf8.decode(res.bodyBytes)}');
      return null;
    }
    final body = jsonDecode(utf8.decode(res.bodyBytes));
    return body['choices']?[0]?['message']?['content']?.toString();
  } catch (e) {
    stderr.writeln('요청 실패: ${e.runtimeType}');
    return null;
  }
}
