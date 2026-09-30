import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import '/custom_code/services/duo_board_service.dart';

Future<DuoBoardClaim?> showDuoBoardSheet(BuildContext context) async {
  await DuoBoardService.ensureParticipantIdentity();
  if (!context.mounted) return null;
  return showModalBottomSheet<DuoBoardClaim>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: const Color(0xFF14171D),
    builder: (_) => const DuoBoardSheet(),
  );
}

Future<bool> showDuoBoardComposer(
  BuildContext context, {
  required String roomId,
  required String mode,
  required String directLanguage,
}) async {
  final topic = TextEditingController();
  var saving = false;
  String? error;
  final saved = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: const Color(0xFF171A21),
    builder: (sheetContext) => StatefulBuilder(
      builder: (context, setLocal) => Padding(
        padding: EdgeInsets.fromLTRB(
            22, 22, 22, 22 + MediaQuery.viewInsetsOf(context).bottom),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Text('Duo 게시판에 올리기',
              style: TextStyle(
                  color: Colors.white,
                  fontSize: 21,
                  fontWeight: FontWeight.w800)),
          const SizedBox(height: 8),
          Text(mode == 'direct' ? 'Direct · $directLanguage' : 'Interpreter',
              style: const TextStyle(color: Color(0xFF93C5FD))),
          const SizedBox(height: 18),
          TextField(
            controller: topic,
            autofocus: true,
            maxLength: 80,
            style: const TextStyle(color: Colors.white),
            decoration: InputDecoration(
              labelText: '대화 주제',
              hintText: '예: 여행 이야기',
              errorText: error,
              filled: true,
              fillColor: const Color(0xFF232833),
              border:
                  OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
            ),
          ),
          const Align(
            alignment: Alignment.centerLeft,
            child: Text('🟢 지금 가능',
                style: TextStyle(color: Color(0xFF86EFAC), fontSize: 13)),
          ),
          const SizedBox(height: 20),
          SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: saving
                    ? null
                    : () async {
                        final value = topic.text.trim();
                        if (value.length < 2) {
                          setLocal(() => error = '주제를 두 글자 이상 입력해 주세요.');
                          return;
                        }
                        setLocal(() {
                          saving = true;
                          error = null;
                        });
                        try {
                          await DuoBoardService.publishPost(
                              roomId: roomId,
                              topic: value,
                              mode: mode,
                              directLanguage: directLanguage,
                              availability: 'now');
                          if (sheetContext.mounted) {
                            Navigator.pop(sheetContext, true);
                          }
                        } catch (_) {
                          setLocal(() {
                            saving = false;
                            error = '등록하지 못했습니다. 잠시 후 다시 시도해 주세요.';
                          });
                        }
                      },
                child: Text(saving ? '등록 중…' : '게시하기'),
              )),
        ]),
      ),
    ),
  );
  topic.dispose();
  return saved == true;
}

class DuoBoardSheet extends StatefulWidget {
  const DuoBoardSheet({super.key});
  @override
  State<DuoBoardSheet> createState() => _DuoBoardSheetState();
}

class _DuoBoardSheetState extends State<DuoBoardSheet> {
  String? _claiming;
  String? _error;

  @override
  Widget build(BuildContext context) => SizedBox(
        height: MediaQuery.sizeOf(context).height * .82,
        child: Column(children: [
          const SizedBox(height: 12),
          Container(
              width: 42,
              height: 4,
              decoration: BoxDecoration(
                  color: Colors.white24,
                  borderRadius: BorderRadius.circular(99))),
          const Padding(
              padding: EdgeInsets.fromLTRB(20, 18, 20, 4),
              child: Row(children: [
                Icon(Icons.forum_outlined, color: Color(0xFF52D4C3)),
                SizedBox(width: 10),
                Text('Duo 초대 게시판',
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: 22,
                        fontWeight: FontWeight.w800)),
              ])),
          const Padding(
              padding: EdgeInsets.fromLTRB(20, 0, 20, 12),
              child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text('상대를 찾은 뒤 기존 Duo 통화로 연결됩니다.',
                      style: TextStyle(color: Colors.white54)))),
          if (_error != null)
            Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Text(_error!,
                    style: const TextStyle(color: Color(0xFFFCA5A5)))),
          Expanded(
              child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: DuoBoardService.watchPosts(),
            builder: (context, snapshot) {
              if (snapshot.hasError)
                return const Center(
                    child: Text('게시글을 불러오지 못했습니다.',
                        style: TextStyle(color: Colors.white70)));
              if (!snapshot.hasData)
                return const Center(child: CircularProgressIndicator());
              final docs = snapshot.data!.docs;
              if (docs.isEmpty)
                return const Center(
                    child: Text('아직 올라온 초대가 없습니다.',
                        style: TextStyle(color: Colors.white54)));
              return ListView.separated(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                itemCount: docs.length,
                separatorBuilder: (_, __) => const SizedBox(height: 10),
                itemBuilder: (_, index) {
                  final doc = docs[index];
                  final data = doc.data();
                  final mode = data['mode']?.toString() ?? 'interpreter';
                  final availability =
                      data['availability']?.toString() ?? 'request';
                  final mine = data['ownerUid'] ==
                      FirebaseAuth.instance.currentUser?.uid;
                  return Card(
                      color: const Color(0xFF202530),
                      child: ListTile(
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 8),
                        title: Text(data['topic']?.toString() ?? '',
                            style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w700)),
                        subtitle: Text(
                            mode == 'direct'
                                ? 'Direct · ${data['directLanguage'] ?? ''}'
                                : 'Interpreter',
                            style: const TextStyle(color: Color(0xFF93C5FD))),
                        trailing: Text(
                            availability == 'now' ? '🟢 지금 가능' : '⚪ 요청 가능',
                            style: const TextStyle(
                                color: Colors.white70, fontSize: 12)),
                        enabled: !mine && _claiming == null,
                        onTap: availability != 'now' || mine
                            ? null
                            : () async {
                                setState(() {
                                  _claiming = doc.id;
                                  _error = null;
                                });
                                try {
                                  final claim =
                                      await DuoBoardService.claimNow(doc.id);
                                  if (context.mounted)
                                    Navigator.pop(context, claim);
                                } catch (_) {
                                  if (mounted)
                                    setState(() {
                                      _claiming = null;
                                      _error = '이미 다른 사용자가 선점했거나 초대가 만료되었습니다.';
                                    });
                                }
                              },
                      ));
                },
              );
            },
          )),
        ]),
      );
}
