// ignore_for_file: avoid_print
// 앱 문구의 원본은 한글이다. 한글만 고치면 나머지 언어는 이 도구가 맞춘다.
//
//   dart run tool/ko_source_drift.dart           # 확인만 (어긋나면 종료 코드 1)
//   dart run tool/ko_source_drift.dart --sync    # 바뀐 한글을 AI로 의역해 다른 언어에 써 넣음
//   dart run tool/ko_source_drift.dart --accept  # 번역 없이 지금 한글을 기준으로 삼음
//
// 커밋할 때 .githooks/pre-commit이 --sync --stage를 돌린다(git config core.hooksPath .githooks).
// tool/ko_source_baseline.json에 마지막으로 맞춘 한글 원문을 둔다. 한글이 그와 다르거나
// 다른 언어에 키가 없으면(영어로 대신 보인다) 그 키를 다시 번역한다.
// 번역은 OPENAI_API_KEY 환경 변수로 gpt-6-luna를 부른다. KO_SYNC_MODEL로 바꿀 수 있다.
import 'dart:convert';
import 'dart:io';

const _baselinePath = 'tool/ko_source_baseline.json';

const _mapFiles = [
  'lib/custom_code/services/coupon_localization.dart',
  'lib/custom_code/services/duo_buddy_localization.dart',
  'lib/custom_code/services/duo_invite_localization.dart',
  'lib/custom_code/services/guide_ui_localization.dart',
  'lib/custom_code/services/talk_ui_localization.dart',
  'lib/custom_code/services/duo_board_intro_notice.dart',
  'lib/custom_code/widgets/routine_mode_duo.dart',
  'lib/custom_code/widgets/chat_history_list_master.dart',
];
const _faqFile = 'lib/custom_code/services/intro_faq_copy.dart';
const _rowFile = 'lib/custom_code/services/origin_surface_localization.dart';
const copyFiles = [..._mapFiles, _faqFile, _rowFile];

const _rowOrder = [
  'en', 'ko', 'ja', 'zh', 'es', 'fr', 'de', 'hi', 'ru', 'pt', 'it', 'nl',
];
const _languageNames = {
  'English': 'English', 'Japanese': 'Japanese', 'Chinese': 'Simplified Chinese',
  'Spanish': 'Spanish', 'French': 'French', 'German': 'German',
  'Hindi': 'Hindi', 'Russian': 'Russian', 'Portuguese': 'Brazilian Portuguese',
  'Italian': 'Italian', 'Dutch': 'Dutch', //
  'en': 'English', 'ja': 'Japanese', 'zh': 'Simplified Chinese',
  'es': 'Spanish', 'fr': 'French', 'de': 'German', 'hi': 'Hindi',
  'ru': 'Russian', 'pt': 'Brazilian Portuguese', 'it': 'Italian', 'nl': 'Dutch',
};
const _ko = {'Korean', 'ko'};
bool _isLanguage(String s) => _ko.contains(s) || _languageNames.containsKey(s);

/// 파일 안의 한 (언어, 키) 자리. 값은 줄 [start, end]에 있다.
class _Entry {
  _Entry(this.lang, this.key, this.start);
  final String lang;
  final String key;
  final int start;
  int end = -1;

  /// map: `'key':`까지의 줄 머리. faq·row는 비어 있다.
  String prefix = '';
  bool comma = true;

  /// 문자열 값. faq는 [질문, 답] 두 개, 나머지는 한 개. null이면 읽지 못한 모양.
  List<String>? values;
}

class _Block {
  _Block(this.lang, this.openLine, this.keyIndent);
  final String lang;
  final int openLine;
  int keyIndent;
}

class _FileCopy {
  _FileCopy(this.path, this.lines, this.kind);
  final String path;
  final List<String> lines;
  final String kind; // map | faq | row
  final entries = <String, Map<String, _Entry>>{}; // lang → key → entry
  final blocks = <String, _Block>{}; // map 파일의 언어 블록

  String get koLang => entries.keys.firstWhere(_ko.contains, orElse: () => '');
  Map<String, _Entry> get ko => entries[koLang] ?? {};
  Iterable<String> get others => entries.keys.where((l) => !_ko.contains(l));

  void put(_Entry e) => entries.putIfAbsent(e.lang, () => {})[e.key] = e;
}

int _indent(String s) => s.length - s.trimLeft().length;

// ── Dart 문자열 읽기 ─────────────────────────────────────────────

