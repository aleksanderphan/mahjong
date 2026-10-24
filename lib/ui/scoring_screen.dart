import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';
import '../core/rules.dart';
import '../core/scoring.dart';
import 'theme.dart';
import 'tile_widgets.dart';

/// Scoring guide: Tai → points chart, who-pays diagrams for each way of winning, and the Tai catalogue with sample hands.
class ScoringScreen extends StatefulWidget {
  const ScoringScreen({super.key});
  @override
  State<ScoringScreen> createState() => _ScoringScreenState();
}

class _ScoringScreenState extends State<ScoringScreen> {
  double _tai = 3;
  String _filter = '';

  @override
  Widget build(BuildContext context) {
    final r = context.watch<AppState>().house;
    final tai = math.min(_tai.round(), r.taiCap);
    return Scaffold(
      appBar: AppBar(title: const Text('Scoring guide 台数')),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        _section(context, '1 · Tai → base points', 'Base = 2^Tai, capped at ${r.taiCap} Tai (${basePoints(r.taiCap, r.taiCap)} points). Minimum to win: ${r.minTai} Tai.'),
        _TaiChart(rules: r, selected: tai),
        const SizedBox(height: 16),
        _section(context, '2 · Who pays whom', 'Pick a hand value. The winner sits East; in the discard and pay-all examples South is the player at fault.'),
        Row(children: [
          const Text('Tai'),
          Expanded(
            child: Slider(
              value: math.min(_tai, r.taiCap.toDouble()),
              min: 0,
              max: math.min(r.taiCap, 8).toDouble(),
              divisions: math.min(r.taiCap, 8),
              label: '$tai',
              onChanged: (v) => setState(() => _tai = v),
            ),
          ),
          Text('$tai  →  base ${basePoints(tai, r.taiCap)}', style: const TextStyle(fontWeight: FontWeight.bold)),
        ]),
        _PayCard(
          title: 'Self-draw 自摸',
          subtitle: 'All three opponents pay 2 × base.',
          deltas: winDeltas(winner: 0, selfDraw: true, tai: tai, cap: r.taiCap),
          unit: r.scoreLabel,
        ),
        _PayCard(
          title: 'Discard win 点炮',
          subtitle: 'The discarder pays 2 × base, the other two pay 1 × base.',
          deltas: winDeltas(winner: 0, shooter: 1, tai: tai, cap: r.taiCap),
          unit: r.scoreLabel,
        ),
        _PayCard(
          title: 'Pay-all 包赔',
          subtitle: 'The responsible player alone pays ${r.baoMultiplier} × base. Triggers: 8th flower, 3rd dragon, 4th wind, feeding a capped hand, completing an exposed full colour, a fresh tile in the final wall.',
          deltas: winDeltas(winner: 0, shooter: 1, tai: tai, cap: r.taiCap, baoBy: 1, baoMultiplier: r.baoMultiplier),
          unit: r.scoreLabel,
        ),
        const SizedBox(height: 8),
        _section(context, '3 · Instant payouts', 'Paid at once by each of the three opponents, outside the hand.'),
        for (final e in instantKinds.entries.where((e) => r.payoutKinds.contains(e.key)))
          ListTile(
            dense: true,
            leading: SizedBox(width: 64, child: Align(alignment: Alignment.centerLeft, child: _payoutIcon(e.key))),
            title: Text('${e.value.label}  ${e.value.zh}'),
            subtitle: Text(e.value.fromDeal ? 'Doubled when held from the deal' : ''),
            trailing: Text('${r.payouts[e.key]} each\n+${r.payouts[e.key]! * 3}', textAlign: TextAlign.end),
          ),
        const SizedBox(height: 8),
        _section(context, '4 · Patterns', 'One base hand OR one limit hand; suits stack with a base hand; bonuses stack with anything. Tap a pattern for a sample hand.'),
        TextField(
          decoration: const InputDecoration(prefixIcon: Icon(Icons.search), labelText: 'Filter patterns', isDense: true),
          onChanged: (v) => setState(() => _filter = v.trim().toLowerCase()),
        ),
        for (final cat in categories.entries) ..._category(context, cat.key, cat.value, r),
        const SizedBox(height: 24),
      ]),
    );
  }

  /// Tile pictures for the instant-payout rows (drawn from assets/tiles).
  Widget _payoutIcon(String kind) => switch (kind) {
        'exposedKong' => Row(mainAxisSize: MainAxisSize.min, children: [for (var i = 0; i < 2; i++) const MjTile('d1', size: 0.7)]),
        'concealedKong' => Row(mainAxisSize: MainAxisSize.min, children: [for (var i = 0; i < 2; i++) const MjTile.faceDown(size: 0.7)]),
        'flowerSet' => Row(mainAxisSize: MainAxisSize.min, children: [for (var i = 1; i <= 2; i++) BonusTile('梅', i)]),
        'flowerPair' => const Row(mainAxisSize: MainAxisSize.min, children: [BonusTile('梅', 1), BonusTile('春', 1, season: true)]),
        'animalPair' => const Text('🐱🐭', style: TextStyle(fontSize: 22)),
        _ => const Text('🐓🐛', style: TextStyle(fontSize: 22)),
      };

  Widget _section(BuildContext context, String title, String sub) => Padding(
        padding: const EdgeInsets.only(top: 8, bottom: 8),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, style: Theme.of(context).textTheme.titleLarge),
          Text(sub, style: Theme.of(context).textTheme.bodySmall),
        ]),
      );

  List<Widget> _category(BuildContext context, String cat, String label, Rules r) {
    final items = taiCatalog.where((x) => x.cat == cat && x.input != TaiInput.variant && r.usesPattern(x.id)).where((x) => _filter.isEmpty || '${x.name} ${x.zh} ${x.desc}'.toLowerCase().contains(_filter)).toList();
    if (items.isEmpty) return const [];
    return [
      Padding(padding: const EdgeInsets.only(top: 12, bottom: 2), child: Text(label, style: Theme.of(context).textTheme.titleMedium)),
      for (final x in items)
        Card(
          child: ExpansionTile(
            shape: const Border(),
            title: Text('${x.name}  ${x.zh}'),
            trailing: _TaiBadge(tai: r.taiValue(x.id), cap: r.taiCap, limit: x.input == TaiInput.limit),
            childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            expandedCrossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(x.desc),
              if (x.input == TaiInput.count) Text('Up to ${x.max}, ${r.taiValue(x.id)} Tai each.', style: Theme.of(context).textTheme.bodySmall),
              if (x.id == 'sevenPairs') Text('Self-drawn: ${r.taiValue('sevenPairsSelf')} Tai.', style: Theme.of(context).textTheme.bodySmall),
              if (samples.containsKey(x.id)) ...[const SizedBox(height: 8), SampleHand(x.id)],
            ],
          ),
        ),
    ];
  }
}

