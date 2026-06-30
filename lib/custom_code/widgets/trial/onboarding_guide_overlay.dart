import 'package:flutter/material.dart';
import '/flutter_flow/flutter_flow_util.dart';

import 'trial_flow_state.dart';

class OnboardingGuideOverlay {
  static Future<void> show(
    BuildContext context, {
    required VoidCallback onStart,
  }) async {
    String nativeLang =
        FFAppState().nativeLang.isNotEmpty ? FFAppState().nativeLang : 'Korean';
    String targetLang = FFAppState().targetLang.isNotEmpty
        ? FFAppState().targetLang
        : 'English';

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
                  const Text(
                    'Try a real conversation for 30 seconds.',
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
                    'After that, StealthVox turns your chat into study material.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Color(0xFFB0B0B0), fontSize: 14),
                  ),
                  const SizedBox(height: 28),
                  _langRow(
                    label: 'Native',
                    value: nativeLang,
                    items: const [
                      'Korean',
                      'English',
                      'Japanese',
                      'Chinese',
                      'Spanish'
                    ],
                    onChanged: (v) => setState(() => nativeLang = v),
                  ),
                  const SizedBox(height: 12),
                  _langRow(
                    label: 'Learn',
                    value: targetLang,
                    items: const [
                      'English',
                      'Korean',
                      'Japanese',
                      'Chinese',
                      'Spanish'
                    ],
                    onChanged: (v) => setState(() => targetLang = v),
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
                        FFAppState().nativeLang = nativeLang;
                        FFAppState().targetLang = targetLang;
                        TrialFlowState.instance.advanceTo(1);
                        Navigator.pop(ctx);
                        onStart();
                      },
                      child: const Text(
                        'Start',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  static Widget _langRow({
    required String label,
    required String value,
    required List<String> items,
    required ValueChanged<String> onChanged,
  }) {
    final effectiveValue = items.contains(value) ? value : items.first;
    return Row(
      children: [
        SizedBox(
          width: 72,
          child: Text(
            label,
            style: const TextStyle(color: Color(0xFF999999), fontSize: 13),
          ),
        ),
        Expanded(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              color: const Color(0xFF2A2A3E),
              borderRadius: BorderRadius.circular(8),
            ),
            child: DropdownButton<String>(
              value: effectiveValue,
              isExpanded: true,
              dropdownColor: const Color(0xFF2A2A3E),
              underline: const SizedBox(),
              style: const TextStyle(color: Colors.white, fontSize: 15),
              items: items
                  .map((e) => DropdownMenuItem(value: e, child: Text(e)))
                  .toList(),
              onChanged: (v) {
                if (v != null) onChanged(v);
              },
            ),
          ),
        ),
      ],
    );
  }
}
