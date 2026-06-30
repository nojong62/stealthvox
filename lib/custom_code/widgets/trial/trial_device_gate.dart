import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_app_installations/firebase_app_installations.dart';
import 'package:firebase_auth/firebase_auth.dart';

class TrialDeviceGate {
  static Future<bool> canTrial() async {
    try {
      final fid = await FirebaseInstallations.instance.getId();
      final doc = await FirebaseFirestore.instance
          .collection('trial_devices')
          .doc(fid)
          .get();
      return !doc.exists;
    } catch (_) {
      return true;
    }
  }

  static Future<void> markUsed() async {
    try {
      final fid = await FirebaseInstallations.instance.getId();
      final uid = FirebaseAuth.instance.currentUser?.uid ?? 'unknown';
      await FirebaseFirestore.instance
          .collection('trial_devices')
          .doc(fid)
          .set({
        'uid': uid,
        'used_at': FieldValue.serverTimestamp(),
      });
    } catch (_) {}
  }
}
