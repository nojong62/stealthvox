// ============================================================================
// 📖 [SCENARIO-GUIDE] Scenario Talk 사용설명서 — 내용은 여기 한 벌뿐이다
// ----------------------------------------------------------------------------
// 두 곳에서 연다.
//   · 입장 전 Scenario Talk Settings 페이지 (stealth_room_master.dart)
//   · 대화방 안 상단 (routine_mode_scenario_talk.dart)
//
// 예전에는 방 위젯의 private 메서드라 앞 페이지에서 부를 수 없었다. 거기서
// 다시 쓰면 같은 설명이 두 벌이 되어 한쪽만 고쳐지는 일이 생긴다.
// `circle_talk_guide.dart`와 같은 모양으로 최상위 함수로 둔다.
// ============================================================================

import 'package:flutter/material.dart';

/// Scenario Talk의 상징색. 아이콘·확인 버튼이 같은 색을 쓴다.
const Color kScenarioGuideAccent = Color(0xFF4ADE80);

Future<void> showScenarioTalkGuide(BuildContext context) {
  return showDialog<void>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      backgroundColor: const Color(0xFF1A1A1A),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      title: const Row(
        children: [
          Icon(Icons.menu_book_rounded, color: kScenarioGuideAccent),
          SizedBox(width: 10),
          Expanded(
            child: Text(
              'Scenario Talk 사용설명서',
              style: TextStyle(color: Colors.white, fontSize: 18),
            ),
          ),
        ],
      ),
      content: const SingleChildScrollView(
        child: Text(
          '실제 상황처럼 역할을 나누어 AI와 대화하는 모드입니다.\n\n'
          '시작 전 시나리오와 AI·사용자 역할을 확인하거나 직접 수정할 수 있습니다.\n\n'
          '시나리오가 정해지면 AI가 먼저 말을 겁니다. 화면에 표시된 역할의 인물처럼 자연스럽게 말해 보세요. AI도 지정된 역할을 유지하며 대화합니다.\n\n'
          'Step 1 · Step 2\n'
          'Step 1은 지금까지의 대화방 그대로입니다. AI도 나와 같은 대화 언어로 말합니다. 방에 들어오면 늘 Step 1로 시작합니다.\n\n'
          '대화 중 아래의 Step 1 단추를 누르면 다음 대화부터 Step 2가 됩니다. AI만 로비에서 고른 배울 언어로 말하고, 나는 계속 내 언어로 대답하면 됩니다 — 듣기 훈련입니다. 다시 누르면 Step 1로 돌아오고, 대화 흐름은 그대로 이어집니다.\n\n'
          'Step 2에서는 가능하면 화면을 보지 말고 귀로만 듣고 대답해 보세요. 못 알아들었으면 그냥 되물으면 됩니다.\n\n'
          '대화 세션 (10분)\n'
          '한 세션은 최대 10분입니다. 10분을 다 채워야 하는 것은 아닙니다 — 하고 싶은 만큼 이야기하고 나가면 그때까지의 대화가 기록에 저장됩니다. 10분이 지나도 대화가 끊기거나 방에서 나가지지 않습니다 — 지금까지의 대화가 저장되고, 같은 화면에서 이어서 계속할 수 있습니다.\n\n'
          '말하는 도중에 10분이 되어도 하던 말과 AI의 답변이 끝난 뒤에 저장되므로, 한 번의 대화가 둘로 잘리지 않습니다.\n\n'
          '세션이 끝나기 30초 전부터 상단 시간 표시가 남은 초를 세고, 10초 전부터는 점이 주황으로 깜빡입니다.',
          style: TextStyle(color: Colors.white70, fontSize: 14, height: 1.55),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(),
          child:
              const Text('확인', style: TextStyle(color: kScenarioGuideAccent)),
        ),
      ],
    ),
  );
}
