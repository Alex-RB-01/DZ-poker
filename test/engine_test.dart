/// 德州扑克引擎单元测试（纯 Dart，无需 Flutter 环境）
///
/// 运行：在装有 Dart/Flutter 的环境下执行
///   flutter test
/// 或（仅 Dart，使用 package:test）
///   dart test
library;

import 'package:flutter_test/flutter_test.dart';

import 'package:poker_app/engine/game.dart';

// 辅助：造牌 (rank 2..14, suit 0..3)
Card c(int rank, int suit) => Card(rank, suit);
List<int> e5(List<Card> cs) => eval5(cs);
int cmp(List<int> a, List<int> b) => cmpEval(a, b);

void main() {
  group('牌型评估 eval5 / eval7', () {
    test('同花顺 > 四条', () {
      final sf = [c(5, 0), c(6, 0), c(7, 0), c(8, 0), c(9, 0)];
      final quads = [c(9, 0), c(9, 1), c(9, 2), c(9, 3), c(2, 0)];
      expect(e5(sf)[0], 8);
      expect(e5(quads)[0], 7);
      expect(cmp(e5(sf), e5(quads)) > 0, isTrue);
    });

    test('轮子顺子 A-2-3-4-5（A 当最小）', () {
      final wheel = [c(14, 0), c(2, 1), c(3, 2), c(4, 3), c(5, 0)];
      expect(e5(wheel)[0], 4); // 顺子
      expect(e5(wheel)[1], 5); // 高点 5
      final sixHigh = [c(6, 0), c(2, 1), c(3, 2), c(4, 3), c(5, 0)];
      expect(cmp(e5(wheel), e5(sixHigh)) < 0, isTrue); // 5-high < 6-high
    });

    test('葫芦：带牌决胜', () {
      final kk3 = [c(13, 0), c(13, 1), c(13, 2), c(3, 0), c(3, 1)];
      final qqA = [c(12, 0), c(12, 1), c(12, 2), c(14, 0), c(14, 1)];
      expect(e5(kk3)[0], 6);
      expect(cmp(e5(kk3), e5(qqA)) > 0, isTrue); // K  Full > Q Full
    });

    test('同花 / 顺子 大小', () {
      final flush = [c(2, 0), c(5, 0), c(9, 0), c(11, 0), c(13, 0)];
      final straight = [c(6, 0), c(7, 1), c(8, 2), c(9, 3), c(10, 0)];
      expect(e5(flush)[0], 5);
      expect(e5(straight)[0], 4);
      expect(cmp(e5(flush), e5(straight)) > 0, isTrue);
    });

    test('两对：高对/低对/边牌 决胜', () {
      final a = [c(14, 0), c(14, 1), c(5, 2), c(5, 3), c(2, 0)]; // AА55 + 2
      final b = [c(13, 0), c(13, 1), c(5, 2), c(5, 3), c(2, 0)]; // KK55 + 2
      expect(e5(a)[0], 2);
      expect(cmp(e5(a), e5(b)) > 0, isTrue);
    });

    test('一对：踢脚牌决胜', () {
      final a = [c(10, 0), c(10, 1), c(14, 2), c(13, 3), c(2, 0)];
      final b = [c(10, 0), c(10, 1), c(14, 2), c(12, 3), c(2, 0)];
      expect(cmp(e5(a), e5(b)) > 0, isTrue);
    });

    test('eval7 从 7 张中选出最强 5 张', () {
      // 4 张同花 + 1 张同花色凑成同花
      final seven = [
        c(2, 0), c(5, 0), c(9, 0), c(11, 0), c(14, 0), // 5 张同花
        c(13, 1), c(3, 2),
      ];
      final best = eval7(seven);
      expect(best[0], 5); // 同花
    });

    test('平局：完全相同的牌型算作平分', () {
      final a = [c(14, 0), c(13, 1), c(12, 2), c(11, 3), c(9, 0)];
      final b = [c(14, 1), c(13, 0), c(12, 3), c(11, 2), c(9, 1)];
      expect(cmp(e5(a), e5(b)), 0);
    });
  });

  group('边池 buildPots（all-in 分层）', () {
    test('三人不同投入 → 主池 + 两个边池', () {
      final g = GameState(config: GameConfig(startingChips: 1000));
      g.players = [
        PlayerState(seat: 0, name: 'A')
          ..hasCards = true
          ..totalContributed = 100
          ..chips = 900,
        PlayerState(seat: 1, name: 'B')
          ..hasCards = true
          ..totalContributed = 300
          ..chips = 700,
        PlayerState(seat: 2, name: 'C')
          ..hasCards = true
          ..totalContributed = 300
          ..chips = 700,
        PlayerState(seat: 3, name: 'D')
          ..hasCards = true
          ..totalContributed = 50
          ..chips = 950,
      ];
      final pots = g.buildPots();
      // 总筹码守恒：100+300+300+50 = 750
      final total = pots.fold<int>(0, (s, p) => s + p.amount);
      expect(total, 750);
      expect(pots.length, 3);
      expect(pots[0].amount, 200); // 所有 4 人可争
      expect(pots[0].seats.toSet(), {0, 1, 2, 3});
      expect(pots[1].amount, 150); // A/B/C 可争
      expect(pots[1].seats.toSet(), {0, 1, 2});
      expect(pots[2].amount, 400); // 仅 B/C 可争
      expect(pots[2].seats.toSet(), {1, 2});
    });

    test('有人弃牌：其投入只进池、无资格赢', () {
      final g = GameState(config: GameConfig(startingChips: 1000));
      g.players = [
        PlayerState(seat: 0, name: 'A')
          ..hasCards = true
          ..totalContributed = 200
          ..chips = 800,
        PlayerState(seat: 1, name: 'B')
          ..hasCards = false // 已弃牌
          ..totalContributed = 200
          ..chips = 800,
      ];
      final pots = g.buildPots();
      expect(pots.length, 1);
      expect(pots[0].amount, 400);
      expect(pots[0].seats, [0]); // B 不可争
    });
  });

  group('整手流程与筹码守恒', () {
    test('开局下注：盲注已扣、轮到 SB 行动（单挑）', () {
      final g = GameState(config: GameConfig(startingChips: 1000));
      g.newGame([PlayerSeed('A'), PlayerSeed('B')]);
      g.startHand();
      // 单挑：button=SB, 另一人为BB
      expect(g.handOver, isFalse);
      expect(g.board.length, 0);
      expect(g.handNumber, 1);
      // 底池 = 小盲5 + 大盲10 = 15；总筹码守恒 2000
      expect(g.potTotal, 15);
      final sumChips = g.players.fold<int>(0, (s, p) => s + p.chips);
      expect(sumChips + g.potTotal, 2000);
      // 轮到小盲（button）行动，且需跟注 5
      final legal = g.legalActions(g.toAct);
      expect(legal.canCheck, isFalse);
      expect(legal.callAmount, 5);
    });

    test('一圈平跟到翻牌：筹码守恒、翻出 3 张公共牌', () {
      final g = GameState(config: GameConfig(startingChips: 1000));
      g.newGame([PlayerSeed('A'), PlayerSeed('B')]);
      g.startHand();
      final sb = g.toAct; // 小盲先行动
      final bb = g.bbSeat;
      // 小盲跟注（call 5）
      expect(g.act(sb, const PokerAction('call')), isTrue);
      // 大盲过牌
      expect(g.act(bb, const PokerAction('check')), isTrue);
      // 进入翻牌
      expect(g.board.length, 3);
      final sumChips = g.players.fold<int>(0, (s, p) => s + p.chips);
      expect(sumChips + g.potTotal, 2000);
    });

    test('非法动作被拒绝：轮到谁才能动、不能平跟当过牌', () {
      final g = GameState(config: GameConfig(startingChips: 1000));
      g.newGame([PlayerSeed('A'), PlayerSeed('B')]);
      g.startHand();
      final notToAct = g.toAct == 0 ? 1 : 0;
      // 非行动者出牌应被忽略
      expect(g.act(notToAct, const PokerAction('fold')), isFalse);
      // 小盲面前有大盲注，不能 check
      expect(g.act(g.toAct, const PokerAction('check')), isFalse);
    });

    test('加注提高 currentBet，并 reopen 行动权', () {
      final g = GameState(config: GameConfig(startingChips: 1000));
      g.newGame([PlayerSeed('A'), PlayerSeed('B')]);
      g.startHand();
      final sb = g.toAct;
      final bb = g.bbSeat;
      // 小盲加注到 30
      expect(g.act(sb, PokerAction('raise', amount: 30)), isTrue);
      expect(g.currentBet, 30);
      // 大盲现在需跟注 20
      final legal = g.legalActions(bb);
      expect(legal.callAmount, 20);
    });
  });

  group('锦标赛盲注递增', () {
    test('按局数递增：第 2 手后升到第 2 级', () {
      final g = GameState(
          config: GameConfig(startingChips: 1000, advanceMode: 'hands',
              advanceEvery: 1));
      g.newGame([PlayerSeed('A'), PlayerSeed('B')]);
      g.startHand();
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
    test('结构字段保持一致（注：快照不序列化逐人投入额）', () {
      final g = GameState(config: GameConfig(startingChips: 1000));
      g.newGame([PlayerSeed('A'), PlayerSeed('B')]);
      g.startHand();
      final map = g.toMap(forSeat: 0);
      final g2 = GameState.fromMap(map);
      expect(g2.players.length, g.players.length);
      expect(g2.handNumber, g.handNumber);
      expect(g2.board.length, g.board.length);
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
  });
}
