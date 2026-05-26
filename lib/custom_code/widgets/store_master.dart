// Automatic FlutterFlow imports
import '/backend/backend.dart';
import '/backend/schema/structs/index.dart';
import '/flutter_flow/flutter_flow_theme.dart';
import '/flutter_flow/flutter_flow_util.dart';
import 'index.dart'; // Imports other custom widgets
import '/custom_code/actions/index.dart'; // Imports custom actions
import '/flutter_flow/custom_functions.dart'; // Imports custom functions
import 'package:flutter/material.dart';
// Begin custom widget code
// DO NOT REMOVE OR MODIFY THE CODE ABOVE!

import 'index.dart'; // Imports other custom widgets
import '/custom_code/actions/billing_ticker.dart';

import '/auth/firebase_auth/auth_util.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:purchases_flutter/purchases_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:package_info_plus/package_info_plus.dart';
// 💡 에러의 원인이었던 외부 패키지 삭제 완료! Firebase로 대체합니다.

class StoreMaster extends StatefulWidget {
  const StoreMaster({
    Key? key,
    this.width,
    this.height,
  }) : super(key: key);

  final double? width;
  final double? height;

  @override
  _StoreMasterState createState() => _StoreMasterState();
}

class _StoreMasterState extends State<StoreMaster> {
  bool isProcessing = false;
  bool _showLogCopyButton = false;
  String _versionText = '';

  final List<String> _debugLogs = [];
  void _log(String tag, String msg) {
    final ts = DateTime.now().toIso8601String().substring(11, 23);
    final line = '[$ts] $tag $msg';
    print(line);
    _debugLogs.add(line);
    if (_debugLogs.length > 500) {
      _debugLogs.removeRange(0, 50);
    }
  }

  final List<Map<String, dynamic>> storePlans = [
    {
      'id': 'stealthvox_10m',
      'title': '10 Minutes',
      'subtitle': '체험권',
      'seconds': 600,
      'price_text': '₩300',
      'theme_color': const Color(0xFF60A5FA),
      'icon': Icons.bolt_rounded,
    },
    {
      'id': 'stealthvox_1h',
      'title': '1 Hour',
      'subtitle': '기본권',
      'seconds': 3600,
      'price_text': '₩1,700',
      'theme_color': const Color(0xFF34D399),
      'icon': Icons.hourglass_top_rounded,
    },
    {
      'id': 'stealthvox_5h',
      'title': '5 Hours',
      'subtitle': '추천권',
      'seconds': 18000,
      'price_text': '₩8,000',
      'theme_color': const Color(0xFFFBBF24),
      'icon': Icons.star_rounded,
    },
    {
      'id': 'stealthvox_10h',
      'title': '10 Hours',
      'subtitle': '프리미엄권',
      'seconds': 36000,
      'price_text': '₩15,000',
      'theme_color': const Color(0xFFA78BFA),
      'icon': Icons.diamond_rounded,
    },
  ];

  @override
  void initState() {
    super.initState();
    _log('STORE', 'StoreMaster initState');
    // 💡 v3.7 보강: 결제 화면 첫 진입 시 한 번만 RevenueCat 사용자 연결 안전 체크
    _initRevenueCatUser();
    _loadVersion();
  }

  Future<void> _loadVersion() async {
    try {
      final info = await PackageInfo.fromPlatform();
      if (mounted) {
        setState(() {
          _versionText = 'v${info.version} (${info.buildNumber})';
        });
      }
    } catch (_) {}
  }

  // 💡 v3.7 보강: 결제 화면 최초 진입 시 한 번만 실행 — 매 결제마다 재로그인하지 않음
  Future<void> _initRevenueCatUser() async {
    try {
      // uid 없으면(비로그인 상태) 스킵
      final uid = currentUserUid;
      if (uid == null || uid.isEmpty) {
        _log('RC_INIT', 'uid null or empty → skip');
        return;
      }
      _log('RC_INIT', 'uid=$uid');

      // 이미 식별된 사용자면 재로그인 불필요
      final isAnon = await Purchases.isAnonymous;
      _log('RC_INIT', 'isAnonymous=$isAnon');
      if (isAnon) {
        await Purchases.logIn(uid);
        _log('RC_INIT', 'Purchases.logIn completed');
      }
    } catch (e) {
      _log('RC_INIT', 'error: $e');
      // 로그인 실패해도 위젯 렌더링에 영향 없음, 로그만 남김
      print('[RevenueCat] _initRevenueCatUser 오류: $e');
    }
  }

