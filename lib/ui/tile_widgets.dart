// Drawn mahjong tiles and the sample winning hands used by the scoring guide.
// Tile codes: m1-9 characters 万, p1-9 dots 筒, s1-9 bamboo 索, w1-4 winds 東南西北, d1 中, d2 發, d3 白.
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

const _honour = {'w1': '東', 'w2': '南', 'w3': '西', 'w4': '北', 'd1': '中', 'd2': '發', 'd3': '白'};
const _flowerCh = ['梅', '兰', '菊', '竹'];
const _seasonCh = ['春', '夏', '秋', '冬'];
const _animalEmoji = {'cat': '🐱', 'mouse': '🐭', 'rooster': '🐓', 'centipede': '🐛'};

Color _suitColor(String t) => switch (t[0]) {
      'm' => const Color(0xFFC62828),
      'p' => const Color(0xFF1565C0),
      's' => const Color(0xFF2E7D32),
      _ => t == 'd1' ? const Color(0xFFC62828) : (t == 'd2' ? const Color(0xFF2E7D32) : const Color(0xFF263238)),
    };

const _numerals = ['一', '二', '三', '四', '五', '六', '七', '八', '九'];
const _glyphFont = ['Noto Sans SC', 'Microsoft YaHei', 'PingFang SC', 'SimHei', 'sans-serif'];

Widget _svg(String name) => SvgPicture.asset('assets/tiles/$name.svg', fit: BoxFit.fill);

/// A tile: base.svg for the body, then the artwork in assets/tiles (dots, bamboo, frames) or a drawn character.
class MjTile extends StatelessWidget {
  const MjTile(this.code, {super.key, this.size = 1});

  /// The back of a tile (concealed kong).
  const MjTile.faceDown({super.key, this.size = 1}) : code = '';
  final String code;
  final double size;

  Widget _glyph(String ch, Color c, double fs, {Alignment at = Alignment.center}) =>
      Align(alignment: at, child: Text(ch, style: TextStyle(fontSize: fs * size, fontWeight: FontWeight.bold, color: c, height: 1, fontFamilyFallback: _glyphFont)));

  @override
  Widget build(BuildContext context) {
    if (code.isEmpty) {
      return Container(width: 30 * size, height: 42 * size, margin: EdgeInsets.all(1.2 * size), child: SvgPicture.asset('assets/tiles/back.svg', fit: BoxFit.fill));
    }
    final suit = code[0];
    final n = int.tryParse(code.substring(1)) ?? 0;
    final c = _suitColor(code);
    final Widget face;
    if (suit == 'p' || suit == 's') {
      face = Padding(padding: EdgeInsets.all(3 * size), child: _svg(code));
    } else if (suit == 'm') {
      face = Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        Text(_numerals[n - 1], style: TextStyle(fontSize: 17 * size, fontWeight: FontWeight.bold, color: const Color(0xFF1A237E), height: 1.05, fontFamilyFallback: _glyphFont)),
        Text('万', style: TextStyle(fontSize: 15 * size, fontWeight: FontWeight.bold, color: const Color(0xFFC62828), height: 1.05, fontFamilyFallback: _glyphFont)),
      ]);
    } else if (code == 'd3') {
      face = _svg('d3');
    } else {
      face = _glyph(_honour[code]!, c, 22);
    }
    return Container(
      width: 30 * size,
      height: 42 * size,
      margin: EdgeInsets.all(1.2 * size),
      child: Stack(fit: StackFit.expand, children: [_svg('base'), face]),
    );
  }
}

/// Flower / season tile: blossom or season-disc artwork plus its name and seat number.
class BonusTile extends StatelessWidget {
  const BonusTile(this.ch, this.n, {super.key, this.season = false});
  final String ch;
  final int n;
  final bool season;

  @override
  Widget build(BuildContext context) => Container(
        width: 30,
        height: 42,
        margin: const EdgeInsets.all(1.2),
        child: Stack(fit: StackFit.expand, children: [
          _svg('base'),
          Padding(padding: const EdgeInsets.all(2), child: _svg('${season ? 'k' : 'f'}$n')),
          Align(
            alignment: const Alignment(0, 0.72),
            child: Text('$ch$n', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFFAD1457), height: 1, fontFamilyFallback: _glyphFont)),
          ),
        ]),
      );
}

