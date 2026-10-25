/// 首页 / 大厅（配置） / 加入房间 三个界面
library;

import 'dart:io';

import 'package:flutter/material.dart';

import '../engine/game.dart';
import '../net/session.dart';
import '../net/transport.dart';
import '../state/controller.dart';
import '../util/avatar.dart';
import 'table_screen.dart';
import 'theme.dart';

/// 头像选择圈：点击从相册选图，自动持久化并回调 base64
class AvatarPickerCircle extends StatefulWidget {
  final double radius;
  final void Function(String? b64) onPicked;
  const AvatarPickerCircle(
      {super.key, this.radius = 28, required this.onPicked});

  @override
  State<AvatarPickerCircle> createState() => _AvatarPickerCircleState();
}

class _AvatarPickerCircleState extends State<AvatarPickerCircle> {
  String? _path;

  @override
  void initState() {
    super.initState();
    AvatarStore.loadPath().then((p) {
      if (mounted && p != null) setState(() => _path = p);
    });
  }

  Future<void> _pick() async {
    final p = await AvatarStore.pickAndSave();
    if (p == null) return; // 用户取消
    setState(() => _path = p);
    widget.onPicked(await AvatarStore.toBase64(p));
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: _pick,
      child: CircleAvatar(
        radius: widget.radius,
        backgroundColor: AppTheme.callBlue.withOpacity(0.35),
        backgroundImage: _path != null ? FileImage(File(_path!)) : null,
        child: _path == null
            ? Icon(Icons.add_a_photo,
                size: widget.radius * 0.8, color: Colors.white70)
            : null,
      ),
    );
  }
}

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text('♠ ♥ 德州扑克 ♦ ♣',
                style: TextStyle(
                    fontSize: 34,
                    fontWeight: FontWeight.bold,
                    color: AppTheme.gold)),
            const SizedBox(height: 8),
            const Text('单机 AI · 同 WiFi 联机 · 最多 10 人 · 锦标赛盲注',
                style: TextStyle(color: Colors.white54)),
            const SizedBox(height: 40),
            _MenuButton(
              icon: Icons.smartphone,
              label: '单机对战（AI）',
              onTap: () => Navigator.push(context,
                  MaterialPageRoute(builder: (_) => const LobbyScreen(local: true))),
            ),
            const SizedBox(height: 16),
            _MenuButton(
              icon: Icons.wifi_tethering,
              label: '创建房间（房主）',
              onTap: () => Navigator.push(context,
                  MaterialPageRoute(builder: (_) => const LobbyScreen(local: false))),
            ),
            const SizedBox(height: 16),
            _MenuButton(
              icon: Icons.login,
              label: '加入房间（同 WiFi）',
              onTap: () => Navigator.push(context,
                  MaterialPageRoute(builder: (_) => const JoinScreen())),
            ),
            const SizedBox(height: 32),
            const Text('虚拟筹码 · 仅供娱乐，不涉及任何真实货币',
                style: TextStyle(fontSize: 12, color: Colors.white38)),
          ],
        ),
      ),
    );
  }
}

class _MenuButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  const _MenuButton({required this.icon, required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 40),
      child: SizedBox(
        width: 320,
        child: FilledButton.tonalIcon(
          onPressed: onTap,
          icon: Icon(icon),
          label: Padding(
            padding: const EdgeInsets.symmetric(vertical: 14),
            child: Text(label, style: const TextStyle(fontSize: 17)),
          ),
        ),
      ),
    );
  }
}

// ---------------- 大厅 / 配置 ----------------

class LobbyScreen extends StatefulWidget {
  final bool local; // true=单机AI false=蓝牙房主
  const LobbyScreen({super.key, required this.local});

  @override
  State<LobbyScreen> createState() => _LobbyScreenState();
}

