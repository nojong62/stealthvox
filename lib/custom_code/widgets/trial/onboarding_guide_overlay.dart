import 'package:flutter/material.dart';
import '/flutter_flow/flutter_flow_util.dart';

import 'trial_flow_state.dart';

class OnboardingGuideOverlay {
  static Future<void> show(
    BuildContext context, {
    required VoidCallback onStart,
  }) async {
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      isDismissible: false,
      enableDrag: false,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setState) {
            return Container(
              margin: const EdgeInsets.only(top: 80),
              decoration: const BoxDecoration(
                color: Color(0xFF1A1A2E),
                borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
              ),
              padding: const EdgeInsets.fromLTRB(24, 32, 24, 40),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                    decoration: BoxDecoration(
                      color: const Color(0xFF2A2A3E),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: const Text(
                      '처음 오셨나요',
                      style: TextStyle(
                        color: Color(0xFFD4AF37),
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    '30초 동안 Anyone 모드를\n체험해 보세요',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      height: 1.35,
                    ),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    '대화가 끝나면 방금 그 대화가\n영어 교재로 바뀝니다.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Color(0xFFB0B0B0), fontSize: 14),
                  ),
                  const SizedBox(height: 32),
                  SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFD4AF37),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      onPressed: () {
                        TrialFlowState.instance.advanceTo(1);
                        Navigator.pop(ctx);
                        onStart();
                      },
                      child: const Text(
                        '시작 →',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    '🎙 마이크를 사용합니다',
                    style: TextStyle(color: Color(0xFF999999), fontSize: 12),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }
}
