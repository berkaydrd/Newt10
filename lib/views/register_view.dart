// ignore_for_file: unused_field

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_application_newtten/utilities/firestore_service.dart';

class RegisterView extends StatefulWidget {
  const RegisterView({super.key});

  @override
  // ignore: library_private_types_in_public_api
  _RegisterViewState createState() =>  _RegisterViewState();
}

class  _RegisterViewState extends State<RegisterView> {
  late final TextEditingController _email;
  late final TextEditingController _password;
  late final TextEditingController _username;
  
  @override
  void initState() {
    _email = TextEditingController();
    _password = TextEditingController();
    _username = TextEditingController();
    super.initState();
  }

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    _username.dispose();
    super.dispose();
  }
  
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Hesap Oluştur',
          style: TextStyle(
            fontSize: 25.0,
            fontWeight: FontWeight.w500,
          ),
        ),
        centerTitle: true,
        elevation: 0.2,
        shadowColor: Colors.black,
      ),
      body: Column(
        children: [
          SizedBox(height: 40.0),
          Padding(//                          Username
            padding: const EdgeInsets.only(
              top: 0.0,
              bottom: 10.0,
              right: 20.0,
              left: 20.0,
            ),
            child: TextField(
              controller: _username,
              enableSuggestions: false,
              autocorrect: false,
              decoration: InputDecoration(
                hintText: 'Kullanıcı Adı',
                
                contentPadding: EdgeInsets.symmetric(
                  vertical: 10.0,
                  horizontal: 30.0
                ),
                hintStyle: const TextStyle(
                  fontSize: 15,
                  color: Color.fromARGB(210, 128, 128, 128),
                ),
                
                filled: true,
                fillColor: const Color.fromARGB(100, 224, 224, 224),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12.0),
                  borderSide: const BorderSide(
                    color: Colors.black,
                    width: 1.0,
                  ),
                ),
              ),
            ),
          ),
          Padding(//                          Email
            padding: const EdgeInsets.only( 
              top: 0.0,
              bottom: 10.0,
              right: 20.0,
              left: 20.0,
            ),
            child: TextField(
              controller: _email,
              enableSuggestions: false,
              autocorrect: false,
              keyboardType: TextInputType.emailAddress,
              decoration: InputDecoration(
                hintText: 'Email',
      
                contentPadding: const EdgeInsets.symmetric( // Size of Container
                  vertical: 10.0,
                  horizontal: 30.0
                ),
      
                hintStyle: const TextStyle( // Text style
                  fontSize: 15.0,
                  color: Color.fromARGB(210, 128, 128, 128),
                ),
                
                filled: true, // Container color
                fillColor: const Color.fromARGB(100, 224, 224, 224),
                
                border: OutlineInputBorder( // Container border
                  borderRadius: BorderRadius.circular(12.0),
                  borderSide: const BorderSide(
                    color: Colors.black,
                    width: 1.0, 
                  ),
                ),
              ),
            ),
          ),
          Padding(//                          Password
            padding: const EdgeInsets.only(
              top: 0.0,
              bottom: 0.0,
              right: 20.0,
              left: 20.0,
            ),
            child: TextField(
              controller: _password,
              obscureText: true,
              enableSuggestions: false,
              autocorrect: false,
              decoration: InputDecoration(
                hintText: 'Password',
                
                contentPadding: EdgeInsets.symmetric(
                  vertical: 10.0,
                  horizontal: 30.0
                ),
                hintStyle: const TextStyle(
                  fontSize: 15,
                  color: Color.fromARGB(210, 128, 128, 128),
                ),
                
                filled: true,
                fillColor: const Color.fromARGB(100, 224, 224, 224),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12.0),
                  borderSide: const BorderSide(
                    color: Colors.black,
                    width: 1.0,
                  ),
                ),
              ),
            ),
          ),
          TextButton(
              onPressed: () async{
      
                final email = _email.text.trim();
                final password = _password.text.trim();
                final username = _username.text.trim();

                final isAvailable = await FirestoreService.isUsernameAvailable(username);
                
                if (!isAvailable){
                  print('Bu kullanıcı adı zaten alınmış. ');
                  return;
                }
                try {
                  // ignore: unused_local_variable
                  final userCredential = await FirebaseAuth.instance.createUserWithEmailAndPassword(
                    email: email, 
                    password: password
                  );
                  final uid = userCredential.user!.uid;
                  await FirebaseFirestore.instance.collection('usernames').doc(username.toLowerCase()).set({
                    'uid': uid,
                    'username': username,
                    'email': email,
                  });
                  if (mounted) {
                    Navigator.of(context).pushNamedAndRemoveUntil(
                      '/verify_email/',
                      (route) => false,
                      );
                  }
                }
                on FirebaseAuthException catch(e){
                  if (e.code == 'weak-password'){
                    print('Güçsüz Şifre');
                  }
                  else if (e.code == 'email-already-in-use'){
                    print('Bu Mail Adresi Zaten Mevcut');
                  }
                  else if (e.code == 'invalid-email'){
                    print('Mail Adresi Geçersiz');
                  }
                }
              },
              child: const Text('Sign In'),
          ),
          TextButton(//                       NewAccount
            onPressed: () {
              Navigator.of(context).pushNamedAndRemoveUntil(
                '/login/',
                (route) => false,);
            },

            style: ButtonStyle(
              foregroundColor: WidgetStatePropertyAll(Color.fromARGB(150, 0, 0, 0)),
              backgroundColor: WidgetStatePropertyAll(Color.fromARGB(200, 224, 224, 224)),
              overlayColor: WidgetStatePropertyAll(Colors.brown),
              minimumSize: WidgetStatePropertyAll(Size(364, 50))
            ), 

            child: const Text('Hesaba Giriş Yap')
          )
        ],                  
      ),
    );
  }
}
