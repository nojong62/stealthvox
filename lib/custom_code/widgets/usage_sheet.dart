// ════════════════════════════════════════════════════════════════════
// 📊 [USAGE] 사용 내역 시트
// --------------------------------------------------------------------
// 원래 Store 안에만 있었다. 스텔스룸 아래 줄에서도 곧장 열 수 있어야 해서
// 밖으로 뺐다 — 두 자리가 **같은 화면**을 열어야 숫자가 갈리지 않는다.
//
// 읽는 곳은 `users/{uid}/usage_logs` 하나뿐이다. 쓰지 않는다.
// ════════════════════════════════════════════════════════════════════

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '/auth/firebase_auth/auth_util.dart';

const Color _kUsageAccent = Color(0xFF60A5FA);

/// 사람이 읽는 시간. 1분 미만은 초로, 1시간 넘으면 시간+분으로 적는다.
String formatUsageDuration(int seconds) {
  if (seconds <= 0) return '0s';
  if (seconds < 60) return '${seconds}s';
  final h = seconds ~/ 3600;
  final mRaw = (seconds % 3600) ~/ 60;
  final mRounded = ((seconds % 3600 + 30) ~/ 60);
  if (h > 0) return mRaw > 0 ? '${h}h ${mRaw}m' : '${h}h';
  return '${mRounded}m';
}

/// mode 문자열을 'talk'(대화방) 또는 'study'(공부방)로 가른다.
///
/// 저장된 mode 값을 그대로 받는다 — `free_talk`·`roleplay`처럼 옛 이름이
/// 들어와도 study로 떨어지므로 새 이름으로 바꿔 적을 필요가 없다.
String usageModeGroup(String mode) {
  const talkModes = {'duo', 'stealth_room'};
  return talkModes.contains(mode) ? 'talk' : 'study';
}

String usageModeGroupName(String mode) =>
    usageModeGroup(mode) == 'talk' ? '대화방' : '공부방';

/// Today / This Week 요약 카드 한 장.
Widget _summaryCard({
  required String title,
  required int talkSeconds,
  required int studySeconds,
}) {
  // 글꼴 배율이 큰 기기에서는 라벨과 값이 한 줄을 같이 못 쓴다. 둘 다
  // Flexible로 묶어 남는 폭을 나눠 쓰게 한다.
  Widget row(String label, int seconds) => Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Flexible(
            child: Text(label,
                style: const TextStyle(color: Colors.white70, fontSize: 13)),
          ),
          const SizedBox(width: 12),
          Flexible(
            child: Text(
              seconds > 0 ? formatUsageDuration(seconds) : '-',
              textAlign: TextAlign.right,
              style: const TextStyle(
                  color: _kUsageAccent,
                  fontSize: 13,
                  fontWeight: FontWeight.w600),
            ),
          ),
        ],
      );

  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
    decoration: BoxDecoration(
      color: Colors.black,
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: Colors.white10),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title,
            style: const TextStyle(
                color: Colors.white38,
                fontSize: 11,
                fontWeight: FontWeight.w600,
                letterSpacing: 1.2)),
        const SizedBox(height: 10),
        row('대화방', talkSeconds),
        const SizedBox(height: 6),
        row('공부방', studySeconds),
      ],
    ),
  );
}

