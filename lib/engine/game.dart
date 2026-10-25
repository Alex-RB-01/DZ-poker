/// 德州扑克「电子筹码」引擎（纯 Dart，无 Flutter 依赖，可独立单测）。
///
/// 定位：线下实体牌桌打真牌时，本引擎只负责筹码记账与盲注计时，不涉及发牌、牌型评估。
/// - 下注动作：弃牌/过牌/跟注/加注/全下（all-in 是状态而非独立动作）
/// - 四条街（翻牌前/翻牌/转牌/河牌）由「房主手动推进」，跟随实体桌发牌节奏
/// - 一局结束时由房主手动指定赢家（可多选平分），把底池分给赢家
library;

import 'dart:math';

enum Street { preflop, flop, turn, river }

// ---------------- 玩家 / 配置 ----------------

class PlayerState {
  final int seat;
  String name;
  bool isAI;
  int chips;
  String gender; // 'male' 男声 / 'female' 女声（用于动作语音）
  int roundBet = 0; // 本轮下注
  int totalContributed = 0; // 本手总投入
  bool folded = false;
  bool allIn = false;
  bool out = false; // 锦标赛出局
  bool acted = false; // 本轮是否已行动

  PlayerState(
      {required this.seat,
      required this.name,
      this.isAI = false,
      this.gender = 'male',
      this.chips = 0});

  /// 仍在本手中（未弃牌且未出局）
  bool get inHand => !folded && !out;
}

class PlayerSeed {
  final String name;
  final bool isAI;
  final String gender; // 'male' / 'female'
  const PlayerSeed(this.name, {this.isAI = false, this.gender = 'male'});
}

class BlindLevel {
  final int sb;
  final int bb;
  const BlindLevel(this.sb, this.bb);
}

class GameConfig {
  int startingChips;
  List<BlindLevel> levels;
  int advanceEvery; // 每级持续（按 advanceMode 解释）
  String advanceMode; // 'hands' | 'minutes'

  GameConfig(
      {this.startingChips = 5000,
      List<BlindLevel>? levels,
      this.advanceEvery = 10,
      this.advanceMode = 'hands'})
      : levels = levels ?? GameConfig.defaultLevels();

  static List<BlindLevel> defaultLevels() {
    const bbs = [10, 20, 30, 50, 75, 100, 150, 200, 300, 500, 750, 1000];
    return [for (final bb in bbs) BlindLevel(bb ~/ 2, bb)];
  }

  Map<String, dynamic> toMap() => {
        'startingChips': startingChips,
        'advanceEvery': advanceEvery,
        'advanceMode': advanceMode,
        'levels': [
          for (final l in levels)
            {'sb': l.sb, 'bb': l.bb}
        ],
      };

  static GameConfig fromMap(Map<String, dynamic> m) => GameConfig(
        startingChips: (m['startingChips'] as num).toInt(),
        advanceEvery: (m['advanceEvery'] as num).toInt(),
        advanceMode: m['advanceMode'] as String,
        levels: [
          for (final l in (m['levels'] as List))
            BlindLevel((l['sb'] as num).toInt(), (l['bb'] as num).toInt())
        ],
      );
}

class PokerAction {
  final String type; // fold | check | call | raise
  final int amount; // raise: 加注到的总额（raise to）
  const PokerAction(this.type, {this.amount = 0});
}

class LegalActions {
  final bool canCheck;
  final int callAmount;
  final bool canRaise;
  final int minRaiseTo;
  final int maxRaiseTo;
  const LegalActions(
      {required this.canCheck,
      required this.callAmount,
      required this.canRaise,
      required this.minRaiseTo,
      required this.maxRaiseTo});
}

/// 一手牌的结果：底池如何分给赢家（由房主手动指定）。
class HandResult {
  final int totalPot;
  final Map<int, int> seatWin; // seat -> 本手赢得
  final Map<int, int> perWin; // seat -> 平分到的金额（用于展示）
  const HandResult({
    required this.totalPot,
    required this.seatWin,
    required this.perWin,
  });
}

