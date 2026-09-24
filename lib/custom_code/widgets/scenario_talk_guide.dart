import 'package:flutter/material.dart';
import '/app_state.dart';
import '/custom_code/services/guide_ui_localization.dart';

const Color kScenarioGuideAccent = Color(0xFF4ADE80);

Future<void> showScenarioTalkGuide(BuildContext context) {
  final copy = GuideUiCopy.forLanguage(FFAppState().nativeLang);
  return showDialog<void>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      backgroundColor: const Color(0xFF1A1A1A),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      title: Row(children: [
        const Icon(Icons.menu_book_rounded, color: kScenarioGuideAccent),
        const SizedBox(width: 10),
        Expanded(
            child: Text(copy['scenarioTitle'],
                style: const TextStyle(color: Colors.white, fontSize: 18))),
      ]),
      content: SingleChildScrollView(
        child: Text(copy['scenarioBody'],
            style: const TextStyle(
                color: Colors.white70, fontSize: 14, height: 1.55)),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(),
          child: Text(copy['confirm'],
              style: const TextStyle(color: kScenarioGuideAccent)),
        ),
      ],
    ),
  );
}
