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
              '처음 오셨나요',
              style: TextStyle(
                color: Color(0xFF5DCAA5),
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const SizedBox(height: 14),
          const Text(
            '30초 동안\nAnyone 모드를\n체험해 보세요',
            style: TextStyle(
              color: Colors.white,
              fontSize: 17,
              fontWeight: FontWeight.bold,
              height: 1.35,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            '대화가 끝나면 방금 그 대화가\n영어 교재로 바뀝니다.',
            style: TextStyle(color: Color(0xFFB0B0B0), fontSize: 13),
          ),
          const SizedBox(height: 10),
          const Row(
            children: [
              Icon(Icons.mic_none, size: 14, color: Color(0xFF999999)),
              SizedBox(width: 6),
              Text(
                '마이크를 사용합니다',
                style: TextStyle(color: Color(0xFF999999), fontSize: 12),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
