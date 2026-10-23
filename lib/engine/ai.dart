/// AI 对手：启发式决策
/// - 翻牌前：起手牌强度粗估（对子/高张/同花连张）
/// - 翻牌后：蒙特卡洛模拟胜率（随机对手手牌 + 补全公共牌），对比底池赔率
library;

import 'dart:math';

import 'game.dart';

class AIPlayer {
  static PokerAction decide(GameState g, Random rng) {
    final me = g.players[g.toAct];
    final legal = g.legalActions(me.seat);

    final double equity;
    if (g.street == Street.preflop) {
      equity = _preflopEquity(me.hole, g.inHandPlayers.length - 1);
    } else {
      equity = _equityMC(g, rng, trials: 160);
    }

    final pot = g.potTotal;
    final call = legal.callAmount;
    final potOdds = pot + call > 0 ? call / (pot + call) : 0.0;
    final e = equity + (rng.nextDouble() - 0.5) * 0.08; // 随机扰动，避免打法死板

    // 需要全下才能跟
    if (call >= me.chips && call > 0) {
      if (e > 0.58) return const PokerAction('call');
      if (e > potOdds + 0.08 && call <= pot * 0.35) {
        return const PokerAction('call');
      }
      return const PokerAction('fold');
    }

    // 无需跟注（可过牌）
    if (call == 0) {
      if (legal.canRaise && e > 0.62 && rng.nextDouble() < 0.8) {
        return _bet(g, legal, e, rng);
      }
      if (legal.canRaise && e > 0.5 && rng.nextDouble() < 0.25) {
        return _bet(g, legal, e, rng);
      }
      if (legal.canRaise && e < 0.32 && rng.nextDouble() < 0.06) {
        return _bet(g, legal, e, rng); // 偶尔诈唬
      }
      return const PokerAction('check');
    }

    // 面对下注
    if (e > 0.82 && legal.canRaise && rng.nextDouble() < 0.7) {
      return _bet(g, legal, e, rng);
    }
    if (e > potOdds + 0.03) return const PokerAction('call');
    if (call <= g.blinds.bb && e > 0.3) return const PokerAction('call');
    if (rng.nextDouble() < 0.04) return const PokerAction('call'); // 偶尔粘一下
    return const PokerAction('fold');
  }

  static PokerAction _bet(
      GameState g, LegalActions legal, double e, Random rng) {
    int to;
    if (e > 0.88 || rng.nextDouble() < 0.08) {
      to = legal.maxRaiseTo; // 强牌或偶尔直接全下
    } else {
      final frac = e > 0.7 ? 0.75 : 0.5;
      final potBet = (g.potTotal * frac).round();
      to = legal.minRaiseTo > g.currentBet + potBet
          ? legal.minRaiseTo
          : g.currentBet + potBet;
      if (to > legal.maxRaiseTo) to = legal.maxRaiseTo;
    }
    if (to <= g.currentBet) return const PokerAction('call');
    return PokerAction('raise', amount: to);
  }

  /// 翻牌前胜率粗估（单人对手基准再按人数衰减）
  static double _preflopEquity(List<Card> hole, int nOpp) {
    if (hole.length < 2) return 0.4;
    final r1 = hole[0].rank > hole[1].rank ? hole[0].rank : hole[1].rank;
    final r2 = hole[0].rank > hole[1].rank ? hole[1].rank : hole[0].rank;
    double base;
    if (r1 == r2) {
      base = 0.52 + (r1 - 2) * 0.02;
    } else {
      base = 0.33 + (r1 - 2) * 0.011 + (r2 - 2) * 0.006;
      if (hole[0].suit == hole[1].suit) base += 0.03;
      final gap = r1 - r2;
      if (gap == 1) {
        base += 0.02;
      } else if (gap == 2) {
        base += 0.01;
      }
      if (r1 == 14 && r2 >= 12) base += 0.03; // AK/AQ 类
    }
    final eq = base - nOpp * 0.11;
    return eq.clamp(0.08, 0.95);
  }

  /// 蒙特卡洛胜率：随机给对手发牌、随机补全公共牌
  static double _equityMC(GameState g, Random rng, {int trials = 160}) {
    final me = g.players[g.toAct];
    final used = <int>{
      for (final c in me.hole) c.code,
      for (final c in g.board) c.code,
    };
    final pool = [
      for (var code = 0; code < 52; code++)
        if (!used.contains(code)) Card.fromCode(code)
    ];
    final oppCount = g.inHandPlayers.length - 1;
    if (oppCount <= 0) return 1.0;
    var win = 0.0;
    for (var t = 0; t < trials; t++) {
      pool.shuffle(rng);
      var idx = 0;
      final oppHoles = [
        for (var o = 0; o < oppCount; o++) [pool[idx++], pool[idx++]]
      ];
      final fullBoard = [...g.board];
      while (fullBoard.length < 5) {
        fullBoard.add(pool[idx++]);
      }
      final myScore = eval7([...me.hole, ...fullBoard]);
      var result = 1; // 1 赢 / 0 平 / -1 输
      for (final oh in oppHoles) {
        final c = cmpEval(myScore, eval7([...oh, ...fullBoard]));
        if (c < 0) {
          result = -1;
          break;
        }
        if (c == 0) result = 0;
      }
      if (result > 0) {
        win += 1;
      } else if (result == 0) {
        win += 0.5;
      }
    }
    return win / trials;
  }
}
