/// 邻近网络传输封装（占位实现）。
///
/// 原实现依赖 flutter_nearby_connections 插件，但该插件（1.1.2）基于已被
/// 现代 Flutter 移除的老 API（Registrar），无法在 Flutter 3.x 上编译，故暂时
/// 移除插件、保留本接口空实现，使工程可正常构建并运行单机/同屏传手机模式。
/// 真正的同 WiFi 联机需后续接入受维护的插件后在此处实现。
library;

import 'dart:async';
import 'dart:convert';

/// 单个对端设备的状态变化事件
class PeerEvent {
  final String id; // deviceId
  final String name; // deviceName
  final bool connected;
  PeerEvent(this.id, this.name, this.connected);
}

/// 一条收到的消息
class IncomingMessage {
  final String fromId;
  final String data;
  IncomingMessage(this.fromId, this.data);
}

class NearbyTransport {
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

  /// 初始化并开始发现 / 广播。占位实现：不连接任何真实对等端。
  Future<void> init() async {
    // TODO(联网): 接入受维护的 nearby 插件后在此启动发现/广播。
  }

  Future<void> invite(String deviceId) async {}
  Future<void> send(String toId, String data) async {}
  Future<void> broadcast(Iterable<String> ids, String data) async {}
  Future<void> stop() async {}
}