// ---------------- 游戏状态机 ----------------

class GameState {
  GameConfig config;
  // 默认为空列表：房主模式在点「开始游戏」前 newGame() 尚未调用，此时 players 应为空，
  // 便于 UI 安全渲染等候房（原 late 字段会在未初始化时访问即抛 LateInitializationError）。
  List<PlayerState> players = [];
  int button = 0;
  int level = 0;
  int handsAtLevel = 0;
  Street street = Street.preflop;
  int currentBet = 0;
  int lastFullRaise = 0;
  int toAct = -1;
  int sbSeat = -1;
  int bbSeat = -1;
  int handNumber = 0;
  bool handOver = true;
  bool gameOver = false;
  /// 当前街道的下注是否已结束（等待房主推进到下一街道 / 结算）。
  bool streetDone = false;
  List<String> log = [];
  HandResult? lastResult;

  GameState({GameConfig? config}) : config = config ?? GameConfig();

  BlindLevel get blinds =>
      config.levels[level.clamp(0, config.levels.length - 1)];

  int get potTotal {
    var s = 0;
    for (final p in players) {
      s += p.totalContributed;
    }
    return s;
  }

  int get liveCount => players.where((p) => !p.out).length;
  List<PlayerState> get inHandPlayers => players.where((p) => p.inHand).toList();

  String _bl() => '${blinds.sb}/${blinds.bb}';

  /// 开新比赛（一场锦标赛）
  void newGame(List<PlayerSeed> seeds) {
    players = [
      for (var i = 0; i < seeds.length; i++)
        PlayerState(
            seat: i,
            name: seeds[i].name,
            isAI: seeds[i].isAI,
            gender: seeds[i].gender,
            chips: config.startingChips)
    ];
    button = players.length - 1; // 第一手会轮到 0
    level = 0;
    handsAtLevel = 0;
    handNumber = 0;
    handOver = true;
    gameOver = false;
    streetDone = false;
    lastResult = null;
    log = ['游戏开始：${players.length} 人，初始筹码 ${config.startingChips}'];
  }

  /// 下一手牌：不发牌，只重置状态、轮转按钮、收大小盲。
  /// 盲注按局数递增在这里自动处理。
  void startHand() {
    if (gameOver) return;
    if (liveCount <= 1) {
      gameOver = true;
      return;
    }
    for (final p in players) {
      p.roundBet = 0;
      p.totalContributed = 0;
      p.folded = false;
      p.allIn = false;
      p.acted = false;
    }
    lastResult = null;
    street = Street.preflop;
    streetDone = false;
    handNumber++;
    handsAtLevel++;
    if (config.advanceMode == 'hands' &&
        handsAtLevel > config.advanceEvery &&
        level < config.levels.length - 1) {
      level++;
      handsAtLevel = 1;
      log.add('— 盲注升级：${_bl()} —');
    }

    do {
      button = (button + 1) % players.length;
    } while (players[button].out);

    if (liveCount == 2) {
      sbSeat = button; // 单挑：按钮位即小盲
      bbSeat = _nextAlive(button);
    } else {
      sbSeat = _nextAlive(button);
      bbSeat = _nextAlive(sbSeat);
    }

    _post(sbSeat, blinds.sb, '小盲');
    _post(bbSeat, blinds.bb, '大盲');
    currentBet = max(players[sbSeat].roundBet, players[bbSeat].roundBet);
    lastFullRaise = max(currentBet, blinds.bb);
    handOver = false;
    log.add('—— 第 $handNumber 手 —— 盲注 ${_bl()}');
    toAct = _nextActor(bbSeat);
    if (toAct < 0) _endBettingRound(); // 罕见：全员盲注即全下
  }

  bool advanceLevel() {
    if (level >= config.levels.length - 1) return false;
    level++;
    handsAtLevel = 0;
    log.add('— 手动升级盲注：${_bl()} —');
    return true;
  }