class _Cursor {
  _Cursor(this.lines, this.line, this.col);
  final List<String> lines;
  int line;
  int col;
  String? get ch => line < lines.length && col < lines[line].length
      ? lines[line][col]
      : (line < lines.length ? '\n' : null);
  void next() {
    if (line >= lines.length) return;
    if (col < lines[line].length) {
      col++;
    } else {
      line++;
      col = 0;
    }
  }

  void skipBlank() {
    while (true) {
      final c = ch;
      if (c == null) return;
      if (c == ' ' || c == '\t' || c == '\n' || c == '\r') {
        next();
      } else if (c == '/' && lines[line].startsWith('//', col)) {
        line++;
        col = 0;
      } else {
        return;
      }
    }
  }
}

/// 따옴표 하나로 싼 문자열 하나. 보간·세 겹 따옴표는 null.
String? _literal(_Cursor c) {
  var raw = false;
  if (c.ch == 'r') {
    raw = true;
    c.next();
  }
  final q = c.ch;
  if (q != "'" && q != '"') return null;
  final row = c.lines[c.line];
  if (row.startsWith('$q$q$q', c.col)) return null;
  c.next();
  final out = StringBuffer();
  while (true) {
    final ch = c.ch;
    if (ch == null || ch == '\n') return null;
    c.next();
    if (ch == q) return out.toString();
    if (ch == r'$' && !raw) {
      return null;
    }
    if (ch == r'\' && !raw) {
      final e = c.ch;
      c.next();
      switch (e) {
        case 'n':
          out.write('\n');
        case 't':
          out.write('\t');
        case 'u':
          final hex = StringBuffer();
          if (c.ch == '{') {
            c.next();
            while (c.ch != '}') {
              hex.write(c.ch);
              c.next();
            }
            c.next();
          } else {
            for (var i = 0; i < 4; i++) {
              hex.write(c.ch);
              c.next();
            }
          }
          out.writeCharCode(int.parse(hex.toString(), radix: 16));
        default:
          out.write(e);
      }
      continue;
    }
    out.write(ch);
  }
}

/// 이어 붙은 문자열들 하나('a' 'b' → ab). 끝난 줄을 돌려준다.
(String, int)? _concat(_Cursor c) {
  final buf = StringBuffer();
  var any = false;
  var lastLine = c.line;
  while (true) {
    c.skipBlank();
    final ch = c.ch;
    if (ch != "'" && ch != '"' && ch != 'r') break;
    final s = _literal(c);
    if (s == null) return null;
    buf.write(s);
    lastLine = c.line;
    any = true;
  }
  return any ? (buf.toString(), lastLine) : null;
}

String _dartLiteral(String s) {
  final b = StringBuffer("'");
  for (final r in s.runes) {
    final ch = String.fromCharCode(r);
    switch (ch) {
      case r'\':
        b.write(r'\\');
      case "'":
        b.write(r"\'");
      case r'$':
        b.write(r'\$');
      case '\n':
        b.write(r'\n');
      case '\t':
        b.write(r'\t');
      default:
        b.write(ch);
    }
  }
  b.write("'");
  return b.toString();
}

// ── 파일 읽기 ───────────────────────────────────────────────────

_FileCopy _scanMaps(String path) {
  final lines = File(path).readAsLinesSync();
  final f = _FileCopy(path, lines, 'map');
  final langRe = RegExp(r"^(\s*)'(\w+)'\s*:");
  final keyRe = RegExp(r"^(\s*'?([A-Za-z_]\w*)'?\s*:)");
  _Block? block;
  var langIndent = -1;
  var skipUntil = -1;
  for (var i = 0; i < lines.length; i++) {
    final t = lines[i];
    if (i <= skipUntil) continue;
    final indent = _indent(t);
    if (RegExp(r'static const _english\s*=').hasMatch(t)) {
      block = _Block('English', i, -1);
      langIndent = indent - 2;
      f.blocks['English'] = block;
      continue;
    }
    final m = langRe.firstMatch(t);
    if (m != null && _isLanguage(m.group(2)!)) {
      block = _Block(m.group(2)!, i, -1);
      langIndent = m.group(1)!.length;
      f.blocks[block.lang] = block;
      continue;
    }
    if (block == null) continue;
    if (t.trim().isNotEmpty &&
        indent <= langIndent &&
        !t.trim().startsWith("'")) {
      block = null;
      continue;
    }
    final km = keyRe.firstMatch(t);
    if (km == null || indent <= langIndent) continue;
    if (block.keyIndent < 0) block.keyIndent = indent;
    if (indent != block.keyIndent) continue;
    final e = _Entry(block.lang, km.group(2)!, i)..prefix = km.group(1)!;
    final c = _Cursor(lines, i, km.end);
    final v = _concat(c);
    if (v == null) {
      e.end = i;
    } else {
      e.values = [v.$1];
      e.end = v.$2;
      c.skipBlank();
      e.comma = c.ch == ',';
      skipUntil = v.$2;
    }
    f.put(e);
  }
  return f;
}

