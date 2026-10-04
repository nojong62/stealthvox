import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '/app_state.dart';
import '/custom_code/services/guide_ui_localization.dart';

Future<void> showCircleTalkGuide(BuildContext context) {
  final copy = GuideUiCopy.forSystemLocale();
  return showDialog<void>(
    context: context,
    barrierDismissible: true,
    builder: (dialogContext) => BackdropFilter(
      filter: ImageFilter.blur(sigmaX: 5, sigmaY: 5),
      child: Dialog(
        backgroundColor: const Color(0xFF1C1C1E),
        insetPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 28),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520, maxHeight: 680),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 24, 24, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  const Icon(Icons.groups_rounded,
                      color: Color(0xFFB46CFF), size: 30),
                  const SizedBox(width: 12),
                  Expanded(
                      child: Text(copy['circleTitle'],
                          style: GoogleFonts.poppins(
                              color: Colors.white,
                              fontSize: 21,
                              fontWeight: FontWeight.bold))),
                  IconButton(
                      onPressed: () => Navigator.of(dialogContext).pop(),
                      icon: const Icon(Icons.close_rounded,
                          color: Colors.white54),
                      tooltip: copy['close']),
                ]),
                const SizedBox(height: 16),
                Flexible(
                    child: SingleChildScrollView(
                  physics: const BouncingScrollPhysics(),
                  child: Text(copy['circleBody'],
                      style: const TextStyle(
                          color: Colors.white70, fontSize: 14, height: 1.55)),
                )),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}