  /// 玩家掉线时强制弃牌
  void forceFold(int seat) {
    final p = players[seat];
    if (handOver || p.folded || p.out) return;
    p.folded = true;
    p.acted = true;
    log.add('${p.name} 掉线，自动弃牌');
    if (toAct == seat) {
      toAct = _nextActor(seat);
      if (toAct < 0) {
        _endBettingRound();
        return;
      }
    }
    if (inHandPlayers.length <= 1 && !handOver) _endBettingRound();
  }

  /// 房主手动推进到下一街道（翻牌前→翻牌→转牌→河牌）。
  /// 只有当前街道下注已结束、且尚未到河牌时有效。
  bool advanceStreet() {
    if (handOver || gameOver || !streetDone) return false;
    if (street == Street.river) return false; // 河牌后应直接结算
    switch (street) {
      case Street.preflop:
        street = Street.flop;
        log.add('— 翻牌 —');
        break;
      case Street.flop:
        street = Street.turn;
        log.add('— 转牌 —');
        break;
      case Street.turn:
        street = Street.river;
        log.add('— 河牌 —');
        break;
      case Street.river:
        return false;
    }
    streetDone = false;
    toAct = _nextActor(button);
    if (toAct < 0) _endBettingRound(); // 全员全下
    return true;
  }

  int _nextAlive(int seat) {
    for (var i = 1; i <= players.length; i++) {
      final s = (seat + i) % players.length;
      if (!players[s].out) return s;
    }
    return seat;
  }

  void _post(int seat, int amount, String label) {
    final p = players[seat];
    final pay = amount < p.chips ? amount : p.chips;
    p.chips -= pay;
    p.roundBet += pay;
    p.totalContributed += pay;
    if (p.chips == 0) p.allIn = true;
    log.add('${p.name} $label \$$pay${p.allIn ? '（全下）' : ''}');
  }

  bool _needsAction(PlayerState p) =>
      !p.folded && !p.out && !p.allIn && (!p.acted || p.roundBet < currentBet);

  int _nextActor(int from) {
    for (var i = 1; i <= players.length; i++) {
      final s = (from + i) % players.length;
      if (_needsAction(players[s])) return s;
    }
    return -1;
  }

  LegalActions legalActions(int seat) {
    final p = players[seat];
    final callAmount = currentBet - p.roundBet > p.chips
        ? p.chips
        : currentBet - p.roundBet;
    final maxRaiseTo = p.roundBet + p.chips;
    final minRaiseTo = maxRaiseTo < currentBet + lastFullRaise
        ? maxRaiseTo
        : currentBet + lastFullRaise;
    return LegalActions(
      canCheck: currentBet == p.roundBet,
      callAmount: callAmount < 0 ? 0 : callAmount,
      canRaise: maxRaiseTo > currentBet,
      minRaiseTo: minRaiseTo,
      maxRaiseTo: maxRaiseTo,
    );
  }

  /// 执行动作。返回 false 表示非法（被忽略）。
  bool act(int seat, PokerAction a) {
    if (handOver || streetDone || toAct != seat) return false;
    final p = players[seat];
    final legal = legalActions(seat);
    switch (a.type) {
      case 'fold':
        p.folded = true;
        log.add('${p.name} 弃牌');
      case 'check':
        if (!legal.canCheck) return false;
        log.add('${p.name} 过牌');
      case 'call':
        final pay = legal.callAmount;
        if (pay > p.chips) return false;
        p.chips -= pay;
        p.roundBet += pay;
        p.totalContributed += pay;
        if (p.chips == 0) p.allIn = true;
        log.add('${p.name} ${pay == 0 ? '过牌' : '跟注 \$$pay'}${p.allIn ? '（全下）' : ''}');
      case 'raise':
        if (!legal.canRaise) return false;
        var to = a.amount;
        if (to > legal.maxRaiseTo) to = legal.maxRaiseTo;
        if (to < legal.minRaiseTo && to < legal.maxRaiseTo) to = legal.minRaiseTo;
        if (to <= currentBet) return false;
        final raiseSize = to - currentBet;
        final pay = to - p.roundBet;
        p.chips -= pay;
        p.roundBet = to;
        p.totalContributed += pay;
        if (p.chips == 0) p.allIn = true;
        if (raiseSize >= lastFullRaise) {
          // 完整加注：重开行动权
          lastFullRaise = raiseSize;
          for (final q in players) {
            if (q.seat != seat) q.acted = false;
          }
        }
        currentBet = to;
        log.add('${p.name} 加注到 \$$to${p.allIn ? '（全下）' : ''}');
      default:
        return false;
    }
    p.acted = true;
    toAct = _nextActor(seat);
    if (toAct < 0) _endBettingRound();
    return true;
  }

