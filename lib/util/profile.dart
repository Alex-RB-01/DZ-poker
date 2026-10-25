/// 玩家资料持久化：昵称 + 性别。头像由 AvatarStore 单独持久化。
/// 单机与联网共用同一份资料，除非手动修改否则一直保留。
library;

import 'package:shared_preferences/shared_preferences.dart';

class ProfileStore {
  static const _nameKey = 'my_name';
  static const _genderKey = 'my_gender';

  static Future<String> loadName() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getString(_nameKey) ?? '玩家';
    } catch (_) {
      return '玩家';
    }
  }

  static Future<String> loadGender() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getString(_genderKey) ?? 'male';
    } catch (_) {
      return 'male';
    }
  }

  static Future<void> saveName(String name) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_nameKey, name);
    } catch (_) {}
  }

  static Future<void> saveGender(String gender) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_genderKey, gender);
    } catch (_) {}
  }
}
