// ════════════════════════════════════════════════════════════════════
// 💡 [NATIVE-EXPR] "현지인 표현" 버튼과 팝업
// --------------------------------------------------------------------
// 확정된 방에서 연필 자리에 온다. 누를 때마다 새 표현을 받아 띄운다.
// - 팝업을 가볍게 누르면 닫힌다(바깥도 마찬가지).
// - 꾹 누르면 Keepers에 저장하고 닫힌다.
// 생성 규칙은 `services/native_expression.dart`에 있다.
// ════════════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';

import '/custom_code/services/native_expression.dart';
import '/custom_code/services/origin_surface_localization.dart';

const Color kNativeExprAccent = Color(0xFFFBBF24);

Widget buildNativeExpressionButton({required VoidCallback onPressed}) {
  final copy = OriginSurfaceCopy.forSystemLocale();
  return IconButton(
    padding: const EdgeInsets.all(8),
    constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
    icon: const Icon(Icons.lightbulb_outline_rounded,
        color: kNativeExprAccent, size: 24),
    onPressed: onPressed,
    tooltip: copy['nativeExpression'],
  );
}

/// [future]가 끝나면 표현을 보여 준다. 꾹 누르면 [onKeep]을 부르고 닫는다.
void showNativeExpressionPopup({
  required BuildContext context,
  required Future<NativeExpression?> future,
  required void Function(NativeExpression expression) onKeep,
}) {
  final copy = OriginSurfaceCopy.forSystemLocale();
  NativeExpression? loaded;
  showDialog<void>(
    context: context,
    barrierDismissible: true,
    builder: (dialogContext) => GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => Navigator.of(dialogContext).pop(),
      onLongPress: () {
        final expr = loaded;
        if (expr == null) return;
        Navigator.of(dialogContext).pop();
        onKeep(expr);
      },
      child: Dialog(
        backgroundColor: const Color(0xFF1E1E1E),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(dialogContext).size.height * 0.75,
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
            child: FutureBuilder<NativeExpression?>(
              future: future,
              builder: (ctx, snapshot) {
                if (snapshot.connectionState != ConnectionState.done) {
                  return const SizedBox(
                    height: 90,
                    child: Center(
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: kNativeExprAccent),
                    ),
                  );
                }
                final expr = snapshot.data;
                loaded = expr;
                return Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.lightbulb_rounded,
                            color: kNativeExprAccent, size: 18),
                        const SizedBox(width: 6),
                        Text(
                          copy['nativeExpression'],
                          style: const TextStyle(
                            color: kNativeExprAccent,
                            fontSize: 15,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    if (expr == null)
                      Text(
                        copy['nativeExpressionFailed'],
                        style: const TextStyle(
                            color: Colors.white70, fontSize: 14),
                      )
                    else
                      Flexible(
                        child: SingleChildScrollView(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                expr.expression,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                  height: 1.35,
                                ),
                              ),
                              if (expr.meaning.isNotEmpty) ...[
                                const SizedBox(height: 6),
                                Text(
                                  expr.meaning,
                                  style: const TextStyle(
                                    color: Colors.white70,
                                    fontSize: 14,
                                    height: 1.35,
                                  ),
                                ),
                              ],
                              if (expr.usage.isNotEmpty) ...[
                                const SizedBox(height: 12),
                                Text(
                                  expr.usage,
                                  style: const TextStyle(
                                    color: Colors.white54,
                                    fontSize: 13,
                                    height: 1.45,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ),
                    const SizedBox(height: 14),
                    Center(
                      child: Text(
                        expr == null
                            ? copy['tapToClose']
                            : copy['nativeExpressionHint'],
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                            color: Colors.white24, fontSize: 11),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    ),
  );
}
