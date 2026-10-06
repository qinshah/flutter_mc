import 'package:flutter/material.dart';

import 'routes.dart';

void main() {
  runApp(const FlutterMcApp());
}

class FlutterMcApp extends StatelessWidget {
  const FlutterMcApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'flutter_mc',
      debugShowCheckedModeBanner: false,
      routes: mcRoutes,
      onGenerateRoute: mcOnGenerateRoute,
    );
  }
}
