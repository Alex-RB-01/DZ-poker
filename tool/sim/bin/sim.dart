// 德州扑克引擎离线验证：直接调用真实引擎 lib/engine/game.dart 与 ai.dart
// 运行：在 poker_app/tool/sim/ 目录下执行  dart pub get && dart run bin/sim.dart
import 'dart:math';

import '../../lib/engine/game.dart';
import '../../lib/engine/ai.dart';

class Check {
  final bool ok;
  final String msg;
  const Check(this.ok, this.msg);
}

class TourResult {
  final bool ok;
  final int winner;
  final int hands;
  final String msg;
  const TourResult(
      {required this.ok, required this.winner, required this.hands, this.msg = ''});
}

void main() {
  final seed = DateTime.now().microsecondsSinceEpoch;
  final rng = Random(seed);
  print('=== 德州扑克引擎验证（运行真实 Dart 引擎，非移植）===');
  print('随机种子: $seed  （每次运行不同 → 发牌序列不同，保证随机性）');
  print('');

  _assertEvaluator();
  print('');

  _dealFairness(rng);
  print('');

  // 跑 10 场锦标赛：5 人（你 + 4 个 AI），全程校验不变量
  final wins = List.filled(5, 0);
  final buttonCounts = List.filled(5, 0);
  var totalHands = 0;
  var ok = true;
  var fatal = '';
  for (var t = 1; t <= 10; t++) {
    final r = _playTournament(rng, t, buttonCounts);
    if (!r.ok) {
      ok = false;
      fatal = '第 $t 场异常: ${r.msg}';
      break;
    }
    totalHands += r.hands;
    wins[r.winner]++;
    print('  第$t 场结束 → 冠军座位${r.winner}，共 ${r.hands} 手');
  }
  print('');
  print('—— 汇总 ——');
  print('总手数: $totalHands');
  print('各座位夺冠次数(10场): $wins  (期望≈每人2次)');
  print('各座位当“按钮/庄家”次数: $buttonCounts  (应大致相等)');
  if (ok) {
    print('✅ 10 场全部跑通，筹码守恒、无崩溃、无非法动作、淘汰判定正确');
  } else {
    print('❌ 发现 bug：');
    print(fatal);
  }
}

void _assertEvaluator() {
  int fails = 0;
  void expect(String name, bool cond) {
    if (!cond) {
      fails++;
      print('  ❌ $name');
    }
  }

  Card c(int r, int s) => Card(r, s);
  // 同花顺 > 四条
  expect(
      '同花顺>四条',
      cmpEval(
              eval7([
                c(10, 0),
                c(11, 0),
                c(12, 0),
                c(13, 0),
                c(14, 0),
                c(2, 1),
                c(3, 2)
              ]),
              eval7([
                c(14, 0),
                c(14, 1),
                c(14, 2),
                c(14, 3),
                c(2, 0),
                c(3, 1),
                c(4, 2)
              ])) >
          0);
  // 轮子 A-2-3-4-5 顺子高牌为 5
  final wheel = eval5([c(14, 0), c(2, 1), c(3, 2), c(4, 0), c(5, 1)]);
  expect('轮子顺类别=4', wheel[0] == 4);
  expect('轮子顺高牌=5', wheel[1] == 5);
  // 四条 > 葫芦
  expect(
      '四条>葫芦',
      cmpEval(
              eval7([c(9, 0), c(9, 1), c(9, 2), c(9, 3), c(2, 0)]),
              eval7([c(5, 0), c(5, 1), c(5, 2), c(8, 0), c(8, 1)])) >
          0);
  // 葫芦类别=6
  expect('葫芦类别=6',
      eval5([c(5, 0), c(5, 1), c(5, 2), c(8, 0), c(8, 1)])[0] == 6);
  // 两对比高牌踢脚
  expect(
      '两对比高牌踢脚',
      cmpEval(
              eval5([c(14, 0), c(14, 1), c(13, 0), c(13, 1), c(2, 2)]),
              eval5([c(14, 0), c(14, 1), c(13, 0), c(13, 1), c(3, 2)])) <
          0);
  // 同花 > 顺子
  final flush = eval5([c(2, 0), c(5, 0), c(7, 0), c(9, 0), c(11, 0)]);
  expect('同花类别=5', flush[0] == 5);
  expect('同花非顺子', flush[0] != 4);

  print('牌型评估断言: ${fails == 0 ? "✅ 全部通过" : "⚠️ $fails 条失败"}');
}

