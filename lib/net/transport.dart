/// 同 WiFi 局域网传输层（纯 dart:io 实现，无第三方插件依赖）。
///
/// 设计：
///  - 发现：UDP 组播信标（239.255.255.250:4790）。房主周期性广播房间名+IP+端口；
///    客人监听信标得到可加入的房间列表。若组播被系统拦截，客人可用「手动输入主机 IP」兜底。
///  - 可靠通信：TCP。房主监听 [tcpPort]，每个连入的客人是一条 TCP 连接；
///    消息以「一行一个 JSON + 换行符」分帧，保证有序、不丢、自动重连友好。
///
/// 本文件替代原先基于 flutter_nearby_connections 的实现（该插件已无法在 Flutter 3.x 编译）。
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// 在局域网中发现到的房间
class HostBeacon {
  final String id; // "$addr:$port"
  final String name;
  final String addr;
  final int port;
  HostBeacon(
      {required this.id,
      required this.name,
      required this.addr,
      required this.port});
}

/// 一条 TCP 连接状态变化（connected=true 已连 / false 已断）
class PeerEvent {
  final String id;
  final String name;
  final bool connected;
  PeerEvent(this.id, this.name, this.connected);
}

/// 收到的一行消息
class IncomingMessage {
  final String fromId;
  final String data;
  IncomingMessage(this.fromId, this.data);
}

class LanTransport {
  static const int tcpPort = 4789;
  static const int udpPort = 4790;
  static const String multicastGroup = '239.255.255.250';

  final bool isHost;
  final String deviceName;

  final StreamController<IncomingMessage> _messages =
      StreamController<IncomingMessage>.broadcast();
  final StreamController<PeerEvent> _peers =
      StreamController<PeerEvent>.broadcast();
  final StreamController<HostBeacon> _beacons =
      StreamController<HostBeacon>.broadcast();

  final Set<String> connectedIds = {};
  final Map<String, _TcpPeer> _peersById = {};
  final Map<String, List<int>> _buf = {};

  ServerSocket? _server;
  RawDatagramSocket? _udp;
  Timer? _beaconTimer;
  int _actualPort = tcpPort;

  LanTransport({required this.isHost, required this.deviceName});

  Stream<IncomingMessage> get messages => _messages.stream;
  Stream<PeerEvent> get peers => _peers.stream;
  Stream<HostBeacon> get beacons => _beacons.stream;

  Future<void> init() async {
    // UDP 组播发现（双方都要监听）
    try {
      _udp = await RawDatagramSocket.bind(InternetAddress.anyIPv4, udpPort);
      try {
        // joinMulticast 返回 void（非 Future），不可 await
        _udp!.joinMulticast(InternetAddress(multicastGroup));
      } catch (_) {
        // 部分设备/网络禁用组播，不影响 TCP 直连
      }
      _udp!.listen(_onUdp);
    } catch (_) {
      _udp = null;
    }

    if (isHost) {
      // TCP 监听：在 4789 起尝试，被占用则顺延端口
      for (var offset = 0; offset < 10; offset++) {
        final tryPort = tcpPort + offset;
        try {
          _server = await ServerSocket.bind(InternetAddress.anyIPv4, tryPort);
          _actualPort = tryPort;
          break;
        } catch (_) {
          _server = null;
        }
      }
      if (_server != null) {
        _server!.listen(_onAccept);
        _beaconTimer =
            Timer.periodic(const Duration(seconds: 2), (_) => _sendBeacon());
        _sendBeacon();
      }
    }
  }

  void _onUdp(RawSocketEvent event) {
    if (event != RawSocketEvent.read) return;
    while (true) {
      final dg = _udp?.receive();
      if (dg == null) break;
      try {
        final map = jsonDecode(utf8.decode(dg.data)) as Map<String, dynamic>;
        if (map['t'] == 'beacon' && !isHost) {
          final addr = dg.address.address;
          final port = (map['port'] as num).toInt();
          final name = (map['name'] ?? '房间').toString();
          _beacons.add(HostBeacon(
              id: '$addr:$port', name: name, addr: addr, port: port));
        }
      } catch (_) {}
    }
  }

  Future<void> _sendBeacon() async {
    if (_udp == null) return;
    final ip = await localIpAddress();
    final body = jsonEncode(
        {'t': 'beacon', 'name': deviceName, 'port': _actualPort, 'addr': ip});
    final data = utf8.encode(body);
    try {
      _udp!.send(data, InternetAddress(multicastGroup), udpPort);
    } catch (_) {}
  }

  void _onAccept(Socket socket) {
    final id =
        '${socket.remoteAddress.address}:${socket.remotePort}';
    _registerPeer(id, socket, '');
  }

  void _registerPeer(String id, Socket socket, String name) {
    final peer = _TcpPeer(id, socket, name);
    _peersById[id] = peer;
    connectedIds.add(id);
    _peers.add(PeerEvent(id, name, true));
    socket.listen(
      (bytes) => _onSocketData(id, bytes),
      onDone: () => _dropPeer(id),
      onError: (_) => _dropPeer(id),
    );
  }

  void _onSocketData(String id, List<int> bytes) {
    _buf[id] ??= <int>[];
    _buf[id]!.addAll(bytes);
    while (true) {
      final idx = _indexOfNewline(_buf[id]!);
      if (idx < 0) break;
      final line = utf8.decode(_buf[id]!.sublist(0, idx));
      _buf[id]!.removeRange(0, idx + 1);
      if (line.isNotEmpty) _messages.add(IncomingMessage(id, line));
    }
  }

  int _indexOfNewline(List<int> b) {
    for (var i = 0; i < b.length; i++) {
      if (b[i] == 10) return i; // '\n'
    }
    return -1;
  }

  void _dropPeer(String id) {
    final peer = _peersById.remove(id);
    if (peer != null) {
      try {
        peer.socket.destroy();
      } catch (_) {}
    }
    connectedIds.remove(id);
    _buf.remove(id);
    _peers.add(PeerEvent(id, '', false));
  }

  // ---- 客人：主动连接房主 ----
  Future<void> connectToHost(String addr, int port) async {
    final socket = await Socket.connect(addr, port);
    _registerPeer('$addr:$port', socket, '');
  }

  // ---- 发送 ----
  void send(String toId, String data) {
    _peersById[toId]?.send(data);
  }

  void broadcast(String data) {
    for (final p in _peersById.values) {
      p.send(data);
    }
  }

  Future<void> stop() async {
    _beaconTimer?.cancel();
    _beaconTimer = null;
    for (final p in _peersById.values) {
      try {
        p.socket.destroy();
      } catch (_) {}
    }
    _peersById.clear();
    connectedIds.clear();
    _buf.clear();
    try {
      await _server?.close();
    } catch (_) {}
    try {
      _udp?.close();
    } catch (_) {}
    _server = null;
    _udp = null;
  }
}

class _TcpPeer {
  final String id;
  final Socket socket;
  String name;
  _TcpPeer(this.id, this.socket, this.name);
  void send(String data) {
    try {
      socket.write('$data\n');
    } catch (_) {}
  }
}

/// 获取本机首个非回环 IPv4 地址（用于房主显示 / 组播信标）
Future<String> localIpAddress() async {
  try {
    final ifaces = await NetworkInterface.list(
        type: InternetAddressType.IPv4, includeLinkLocal: false);
    for (final i in ifaces) {
      for (final a in i.addresses) {
        final s = a.address;
        if (!s.startsWith('127.') && !s.startsWith('169.254.')) return s;
      }
    }
  } catch (_) {}
  return '0.0.0.0';
}
