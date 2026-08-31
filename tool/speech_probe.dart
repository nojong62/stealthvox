// 🗣️ My English → Native English를 **실기기 없이** 돌려 보는 도구.
//
//   flutter test tool/speech_probe.dart
//
// 왜 flutter test인가. probe는 프롬프트를 베끼지 않고 **앱이 실제로 쓰는
// 함수**(`MySpeechBuilder` · `NativeEnglishSpeechBuilder`)를 그대로 부른다.
// 그 사슬이 `ai_style.dart → app_state.dart → package:flutter`까지 닿아서
// 순수 Dart VM(`dart run`)으로는 못 띄운다. 그래서 Flutter가 딸린 러너를
// 빌려 쓴다 — 시험이 아니라 도구다. `test/`가 아니라 `tool/`에 있는 이유다.
//
// 🔑 키는 **환경변수로만** 받는다. 명령줄 인자로 두면 셸 히스토리·프로세스
//    목록에 남는다.
//
//      PowerShell  $env:OPENAI_API_KEY = "..."      (그 창에서만 산다)
//      bash        export OPENAI_API_KEY=...
//      파일로 두려면  tool/.openai_key  (.gitignore에 있다)
//
// 넣는 글: 한 줄에 한 발화. 누가 유저인지만 가르면 된다.
//
//      USER: 나 방금 집에 왔어.
//      OTHER: 오늘 늦었네요.
//      USER: 내일 일찍 일어나야 돼.
//
//   앞의 이름은 USER / HOST / ME 가 유저이고, 나머지(OTHER · GUEST · AI ·
//   SYSTEM)는 상대다. `#`으로 시작하는 줄과 빈 줄은 건너뛴다.
//
// 손잡이는 전부 환경변수다(`flutter test`가 임의 인자를 안 넘겨준다).
//
//   SPEECH_PROBE_INPUT     넣을 파일. 기본 tool/speech_samples/short_evening.txt
//   SPEECH_PROBE_RUNS      같은 글로 몇 번 뽑을지. 기본 1.
//                          **temperature를 볼 때 이걸 3으로 준다** — 한 번
//                          뽑아서는 0.6이 넓은지 좁은지 알 수 없다.
//   SPEECH_PROBE_LANG      타겟 언어. 기본 English.
//   SPEECH_PROBE_USER      유저 이름(선택). 프롬프트의 `USER is ...`에 박힌다.
//   SPEECH_PROBE_PARTNER   상대 이름(선택).
//   SPEECH_PROBE_SITUATION 상황 한 줄(선택). Scenario Talk 방을 흉내 낼 때.
//   SPEECH_PROBE_DRY       1이면 모델을 부르지 않고 대화록과 프롬프트만 본다.
//
// ⚠️ **로비 AI STYLE은 Standard로 고정된다.** 스타일은 `FFAppState`가 들고
//    있고 그 setter가 SharedPreferences를 건드려 러너에서 터진다. 기본값이자
//    대다수 유저의 값인 Standard만 여기서 본다. American·British·Native는
//    실기기로 봐야 한다.
//
// 내는 것: 대화록 · My English · Native English · 두 글의 길이와 문장 수.
// **판단은 사람이 한다.** 통과·실패를 매기지 않는다.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:stealth_vox/custom_code/services/speech_reconstruction.dart';

const String _defaultInput = 'tool/speech_samples/short_evening.txt';

/// 유저 줄로 치는 이름들. 나머지는 전부 상대다.
const Set<String> _userLabels = <String>{'USER', 'HOST', 'ME', '나'};

