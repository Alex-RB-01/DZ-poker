/// 德州扑克引擎（纯 Dart，无 Flutter 依赖，可独立单测）
///
/// 覆盖：发牌、大小盲、四条街下注、最小加注规则、边池（side pot）、
/// 未被跟注返还、平分池与奇数筹码、锦标赛盲注级别、淘汰与冠军判定。
library;

import 'dart:math';

const String kRanks = '23456789TJQKA';
const List<String> kSuitChars = ['♠', '♥', '♦', '♣'];

enum Street { preflop, flop, turn, river }

class Card {
  final int rank; // 2..14, A=14
  final int suit; // 0..3: ♠♥♦♣
  const Card(this.rank, this.suit);

  factory Card.fromCode(int code) => Card(code ~/ 4, code % 4);
  int get code => rank * 4 + suit;
  bool get isRed => suit == 1 || suit == 2;
  String get text => '${kRanks[rank - 2]}${kSuitChars[suit]}';

  @override
  String toString() => text;
}

class Deck {
  final List<Card> _cards;
  final Random _rng;

  Deck({Random? rng})
      : _rng = rng ?? Random(),
        _cards = [
          for (var r = 2; r <= 14; r++)
            for (var s = 0; s < 4; s++) Card(r, s)
        ];

  void shuffle() => _cards.shuffle(_rng);
  Card deal() => _cards.removeLast();
}

// ---------------- 牌型评估 ----------------

/// 评估 5 张牌，返回可比较的分值列表：[类别, 决胜张...]，类别越大越强。
/// 类别: 8同花顺 7四条 6葫芦 5同花 4顺子 3三条 2两对 1一对 0高牌
List<int> eval5(List<Card> cs) {
  final ranks = cs.map((c) => c.rank).toList()..sort((a, b) => b - a);
  final isFlush = cs.every((c) => c.suit == cs.first.suit);
  final counts = <int, int>{};
  for (final r in ranks) {
    counts[r] = (counts[r] ?? 0) + 1;
  }
  // 组按 (数量降序, 点数降序) 排
  final groups = counts.keys.toList()
    ..sort((a, b) {
      final d = counts[b]! - counts[a]!;
      return d != 0 ? d : b - a;
    });
  int? straightHigh;
  final uniq = counts.keys.toList()..sort((a, b) => b - a);
  if (uniq.length == 5) {
    if (uniq[0] - uniq[4] == 4) {
      straightHigh = uniq[0];
    } else if (uniq[0] == 14 && uniq[1] == 5 && uniq[1] - uniq[4] == 3) {
      straightHigh = 5; // A-2-3-4-5 轮子
    }
  }
  if (isFlush && straightHigh != null) return [8, straightHigh];
  if (counts[groups[0]] == 4) return [7, groups[0], groups[1]];
  if (counts[groups[0]] == 3 && counts[groups[1]] == 2) {
    return [6, groups[0], groups[1]];
  }
  if (isFlush) return [5, ...ranks];
  if (straightHigh != null) return [4, straightHigh];
  if (counts[groups[0]] == 3) {
    return [3, groups[0], groups[1], groups[2]];
  }
  if (counts[groups[0]] == 2 && counts[groups[1]] == 2) {
    return [2, groups[0], groups[1], groups[2]];
  }
  if (counts[groups[0]] == 2) {
    return [1, groups[0], groups[1], groups[2], groups[3]];
  }
  return [0, ...ranks];
}

int cmpEval(List<int> a, List<int> b) {
  for (var i = 0; i < a.length && i < b.length; i++) {
    if (a[i] != b[i]) return a[i] - b[i];
  }
  return a.length - b.length;
}

/// 从 5~7 张中选最强 5 张
List<int> eval7(List<Card> cards) {
  final n = cards.length;
  List<int> best = const [];
  for (var a = 0; a < n - 4; a++) {
    for (var b = a + 1; b < n - 3; b++) {
      for (var c = b + 1; c < n - 2; c++) {
        for (var d = c + 1; d < n - 1; d++) {
          for (var e = d + 1; e < n; e++) {
            final s = eval5([cards[a], cards[b], cards[c], cards[d], cards[e]]);
            if (best.isEmpty || cmpEval(s, best) > 0) best = s;
          }
        }
      }
    }
  }
  return best;
}