/// FAQ는 언어마다 [질문, 답] 목록이다. 몇 번째 항목인지로 맞댄다.
_FileCopy _scanFaq(String path) {
  final lines = File(path).readAsLinesSync();
  final f = _FileCopy(path, lines, 'faq');
  String? lang;
  var item = -1;
  for (var i = 0; i < lines.length; i++) {
    final m = RegExp(r"^    '(\w+)': IntroFaqCopy\._\(").firstMatch(lines[i]);
    if (m != null) {
      lang = m.group(1);
      item = -1;
      continue;
    }
    if (lang == null || !RegExp(r'^      \[\s*$').hasMatch(lines[i])) continue;
    item++;
    final e = _Entry(lang, 'item ${item + 1}', i);
    final c = _Cursor(lines, i + 1, 0);
    final q = _concat(c);
    c.skipBlank();
    if (c.ch == ',') c.next();
    final a = _concat(c);
    var j = i + 1;
    while (j < lines.length && !RegExp(r'^      \],?\s*$').hasMatch(lines[j])) {
      j++;
    }
    e.end = j;
    if (q != null && a != null) e.values = [q.$1, a.$1];
    f.put(e);
    i = j;
  }
  return f;
}

/// 계정 화면 문구는 키마다 [en, ko, ja, ...] 12칸 목록이다. 칸 순서가 언어 순서다.
_FileCopy _scanRows(String path) {
  final lines = File(path).readAsLinesSync();
  final f = _FileCopy(path, lines, 'row');
  for (var i = 0; i < lines.length; i++) {
    final m = RegExp(r"^    '(\w+)': \[\s*$").firstMatch(lines[i]);
    if (m == null) continue;
    final c = _Cursor(lines, i + 1, 0);
    for (var slot = 0; slot < _rowOrder.length; slot++) {
      c.skipBlank();
      final startLine = c.line;
      final v = _concat(c);
      if (v == null) break;
      final e = _Entry(_rowOrder[slot], m.group(1)!, startLine)
        ..end = v.$2
        ..values = [v.$1];
      f.put(e);
      c.skipBlank();
      if (c.ch == ',') c.next();
    }
  }
  return f;
}

_FileCopy _scan(String path) => path == _faqFile
    ? _scanFaq(path)
    : path == _rowFile
        ? _scanRows(path)
        : _scanMaps(path);

// ── 확인 ────────────────────────────────────────────────────────

/// 다시 번역해야 할 한글 키: 한글이 기준과 다르거나, 어떤 언어에 키가 없다.
Map<String, String> _pending(_FileCopy f, Map<String, dynamic> was) {
  final out = <String, String>{};
  for (final e in f.ko.values) {
    final now = e.values == null ? null : jsonEncode(e.values);
    if (now == null) continue;
    final before = was[e.key];
    if (before == null) {
      out[e.key] = '한글 새 키';
    } else if (before != now) {
      out[e.key] = '한글 바뀜';
    } else {
      final missing =
          f.others.where((l) => f.entries[l]![e.key] == null).toList();
      if (missing.isNotEmpty) out[e.key] = '${missing.join(', ')} 없음';
    }
  }
  return out;
}

Map<String, dynamic> _readBaseline() {
  final file = File(_baselinePath);
  return file.existsSync()
      ? jsonDecode(file.readAsStringSync()) as Map<String, dynamic>
      : <String, dynamic>{};
}

void _writeBaseline(Map<String, _FileCopy> all, Map<String, dynamic> base,
    {Set<String>? onlyFiles}) {
  for (final f in all.values) {
    if (onlyFiles != null && !onlyFiles.contains(f.path)) continue;
    base[f.path] = {
      for (final e in f.ko.values)
        if (e.values != null) e.key: jsonEncode(e.values),
    };
  }
  File(_baselinePath).writeAsStringSync(
      '${const JsonEncoder.withIndent('  ').convert(base)}\n');
}

// ── 번역 ────────────────────────────────────────────────────────

