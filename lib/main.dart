/// 德州扑克（蓝牙局域网 · 锦标赛盲注 · 支持 AI 单机）入口
library;

import 'package:flutter/material.dart';

import 'ui/screens.dart';
import 'ui/theme.dart';

void main() {
  // 把 release 模式下默认的「灰屏」替换为可读的报错界面，
  // 既提升体验，也方便定位真机上的未捕获异常（而不再是一片灰）。
  ErrorWidget.builder = (details) {
    final msg = details.exceptionAsString();
    return Scaffold(
      backgroundColor: AppTheme.bg,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('应用出错（已捕获）',
                  style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Colors.redAccent)),
              const SizedBox(height: 12),
              const Text('请把下面这段文字反馈给开发者：',
                  style: TextStyle(color: Colors.white70)),
              const SizedBox(height: 8),
              Text(msg,
                  style: const TextStyle(
                      fontSize: 12, color: Colors.white54)),
            ],
          ),
        ),
      ),
    );
  };
  runApp(const MyApp());
}

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
