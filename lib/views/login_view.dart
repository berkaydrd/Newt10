import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

class LoginView extends StatefulWidget {
  const LoginView({super.key});

  @override
  State<LoginView> createState() => _LoginViewState();
}

class _LoginViewState extends State<LoginView> {
  late final TextEditingController _email;
  late final TextEditingController _password;

  @override
  void initState() {
    _email = TextEditingController();
    _password = TextEditingController();
    super.initState();
  }

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }
  
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.center, 
        mainAxisSize: MainAxisSize.max,
        children: [
          Padding(
            padding: const EdgeInsets.only(
              top:  15.0,
              bottom: 0.0,
              left: 50.0,
              right: 50.0,
            ),
            child: SizedBox(
              width: 200.0,
              height: 200.0,
              child: Image.asset(
                'assets/images/Logo1.png',
                fit: BoxFit.contain,
              ),
            ),
          ),
          Text(
            'NewtNet',
            style: TextStyle(
              fontStyle: FontStyle.normal,
              fontSize: 45.0,
              fontWeight: FontWeight.w500,
            ),
          ),
          Padding(//                          Email
            padding: const EdgeInsets.only( 
              top: 50.0,
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
      
                hintStyle: const TextStyle(
                  fontSize: 15.0,
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
          Padding(//                          LoginButton
            padding: const EdgeInsets.only(
              top: 10.0,
              bottom: 0.0,
              right: 0.0,
              left: 0.0,
            ),
            child: TextButton(
              
              onPressed: () async{  
                final email = _email.text;
                final password = _password.text;
                try {
                  // ignore: unused_local_variable
                  final userCredential = await FirebaseAuth.instance.signInWithEmailAndPassword(
                    email: email,
                    password: password
                  );
                  if (userCredential.user != null){
                    Navigator.of(context).pushNamedAndRemoveUntil(
                      '/profile_page',
                      (route) =>false
                    );
                  }
                }
                on FirebaseAuthException catch(e){
                  if (e.code == 'user-not-found'){
                    print('Kullanıcı Bulunamadı');
                  }
                  else if (e.code == 'wrong password'){
                    print('Parola Yanlış');
                  }
                }
              },
      
              style: ButtonStyle(
                foregroundColor: WidgetStatePropertyAll(Colors.white),
                backgroundColor: WidgetStatePropertyAll(Colors.black),
                minimumSize: WidgetStatePropertyAll(Size(364, 50)),
                overlayColor: WidgetStatePropertyAll(Colors.brown),
              ),
              
              child: const Text('Giriş Yap')
            ),
          ),
          Padding(//                          ForgetPass
            padding: const EdgeInsets.only(
              top: 10.0,
              bottom: 0.0,
              right: 0.0,
              left: 0.0,
            ),
            child: TextButton(
              onPressed: () {  },
            
              style: ButtonStyle(
                foregroundColor: WidgetStatePropertyAll(Color.fromARGB(150, 0, 0, 0)),
                backgroundColor: WidgetStatePropertyAll(Colors.transparent),
                overlayColor: WidgetStatePropertyAll(Colors.transparent),
              ),
            
              child: const Text('Şifremi Unuttum')
            ),
          ),
          SizedBox(height: 145.0),
          Text(
            "Mevcut bir hesabınız yok mu ?",
            style: TextStyle(
              fontStyle: FontStyle.normal,
              fontSize: 13.0,
              color: Color.fromARGB(150, 0, 0, 0)
             ),
          ),
          SizedBox(height: 8.0),
          TextButton(//                       NewAccount
            onPressed: () {
              Navigator.of(context).pushNamedAndRemoveUntil(
                '/register/',
                (route) => false,
              );
            },
      
             style: ButtonStyle(
              foregroundColor: WidgetStatePropertyAll(Color.fromARGB(150, 0, 0, 0)),
              backgroundColor: WidgetStatePropertyAll(Color.fromARGB(200, 224, 224, 224)),
              overlayColor: WidgetStatePropertyAll(Colors.brown),
              minimumSize: WidgetStatePropertyAll(Size(364, 50))
            ), 
            child: const Text('Yeni Hesap Oluştur')
          )
        ],
      ),
    );
  }
}