// ⏸️ [CHIRP-PAUSE] Chirp 3 HD의 pause control markup.
//
//   쉐도잉·Snap Echoing의 호흡 사이 여유를 **TTS가 직접 쉬게** 만든다. 예전
//   에는 소리를 받은 뒤 호흡 경계에 무음을 끼워 넣었다(`buildGappedPcm`).
//
//   태그는 문장부호 뒤에만 넣는다 — 문장부호 없는 긴 구절 안에는 넣지 않는다.
//   호흡 경계 자체는 여전히 소리의 무음으로 찾는다(`analyzeBreaths`).
//   Gateway는 이 문자열을 `markup` 칸으로 받아 Chirp에만 쓰고, OpenAI로
//   넘길 때는 지운다.

enum ChirpPause { short, medium, long }

extension ChirpPauseTag on ChirpPause {
  String get tag {
    switch (this) {
      case ChirpPause.short:
        return '[pause short]';
      case ChirpPause.medium:
        return '[pause]';
      case ChirpPause.long:
        return '[pause long]';
    }
  }
}

// 반각 문장부호는 뒤에 공백이 있을 때만 경계로 본다("3.5", "e.g." 보호).
// 전각·데바나가리 문장부호는 공백 없이 이어 쓰므로 공백을 요구하지 않는다.
final RegExp _halfWidthBreak = RegExp(r'([,;:.!?])\s+(?=\S)');
final RegExp _fullWidthBreak = RegExp(r'([，、；：。！？।])\s*(?=\S)');

// MY STORY는 한 줄 = 한 호흡이다(2026-11-08). 문장부호 없이 끝나는 줄도 쉰다.
final RegExp _lineBreak = RegExp(r'[ \t]*\r?\n\s*');

/// [text]의 문장부호 뒤·줄 끝마다 [pause] 태그를 넣는다. 맨 끝에는 넣지 않는다.
/// 이미 대괄호가 있는 문장은 그대로 돌려준다 — 태그로 오인될 수 있다.
String chirpPauseMarkup(String text, ChirpPause pause) {
  final input = text.trim();
  if (input.isEmpty || input.contains('[') || input.contains(']')) {
    return input;
  }
  final tag = pause.tag;
  // 문장부호 뒤의 줄바꿈은 아래 두 규칙이 먹는다. 남는 줄바꿈은 문장부호
  // 없이 끝난 줄이고, 거기에도 쉼을 넣는다.
  return input
      .replaceAllMapped(_halfWidthBreak, (m) => '${m[1]} $tag ')
      .replaceAllMapped(_fullWidthBreak, (m) => '${m[1]} $tag ')
      .replaceAll(_lineBreak, ' $tag ');
}
