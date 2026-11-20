import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '/custom_code/services/recording_picker.dart';
import '/custom_code/services/recording_scenario_service.dart';
import '/custom_code/services/shorts_scenario_service.dart';
import '/custom_code/services/talk_ui_localization.dart';

/// 모드 선택 제목 위 녹음 가져오기 알약(쇼츠 링크 알약 옆).
class RecordingImportEntry extends StatelessWidget {
  const RecordingImportEntry({super.key, required this.copy, required this.onTap});

  final TalkUiCopy copy;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    const accent = Color(0xFF0EA5E9);
    return Material(
      color: const Color(0xFF0B1F2A),
      shape: StadiumBorder(
        side: BorderSide(color: accent.withValues(alpha: 0.6)),
      ),
      child: InkWell(
        customBorder: const StadiumBorder(),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.graphic_eq, color: accent, size: 20),
              const SizedBox(width: 7),
              Text(
                copy['recordingImport'],
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 🎙️ 녹음 가져오기 팝업 — 파일 고르기와 '대화 만들기'. 만들면 공부방에 새 방을
/// 넣고 그 방의 문서 참조를 돌려준다(취소하면 null). 방으로 들어가는 일은
/// 부르는 쪽이 한다(쇼츠 링크 팝업과 같다). 실패는 팝업 안에 적는다.
///
/// [onRemainingSeconds]: 서버가 시간을 뺐다면 남은 초 — 부르는 쪽이 로비·과금
/// 시계를 맞춘다.
Future<DocumentReference?> showRecordingImportDialog(
  BuildContext context, {
  required TalkUiCopy copy,
  required String originLanguage,
  required String targetLanguage,
  required void Function(int seconds) onRemainingSeconds,
}) {
  const action = Color(0xFF0EA5E9);
  PickedRecording? picked;
  return showDialog<DocumentReference>(
    context: context,
    barrierDismissible: false,
    builder: (dialogContext) {
      var busy = false;
      String? errorText;
      return StatefulBuilder(
        builder: (dialogContext, setDialogState) {
          Future<void> choose() async {
            final file = await pickRecording();
            if (file == null || !dialogContext.mounted) return;
            setDialogState(() {
              picked = file;
              errorText = null;
            });
          }

          Future<void> create() async {
            final file = picked;
            if (file == null) {
              setDialogState(() => errorText = copy['recordingError_noFile']);
              return;
            }
            setDialogState(() {
              busy = true;
              errorText = null;
            });
            try {
              final room = await RecordingScenarioService.createStudyRoom(
                audio: file.bytes,
                fileName: file.name,
                originLanguage: originLanguage,
                targetLanguage: targetLanguage,
              );
              final left = room.remainingSeconds;
              if (left != null) onRemainingSeconds(left);
              if (dialogContext.mounted) {
                Navigator.of(dialogContext).pop(room.ref);
              }
            } on ShortsScenarioException catch (error) {
              if (dialogContext.mounted) {
                setDialogState(() {
                  busy = false;
                  errorText = copy['recordingError_${error.code}'];
                });
              }
            }
          }

          return PopScope(
            canPop: !busy,
            child: Dialog(
              backgroundColor: const Color(0xFF1E1E1E),
              insetPadding:
                  const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
                side: const BorderSide(color: Color(0x1FFFFFFF)),
              ),
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.graphic_eq, color: action, size: 26),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            copy['recordingImport'],
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        IconButton(
                          onPressed: busy
                              ? null
                              : () => Navigator.of(dialogContext).pop(),
                          icon:
                              const Icon(Icons.close, color: Colors.white54),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    OutlinedButton.icon(
                      onPressed: busy ? null : choose,
                      icon: const Icon(Icons.folder_open, size: 20),
                      label: Text(
                        picked?.name ?? copy['recordingPick'],
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.white,
                        minimumSize: const Size.fromHeight(54),
                        side: const BorderSide(color: Color(0x1FFFFFFF)),
                        backgroundColor: const Color(0xFF121212),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14)),
                      ),
                    ),
                    if (errorText != null) ...[
                      const SizedBox(height: 8),
                      Text(
                        errorText!,
                        style: const TextStyle(
                            color: Color(0xFFF87171),
                            fontSize: 13,
                            height: 1.4),
                      ),
                    ],
                    const SizedBox(height: 14),
                    FilledButton(
                      onPressed: busy ? null : create,
                      style: FilledButton.styleFrom(
                        backgroundColor: action,
                        disabledBackgroundColor: action.withValues(alpha: 0.5),
                        foregroundColor: Colors.white,
                        minimumSize: const Size.fromHeight(54),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16)),
                      ),
                      child: busy
                          ? const SizedBox(
                              width: 22,
                              height: 22,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2.2, color: Colors.white),
                            )
                          : Text(
                              copy['recordingCreate'],
                              style: const TextStyle(
                                  fontSize: 16, fontWeight: FontWeight.bold),
                            ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(4, 12, 4, 0),
                      child: Text(
                        copy['recordingNotice'],
                        style: const TextStyle(
                            color: Colors.white38, fontSize: 11.5, height: 1.6),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      );
    },
  );
}
