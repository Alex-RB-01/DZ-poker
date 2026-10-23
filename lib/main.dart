/// 德州扑克（蓝牙局域网 · 锦标赛盲注 · 支持 AI 单机）入口
library;

import 'package:flutter/material.dart';

import 'ui/screens.dart';
import 'ui/theme.dart';

void main() => runApp(const MyApp());

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '德州扑克',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.dark(),
      home: const HomeScreen(),
    );
  }
}
