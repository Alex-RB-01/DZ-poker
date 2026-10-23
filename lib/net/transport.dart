/// 邻近网络传输封装。
///
/// 底层使用 flutter_nearby_connections 插件：
///   - Android：Google Nearby Connections（蓝牙 + WiFi Direct / 热点，无需互联网）
///   - iOS：MultipeerConnectivity
///
/// 这是整个工程里唯一与该插件 API 接触的地方。若插件版本升级导致 API 变化，
/// 只需调整本文件即可，业务层（session / controller）不受影响。
///
/// 关键概念（来自插件官方用法）：
///   - 设备以 deviceName 互相可见（房主把房间名设为自己的 deviceName）
///   - 连接需“浏览器”端主动 invitePeer，连接建立后双方才能收发消息
///   - 消息通过 dataReceivedSubscription 回调接收；状态变化通过
///     stateChangedSubscription 回调接收（List<Device>）
library;

import 'dart:async';
import 'dart:convert';

import 'package:flutter_nearby_connections/flutter_nearby_connections.dart';

/// 单个对端设备的状态变化事件
class PeerEvent {
  final String id; // 插件的 deviceId
  final String name; // 对方 deviceName（房主=房间名）
  final bool connected;
  PeerEvent(this.id, this.name, this.connected);
}

/// 一条收到的消息（已剥离出发送方）
class IncomingMessage {
  final String fromId; // 发送方 deviceId
  final String data; // 原始字符串（本工程统一用 JSON）
  IncomingMessage(this.fromId, this.data);
}

class NearbyTransport {
  final NearbyService _service = NearbyService();
  final StreamController<IncomingMessage> _messages =
      StreamController<IncomingMessage>.broadcast();
  final StreamController<PeerEvent> _peers =
      StreamController<PeerEvent>.broadcast();
  final Set<String> connectedIds = {};

  final bool isHost;
  final String deviceName;

  NearbyTransport({required this.isHost, required this.deviceName});

  Stream<IncomingMessage> get messages => _messages.stream;
  Stream<PeerEvent> get peers => _peers.stream;

  /// 初始化并开始发现 / 广播。必须在调用任何 send/invite 之前 await。
  Future<void> init() async {
    await _service.init(
      serviceType: 'wbbholdem',
      deviceName: deviceName,
      strategy: Strategy.P2P_STAR,
      callback: (bool isRunning) async {
        if (!isRunning) return;
        if (isHost) {
          await _service.stopBrowsingForPeers();
          await Future.delayed(const Duration(milliseconds: 200));
          await _service.startAdvertisingPeer();
          await _service.startBrowsingForPeers();
        } else {
          await _service.stopBrowsingForPeers();
          await Future.delayed(const Duration(milliseconds: 200));
          await _service.startBrowsingForPeers();
        }
      },
    );
    _listen();
  }

  void _listen() {
    // 接收消息
    _service.dataReceivedSubscription(callback: (data) {
      try {
        final map = _asMap(data);
        if (map == null) return;
        final from = _str(map['deviceId'] ?? map['device_id'] ?? map['id']) ?? '';
        final raw = map['message'] ?? map['msg'];
        final s = raw is String ? raw : (raw == null ? '' : jsonEncode(raw));
        if (from.isNotEmpty && s.isNotEmpty) {
          _messages.add(IncomingMessage(from, s));
        }
      } catch (_) {}
    });
    // 连接状态变化
    _service.stateChangedSubscription(callback: (List<Device> devices) {
      for (final d in devices) {
        final connected = d.state == SessionState.connected;
        if (connected) {
          connectedIds.add(d.deviceId);
        } else {
          connectedIds.remove(d.deviceId);
        }
        _peers.add(PeerEvent(d.deviceId, d.deviceName, connected));
      }
    });
  }

  /// 浏览器端主动邀请某设备建立连接（房主无需调用）
  Future<void> invite(String deviceId) async {
    try {
      await _service.invitePeer(deviceID: deviceId, deviceName: deviceName);
    } catch (_) {}
  }

  /// 向指定对端发送字符串消息
  Future<void> send(String toId, String data) async {
    try {
      await _service.sendMessage(toId, data);
    } catch (_) {}
  }

  /// 向多个对端广播（逐一发送）
  Future<void> broadcast(Iterable<String> ids, String data) async {
    for (final id in ids) {
      await send(id, data);
    }
  }

  Future<void> stop() async {
    try {
      await _service.stopAdvertisingPeer();
      await _service.stopBrowsingForPeers();
    } catch (_) {}
  }

  // 防御式取 Map，避免版本差异导致类型转换异常
  static Map<String, dynamic>? _asMap(dynamic obj) {
    if (obj is Map) {
      return obj.map((k, v) => MapEntry(k.toString(), v));
    }
    try {
      final m = (obj as dynamic).toJson();
      if (m is Map) return m.map((k, v) => MapEntry(k.toString(), v));
    } catch (_) {}
    return null;
  }

  static String? _str(dynamic v) => v == null ? null : v.toString();
}
