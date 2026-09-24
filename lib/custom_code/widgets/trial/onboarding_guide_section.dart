import 'package:flutter/material.dart';

class OnboardingGuideSection extends StatelessWidget {
  const OnboardingGuideSection({super.key});

  @override
  Widget build(BuildContext context) {
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
            child: const Text(
              'New Here?',
              style: TextStyle(
                color: Color(0xFF5DCAA5),
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const SizedBox(height: 14),
          const Text(
            'Try a 10-minute\nDuo call with\na friend',
            style: TextStyle(
              color: Colors.white,
              fontSize: 17,
              fontWeight: FontWeight.bold,
              height: 1.35,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'After the call, review it for 5 minutes.\nOne trial per device.',
            style: TextStyle(color: Color(0xFFB0B0B0), fontSize: 13),
          ),
          const SizedBox(height: 10),
          const Row(
            children: [
              Icon(Icons.mic_none, size: 14, color: Color(0xFF999999)),
              SizedBox(width: 6),
              Text(
                'Microphone Required',
                style: TextStyle(color: Color(0xFF999999), fontSize: 12),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
