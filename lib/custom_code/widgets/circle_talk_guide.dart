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
                        _CircleGuideHeading('Step 1 · Step 2'),
                        SizedBox(height: 10),
                        Text(
                          'Step 1은 지금까지의 대화방 그대로입니다. AI도 나와 같은 대화 언어로 말합니다. 방에 들어오면 늘 Step 1로 시작합니다.',
                          style: TextStyle(
                              color: Colors.white70,
                              fontSize: 14,
                              height: 1.55),
                        ),
                        SizedBox(height: 10),
                        Text(
                          '대화 중 아래의 Step 1 단추를 누르면 다음 대화부터 Step 2가 됩니다. AI만 로비에서 고른 배울 언어로 말하고, 나는 계속 내 언어로 대답하면 됩니다 — 듣기 훈련입니다. 다시 누르면 Step 1로 돌아오고, 대화 흐름은 그대로 이어집니다.',
                          style: TextStyle(
                              color: Colors.white70,
                              fontSize: 14,
                              height: 1.55),
                        ),
                        SizedBox(height: 10),
                        _CircleGuideTip(
                            'Step 2에서는 가능하면 화면을 보지 말고 귀로만 듣고 대답해 보세요. 못 알아들었으면 그냥 되물으면 됩니다.'),
                        SizedBox(height: 22),
                        _CircleGuideHeading('대화 세션 (10분)'),
                        SizedBox(height: 10),
                        Text(
                          '한 세션은 최대 10분입니다. 10분을 다 채워야 하는 것은 아닙니다 — 하고 싶은 만큼 이야기하고 나가면 그때까지의 대화가 기록에 저장됩니다. 10분이 지나도 대화가 끊기거나 방에서 나가지지 않습니다 — 지금까지의 대화가 저장되고, 같은 화면에서 이어서 계속할 수 있습니다. AI는 방을 나가기 전까지 앞서 나눈 이야기의 줄기를 기억한 채 대화를 이어갑니다.',
                          style: TextStyle(
                              color: Colors.white70,
                              fontSize: 14,
                              height: 1.55),
                        ),
                        SizedBox(height: 10),
                        Text(
                          '말하는 도중에 10분이 되어도 하던 말과 AI의 답변이 끝난 뒤에 저장되므로, 한 번의 대화가 둘로 잘리지 않습니다.',
                          style: TextStyle(
                              color: Colors.white70,
                              fontSize: 14,
                              height: 1.55),
                        ),
                        SizedBox(height: 10),
                        Text(
                          '세션이 끝나기 30초 전부터 상단 시간 표시가 남은 초를 세고, 10초 전부터는 점이 주황으로 깜빡입니다.',
                          style: TextStyle(
                              color: Colors.white70,
                              fontSize: 14,
                              height: 1.55),
                        ),
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