String handName(List<int> s) {
  switch (s[0]) {
    case 8:
      return '同花顺';
    case 7:
      return '四条';
    case 6:
      return '葫芦';
    case 5:
      return '同花';
    case 4:
      return '顺子';
    case 3:
      return '三条';
    case 2:
      return '两对';
    case 1:
      return '一对';
    default:
      return '高牌';
  }
}

// ---------------- 玩家 / 配置 ----------------

class PlayerState {
  final int seat;
  String name;
  bool isAI;
  int chips;
  List<Card> hole = const [];
  int roundBet = 0; // 本轮下注
  int totalContributed = 0; // 本手总投入
  bool folded = false;
  bool allIn = false;
  bool out = false; // 锦标赛出局
  bool acted = false; // 本轮是否已行动
  bool hasCards = false;
  bool revealed = false; // 摊牌亮牌

  PlayerState(
      {required this.seat, required this.name, this.isAI = false, this.chips = 0});

  bool get inHand => hasCards && !folded;
}

class PlayerSeed {
  final String name;
  final bool isAI;
  const PlayerSeed(this.name, {this.isAI = false});
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

class Pot {
  final int amount;
  final List<int> seats; // 有资格赢该池的座位
  const Pot(this.amount, this.seats);
}

class HandResult {
  final List<Pot> pots;
  final Map<int, int> seatWin; // seat -> 本手赢得
  final Map<int, List<int>> reveal; // seat -> 底牌 code
  final Map<int, String> handNames;
  const HandResult(
      {required this.pots,
      required this.seatWin,
      required this.reveal,
      required this.handNames});
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

// ---------------- 游戏状态机 ----------------

class GameState {
  final Random rng;
  GameConfig config;
  late List<PlayerState> players;
  int button = 0;
  int level = 0;
  int handsAtLevel = 0;
  List<Card> board = [];
  Deck? _deck;
  Street street = Street.preflop;
  int currentBet = 0;
  int lastFullRaise = 0;
  int toAct = -1;
  int sbSeat = -1;
  int bbSeat = -1;
  int handNumber = 0;
  bool handOver = true;
  bool gameOver = false;
  List<String> log = [];
  HandResult? lastResult;

  GameState({Random? rng, GameConfig? config})
      : rng = rng ?? Random(),
        config = config ?? GameConfig();

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
  List<PlayerState> get inHandPlayers =>
      players.where((p) => p.inHand).toList();

  String _bl() => '${blinds.sb}/${blinds.bb}';

  /// 开新比赛（一场锦标赛）
  void newGame(List<PlayerSeed> seeds) {
    players = [
      for (var i = 0; i < seeds.length; i++)
        PlayerState(
            seat: i,
            name: seeds[i].name,
            isAI: seeds[i].isAI,
            chips: config.startingChips)
    ];
    button = players.length - 1; // 第一手会轮到 0
    level = 0;
    handsAtLevel = 0;
    handNumber = 0;
    handOver = true;
    gameOver = false;
    lastResult = null;
    board = [];
    log = ['游戏开始：${players.length} 人，初始筹码 ${config.startingChips}'];
  }

