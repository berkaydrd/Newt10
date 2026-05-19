import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_application_newtten/firebase_options.dart';
import 'package:flutter_application_newtten/utilities/notification_service.dart';
import 'package:flutter_application_newtten/views/login_view.dart';
import 'package:flutter_application_newtten/views/profile_page_view.dart';
import 'package:flutter_application_newtten/views/register_view.dart';
import 'package:flutter_application_newtten/views/verify_email_view.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await dotenv.load(fileName: '.env');

  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  FirebaseFirestore.instance.settings = const Settings(persistenceEnabled: false);
  await NotificationService().init();
  
  runApp(
    MaterialApp(
      title: 'Flutter Demo',
      theme: ThemeData(
      ),
      home: const LoginView(),
      routes: {
        '/login/': (context) => const LoginView(),
        '/register/': (context) => const RegisterView(),
        '/verify_email/': (context) => const VerifyEmailView(),
        '/profile_page' : (context) => const ProfilePage(),
      },
    ),
  );
}

class HomePage extends StatelessWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context) {
    return FutureBuilder(
      future: Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform,
      ), 
      builder: (context, snapshot){
        switch (snapshot.connectionState){
          case ConnectionState.done:
            final user = FirebaseAuth.instance.currentUser;
            if (user != null) {
              user.reload();
              if(user.emailVerified != false){
                return ProfilePage();
              }
              else {
                return const VerifyEmailView();
              }
            }
            else {
              return const LoginView();
          }
          default:
            return const CircularProgressIndicator();
        }
      },
    );
  }
}