  Future<void> _executePurchase(Map<String, dynamic> plan) async {
    if (isProcessing) return;

    _log('PURCHASE', 'tap productId=${plan['id']} title=${plan['title']} uid=$currentUserUid ref=${currentUserReference != null}');

    if (currentUserReference == null) {
      _showFeedback("로그인 후 이용해 주세요.", const Color(0xFFF87171));
      return;
    }

    setState(() => isProcessing = true);
    try {
      // RevenueCat 권장 흐름: Offerings → Package 매칭 → purchasePackage
      final offerings = await Purchases.getOfferings();
      _log('OFFERINGS', 'current=${offerings.current?.identifier}');
      _log('OFFERINGS', 'default=${offerings.all['default']?.identifier}');
      final offering = offerings.current ?? offerings.all['default'];
      _log('OFFERINGS', 'selected=${offering?.identifier}');
      _log('OFFERINGS', 'packageCount=${offering?.availablePackages.length ?? 0}');
      for (final p in offering?.availablePackages ?? []) {
        _log('OFFERINGS', 'package=${p.identifier}, product=${p.storeProduct.identifier}, price=${p.storeProduct.priceString}');
      }

      if (offering == null) {
        _log('OFFERINGS', 'no current or default offering → abort');
        debugPrint('[RevenueCat] No current or default offering found');
        _showFeedback(
            "상품 정보를 아직 불러오지 못했습니다. 잠시 후 다시 시도해 주세요.", const Color(0xFFF87171));
        return;
      }

      final targetProductId = plan['id'] as String;
      _log('MATCH', 'request productId=$targetProductId');
      Package? matchedPackage;
      for (final pkg in offering.availablePackages) {
        if (pkg.storeProduct.identifier == targetProductId) {
          matchedPackage = pkg;
          break;
        }
      }
      _log('MATCH', 'matched package=${matchedPackage?.identifier}, product=${matchedPackage?.storeProduct.identifier}');

      if (matchedPackage == null) {
        _log('MATCH', 'package NOT FOUND for productId=$targetProductId → abort');
        debugPrint('[RevenueCat] Package not found — productId: $targetProductId');
        debugPrint('[RevenueCat] current offering: ${offering.identifier}');
        debugPrint(
            '[RevenueCat] available package identifiers: ${offering.availablePackages.map((p) => p.identifier).toList()}');
        debugPrint(
            '[RevenueCat] available store product identifiers: ${offering.availablePackages.map((p) => p.storeProduct.identifier).toList()}');
        _showFeedback(
            "상품 정보를 아직 불러오지 못했습니다. 잠시 후 다시 시도해 주세요.", const Color(0xFFF87171));
        return;
      }

      _log('PURCHASE', 'purchasePackage start productId=$targetProductId');
      final purchaseResult = await Purchases.purchase(PurchaseParams.package(matchedPackage));
      _log('PURCHASE', 'success appUserId=${purchaseResult.customerInfo.originalAppUserId}');
      _log('PURCHASE', 'activeEntitlements=${purchaseResult.customerInfo.entitlements.active.keys.join(',')}');

      // 클라이언트 UUID 생성 (RevenueCat 웹훅 ID와 매핑 가능)
      final uid = currentUserUid ?? 'anon';
      final uidPrefix = uid.length >= 6 ? uid.substring(0, 6) : uid;
      final clientTxId =
          'client_${DateTime.now().millisecondsSinceEpoch}_$uidPrefix';

      await _syncPurchaseData(plan, clientTxId);
      _showFeedback("✅ 충전 완료! (${plan['title']})", const Color(0xFF34D399));
    } on PlatformException catch (e) {
      final errorCode = PurchasesErrorHelper.getErrorCode(e);
      _log('ERROR', 'platform code=$errorCode message=${e.message} details=${e.details}');
      if (errorCode == PurchasesErrorCode.purchaseCancelledError) {
        _showFeedback("결제가 취소되었습니다.", Colors.white54);
      } else if (errorCode == PurchasesErrorCode.purchaseNotAllowedError) {
        _showFeedback("이 기기에서는 결제할 수 없습니다.", const Color(0xFFF87171));
      } else if (errorCode == PurchasesErrorCode.paymentPendingError) {
        _showFeedback("결제 승인 대기 중입니다.", const Color(0xFFFBBF24));
      } else if (errorCode == PurchasesErrorCode.networkError) {
        _showFeedback("네트워크 연결을 확인해 주세요.", const Color(0xFFF87171));
      } else if (errorCode == PurchasesErrorCode.storeProblemError) {
        _showFeedback("스토어 점검 중입니다. 잠시 후 다시 시도해 주세요.", const Color(0xFFF87171));
      } else {
        _showFeedback("결제 처리 중 오류가 발생했습니다. 잠시 후 다시 시도해 주세요.",
            const Color(0xFFF87171));
      }
    } catch (e, stack) {
      final stackStr = stack.toString();
      _log('ERROR', 'general: $e');
      _log('ERROR', 'stack: ${stackStr.substring(0, stackStr.length > 200 ? 200 : stackStr.length)}');
      _showFeedback("결제 처리 중 오류가 발생했습니다. 잠시 후 다시 시도해 주세요.", const Color(0xFFF87171));
    } finally {
      if (mounted) setState(() => isProcessing = false);
    }
  }

