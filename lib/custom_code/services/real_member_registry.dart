import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

/// Keeps the operator-only `real_members` collection in sync.
///
/// Anonymous trial/Duo guests are deliberately excluded. The callable derives
/// all identity fields from the verified Firebase Auth token and Admin SDK.
class RealMemberRegistry {
  RealMemberRegistry._();

  static final FirebaseFunctions _functions =
      FirebaseFunctions.instanceFor(region: 'asia-northeast3');

  static Future<void> syncCurrentMember() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null || user.isAnonymous) return;
    try {
      await _functions
          .httpsCallable('syncRealMemberProfile')
          .call(<String, dynamic>{});
    } catch (error) {
      // Member reporting must never block the lobby or purchases.
      debugPrint('[RealMemberRegistry] sync failed: $error');
    }
  }
}
