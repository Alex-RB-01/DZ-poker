"""
德州扑克引擎离线验证（Python 1:1 对照 lib/engine/game.dart + ai.dart）
目的：在本地真实跑通 10 场锦标赛（5人，你+4AI），校验
  1) 牌型评估 / 边池算法正确性
  2) 全程筹码守恒（任何时刻筹码总量不变）
  3) 无崩溃 / 无非法动作 / 淘汰与冠军判定正确
  4) 发牌随机性 & 对各座位公平（无座位被偏爱）
发现的 bug 会改回真实 Dart 引擎。
"""
import random
import math

RANKS = '23456789TJQKA'
SUIT_CHARS = ['♠', '♥', '♦', '♣']


class Card:
    def __init__(self, rank, suit):
        self.rank = rank  # 2..14, A=14
        self.suit = suit  # 0..3

    @classmethod
    def from_code(cls, code):
        return cls(code // 4, code % 4)

    @property
    def code(self):
        return self.rank * 4 + self.suit

    @property
    def is_red(self):
        return self.suit in (1, 2)

    @property
    def text(self):
        return f'{RANKS[self.rank - 2]}{SUIT_CHARS[self.suit]}'

    def __repr__(self):
        return self.text


class Deck:
    def __init__(self, rng):
        self.rng = rng
        self.cards = [Card(r, s) for r in range(2, 15) for s in range(4)]

    def shuffle(self):
        self.rng.shuffle(self.cards)

    def deal(self):
        return self.cards.pop()


# ---------------- 牌型评估 ----------------
def eval5(cs):
    ranks = sorted((c.rank for c in cs), reverse=True)
    is_flush = all(c.suit == cs[0].suit for c in cs)
    counts = {}
    for r in ranks:
        counts[r] = counts.get(r, 0) + 1
    groups = sorted(counts.keys(), key=lambda r: (counts[r], r), reverse=True)
    straight_high = None
    uniq = sorted(counts.keys(), reverse=True)
    if len(uniq) == 5:
        if uniq[0] - uniq[4] == 4:
            straight_high = uniq[0]
        elif uniq[0] == 14 and uniq[1] == 5 and uniq[1] - uniq[4] == 3:
            straight_high = 5  # 轮子 A-2-3-4-5
    if is_flush and straight_high is not None:
        return [8, straight_high]
    if counts[groups[0]] == 4:
        return [7, groups[0], groups[1]]
    if counts[groups[0]] == 3 and counts[groups[1]] == 2:
        return [6, groups[0], groups[1]]
    if is_flush:
        return [5] + ranks
    if straight_high is not None:
        return [4, straight_high]
    if counts[groups[0]] == 3:
        return [3, groups[0], groups[1], groups[2]]
    if counts[groups[0]] == 2 and counts[groups[1]] == 2:
        return [2, groups[0], groups[1], groups[2]]
    if counts[groups[0]] == 2:
        return [1, groups[0], groups[1], groups[2], groups[3]]
    return [0] + ranks


def cmp_eval(a, b):
    for i in range(min(len(a), len(b))):
        if a[i] != b[i]:
            return a[i] - b[i]
    return len(a) - len(b)


def eval7(cards):
    n = len(cards)
    best = []
    for a in range(n - 4):
        for b in range(a + 1, n - 3):
            for c in range(b + 1, n - 2):
                for d in range(c + 1, n - 1):
                    for e in range(d + 1, n):
                        s = eval5([cards[a], cards[b], cards[c], cards[d], cards[e]])
                        if not best or cmp_eval(s, best) > 0:
                            best = s
    return best


def hand_name(s):
    return {8: '同花顺', 7: '四条', 6: '葫芦', 5: '同花', 4: '顺子', 3: '三条',
            2: '两对', 1: '一对', 0: '高牌'}[s[0]]


# ---------------- 玩家 / 配置 ----------------
class PlayerState:
    def __init__(self, seat, name, is_ai=False, chips=0):
        self.seat = seat
        self.name = name
        self.is_ai = is_ai
        self.chips = chips
        self.hole = []
        self.round_bet = 0
        self.total_contributed = 0
        self.folded = False
        self.all_in = False
        self.out = False
        self.acted = False
        self.has_cards = False
        self.revealed = False

    @property
    def in_hand(self):
        return self.has_cards and not self.folded


class PlayerSeed:
    def __init__(self, name, is_ai=False):
        self.name = name
        self.is_ai = is_ai


class BlindLevel:
    def __init__(self, sb, bb):
        self.sb = sb
        self.bb = bb


class GameConfig:
    def __init__(self, starting_chips=5000, levels=None, advance_every=10, advance_mode='hands'):
        self.starting_chips = starting_chips
        self.levels = levels if levels is not None else self.default_levels()
        self.advance_every = advance_every
        self.advance_mode = advance_mode

    @staticmethod
    def default_levels():
        bbs = [10, 20, 30, 50, 75, 100, 150, 200, 300, 500, 750, 1000]
        return [BlindLevel(bb // 2, bb) for bb in bbs]


class PokerAction:
    def __init__(self, type_, amount=0):
        self.type = type_
        self.amount = amount


class Pot:
    def __init__(self, amount, seats):
        self.amount = amount
        self.seats = seats


class HandResult:
    def __init__(self, pots, seat_win, reveal, hand_names):
        self.pots = pots
        self.seat_win = seat_win
        self.reveal = reveal
        self.hand_names = hand_names


class LegalActions:
    def __init__(self, can_check, call_amount, can_raise, min_raise_to, max_raise_to):
        self.can_check = can_check
        self.call_amount = call_amount
        self.can_raise = can_raise
        self.min_raise_to = min_raise_to
        self.max_raise_to = max_raise_to


PREFLOP, FLOP, TURN, RIVER = 0, 1, 2, 3
STREET_NAMES = ['preflop', 'flop', 'turn', 'river']


class GameState:
    def __init__(self, rng, config=None):
        self.rng = rng
        self.config = config or GameConfig()
        self.players = []
        self.button = 0
        self.level = 0
        self.hands_at_level = 0
        self.board = []
        self.deck = None
        self.street = PREFLOP
        self.current_bet = 0
        self.last_full_raise = 0
        self.to_act = -1
        self.sb_seat = -1
        self.bb_seat = -1
        self.hand_number = 0
        self.hand_over = True
        self.game_over = False
        self.log = []
        self.last_result = None

    @property
    def blinds(self):
        return self.config.levels[min(self.level, len(self.config.levels) - 1)]

    @property
    def pot_total(self):
        return sum(p.total_contributed for p in self.players)

    @property
    def live_count(self):
        return sum(1 for p in self.players if not p.out)

    @property
    def in_hand_players(self):
        return [p for p in self.players if p.in_hand]

    def _bl(self):
        return f'{self.blinds.sb}/{self.blinds.bb}'

    def new_game(self, seeds):
        self.players = [PlayerState(i, s.name, is_ai=s.is_ai, chips=self.config.starting_chips)
                        for i, s in enumerate(seeds)]
        self.button = len(self.players) - 1
        self.level = 0
        self.hands_at_level = 0
        self.hand_number = 0
        self.hand_over = True
        self.game_over = False
        self.last_result = None
        self.board = []
        self.log = [f'游戏开始：{len(self.players)} 人，初始筹码 {self.config.starting_chips}']

    def start_hand(self):
        if self.game_over:
            return
        if self.live_count <= 1:
            self.game_over = True
            return
        for p in self.players:
            p.hole = []
            p.round_bet = 0
            p.total_contributed = 0
            p.folded = False
            p.all_in = False
            p.acted = False
            p.has_cards = False
            p.revealed = False
        self.last_result = None
        self.board = []
        self.street = PREFLOP
        self.hand_number += 1
        self.hands_at_level += 1
        if (self.config.advance_mode == 'hands' and self.hands_at_level > self.config.advance_every
                and self.level < len(self.config.levels) - 1):
            self.level += 1
            self.hands_at_level = 1
            self.log.append(f'— 盲注升级：{self._bl()} —')
        # 按钮轮转（跳过已出局）
        while self.players[(self.button + 1) % len(self.players)].out:
            self.button = (self.button + 1) % len(self.players)
        self.button = (self.button + 1) % len(self.players)

        if self.live_count == 2:
            self.sb_seat = self.button
            self.bb_seat = self._next_alive(self.button)
        else:
            self.sb_seat = self._next_alive(self.button)
            self.bb_seat = self._next_alive(self.sb_seat)

        self.deck = Deck(self.rng)
        self.deck.shuffle()
        seat = self.sb_seat
        for _ in range(2):
            seat = self.sb_seat
            for _ in range(self.live_count):
                p = self.players[seat]
                p.hole.append(self.deck.deal())
                p.has_cards = True
                seat = self._next_alive(seat)
        self._post(self.sb_seat, self.blinds.sb, '小盲')
        self._post(self.bb_seat, self.blinds.bb, '大盲')
        self.current_bet = max(self.players[self.sb_seat].round_bet,
                               self.players[self.bb_seat].round_bet)
        self.last_full_raise = max(self.current_bet, self.blinds.bb)
        self.hand_over = False
        self.log.append(f'—— 第 {self.hand_number} 手 —— 盲注 {self._bl()}')
        self.to_act = self._next_actor(self.bb_seat)
        if self.to_act < 0:
            self._end_betting_round()

    def _next_alive(self, seat):
        for i in range(1, len(self.players) + 1):
            s = (seat + i) % len(self.players)
            if not self.players[s].out:
                return s
        return seat

    def _post(self, seat, amount, label):
        p = self.players[seat]
        pay = amount if amount < p.chips else p.chips
        p.chips -= pay
        p.round_bet += pay
        p.total_contributed += pay
        if p.chips == 0:
            p.all_in = True
        self.log.append(f'{p.name} {label} ${pay}{"（全下）" if p.all_in else ""}')

    def _needs_action(self, p):
        return p.has_cards and not p.folded and not p.all_in and (not p.acted or p.round_bet < self.current_bet)

    def _next_actor(self, frm):
        for i in range(1, len(self.players) + 1):
            s = (frm + i) % len(self.players)
            if self._needs_action(self.players[s]):
                return s
        return -1

    def legal_actions(self, seat):
        p = self.players[seat]
        call_amount = self.current_bet - p.round_bet
        if call_amount > p.chips:
            call_amount = p.chips
        max_raise_to = p.round_bet + p.chips
        min_raise_to = (self.current_bet + self.last_full_raise
                        if max_raise_to >= self.current_bet + self.last_full_raise
                        else max_raise_to)
        return LegalActions(
            can_check=self.current_bet == p.round_bet,
            call_amount=call_amount if call_amount >= 0 else 0,
            can_raise=max_raise_to > self.current_bet,
            min_raise_to=min_raise_to,
            max_raise_to=max_raise_to,
        )

    def act(self, seat, a):
        if self.hand_over or self.to_act != seat:
            return False
        p = self.players[seat]
        legal = self.legal_actions(seat)
        if a.type == 'fold':
            p.folded = True
            self.log.append(f'{p.name} 弃牌')
        elif a.type == 'check':
            if not legal.can_check:
                return False
            self.log.append(f'{p.name} 过牌')
        elif a.type == 'call':
            pay = legal.call_amount
            if pay > p.chips:
                return False
            p.chips -= pay
            p.round_bet += pay
            p.total_contributed += pay
            if p.chips == 0:
                p.all_in = True
            self.log.append(f'{p.name} {"过牌" if pay == 0 else "跟注 $" + str(pay)}'
                            f'{"（全下）" if p.all_in else ""}')
        elif a.type == 'raise':
            if not legal.can_raise:
                return False
            to = a.amount
            if to > legal.max_raise_to:
                to = legal.max_raise_to
            if to < legal.min_raise_to and to < legal.max_raise_to:
                to = legal.min_raise_to
            if to <= self.current_bet:
                return False
            raise_size = to - self.current_bet
            pay = to - p.round_bet
            p.chips -= pay
            p.round_bet = to
            p.total_contributed += pay
            if p.chips == 0:
                p.all_in = True
            if raise_size >= self.last_full_raise:
                self.last_full_raise = raise_size
                for q in self.players:
                    if q.seat != seat:
                        q.acted = False
            self.current_bet = to
            self.log.append(f'{p.name} 加注到 ${to}{"（全下）" if p.all_in else ""}')
        else:
            return False
        p.acted = True
        self.to_act = self._next_actor(seat)
        if self.to_act < 0:
            self._end_betting_round()
        return True

    def _end_betting_round(self):
        bets = sorted([p.round_bet for p in self.players if p.has_cards], reverse=True)
        if len(bets) > 1 and bets[0] > bets[1]:
            top = next(p for p in self.players if p.has_cards and p.round_bet == bets[0])
            refund = bets[0] - bets[1]
            top.round_bet -= refund
            top.chips += refund
            top.total_contributed -= refund
            if top.chips > 0:
                top.all_in = False
            self.log.append(f'退回 {top.name} 未被跟注的 ${refund}')
        for p in self.players:
            p.round_bet = 0
            p.acted = False
        self.current_bet = 0
        self.last_full_raise = self.blinds.bb

        live = self.in_hand_players
        if len(live) <= 1:
            self._award_uncontested(live[0] if live else None)
            return
        if self.street == RIVER:
            self.resolve_showdown()
            return
        self._deal_street()
        self.to_act = self._next_actor(self.button)
        if self.to_act < 0:
            self._end_betting_round()

    def _deal_street(self):
        if self.street == PREFLOP:
            self.deck.deal()  # 烧牌
            self.board += [self.deck.deal(), self.deck.deal(), self.deck.deal()]
            self.street = FLOP
            self.log.append('翻牌 ' + ' '.join(c.text for c in self.board))
        elif self.street == FLOP:
            self.deck.deal()
            self.board.append(self.deck.deal())
            self.street = TURN
            self.log.append('转牌 ' + self.board[-1].text)
        elif self.street == TURN:
            self.deck.deal()
            self.board.append(self.deck.deal())
            self.street = RIVER
            self.log.append('河牌 ' + self.board[-1].text)

    def _award_uncontested(self, winner):
        if winner is None:
            return
        total = sum(p.total_contributed for p in self.players)
        winner.chips += total
        self.log.append(f'{winner.name} 收下底池 ${total}')
        self.last_result = HandResult([Pot(total, [winner.seat])],
                                       {winner.seat: total}, {}, {})
        self._finish_hand()

    def build_pots(self):
        levels = sorted({p.total_contributed for p in self.players if p.total_contributed > 0})
        pots = []
        prev = 0
        for lv in levels:
            amt = 0
            for p in self.players:
                hi = p.total_contributed if p.total_contributed < lv else lv
                lo = p.total_contributed if p.total_contributed < prev else prev
                amt += hi - lo
            seats = [p.seat for p in self.in_hand_players if p.total_contributed >= lv]
            if amt > 0:
                pots.append(Pot(amt, seats))
            prev = lv
        return pots

    def _dist_from_button(self, seat):
        d = 0
        s = self.button
        while s != seat and d <= len(self.players):
            s = self._next_alive(s)
            d += 1
        return d

    def resolve_showdown(self):
        pots = self.build_pots()
        seat_win = {}
        reveal = {}
        hand_names = {}
        for p in self.in_hand_players:
            reveal[p.seat] = [c.code for c in p.hole]
            p.revealed = True
            hand_names[p.seat] = hand_name(eval7(p.hole + self.board))
        for pot in pots:
            best_score = []
            winners = []
            for seat in pot.seats:
                p = self.players[seat]
                score = eval7(p.hole + self.board)
                if not winners:
                    winners = [p]
                    best_score = score
                else:
                    c = cmp_eval(score, best_score)
                    if c > 0:
                        winners = [p]
                        best_score = score
                    elif c == 0:
                        winners.append(p)
            if not winners:
                continue
            base = pot.amount // len(winners)
            rem = pot.amount - base * len(winners)
            order = sorted(winners, key=lambda w: self._dist_from_button(w.seat))
            for w in order:
                gain = base
                if rem > 0:
                    gain += 1
                    rem -= 1
                w.chips += gain
                seat_win[w.seat] = seat_win.get(w.seat, 0) + gain
            self.log.append(f'底池 ${pot.amount} → ' +
                            '、'.join(w.name for w in winners) +
                            ('（平分）' if len(winners) > 1 else ''))
        self.last_result = HandResult(pots, seat_win, reveal, hand_names)
        self._finish_hand()

    def _finish_hand(self):
        self.hand_over = True
        self.to_act = -1
        for p in self.players:
            if not p.out and p.chips <= 0:
                p.out = True
                self.log.append(f'{p.name} 筹码输完，出局')
        if self.live_count <= 1:
            self.game_over = True
            champ = next((p for p in self.players if not p.out), self.players[0])
            self.log.append(f'🏆 {champ.name} 赢得整场比赛！')


# ---------------- AI ----------------
class AIPlayer:
    @staticmethod
    def decide(g, rng):
        me = g.players[g.to_act]
        legal = g.legal_actions(me.seat)
        if g.street == PREFLOP:
            equity = AIPlayer._preflop_equity(me.hole, len(g.in_hand_players) - 1)
        else:
            equity = AIPlayer._equity_mc(g, rng, trials=160)
        pot = g.pot_total
        call = legal.call_amount
        pot_odds = call / (pot + call) if (pot + call) > 0 else 0.0
        e = equity + (rng.random() - 0.5) * 0.08

        if call >= me.chips and call > 0:
            if e > 0.58:
                return PokerAction('call')
            if e > pot_odds + 0.08 and call <= pot * 0.35:
                return PokerAction('call')
            return PokerAction('fold')
        if call == 0:
            if legal.can_raise and e > 0.62 and rng.random() < 0.8:
                return AIPlayer._bet(g, legal, e, rng)
            if legal.can_raise and e > 0.5 and rng.random() < 0.25:
                return AIPlayer._bet(g, legal, e, rng)
            if legal.can_raise and e < 0.32 and rng.random() < 0.06:
                return AIPlayer._bet(g, legal, e, rng)
            return PokerAction('check')
        if e > 0.82 and legal.can_raise and rng.random() < 0.7:
            return AIPlayer._bet(g, legal, e, rng)
        if e > pot_odds + 0.03:
            return PokerAction('call')
        if call <= g.blinds.bb and e > 0.3:
            return PokerAction('call')
        if rng.random() < 0.04:
            return PokerAction('call')
        return PokerAction('fold')

    @staticmethod
    def _bet(g, legal, e, rng):
        if e > 0.88 or rng.random() < 0.08:
            to = legal.max_raise_to
        else:
            frac = 0.75 if e > 0.7 else 0.5
            pot_bet = round(g.pot_total * frac)
            to = (g.current_bet + pot_bet if legal.min_raise_to > g.current_bet + pot_bet
                  else g.current_bet + pot_bet)
            if to > legal.max_raise_to:
                to = legal.max_raise_to
        if to <= g.current_bet:
            return PokerAction('call')
        return PokerAction('raise', amount=to)

    @staticmethod
    def _preflop_equity(hole, n_opp):
        if len(hole) < 2:
            return 0.4
        r1 = max(hole[0].rank, hole[1].rank)
        r2 = min(hole[0].rank, hole[1].rank)
        if r1 == r2:
            base = 0.52 + (r1 - 2) * 0.02
        else:
            base = 0.33 + (r1 - 2) * 0.011 + (r2 - 2) * 0.006
            if hole[0].suit == hole[1].suit:
                base += 0.03
            gap = r1 - r2
            if gap == 1:
                base += 0.02
            elif gap == 2:
                base += 0.01
            if r1 == 14 and r2 >= 12:
                base += 0.03
        eq = base - n_opp * 0.11
        return max(0.08, min(0.95, eq))

    @staticmethod
    def _equity_mc(g, rng, trials=160):
        me = g.players[g.to_act]
        used = {c.code for c in me.hole} | {c.code for c in g.board}
        pool = [Card.from_code(code) for code in range(52) if code not in used]
        opp_count = len(g.in_hand_players) - 1
        if opp_count <= 0:
            return 1.0
        win = 0.0
        for _ in range(trials):
            rng.shuffle(pool)
            idx = 0
            opp_holes = [[pool[idx], pool[idx + 1]] for _ in range(opp_count)]
            idx += 2 * opp_count
            full = list(g.board)
            while len(full) < 5:
                full.append(pool[idx])
                idx += 1
            my_score = eval7(me.hole + full)
            result = 1
            for oh in opp_holes:
                c = cmp_eval(my_score, eval7(oh + full))
                if c < 0:
                    result = -1
                    break
                if c == 0:
                    result = 0
            if result > 0:
                win += 1
            elif result == 0:
                win += 0.5
        return win / trials


# ---------------- 验证主程序 ----------------
def check_conservation(g, total):
    chips = sum(p.chips for p in g.players)
    contributed = sum(p.total_contributed for p in g.players)
    if chips + contributed != total:
        return False, (f'筹码不守恒 chips={chips} contributed={contributed} '
                       f'sum={chips + contributed} 期望={total}')
    return True, ''


def dump(g):
    lines = [f'street={STREET_NAMES[g.street]} toAct={g.to_act} currentBet={g.current_bet} '
             f'pot={g.pot_total} level={g.level}']
    for p in g.players:
        lines.append(f'  seat{p.seat} {p.name} chips={p.chips} bet={p.round_bet} '
                     f'contrib={p.total_contributed} '
                     f'{"FOLD" if p.folded else ""}{" ALLIN" if p.all_in else ""}'
                     f'{" OUT" if p.out else ""}'
                     f'{" cards=" + "".join(c.text for c in p.hole) if p.has_cards else ""}')
    lines.append('board=' + ' '.join(c.text for c in g.board))
    return '\n'.join(lines)


def play_tournament(rng, button_counts):
    cfg = GameConfig(starting_chips=1000, advance_every=6, advance_mode='hands')
    g = GameState(rng, cfg)
    g.new_game([PlayerSeed(f'P{i}', is_ai=True) for i in range(5)])
    total = cfg.starting_chips * 5
    hands = 0
    actions = 0
    while not g.game_over:
        if g.hand_over:
            g.start_hand()
            hands += 1
            if hands > 200000:
                return False, -1, hands, '手数超限，疑似死循环'
            button_counts[g.button] += 1
            ok, msg = check_conservation(g, total)
            if not ok:
                return False, -1, hands, msg + '\n' + dump(g)
        act = AIPlayer.decide(g, rng)
        applied = g.act(g.to_act, act)
        if not applied:
            return False, -1, hands, (f'AI 非法动作: {act.type} amount={act.amount} seat={g.to_act}\n'
                                      + dump(g))
        actions += 1
        if actions > 1000000:
            return False, -1, hands, '动作数超限'
        if not g.hand_over:
            ok, msg = check_conservation(g, total)
            if not ok:
                return False, -1, hands, msg + '\n' + dump(g)
    alive = sum(1 for p in g.players if not p.out)
    if alive != 1:
        return False, -1, hands, f'结束应仅1人存活，实际 {alive}'
    if sum(p.chips for p in g.players) != total:
        return False, -1, hands, '终局筹码不守恒'
    winner = next(p.seat for p in g.players if not p.out)
    return True, winner, hands, ''


def deal_fairness(rng):
    n = 5
    hands = 30000
    aa = [0] * n
    pair = [0] * n
    for _ in range(hands):
        d = Deck(rng)
        d.shuffle()
        for s in range(n):
            a = d.deal()
            b = d.deal()
            if a.rank == 14 and b.rank == 14:
                aa[s] += 1
            elif a.rank == b.rank:
                pair[s] += 1
    exp = hands / 221.0
    chi = sum((aa[s] - exp) ** 2 / exp for s in range(n))
    return aa, pair, chi


def assert_evaluator():
    fails = []
    c = lambda r, s: Card(r, s)
    if not (cmp_eval(eval7([c(10, 0), c(11, 0), c(12, 0), c(13, 0), c(14, 0), c(2, 1), c(3, 2)]),
                   eval7([c(14, 0), c(14, 1), c(14, 2), c(14, 3), c(2, 0), c(3, 1), c(4, 2)])) > 0):
        fails.append('同花顺>四条')
    wheel = eval5([c(14, 0), c(2, 1), c(3, 2), c(4, 0), c(5, 1)])
    if wheel[0] != 4 or wheel[1] != 5:
        fails.append('轮子顺')
    if cmp_eval(eval7([c(9, 0), c(9, 1), c(9, 2), c(9, 3), c(2, 0)]),
                eval7([c(5, 0), c(5, 1), c(5, 2), c(8, 0), c(8, 1)])) <= 0:
        fails.append('四条>葫芦')
    if eval5([c(5, 0), c(5, 1), c(5, 2), c(8, 0), c(8, 1)])[0] != 6:
        fails.append('葫芦类别')
    if cmp_eval(eval5([c(14, 0), c(14, 1), c(13, 0), c(13, 1), c(2, 2)]),
                eval5([c(14, 0), c(14, 1), c(13, 0), c(13, 1), c(3, 2)])) >= 0:
        fails.append('两对比踢脚')
    flush = eval5([c(2, 0), c(5, 0), c(7, 0), c(9, 0), c(11, 0)])
    if flush[0] != 5:
        fails.append('同花类别')
    return fails


def main():
    seed = random.getrandbits(64)
    rng = random.Random(seed)
    print('=== 德州扑克引擎验证（Python 1:1 对照 Dart 引擎）===')
    print(f'随机种子: {seed}  （每次运行不同 → 发牌不同）')
    print()

    fails = assert_evaluator()
    print('牌型评估断言:', '✅ 全部通过' if not fails else f'⚠️ 失败: {fails}')
    print()

    aa, pair, chi = deal_fairness(rng)
    exp = 30000 / 221
    print(f'发牌随机性/公平性（30000手×5座位，共{30000 * 5}次发牌）:')
    print(f'  各座位拿到 AA(口袋A)次数: {aa}  (期望≈{exp:.0f})')
    print(f'  各座位拿到口袋对子(非AA)次数: {pair}')
    print(f'  AA 分布卡方值={chi:.2f}  (临界9.49@95%) → '
          f'{"均匀✅ 无座位被偏爱" if chi < 9.49 else "疑似偏差⚠️"}')
    print()

    wins = [0] * 5
    button_counts = [0] * 5
    total_hands = 0
    ok = True
    fatal = ''
    for t in range(1, 11):
        res = play_tournament(rng, button_counts)
        if not res[0]:
            ok = False
            fatal = f'第 {t} 场异常: {res[3]}'
            break
        total_hands += res[2]
        wins[res[1]] += 1
        print(f'  第{t}场结束 → 冠军座位{res[1]}，共 {res[2]} 手')

    print()
    print('—— 汇总 ——')
    print(f'总手数: {total_hands}')
    print(f'各座位夺冠次数(10场): {wins}  (期望≈每人2次)')
    print(f'各座位当“按钮/庄家”次数: {button_counts}  (应大致相等)')
    if ok:
        print('✅ 10 场全部跑通：筹码守恒、无崩溃、无非法动作、淘汰/冠军判定正确')
    else:
        print('❌ 发现 bug：')
        print(fatal)


if __name__ == '__main__':
    main()
