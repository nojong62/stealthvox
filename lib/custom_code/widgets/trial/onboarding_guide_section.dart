import 'package:flutter/material.dart';
import '/flutter_flow/flutter_flow_util.dart';
import '/custom_code/services/origin_surface_localization.dart';

class OnboardingGuideSection extends StatelessWidget {
  const OnboardingGuideSection({super.key});

  @override
  Widget build(BuildContext context) {
    final copy = OriginSurfaceCopy.forSystemLocale();
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 20),
      decoration: BoxDecoration(
        color: const Color(0xFF222222),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
            decoration: BoxDecoration(
              color: const Color(0xFF2A2A3E),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              copy['newHere'],
              style: TextStyle(
                color: Color(0xFF5DCAA5),
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const SizedBox(height: 14),
          Text(
            copy['tryDuoTrial'],
            style: TextStyle(
              color: Colors.white,
              fontSize: 17,
              fontWeight: FontWeight.bold,
              height: 1.35,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            copy['trialReview'],
            style: TextStyle(color: Color(0xFFB0B0B0), fontSize: 13),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              const Icon(Icons.mic_none, size: 14, color: Color(0xFF999999)),
              SizedBox(width: 6),
              Text(
                copy['microphoneRequired'],
                style: TextStyle(color: Color(0xFF999999), fontSize: 12),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