/// 📊 사용 내역을 아래에서 올라오는 시트로 연다.
void showUsageSheet(BuildContext context) {
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (sheetContext) {
      return Container(
        height: MediaQuery.of(sheetContext).size.height * 0.75,
        padding: const EdgeInsets.all(24),
        decoration: const BoxDecoration(
          color: Color(0xFF222222),
          borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Flexible(
                  child: Text("📊 Usage",
                      style: GoogleFonts.orbitron(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.bold)),
                ),
                IconButton(
                  icon: const Icon(Icons.close_rounded, color: Colors.white54),
                  onPressed: () => Navigator.pop(sheetContext),
                ),
              ],
            ),
            const Divider(color: Colors.white12, height: 24),
            Expanded(
              child: currentUserReference == null
                  ? const Center(
                      child: Text("로그인 후 이용해 주세요.",
                          style: TextStyle(color: Colors.white54)))
                  : StreamBuilder<QuerySnapshot>(
                      stream: currentUserReference!
                          .collection('usage_logs')
                          .orderBy('created_at', descending: true)
                          .limit(200)
                          .snapshots(),
                      builder: (context, snapshot) {
                        if (!snapshot.hasData) {
                          return const Center(
                              child: CircularProgressIndicator(
                                  color: _kUsageAccent));
                        }

                        // 10초 미만은 기록으로 치지 않는다 — 잘못 눌러 들어갔다
                        // 나온 것까지 내역에 남으면 읽을 수 없어진다.
                        final records = snapshot.data!.docs.where((doc) {
                          final d = doc.data() as Map<String, dynamic>;
                          final int sec = (d['actual_seconds'] as int?) ??
                              (d['seconds_used'] as int?) ??
                              0;
                          return sec >= 10;
                        }).toList();

                        if (records.isEmpty) {
                          return const Center(
                            child: Padding(
                              padding: EdgeInsets.all(24.0),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.access_time_rounded,
                                      color: Colors.white24, size: 48),
                                  SizedBox(height: 16),
                                  Text("아직 사용 내역이 없습니다.",
                                      style: TextStyle(
                                          color: Colors.white54, fontSize: 14)),
                                  SizedBox(height: 8),
                                  Text(
                                    "대화를 시작하면 사용 시간이 이곳에 표시됩니다.",
                                    style: TextStyle(
                                        color: Colors.white38, fontSize: 12),
                                    textAlign: TextAlign.center,
                                  ),
                                ],
                              ),
                            ),
                          );
                        }

                        final now = DateTime.now();
                        final todayStart =
                            DateTime(now.year, now.month, now.day);
                        final weekStart = todayStart
                            .subtract(Duration(days: todayStart.weekday - 1));

                        int sumGroup(String group, DateTime rangeStart) {
                          int total = 0;
                          for (final doc in records) {
                            final d = doc.data() as Map<String, dynamic>;
                            final DateTime ts = d['created_at'] != null
                                ? (d['created_at'] as Timestamp).toDate()
                                : now;
                            if (ts.isBefore(rangeStart)) continue;
                            final String mode = (d['mode'] as String?) ?? '';
                            if (usageModeGroup(mode) != group) continue;
                            total += (d['actual_seconds'] as int?) ??
                                (d['seconds_used'] as int?) ??
                                0;
                          }
                          return total;
                        }

                        final recentSessions = records.take(5).toList();

                        return SingleChildScrollView(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _summaryCard(
                                title: 'Today',
                                talkSeconds: sumGroup('talk', todayStart),
                                studySeconds: sumGroup('study', todayStart),
                              ),
                              const SizedBox(height: 10),
                              _summaryCard(
                                title: 'This Week',
                                talkSeconds: sumGroup('talk', weekStart),
                                studySeconds: sumGroup('study', weekStart),
                              ),
                              const SizedBox(height: 20),
                              const Text(
                                'Recent Sessions',
                                style: TextStyle(
                                    color: Colors.white54,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                    letterSpacing: 1.1),
                              ),
                              const SizedBox(height: 10),
                              ...recentSessions.map((doc) {
                                final d = doc.data() as Map<String, dynamic>;
                                final DateTime ts = d['created_at'] != null
                                    ? (d['created_at'] as Timestamp).toDate()
                                    : now;
                                final String dateStr =
                                    DateFormat('yyyy.MM.dd HH:mm').format(ts);
                                final String modeRaw =
                                    (d['mode'] as String?) ?? '';
                                final String groupName =
                                    usageModeGroupName(modeRaw);
                                final int actualSec =
                                    (d['actual_seconds'] as int?) ??
                                        (d['seconds_used'] as int?) ??
                                        0;
                                final int usedSec =
                                    (d['seconds_used'] as int?) ?? 0;
                                // 실제 사용과 차감이 5초 넘게 벌어졌을 때만
                                // 둘을 함께 적는다. 늘 적으면 줄이 길어져
                                // 정작 시간이 안 보인다.
                                final bool isDiff =
                                    (actualSec - usedSec).abs() > 5 &&
                                        usedSec > 0;

                                return Padding(
                                  padding: const EdgeInsets.only(bottom: 10),
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 16, vertical: 12),
                                    decoration: BoxDecoration(
                                      color: Colors.black,
                                      borderRadius: BorderRadius.circular(14),
                                      border: Border.all(color: Colors.white10),
                                    ),
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          isDiff
                                              ? '$groupName  ·  실제 ${formatUsageDuration(actualSec)} 사용  ·  ${formatUsageDuration(usedSec)} 차감'
                                              : '$groupName  ·  ${formatUsageDuration(actualSec)}',
                                          style: const TextStyle(
                                              color: _kUsageAccent,
                                              fontSize: 13,
                                              fontWeight: FontWeight.w600),
                                        ),
                                        const SizedBox(height: 4),
                                        Text(dateStr,
                                            style: const TextStyle(
                                                color: Colors.white38,
                                                fontSize: 11)),
                                      ],
                                    ),
                                  ),
                                );
                              }),
                            ],
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      );
    },
  );
}