Future<Map<String, List<String>>> _translate({
  required String apiKey,
  required String model,
  required String key,
  required List<String> korean,
  required List<String>? oldKorean,
  required Map<String, List<String>?> current,
}) async {
  final targets = {for (final l in current.keys) l: _languageNames[l]!};
  final prompt = StringBuffer()
    ..writeln('You localize UI copy for the StealthVox language-practice app.')
    ..writeln('Korean is the source of truth. For each target language, '
        'rewrite the Korean meaning so it reads naturally to a native speaker '
        'of that language. Do not translate word for word.')
    ..writeln('Rules: keep placeholders such as {n} exactly; keep line breaks '
        '(\\n) where the Korean has them; keep product and feature names in '
        'Latin letters as they are (StealthVox, Duo, Duo Connect, Circle Talk, '
        'Scenario Talk, PRACTICE, ESSAY, Keepers, Snap Echoing, Shadowing, '
        'Origin, Target); keep roughly the Korean length; match the tone and '
        'terminology of the current translation when it is still correct.')
    ..writeln()
    ..writeln('Key: $key')
    ..writeln('Korean now: ${jsonEncode(korean)}');
  if (oldKorean != null) {
    prompt.writeln('Korean before this change: ${jsonEncode(oldKorean)}');
  }
  prompt
    ..writeln('Current translations (null = missing): '
        '${jsonEncode({for (final e in current.entries) e.key: e.value})}')
    ..writeln()
    ..writeln('Each value is a list of ${korean.length} string(s), in the same '
        'order as the Korean list. Answer with one JSON object whose keys are '
        'exactly: ${jsonEncode(targets)} (key = code, value = language).');

  final client = HttpClient();
  try {
    final req = await client
        .postUrl(Uri.parse('https://api.openai.com/v1/chat/completions'));
    req.headers
      ..set(HttpHeaders.authorizationHeader, 'Bearer $apiKey')
      ..contentType = ContentType.json;
    req.add(utf8.encode(jsonEncode({
      'model': model,
      'reasoning_effort': 'low',
      'response_format': {'type': 'json_object'},
      'messages': [
        {'role': 'user', 'content': prompt.toString()},
      ],
    })));
    final res = await req.close();
    final body = await res.transform(utf8.decoder).join();
    if (res.statusCode != 200) {
      throw StateError('번역 요청 실패 ${res.statusCode}: $body');
    }
    final content = (jsonDecode(body)['choices'][0]['message']['content']
        as String);
    final parsed = jsonDecode(content) as Map<String, dynamic>;
    final out = <String, List<String>>{};
    for (final l in current.keys) {
      final v = parsed[l];
      final list = v is String ? [v] : (v as List?)?.cast<String>();
      if (list == null || list.length != korean.length) {
        throw StateError('$key: $l 번역이 비었거나 모양이 다릅니다: $v');
      }
      out[l] = list;
    }
    return out;
  } finally {
    client.close();
  }
}

// ── 써 넣기 ──────────────────────────────────────────────────────

List<String> _render(_FileCopy f, _Entry? old, String lang, String key,
    List<String> values, {required String indent}) {
  switch (f.kind) {
    case 'faq':
      return [
        '$indent[',
        '$indent  ${_dartLiteral(values[0])},',
        '$indent  ${_dartLiteral(values[1])},',
        '$indent],',
      ];
    case 'row':
      return ['$indent${_dartLiteral(values[0])}${old!.comma ? ',' : ''}'];
    default:
      final prefix = old?.prefix ?? "$indent'$key':";
      final lit = _dartLiteral(values[0]);
      final comma = (old?.comma ?? true) ? ',' : '';
      final one = '$prefix $lit$comma';
      if (one.length <= 80) return [one];
      return [prefix, '$indent    $lit$comma'];
  }
}

/// 바뀔 자리를 아래에서 위로 고쳐야 줄 번호가 안 어긋난다.
class _Edit {
  _Edit(this.start, this.end, this.lines);
  final int start; // 지울 첫 줄
  final int end; // 지울 끝 줄 (start-1이면 끼워 넣기만)
  final List<String> lines;
}