  // 💡 v3.7 보강: transactionId 파라미터 추가 — 중복 결제 방지용
  Future<void> _syncPurchaseData(
      Map<String, dynamic> plan, String transactionId) async {
    int earnedSeconds = plan['seconds'];
    String planId = plan['id'];
    String planTitle = plan['title'];

    _log('SYNC', 'start planId=$planId txId=$transactionId earnedSeconds=$earnedSeconds remainingTime=${FFAppState().remainingTime}');

    if (currentUserReference == null) {
      _log('SYNC', 'currentUserReference null → abort');
      return;
    }

    // 💡 v3.7.2: 시간 기반 중복 결제 방지 — 동일 product_id가 최근 10초 내에 결제됐으면 스킵
    final tenSecondsAgo = Timestamp.fromDate(
        DateTime.now().subtract(const Duration(seconds: 10)));

    final recentDuplicates = await currentUserReference!
        .collection('purchases')
        .where('product_id', isEqualTo: planId)
        .where('purchased_at', isGreaterThan: tenSecondsAgo)
        .limit(1)
        .get();

    if (recentDuplicates.docs.isNotEmpty) {
      _showFeedback("잠시 후 다시 시도해 주세요.", Colors.white54);
      return;
    }

    // 중복 없음 확인 후 증액 처리
    // 💡 v3.7.1 보강: 위젯 dispose 후 setState 호출 방지 (결제 도중 뒤로가기 케이스)
    if (mounted) {
      setState(() {
        FFAppState().remainingTime += earnedSeconds;
      });
      BillingTicker.instance.remainingSecondsNotifier.value =
          FFAppState().remainingTime;
    }

    await currentUserReference!.update({
      'remaining_seconds': FieldValue.increment(earnedSeconds),
      'remainingTime': FieldValue.increment(earnedSeconds),
    });
    await currentUserReference!.collection('purchases').add({
      'product_id': planId,
      'product_title': planTitle,
      'seconds_added': earnedSeconds,
      'purchased_at': FieldValue.serverTimestamp(),
      // 💡 v3.7 보강: 중복 방지용 트랜잭션 ID 저장
      'transaction_id': transactionId,
    });
    _log('SYNC', 'Firestore increment + purchase record success');
  }

