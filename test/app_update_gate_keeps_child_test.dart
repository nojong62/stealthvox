import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stealth_vox/custom_code/services/app_update_policy.dart';
import 'package:stealth_vox/custom_code/widgets/app_update_gate.dart';

/// 자기 State를 가진 child. 업데이트 안내창을 닫을 때 이 State가 새로 만들어지면
/// 앱 전체 Router도 새로 만들어지는 것이다(2026-11-21 go_router RangeError).
class _Counter extends StatefulWidget {
  const _Counter();

  @override
  State<_Counter> createState() => _CounterState();
}

int _created = 0;

class _CounterState extends State<_Counter> {
  @override
  void initState() {
    super.initState();
    _created++;
  }

  @override
  Widget build(BuildContext context) => const Scaffold(body: Text('앱 본문'));
}

void main() {
  testWidgets('dismissing the recommended update keeps the app subtree alive',
      (tester) async {
    _created = 0;
    await tester.pumpWidget(const MaterialApp(
      home: AppUpdateGate(
        decision: AppUpdateDecision(
          requirement: AppUpdateRequirement.recommended,
        ),
        child: _Counter(),
      ),
    ));
    expect(_created, 1);

    // "나중에"는 TextButton 중 첫 번째다(필수 업데이트가 아니므로 둘이 있다).
    await tester.tap(find.byType(TextButton).first);
    await tester.pump();

    expect(find.byType(AlertDialog), findsNothing);
    expect(find.text('앱 본문'), findsOneWidget);
    // child State가 새로 만들어지지 않았다.
    expect(_created, 1);
  });

  testWidgets('without any update requirement the child is shown as is',
      (tester) async {
    _created = 0;
    await tester.pumpWidget(const MaterialApp(
      home: AppUpdateGate(
        decision: AppUpdateDecision(requirement: AppUpdateRequirement.none),
        child: _Counter(),
      ),
    ));
    expect(find.byType(AlertDialog), findsNothing);
    expect(find.text('앱 본문'), findsOneWidget);
    expect(_created, 1);
  });
}
