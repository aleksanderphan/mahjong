// Human-readable list of what changed between two sets of house rules (used for change notifications).
import 'rules.dart';
import 'scoring.dart';

class RuleChange {
  final int at;
  final String byName, summary;
  const RuleChange(this.at, this.byName, this.summary);

  Map<String, dynamic> toJson() => {'at': at, 'byName': byName, 'summary': summary};
  factory RuleChange.fromJson(Map<String, dynamic> j) =>
      RuleChange((j['at'] as num?)?.toInt() ?? 0, '${j['byName'] ?? 'Someone'}', '${j['summary'] ?? ''}');
}

const _labels = {
  'minTai': 'Minimum Tai',
  'taiCap': 'Tai cap',
  'winCircumstance': 'Special-win Tai',
  'doubleWind': 'Seat = round wind',
  'autoDealer': 'Track dealer',
  'drawRule': 'On a draw',
  'scoreLabel': 'Score label',
  'baoMultiplier': 'Pay-all multiplier',
  'finalWallStacks': 'Final-wall stacks',
  'aiScan': 'AI hand scan',
  'animals': 'Set has animal tiles',
  'aiModel': 'AI model',
};

/// e.g. ['Tai cap 5 → 8', 'All Pong 2 → 3 Tai'].
List<String> rulesDiff(Rules before, Rules after) {
  final out = <String>[];
  final a = before.toJson(), b = after.toJson();
  for (final e in _labels.entries) {
    if ('${a[e.key]}' != '${b[e.key]}') out.add('${e.value} ${a[e.key]} → ${b[e.key]}');
  }
  for (final k in defaultPayouts.keys) {
    if (a[k] != b[k]) out.add('${instantKinds[k]!.label} ${a[k]} → ${b[k]}');
  }
  for (final x in taiCatalog) {
    if (before.taiValue(x.id) != after.taiValue(x.id)) out.add('${x.name} ${before.taiValue(x.id)} → ${after.taiValue(x.id)} Tai');
  }
  return out;
}