class _LobbyScreenState extends State<LobbyScreen> {
  final _nameCtrl = TextEditingController(text: '玩家');
  int _startingChips = 5000;
  int _advanceEvery = 10;
  String _advanceMode = 'hands'; // hands | minutes
  int _aiCount = 3;
  List<BlindLevel> _levels = GameConfig.defaultLevels();
  String? _avatarB64;
  String _gender = 'male'; // 'male' 帅哥 / 'female' 女神

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
          title: Text(widget.local ? '单机对战' : '创建 Wi-Fi 房间')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Row(
            children: [
              AvatarPickerCircle(
                  onPicked: (b64) => _avatarB64 = b64),
              const SizedBox(width: 16),
              Expanded(
                child: TextField(
                  controller: _nameCtrl,
                  decoration: const InputDecoration(
                      labelText: '我的昵称', border: OutlineInputBorder()),
                ),
              ),
            ],
          ),
          const Text('点头像可从相册选择照片作为头像',
              style: TextStyle(fontSize: 11, color: Colors.white38)),
          const SizedBox(height: 12),
          _sectionTitle('我的身份'),
          SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: 'male', label: Text('帅哥')),
              ButtonSegment(value: 'female', label: Text('女神')),
            ],
            selected: {_gender},
            onSelectionChanged: (s) => setState(() => _gender = s.first),
          ),
          const SizedBox(height: 16),
          _sectionTitle('初始筹码'),
          Wrap(
            spacing: 8,
            children: [2000, 5000, 10000, 20000]
                .map((v) => ChoiceChip(
                      label: Text(AppTheme.money(v)),
                      selected: _startingChips == v,
                      onSelected: (_) => setState(() => _startingChips = v),
                    ))
                .toList(),
          ),
          const SizedBox(height: 16),
          _sectionTitle('盲注升级方式'),
          SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: 'hands', label: Text('按局数')),
              ButtonSegment(value: 'minutes', label: Text('按时间')),
            ],
            selected: {_advanceMode},
            onSelectionChanged: (s) => setState(() => _advanceMode = s.first),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Text(_advanceMode == 'hands' ? '每 ' : '每 ',
                  style: const TextStyle(color: Colors.white70)),
              Slider(
                value: _advanceEvery.toDouble(),
                min: 1,
                max: 20,
                divisions: 19,
                label: '$_advanceEvery',
                onChanged: (v) => setState(() => _advanceEvery = v.round()),
              ),
              Text(_advanceMode == 'hands' ? ' 手升一级' : ' 分钟升一级',
                  style: const TextStyle(color: Colors.white70)),
            ],
          ),
          const SizedBox(height: 16),
          _sectionTitle('盲注级别表（点按可修改）'),
          ..._levels.asMap().entries.map((e) => ListTile(
                dense: true,
                leading: Text('L${e.key + 1}',
                    style: const TextStyle(color: AppTheme.gold)),
                title: Text('${e.value.sb} / ${e.value.bb}'),
                trailing: e.key == 0
                    ? const Icon(Icons.lock, size: 16, color: Colors.white24)
                    : const Icon(Icons.edit, size: 16),
                onTap: e.key == 0
                    ? null
                    : () => _editLevel(e.key, e.value),
              )),
          if (widget.local) ...[
            const SizedBox(height: 16),
            _sectionTitle('AI 对手数量：$_aiCount'),
            Slider(
              value: _aiCount.toDouble(),
              min: 1,
              max: 9,
              divisions: 8,
              label: '$_aiCount',
              onChanged: (v) => setState(() => _aiCount = v.round()),
            ),
          ],
          const SizedBox(height: 24),
          FilledButton(
            style: FilledButton.styleFrom(
                backgroundColor: AppTheme.raiseGreen,
                padding: const EdgeInsets.symmetric(vertical: 16)),
            onPressed: () {
              _start();
            },
            child: Text(widget.local ? '开始游戏' : '创建房间并等待玩家加入',
                style: const TextStyle(fontSize: 17)),
          ),
        ],
      ),
    );
  }

  Widget _sectionTitle(String t) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Text(t,
            style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.bold,
                color: AppTheme.gold)),
      );

  void _editLevel(int idx, BlindLevel lv) {
    final sbCtrl = TextEditingController(text: lv.sb.toString());
    final bbCtrl = TextEditingController(text: lv.bb.toString());
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: Text('编辑级别 L${idx + 1}'),
        content: Row(children: [
          Expanded(
              child: TextField(
                  controller: sbCtrl,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: '小盲'))),
          const SizedBox(width: 12),
          Expanded(
              child: TextField(
                  controller: bbCtrl,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: '大盲'))),
        ]),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('取消')),
          FilledButton(
            onPressed: () {
              final sb = int.tryParse(sbCtrl.text) ?? lv.sb;
              final bb = int.tryParse(bbCtrl.text) ?? lv.bb;
              setState(() => _levels[idx] = BlindLevel(sb, bb < sb ? sb : bb));
              Navigator.pop(context);
            },
            child: const Text('保存'),
          ),
        ],
      ),
    );
  }

  Future<void> _start() async {
    final config = GameConfig(
      startingChips: _startingChips,
      levels: _levels,
      advanceEvery: _advanceEvery,
      advanceMode: _advanceMode,
    );
    final name = _nameCtrl.text.trim().isEmpty ? '玩家' : _nameCtrl.text.trim();
    if (widget.local) {
      final c = GameController.local(
          myName: name, aiCount: _aiCount, config: config, myGender: _gender);
      c.myAvatarB64 = _avatarB64;
      if (_avatarB64 != null) c.avatarsBySeat[0] = _avatarB64!;
      if (!mounted) return;
      Navigator.pushReplacement(context,
          MaterialPageRoute(builder: (_) => GameScreen(controller: c)));
      return;
    }
    // 房主：直接进入等候房，联网在后台启动（不阻塞、不因网络失败而灰屏）。
    // 即便局域网不可用，也能照常 AI 开局。
    final c = GameController.host(
        myName: name, config: config, myGender: _gender);
    c.myAvatarB64 = _avatarB64;
    if (!mounted) return;
    Navigator.pushReplacement(context,
        MaterialPageRoute(builder: (_) => GameScreen(controller: c)));
    c.startHostInBackground();
  }
}

