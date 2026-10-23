/// 游戏控制器：绑定 引擎 + AI + 网络 + 盲注计时。
/// 三种模式：local（单机 AI）、host（蓝牙房主）、client（蓝牙客人）。
library;

import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';

import '../engine/ai.dart';
import '../engine/game.dart';
import '../net/session.dart';

enum GameMode { local, host, client }

class GameController extends ChangeNotifier {
  final GameMode mode;
  GameState g; // 客户端模式下随快照重建，故不可 final
  final Random rng;
  final String myName;
  int mySeat = 0;

  HostSession? hostSession;
  ClientSession? clientSession;

  // 主机模式：peerId -> 座位 / 座位 -> peerId
  final Map<String, int> _seatByPeer = {};
  Map<int, String> get peerBySeat =>
      _seatByPeer.map((k, v) => MapEntry(v, k));

  int _aiTicket = 0;
  Timer? _blindTimer;
  int _minutesAtLevel = 0;

  GameController._({
    required this.mode,
    required String name,
    required GameConfig config,
    int? seed,
  })  : myName = name,
        rng = Random(seed),
        g = GameState(config: config, rng: Random(seed));

  /// 单机 AI 模式：1 台手机即可玩
  factory GameController.local(
      {required String myName,
      required int aiCount,
      required GameConfig config,
      int? seed}) {
    final c = GameController._(
        mode: GameMode.local, name: myName, config: config, seed: seed);
    final roster = <PlayerSeed>[PlayerSeed(myName)];
    for (var i = 1; i <= aiCount && roster.length < 10; i++) {
      roster.add(PlayerSeed('AI $i', isAI: true));
    }
    c.g.newGame(roster);
    c.g.startHand();
    c._startBlindTimerIfNeeded();
    c._afterChange(); // 通知 UI 并启动首个 AI 行动（否则会卡在 AI 思考）
    return c;
  }

  /// 蓝牙房主：先广播房间，客人连入后 startNetworkGame 开局
  factory GameController.host(
      {required String myName, required GameConfig config}) {
    final c = GameController._(
        mode: GameMode.host, name: myName, config: config);
    c.hostSession = HostSession(
      roomName: myName,
      onMessage: c._onHostMessage,
      onChanged: c.notifyListeners,
      onPeerDisconnected: c._onPeerDisconnected,
    );
    c.hostSession!.start();
    return c;
  }

  /// 蓝牙客人
  factory GameController.client(
      {required String myName, required ClientSession session}) {
    final c = GameController._(
        mode: GameMode.client, name: myName, config: GameConfig());
    c.clientSession = session;
    return c;
  }

  // ---------- 主机 ----------

  void startNetworkGame({required int aiFill}) {
    final hs = hostSession;
    if (hs == null) return;
    final roster = <PlayerSeed>[PlayerSeed(myName)];
    var seat = 1;
    for (final entry in hs.pendingClients.entries) {
      if (roster.length >= 10) break;
      roster.add(PlayerSeed(entry.value));
      _seatByPeer[entry.key] = seat;
      seat++;
    }
    var ai = 1;
    while (roster.length < 10 && ai <= aiFill) {
      roster.add(PlayerSeed('AI $ai', isAI: true));
      ai++;
    }
    // 通知各客人座位号
    _seatByPeer.forEach((peerId, s) {
      hs.sendTo(peerId, {'t': 'seat', 'seat': s});
    });
    g.newGame(roster);
    g.startHand();
    _startBlindTimerIfNeeded();
    _afterChange();
  }

  void _onPeerDisconnected(String peerId) {
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
        notifyListeners();
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
        notifyListeners();
      case 'snap':
        g = GameState.fromMap((msg['state'] as Map).cast<String, dynamic>());
        notifyListeners();
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
    final ok = g.act(seat, a);
    if (ok) _afterChange();
  }

  void nextHand() {
    if (mode == GameMode.client || !g.handOver || g.gameOver) return;
    g.startHand();
    _afterChange();
  }

  void skipBlindLevel() {
    if (mode == GameMode.client) return;
    if (g.advanceLevel()) {
      _minutesAtLevel = 0;
      _afterChange();
    }
  }

  void _afterChange() {
    notifyListeners();
    if (mode == GameMode.host) _broadcastSnapshots();
    _scheduleAI();
  }

  void _scheduleAI() {
    if (mode == GameMode.client) return;
    _aiTicket++;
    final ticket = _aiTicket;
    if (g.gameOver) return;
    if (g.handOver) {
      // 4 秒后自动开下一手
      Future.delayed(const Duration(seconds: 4), () {
        if (ticket == _aiTicket && g.handOver && !g.gameOver) nextHand();
      });
      return;
    }
    if (g.toAct >= 0 && g.players[g.toAct].isAI) {
      Future.delayed(Duration(milliseconds: 900 + rng.nextInt(800)), () {
        if (ticket != _aiTicket ||
            g.handOver ||
            g.toAct < 0 ||
            !g.players[g.toAct].isAI) {
          return;
        }
        PokerAction a;
        try {
          a = AIPlayer.decide(g, rng);
        } catch (_) {
          // 决策异常时退化为安全动作，避免永久卡在“思考中”
          final legal = g.legalActions(g.toAct);
          a = legal.canCheck
              ? const PokerAction('check')
              : (legal.callAmount > 0 &&
                      legal.callAmount <= g.players[g.toAct].chips
                  ? const PokerAction('call')
                  : const PokerAction('fold'));
        }
        applyAction(g.toAct, a);
      });
    }
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

  @override
  void dispose() {
    _aiTicket++;
    _blindTimer?.cancel();
    try {
      if (mode == GameMode.host) hostSession?.stop();
      if (mode == GameMode.client) clientSession?.stop();
    } catch (_) {}
    super.dispose();
  }
}

/// 便捷：把任意对象编码为 JSON 字符串（调试用）
String encodeMsg(Map<String, dynamic> m) => jsonEncode(m);
