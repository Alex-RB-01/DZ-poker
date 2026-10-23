/// 蓝牙房间会话层：主机 / 客户端。
///
/// 协议（JSON 字符串）：
///   客户端 → 主机：{t:'hello', name}、{t:'action', type, amount}
///   主机 → 客户端：{t:'seat', seat}、{t:'snap', state:{...GameState.toMap}}
library;

import 'dart:async';
import 'dart:convert';

import 'transport.dart';

class HostSession {
  final NearbyTransport transport;
  final void Function(String peerId, Map<String, dynamic> msg) onMessage;
  final void Function() onChanged;
  final void Function(String peerId)? onPeerDisconnected;

  /// peerId -> 玩家昵称（已连入、等待开局/已入座）
  final Map<String, String> pendingClients = {};

  HostSession(
      {required this.onMessage,
      required this.onChanged,
      required String roomName,
      this.onPeerDisconnected})
      : transport = NearbyTransport(isHost: true, deviceName: roomName);

  Future<void> start() async {
    await transport.init();
    transport.messages.listen((m) {
      try {
        final map = jsonDecode(m.data) as Map<String, dynamic>;
        onMessage(m.fromId, map);
      } catch (_) {}
    });
    transport.peers.listen((p) {
      if (!p.connected) {
        pendingClients.remove(p.id);
        onPeerDisconnected?.call(p.id);
      }
      onChanged();
    });
  }

  void sendTo(String peerId, Map<String, dynamic> obj) =>
      transport.send(peerId, jsonEncode(obj));

  void broadcast(Map<String, dynamic> obj) =>
      transport.broadcast(transport.connectedIds, jsonEncode(obj));

  Future<void> stop() => transport.stop();
}

class ClientSession {
  final NearbyTransport transport;
  final void Function(Map<String, dynamic> msg) onMessage;
  final void Function() onChanged;

  /// 已发现并连接上的主机（deviceId -> 房间名）
  final Map<String, String> hosts = {};
  String? hostPeerId;
  String? _pendingHost;
  String? _myName;
  bool _helloSent = false;

  ClientSession(
      {required String myName,
      required this.onMessage,
      required this.onChanged})
      : transport = NearbyTransport(isHost: false, deviceName: myName);

  Future<void> start() async {
    await transport.init();
    transport.messages.listen((m) {
      try {
        final map = jsonDecode(m.data) as Map<String, dynamic>;
        if (map['t'] == 'seat' || map['t'] == 'snap') {
          hostPeerId ??= m.fromId;
        }
        onMessage(map);
      } catch (_) {}
    });
    transport.peers.listen((p) {
      if (p.connected) {
        hosts[p.id] = p.name.isEmpty ? '房间 ${p.id.substring(0, 4)}' : p.name;
        // 连接建立后，向房主发送加入请求（昵称）
        if (p.id == _pendingHost && !_helloSent && _myName != null) {
          _helloSent = true;
          transport.send(p.id, jsonEncode({'t': 'hello', 'name': _myName}));
        }
      } else {
        hosts.remove(p.id);
      }
      onChanged();
    });
  }

  /// 加入某房间：记录目标并主动邀请建立连接，连接成功后由 peers 监听自动发送 hello
  Future<void> join(String peerId, String myName) async {
    _pendingHost = peerId;
    _myName = myName;
    await transport.invite(peerId);
  }

  Future<void> sendAction(String type, int amount) async {
    final hp = hostPeerId;
    if (hp == null) return;
    await transport
        .send(hp, jsonEncode({'t': 'action', 'type': type, 'amount': amount}));
  }

  Future<void> stop() => transport.stop();
}
