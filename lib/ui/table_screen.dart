/// 牌桌对局界面（竖屏）：椭圆牌桌 + 玩家围桌（照片头像）+ 中央公牌 + 底部手牌/操作栏
library;

import 'dart:convert';
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
    // 牌桌固定竖屏（参考经典德州手游布局）
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
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
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
      color: AppTheme.panel,
      child: Row(
        children: [
          Text('第 ${g.handNumber} 手',
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
          const SizedBox(width: 10),
          Text('盲注 ${g.blinds.sb}/${g.blinds.bb} (L${g.level + 1})',
              style: const TextStyle(color: AppTheme.gold, fontSize: 13)),
          const SizedBox(width: 10),
          Text(streetName, style: const TextStyle(color: Colors.white54, fontSize: 13)),
          const Spacer(),
          IconButton(
            visualDensity: VisualDensity.compact,
            icon: const Icon(Icons.schedule, size: 20),
            tooltip: '盲注级别表',
            onPressed: () => _showBlindSheet(context, controller),
          ),
          IconButton(
            visualDensity: VisualDensity.compact,
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

// ---------------- 牌桌区域（竖屏） ----------------

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

    // ---- 桌面椭圆：占满区域，留少量边距 ----
    final tableW = w * 0.92;
    final tableH = h * 0.86;
    final tableRim = BorderRadius.circular(tableH / 2);

    // ---- 对手座位（自己画在底部信息条，不占桌环）----
    final opponents = <int>[
      for (var s = 0; s < n; s++)
        if (s != controller.mySeat) s
    ];
    final m = opponents.length;

    const seatH = 86.0;
    final seatW = min(w * 0.24, 112.0);

    // 座位中心椭圆：略内缩，让座位框“骑”在桌沿上（参考图样式）
    final A = tableW / 2 - seatW * 0.30;
    final B = tableH / 2 - seatH * 0.30;

    // 对手分布：避开底部（自己是底部），从左下 140° 经顶部 270° 到右下 40°
    List<double> angles;
    if (m == 1) {
      angles = [270];
    } else {
      angles = [
        for (var k = 0; k < m; k++) (140 + k * 260 / (m - 1)) * pi / 180
      ];
    }

    // 座位中心坐标
    final centers = <Offset>[
      for (final rad in angles)
        Offset(w / 2 + A * cos(rad), h / 2 + B * sin(rad)),
    ];

    // ---- 中央公牌尺寸：在桌面内尽可能大，且不被两侧座位挡住 ----
    var cardW = min(min(w * 0.155, tableH * 0.30), 62.0);
    // 垂直空间：底池文字 + 公牌
    cardW = min(cardW, (tableH * 0.62 - 30) / 1.4);
    // 水平：与公牌带发生竖向重叠的座位，让出水平空间
    final cardBandHalf = cardW * 1.4 / 2 + 12;
    var rowHalfMax = tableW / 2 - 14;
    for (final c0 in centers) {
      if ((c0.dy - h / 2).abs() < cardBandHalf + seatH / 2) {
        if (c0.dx < w / 2) {
          rowHalfMax = min(rowHalfMax, w / 2 - c0.dx - seatW / 2 - 8);
        } else {
          rowHalfMax = min(rowHalfMax, c0.dx - seatW / 2 - w / 2 - 8);
        }
      }
    }
    cardW = max(30.0, min(cardW, (rowHalfMax * 2 - 16) / 5));

    final boardRow = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < g.board.length; i++)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 2),
            child: CardView(card: g.board[i], width: cardW),
          ),
      ],
    );

    return Stack(
      children: [
        // 桌面
        Center(
          child: Container(
            width: tableW,
            height: tableH,
            decoration: BoxDecoration(
              borderRadius: tableRim,
              border: Border.all(color: AppTheme.tableRim, width: 8),
              gradient: const RadialGradient(
                colors: [AppTheme.tableGreen, AppTheme.tableGreenDark],
              ),
            ),
          ),
        ),
        // 中央：底池（上）+ 公牌（中）
        Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('底池 ${AppTheme.money(g.potTotal)}',
                  style: const TextStyle(
                      color: AppTheme.gold,
                      fontWeight: FontWeight.bold,
                      fontSize: 17)),
              if (g.board.isNotEmpty) const SizedBox(height: 10),
              if (g.board.isNotEmpty) boardRow,
            ],
          ),
        ),
        // 对手座位
        for (var k = 0; k < m; k++)
          Positioned(
            left: (centers[k].dx - seatW / 2).clamp(2.0, w - seatW - 2).toDouble(),
            top: (centers[k].dy - seatH / 2).clamp(2.0, h - seatH - 2).toDouble(),
            child: SeatView(
              controller: controller,
              seat: opponents[k],
              width: seatW,
            ),
          ),
      ],
    );
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
        (p.revealed); // 对手只有摊牌才亮牌
    final isDealer = g.button == seat && g.handNumber > 0;
    final avatarB64 = controller.avatarsBySeat[seat];

    final Color ring = isToAct
        ? AppTheme.gold
        : p.folded
            ? Colors.white12
            : Colors.white24;

    // 底牌：摊牌亮真牌；持牌未摊显示牌背；未持牌不显示
    final List<Widget> cardRow;
    if (!p.hasCards) {
      cardRow = [];
    } else if (showCards) {
      cardRow = [
        for (final c in p.hole)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 1),
            child: CardView(card: c, width: 22, small: true),
          ),
      ];
    } else {
      cardRow = [
        CardView.back(width: 22, small: true),
        const SizedBox(width: 2),
        CardView.back(width: 22, small: true),
      ];
    }

    final statusText = p.out
        ? '已出局'
        : p.allIn
            ? 'ALL-IN'
            : p.folded
                ? '弃牌'
                : (isToAct ? '思考中…' : '');

    return Opacity(
      opacity: p.folded ? 0.45 : 1,
      child: Container(
        width: width,
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 3),
        decoration: BoxDecoration(
          color: AppTheme.panel.withOpacity(0.92),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: ring, width: isToAct ? 2 : 1),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(p.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                    fontSize: 11, fontWeight: FontWeight.bold)),
            const SizedBox(height: 2),
            Stack(
              clipBehavior: Clip.none,
              children: [
                CircleAvatar(
                  radius: 19,
                  backgroundColor: p.isAI ? Colors.teal : AppTheme.callBlue,
                  backgroundImage: (avatarB64 != null && avatarB64.isNotEmpty)
                      ? MemoryImage(base64Decode(avatarB64))
                      : null,
                  child: (avatarB64 == null || avatarB64.isEmpty)
                      ? Text(p.name.isNotEmpty ? p.name[0] : '?',
                          style: const TextStyle(fontSize: 15))
                      : null,
                ),
                if (isDealer)
                  Positioned(
                    right: -4,
                    bottom: -2,
                    child: Container(
                      padding: const EdgeInsets.all(2),
                      decoration: const BoxDecoration(
                          color: Colors.white, shape: BoxShape.circle),
                      child: const Text('D',
                          style: TextStyle(
                              color: Colors.black87,
                              fontSize: 9,
                              fontWeight: FontWeight.bold)),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 2),
            Text(AppTheme.money(p.chips),
                style: const TextStyle(
                    fontSize: 12,
                    color: AppTheme.gold,
                    fontWeight: FontWeight.bold)),
            if (cardRow.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: cardRow,
                ),
              ),
            if (statusText.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                  decoration: BoxDecoration(
                    color: p.folded ? Colors.black26 : Colors.black45,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(statusText,
                      style: TextStyle(
                          fontSize: 10,
                          color: p.allIn
                              ? AppTheme.allinOrange
                              : p.folded
                                  ? Colors.white38
                                  : Colors.white70)),
                ),
              ),
            if (p.roundBet > 0 && !g.handOver)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                  decoration: BoxDecoration(
                    color: AppTheme.gold.withOpacity(0.18),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: AppTheme.gold, width: 1),
                  ),
                  child: Text('下注 ${p.roundBet}',
                      style: const TextStyle(
                          fontSize: 10, color: AppTheme.gold)),
                ),
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

