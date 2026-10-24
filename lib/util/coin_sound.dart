/// 金币音效：每次有人下注/跟注/赢池时播放一次「哗啦啦」声。
///
/// 使用 audioplayers 播放打包在 assets 里的 coin.wav（由 gen_coin_wav.py 合成）。
/// 播放失败（如设备音频被占用）不影响牌局，仅静默忽略。
library;

import 'package:audioplayers/audioplayers.dart';

class CoinSound {
  CoinSound._();

  /// 播放一次金币哗啦声。每次下注/跟注或赢池调用一次。
  static Future<void> play() async {
    try {
      final player = AudioPlayer();
      await player.play(AssetSource('coin.wav'));
      // 播放结束自动释放，避免实例堆积
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
