/// 联机全链路集成测试：在本机回环 TCP 上跑真实的 Host/Client 会话，
/// 验证：入座(seat) → 快照(sync) → 客人下注(action) → 房主执行 → 快照回传 → 头像分发。
library;

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:poker_app/engine/game.dart';
import 'package:poker_app/net/session.dart';
import 'package:poker_app/net/transport.dart';
import 'package:poker_app/state/controller.dart';

Future<void> waitFor(bool Function() cond,
    {Duration timeout = const Duration(seconds: 8), String what = 'condition'}) async {
  final end = DateTime.now().add(timeout);
  while (!cond()) {
    if (DateTime.now().isAfter(end)) fail('timeout waiting for: $what');
    await Future.delayed(const Duration(milliseconds: 20));
  }
}

/// 保守动作：能过则过，小额跟注，否则弃牌（保证多手牌顺利进行）
PokerAction _safeAction(GameState g, int seat) {
  final legal = g.legalActions(seat);
  if (legal.canCheck) return const PokerAction('check');
  final chips = g.players[seat].chips;
  if (legal.callAmount > 0 && legal.callAmount <= chips ~/ 3) {
    return PokerAction('call');
  }
  if (legal.callAmount == 0) return const PokerAction('call');
  return const PokerAction('fold');
}

void main() {
  test('LAN host+client: seat/snapshot/action/avatar 全链路', () async {
    // ---- 房主 ----
    final host = GameController.host(myName: 'Host', config: GameConfig());
    addTearDown(host.dispose);

    // ---- 客人（模拟 JoinScreen 的消息接线）----
    GameController? cctrl;
    final client = ClientSession(
      myName: 'P2',
      onMessage: (msg) {
        final c = cctrl;
        if (c != null) {
          c.onClientMessage(msg);
        }
      },
      onChanged: () {},
    );
    addTearDown(client.stop);
    await client.start();

    // 等 TCP 服务端就绪后连接（携带头像）
    await Future.delayed(const Duration(milliseconds: 500));
    await client.join('127.0.0.1', LanTransport.tcpPort, 'P2',
        avatarB64: 'aGVsbG8='); // base64('hello')

    await waitFor(() => host.pendingAvatars.isNotEmpty,
        what: 'host received hello');
    // hello 中携带的头像应被房主记录
    expect(host.pendingAvatars.isNotEmpty, isTrue,
        reason: '房主应收到并记录客人头像');

    cctrl = GameController.client(myName: 'P2', session: client);
    cctrl.myAvatarB64 = 'aGVsbG8=';

    // ---- 开局 ----
    host.startNetworkGame(aiFill: 0);
    await waitFor(() => cctrl!.g.handNumber > 0, what: 'client got snapshot');
    await waitFor(() => cctrl!.mySeat >= 0, what: 'client seat assigned');
    expect(cctrl!.mySeat, 1);

    // 头像分发：客人应收到全桌头像表（含自己的）
    await waitFor(() => cctrl!.avatarsBySeat.containsKey(1),
        what: 'avatars broadcast');
    expect(cctrl.avatarsBySeat[1], 'aGVsbG8=');

    // ---- 打 3 手牌：双方均为真人，各自通过自身控制器下注 ----
    var clientActedLog = false;
    for (var hand = 0; hand < 3 && !host.g.gameOver; hand++) {
      var guard = 0;
      while (!host.g.handOver && !host.g.gameOver && guard++ < 300) {
        if (host.g.toAct == 0) {
          host.sendMyAction(_safeAction(host.g, 0));
          await Future.delayed(const Duration(milliseconds: 10));
        } else if (host.g.toAct == 1) {
          await waitFor(() => cctrl!.isMyTurn,
              what: 'client turn (hand ${host.g.handNumber})');
          cctrl!.sendMyAction(_safeAction(cctrl.g, 1));
          await Future.delayed(const Duration(milliseconds: 10));
        } else {
          await Future.delayed(const Duration(milliseconds: 20));
        }
      }
      if (host.g.gameOver) break;
      host.nextHand();
      await waitFor(() => cctrl!.g.handNumber == host.g.handNumber,
          what: 'client snapshot for hand ${host.g.handNumber}');
    }

    // 快照同步一致
    expect(cctrl!.g.handNumber, host.g.handNumber);
    expect(cctrl.g.players.length, host.g.players.length);

    // 客人的动作确实被房主执行（日志中出现 P2 的下注/弃牌记录）
    clientActedLog = cctrl.g.log
        .any((l) => l.contains('P2') && (l.contains('跟注') || l.contains('过牌') || l.contains('加注') || l.contains('弃牌')));
    expect(clientActedLog, isTrue,
        reason: '客人发出的下注应到达房主并被执行，log=${cctrl.g.log}');
  }, timeout: const Timeout(Duration(seconds: 60)));
}
