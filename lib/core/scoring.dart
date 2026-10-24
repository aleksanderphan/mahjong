// Singapore / Sear Mahjong scoring engine (pure functions, no Flutter, no network).
// All amounts are integer "units" (chips). Port of legacy_web/js/scoring.js.
import 'dart:math' as math;

const int kPlayers = 4;
const int kMaxTai = 5;

class InstantKind {
  final String label, zh, icon;
  final bool kong, fromDeal;
  const InstantKind(this.label, this.zh, this.icon, {this.kong = false, this.fromDeal = false});
}

const Map<String, InstantKind> instantKinds = {
  'exposedKong': InstantKind('Exposed kong', '明杠 / 碰杠', '🀫', kong: true),
  'concealedKong': InstantKind('Concealed kong', '暗杠', '🀫', kong: true),
  'flowerSet': InstantKind('Complete flower / season set', '一堂花', '🌸'),
  'flowerPair': InstantKind('Matched flower + season pair', '正花正季', '🌼', fromDeal: true),
  'animalPair': InstantKind('Animal pair (cat + mouse or rooster + centipede)', '猫鼠 / 鸡蜈蚣', '🐱', fromDeal: true),
  'animalSet': InstantKind('All four animals', '四动物', '🐓'),
};

const Map<String, (String, String)> baoReasons = {
  'eighthFlower': ('Fed the 8th bonus tile', '打出第八张花'),
  'thirdDragon': ('Discarded the 3rd dragon', '包大三元'),
  'fourthWind': ('Discarded the 4th wind', '包大四喜'),
  'toCap': ('Fed a tile that reaches the Tai cap', '包台 (喂饱满台)'),
  'fullColour': ('Completed an exposed full colour', '包清一色'),
  'finalWall': ('Fresh tile in the final wall', '过水 / 底牌鲜牌点炮'),
  'other': ('Other house rule', ''),
};

/// Default payout amounts (points EACH opponent pays the receiver).
const Map<String, int> defaultPayouts = {
  'exposedKong': 2,
  'concealedKong': 4,
  'flowerSet': 4,
  'flowerPair': 2,
  'animalPair': 2,
  'animalSet': 4,
};

class ScoringError implements Exception {
  final String message;
  ScoringError(this.message);
  @override
  String toString() => message;
}

int clampTai(num? tai, [int cap = kMaxTai]) {
  final n = (tai ?? 0).floor();
  return math.max(0, math.min(cap, n));
}

/// Base points = 2^Tai, Tai clamped to [0, cap].
int basePoints(num? tai, [int cap = kMaxTai]) => 1 << clampTai(tai, cap);

List<int> _zeros() => List<int>.filled(kPlayers, 0);

void _assertSeat(int? i, String name) {
  if (i == null || i < 0 || i >= kPlayers) throw ScoringError('Invalid $name');
}

/// Win payout.
/// - Discard win: shooter pays 2 x base, the other two pay 1 x base each.
/// - Self-draw: all three pay 2 x base.
/// - Pay-all (包赔): [baoBy] pays [baoMultiplier] x base alone.
List<int> winDeltas({
  required int winner,
  int? shooter,
  bool selfDraw = false,
  required num tai,
  int cap = kMaxTai,
  int? baoBy,
  int baoMultiplier = 6,
}) {
  _assertSeat(winner, 'winner');
  final base = basePoints(tai, cap);
  final d = _zeros();
  if (baoBy != null) {
    _assertSeat(baoBy, 'responsible player');
    if (baoBy == winner) throw ScoringError('The responsible player cannot be the winner');
    final amt = math.max(1, baoMultiplier) * base;
    d[baoBy] -= amt;
    d[winner] += amt;
    return d;
  }
  if (selfDraw) {
    for (var i = 0; i < kPlayers; i++) {
      if (i != winner) {
        d[i] -= 2 * base;
        d[winner] += 2 * base;
      }
    }
  } else {
    _assertSeat(shooter, 'shooter');
    if (shooter == winner) throw ScoringError('Shooter cannot be the winner');
    for (var i = 0; i < kPlayers; i++) {
      if (i == winner) continue;
      final pay = i == shooter ? 2 * base : base;
      d[i] -= pay;
      d[winner] += pay;
    }
  }
  return d;
}

