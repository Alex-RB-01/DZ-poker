/// 真人声动作语音：弃牌 / 跟注 / 加注 / 全下。
///
/// 按性别播放 assets/voices/voice_{gender}_{action}.wav。
/// gender: 'male'（男声）/ 'female'（女声）；action: fold/call/raise/allin。
/// 说明：受工具限制无法克隆真实明星声线，这里用高质量中文神经 TTS 作为占位真人声；
/// 若你有肖战 / 林志玲等真人配音片段，按同名文件替换 assets/voices/ 下对应 wav 即可。
/// 播放失败（文件缺失/设备占用）静默忽略，不影响牌局。
library;

import 'package:audioplayers/audioplayers.dart';

class VoiceSound {
  VoiceSound._();

  /// 播放某座位的动作语音。allIn=true 时统一播「全下」，覆盖 call/raise 的实际类型。
  static Future<void> playAction(
      String gender, String action, bool allIn) async {
    final String clip;
    if (allIn) {
      clip = 'allin';
    } else if (action == 'fold') {
      clip = 'fold';
    } else if (action == 'call') {
      clip = 'call';
    } else if (action == 'raise') {
      clip = 'raise';
    } else {
      return; // check 等不发音
    }
    final g = (gender == 'female') ? 'female' : 'male';
    final asset = 'voices/voice_${g}_$clip.mp3';
    try {
      final player = AudioPlayer();
      await player.play(AssetSource(asset));
      player.onPlayerComplete.first.then((_) async {
        try {
          await player.dispose();
        } catch (_) {}
      });
    } catch (_) {
      // 音频异常不影响牌局逻辑
    }
  }
}
