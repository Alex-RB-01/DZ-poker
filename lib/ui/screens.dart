/// 首页 / 大厅（配置） / 加入房间 三个界面
library;

import 'package:flutter/material.dart';

import '../engine/game.dart';
import '../net/session.dart';
import '../state/controller.dart';
import 'table_screen.dart';
import 'theme.dart';

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
            const Text('单机 AI · 最多 10 人 · 锦标赛盲注',
                style: TextStyle(color: Colors.white54)),
            const SizedBox(height: 48),
            _MenuButton(
              icon: Icons.person,
              label: '单机对战（AI）',
              onTap: () => Navigator.push(context,
                  MaterialPageRoute(builder: (_) => const LobbyScreen(local: true))),
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
          title: Text(widget.local ? '单机对战' : '创建蓝牙房间')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TextField(
            controller: _nameCtrl,
            decoration: const InputDecoration(
                labelText: '我的昵称', border: OutlineInputBorder()),
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
            onPressed: _start,
            child: Text(widget.local ? '开始游戏' : '开启蓝牙房间并等待玩家',
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

  void _start() {
    final config = GameConfig(
      startingChips: _startingChips,
      levels: _levels,
      advanceEvery: _advanceEvery,
      advanceMode: _advanceMode,
    );
    final name = _nameCtrl.text.trim().isEmpty ? '玩家' : _nameCtrl.text.trim();
    if (widget.local) {
      final c = GameController.local(
          myName: name, aiCount: _aiCount, config: config);
      Navigator.pushReplacement(context,
          MaterialPageRoute(builder: (_) => GameScreen(controller: c)));
    } else {
      final c = GameController.host(myName: name, config: config);
      Navigator.pushReplacement(context,
          MaterialPageRoute(builder: (_) => GameScreen(controller: c)));
    }
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
  ClientSession? _session;
  bool _started = false;
  String _status = '正在搜索附近房间…';
  GameController? _controller;

  @override
  void initState() {
    super.initState();
    _startBrowsing();
  }

  Future<void> _startBrowsing() async {
    final name = _nameCtrl.text.trim().isEmpty ? '玩家' : _nameCtrl.text.trim();
    final session = ClientSession(
        myName: name,
        onMessage: _onMsg,
        onChanged: () {
          if (mounted) setState(() {});
        });
    _session = session;
    await session.start();
    if (mounted) {
      setState(() => _started = true);
    }
  }

  void _onMsg(Map<String, dynamic> msg) {
    if (msg['t'] == 'seat') {
      final c = GameController.client(
          myName:
              _nameCtrl.text.trim().isEmpty ? '玩家' : _nameCtrl.text.trim(),
          session: _session!);
      c.onClientMessage(msg);
      _controller = c;
      if (!mounted) return;
      Navigator.pushReplacement(context,
          MaterialPageRoute(builder: (_) => GameScreen(controller: c)));
    }
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
      appBar: AppBar(title: const Text('加入蓝牙房间')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: TextField(
              controller: _nameCtrl,
              decoration: const InputDecoration(
                  labelText: '我的昵称', border: OutlineInputBorder()),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                !_started ? '正在初始化蓝牙…' : (hosts.isEmpty ? '未发现房间，请确认房主已创建且双方蓝牙/定位权限已开启' : '发现 ${hosts.length} 个房间'),
                style: const TextStyle(color: Colors.white54),
              ),
            ),
          ),
          Expanded(
            child: ListView(
              children: hosts.entries
                  .map((e) => ListTile(
                        leading: const Icon(Icons.table_restaurant,
                            color: AppTheme.gold),
                        title: Text(e.value),
                        subtitle: Text('点击加入 · ${e.key}'),
                        onTap: _started
                            ? () async {
                                setState(() => _status = '正在加入…');
                                await _session!.join(
                                    e.key,
                                    _nameCtrl.text.trim().isEmpty
                                        ? '玩家'
                                        : _nameCtrl.text.trim());
                              }
                            : null,
                      ))
                  .toList(),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(12),
            child: Text(_status,
                style: const TextStyle(fontSize: 12, color: Colors.white38)),
          ),
        ],
      ),
    );
  }
}