/// One sample hand. sets are (type, tile): chow = lowest tile of the run; pong / kong = the tile.
class Sample {
  final List<(String, String)> sets;
  final String? pair, note;
  final List<String> pairs; // seven pairs
  final List<String> thirteen; // thirteen wonders: tiles shown as is
  final List<int> flowers, seasons;
  final List<String> animals;
  const Sample({this.sets = const [], this.pair, this.pairs = const [], this.thirteen = const [], this.flowers = const [], this.seasons = const [], this.animals = const [], this.note});
}

const _plain = [('chow', 'm2'), ('chow', 'm5'), ('pong', 'p3'), ('chow', 's6')];
const _runs = [('chow', 'm2'), ('chow', 'm5'), ('chow', 'p3'), ('chow', 's6')];
List<(String, String)> _runsAnd((String, String) set) => [set, ('chow', 'm2'), ('chow', 'p4'), ('chow', 's6')];
const _sevenPairs = ['m2', 'm5', 'p3', 'p7', 's4', 's8', 'w2'];
const _thirteenTiles = ['m1', 'm9', 'p1', 'p9', 's1', 's9', 'w1', 'w2', 'w3', 'w4', 'd1', 'd2', 'd3', 'm1'];

final Map<String, Sample> samples = {
  'chicken': const Sample(sets: _plain, pair: 'p8', note: 'No pattern and no bonus tile: 0 Tai, not a winning hand.'),
  'allChow': const Sample(sets: _runs, pair: 'p8', seasons: [2], note: 'Four runs and a plain pair. Any bonus tile makes it All Chow (1 Tai) instead of Ping Hu.'),
  'pingHu': const Sample(sets: _runs, pair: 'p8'),
  'allPong': const Sample(sets: [('pong', 'm3'), ('pong', 'p7'), ('pong', 's5'), ('pong', 'm8')], pair: 'p2'),
  'sevenPairs': const Sample(pairs: _sevenPairs, note: '2 Tai off a discard; 4 Tai when self-drawn.'),
  'halfColour': const Sample(sets: [('chow', 's2'), ('chow', 's5'), ('pong', 's8'), ('pong', 'w4')], pair: 's3', note: 'One suit (bamboo) plus a wind.'),
  'fullColour': const Sample(sets: [('chow', 'p2'), ('chow', 'p3'), ('pong', 'p6'), ('pong', 'p8')], pair: 'p5', note: 'One suit only (dots), no honours.'),
  'halfTerminals': const Sample(sets: [('pong', 'm1'), ('pong', 'm9'), ('pong', 's1'), ('pong', 'w3')], pair: 'p1'),
  'mixedOrphans': const Sample(sets: [('chow', 'm1'), ('chow', 'p7'), ('pong', 's9'), ('pong', 'w4')], pair: 'm9'),
  'pureOrphans': const Sample(sets: [('chow', 'm1'), ('chow', 'm7'), ('chow', 'p7'), ('pong', 's9')], pair: 'p1'),
  'pureStraight': const Sample(sets: [('chow', 'm1'), ('chow', 'm4'), ('chow', 'm7'), ('pong', 'p5')], pair: 's2'),
  'concealed': const Sample(sets: _runs, pair: 'p8', note: 'No claimed chow, pong or exposed kong.'),
  'kong': const Sample(sets: [('kong', 'p5'), ('chow', 'm2'), ('chow', 'm5'), ('chow', 's6')], pair: 'p8'),
  'dragonPung': Sample(sets: _runsAnd(('pong', 'd1')), pair: 's2'),
  'seatWind': Sample(sets: _runsAnd(('pong', 'w1')), pair: 's2', note: 'You sit East, so a pong of East 東 scores.'),
  'roundWind': Sample(sets: _runsAnd(('pong', 'w2')), pair: 's2', note: 'The round is South, so a pong of South 南 scores.'),
  'smallWinds': const Sample(sets: [('pong', 'w1'), ('pong', 'w2'), ('pong', 'w3'), ('chow', 'm2')], pair: 'w4'),
  'smallDragons': const Sample(sets: [('pong', 'd1'), ('pong', 'd2'), ('chow', 'm2'), ('chow', 'p5')], pair: 'd3'),
  'flower': const Sample(sets: _plain, pair: 'p8', flowers: [1], note: 'You sit East (1), so Plum 梅 is your flower.'),
  'season': const Sample(sets: _plain, pair: 'p8', seasons: [1], note: 'You sit East (1), so Spring 春 is your season.'),
  'flowerSet': const Sample(sets: _plain, pair: 'p8', flowers: [1, 2, 3, 4]),
  'animal': const Sample(sets: _plain, pair: 'p8', animals: ['cat']),
  'animalPair': const Sample(sets: _plain, pair: 'p8', animals: ['cat', 'mouse']),
  'bigDragons': const Sample(sets: [('pong', 'd1'), ('pong', 'd2'), ('pong', 'd3'), ('chow', 'm2')], pair: 'p5'),
  'thirteen': const Sample(thirteen: _thirteenTiles),
  'allTerminals': const Sample(sets: [('pong', 'm1'), ('pong', 'm9'), ('pong', 'p1'), ('pong', 's9')], pair: 'p9'),
  'sevenFlowers': const Sample(sets: _plain, pair: 'p8', flowers: [1, 2, 3, 4], seasons: [1, 2, 3], note: 'Won by self-draw.'),
  'eightFlowers': const Sample(flowers: [1, 2, 3, 4], seasons: [1, 2, 3, 4], note: 'Wins immediately, no sets needed.'),
  'bigWinds': const Sample(sets: [('pong', 'w1'), ('pong', 'w2'), ('pong', 'w3'), ('pong', 'w4')], pair: 'm5'),
  'nineGates': const Sample(sets: [('pong', 'm1'), ('chow', 'm2'), ('chow', 'm5'), ('pong', 'm9')], pair: 'm8', note: 'Concealed 1112345678999 plus any tile of the suit.'),
  'allHonours': const Sample(sets: [('pong', 'w1'), ('pong', 'w2'), ('pong', 'd1'), ('pong', 'd2')], pair: 'd3'),
  'allKongs': const Sample(sets: [('kong', 'm1'), ('kong', 'p2'), ('kong', 's3'), ('kong', 'm9')], pair: 'p5'),
  'fourConcealed': const Sample(sets: [('pong', 'm1'), ('pong', 'p2'), ('pong', 's3'), ('pong', 'm9')], pair: 'p5', note: 'All from the wall, won by self-draw.'),
  'pureGreen': const Sample(sets: [('chow', 's2'), ('pong', 's6'), ('pong', 's8'), ('pong', 'd2')], pair: 's4'),
};

