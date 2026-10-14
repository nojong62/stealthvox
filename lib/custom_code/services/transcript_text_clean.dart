// 🔤 전사문 잡음 판정에서 **글자로 남길 것**의 기준.
//
// 예전에는 여섯 곳이 `RegExp(r'[^\w\s가-힣]')`를 따로 들고 있었다. Dart의
// `\w`는 유니코드가 아니라 ASCII [A-Za-z0-9_]라서 가나·한자·키릴·데바나가리가
// 전부 지워졌다. 일본어 한 문장이 빈 문자열이 되어 서클톡은 "2글자 미만 =
// 잡음"으로, Duo는 `empty_after_clean`으로 버렸다(2026-10-14 실기기,
// `[NOISE-GATE] dropped=true len=32`).
//
// 문자(모든 문자 체계)·숫자·공백만 남기고 문장부호·기호를 지운다.

/// 문자·숫자·공백이 **아닌** 것. `replaceAll(..., '')`로 지우는 데 쓴다.
final RegExp kTranscriptNonLetterPattern =
    RegExp(r'[^\p{L}\p{N}\s]', unicode: true);
