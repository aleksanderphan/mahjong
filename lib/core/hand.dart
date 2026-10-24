// Hand evaluation: turns a pattern selection into Tai, effective Tai and base points.
// Rule (Singapore / SEA "single primary hand"): at most ONE base hand OR ONE fixed/limit hand.
// Suits (half / full colour) stack with a base hand (incl. Seven Pairs) but not with a limit hand.
// Additive bonuses (flowers, animals, dragons, winds, concealed, kong…) combo with anything.
import 'models.dart';
import 'rules.dart';
import 'scoring.dart';

final List<TaiItem> baseHands = taiCatalog.where((x) => x.input == TaiInput.pattern).toList();
final List<TaiItem> suitItems = taiCatalog.where((x) => x.input == TaiInput.colour).toList();
final List<TaiItem> limitItems = taiCatalog.where((x) => x.input == TaiInput.limit).toList();
final List<TaiItem> bonusItems = taiCatalog.where((x) => x.input == TaiInput.flag || x.input == TaiInput.count).toList();

class Selection {
  String? base, suit, limit;
  final Map<String, bool> flags;
  final Map<String, int> counts;
  Selection({this.base, this.suit, this.limit, Map<String, bool>? flags, Map<String, int>? counts})
      : flags = flags ?? {},
        counts = counts ?? {};

  Selection copy() => Selection(base: base, suit: suit, limit: limit, flags: {...flags}, counts: {...counts});

  /// Selection -> list of patterns for storage.
  List<PatternUse> toList() => [
        if (base != null) PatternUse(base!),
        if (suit != null) PatternUse(suit!),
        if (limit != null) PatternUse(limit!),
        for (final e in flags.entries) if (e.value) PatternUse(e.key),
        for (final e in counts.entries) if (e.value > 0) PatternUse(e.key, e.value),
      ];

  /// Stored list -> selection.
  factory Selection.fromList(Iterable<PatternUse> list) {
    final s = Selection();
    for (final p in list) {
      final x = taiById[p.id];
      if (x == null) continue;
      switch (x.input) {
        case TaiInput.pattern:
        case TaiInput.variant:
          s.base = x.id == 'sevenPairsSelf' ? 'sevenPairs' : x.id;
        case TaiInput.colour:
          s.suit = x.id;
        case TaiInput.limit:
          s.limit = x.id;
        case TaiInput.count:
          s.counts[x.id] = p.n;
        case TaiInput.flag:
          s.flags[x.id] = true;
      }
    }
    return s;
  }
}

class HandItem {
  final String id, name, zh;
  final int n, tai;
  const HandItem(this.id, this.name, this.zh, this.n, this.tai);
}

class HandResult {
  final List<HandItem> items;
  final int actual, effective, cap, base;
  final List<String> errors;
  const HandResult(this.items, this.actual, this.effective, this.cap, this.base, this.errors);
  bool get valid => errors.isEmpty && items.isNotEmpty;
}

/// Evaluate a hand. [selfDraw] makes Seven Pairs use its self-draw value; [sameWind] means seat wind == prevailing wind,
/// so a single wind pong counts 1x or 2x (rules.doubleWind).
HandResult evaluateHand(Selection sel, Rules rules, {bool selfDraw = false, bool sameWind = false}) {
  final cap = rules.taiCap;
  final items = <HandItem>[];
  final errors = <String>[];
  void push(String id, [int n = 1]) {
    final x = taiById[id];
    if (x == null) return;
    items.add(HandItem(id, x.name, x.zh, n, rules.taiValue(id) * n));
  }

  if (sel.base != null && sel.limit != null) errors.add('Choose one base hand OR one limit hand, not both.');
  if (sel.suit != null && sel.limit != null) errors.add('Suit bonuses only stack with a base hand, not with a limit hand.');
  if (sel.limit != null) push(sel.limit!);
  if (sel.base != null) push(sel.base == 'sevenPairs' && selfDraw ? 'sevenPairsSelf' : sel.base!);
  if (sel.suit != null) push(sel.suit!);
  for (final x in bonusItems) {
    if (x.cat == 'special' && !rules.winCircumstance) continue;
    if (!rules.usesPattern(x.id)) continue;
    if (x.input == TaiInput.flag && sel.flags[x.id] == true) {
      if (x.id == 'roundWind' && sameWind && sel.flags['seatWind'] == true && rules.doubleWind != '2x') continue; // same tile counted once
      push(x.id);
    }
    final c = sel.counts[x.id] ?? 0;
    if (x.input == TaiInput.count && c > 0) push(x.id, c < x.max ? c : x.max);
  }
  if (sel.base == 'pingHu' &&
      (sel.flags['flower'] == true || sel.flags['season'] == true || (sel.counts['animal'] ?? 0) > 0 || (sel.counts['animalPair'] ?? 0) > 0 || (sel.counts['flowerSet'] ?? 0) > 0)) {
    errors.add('Ping Hu must have zero flowers/animals — choose All Chow instead.');
  }
  final actual = items.fold<int>(0, (s, i) => s + i.tai);
  if (actual < rules.minTai) {
    errors.add(actual == 0 ? 'Chicken hand (0 Tai) is not a valid win.' : 'Below the minimum of ${rules.minTai} Tai — not a valid win.');
  }
  return HandResult(items, actual, clampTai(actual, cap), cap, basePoints(actual, cap), errors);
}

/// Short text like "All Pong (对对胡) + Dragon Pong ×2".
String describeItems(Iterable<HandItem> items, {bool withZh = true}) =>
    items.map((i) => '${i.name}${withZh && i.zh.isNotEmpty ? ' (${i.zh})' : ''}${i.n > 1 ? ' ×${i.n}' : ''}').join(' + ');

String patternText(Iterable<PatternUse> list, {bool zh = true}) => list.map((p) {
      final x = taiById[p.id];
      if (x == null) return p.id;
      return '${x.name}${zh ? ' (${x.zh})' : ''}${p.n > 1 ? ' ×${p.n}' : ''}';
    }).join(' + ');
