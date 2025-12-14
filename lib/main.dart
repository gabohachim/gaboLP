import 'package:flutter/material.dart';
import 'ui/home_screen.dart';

void main() {
  runApp(const GaBoLpApp());
}

class GaBoLpApp extends StatelessWidget {
  const GaBoLpApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Colección vinilos',
      theme: ThemeData(useMaterial3: true),
      home: const HomeScreen(),
    );
  }
}
