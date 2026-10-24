/// 头像：从手机相册选图 → 复制到应用文档目录持久化 → 提供 base64 缩略图用于联机分发。
library;

import 'dart:convert';
import 'dart:io';

import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AvatarStore {
  static const _prefKey = 'my_avatar_path';

  /// 当前已保存的头像文件路径（未设置返回 null）
  static Future<String?> loadPath() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final p = prefs.getString(_prefKey);
      if (p == null) return null;
      if (!File(p).existsSync()) return null;
      return p;
    } catch (_) {
      return null;
    }
  }

  /// 从相册选图并持久化；返回文件路径，取消/失败返回 null
  static Future<String?> pickAndSave() async {
    try {
      final x = await ImagePicker()
          .pickImage(source: ImageSource.gallery, maxWidth: 256, maxHeight: 256, imageQuality: 75);
      if (x == null) return null;
      final dir = await getApplicationDocumentsDirectory();
      final avDir = Directory('${dir.path}/avatars');
      if (!avDir.existsSync()) avDir.createSync(recursive: true);
      final dest = File('${avDir.path}/me.jpg');
      await x.saveTo(dest.path);
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefKey, dest.path);
      return dest.path;
    } catch (_) {
      return null;
    }
  }

  /// 读取头像文件并压缩为 base64（用于联机发送，通常 < 15KB）
  static Future<String?> toBase64(String? path) async {
    if (path == null) return null;
    try {
      final f = File(path);
      if (!f.existsSync()) return null;
      final bytes = await f.readAsBytes();
      if (bytes.length > 60 * 1024) return null; // 过大不发送，防止拖慢握手
      return base64Encode(bytes);
    } catch (_) {
      return null;
    }
  }
}
