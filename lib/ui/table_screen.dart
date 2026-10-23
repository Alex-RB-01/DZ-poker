/// 牌桌对局界面：环形座位牌桌 + 操作栏 + 日志 + 结算/淘汰覆盖层
library;

import 'dart:math';

import 'package:flutter/material.dart' hide Card;
import 'package:flutter/services.dart';

import '../engine/game.dart';
import '../net/transport.dart';
import '../state/controller.dart';
import 'theme.dart';

class GameScreen extends StatefulWidget {
  final GameController controller;
  const GameScreen({super.key, required this.controller});

  @override
  State<GameScreen> createState() => _GameScreenState();
}

class _GameScreenState extends State<GameScreen> {
  @override
  void initState() {
    super.initState();
    // 牌桌专横屏：把完整桌面与 10 人座位都摊开
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
  }

  @override
  void dispose() {
    // 关闭牌桌时一并释放控制器（停掉 AI 计时器 / 网络会话）
    widget.controller.dispose();
    // 恢复自动旋转
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      child: Scaffold(
        body: SafeArea(
          child: AnimatedBuilder(
            animation: widget.controller,
            builder: (context, _) => _Body(controller: widget.controller),
          ),
        ),
      ),
    );
  }
}

class _Body extends StatelessWidget {
  final GameController controller;
  const _Body({required this.controller});

  @override
  Widget build(BuildContext context) {
    final c = controller;
    // 房主还没开局 → 等候房
    if (c.mode == GameMode.host && c.g.handNumber == 0) {
      return _HostLobby(controller: c);
    }
    // 客人还没收到座位分配 → 等待
    if (c.mode == GameMode.client && c.g.handNumber == 0) {
      return const Center(
          child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
          CircularProgressIndicator(),
          SizedBox(height: 16),
          Text('已发送加入请求，等待房主开始…'),
          SizedBox(height: 8),
          Text('（若房主已开始游戏，请让房主重新开局）',
              style: TextStyle(fontSize: 12, color: Colors.white38)),
        ]));
    }
    if (c.g.players.isEmpty) return const SizedBox.shrink();

    return Column(
      children: [
        _TopBar(controller: c),
        Expanded(
          flex: 6,
          child: LayoutBuilder(
            builder: (context, box) =>
                _TableArea(controller: c, size: box.biggest),
          ),
        ),
        _HeroStrip(controller: c),
        _LogTicker(controller: c),
        _ActionBar(controller: c),
      ],
    );
  }
}

// ---------------- 顶栏 ----------------

class _TopBar extends StatelessWidget {
  final GameController controller;
  const _TopBar({required this.controller});

  @override
  Widget build(BuildContext context) {
    final g = controller.g;
    final streetName = switch (g.street) {
      Street.preflop => '翻牌前',
      Street.flop => '翻牌',
      Street.turn => '转牌',
      Street.river => '河牌',
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      color: AppTheme.panel,
      child: Row(
        children: [
          Text('第 ${g.handNumber} 手',
              style: const TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(width: 12),
          Text('盲注 ${g.blinds.sb}/${g.blinds.bb} (L${g.level + 1})',
              style: const TextStyle(color: AppTheme.gold)),
          const SizedBox(width: 12),
          Text(streetName, style: const TextStyle(color: Colors.white54)),
          const Spacer(),
          IconButton(
            icon: const Icon(Icons.schedule, size: 20),
            tooltip: '盲注级别表',
            onPressed: () => _showBlindSheet(context, controller),
          ),
          IconButton(
            icon: const Icon(Icons.exit_to_app, size: 20),
            tooltip: '退出',
            onPressed: () => _confirmExit(context),
          ),
        ],
      ),
    );
  }

  void _showBlindSheet(BuildContext context, GameController c) {
    final g = c.g;
    showModalBottomSheet(
      context: context,
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
                padding: EdgeInsets.all(12),
                child: Text('盲注级别表',
                    style:
                        TextStyle(fontWeight: FontWeight.bold, fontSize: 16))),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                children: [
                  for (var i = 0; i < g.config.levels.length; i++)
                    ListTile(
                      dense: true,
                      leading: Text('L${i + 1}',
                          style: TextStyle(
                              color: i == g.level
                                  ? AppTheme.gold
                                  : Colors.white38,
                              fontWeight: i == g.level
                                  ? FontWeight.bold
                                  : FontWeight.normal)),
                      title: Text(
                          '${g.config.levels[i].sb} / ${g.config.levels[i].bb}'),
                      trailing: i == g.level
                          ? const Icon(Icons.check,
                              size: 16, color: AppTheme.gold)
                          : null,
                    ),
                ],
              ),
            ),
            if (c.mode != GameMode.client)
              Padding(
                padding: const EdgeInsets.all(12),
                child: FilledButton(
                  onPressed: () {
                    c.skipBlindLevel();
                    Navigator.pop(context);
                  },
                  child: const Text('手动升到下一级盲注'),
                ),
              ),
          ],
        ),
      ),
    );
  }

  void _confirmExit(BuildContext context) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('退出本局？'),
        content: const Text('退出后你将离开牌桌（掉线会自动弃牌）。'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('取消')),
          FilledButton(
            onPressed: () {
              Navigator.pop(context);
              // 逐层退出到首页
              Navigator.of(context, rootNavigator: true)
                  .popUntil((r) => r.isFirst);
            },
            style: FilledButton.styleFrom(backgroundColor: AppTheme.foldRed),
            child: const Text('退出'),
          ),
        ],
      ),
    );
  }
}

