// 🖼️ Duo 무대 그림 미리보기 — 실기기에 올려 눈으로 확인하는 용도.
//
//   flutter run -t tool/duo_stage_preview.dart -d <device>
//
// 앱 본체를 거치지 않는다. Duo 화면을 실제로 보려면 방을 만들고 상대가 들어와야
// 하는데, 그림만 고치는 동안 매번 그럴 수는 없어서 따로 띄운다.
import 'package:flutter/material.dart';
import 'package:stealth_vox/custom_code/widgets/duo_stage.dart';

void main() => runApp(const _PreviewApp());

class _PreviewApp extends StatelessWidget {
  const _PreviewApp();

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        backgroundColor: const Color(0xFF121212),
        body: SafeArea(
          child: ListView(
            padding: const EdgeInsets.symmetric(vertical: 12),
            children: const [
              _Case(
                title: '직접 대화 · 상대 없음',
                child: DuoDirectStage(
                    callActive: false, muted: false, partnerOnline: false),
              ),
              _Case(
                title: '직접 대화 · 통화 중',
                child: DuoDirectStage(
                    callActive: true, muted: false, partnerOnline: true),
              ),
              _Case(
                title: '직접 대화 · 음소거',
                child: DuoDirectStage(
                    callActive: true, muted: true, partnerOnline: true),
              ),
              _Case(
                title: '만능 통역 · 대기',
                child:
                    DuoInterpreterStage(ready: false, partnerSpeaking: false),
              ),
              _Case(
                title: '만능 통역 · 말하기 가능',
                child: DuoInterpreterStage(ready: true, partnerSpeaking: false),
              ),
              _Case(
                title: '만능 통역 · 상대 발화 중',
                child: DuoInterpreterStage(ready: false, partnerSpeaking: true),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Case extends StatelessWidget {
  const _Case({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 6, 12, 6),
      padding: const EdgeInsets.symmetric(vertical: 14),
      decoration: BoxDecoration(
        border: Border.all(color: const Color(0xFF2A2A2E)),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          Text(title,
              style: const TextStyle(color: Colors.white38, fontSize: 11)),
          const SizedBox(height: 10),
          SizedBox(height: 210, child: child),
        ],
      ),
    );
  }
}
