/// 全局主题与配色（参考 PokerTH 桌面版风格：绿呢桌面 + 深色底 + 金色点缀）
library;

import 'package:flutter/material.dart';

class AppTheme {
  static const bg = Color(0xFF10141c);
  static const panel = Color(0xFF1a2130);
  static const tableGreen = Color(0xFF1e7d46);
  static const tableGreenDark = Color(0xFF145732);
  static const tableRim = Color(0xFF6d4c35);
  static const gold = Color(0xFFe6c25a);
  static const cardRed = Color(0xFFd32f2f);
  static const foldRed = Color(0xFFc62828);
  static const callBlue = Color(0xFF1565c0);
  static const raiseGreen = Color(0xFF2e7d32);
  static const allinOrange = Color(0xFFe65100);

  static ThemeData dark() => ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        scaffoldBackgroundColor: bg,
        colorScheme: const ColorScheme.dark(
          primary: gold,
          secondary: callBlue,
          surface: panel,
        ),
        appBarTheme: const AppBarTheme(backgroundColor: panel),
        dividerColor: Colors.white12,
      );

  static String money(int n) {
    final s = n.toString();
    final b = StringBuffer();
    for (var i = 0; i < s.length; i++) {
      b.write(s[i]);
      final left = s.length - 1 - i;
      if (left > 0 && left % 3 == 0) b.write(',');
    }
    return '\$$b';
  }
}