class _TaiBadge extends StatelessWidget {
  const _TaiBadge({required this.tai, required this.cap, required this.limit});
  final int tai, cap;
  final bool limit;

  @override
  Widget build(BuildContext context) {
    final capped = tai > cap;
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(color: limit ? cs.tertiaryContainer : cs.primaryContainer, borderRadius: BorderRadius.circular(20)),
      child: Text(capped ? '$tai → $cap Tai' : '$tai Tai', style: const TextStyle(fontWeight: FontWeight.bold)),
    );
  }
}

/// Bars of base points for each Tai value up to the cap (or 8 when there is no cap).
class _TaiChart extends StatelessWidget {
  const _TaiChart({required this.rules, required this.selected});
  final Rules rules;
  final int selected;

  @override
  Widget build(BuildContext context) {
    final top = math.min(rules.taiCap, 8);
    final maxPts = basePoints(top, rules.taiCap);
    final cs = Theme.of(context).colorScheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(children: [
          for (var t = 0; t <= top; t++)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Row(children: [
                SizedBox(width: 44, child: Text('$t Tai', style: TextStyle(fontWeight: t == selected ? FontWeight.bold : null))),
                Expanded(
                  child: LayoutBuilder(
                    builder: (_, c) => Stack(children: [
                      Container(height: 22, width: c.maxWidth, decoration: BoxDecoration(color: cs.surfaceContainerHighest, borderRadius: BorderRadius.circular(4))),
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        height: 22,
                        width: math.max(6, c.maxWidth * basePoints(t, rules.taiCap) / maxPts),
                        decoration: BoxDecoration(color: t == selected ? cs.primary : cs.primary.withValues(alpha: 0.45), borderRadius: BorderRadius.circular(4)),
                      ),
                    ]),
                  ),
                ),
                SizedBox(width: 56, child: Text('${basePoints(t, rules.taiCap)}${t == rules.taiCap ? ' 满' : ''}', textAlign: TextAlign.end, style: TextStyle(fontWeight: t == selected ? FontWeight.bold : null))),
              ]),
            ),
          if (rules.taiCap > top) Padding(padding: const EdgeInsets.only(top: 4), child: Text('… up to the cap of ${rules.taiCap} Tai (${basePoints(rules.taiCap, rules.taiCap)})', style: Theme.of(context).textTheme.bodySmall)),
        ]),
      ),
    );
  }
}

/// Diverging bars: red to the left for what each seat pays, green to the right for what the winner collects.
class _PayCard extends StatelessWidget {
  const _PayCard({required this.title, required this.subtitle, required this.deltas, required this.unit});
  final String title, subtitle, unit;
  final List<int> deltas;

  @override
  Widget build(BuildContext context) {
    final maxAbs = deltas.map((d) => d.abs()).reduce(math.max).clamp(1, 1 << 30);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, style: Theme.of(context).textTheme.titleMedium),
          Text(subtitle, style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 8),
          for (var i = 0; i < 4; i++)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Row(children: [
                SizedBox(width: 56, child: Text('${windZh[i]} ${windNames[i]}', style: const TextStyle(fontSize: 12))),
                Expanded(
                  child: Row(children: [
                    Expanded(child: Align(alignment: Alignment.centerRight, child: _bar(deltas[i] < 0 ? -deltas[i] / maxAbs : 0, Colors.red.shade400))),
                    Container(width: 1, height: 22, color: Theme.of(context).dividerColor),
                    Expanded(child: Align(alignment: Alignment.centerLeft, child: _bar(deltas[i] > 0 ? deltas[i] / maxAbs : 0, Colors.green.shade500))),
                  ]),
                ),
                SizedBox(width: 64, child: Text('${sign(deltas[i])} $unit', textAlign: TextAlign.end, style: TextStyle(fontWeight: FontWeight.bold, color: deltaColor(context, deltas[i])))),
              ]),
            ),
        ]),
      ),
    );
  }

  Widget _bar(double frac, Color c) => FractionallySizedBox(widthFactor: frac, child: Container(height: 18, decoration: BoxDecoration(color: c, borderRadius: BorderRadius.circular(3))));
}