List<String> _expand((String, String) set) {
  final (type, t) = set;
  if (type == 'chow') {
    final n = int.parse(t.substring(1));
    return [for (var i = 0; i < 3; i++) '${t[0]}${n + i}'];
  }
  return List.filled(type == 'kong' ? 4 : 3, t);
}

/// Picture of a sample hand, or an empty box when a pattern has none.
class SampleHand extends StatelessWidget {
  const SampleHand(this.id, {super.key, this.size = 0.8});
  final String id;
  final double size;

  @override
  Widget build(BuildContext context) {
    final s = samples[id];
    if (s == null) return const SizedBox.shrink();
    final groups = <List<String>>[
      for (final set in s.sets) _expand(set),
      if (s.pair != null) [s.pair!, s.pair!],
      for (final p in s.pairs) [p, p],
      if (s.thirteen.isNotEmpty) s.thirteen,
    ];
    final bonus = <Widget>[
      for (final n in s.flowers) BonusTile(_flowerCh[n - 1], n),
      for (final n in s.seasons) BonusTile(_seasonCh[n - 1], n, season: true),
      for (final a in s.animals) Padding(padding: const EdgeInsets.all(2), child: Text(_animalEmoji[a]!, style: const TextStyle(fontSize: 26))),
    ];
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      if (groups.isNotEmpty)
        Wrap(runSpacing: 4, children: [
          for (final g in groups) Padding(padding: const EdgeInsets.only(right: 8), child: Row(mainAxisSize: MainAxisSize.min, children: [for (final t in g) MjTile(t, size: size)])),
        ]),
      if (bonus.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 4), child: Wrap(crossAxisAlignment: WrapCrossAlignment.center, children: bonus)),
      if (s.note != null) Padding(padding: const EdgeInsets.only(top: 4), child: Text(s.note!, style: Theme.of(context).textTheme.bodySmall)),
    ]);
  }
}
