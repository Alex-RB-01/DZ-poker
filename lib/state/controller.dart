/// 游戏控制器：绑定 引擎 + 网络 + 盲注计时。
/// 三种模式：local（单机记分）、host（局域网房主）、client（局域网客人）。
library;

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../engine/game.dart';
import '../net/session.dart';

enum GameMode { local, host, client }

class GameController extends ChangeNotifier {
  final GameMode mode;
  GameState g; // 客户端模式下随快照重建，故不可 final
  final String myName;
  String myGender = 'male'; // 本机玩家性别：'male' 男声 / 'female' 女声

  /// 动作发生回调：座位号 + 动作类型 + 是否全下。房主/单机用它在 UI 侧播音。
  void Function(int seat, String type, bool allIn)? onAction;

  int mySeat = 0;

  HostSession? hostSession;
  ClientSession? clientSession;

  /// 头像（base64 jpeg）：座位号 -> 头像；本机头像
  final Map<int, String> avatarsBySeat = {};
  String? myAvatarB64;

  /// 主机模式：等待中客人的头像 peerId -> base64
  final Map<String, String> _pendingAvatars = {};
  Map<String, String> get pendingAvatars => _pendingAvatars;

  // 主机模式：peerId -> 座位 / 座位 -> peerId
  final Map<String, int> _seatByPeer = {};
  Map<int, String> get peerBySeat =>
      _seatByPeer.map((k, v) => MapEntry(v, k));

  Timer? _blindTimer;
  int _minutesAtLevel = 0;

  GameController._({
    required this.mode,
    required String name,
    required GameConfig config,
  })  : myName = name,
        g = GameState(config: config);

  /// 单机记分模式：1 台手机当裁判/房主，本机为座位 0，
  /// 其余 [playerCount]-1 个座位为「本地真人」座位（非 AI，各自在实体桌下注、由本机代点）。
  factory GameController.local(
      {required String myName,
      required int playerCount,
      required GameConfig config,
      String myGender = 'male',
      int? seed}) {
    final c = GameController._(
        mode: GameMode.local, name: myName, config: config);
    c.myGender = myGender;
    final roster = <PlayerSeed>[PlayerSeed(myName, gender: myGender)];
    for (var i = 1; i < playerCount && roster.length < 10; i++) {
      roster.add(PlayerSeed('玩家 ${i + 1}', isAI: false, gender: 'male'));
    }
    c.g.newGame(roster);
    c.g.startHand();
    c._startBlindTimerIfNeeded();
    c._afterChange();
    return c;
  }

  /// 蓝牙房主：先广播房间，客人连入后 startNetworkGame 开局
  factory GameController.host(
      {required String myName,
      required GameConfig config,
      String myGender = 'male'}) {
    final c = GameController._(
        mode: GameMode.host, name: myName, config: config);
    c.myGender = myGender;
    c.hostSession = HostSession(
      roomName: myName,
      onMessage: c._onHostMessage,
      onChanged: c._safeNotify,
      onPeerDisconnected: c._onPeerDisconnected,
    );
    // 注意：会话初始化（建 socket）改为由调用方 await initHost()，
    // 避免 fire-and-forget 的未捕获异步异常导致 release 灰屏。
    return c;
  }

  /// 真正启动房主网络会话（建 UDP/TCP）。网络受限时捕获异常，不阻断 UI。
  Future<void> initHost() async {
    try {
      await hostSession?.start();
    } catch (_) {
      // 网络初始化失败（如权限/端口）：仍允许「纯 AI 开局」，仅无法联机
    }
  }

  /// 后台启动房主网络会话：不 await、不抛未捕获异常。
  /// 点「创建房间」后立刻进入等候房，联网在后台进行；即便失败也照常可 AI 开局。
  void startHostInBackground() {
    final hs = hostSession;
    if (hs == null) return;
    // fire-and-forget，但内部已 try/catch，绝不向 UI 抛出未捕获异步错误
    unawaited(hs.start().catchError((_) {}));
  }

  /// 蓝牙客人
  factory GameController.client(
      {required String myName,
      required ClientSession session,
      String myGender = 'male'}) {
    final c = GameController._(
        mode: GameMode.client, name: myName, config: GameConfig());
    c.myGender = myGender;
    c.clientSession = session;
    return c;
  }

