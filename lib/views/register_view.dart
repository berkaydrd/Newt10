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
  bool _isLoading = false;
  
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

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  String _authMessage(FirebaseAuthException error) {
    switch (error.code) {
      case 'weak-password':
        return 'Şifre çok zayıf. En az 6 karakter kullanın.';
      case 'email-already-in-use':
        return 'Bu mail adresi zaten kayıtlı.';
      case 'invalid-email':
        return 'Mail adresi geçersiz.';
      case 'network-request-failed':
        return 'Ağ bağlantısı kurulamadı. İnternet bağlantınızı kontrol edin.';
      default:
        return 'Hesap oluşturulamadı: ${error.message ?? error.code}';
    }
  }

  Future<void> _register() async {
    final email = _email.text.trim();
    final password = _password.text.trim();
    final username = _username.text.trim();

    if (username.isEmpty || email.isEmpty || password.isEmpty) {
      _showMessage('Kullanıcı adı, mail ve şifre alanlarını doldurun.');
      return;
    }

    setState(() => _isLoading = true);
    UserCredential? userCredential;
    try {
      userCredential = await FirebaseAuth.instance
          .createUserWithEmailAndPassword(email: email, password: password);
      final uid = userCredential.user!.uid;
      await userCredential.user?.getIdToken(true);

      bool isAvailable;
      try {
        isAvailable = await FirestoreService.isUsernameAvailable(username);
      } on FirebaseException catch (e) {
        _showMessage('Adım 1 hatası [${e.plugin}/${e.code}]: ${e.message}');
        await userCredential.user?.delete();
        return;
      }

      if (!isAvailable) {
        await userCredential.user?.delete();
        _showMessage('Bu kullanıcı adı zaten alınmış.');
        return;
      }

      try {
        await FirebaseFirestore.instance
            .collection('usernames')
            .doc(username.toLowerCase())
            .set({
              'uid': uid,
              'username': username.toLowerCase(),
              'email': email,
            });
      } on FirebaseException catch (e) {
        _showMessage('Adım 2 hatası [${e.plugin}/${e.code}]: ${e.message}');
        await userCredential.user?.delete();
        return;
      }

      await userCredential.user?.sendEmailVerification();

      if (mounted) {
        Navigator.of(context).pushNamedAndRemoveUntil(
          '/verify_email/',
          (route) => false,
        );
      }
    } on FirebaseAuthException catch (e) {
      _showMessage(_authMessage(e));
    } on FirebaseException catch (e) {
      _showMessage('Genel DB hatası [${e.plugin}/${e.code}]: ${e.message}');
      await userCredential?.user?.delete();
    } catch (e) {
      _showMessage('Beklenmeyen hata: $e');
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
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
              onPressed: _isLoading ? null : _register,
              child: _isLoading
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Hesap Oluştur'),
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
