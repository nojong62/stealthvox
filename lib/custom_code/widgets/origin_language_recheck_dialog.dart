// ====================================================================
// 🌐 [ORIGIN-RECHECK] "지금 말씀하시는 언어가 설정과 다릅니다" 확인 창
// --------------------------------------------------------------------
// 로비에서 미리 고른 대화 언어(ORIGIN)와 실제 첫 발화의 언어가 다를 때 뜬다.
// 하는 일은 둘뿐이다.
//   ① 감지된 언어로 "재설정하셔도 됩니다"라고 알린다
//   ② 그 자리에서 로비와 **같은 언어 설정**을 다시 고르게 한다
//
// 🚫 **여기서는 아무것도 저장하지 않는다.** 고른 값을 [OriginLanguageRecheckResult]
//   로 돌려줄 뿐이고, prefs·전사 소켓·히스토리 문서를 건드리는 일은 전부
//   호출한 모드가 한다. 모드마다 뒤처리가 다르기 때문이다(서클톡은 전사
//   소켓만, 듀오는 통역 방향까지 갈아 끼운다).
//
// 📐 모양은 듀오의 게스트 언어 오버레이와 같다 — 유저가 이미 한 번 본 화면이라
//   무엇을 고르는 자리인지 따로 설명할 필요가 없다.
//
// ⚠️ 대화를 끊지 않는다. 이 막 뒤에서 마이크도 재생도 계속 돈다.
// ====================================================================

import 'package:flutter/material.dart';

import '/custom_code/services/origin_language_session.dart'
    show kOriginLanguageOptions;
import 'first_utterance_context_judge.dart';

/// 창에서 유저가 고른 결과. 닫기만 했으면 호출부가 null을 받는다.
class OriginLanguageRecheckResult {
  const OriginLanguageRecheckResult({
    required this.applied,
    required this.native,
    required this.target,
  });

  /// 확정 버튼을 눌렀는가. false면 "그대로 두기"다.
  final bool applied;

  /// 고른 대화 언어(ORIGIN). [applied]가 false면 의미 없다.
  final String native;

  /// 🎯 고른 배울 언어(TARGET). **만졌을 때만 값이 있다.**
  ///
  /// 안 만졌는데 표시값을 되쓰면 두 가지가 조용히 망가진다.
  ///   ① 목록(12개) 밖의 배울 언어를 쓰던 사람은 기본값으로 덮인다
  ///   ② 바꾸지도 않은 값이 prefs에 다시 쓰인다
  /// 이 창은 ORIGIN을 고치자고 띄운 것이지 배울 언어를 건드리자는 것이 아니다.
  final String? target;
}

/// 언어 확인 창을 띄운다.
///
/// [detected]는 첫 발화에서 판정된 언어다. 창의 모든 글자를 **이 언어로** 적는다
/// — 로비값으로 적으면 정작 읽어야 할 사람이 못 읽는다.
/// [currentNative]/[currentTarget]은 드롭다운의 시작값이며, ORIGIN 자리에는
/// 감지된 언어를 미리 골라 둔다(보통 그대로 확정만 누르면 끝나야 한다).
Future<OriginLanguageRecheckResult?> showOriginLanguageRecheckDialog({
  required BuildContext context,
  required String detected,
  required String currentNative,
  required String currentTarget,
}) {
  const List<String> langs = kOriginLanguageOptions;
  String native = langs.contains(detected)
      ? detected
      : (langs.contains(currentNative) ? currentNative : 'Korean');
  String target = langs.contains(currentTarget) ? currentTarget : 'English';
  bool targetTouched = false;

  return showDialog<OriginLanguageRecheckResult>(
    context: context,
    // 대화는 뒤에서 계속 돈다. 빈 곳을 눌러 흘려보내지 못하게 막아 둔다 —
    // 지나가면 같은 세션에서 다시 뜨지 않는다(안내 슬롯은 한 번뿐이다).
    barrierDismissible: false,
    barrierColor: Colors.black.withValues(alpha: 0.78),
    builder: (dialogContext) => StatefulBuilder(
      builder: (context, setLocal) {
        Widget dropdown(String label, String value, Color color,
            ValueChanged<String?> onChanged) {
          return Row(
            children: [
              SizedBox(
                width: 92,
                child: Text(label,
                    style: TextStyle(
                        color: color,
                        fontSize: 14,
                        fontWeight: FontWeight.w600)),
              ),
              Expanded(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  decoration: BoxDecoration(
                      color: const Color(0xFF2C2C2E),
                      borderRadius: BorderRadius.circular(10)),
                  child: DropdownButton<String>(
                    value: value,
                    isExpanded: true,
                    underline: const SizedBox.shrink(),
                    dropdownColor: const Color(0xFF2C2C2E),
                    style: const TextStyle(color: Colors.white, fontSize: 15),
                    items: langs
                        .map((l) =>
                            DropdownMenuItem<String>(value: l, child: Text(l)))
                        .toList(),
                    onChanged: onChanged,
                  ),
                ),
              ),
            ],
          );
        }

        return Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: const EdgeInsets.symmetric(horizontal: 28),
          child: SingleChildScrollView(
            child: Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                  color: const Color(0xFF1C1C1E),
                  borderRadius: BorderRadius.circular(20),
                  border:
                      Border.all(color: const Color(0xFFF59E0B), width: 1.5)),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(originLanguageCheckPromptLine(detected),
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 17,
                          fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  Text(originLanguageResetHintLine(detected),
                      style: const TextStyle(
                          color: Colors.white54, fontSize: 13, height: 1.35)),
                  const SizedBox(height: 22),
                  dropdown("Original", native, const Color(0xFF93C5FD), (val) {
                    if (val != null) setLocal(() => native = val);
                  }),
                  const SizedBox(height: 18),
                  dropdown("Target", target, const Color(0xFF4ADE80), (val) {
                    if (val == null) return;
                    setLocal(() {
                      target = val;
                      targetTouched = true;
                    });
                  }),
                  const SizedBox(height: 26),
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF2563EB),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12))),
                    onPressed: () => Navigator.of(dialogContext).pop(
                      OriginLanguageRecheckResult(
                        applied: true,
                        native: native,
                        // 만지지 않은 Target은 넘기지 않는다(null = 그대로 둔다).
                        target: targetTouched ? target : null,
                      ),
                    ),
                    child: Text(originLanguageApplyLabel(detected),
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.bold)),
                  ),
                  const SizedBox(height: 10),
                  TextButton(
                    onPressed: () => Navigator.of(dialogContext).pop(
                      OriginLanguageRecheckResult(
                          applied: false, native: native, target: null),
                    ),
                    child: Text(originLanguageKeepLabel(detected),
                        style: const TextStyle(
                            color: Colors.white70, fontSize: 15)),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    ),
  );
}