  // ---------- 主机 ----------

  void startNetworkGame({int aiFill = 0}) {
    final hs = hostSession;
    if (hs == null) return;
    final roster = <PlayerSeed>[PlayerSeed(myName, gender: myGender)];
    avatarsBySeat[0] = myAvatarB64 ?? '';
    var seat = 1;
    for (final entry in hs.pendingClients.entries) {
      if (roster.length >= 10) break;
      roster.add(PlayerSeed(entry.value,
          gender: hs.pendingGenders[entry.key] ?? 'male'));
      _seatByPeer[entry.key] = seat;
      avatarsBySeat[seat] = _pendingAvatars[entry.key] ?? '';
      seat++;
    }
    // 电子筹码模式：无 AI 补位，仅已连入的真人玩家
    // 通知各客人座位号 + 全桌头像表
    _seatByPeer.forEach((peerId, s) {
      hs.sendTo(peerId, {'t': 'seat', 'seat': s});
      hs.sendTo(peerId, {
        't': 'avatars',
        'bySeat': {
          for (final e in avatarsBySeat.entries) if (e.value.isNotEmpty) '${e.key}': e.value,
        },
      });
    });
    g.newGame(roster);
    g.startHand();
    _startBlindTimerIfNeeded();
    _afterChange();
  }

  void _onPeerDisconnected(String peerId) {
    _pendingAvatars.remove(peerId);
    final seat = _seatByPeer.remove(peerId);
    if (seat != null && !g.gameOver && !g.handOver) {
      g.forceFold(seat);
      _afterChange();
    }
  }

  void _onHostMessage(String peerId, Map<String, dynamic> msg) {
    switch (msg['t']) {
      case 'hello':
        hostSession?.pendingClients[peerId] =
            (msg['name'] ?? '玩家').toString();
        hostSession?.setPendingGender(
            peerId, (msg['gender'] ?? 'male').toString());
        final av = msg['avatar'];
        if (av is String && av.isNotEmpty) {
          _pendingAvatars[peerId] = av;
        } else {
          _pendingAvatars.remove(peerId);
        }
        _safeNotify();
      case 'next':
        nextHand();
      case 'restart':
        restartMatch();
      case 'advance':
        advanceStreet();
      case 'settle':
        settleHand([for (final s in (msg['winners'] as List? ?? [])) (s as num).toInt()]);
      case 'action':
        final seat = _seatByPeer[peerId];
        if (seat != null) {
          applyAction(
              seat,
              PokerAction((msg['type'] ?? '').toString(),
                  amount: ((msg['amount'] ?? 0) as num).toInt()));
        }
    }
  }

  void _broadcastSnapshots() {
    final hs = hostSession;
    if (hs == null) return;
    _seatByPeer.forEach((peerId, seat) {
      hs.sendTo(peerId, {
        't': 'snap',
        'state': g.toMap(forSeat: seat),
      });
    });
  }

  // ---------- 客人 ----------

  void onClientMessage(Map<String, dynamic> msg) {
    switch (msg['t']) {
      case 'seat':
        mySeat = (msg['seat'] as num).toInt();
        _safeNotify();
      case 'avatars':
        final bySeat = (msg['bySeat'] as Map? ?? {});
        avatarsBySeat
          ..clear()
          ..addAll({
            for (final e in bySeat.entries)
              int.parse(e.key.toString()): e.value.toString(),
          });
        _safeNotify();
      case 'snap':
        g = GameState.fromMap((msg['state'] as Map).cast<String, dynamic>());
        _safeNotify();
    }
  }

  void sendMyAction(PokerAction a) {
    if (mode == GameMode.client) {
      clientSession?.sendAction(a.type, a.amount);
    } else {
      applyAction(mySeat, a);
    }
  }

  // ---------- 通用 ----------

  bool get isMyTurn => !g.handOver && g.toAct == mySeat;