/// Correct who discarded the winning tile on a plain discard win.
List<int> reassignShooter(List<int> deltas, int winner, int oldShooter, int newShooter) {
  _assertSeat(winner, 'winner');
  _assertSeat(oldShooter, 'old discarder');
  _assertSeat(newShooter, 'new discarder');
  if (newShooter == winner) throw ScoringError('The discarder cannot be the winner');
  final base = deltas[winner] ~/ 4;
  var plain = deltas[winner] % 4 == 0;
  for (var i = 0; i < kPlayers; i++) {
    if (i == winner) continue;
    if (deltas[i] != (i == oldShooter ? -2 * base : -base)) plain = false;
  }
  if (oldShooter == winner || base <= 0 || !plain) {
    throw ScoringError('This entry is not a plain discard win, so the discarder cannot be changed here');
  }
  final d = [...deltas];
  if (newShooter != oldShooter) {
    d[oldShooter] += base;
    d[newShooter] -= base;
  }
  return d;
}

/// Instant payout: every opponent pays amounts[kind] to the receiver
/// (x2 when held from the deal, for kinds that allow it).
List<int> instantDeltas({
  required int player,
  required String kind,
  bool fromDeal = false,
  Map<String, int> amounts = defaultPayouts,
}) {
  _assertSeat(player, 'player');
  final k = instantKinds[kind];
  if (k == null) throw ScoringError('Unknown payout type');
  final amt = (amounts[kind] ?? defaultPayouts[kind]!) * (fromDeal && k.fromDeal ? 2 : 1);
  if (amt < 0) throw ScoringError('Invalid payout amount');
  final d = _zeros();
  for (var i = 0; i < kPlayers; i++) {
    if (i != player) {
      d[i] -= amt;
      d[player] += amt;
    }
  }
  return d;
}

/// Manual multi-player adjustment: any integer deltas that sum to zero.
List<int> manualDeltas(List<num> deltas) {
  if (deltas.length != kPlayers) throw ScoringError('Need 4 values');
  final d = deltas.map((x) => x.truncate()).toList();
  if (d.every((x) => x == 0)) throw ScoringError('Nothing to adjust');
  final s = sum(d);
  if (s != 0) throw ScoringError('Adjustments must add up to 0 (now ${s > 0 ? '+' : ''}$s)');
  return d;
}

int sum(Iterable<int> xs) => xs.fold(0, (a, b) => a + b);

/// Minimal view of an event for auditing, implemented by GameEvent.
abstract class LedgerEntry {
  String? get id;
  String get type;
  bool get voided;
  List<int> get deltas;
}

class AuditProblem {
  final String? id;
  final String reason;
  const AuditProblem(this.id, this.reason);
}

class AuditResult {
  final List<int> balances;
  final int total, active, voided, hands;
  final bool balanced;
  final List<AuditProblem> problems;
  const AuditResult(this.balances, this.total, this.balanced, this.problems, this.active, this.voided, this.hands);
}

/// Zero-sum audit over all events (voided ones are skipped).
AuditResult audit(Iterable<LedgerEntry> events) {
  final balances = _zeros();
  final problems = <AuditProblem>[];
  var active = 0, voided = 0, hands = 0;
  for (final ev in events) {
    if (ev.voided) {
      voided++;
      continue;
    }
    final d = ev.deltas;
    if (d.length != kPlayers) {
      problems.add(AuditProblem(ev.id, 'Malformed deltas'));
      continue;
    }
    final s = sum(d);
    if (s != 0) {
      problems.add(AuditProblem(ev.id, 'Event sums to $s, not 0'));
      continue;
    }
    active++;
    if (ev.type == 'win' || ev.type == 'draw') hands++;
    for (var i = 0; i < kPlayers; i++) {
      balances[i] += d[i];
    }
  }
  final total = sum(balances);
  return AuditResult(balances, total, total == 0 && problems.isEmpty, problems, active, voided, hands);
}

class Transfer {
  final int from, to, units;
  const Transfer(this.from, this.to, this.units);
}

/// Greedy list of transfers to settle balances.
List<Transfer> settlement(List<int> balances) {
  final cred = <List<int>>[], debt = <List<int>>[];
  for (var i = 0; i < balances.length; i++) {
    if (balances[i] > 0) {
      cred.add([i, balances[i]]);
    } else if (balances[i] < 0) {
      debt.add([i, -balances[i]]);
    }
  }
  cred.sort((a, b) => b[1] - a[1]);
  debt.sort((a, b) => b[1] - a[1]);
  final out = <Transfer>[];
  var ci = 0, di = 0;
  while (ci < cred.length && di < debt.length) {
    final amt = math.min(cred[ci][1], debt[di][1]);
    out.add(Transfer(debt[di][0], cred[ci][0], amt));
    cred[ci][1] -= amt;
    debt[di][1] -= amt;
    if (cred[ci][1] == 0) ci++;
    if (debt[di][1] == 0) di++;
  }
  return out;
}