  void _endBettingRound() {
    // 返还未被跟注的部分
    final bets = players.where((p) => !p.folded && !p.out).map((p) => p.roundBet).toList()
      ..sort((a, b) => b - a);
    if (bets.length > 1 && bets[0] > bets[1]) {
      final top =
          players.firstWhere((p) => !p.folded && !p.out && p.roundBet == bets[0]);
      final refund = bets[0] - bets[1];
      top.roundBet -= refund;
      top.chips += refund;
      top.totalContributed -= refund;
      if (top.chips > 0) top.allIn = false;
      log.add('退回 ${top.name} 未被跟注的 \$$refund');
    }
    for (final p in players) {
      p.roundBet = 0;
      p.acted = false;
    }
    currentBet = 0;
    lastFullRaise = blinds.bb;
    toAct = -1;

    // 若只剩一人未弃牌 → 无人可行动，应直接结算给该赢家
    if (inHandPlayers.length <= 1) {
      streetDone = false;
      return;
    }

    // 当前街道下注结束，等待房主推进到下一街道（或河牌后结算）
    streetDone = true;
  }

  /// 房主手动结算本手：把底池平均分给指定赢家（可多选平分）。
  /// 只有河牌下注结束（或全弃牌只剩一人）时可结算。
  bool settleHand(List<int> winnerSeats) {
    if (handOver || gameOver) return false;
    // 河牌后街道结束，或仅剩一人未弃牌时，允许结算
    final onlyOne = inHandPlayers.length <= 1;
    if (!onlyOne && !(streetDone && street == Street.river)) {
      return false;
    }
    final valid = <int>[
      for (final s in winnerSeats)
        if (s >= 0 && s < players.length && !players[s].out && !players[s].folded) s
    ];
    if (valid.isEmpty) return false;

    final total = potTotal;
    final base = total ~/ valid.length;
    var rem = total - base * valid.length;
    final seatWin = <int, int>{};
    final perWin = <int, int>{};
    // 离按钮近者优先拿奇数筹码（与实体桌惯例一致）
    final order = [...valid]..sort(
        (a, b) => _distFromButton(a).compareTo(_distFromButton(b)));
    for (final w in order) {
      var gain = base;
      if (rem > 0) {
        gain++;
        rem--;
      }
      players[w].chips += gain;
      seatWin[w] = (seatWin[w] ?? 0) + gain;
      perWin[w] = gain;
      // 结算后清零该手投入
      players[w].totalContributed = 0;
    }
    // 其余仍在手玩家（理论上结算后不该有）投入也清零
    for (final p in players) {
      p.totalContributed = 0;
    }
    final names = order.map((s) => players[s].name).join('、');
    log.add('${names} 收下底池 \$$total${order.length > 1 ? '（平分）' : ''}');
    lastResult = HandResult(
        totalPot: total, seatWin: seatWin, perWin: perWin);
    _finishHand();
    return true;
  }

  int _distFromButton(int seat) {
    var d = 0;
    var s = button;
    while (s != seat && d <= players.length) {
      s = _nextAlive(s);
      d++;
    }
    return d;
  }

  void _finishHand() {
    handOver = true;
    streetDone = false;
    toAct = -1;
    for (final p in players) {
      if (!p.out && p.chips <= 0) {
        p.out = true;
        log.add('${p.name} 筹码输完，出局');
      }
    }
    if (liveCount <= 1) {
      gameOver = true;
      final champ = players.firstWhere((p) => !p.out, orElse: () => players[0]);
      log.add('🏆 ${champ.name} 赢得整场比赛！');
    }
  }

