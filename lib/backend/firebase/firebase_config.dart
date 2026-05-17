import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';

Future initFirebase() async {
  if (kIsWeb) {
    await Firebase.initializeApp(
        options: FirebaseOptions(
            apiKey: "AIzaSyCDEDlP9kQltGL38V0f7qS0GYjLzsq86bA",
            authDomain: "stealth-vox-3p3rq3.firebaseapp.com",
            projectId: "stealth-vox-3p3rq3",
            storageBucket: "stealth-vox-3p3rq3.firebasestorage.app",
            messagingSenderId: "450483026108",
            appId: "1:450483026108:web:362efbb9c26ec7bb3db8b9"));
  } else {
    await Firebase.initializeApp();
  }
}
