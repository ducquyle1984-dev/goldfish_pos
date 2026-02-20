import 'package:flutter/material.dart';

/// Placeholder for the main point-of-sale screen that users see after login.
class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('POS Home')),
      body: const Center(child: Text('Welcome to the POS system!')),
    );
  }
}
