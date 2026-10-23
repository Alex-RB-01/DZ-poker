/// 同 WiFi 房间会话层：主机 / 客户端。
///
/// 协议（JSON 字符串，每行一条）：
///   客户端 → 主机：{t:'hello', name}、{t:'action', type, amount}
///   主机 → 客户端：{t:'seat', seat}、{t:'snap', state:{...GameState.toMap}}
library;

import 'dart:async';
import 'dart:convert';

import 'transport.dart';

class HostSession {
  final LanTransport transport;
  final void Function(String peerId, Map<String, dynamic> msg) onMessage;
  final void Function() onChanged;
  final void Function(String peerId)? onPeerDisconnected;

  /// peerId -> 玩家昵称（已连入、收到 hello 后入座等待）
  final Map<String, String> pendingClients = {};

  HostSession(
      {required this.onMessage,
      required this.onChanged,
      required String roomName,
      this.onPeerDisconnected})
      : transport = LanTransport(isHost: true, deviceName: roomName) {
    transport.peers.listen((p) {
      if (!p.connected) {
        pendingClients.remove(p.id);
        onPeerDisconnected?.call(p.id);
      }
      onChanged();
    });
    transport.messages.listen((m) {
      try {
        final map = jsonDecode(m.data) as Map<String, dynamic>;
        onMessage(m.fromId, map);
      } catch (_) {}
    });
  }

  Future<void> start() => transport.init();

  void sendTo(String peerId, Map<String, dynamic> obj) =>
      transport.send(peerId, jsonEncode(obj));

  void broadcast(Map<String, dynamic> obj) =>
      transport.broadcast(jsonEncode(obj));

  Future<void> stop() => transport.stop();
}

class ClientSession {
  final LanTransport transport;
  final void Function(Map<String, dynamic> msg) onMessage;
  final void Function() onChanged;

  /// 发现到的房间：id("$addr:$port") -> 信标
  final Map<String, HostBeacon> hosts = {};
  String? hostPeerId;
  String? _myName;
  bool _helloSent = false;

  ClientSession(
      {required String myName,
      required this.onMessage,
      required this.onChanged})
      : transport = LanTransport(isHost: false, deviceName: myName) {
    transport.beacons.listen((b) {
      hosts[b.id] = b;
      onChanged();
    });
    transport.peers.listen((p) {
      if (p.connected) {
        hostPeerId ??= p.id;
        if (!_helloSent && _myName != null) {
          _helloSent = true;
          transport.send(p.id, jsonEncode({'t': 'hello', 'name': _myName}));
        }
      } else {
        if (hostPeerId == p.id) hostPeerId = null;
      }
      onChanged();
    });
    transport.messages.listen((m) {
      try {
        final map = jsonDecode(m.data) as Map<String, dynamic>;
        if (map['t'] == 'seat' || map['t'] == 'snap') {
          hostPeerId ??= m.fromId;
        }
        onMessage(map);
      } catch (_) {}
    });
  }

  Future<void> start() => transport.init();

  /// 加入某房间：建立 TCP 连接（连接成功后由 peers 监听自动发送 hello）
  Future<void> join(String addr, int port, String myName) async {
    _myName = myName;
    await transport.connectToHost(addr, port);
  }

  Future<void> sendAction(String type, int amount) async {
    final hp = hostPeerId;
    if (hp == null) return;
    transport.send(
        hp, jsonEncode({'t': 'action', 'type': type, 'amount': amount}));
  }

  /// 请求房主开下一手（一手结束后手动继续）
  Future<void> sendNext() async {
    final hp = hostPeerId;
    if (hp == null) return;
    transport.send(hp, jsonEncode({'t': 'next'}));
  }

  Future<void> stop() => transport.stop();
}