// ---------------- 加入房间 ----------------

class JoinScreen extends StatefulWidget {
  const JoinScreen({super.key});

  @override
  State<JoinScreen> createState() => _JoinScreenState();
}

class _JoinScreenState extends State<JoinScreen> {
  final _nameCtrl = TextEditingController(text: '玩家');
  final _ipCtrl = TextEditingController();
  ClientSession? _session;
  bool _started = false;
  bool _connecting = false;
  String? _avatarB64;
  String _gender = 'male'; // 'male' 帅哥 / 'female' 女神
  GameController? _controller;

  @override
  void initState() {
    super.initState();
    _startBrowsing();
  }

  String _name() =>
      _nameCtrl.text.trim().isEmpty ? '玩家' : _nameCtrl.text.trim();

  Future<void> _startBrowsing() async {
    final session = ClientSession(
        myName: _name(),
        myGender: _gender,
        onMessage: _onMsg,
        onChanged: () {
          if (mounted) setState(() {});
        });
    _session = session;
    await session.start();
    if (mounted) setState(() => _started = true);
  }

  void _onMsg(Map<String, dynamic> msg) {
    if (_controller != null) {
      _controller!.onClientMessage(msg);
      return;
    }
    if (msg['t'] == 'seat') {
      final c = GameController.client(
          myName: _name(), session: _session!, myGender: _gender);
      c.myAvatarB64 = _avatarB64;
      c.onClientMessage(msg);
      _controller = c;
      if (!mounted) return;
      Navigator.pushReplacement(context,
          MaterialPageRoute(builder: (_) => GameScreen(controller: c)));
    }
  }

  Future<void> _join(HostBeacon b) async {
    if (_connecting) return;
    setState(() => _connecting = true);
    try {
      await _session!
          .join(b.addr, b.port, _name(), avatarB64: _avatarB64);
    } catch (_) {
      if (mounted) {
        setState(() => _connecting = false);
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('无法连接到 ${b.addr}，请确认同一 Wi-Fi')));
      }
      return;
    }
    if (mounted) setState(() => _connecting = false);
  }

  Future<void> _joinManual() async {
    final ip = _ipCtrl.text.trim();
    if (ip.isEmpty || _connecting) return;
    setState(() => _connecting = true);
    try {
      await _session!
          .join(ip, LanTransport.tcpPort, _name(), avatarB64: _avatarB64);
    } catch (_) {
      if (mounted) {
        setState(() => _connecting = false);
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('无法连接，请检查 IP 与 Wi-Fi')));
      }
      return;
    }
    if (mounted) setState(() => _connecting = false);
  }

  @override
  void dispose() {
    // 已进入对局时由 controller 负责关闭；否则这里关
    if (_controller == null) _session?.stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final hosts = _session?.hosts ?? {};
    return Scaffold(
      appBar: AppBar(title: const Text('加入同 WiFi 房间')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                AvatarPickerCircle(onPicked: (b64) => _avatarB64 = b64),
                const SizedBox(width: 16),
                Expanded(
                  child: TextField(
                    controller: _nameCtrl,
                    decoration: const InputDecoration(
                        labelText: '我的昵称', border: OutlineInputBorder()),
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                const Text('身份：', style: TextStyle(color: Colors.white70)),
                SegmentedButton<String>(
                  segments: const [
                    ButtonSegment(value: 'male', label: Text('帅哥')),
                    ButtonSegment(value: 'female', label: Text('女神')),
                  ],
                  selected: {_gender},
                  onSelectionChanged: (s) {
                    setState(() => _gender = s.first);
                    _session?.setMyGender(_gender); // 同步给已建会话
                  },
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                !_started
                    ? '正在初始化…'
                    : (hosts.isEmpty
                        ? '未发现房间，可用下方手动输入主机 IP'
                        : '发现 ${hosts.length} 个房间'),
                style: const TextStyle(color: Colors.white54),
              ),
            ),
          ),
          Expanded(
            child: ListView(
              children: hosts.values
                  .map((b) => ListTile(
                        leading: const Icon(Icons.table_restaurant,
                            color: AppTheme.gold),
                        title: Text(b.name),
                        subtitle: Text('${b.addr} · 点击加入'),
                        onTap: _started ? () => _join(b) : null,
                      ))
                  .toList(),
            ),
          ),
          const Divider(),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _ipCtrl,
                    decoration: const InputDecoration(
                        labelText: '主机 IP（手动）',
                        hintText: '如 192.168.1.5',
                        border: OutlineInputBorder()),
                    keyboardType: TextInputType.number,
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  onPressed: _connecting ? null : _joinManual,
                  child: const Text('连接'),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(12),
            child: Text(
                _connecting
                    ? '正在连接…'
                    : '房间由“创建房间”一方开启，双方须连同一 Wi-Fi',
                style: const TextStyle(fontSize: 12, color: Colors.white38)),
          ),
        ],
      ),
    );
  }
}