// ---------------- 牌桌区域 ----------------

class _TableArea extends StatelessWidget {
  final GameController controller;
  final Size size;
  const _TableArea({required this.controller, required this.size});

  @override
  Widget build(BuildContext context) {
    final g = controller.g;
    final w = size.width;
    final h = size.height;
    final n = g.players.length;
    if (n == 0) return const SizedBox.shrink();

    // 座位顺序：自己(或观战时座位0)在底部，顺时针排布
    final ordered = <int>[
      for (var i = 0; i < n; i++) (controller.mySeat + i) % n
    ];
    final angles = <double>[
      for (var d = 0; d < n; d++) (90 + 360 * d / n) * pi / 180
    ];

    // 座位盒：紧凑但信息完整（昵称/筹码/状态/底牌），不与中央桌面重叠
    const seatH = 76.0;
    var seatW = min(w * 0.22, 150.0);

    // 座位中心所在的椭圆（贴边排布）
    final a = w / 2 - seatW / 2 - 4.0;

    // 计算相邻座位最小水平间距，防止座位互相遮挡
    var minHGap = double.infinity;
    for (var i = 0; i < n; i++) {
      final dcos = (cos(angles[i]) - cos(angles[(i + 1) % n])).abs();
      final gap = a * dcos;
      if (gap < minHGap) minHGap = gap;
    }
    seatW = max(60.0, min(seatW, minHGap - 6));

    // 用夹紧后的 seatW 重新计算贴边椭圆
    final a2 = w / 2 - seatW / 2 - 4.0;
    final b2 = h / 2 - seatH / 2 - 4.0;

    // 中央桌面椭圆：严格位于座位环内侧，留 10px 间隙，绝不遮挡中央公共牌
    final tableA = max(40.0, a2 - seatW / 2 - 12.0);
    final tableB = max(30.0, b2 - seatH / 2 - 12.0);

    final children = <Widget>[
      // 桌面
      Center(
        child: Container(
          width: tableA * 2,
          height: tableB * 2,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(tableB),
            border: Border.all(color: AppTheme.tableRim, width: 8),
            gradient: const RadialGradient(
              colors: [AppTheme.tableGreen, AppTheme.tableGreenDark],
            ),
          ),
        ),
      ),
      // 中心：底池 + 公共牌 + 街名
      Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('底池 ${AppTheme.money(g.potTotal)}',
                style: const TextStyle(
                    color: AppTheme.gold,
                    fontWeight: FontWeight.bold,
                    fontSize: 16)),
            const SizedBox(height: 6),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (var i = 0; i < 5; i++)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 2),
                    child: i < g.board.length
                        ? CardView(card: g.board[i], width: 42)
                        : CardView.empty(width: 42),
                  ),
              ],
            ),
          ],
        ),
      ),
    ];

    for (var d = 0; d < n; d++) {
      final seat = ordered[d];
      final rad = angles[d];
      final cx = w / 2 + a2 * cos(rad);
      final cy = h / 2 + b2 * sin(rad);
      children.add(Positioned(
        left: cx - seatW / 2,
        top: cy - seatH / 2,
        child: SeatView(
          controller: controller,
          seat: seat,
          width: seatW,
        ),
      ));
    }

    return Stack(children: children);
  }
}

class SeatView extends StatelessWidget {
  final GameController controller;
  final int seat;
  final double width;
  const SeatView(
      {super.key,
      required this.controller,
      required this.seat,
      required this.width});