void _apply(_FileCopy f, String key, Map<String, List<String>> translated,
    List<_Edit> edits) {
  final koKeys = f.ko.keys.toList();
  for (final t in translated.entries) {
    final lang = t.key;
    final old = f.entries[lang]?[key];
    if (old != null) {
      final indent = ' ' * _indent(f.lines[old.start]);
      edits.add(_Edit(old.start, old.end,
          _render(f, old, lang, key, t.value, indent: indent)));
      continue;
    }
    if (f.kind != 'map') {
      throw StateError('${f.path}: $lang $key 자리가 없어 끼워 넣지 못합니다.');
    }
    // 한글에서 이 키 앞에 있는 키들 중 그 언어에 있는 마지막 키 뒤에 넣는다.
    final block = f.blocks[lang]!;
    var after = block.openLine;
    for (final k in koKeys.sublist(0, koKeys.indexOf(key)).reversed) {
      final prev = f.entries[lang]?[k];
      if (prev != null) {
        after = prev.end;
        break;
      }
    }
    final indent = ' ' * (block.keyIndent < 0 ? 6 : block.keyIndent);
    edits.add(_Edit(after + 1, after,
        _render(f, null, lang, key, t.value, indent: indent)));
  }
}

void _write(_FileCopy f, List<_Edit> edits) {
  final raw = File(f.path).readAsStringSync();
  final nl = raw.contains('\r\n') ? '\r\n' : '\n';
  final lines = [...f.lines];
  edits.sort((a, b) => b.start.compareTo(a.start));
  for (final e in edits) {
    lines.replaceRange(e.start, e.end + 1, e.lines);
  }
  File(f.path).writeAsStringSync(
      lines.join(nl) + (raw.endsWith(nl) ? nl : ''));
}

// ── 실행 ────────────────────────────────────────────────────────

Future<void> main(List<String> args) async {
  final sync = args.contains('--sync');
  final stage = args.contains('--stage');
  final all = {for (final p in copyFiles) p: _scan(p)};

  if (args.contains('--accept')) {
    _writeBaseline(all, <String, dynamic>{});
    print('기준을 지금 한글로 갱신했습니다: $_baselinePath');
    return;
  }

  final base = _readBaseline();
  final pending = {
    for (final f in all.values)
      f.path: _pending(f, (base[f.path] as Map<String, dynamic>?) ?? {}),
  };
  final total = pending.values.fold<int>(0, (n, m) => n + m.length);

  if (!sync) {
    for (final e in pending.entries) {
      print('== ${e.key}${e.value.isEmpty ? '  OK' : ''}');
      e.value.forEach((k, why) => print('  $why  $k'));
    }
    print(total == 0
        ? '\n모든 언어가 한글 기준과 같습니다.'
        : '\n$total건: --sync로 다른 언어를 맞추세요.');
    exit(total == 0 ? 0 : 1);
  }

  if (total == 0) return;
  final apiKey = Platform.environment['OPENAI_API_KEY'] ?? '';
  if (apiKey.isEmpty) {
    stderr.writeln('한글 문구 $total건이 바뀌었는데 OPENAI_API_KEY가 없어 다른 언어를 '
        '맞추지 못했습니다. 키를 넣고 다시 커밋하세요.');
    exit(1);
  }
  final model = Platform.environment['KO_SYNC_MODEL'] ?? 'gpt-6-luna';

  final changed = <String>{};
  for (final f in all.values) {
    final keys = pending[f.path]!;
    if (keys.isEmpty) continue;
    final was = (base[f.path] as Map<String, dynamic>?) ?? {};
    final edits = <_Edit>[];
    for (final key in keys.keys) {
      final ko = f.ko[key]!;
      final before = was[key] == null
          ? null
          : (jsonDecode(was[key] as String) as List).cast<String>();
      stdout.write('  ${f.path.split('/').last} $key … ');
      final translated = await _translate(
        apiKey: apiKey,
        model: model,
        key: key,
        korean: ko.values!,
        oldKorean: before,
        current: {for (final l in f.others) l: f.entries[l]![key]?.values},
      );
      _apply(f, key, translated, edits);
      print('${translated.length}개 언어');
    }
    _write(f, edits);
    changed.add(f.path);
  }

  // 다시 읽어 기준을 갱신한다. 덜 맞춘 키가 남으면 실패.
  final after = {for (final p in copyFiles) p: _scan(p)};
  _writeBaseline(after, base, onlyFiles: changed);
  final left = after.values.fold<int>(
      0,
      (n, f) =>
          n +
          _pending(f, (base[f.path] as Map<String, dynamic>?) ?? {}).length);
  if (left != 0) {
    stderr.writeln('맞춘 뒤에도 $left건이 남았습니다. dart run tool/ko_source_drift.dart로 보세요.');
    exit(1);
  }
  if (stage) {
    await Process.run('git', ['add', ...changed, _baselinePath]);
  }
  print('한글 기준으로 ${changed.length}개 파일을 맞췄습니다.');
}
