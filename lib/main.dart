import 'dart:io';

import 'package:cats_scanner/screens/home_screen.dart';
import 'package:cats_scanner/screens/login_screen.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

const apiToken =
    'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJleHAiOjE3MjI3MjcwNDMsImlhdCI6MTcyMjY0MDY0MywiaXNzIjoiU3QuUmlra3kiLCJyb2xlcyI6WyJ1c2VyIl0sInN1YiI6IjY2N2ViNjFiMjdmZTI0MzYyYzAwMDAwMCJ9.BqNYTXEDXcA6ubNF7GwMCKh2EZLEWyCPr3nsqFqapwA';
// const baseUrl = 'https://cats_backend_dart-dczoe7q-mikkyboy357.globeapp.dev';
const baseUrl = 'http://192.168.1.18:8080';

class MyHttpOverrides extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) {
    return super.createHttpClient(context)
      ..badCertificateCallback =
          (X509Certificate cert, String host, int port) => true;
  }
}

void main() {
  HttpOverrides.global = MyHttpOverrides();
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        title: 'Flutter Demo',
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
        ),
        home: const AuthWrapper(),
      ),
    );
  }
}

class AuthWrapper extends StatefulWidget {
  const AuthWrapper({super.key});

  @override
  State<AuthWrapper> createState() => _AuthWrapperState();
}

class _AuthWrapperState extends State<AuthWrapper> {
  bool? isLoggedIn;

  @override
  void initState() {
    super.initState();
    _checkLoginStatus();
  }

  Future<void> _checkLoginStatus() async {
    final prefs = await SharedPreferences.getInstance();
    final loggedIn = prefs.getBool('isLoggedIn') ?? false;
    setState(() {
      isLoggedIn = loggedIn;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (isLoggedIn == null) {
      // Show loading while checking login status
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return isLoggedIn! ? const HomeScreen() : const LoginScreen();
  }
}