  @override
  Widget build(BuildContext context) {
    final g = controller.g;
    final p = g.players[seat];
    final isToAct = g.toAct == seat && !g.handOver;
    final showCards = p.hasCards &&
        (p.hole.isNotEmpty) &&
        (seat == controller.mySeat || p.revealed);
    final isDealer = g.button == seat && g.handNumber > 0;

    final Color ring = isToAct
        ? AppTheme.gold
        : p.folded
            ? Colors.white12
            : Colors.white24;

    // 底牌：自己/摊牌亮真牌；其余持牌者显示牌背；未持牌不显示
    final List<Widget> cardRow;
    if (!p.hasCards) {
      cardRow = [const SizedBox(height: 22)];
    } else if (showCards) {
      cardRow = [
        for (final c in p.hole)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 1),
            child: CardView(card: c, width: 20, small: true),
          ),
      ];
    } else {
      cardRow = [
        CardView.back(width: 20, small: true),
        const SizedBox(width: 2),
        CardView.back(width: 20, small: true),
      ];
    }

    final statusText = p.out
        ? '已出局'
        : p.allIn
            ? 'ALL-IN'
            : p.folded
                ? '弃牌'
                : (g.toAct == seat && !g.handOver ? '思考中…' : '');

    return Opacity(
      opacity: p.folded ? 0.45 : 1,
      child: Container(
        width: width,
        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 4),
        decoration: BoxDecoration(
          color: seat == controller.mySeat
              ? Colors.blueGrey.shade800.withOpacity(0.92)
              : AppTheme.panel.withOpacity(0.92),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: ring, width: isToAct ? 2 : 1),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (isDealer)
                  const Padding(
                    padding: EdgeInsets.only(right: 3),
                    child: Text('D',
                        style: TextStyle(
                            color: AppTheme.gold,
                            fontSize: 11,
                            fontWeight: FontWeight.bold)),
                  ),
                CircleAvatar(
                  radius: 9,
                  backgroundColor: p.isAI ? Colors.teal : AppTheme.callBlue,
                  child: Text(p.name.isNotEmpty ? p.name[0] : '?',
                      style: const TextStyle(fontSize: 10)),
                ),
                const SizedBox(width: 4),
                Flexible(
                  child: Text(p.name,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: 11, fontWeight: FontWeight.bold)),
                ),
              ],
            ),
            Text(AppTheme.money(p.chips),
                style: const TextStyle(fontSize: 11, color: AppTheme.gold)),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: cardRow,
            ),
            Text(
              statusText,
              style: TextStyle(
                  fontSize: 9,
                  color: p.allIn
                      ? AppTheme.allinOrange
                      : p.folded
                          ? Colors.white38
                          : Colors.white70),
            ),
            if (p.roundBet > 0 && !g.handOver)
              Container(
                margin: const EdgeInsets.only(top: 2),
                padding:
                    const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                decoration: BoxDecoration(
                  color: Colors.black26,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text('下注 ${p.roundBet}',
                    style: const TextStyle(fontSize: 9)),
              ),
          ],
        ),
      ),
    );
  }
}

// ---------------- 扑克牌 ----------------

class CardView extends StatelessWidget {
  static const _front = 0, _back = 1, _empty = 2;
  final Card? card;
  final double width;
  final bool small;
  final int _style;
  const CardView({super.key, required this.card, this.width = 44, this.small = false})
      : _style = _front;
  const CardView.empty({super.key, this.width = 44, this.small = false})
      : card = null,
        _style = _empty;
  const CardView.back({super.key, this.width = 44, this.small = false})
      : card = null,
        _style = _back;

