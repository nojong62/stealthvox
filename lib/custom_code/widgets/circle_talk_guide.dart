import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

Future<void> showCircleTalkGuide(BuildContext context) {
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
                Row(
                  children: [
                    const Icon(Icons.groups_rounded,
                        color: Color(0xFFB46CFF), size: 30),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'Circle Talk',
                        style: GoogleFonts.poppins(
                          color: Colors.white,
                          fontSize: 21,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.of(dialogContext).pop(),
                      icon: const Icon(Icons.close_rounded,
                          color: Colors.white54),
                      tooltip: '닫기',
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                const Flexible(
                  child: SingleChildScrollView(
                    physics: BouncingScrollPhysics(),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '관심사나 직업, 커뮤니티를 직접 만들고 AI와 대화하는 모드입니다.',
                          style: TextStyle(
                              color: Colors.white,
                              fontSize: 15,
                              height: 1.55,
                              fontWeight: FontWeight.w600),
                        ),
                        SizedBox(height: 14),
                        Text(
                          '원하는 서클을 입력하면 AI는 그 서클의 구성원이 되어 분위기와 말투, 관심사를 반영해 자연스럽게 대화합니다.',
                          style: TextStyle(
                              color: Colors.white70,
                              fontSize: 14,
                              height: 1.55),
                        ),
                        SizedBox(height: 22),
                        _CircleGuideHeading('예시'),
                        SizedBox(height: 10),
                        _CircleGuideExample('인도 수출 무역회사'),
                        _CircleGuideExample('스타트업 개발팀'),
                        _CircleGuideExample('주식 트레이더 모임'),
                        _CircleGuideExample('병원 의료진'),
                        _CircleGuideExample('자동차 동호회'),
                        SizedBox(height: 12),
                        Text(
                          '또는 원하는 서클을 직접 만들어 사용할 수도 있습니다.',
                          style: TextStyle(
                              color: Colors.white70, fontSize: 14, height: 1.5),
                        ),
                        SizedBox(height: 22),
                        _CircleGuideHeading('이용 팁'),
                        SizedBox(height: 10),
                        _CircleGuideTip('실제 동료와 이야기하듯 편하게 대화하세요.'),
                        _CircleGuideTip('업계 용어나 관심사에 맞는 표현을 자유롭게 사용해 보세요.'),
                        _CircleGuideTip(
                            '대화가 이어질수록 AI는 서클의 맥락을 반영해 더욱 자연스럽게 대화합니다.'),
                        SizedBox(height: 22),
                        Text(
                          '당신만의 서클을 만들고, 그 안에서 자연스러운 영어 대화를 경험해 보세요.',
                          style: TextStyle(
                              color: Color(0xFFD2A7FF),
                              fontSize: 14,
                              height: 1.55,
                              fontWeight: FontWeight.w700),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

class _CircleGuideHeading extends StatelessWidget {
  const _CircleGuideHeading(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Text(
        text,
        style: const TextStyle(
          color: Color(0xFFB46CFF),
          fontSize: 15,
          fontWeight: FontWeight.bold,
        ),
      );
}

class _CircleGuideExample extends StatelessWidget {
  const _CircleGuideExample(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Row(
          children: [
            const Icon(Icons.circle, color: Colors.white38, size: 5),
            const SizedBox(width: 9),
            Expanded(
              child: Text(text,
                  style: const TextStyle(
                      color: Colors.white70, fontSize: 14, height: 1.4)),
            ),
          ],
        ),
      );
}

class _CircleGuideTip extends StatelessWidget {
  const _CircleGuideTip(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 9),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Padding(
              padding: EdgeInsets.only(top: 2),
              child: Icon(Icons.check_circle_outline_rounded,
                  color: Color(0xFFB46CFF), size: 17),
            ),
            const SizedBox(width: 9),
            Expanded(
              child: Text(text,
                  style: const TextStyle(
                      color: Colors.white70, fontSize: 14, height: 1.45)),
            ),
          ],
        ),
      );
}
