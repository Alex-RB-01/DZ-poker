/// 德州扑克电子筹码引擎单元测试（纯 Dart，无需 Flutter 环境）
///
/// 运行：在装有 Dart/Flutter 的环境下执行
///   flutter test
/// 或（仅 Dart，使用 package:test）
///   dart test
library;

import 'package:flutter_test/flutter_test.dart';

import 'package:poker_app/engine/game.dart';

/// 辅助：让当前行动者「过牌或跟注」（call，金额为 0 时引擎自动视为过牌），
/// 直到本轮下注结束（streetDone）。返回是否成功推进。
bool _actAll(GameState g) {
  var guard = 0;
  while (!g.streetDone && g.toAct >= 0 && guard < 100) {
    guard++;
    g.act(g.toAct, const PokerAction('call'));
  }
  return g.streetDone;
}

/// 辅助：打完一整手（四条街都平跟），停在河牌 streetDone 状态。
void _playFullHand(GameState g) {
  _actAll(g); // 翻牌前
  g.advanceStreet();
  _actAll(g); // 翻牌
  g.advanceStreet();
  _actAll(g); // 转牌
  g.advanceStreet();
  _actAll(g); // 河牌
}

void main() {
  group('开局与盲注', () {
    test('开局收大小盲、轮到小盲行动（单挑 SB=button）', () {
      final g = GameState(config: GameConfig(startingChips: 1000));
      g.newGame([PlayerSeed('A'), PlayerSeed('B')]);
      g.startHand();
      expect(g.handOver, isFalse);
      expect(g.handNumber, 1);
      expect(g.street, Street.preflop);
      // 底池 = 小盲5 + 大盲10 = 15；总筹码守恒 2000
      expect(g.potTotal, 15);
      final sumChips = g.players.fold<int>(0, (s, p) => s + p.chips);
      expect(sumChips + g.potTotal, 2000);
      // 单挑：button 即小盲，先行动且需跟注 5
      expect(g.toAct, g.sbSeat);
      final legal = g.legalActions(g.toAct);
      expect(legal.canCheck, isFalse);
      expect(legal.callAmount, 5);
    });

    test('多人局：按钮轮转，SB/BB 紧随按钮之后', () {
      final g = GameState(config: GameConfig(startingChips: 1000));
      g.newGame([PlayerSeed('A'), PlayerSeed('B'), PlayerSeed('C')]);
      g.startHand();
      // newGame 时 button=2，startHand 先轮转到 0；SB=1，BB=2
      expect(g.button, 0);
      expect(g.sbSeat, 1);
      expect(g.bbSeat, 2);
    });
  });

  group('下注流程（不再自动发牌，本轮结束停在 streetDone）', () {
    test('单挑平跟一圈 → streetDone=true，不进翻牌', () {
      final g = GameState(config: GameConfig(startingChips: 1000));
      g.newGame([PlayerSeed('A'), PlayerSeed('B')]);
      g.startHand();
      final sb = g.toAct;
      final bb = g.bbSeat;
      expect(g.act(sb, const PokerAction('call')), isTrue);
      expect(g.act(bb, const PokerAction('check')), isTrue);
      // 下注轮结束，但不发牌，等待房主推进
      expect(g.streetDone, isTrue);
      expect(g.street, Street.preflop);
      expect(g.toAct, -1);
      final sumChips = g.players.fold<int>(0, (s, p) => s + p.chips);
      expect(sumChips + g.potTotal, 2000);
    });

    test('advanceStreet 推进街道：preflop → flop', () {
      final g = GameState(config: GameConfig(startingChips: 1000));
      g.newGame([PlayerSeed('A'), PlayerSeed('B')]);
      g.startHand();
      _actAll(g);
      expect(g.advanceStreet(), isTrue);
      expect(g.street, Street.flop);
      expect(g.streetDone, isFalse);
      // 翻牌后轮到按钮位之后的第一个行动者（单挑即大盲 BB）
      expect(g.toAct, g.bbSeat);
    });

    test('非法推进：下注未结束不能推进', () {
      final g = GameState(config: GameConfig(startingChips: 1000));
      g.newGame([PlayerSeed('A'), PlayerSeed('B')]);
      g.startHand();
      expect(g.advanceStreet(), isFalse); // 还没下注完
      expect(g.street, Street.preflop);
    });
  });

  group('加注与行动权', () {
    test('加注提高 currentBet 并 reopen 行动权', () {
      final g = GameState(config: GameConfig(startingChips: 1000));
      g.newGame([PlayerSeed('A'), PlayerSeed('B')]);
      g.startHand();
      final sb = g.toAct;
      final bb = g.bbSeat;
      expect(g.act(sb, PokerAction('raise', amount: 30)), isTrue);
      expect(g.currentBet, 30);
      final legal = g.legalActions(bb);
      expect(legal.callAmount, 20);
    });

    test('非法动作被拒绝', () {
      final g = GameState(config: GameConfig(startingChips: 1000));
      g.newGame([PlayerSeed('A'), PlayerSeed('B')]);
      g.startHand();
      final notToAct = g.toAct == 0 ? 1 : 0;
      expect(g.act(notToAct, const PokerAction('fold')), isFalse);
      expect(g.act(g.toAct, const PokerAction('check')), isFalse);
    });
  });

  group('手动结算', () {
    test('河牌下注结束 → settleHand 分给赢家，筹码守恒', () {
      final g = GameState(config: GameConfig(startingChips: 1000));
      g.newGame([PlayerSeed('A'), PlayerSeed('B')]);
      g.startHand();
      _playFullHand(g);
      expect(g.street, Street.river);
      expect(g.streetDone, isTrue);
      final pot = g.potTotal; // 20（每人10）
      final winnerSeat = g.button;
      final loserSeat = g.bbSeat;
      final loserChipsBefore = g.players[loserSeat].chips;
      expect(g.settleHand([winnerSeat]), isTrue);
      expect(g.handOver, isTrue);
      expect(g.lastResult!.seatWin[winnerSeat], pot);
      // 赢家获得底池，总筹码守恒
      final sumChips = g.players.fold<int>(0, (s, p) => s + p.chips);
      expect(sumChips, 2000);
      expect(g.players[loserSeat].chips, loserChipsBefore);
    });

    test('未到河牌不能结算', () {
      final g = GameState(config: GameConfig(startingChips: 1000));
      g.newGame([PlayerSeed('A'), PlayerSeed('B')]);
      g.startHand();
      expect(g.settleHand([0]), isFalse);
    });

    test('多人平分：底池按人头均分', () {
      final g = GameState(config: GameConfig(startingChips: 1000));
      g.newGame([PlayerSeed('A'), PlayerSeed('B'), PlayerSeed('C')]);
      g.startHand();
      _playFullHand(g);
      expect(g.streetDone, isTrue);
      final pot = g.potTotal;
      expect(g.settleHand([0, 1]), isTrue);
      final sumChips = g.players.fold<int>(0, (s, p) => s + p.chips);
      expect(sumChips, 3000);
      expect(g.lastResult!.seatWin[0]! + g.lastResult!.seatWin[1]!, pot);
    });

    test('全弃牌只剩一人 → 可直接结算给该赢家', () {
      final g = GameState(config: GameConfig(startingChips: 1000));
      g.newGame([PlayerSeed('A'), PlayerSeed('B'), PlayerSeed('C')]);
      g.startHand();
      // 依次弃牌直到只剩一人
      while (g.inHandPlayers.length > 1) {
        g.act(g.toAct, const PokerAction('fold'));
      }
      final winner = g.inHandPlayers.first;
      expect(g.settleHand([winner.seat]), isTrue);
      expect(g.handOver, isTrue);
    });
  });

  group('锦标赛盲注递增', () {
    test('按局数递增：第 2 手后升到第 2 级', () {
      final g = GameState(
          config: GameConfig(
              startingChips: 1000, advanceMode: 'hands', advanceEvery: 1));
      g.newGame([PlayerSeed('A'), PlayerSeed('B')]);
      g.startHand();
      // 打完第一手
      _playFullHand(g);
      g.settleHand([g.button]);
      expect(g.handOver, isTrue);
      g.startHand(); // 第二手触发升级
      expect(g.level, 1);
      expect(g.blinds.sb, GameConfig.defaultLevels()[1].sb);
    });

    test('手动 advanceLevel 提升级别', () {
      final g = GameState(config: GameConfig(startingChips: 1000));
      g.newGame([PlayerSeed('A'), PlayerSeed('B')]);
      final before = g.blinds.bb;
      expect(g.advanceLevel(), isTrue);
      expect(g.blinds.bb > before, isTrue);
    });
  });

  group('序列化往返 toMap / fromMap', () {
    test('结构字段保持一致', () {
      final g = GameState(config: GameConfig(startingChips: 1000));
      g.newGame([PlayerSeed('A'), PlayerSeed('B')]);
      g.startHand();
      final map = g.toMap(forSeat: 0);
      final g2 = GameState.fromMap(map);
      expect(g2.players.length, g.players.length);
      expect(g2.handNumber, g.handNumber);
      expect(g2.street, g.street);
      expect(g2.streetDone, g.streetDone);
      expect(g2.toAct, g.toAct);
      expect(g2.blinds.bb, g.blinds.bb);
    });
  });

  group('淘汰与比赛结束', () {
    test('仅剩一名存活玩家 → startHand 置 gameOver', () {
      final g = GameState(config: GameConfig(startingChips: 1000));
      g.newGame([PlayerSeed('A'), PlayerSeed('B')]);
      g.players[1].out = true; // B 已淘汰
      g.startHand(); // liveCount=1 → 结束
      expect(g.gameOver, isTrue);
      expect(g.liveCount, 1);
    });

    test('结算后筹码输光者出局，仅剩一人则比赛结束', () {
      final g = GameState(config: GameConfig(startingChips: 1000));
      g.newGame([PlayerSeed('A'), PlayerSeed('B')]);
      g.startHand();
      // 让 A 全下，B 全跟，B 输光
      final aSeat = g.sbSeat;
      final bSeat = g.bbSeat;
      g.act(aSeat, PokerAction('raise', amount: 1000));
      g.act(bSeat, const PokerAction('call')); // B 全下跟注
      // 河牌（全下后需推进到河牌才能结算）
      g.advanceStreet();
      g.advanceStreet();
      g.advanceStreet();
      expect(g.settleHand([aSeat]), isTrue);
      expect(g.players[bSeat].out, isTrue);
      expect(g.gameOver, isTrue);
    });
  });
}