  /// 下一手牌。盲注按局数递增在这里自动处理。
  void startHand() {
    if (gameOver) return;
    if (liveCount <= 1) {
      gameOver = true;
      return;
    }
    for (final p in players) {
      p.hole = const [];
      p.roundBet = 0;
      p.totalContributed = 0;
      p.folded = false;
      p.allIn = false;
      p.acted = false;
      p.hasCards = false;
      p.revealed = false;
    }
    lastResult = null;
    board = [];
    street = Street.preflop;
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

    _deck = Deck(rng: rng)..shuffle();
    var seat = sbSeat;
    for (var round = 0; round < 2; round++) {
      seat = sbSeat;
      for (var i = 0; i < liveCount; i++) {
        final p = players[seat];
        p.hole = [...p.hole, _deck!.deal()];
        p.hasCards = true;
        seat = _nextAlive(seat);
      }
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
    if (handOver || !p.hasCards || p.folded) return;
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
      p.hasCards && !p.folded && !p.allIn && (!p.acted || p.roundBet < currentBet);

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
    if (handOver || toAct != seat) return false;
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
    final bets = players
        .where((p) => p.hasCards)
        .map((p) => p.roundBet)
        .toList()
      ..sort((a, b) => b - a);
    if (bets.length > 1 && bets[0] > bets[1]) {
      final top =
          players.firstWhere((p) => p.hasCards && p.roundBet == bets[0]);
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

    final live = inHandPlayers;
    if (live.length <= 1) {
      _awardUncontested(live.first);
      return;
    }
    if (street == Street.river) {
      resolveShowdown();
      return;
    }
    _dealStreet();
    toAct = _nextActor(button);
    if (toAct < 0) _endBettingRound(); // 全员全下，自动发完剩余公共牌
  }

  void _dealStreet() {
    switch (street) {
      case Street.preflop:
        _deck!.deal(); // 烧牌
        board.addAll([_deck!.deal(), _deck!.deal(), _deck!.deal()]);
        street = Street.flop;
        log.add('翻牌 ${board.map((c) => c.text).join(" ")}');
      case Street.flop:
        _deck!.deal();
        board.add(_deck!.deal());
        street = Street.turn;
        log.add('转牌 ${board.last.text}');
      case Street.turn:
        _deck!.deal();
        board.add(_deck!.deal());
        street = Street.river;
        log.add('河牌 ${board.last.text}');
      case Street.river:
        break;
    }
  }

  void _awardUncontested(PlayerState winner) {
    var total = 0;
    for (final p in players) {
      total += p.totalContributed;
    }
    winner.chips += total;
    log.add('${winner.name} 收下底池 \$$total');
    lastResult = HandResult(
        pots: [Pot(total, [winner.seat])],
        seatWin: {winner.seat: total},
        reveal: {},
        handNames: {});
    _finishHand();
  }

  /// 按投入层级构建主池/边池
  List<Pot> buildPots() {
    final levels =
        players.map((p) => p.totalContributed).where((c) => c > 0).toSet().toList()
          ..sort();
    final pots = <Pot>[];
    var prev = 0;
    for (final lv in levels) {
      var amt = 0;
      for (final p in players) {
        amt += (p.totalContributed < lv ? p.totalContributed : lv) -
            (p.totalContributed < prev ? p.totalContributed : prev);
      }
      final seats = [
        for (final p in inHandPlayers)
          if (p.totalContributed >= lv) p.seat
      ];
      if (amt > 0) pots.add(Pot(amt, seats));
      prev = lv;
    }
    return pots;
  }

  /// 摊牌结算（公开，供测试与流程复用）
  void resolveShowdown() {
    final pots = buildPots();
    final seatWin = <int, int>{};
    final reveal = <int, List<int>>{};
    final handNames = <int, String>{};
    for (final p in inHandPlayers) {
      reveal[p.seat] = [for (final c in p.hole) c.code];
      p.revealed = true;
      handNames[p.seat] = handName(eval7([...p.hole, ...board]));
    }
    for (final pot in pots) {
      List<int> bestScore = const [];
      var winners = <PlayerState>[];
      for (final seat in pot.seats) {
        final p = players[seat];
        final score = eval7([...p.hole, ...board]);
        if (winners.isEmpty) {
          winners = [p];
          bestScore = score;
        } else {
          final c = cmpEval(score, bestScore);
          if (c > 0) {
            winners = [p];
            bestScore = score;
          } else if (c == 0) {
            winners.add(p);
          }
        }
      }
      if (winners.isEmpty) continue;
      final base = pot.amount ~/ winners.length;
      var rem = pot.amount - base * winners.length;
      final order = [...winners]..sort((a, b) =>
          _distFromButton(a.seat).compareTo(_distFromButton(b.seat)));
      for (final w in order) {
        var gain = base;
        if (rem > 0) {
          gain++;
          rem--;
        }
        w.chips += gain;
        seatWin[w.seat] = (seatWin[w.seat] ?? 0) + gain;
      }
      log.add(
          '底池 \$$pot.amount → ${winners.map((w) => w.name).join("、")}${winners.length > 1 ? '（平分）' : ''}');
    }
    lastResult = HandResult(
        pots: pots, seatWin: seatWin, reveal: reveal, handNames: handNames);
    _finishHand();
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
    toAct = -1;
    for (final p in players) {
      if (!p.out && p.chips <= 0) {
        p.out = true;
        log.add('${p.name} 筹码输完，出局');
      }
    }
    if (liveCount <= 1) {
      gameOver = true;
      final champ = players.firstWhere((p) => !p.out,
          orElse: () => players[0]);
      log.add('🏆 ${champ.name} 赢得整场比赛！');
    }
  }

  // ---------------- 网络序列化 ----------------

  /// 公共快照。forSeat 指定接收者座位，其底牌包含在内；其他人的底牌只有摊牌亮出才包含。
  Map<String, dynamic> toMap({int? forSeat}) {
    return {
      'players': [
        for (final p in players)
          {
            'seat': p.seat,
            'name': p.name,
            'chips': p.chips,
            'isAI': p.isAI,
            'roundBet': p.roundBet,
            'totalContributed': p.totalContributed,
            'folded': p.folded,
            'allIn': p.allIn,
            'out': p.out,
            'hasCards': p.hasCards,
            'revealed': p.revealed,
            'hole': p.hasCards && (p.revealed || p.seat == forSeat)
                ? [for (final c in p.hole) c.code]
                : null,
          }
      ],
      'board': [for (final c in board) c.code],
      'street': street.name,
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
              'seatWin': {
                for (final e in lastResult!.seatWin.entries) '${e.key}': e.value
              },
              'reveal': {
                for (final e in lastResult!.reveal.entries) '${e.key}': e.value
              },
              'handNames': {
                for (final e in lastResult!.handNames.entries) '${e.key}': e.value
              },
              'pots': [
                for (final pot in lastResult!.pots)
                  {'amount': pot.amount, 'seats': pot.seats}
              ],
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
            chips: (p['chips'] as num).toInt(),
          );
          ps.roundBet = (p['roundBet'] as num).toInt();
          ps.totalContributed =
              (p['totalContributed'] as num?)?.toInt() ?? 0;
          ps.folded = p['folded'] as bool;
          ps.allIn = p['allIn'] as bool;
          ps.out = p['out'] as bool;
          ps.hasCards = p['hasCards'] as bool;
          ps.revealed = p['revealed'] as bool;
          final hole = p['hole'];
          if (hole != null) {
            ps.hole = [for (final c in (hole as List)) Card.fromCode((c as num).toInt())];
          }
          return ps;
        })()
    ];
    g.board = [
      for (final c in (m['board'] as List)) Card.fromCode((c as num).toInt())
    ];
    g.street =
        Street.values.firstWhere((s) => s.name == m['street']);
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
        pots: [
          for (final pm in (r['pots'] as List))
            Pot((pm['amount'] as num).toInt(),
                [for (final s in (pm['seats'] as List)) (s as num).toInt()])
        ],
        seatWin: (r['seatWin'] as Map).map((k, v) =>
            MapEntry(int.parse(k.toString()), (v as num).toInt())),
        reveal: (r['reveal'] as Map).map((k, v) => MapEntry(
            int.parse(k.toString()),
            [for (final c in (v as List)) (c as num).toInt()])),
        handNames: (r['handNames'] as Map)
            .map((k, v) => MapEntry(int.parse(k.toString()), v.toString())),
      );
    }
    return g;
  }
}