  // ---------------- 网络序列化 ----------------

  /// 公共快照。所有玩家的筹码/下注/状态均公开（无底牌隐私）。
  Map<String, dynamic> toMap({int? forSeat}) {
    return {
      'players': [
        for (final p in players)
          {
            'seat': p.seat,
            'name': p.name,
            'chips': p.chips,
            'isAI': p.isAI,
            'gender': p.gender,
            'roundBet': p.roundBet,
            'totalContributed': p.totalContributed,
            'folded': p.folded,
            'allIn': p.allIn,
            'out': p.out,
          }
      ],
      'street': street.name,
      'streetDone': streetDone,
      'currentBet': currentBet,
      'lastFullRaise': lastFullRaise,
      'toAct': toAct,
      'button': button,
      'sbSeat': sbSeat,
      'bbSeat': bbSeat,
      'level': level,
      'sb': blinds.sb,
      'bb': blinds.bb,
      'handNumber': handNumber,
      'handOver': handOver,
      'gameOver': gameOver,
      'potTotal': potTotal,
      'log': log.length > 60 ? log.sublist(log.length - 60) : log,
      'result': lastResult == null
          ? null
          : {
              // JSON 要求 Map 的 key 必须是 String，故把 int 座位号转成字符串（fromMap 用 int.parse 还原）
              'totalPot': lastResult!.totalPot,
              'seatWin': {
                for (final e in lastResult!.seatWin.entries) '${e.key}': e.value
              },
              'perWin': {
                for (final e in lastResult!.perWin.entries) '${e.key}': e.value
              },
            },
      'config': config.toMap(),
    };
  }

  static GameState fromMap(Map<String, dynamic> m) {
    final g = GameState(config: GameConfig.fromMap(m['config']));
    g.players = [
      for (final pm in (m['players'] as List))
        (() {
          final p = pm as Map;
          final ps = PlayerState(
            seat: (p['seat'] as num).toInt(),
            name: p['name'] as String,
            isAI: p['isAI'] as bool,
            gender: (p['gender'] as String?) ?? 'male',
            chips: (p['chips'] as num).toInt(),
          );
          ps.roundBet = (p['roundBet'] as num).toInt();
          ps.totalContributed = (p['totalContributed'] as num?)?.toInt() ?? 0;
          ps.folded = p['folded'] as bool;
          ps.allIn = p['allIn'] as bool;
          ps.out = p['out'] as bool;
          return ps;
        })()
    ];
    g.street = Street.values.firstWhere((s) => s.name == m['street']);
    g.streetDone = (m['streetDone'] as bool?) ?? false;
    g.currentBet = (m['currentBet'] as num).toInt();
    g.lastFullRaise = (m['lastFullRaise'] as num?)?.toInt() ?? g.blinds.bb;
    g.toAct = (m['toAct'] as num).toInt();
    g.button = (m['button'] as num).toInt();
    g.sbSeat = (m['sbSeat'] as num?)?.toInt() ?? -1;
    g.bbSeat = (m['bbSeat'] as num?)?.toInt() ?? -1;
    g.level = (m['level'] as num).toInt();
    g.handNumber = (m['handNumber'] as num).toInt();
    g.handOver = m['handOver'] as bool;
    g.gameOver = m['gameOver'] as bool;
    g.log = [for (final l in (m['log'] as List)) l.toString()];
    final r = m['result'];
    if (r != null) {
      g.lastResult = HandResult(
        totalPot: (r['totalPot'] as num).toInt(),
        seatWin: (r['seatWin'] as Map).map(
            (k, v) => MapEntry(int.parse(k.toString()), (v as num).toInt())),
        perWin: (r['perWin'] as Map).map(
            (k, v) => MapEntry(int.parse(k.toString()), (v as num).toInt())),
      );
    }
    return g;
  }
}