void main() {
  test('speech probe', () async {
    // 러너가 깔아 두는 가짜 HttpClient를 걷어낸다. 안 걷으면 OpenAI 호출이
    // 전부 400으로 돌아온다 — 시험이 아니라 도구이므로 진짜 망을 탄다.
    //
    // **본문 안에서 지운다.** main()에서 지우면 그 뒤에 바인딩이 늦게 올라오며
    // 다시 깔 수 있다. 호출 직전에 비어 있는 것이 확실해야 한다.
    HttpOverrides.global = null;

    final env = Platform.environment;
    final path = (env['SPEECH_PROBE_INPUT'] ?? _defaultInput).trim();
    final file = File(path);
    if (!file.existsSync()) {
      stdout.writeln('넣을 파일이 없다: $path');
      return;
    }

    final turns = _readTranscript(file);
    if (turns.isEmpty) {
      stdout.writeln('$path: 읽을 발화가 없다');
      return;
    }
    if (!hasUserTurn(turns)) {
      stdout.writeln('$path: 유저 줄이 하나도 없다 — My English는 성립하지 않는다');
      return;
    }

    final lang = (env['SPEECH_PROBE_LANG'] ?? 'English').trim();
    final userLabel = (env['SPEECH_PROBE_USER'] ?? '').trim();
    final partnerLabel = (env['SPEECH_PROBE_PARTNER'] ?? '').trim();
    final situation = (env['SPEECH_PROBE_SITUATION'] ?? '').trim();
    final runs = int.tryParse(env['SPEECH_PROBE_RUNS'] ?? '') ?? 1;
    final dry = (env['SPEECH_PROBE_DRY'] ?? '').trim() == '1';

    stdout.writeln('\n══════ $path ══════');
    _section('CONVERSATION SEED (${turns.length}줄)');
    for (final turn in turns) {
      stdout.writeln('  ${turn.isUser ? 'USER ' : 'OTHER'}  ${turn.text}');
    }

    if (dry) {
      _section('MY ENGLISH 지시문');
      stdout.writeln(buildMySpeechInstructions(
        targetLang: lang,
        userLabel: userLabel,
        partnerLabel: partnerLabel,
        situation: situation,
      ));
      stdout.writeln('\n(SPEECH_PROBE_DRY=1: 모델을 부르지 않는다)');
      return;
    }

    final key = _readKey();
    if (key.isEmpty) {
      stdout.writeln('\n키가 없다. OPENAI_API_KEY 환경변수를 두거나 '
          'tool/.openai_key 파일에 넣을 것.');
      return;
    }

    for (var run = 1; run <= runs; run++) {
      if (runs > 1) stdout.writeln('\n\n░░░░░░ RUN $run / $runs ░░░░░░');

      final my = await MySpeechBuilder.build(
        apiKey: key,
        turns: turns,
        targetLang: lang,
        userLabel: userLabel,
        partnerLabel: partnerLabel,
        situation: situation,
      );
      if (!my.isUsable) {
        stdout.writeln('\n❌ MY ENGLISH 실패 — ${my.failure.name}');
        continue;
      }
      _section('MY ENGLISH  ${_shape(my.text)}');
      stdout.writeln(_wrap(my.text));

      final native = await NativeEnglishSpeechBuilder.build(
        apiKey: key,
        mySpeech: my.text,
      );
      if (!native.isUsable) {
        stdout.writeln('\n❌ NATIVE ENGLISH 실패 — ${native.failure.name}');
        continue;
      }
      _section('NATIVE ENGLISH  ${_shape(native.text)}');
      stdout.writeln(_wrap(native.text));

      // 두 글이 같으면 나란히 놓을 이유가 사라진다. 앱도 같은 값을 버린다.
      if (native.text.trim() == my.text.trim()) {
        stdout.writeln('\n  ⚠ 두 글이 같다 — 앱이라면 이 Native English는 버려진다');
      }
    }

    _section('볼 것');
    stdout.writeln('  · 원 대화와 어긋나는 말이 들어갔는가 (모순은 유일한 금지선이다)');
    stdout.writeln('  · 대화에 없던 이름·장소·숫자·회사·돈이 생겼는가');
    stdout.writeln('  · 대화 요약이 되어 버렸는가, 질문-답변을 이어 붙였는가');
    stdout.writeln('  · 내가 실제로 다시 쓸 만한 말인가');
    stdout.writeln('  · RUNS를 여러 번 줬다면 — 매번 너무 달라지는가(온도가 높다),');
    stdout.writeln('    아니면 원문에 붙어 거의 안 늘어나는가(온도가 낮다)');
  }, timeout: const Timeout(Duration(minutes: 5)));
}

/// 키를 읽는 자리는 여기 하나뿐이다. **화면에도 로그에도 찍지 않는다.**
String _readKey() {
  final env = (Platform.environment['OPENAI_API_KEY'] ?? '').trim();
  if (env.isNotEmpty) return env;
  final file = File('tool/.openai_key');
  if (file.existsSync()) return file.readAsStringSync().trim();
  return '';
}

List<SpeechTranscriptTurn> _readTranscript(File file) {
  final out = <SpeechTranscriptTurn>[];
  for (final raw in file.readAsLinesSync()) {
    final line = raw.trim();
    if (line.isEmpty || line.startsWith('#')) continue;
    final sep = line.indexOf(':');
    if (sep <= 0) continue;
    final who = line.substring(0, sep).trim().toUpperCase();
    final body = line.substring(sep + 1).trim();
    if (body.isEmpty) continue;
    out.add(
        SpeechTranscriptTurn(isUser: _userLabels.contains(who), text: body));
  }
  return out;
}

/// 길이와 문장 수. 확장이 실제로 일어났는지 눈으로 재는 자다.
String _shape(String text) {
  final words = text.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).length;
  final sentences =
      text.split(RegExp(r'[.!?]+\s')).where((s) => s.trim().isNotEmpty).length;
  return '($words words · $sentences sentences)';
}

/// 터미널에서 읽히게 접는다. 글자는 건드리지 않는다.
String _wrap(String text, {int width = 76}) {
  final out = StringBuffer();
  var col = 0;
  for (final word in text.split(RegExp(r'\s+'))) {
    if (word.isEmpty) continue;
    if (col == 0) {
      out.write('  $word');
      col = word.length + 2;
    } else if (col + word.length + 1 > width) {
      out.write('\n  $word');
      col = word.length + 2;
    } else {
      out.write(' $word');
      col += word.length + 1;
    }
  }
  return out.toString();
}

void _section(String title) {
  final bar = '─' * (52 - title.length).clamp(0, 52);
  stdout.writeln('\n── $title $bar');
}