  void applyAction(int seat, PokerAction a) {
    if (mode == GameMode.client) return;
    final chipsBefore = g.players[seat].chips;
    final ok = g.act(seat, a);
    if (ok) {
      // 通知 UI 播放该座位的真人声动作语音（含是否全下）
      final allIn = g.players[seat].chips == 0;
      // 修正动作语义：call 但未付出任何筹码 => 实为「过牌(check)」
      var type = a.type;
      if (type == 'call' &&
          g.players[seat].chips == chipsBefore &&
          !allIn) {
        type = 'check';
      }
      try {
        onAction?.call(seat, type, allIn);
      } catch (_) {}
      _afterChange();
    }
  }

  void nextHand() {
    if (mode == GameMode.client || !g.handOver || g.gameOver) return;
    g.startHand();
    _afterChange();
  }

  /// 锦标赛结束后重开一场新比赛（房主/单机）。
  /// 复用当前已入座的玩家（顺序、姓名、性别、是否 AI 不变），重新 newGame。
  void restartMatch() {
    if (mode == GameMode.client || !g.gameOver) return;
    final roster = <PlayerSeed>[
      for (final p in g.players)
        PlayerSeed(p.name, isAI: p.isAI, gender: p.gender)
    ];
    if (roster.isEmpty) return;
    g.newGame(roster);
    g.startHand();
    _startBlindTimerIfNeeded();
    _afterChange(); // 广播快照，客户端自动同步新比赛
  }

  /// 请求重开一场新比赛：房主/单机直接开；客人发消息请房主开。
  void requestRestart() {
    if (mode == GameMode.client) {
      clientSession?.sendRestart();
    } else {
      restartMatch();
    }
  }

  /// 请求开下一手：房主/单机直接开；客人发消息请房主开
  void requestNextHand() {
    if (mode == GameMode.client) {
      clientSession?.sendNext();
    } else {
      nextHand();
    }
  }

  /// 房主推进到下一街道（翻牌/转牌/河牌）。客人发消息请房主推进。
  void advanceStreet() {
    if (mode == GameMode.client) return;
    if (g.advanceStreet()) {
      _afterChange();
    }
  }

  /// 房主结算本手，把底池分给指定赢家（可多选平分）。客人发消息请房主结算。
  void settleHand(List<int> winners) {
    if (mode == GameMode.client) return;
    if (g.settleHand(winners)) {
      _afterChange();
    }
  }

  /// 请求推进街道：房主/单机直接推进；客人发消息请房主推进。
  void requestAdvanceStreet() {
    if (mode == GameMode.client) {
      clientSession?.sendAdvanceStreet();
    } else {
      advanceStreet();
    }
  }

  /// 请求结算：房主/单机直接结算；客人发消息请房主结算。
  void requestSettle(List<int> winners) {
    if (mode == GameMode.client) {
      clientSession?.sendSettle(winners);
    } else {
      settleHand(winners);
    }
  }

  void skipBlindLevel() {
    if (mode == GameMode.client) return;
    if (g.advanceLevel()) {
      _minutesAtLevel = 0;
      _afterChange();
    }
  }

  void _afterChange() {
    _safeNotify();
    if (mode == GameMode.host) _broadcastSnapshots();
  }

  void _startBlindTimerIfNeeded() {
    if (g.config.advanceMode != 'minutes') return;
    _blindTimer?.cancel();
    _minutesAtLevel = 0;
    _blindTimer = Timer.periodic(const Duration(minutes: 1), (_) {
      if (g.gameOver || g.handOver) return;
      _minutesAtLevel++;
      if (_minutesAtLevel >= g.config.advanceEvery) {
        _minutesAtLevel = 0;
        if (g.advanceLevel()) _afterChange();
      }
    });
  }

  bool _disposed = false;

  @override
  void dispose() {
    _disposed = true;
    _blindTimer?.cancel();
    try {
      if (mode == GameMode.host) hostSession?.stop();
      if (mode == GameMode.client) clientSession?.stop();
    } catch (_) {}
    super.dispose();
  }

  /// 安全的 notify：控制器已 dispose 后（如 session 异步回调延迟触发）不再通知，避免抛 assert
  void _safeNotify() {
    if (!_disposed) notifyListeners();
  }
}

/// 便捷：把任意对象编码为 JSON 字符串（调试用）
String encodeMsg(Map<String, dynamic> m) => jsonEncode(m);