  Future<void> _runRestore() async {
    setState(() => isProcessing = true);
    try {
      await Purchases.restorePurchases();
      _showFeedback("✅ 구매 내역 복원 완료", Colors.blueAccent);
    } on PlatformException catch (e) {
      _showFeedback("❌ 복원 실패: ${e.message}", const Color(0xFFF87171));
    } finally {
      if (mounted) setState(() => isProcessing = false);
    }
  }

  void _showFeedback(String message, Color bgColor) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message,
            style: const TextStyle(
                fontWeight: FontWeight.bold, color: Colors.white)),
        backgroundColor: bgColor,
        duration: const Duration(milliseconds: 2500),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<void> _launchURL(String urlString) async {
    final Uri url = Uri.parse(urlString);
    if (!await launchUrl(url, mode: LaunchMode.externalApplication)) {
      _showFeedback('링크를 열 수 없습니다.', const Color(0xFFF87171));
    }
  }

  /// Firestore mode 값을 사용자 친화적 이름으로 변환하는 헬퍼
  /// billing_ticker.dart의 logMode() 호출값과 매핑
  String _modeDisplayName(String mode) {
    switch (mode) {
      case 'duo':
        return '🎭 Duo Mode';
      case 'roleplay':
        return '🎬 Roleplay';
      case 'study_room':
      case 'stealth_room':
        return '🕵️ Stealth Room';
      case 'clone':
        return '🤖 AI Clone';
      case 'history':
        return '📖 Chat History';
      case 'history_list':
        return '📋 History List';
      case 'ai_practice':
        return '🧠 AI Practice';
      default:
        return mode.isNotEmpty ? mode : 'Unknown';
    }
  }

  /// 초 단위를 보기 좋은 문자열로 변환하는 헬퍼
  /// 예: 65 → "1m 5s", 3600 → "1h 0m", 0 이하 → "0s"
  String _formatDurationFromSeconds(int seconds) {
    if (seconds <= 0) return '0s';
    final h = seconds ~/ 3600;
    final m = (seconds % 3600) ~/ 60;
    final s = seconds % 60;
    if (h > 0) return '${h}h ${m}m';
    if (m > 0) return '${m}m ${s}s';
    return '${s}s';
  }

  void _openReceiptSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return Container(
          height: MediaQuery.of(context).size.height * 0.65,
          padding: const EdgeInsets.all(24),
          decoration: const BoxDecoration(
            color: Color(0xFF222222), // 모달창 다크 그레이
            borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text("🧾 Purchase History",
                      style: GoogleFonts.orbitron(
                          color: Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.bold)),
                  IconButton(
                    icon:
                        const Icon(Icons.close_rounded, color: Colors.white54),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
              const Divider(color: Colors.white12, height: 30),
              Expanded(
                child: currentUserReference == null
                    ? const Center(
                        child: Text("접근 권한이 없습니다.",
                            style: TextStyle(color: Colors.white54)))
                    : StreamBuilder<QuerySnapshot>(
                        stream: currentUserReference!
                            .collection('purchases')
                            .orderBy('purchased_at', descending: true)
                            .snapshots(),
                        builder: (context, snapshot) {
                          if (!snapshot.hasData)
                            return const Center(
                                child: CircularProgressIndicator(
                                    color: Colors.amber));
                          final records = snapshot.data!.docs;
                          if (records.isEmpty)
                            return const Center(
                                child: Text("결제 내역이 존재하지 않습니다.",
                                    style: TextStyle(color: Colors.white54)));

                          return ListView.separated(
                            itemCount: records.length,
                            separatorBuilder: (_, __) =>
                                const SizedBox(height: 12),
                            itemBuilder: (context, index) {
                              var data =
                                  records[index].data() as Map<String, dynamic>;
                              DateTime ts = data['purchased_at'] != null
                                  ? (data['purchased_at'] as Timestamp).toDate()
                                  : DateTime.now();
                              String dateFormatted =
                                  DateFormat('yyyy.MM.dd HH:mm').format(ts);
                              int addedMinutes =
                                  (data['seconds_added'] ?? 0) ~/ 60;

                              return Container(
                                padding: const EdgeInsets.all(16),
                                decoration: BoxDecoration(
                                  color: Colors.black,
                                  borderRadius: BorderRadius.circular(16),
                                  border: Border.all(color: Colors.white10),
                                ),
                                child: Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  children: [
                                    Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                            data['product_title'] ??
                                                'Unknown Item',
                                            style: const TextStyle(
                                                color: Colors.white,
                                                fontSize: 15,
                                                fontWeight: FontWeight.bold)),
                                        const SizedBox(height: 4),
                                        Text(dateFormatted,
                                            style: const TextStyle(
                                                color: Colors.white38,
                                                fontSize: 12)),
                                      ],
                                    ),
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 12, vertical: 6),
                                      decoration: BoxDecoration(
                                        color: Colors.green.withOpacity(0.15),
                                        borderRadius: BorderRadius.circular(20),
                                      ),
                                      child: Text("+ ${addedMinutes}m",
                                          style: const TextStyle(
                                              color: Colors.green,
                                              fontWeight: FontWeight.bold)),
                                    ),
                                  ],
                                ),
                              );
                            },
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

  // ── 사용자용 Usage 화면 ────────────────────────────────────────────────────
  void _openUsageSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return Container(
          height: MediaQuery.of(context).size.height * 0.70,
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
                  Text("📊 Usage",
                      style: GoogleFonts.orbitron(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.bold)),
                  IconButton(
                    icon: const Icon(Icons.close_rounded,
                        color: Colors.white54),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
              const Divider(color: Colors.white12, height: 30),
              Expanded(
                child: currentUserReference == null
                    ? const Center(
                        child: Text("로그인 후 이용해 주세요.",
                            style: TextStyle(color: Colors.white54)))
                    : StreamBuilder<QuerySnapshot>(
                        stream: currentUserReference!
                            .collection('usage_logs')
                            .orderBy('created_at', descending: true)
                            .limit(100)
                            .snapshots(),
                        builder: (context, snapshot) {
                          if (!snapshot.hasData) {
                            return const Center(
                                child: CircularProgressIndicator(
                                    color: Color(0xFF60A5FA)));
                          }
                          final records = snapshot.data!.docs;
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
                                    Text(
                                      "No usage history yet.",
                                      style: TextStyle(
                                          color: Colors.white54,
                                          fontSize: 14),
                                    ),
                                    SizedBox(height: 8),
                                    Text(
                                      "Your usage will appear here after a session.",
                                      style: TextStyle(
                                          color: Colors.white38,
                                          fontSize: 12),
                                      textAlign: TextAlign.center,
                                    ),
                                  ],
                                ),
                              ),
                            );
                          }

                          return ListView.separated(
                            itemCount: records.length,
                            separatorBuilder: (_, __) =>
                                const SizedBox(height: 12),
                            itemBuilder: (context, index) {
                              final data = records[index].data()
                                  as Map<String, dynamic>;

                              final DateTime ts = data['created_at'] != null
                                  ? (data['created_at'] as Timestamp)
                                      .toDate()
                                  : DateTime.now();
                              final String dateFormatted =
                                  DateFormat('yyyy.MM.dd HH:mm').format(ts);

                              final String modeRaw =
                                  (data['mode'] as String?) ??
                                      (data['reason'] as String?) ??
                                      '';
                              final String modeName =
                                  _modeDisplayName(modeRaw);

                              // actual_seconds 우선, 없으면 seconds_used로 폴백
                              final int actualSeconds =
                                  (data['actual_seconds'] as int?) ??
                                  (data['seconds_used'] as int?) ??
                                  0;
                              final int secondsUsed =
                                  (data['seconds_used'] as int?) ?? 0;

                              // rate: 화면에 직접 노출 안 함, 할인 여부만 판단
                              final dynamic rateRaw = data['rate'];
                              final double rateVal = rateRaw is double
                                  ? rateRaw
                                  : (rateRaw is num
                                      ? rateRaw.toDouble()
                                      : 1.0);
                              final bool isDiscounted = rateVal < 0.99;

                              final String usageText = isDiscounted
                                  ? "실제 ${_formatDurationFromSeconds(actualSeconds)} 사용  ·  ${_formatDurationFromSeconds(secondsUsed)} 차감"
                                  : "${_formatDurationFromSeconds(actualSeconds)} 사용";

                              return Container(
                                padding: const EdgeInsets.all(16),
                                decoration: BoxDecoration(
                                  color: Colors.black,
                                  borderRadius: BorderRadius.circular(16),
                                  border:
                                      Border.all(color: Colors.white10),
                                ),
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.start,
                                  children: [
                                    // 모드명 + 날짜
                                    Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment.spaceBetween,
                                      children: [
                                        Expanded(
                                          child: Text(
                                            modeName,
                                            style: const TextStyle(
                                                color: Colors.white,
                                                fontSize: 14,
                                                fontWeight:
                                                    FontWeight.bold),
                                            overflow:
                                                TextOverflow.ellipsis,
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        Text(dateFormatted,
                                            style: const TextStyle(
                                                color: Colors.white38,
                                                fontSize: 11)),
                                      ],
                                    ),
                                    const SizedBox(height: 8),
                                    // 사용 시간 (개발자 정보 없음)
                                    Text(
                                      usageText,
                                      style: const TextStyle(
                                          color: Color(0xFF60A5FA),
                                          fontSize: 13,
                                          fontWeight: FontWeight.w600),
                                    ),
                                  ],
                                ),
                              );
                            },
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

  // ── 관리자용 Admin Time Log (STORE 제목 long press 진입) ──────────────────
  void _openAdminTimeLogSheet() {
    // TODO: 관리자 이메일 목록 확정 후 아래 Set에 추가
    const Set<String> adminEmails = {
      'nisiekorea@gmail.com',
    };
    final String email = currentUserEmail.trim().toLowerCase();
    if (!adminEmails.contains(email)) return; // 관리자 아니면 아무 반응 없음
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return Container(
          height: MediaQuery.of(context).size.height * 0.75,
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
                  Text("🔐 Admin Time Log",
                      style: GoogleFonts.orbitron(
                          color: Colors.amber,
                          fontSize: 16,
                          fontWeight: FontWeight.bold)),
                  IconButton(
                    icon: const Icon(Icons.close_rounded,
                        color: Colors.white54),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
              const Divider(color: Colors.white12, height: 30),
              Expanded(
                child: currentUserReference == null
                    ? const Center(
                        child: Text("접근 권한이 없습니다.",
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
                                    color: Colors.amber));
                          }
                          final records = snapshot.data!.docs;
                          if (records.isEmpty) {
                            return const Center(
                              child: Text("사용시간 로그가 없습니다.",
                                  style:
                                      TextStyle(color: Colors.white54)),
                            );
                          }

                          return ListView.separated(
                            itemCount: records.length,
                            separatorBuilder: (_, __) =>
                                const SizedBox(height: 10),
                            itemBuilder: (context, index) {
                              final data = records[index].data()
                                  as Map<String, dynamic>;

                              final DateTime ts = data['created_at'] != null
                                  ? (data['created_at'] as Timestamp)
                                      .toDate()
                                  : DateTime.now();
                              final String dateFormatted =
                                  DateFormat('yyyy.MM.dd HH:mm:ss')
                                      .format(ts);

                              final String modeRaw =
                                  (data['mode'] as String?) ??
                                      (data['reason'] as String?) ??
                                      'unknown';
                              final int secondsUsed =
                                  (data['seconds_used'] as int?) ?? 0;
                              final int actualSeconds =
                                  (data['actual_seconds'] as int?) ?? 0;
                              final int? beforeSeconds =
                                  data['before_seconds'] as int?;
                              final int? afterSeconds =
                                  data['after_seconds'] as int?;
                              final dynamic rateRaw = data['rate'];
                              final double? rate = rateRaw is double
                                  ? rateRaw
                                  : (rateRaw is num
                                      ? rateRaw.toDouble()
                                      : null);
                              final String? roomId =
                                  data['room_id'] as String?;

                              return Container(
                                padding: const EdgeInsets.all(14),
                                decoration: BoxDecoration(
                                  color: Colors.black,
                                  borderRadius: BorderRadius.circular(14),
                                  border:
                                      Border.all(color: Colors.white10),
                                ),
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment.spaceBetween,
                                      children: [
                                        Text(modeRaw,
                                            style: const TextStyle(
                                                color: Colors.amber,
                                                fontSize: 13,
                                                fontWeight:
                                                    FontWeight.bold)),
                                        Text(dateFormatted,
                                            style: const TextStyle(
                                                color: Colors.white38,
                                                fontSize: 10)),
                                      ],
                                    ),
                                    const SizedBox(height: 6),
                                    Text(
                                      "차감 ${_formatDurationFromSeconds(secondsUsed)}"
                                      "  ·  실제 ${_formatDurationFromSeconds(actualSeconds)}"
                                      "${rate != null ? '  ·  ${rate}x' : ''}",
                                      style: const TextStyle(
                                          color: Color(0xFF60A5FA),
                                          fontSize: 12),
                                    ),
                                    if (beforeSeconds != null &&
                                        afterSeconds != null) ...[
                                      const SizedBox(height: 4),
                                      Text(
                                        "잔여 ${_formatDurationFromSeconds(beforeSeconds)} → ${_formatDurationFromSeconds(afterSeconds)}",
                                        style: const TextStyle(
                                            color: Colors.white54,
                                            fontSize: 12),
                                      ),
                                    ],
                                    if (roomId != null &&
                                        roomId.isNotEmpty) ...[
                                      const SizedBox(height: 4),
                                      Text(
                                        "room: $roomId",
                                        style: const TextStyle(
                                            color: Colors.white38,
                                            fontSize: 11),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ],
                                  ],
                                ),
                              );
                            },
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

  @override
  Widget build(BuildContext context) {
    int displayMinutes = FFAppState().remainingTime ~/ 60;

    return Container(
      color: Colors.black,
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: SafeArea(
          child: Stack(
            children: [
              Column(
                children: [
                  // 상단 헤더
                  Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        IconButton(
                          icon: const Icon(Icons.arrow_back_ios_new_rounded,
                              color: Colors.white, size: 20),
                          onPressed: () => Navigator.pop(context),
                        ),
                        GestureDetector(
                          onLongPress: _openAdminTimeLogSheet,
                          child: Text("STORE",
                              style: GoogleFonts.orbitron(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white,
                                  letterSpacing: 2)),
                        ),
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (_showLogCopyButton)
                              IconButton(
                                icon: const Icon(Icons.copy,
                                    color: Colors.amber, size: 18),
                                tooltip: '로그 복사',
                                onPressed: () async {
                                  final text = _debugLogs.join('\n');
                                  await Clipboard.setData(
                                      ClipboardData(text: text));
                                  if (mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(
                                        content:
                                            Text('✅ 스토어 로그가 복사되었습니다'),
                                        duration: Duration(seconds: 1),
                                      ),
                                    );
                                  }
                                },
                              ),
                            IconButton(
                              onPressed: _openUsageSheet,
                              tooltip: 'Usage',
                              icon: const Icon(Icons.access_time_rounded,
                                  color: Color(0xFF60A5FA), size: 22),
                            ),
                            IconButton(
                              onPressed: _openReceiptSheet,
                              tooltip: 'Receipt',
                              icon: const Icon(Icons.receipt_long_rounded,
                                  color: Colors.amber, size: 22),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),

                  Expanded(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 20, vertical: 10),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          // 1. 잔여 시간 카드
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.symmetric(vertical: 24),
                            decoration: BoxDecoration(
                              color: const Color(0xFF222222),
                              borderRadius: BorderRadius.circular(24),
                              border: Border.all(color: Colors.white10),
                            ),
                            child: Column(
                              children: [
                                GestureDetector(
                                  onTap: () => setState(
                                      () => _showLogCopyButton = !_showLogCopyButton),
                                  child: const Icon(Icons.shield_moon_rounded,
                                      color: Colors.amber, size: 28),
                                ),
                                const SizedBox(height: 10),
                                Text("REMAINING TIME",
                                    style: GoogleFonts.orbitron(
                                        color: Colors.amber,
                                        fontSize: 11,
                                        letterSpacing: 2)),
                                const SizedBox(height: 6),
                                Text("${displayMinutes}m",
                                    style: GoogleFonts.orbitron(
                                        color: Colors.white,
                                        fontSize: 48,
                                        fontWeight: FontWeight.w900)),
                              ],
                            ),
                          ),
                          const SizedBox(height: 16),

                          // 2. 상품 리스트
                          ListView.separated(
                            shrinkWrap: true,
                            physics: const NeverScrollableScrollPhysics(),
                            itemCount: storePlans.length,
                            separatorBuilder: (_, __) =>
                                const SizedBox(height: 14),
                            itemBuilder: (context, index) {
                              final plan = storePlans[index];
                              return InkWell(
                                onTap: () => _executePurchase(plan),
                                borderRadius: BorderRadius.circular(20),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 14, vertical: 16),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF222222),
                                    borderRadius: BorderRadius.circular(20),
                                    border: Border.all(color: Colors.white10),
                                  ),
                                  child: Row(
                                    children: [
                                      Container(
                                        padding: const EdgeInsets.all(12),
                                        decoration: BoxDecoration(
                                          color: plan['theme_color']
                                              .withOpacity(0.15),
                                          shape: BoxShape.circle,
                                        ),
                                        child: Icon(plan['icon'],
                                            color: plan['theme_color'],
                                            size: 24),
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            FittedBox(
                                              fit: BoxFit.scaleDown,
                                              alignment: Alignment.centerLeft,
                                              child: Text(plan['title'],
                                                  style: const TextStyle(
                                                      color: Colors.white,
                                                      fontSize: 15,
                                                      fontWeight:
                                                          FontWeight.bold)),
                                            ),
                                            const SizedBox(height: 4),
                                            Text(plan['subtitle'],
                                                style: const TextStyle(
                                                    color: Colors.white54,
                                                    fontSize: 11),
                                                overflow: TextOverflow.ellipsis,
                                                maxLines: 1),
                                          ],
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      FittedBox(
                                        fit: BoxFit.scaleDown,
                                        child: Container(
                                          padding: const EdgeInsets.symmetric(
                                              horizontal: 12, vertical: 10),
                                          decoration: BoxDecoration(
                                            color: plan['theme_color']
                                                .withOpacity(0.15),
                                            borderRadius:
                                                BorderRadius.circular(12),
                                          ),
                                          child: Text(plan['price_text'],
                                              style: TextStyle(
                                                  color: plan['theme_color'],
                                                  fontSize: 12,
                                                  fontWeight: FontWeight.w800)),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              );
                            },
                          ),
                        ],
                      ),
                    ),
                  ),

                  // 하단 부가 기능 메뉴
                  Padding(
                    padding: const EdgeInsets.only(bottom: 4, top: 10),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        InkWell(
                          onTap: _runRestore,
                          child: const Text("Restore Purchases",
                              style: TextStyle(
                                  color: Colors.white38,
                                  fontSize: 11,
                                  decoration: TextDecoration.underline)),
                        ),
                        const Padding(
                          padding: EdgeInsets.symmetric(horizontal: 12.0),
                          child: Text("|",
                              style: TextStyle(
                                  color: Colors.white24, fontSize: 10)),
                        ),
                        InkWell(
                          onTap: () => _launchURL(
                              'https://www.ubizens.com/stealthvox/privacy.html'),
                          child: const Text("Privacy Policy",
                              style: TextStyle(
                                  color: Colors.white38,
                                  fontSize: 11,
                                  decoration: TextDecoration.underline)),
                        ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.only(bottom: 16),
                    child: Text(
                      _versionText,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                          color: Colors.white24, fontSize: 10),
                    ),
                  ),
                ],
              ),
              if (isProcessing)
                Container(
                  color: Colors.black87,
                  child: const Center(
                    child: CircularProgressIndicator(color: Colors.amber),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