  @override
  Widget build(BuildContext context) {
    final h = width * 1.4;
    if (_style != _front) {
      return Container(
        width: width,
        height: h,
        decoration: _style == _empty
            ? BoxDecoration(
                border: Border.all(color: Colors.white24, width: 1),
                borderRadius: BorderRadius.circular(4),
              )
            : BoxDecoration(
                gradient: const LinearGradient(
                    colors: [Color(0xFF274b8f), Color(0xFF16294f)]),
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: Colors.white24, width: 1),
              ),
        alignment: Alignment.center,
        child: _style == _empty
            ? null
            : Text('♠',
                style: TextStyle(
                    fontSize: width * 0.4,
                    color: Colors.white.withOpacity(0.35))),
      );
    }
    final c = card!;
    final rankText = c.rank == 14
        ? 'A'
        : c.rank == 13
            ? 'K'
            : c.rank == 12
                ? 'Q'
                : c.rank == 11
                    ? 'J'
                    : c.rank == 10
                        ? '10'
                        : '${c.rank}';
    final fontSize = small ? width * 0.52 : width * 0.42;
    // 红桃/方块=红；梅花=蓝；黑桃=黑。梅花用蓝避免与黑桃混淆
    final fg = c.isRed
        ? AppTheme.cardRed
        : (c.suit == 3 ? AppTheme.clubBlue : Colors.black87);
    return Container(
      width: width,
      height: h,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: Colors.black26, width: 1),
      ),
      alignment: Alignment.center,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(rankText,
              style: TextStyle(
                  fontSize: fontSize,
                  height: 1.0,
                  fontWeight: FontWeight.bold,
                  color: fg)),
          Text(kSuitChars[c.suit],
              style: TextStyle(
                  fontSize: fontSize * 0.85, height: 1.0, color: fg)),
        ],
      ),
    );
  }
}

// ---------------- 自己的信息条 ----------------

class _HeroStrip extends StatelessWidget {
  final GameController controller;
  const _HeroStrip({required this.controller});

  @override
  Widget build(BuildContext context) {
    final g = controller.g;
    final me = g.players[controller.mySeat];
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      color: AppTheme.panel,
      child: Row(
        children: [
          for (final card in me.hole)
            Padding(
              padding: const EdgeInsets.only(right: 6),
              child: CardView(card: card, width: 40),
            ),
          if (me.hole.isEmpty) ...[
            CardView.back(width: 40),
            const SizedBox(width: 6),
            CardView.back(width: 40),
          ],
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(me.name,
                  style: const TextStyle(
                      fontWeight: FontWeight.bold, fontSize: 14)),
              Text('筹码 ${AppTheme.money(me.chips)}',
                  style: const TextStyle(
                      color: AppTheme.gold, fontSize: 13)),
            ],
          ),
          const Spacer(),
          if (me.out)
            const Text('你已出局（观战中）',
                style: TextStyle(color: Colors.white38)),
        ],
      ),
    );
  }
}

// ---------------- 日志 ----------------

class _LogTicker extends StatelessWidget {
  final GameController controller;
  const _LogTicker({required this.controller});

  @override
  Widget build(BuildContext context) {
    final g = controller.g;
    final last = g.log.isEmpty ? '' : g.log.last;
    return InkWell(
      onTap: () => showModalBottomSheet(
        context: context,
        builder: (_) => SafeArea(
          child: ListView(
            children: [
              for (final line in g.log)
                Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 3),
                  child: Text(line,
                      style:
                          const TextStyle(fontSize: 13, color: Colors.white70)),
                ),
            ],
          ),
        ),
      ),
      child: Container(
        width: double.infinity,
        color: Colors.black26,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
        child: Text(
          last,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 12, color: Colors.white54),
        ),
      ),
    );
  }
}

// ---------------- 操作栏 ----------------

class _ActionBar extends StatefulWidget {
  final GameController controller;
  const _ActionBar({required this.controller});

  @override
  State<_ActionBar> createState() => _ActionBarState();
}

class _ActionBarState extends State<_ActionBar> {
  bool _raiseOpen = false;
  double _raiseValue = 0;

