import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';

FirebaseOptions get closerFirebaseOptions => kIsWeb
    ? const FirebaseOptions(
        apiKey: "AIzaSyDqQo3cpng76Uj5xqDIF1lW7n-a7Owz-Qg",
        appId: "1:97502564446:web:e8d6fc1bfd306030f364cf",
        messagingSenderId: "97502564446",
        projectId: "iseeapp-ddf3a",
        authDomain: "iseeapp-ddf3a.firebaseapp.com",
        storageBucket: "iseeapp-ddf3a.firebasestorage.app",
      )
    : defaultTargetPlatform == TargetPlatform.iOS
    ? const FirebaseOptions(
        apiKey: "AIzaSyAuSuKMgZICrcMTyVOrllYoKXHLiB0C71U",
        appId: "1:97502564446:ios:a8ed10fc2969166ff364cf",
        messagingSenderId: "97502564446",
        projectId: "iseeapp-ddf3a",
        iosBundleId: "com.jcm.closer",
      )
    : const FirebaseOptions(
        apiKey: "AIzaSyDG1LZ4juUA3q3KEvcRX7H9hwWcNaQvMhI",
        appId: "1:97502564446:android:663da6eab52bb389f364cf",
        messagingSenderId: "97502564446",
        projectId: "iseeapp-ddf3a",
      );