// ---------------- 自己的信息条（底部：头像 + 昵称筹码 + 大底牌） ----------------

class _HeroStrip extends StatelessWidget {
  final GameController controller;
  const _HeroStrip({required this.controller});

  @override
  Widget build(BuildContext context) {
    final g = controller.g;
    final me = g.players[controller.mySeat];
    final avatarB64 = controller.avatarsBySeat[controller.mySeat] ??
        (controller.myAvatarB64 ?? '');
    final isDealer = g.button == controller.mySeat && g.handNumber > 0;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      color: AppTheme.panel,
      child: Row(
        children: [
          Stack(
            clipBehavior: Clip.none,
            children: [
              CircleAvatar(
                radius: 24,
                backgroundColor: me.isAI ? Colors.teal : AppTheme.callBlue,
                backgroundImage:
                    avatarB64.isNotEmpty ? MemoryImage(base64Decode(avatarB64)) : null,
                child: avatarB64.isEmpty
                    ? Text(me.name.isNotEmpty ? me.name[0] : '?',
                        style: const TextStyle(fontSize: 18))
                    : null,
              ),
              if (isDealer)
                Positioned(
                  right: -4,
                  bottom: -2,
                  child: Container(
                    padding: const EdgeInsets.all(2),
                    decoration: const BoxDecoration(
                        color: Colors.white, shape: BoxShape.circle),
                    child: const Text('D',
                        style: TextStyle(
                            color: Colors.black87,
                            fontSize: 10,
                            fontWeight: FontWeight.bold)),
                  ),
                ),
            ],
          ),
          const SizedBox(width: 10),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(me.name,
                  style: const TextStyle(
                      fontWeight: FontWeight.bold, fontSize: 14)),
              Text('筹码 ${AppTheme.money(me.chips)}',
                  style: const TextStyle(
                      color: AppTheme.gold, fontSize: 13)),
              if (me.out)
                const Text('已出局（观战中）',
                    style: TextStyle(color: Colors.white38, fontSize: 11)),
            ],
          ),
          const Spacer(),
          if (me.hole.isEmpty) ...[
            CardView.back(width: 58),
            const SizedBox(width: 6),
            CardView.back(width: 58),
          ] else
            for (final card in me.hole)
              Padding(
                padding: const EdgeInsets.only(left: 6),
                child: CardView(card: card, width: 58),
              ),
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
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
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
        padding: const EdgeInsets.all(12),
        color: AppTheme.panel,
        child: Center(
            child: Text(waiting,
                style: const TextStyle(color: Colors.white54, fontSize: 14))),
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
            padding: const EdgeInsets.all(8),
            child: Row(
              children: [
                Expanded(
                  child: FilledButton(
                    style: FilledButton.styleFrom(
                        backgroundColor: AppTheme.foldRed,
                        padding: const EdgeInsets.symmetric(vertical: 12)),
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
                        padding: const EdgeInsets.symmetric(vertical: 12)),
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
                        padding: const EdgeInsets.symmetric(vertical: 12)),
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
                        padding: const EdgeInsets.symmetric(vertical: 12)),
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
    final clients = hs.pendingClients.entries.toList();
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
            leading: CircleAvatar(
              backgroundImage: c.myAvatarB64 != null
                  ? MemoryImage(base64Decode(c.myAvatarB64!))
                  : null,
              child: c.myAvatarB64 == null ? const Icon(Icons.person) : null,
            ),
            title: Text('${c.myName}（本机/房主）'),
          ),
          for (final e in clients)
            ListTile(
              leading: CircleAvatar(
                backgroundImage:
                    c.pendingAvatars[e.key] != null
                        ? MemoryImage(base64Decode(c.pendingAvatars[e.key]!))
                        : null,
                child: c.pendingAvatars[e.key] == null
                    ? const Icon(Icons.person_outline)
                    : null,
              ),
              title: Text(e.value),
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