void _dealFairness(Random rng) {
  const n = 5;
  const hands = 30000;
  final aa = List.filled(n, 0);
  final pair = List.filled(n, 0);
  for (var h = 0; h < hands; h++) {
    final d = Deck(rng: rng)..shuffle();
    for (var s = 0; s < n; s++) {
      final a = d.deal();
      final b = d.deal();
      if (a.rank == 14 && b.rank == 14) aa[s]++;
      if (a.rank == b.rank && a.rank != 14) pair[s]++;
    }
  }
  // 每个座位每手拿到 AA 的概率 = 1/221
  final exp = hands / 221.0;
  double chi = 0;
  for (var s = 0; s < n; s++) {
    chi += (aa[s] - exp) * (aa[s] - exp) / exp;
  }
  print('发牌随机性/公平性（${hands}手×$n座位，共${hands * n}次发牌）:');
  print('  各座位拿到 AA(口袋A)次数: $aa  (期望≈${exp.toStringAsFixed(0)})');
  print('  各座位拿到口袋对子(非AA)次数: $pair');
  final chiCrit = 9.49; // 自由度4 @95%
  print('  AA 分布卡方值=$chi  (临界$chiCrit) → ${chi < chiCrit ? "均匀✅ 无座位被偏爱" : "疑似偏差⚠️"}');
}

TourResult _playTournament(Random rng, int t, List<int> buttonCounts) {
  final cfg =
      GameConfig(startingChips: 1000, advanceEvery: 6, advanceMode: 'hands');
  final g = GameState(config: cfg, rng: rng);
  g.newGame(
      [for (var i = 0; i < 5; i++) PlayerSeed('P$i', isAI: true)]);
  var hands = 0;
  var actions = 0;
  const maxActions = 1000000;
  final total = cfg.startingChips * 5;

  while (!g.gameOver) {
    if (g.handOver) {
      g.startHand();
      hands++;
      if (hands > 200000) {
        return TourResult(ok: false, winner: -1, hands: hands, msg: '手数超限，疑似死循环');
      }
      buttonCounts[g.button]++;
      final c0 = _conservation(g, total);
      if (!c0.ok) return TourResult(ok: false, winner: -1, hands: hands, msg: c0.msg);
    }

    final act = AIPlayer.decide(g, rng);
    final applied = g.act(g.toAct, act);
    if (!applied) {
      return TourResult(
          ok: false,
          winner: -1,
          hands: hands,
          msg: 'AI 产生非法动作被拒: ${act.type} amount=${act.amount} seat=${g.toAct}\n${_dump(g)}');
    }
    actions++;
    if (actions > maxActions) {
      return TourResult(ok: false, winner: -1, hands: hands, msg: '动作数超限');
    }
    // 手已结束的瞬间不做守恒校验（结算后贡献额尚未清零，下一手开场会校验）
    if (!g.handOver) {
      final c1 = _conservation(g, total);
      if (!c1.ok) {
        return TourResult(ok: false, winner: -1, hands: hands, msg: c1.msg);
      }
    }
  }

  // 结束时：应仅 1 人存活，且总筹码守恒
  final alive = g.players.where((p) => !p.out).length;
  if (alive != 1) {
    return TourResult(ok: false, winner: -1, hands: hands, msg: '结束时应仅1人存活，实际 $alive');
  }
  final sumChips = g.players.fold(0, (s, p) => s + p.chips);
  if (sumChips != total) {
    return TourResult(ok: false, winner: -1, hands: hands, msg: '终局筹码不守恒: $sumChips != $total');
  }
  final winner = g.players.firstWhere((p) => !p.out).seat;
  return TourResult(ok: true, winner: winner, hands: hands);
}

Check _conservation(GameState g, int total) {
  var chips = 0;
  var contributed = 0;
  for (final p in g.players) {
    chips += p.chips;
    contributed += p.totalContributed;
  }
  if (chips + contributed != total) {
    return Check(false,
        '筹码不守恒: chips=$chips contributed=$contributed sum=${chips + contributed} 期望=$total\n${_dump(g)}');
  }
  return const Check(true, '');
}

String _dump(GameState g) {
  final sb = StringBuffer();
  sb.writeln('street=${g.street} toAct=${g.toAct} currentBet=${g.currentBet} pot=${g.potTotal} level=${g.level}');
  for (final p in g.players) {
    sb.writeln(
        '  seat${p.seat} ${p.name} chips=${p.chips} bet=${p.roundBet} contributed=${p.totalContributed} ${p.folded ? "FOLD" : ""}${p.allIn ? " ALLIN" : ""}${p.out ? " OUT" : ""}${p.hasCards ? " cards=${p.hole.map((c) => c.text).join("")}" : ""}');
  }
  sb.writeln('board=${g.board.map((c) => c.text).join(" ")}');
  return sb.toString();
}
