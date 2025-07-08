import 'package:bluetooth_poc/app_scanning.dart';
import 'package:bluetooth_poc/controller/requirement_state_controller.dart';
import 'package:bluetooth_poc/home_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:get/get.dart';

// Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
//   const platform = MethodChannel('ble_advertiser_scanner');
//   try {
//     await platform.invokeMethod('startAdvertisingFromStoredUUID');
//   } catch (e) {
//     debugPrint('Error invoking BLE method from background: $e');
//   }
// }

// Future<void> requestNotificationPermissions() async {
//   FirebaseMessaging messaging = FirebaseMessaging.instance;

//   NotificationSettings settings = await messaging.requestPermission(
//     alert: true,
//     announcement: false,
//     badge: true,
//     carPlay: false,
//     criticalAlert: false,
//     provisional: true, // Allow provisional permissions for silent pushes
//     sound: true,
//   );

//   if (settings.authorizationStatus == AuthorizationStatus.authorized ||
//       settings.authorizationStatus == AuthorizationStatus.provisional) {
//     print('User granted permission (or provisional)');

//     // Wait for APNS token with a longer timeout and more retries
//     String? apnsToken;
//     int retry = 0;
//     const maxRetries = 10;
//     const delaySeconds = 2;

//     while (apnsToken == null && retry < maxRetries) {
//       apnsToken = await messaging.getAPNSToken();
//       if (apnsToken == null) {
//         print('APNS token not available yet, retrying (${retry + 1}/$maxRetries)...');
//         await Future.delayed(Duration(seconds: delaySeconds));
//       }
//       retry++;
//     }

//     if (apnsToken != null) {
//       print("APNS TOKEN: $apnsToken");
//       String? fcmToken = await messaging.getToken();
//       print("FCM TOKEN: $fcmToken");
//     } else {
//       print("Failed to get APNS token after $maxRetries retries.");
//     }
//   } else {
//     print('User declined or has not accepted permission');
//   }
// }

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // await Firebase.initializeApp();
  // requestNotificationPermissions();
  // FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);
  runApp(MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    Get.put(RequirementStateController());
    //Set the fit size (Find your UI design, look at the dimensions of the device screen and fill it in,unit in dp)
    return ScreenUtilInit(
      designSize: const Size(380, 844),
      minTextAdapt: true,
      splitScreenMode: true,
      builder: (_, child) {
        return MaterialApp(
          debugShowCheckedModeBanner: false,
          title: 'First Method',
          theme: ThemeData(
            colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
            useMaterial3: true,
          ),
          home: child,
        );
      },
      child: HomePage(),
    );
  }
}