  @override
  Widget build(BuildContext context) {
    final c = widget.controller;
    final g = c.g;

    // 结算覆盖
    if (g.gameOver) return _GameOver(controller: c);
    if (g.handOver && g.lastResult != null) {
      return _ResultPanel(controller: c);
    }

    final me = g.players[c.mySeat];
    final myTurn = c.isMyTurn && !me.out;
    final legal = myTurn ? g.legalActions(c.mySeat) : null;

    if (!myTurn || legal == null) {
      final waiting = (g.toAct >= 0 && !g.handOver)
          ? '${g.players[g.toAct].name} ${g.players[g.toAct].isAI ? "思考中…" : "行动中…"}'
          : '等待下一手…';
      return Container(
        padding: const EdgeInsets.all(16),
        color: AppTheme.panel,
        child: Center(
            child: Text(waiting,
                style: const TextStyle(color: Colors.white54, fontSize: 15))),
      );
    }

    final canCheck = legal.canCheck;
    final callLabel = canCheck
        ? '过牌'
        : '跟注 ${AppTheme.money(legal.callAmount)}';

    final raisePanel = _raiseOpen
        ? Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            color: Colors.black26,
            child: Column(
              children: [
                Slider(
                  min: legal.minRaiseTo.toDouble(),
                  max: legal.maxRaiseTo.toDouble(),
                  divisions: (legal.maxRaiseTo - legal.minRaiseTo) <= 0
                      ? null
                      : (legal.maxRaiseTo - legal.minRaiseTo),
                  value: _raiseValue.clamp(legal.minRaiseTo.toDouble(),
                      legal.maxRaiseTo.toDouble()),
                  label: AppTheme.money(_raiseValue.round()),
                  onChanged: (v) => setState(() => _raiseValue = v),
                ),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    for (final frac in [0.33, 0.5, 1.0])
                      OutlinedButton(
                        onPressed: () {
                          final target =
                              (g.potTotal * frac).round() + g.currentBet;
                          setState(() {
                            _raiseValue = target
                                .clamp(legal.minRaiseTo, legal.maxRaiseTo)
                                .toDouble();
                          });
                        },
                        child: Text(frac == 1.0 ? '满池' : '${(frac * 100).round()}%池'),
                      ),
                    OutlinedButton(
                      onPressed: () => setState(
                          () => _raiseValue = legal.maxRaiseTo.toDouble()),
                      child: const Text('全下额'),
                    ),
                    FilledButton(
                      style: FilledButton.styleFrom(
                          backgroundColor: AppTheme.raiseGreen),
                      onPressed: () {
                        setState(() => _raiseOpen = false);
                        c.sendMyAction(PokerAction('raise',
                            amount: _raiseValue.round()));
                      },
                      child: Text('加注到 ${_raiseValue.round()}'),
                    ),
                  ],
                ),
              ],
            ),
          )
        : const SizedBox.shrink();

    return Container(
      color: AppTheme.panel,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          raisePanel,
          Padding(
            padding: const EdgeInsets.all(10),
            child: Row(
              children: [
                Expanded(
                  child: FilledButton(
                    style: FilledButton.styleFrom(
                        backgroundColor: AppTheme.foldRed,
                        padding: const EdgeInsets.symmetric(vertical: 14)),
                    onPressed: () => c.sendMyAction(const PokerAction('fold')),
                    child: const Text('弃牌'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  flex: 2,
                  child: FilledButton(
                    style: FilledButton.styleFrom(
                        backgroundColor: AppTheme.callBlue,
                        padding: const EdgeInsets.symmetric(vertical: 14)),
                    onPressed: () => c.sendMyAction(
                        const PokerAction('call')),
                    child: Text(callLabel),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  flex: 2,
                  child: FilledButton(
                    style: FilledButton.styleFrom(
                        backgroundColor: AppTheme.raiseGreen,
                        padding: const EdgeInsets.symmetric(vertical: 14)),
                    onPressed: legal.canRaise
                        ? () {
                            setState(() {
                              _raiseOpen = !_raiseOpen;
                              _raiseValue = legal.minRaiseTo.toDouble();
                            });
                          }
                        : null,
                    child: const Text('加注'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: FilledButton(
                    style: FilledButton.styleFrom(
                        backgroundColor: AppTheme.allinOrange,
                        padding: const EdgeInsets.symmetric(vertical: 14)),
                    onPressed: () {
                      if (legal.callAmount >= me.chips) {
                        c.sendMyAction(const PokerAction('call'));
                      } else {
                        c.sendMyAction(PokerAction('raise',
                            amount: legal.maxRaiseTo));
                      }
                    },
                    child: const Text('全下'),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------- 结算面板 ----------------

class _ResultPanel extends StatelessWidget {
  final GameController controller;
  const _ResultPanel({required this.controller});

  @override
  Widget build(BuildContext context) {
    final g = controller.g;
    final r = g.lastResult!;
    final lines = <Widget>[];
    r.seatWin.forEach((seat, win) {
      final p = g.players[seat];
      final hn = r.handNames[seat];
      lines.add(Row(
        children: [
          Text('${p.name} 赢得 ${AppTheme.money(win)}',
              style: const TextStyle(
                  color: AppTheme.gold, fontWeight: FontWeight.bold)),
          if (hn != null)
            Padding(
              padding: const EdgeInsets.only(left: 8),
              child: Text('（$hn）', style: const TextStyle(color: Colors.white54)),
            ),
        ],
      ));
    });
    return Container(
      color: AppTheme.panel,
      padding: const EdgeInsets.all(12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ...lines,
          if (r.reveal.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Wrap(
                spacing: 10,
                children: [
                  for (final entry in r.reveal.entries)
                    Row(mainAxisSize: MainAxisSize.min, children: [
                      Text(g.players[entry.key].name,
                          style: const TextStyle(fontSize: 12)),
                      const SizedBox(width: 4),
                      for (final code in entry.value)
                        Padding(
                          padding: const EdgeInsets.only(right: 2),
                          child: CardView(
                              card: Card.fromCode(code), width: 20, small: true),
                        ),
                    ]),
                ],
              ),
            ),
          const Padding(
            padding: EdgeInsets.only(top: 8),
            child: Text('看完桌面后，点“下一手”开始新手牌',
                style: TextStyle(fontSize: 12, color: Colors.white54)),
          ),
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: FilledButton(
              style: FilledButton.styleFrom(
                  backgroundColor: AppTheme.raiseGreen,
                  padding: const EdgeInsets.symmetric(vertical: 14)),
              onPressed: () => controller.requestNextHand(),
              child: const Text('下一手', style: TextStyle(fontSize: 17)),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------- 比赛结束 ----------------

class _GameOver extends StatelessWidget {
  final GameController controller;
  const _GameOver({required this.controller});

  @override
  Widget build(BuildContext context) {
    final champ = controller.g.players
        .firstWhere((p) => !p.out, orElse: () => controller.g.players[0]);
    return Container(
      color: AppTheme.panel,
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('🏆 比赛结束',
              style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  color: AppTheme.gold)),
          const SizedBox(height: 8),
          Text('${champ.name} 获胜！',
              style: const TextStyle(fontSize: 18)),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (controller.mode != GameMode.client)
                FilledButton(
                  onPressed: () => controller.nextHand(),
                  child: const Text('再来一场（新比赛需重开）'),
                ),
              const SizedBox(width: 12),
              OutlinedButton(
                onPressed: () => Navigator.of(context, rootNavigator: true)
                    .popUntil((r) => r.isFirst),
                child: const Text('返回首页'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ---------------- 房主等候房 ----------------

class _HostLobby extends StatefulWidget {
  final GameController controller;
  const _HostLobby({required this.controller});

  @override
  State<_HostLobby> createState() => _HostLobbyState();
}

class _HostLobbyState extends State<_HostLobby> {
  int _aiFill = 2;
  String _ip = '获取中…';

  @override
  void initState() {
    super.initState();
    localIpAddress().then((v) {
      if (mounted) setState(() => _ip = v);
    });
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.controller;
    final hs = c.hostSession!;
    final clients = hs.pendingClients.values.toList();
    final total = 1 + clients.length + _aiFill;
    return Scaffold(
      backgroundColor: AppTheme.bg,
      appBar: AppBar(title: const Text('房间等候中（同 WiFi）')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text('已连接玩家：',
              style: TextStyle(fontWeight: FontWeight.bold, color: AppTheme.gold)),
          ListTile(
            leading: const CircleAvatar(child: Icon(Icons.person)),
            title: Text('${c.myName}（本机/房主）'),
          ),
          for (final name in clients)
            ListTile(
              leading: const CircleAvatar(child: Icon(Icons.person_outline)),
              title: Text(name),
            ),
          Container(
            margin: const EdgeInsets.symmetric(vertical: 8),
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.black26,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
                '本机局域网 IP：$_ip（端口 ${LanTransport.tcpPort}）\n若对方“加入房间”里搜不到，可让对方手动输入此 IP 连接。',
                style: const TextStyle(fontSize: 12, color: Colors.white70)),
          ),
          const Divider(),
          Text('AI 补位数量：$_aiFill（总人数 $total / 10）',
              style: const TextStyle(color: Colors.white70)),
          Slider(
            value: _aiFill.toDouble(),
            min: 0,
            max: 9,
            divisions: 9,
            label: '$_aiFill',
            onChanged: (v) => setState(() => _aiFill = v.round()),
          ),
          const SizedBox(height: 12),
          FilledButton(
            style: FilledButton.styleFrom(
                backgroundColor: AppTheme.raiseGreen,
                padding: const EdgeInsets.symmetric(vertical: 16)),
            onPressed: total >= 2
                ? () => c.startNetworkGame(aiFill: _aiFill)
                : null,
            child: Text(total >= 2 ? '开始游戏' : '至少需要 2 名玩家',
                style: const TextStyle(fontSize: 17)),
          ),
        ],
      ),
    );
  }
}
