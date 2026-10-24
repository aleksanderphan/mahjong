// House rules, the Tai catalogue and dealer tracking. Port of legacy_web/js/rules.js.
import 'scoring.dart';

const Map<String, String> categories = {
  'base': 'Base hands',
  'sets': 'Sets & winds',
  'bonus': 'Bonus & flowers',
  'special': 'Special wins',
  'limit': 'Fixed & limit hands',
};

/// pattern (pick one) | variant | colour (pick one) | count (0..max) | flag (yes/no) | limit (always = cap)
enum TaiInput { pattern, variant, colour, count, flag, limit }

class TaiItem {
  final String id, cat, name, zh, desc;
  final TaiInput input;
  final int def, max;
  const TaiItem(this.id, this.cat, this.input, this.name, this.zh, this.def, this.desc, {this.max = 0});
}

const List<TaiItem> taiCatalog = [
  TaiItem('chicken', 'base', TaiInput.pattern, 'Chicken Hand', '鸡糊', 0, 'No scoring pattern of any kind. Not a valid win when minimum Tai is 1 or more.'),
  TaiItem('allChow', 'base', TaiInput.pattern, 'All Chow', '吃吃胡 (顺子胡)', 1, 'Every set is a chow. The pair may be any tile except dragons or scoring winds. Flowers allowed.'),
  TaiItem('pingHu', 'base', TaiInput.pattern, 'Ping Hu (Zero Flowers)', '平胡 (无花)', 4, 'Same as All Chow with no bonus tiles at all (no flowers, seasons or animals). With any bonus tile it scores as All Chow + bonuses.'),
  TaiItem('allPong', 'base', TaiInput.pattern, 'All Pong', '对对胡 (碰碰胡)', 2, 'Every set is a pong or kong, plus one pair.'),
  TaiItem('sevenPairs', 'base', TaiInput.pattern, 'Seven Pairs', '七对子', 2, 'Seven pairs, won off a discard (2 Tai; 4 Tai when self-drawn). Stacks with half / full colour.'),
  TaiItem('sevenPairsSelf', 'base', TaiInput.variant, 'Seven Pairs — self-draw', '七对子 自摸', 4, 'Seven pairs won by self-draw.'),
  TaiItem('halfColour', 'base', TaiInput.colour, 'Half Color (Hun Yi Se)', '混一色', 2, 'One numbered suit together with honour tiles (winds and/or dragons).'),
  TaiItem('fullColour', 'base', TaiInput.colour, 'Full Color (Qing Yi Se)', '清一色', 4, 'One numbered suit only. No honours.'),
  TaiItem('halfTerminals', 'base', TaiInput.pattern, 'Half Terminals', '混么九', 4, 'Only terminal number tiles (1 and 9) and honour tiles. No middle (2-8) tiles.'),
  TaiItem('mixedOrphans', 'base', TaiInput.pattern, 'Mixed Orphans', '混全带幺', 2, 'Every set and the pair has a terminal (1 or 9) or is an honour (winds / dragons). Runs must be 1-2-3 or 7-8-9.'),
  TaiItem('pureOrphans', 'base', TaiInput.pattern, 'Pure Orphans', '纯全带幺', 4, 'Every set and the pair has a terminal (1 or 9), with no honours. Runs must be 1-2-3 or 7-8-9.'),
  TaiItem('pureStraight', 'sets', TaiInput.flag, 'Pure Straight', '一条龙', 2, 'Three chows 1-2-3, 4-5-6 and 7-8-9 of the same suit. Added on top of the other Tai.'),
  TaiItem('concealed', 'sets', TaiInput.flag, 'Concealed Hand', '门清', 1, 'Hand stays completely concealed until the win: no claimed chow, pong or exposed kong.'),
  TaiItem('kong', 'sets', TaiInput.count, 'Kong / Gang (4 of a kind)', '杠牌 (明杠/暗杠)', 1, 'Each exposed or concealed kong in the winning hand.', max: 4),
  TaiItem('dragonPung', 'sets', TaiInput.count, 'Dragon Pong / Kong', '红中 / 发财 / 白板 刻', 1, 'Each pong or kong of red 中, green 發 or white 白 dragons.', max: 3),
  TaiItem('seatWind', 'sets', TaiInput.flag, 'Seat Wind Pong / Kong', '门风刻 (本命风)', 1, 'Pong or kong of your own seat wind.'),
  TaiItem('roundWind', 'sets', TaiInput.flag, 'Prevailing Wind Pong / Kong', '圈风刻 (场风)', 1, 'Pong or kong of the round (prevailing) wind.'),
  TaiItem('smallWinds', 'sets', TaiInput.flag, 'Small Four Winds', '小四喜', 2, 'Pongs/kongs of three winds plus the fourth wind as your pair. Added on top of any seat/round wind pong.'),
  TaiItem('smallDragons', 'sets', TaiInput.flag, 'Small Three Dragons', '小三元', 1, 'Two dragon pongs + a dragon pair. Added on top of the dragon pongs.'),
  TaiItem('flower', 'bonus', TaiInput.flag, 'Matched Seat Flower', '正花 (本命花)', 1, 'Your seat’s flower: 1 East 梅, 2 South 兰, 3 West 菊, 4 North 竹.'),
  TaiItem('season', 'bonus', TaiInput.flag, 'Matched Seat Season', '正季 (本命季)', 1, 'Your seat’s season: 1 East 春, 2 South 夏, 3 West 秋, 4 North 冬.'),
  TaiItem('flowerSet', 'bonus', TaiInput.count, 'Complete 4-Flower or 4-Season Set', '一堂花 (一台四花)', 1, 'All four flowers or all four seasons (extra Tai).', max: 2),
  TaiItem('animal', 'bonus', TaiInput.count, 'Animal Bonus Tile', '动物花牌', 1, 'Each animal: cat, mouse, cockerel, centipede.', max: 4),
  TaiItem('animalPair', 'bonus', TaiInput.count, 'Matched Animal Pair', '一对动物 (猫鼠 / 鸡蜈蚣)', 2, 'Cat + mouse, or cockerel + centipede.', max: 2),
  TaiItem('kongWin', 'special', TaiInput.flag, 'Win on Kong Replacement', '杠上开花', 1, 'Winning with the replacement tile drawn after a kong.'),
  TaiItem('lastTile', 'special', TaiInput.flag, 'Win on the Last Tile', '海底捞月', 1, 'Winning on the very last tile of the wall.'),
  TaiItem('robKong', 'special', TaiInput.flag, 'Robbing the Kong', '抢杠', 1, 'Winning with the tile another player adds to a pong to make a kong.'),
  TaiItem('bigDragons', 'limit', TaiInput.limit, 'Big Three Dragons', '大三元', 7, 'Pong or kong of all three dragons (red, green, white).'),
  TaiItem('thirteen', 'limit', TaiInput.limit, 'Thirteen Wonders', '十三幺', 8, 'One of every terminal (1 & 9 of each suit) and every honour, plus any matching pair.'),
  TaiItem('allTerminals', 'limit', TaiInput.limit, 'All Terminals', '清么九', 9, 'Only 1 and 9 number tiles — no middle tiles, no honours.'),
  TaiItem('sevenFlowers', 'limit', TaiInput.limit, 'Seven Flowers', '七星伴月', 10, 'Seven of the eight bonus tiles, won by self-draw only.'),
  TaiItem('eightFlowers', 'limit', TaiInput.limit, 'Eight Flowers', '八仙过海', 12, 'All eight bonus tiles — wins immediately, no sets needed.'),
  TaiItem('bigWinds', 'limit', TaiInput.limit, 'Big Four Winds', '大四喜', 12, 'Pong or kong of all four winds plus a pair.'),
  TaiItem('nineGates', 'limit', TaiInput.limit, 'Nine Gates', '九莲宝灯', 10, 'Concealed 1112345678999 of one suit, waiting on any tile of that suit.'),
  TaiItem('allHonours', 'limit', TaiInput.limit, 'All Honours', '字一色', 5, 'Only winds and dragons — no number tiles at all.'),
  TaiItem('allKongs', 'limit', TaiInput.limit, 'All Kongs', '十八罗汉', 5, 'Four kongs plus a pair (18 tiles).'),
  TaiItem('fourConcealed', 'limit', TaiInput.limit, 'Four Concealed Pongs', '四暗刻', 5, 'Four pongs/kongs all from the wall, won by self-draw.'),
  TaiItem('pureGreen', 'limit', TaiInput.limit, 'Pure Green', '绿一色', 5, 'Only green tiles: bamboo 2, 3, 4, 6, 8 and green dragon 發.'),
  TaiItem('heavenly', 'limit', TaiInput.limit, 'Heavenly Hand', '天胡', 5, 'Dealer wins on the initial 14-tile deal.'),
  TaiItem('earthly', 'limit', TaiInput.limit, 'Earthly Hand', '地胡', 5, 'Non-dealer wins on the dealer’s very first discard.'),
  TaiItem('human', 'limit', TaiInput.limit, 'Human Hand', '人胡', 5, 'Early-game win before the player’s first normal draw.'),
];

final Map<String, TaiItem> taiById = {for (final x in taiCatalog) x.id: x};

const Map<String, String> scoreLabels = {'pts': 'PTS (Points)', 'chips': 'Chips (筹码)', 'poin': 'Poin'};
const List<int> capOptions = [3, 4, 5, 6, 7, 8, 10, 13]; // 13 = no cap
const int noCap = 13;

const String defaultAiModel = 'gemini-3.8-flash';
const Map<String, String> aiModels = {
  'gemini-3.8-flash': 'Gemini 3.8 Flash (best, default)',
  'gemini-3.5-flash': 'Gemini 3.5 Flash',
  'gemini-3.5-flash-lite': 'Gemini 3.5 Flash-Lite (fastest)',
};

const List<String> windNames = ['East', 'South', 'West', 'North'];
const List<String> windZh = ['東', '南', '西', '北'];

int _int(dynamic v, int d, int lo, int hi) {
  final n = v is num ? v.floor() : int.tryParse('$v');
  if (n == null) return d;
  return n < lo ? lo : (n > hi ? hi : n);
}

/// Where a continued table starts: dealer seat, round wind and dealer streak.
class Resume {
  final int dealer, round, streak;
  const Resume(this.dealer, this.round, this.streak);
  Map<String, dynamic> toJson() => {'dealer': dealer, 'round': round, 'streak': streak};
  factory Resume.fromJson(Map<String, dynamic> j) => Resume(_int(j['dealer'], 0, 0, 3), _int(j['round'], 0, 0, 3), _int(j['streak'], 0, 0, 99));
}

/// Validated house rules (also the per-table settings snapshot).
class Rules {
  final int minTai, taiCap, finalWallStacks, baoMultiplier;
  final bool winCircumstance, autoDealer;
  final String doubleWind; // '1x' | '2x'
  final String drawRule; // 'stay' | 'rotate'
  final String scoreLabel;
  final Map<String, int> payouts; // exposedKong, concealedKong, flowerSet, flowerPair, animalPair, animalSet
  final Map<String, int> tai; // overrides of the catalogue defaults
  final Resume? resume;
  final int leaderboardResetAt;
  final bool aiScan;
  final bool animals; // set includes the 4 animal bonus tiles (Singapore / Malaysia sets); off for a Chinese set
  final String aiModel;

  const Rules({
    this.minTai = 1,
    this.taiCap = kMaxTai,
    this.finalWallStacks = 12,
    this.baoMultiplier = 6,
    this.winCircumstance = true,
    this.autoDealer = true,
    this.doubleWind = '2x',
    this.drawRule = 'stay',
    this.scoreLabel = 'pts',
    this.payouts = defaultPayouts,
    this.tai = const {},
    this.resume,
    this.leaderboardResetAt = 0,
    this.aiScan = true,
    this.animals = false,
    this.aiModel = defaultAiModel,
  });

  /// Validate/merge saved JSON over the defaults (mergeRules in the web app).
  factory Rules.fromJson(Map<String, dynamic>? j) {
    j ??= const {};
    final cap = _int(j['taiCap'], kMaxTai, 1, 13);
    final min = _int(j['minTai'], 1, 0, 5);
    final payouts = {
      for (final k in defaultPayouts.keys) k: _int(j[k], defaultPayouts[k]!, 0, 99),
    };
    final tai = <String, int>{};
    final raw = j['tai'];
    if (raw is Map) {
      raw.forEach((k, v) {
        final item = taiById[k];
        if (item == null) return;
        final n = _int(v, item.def, 0, 13);
        if (n != item.def) tai['$k'] = n;
      });
    }
    return Rules(
      minTai: min > cap ? cap : min,
      taiCap: cap,
      finalWallStacks: _int(j['finalWallStacks'], 12, 0, 40),
      baoMultiplier: _int(j['baoMultiplier'], 6, 1, 12),
      winCircumstance: j['winCircumstance'] != false,
      autoDealer: j['autoDealer'] != false,
      doubleWind: j['doubleWind'] == '1x' ? '1x' : '2x',
      drawRule: j['drawRule'] == 'rotate' ? 'rotate' : 'stay',
      scoreLabel: scoreLabels.containsKey(j['scoreLabel']) ? j['scoreLabel'] as String : 'pts',
      payouts: payouts,
      tai: tai,
      resume: j['resume'] is Map ? Resume.fromJson(Map<String, dynamic>.from(j['resume'] as Map)) : null,
      leaderboardResetAt: _int(j['leaderboardResetAt'], 0, 0, 1 << 52),
      aiScan: j['aiScan'] != false,
      animals: j['animals'] == true,
      aiModel: j['aiModel'] is String && RegExp(r'^[a-z0-9.\-]{3,60}$').hasMatch(j['aiModel'] as String) ? j['aiModel'] as String : defaultAiModel,
    );
  }

  Map<String, dynamic> toJson() => {
        'minTai': minTai,
        'taiCap': taiCap,
        'finalWallStacks': finalWallStacks,
        'baoMultiplier': baoMultiplier,
        'winCircumstance': winCircumstance,
        'autoDealer': autoDealer,
        'doubleWind': doubleWind,
        'drawRule': drawRule,
        'scoreLabel': scoreLabel,
        ...payouts,
        'tai': tai,
        if (resume != null) 'resume': resume!.toJson(),
        'leaderboardResetAt': leaderboardResetAt,
        'aiScan': aiScan,
        'animals': animals,
        'aiModel': aiModel,
      };

  Rules copyWith({
    int? minTai,
    int? taiCap,
    int? finalWallStacks,
    int? baoMultiplier,
    bool? winCircumstance,
    bool? autoDealer,
    String? doubleWind,
    String? drawRule,
    String? scoreLabel,
    Map<String, int>? payouts,
    Map<String, int>? tai,
    Resume? resume,
    int? leaderboardResetAt,
    bool? aiScan,
    bool? animals,
    String? aiModel,
  }) =>
      Rules.fromJson({
        ...toJson(),
        'minTai': ?minTai,
        'taiCap': ?taiCap,
        'finalWallStacks': ?finalWallStacks,
        'baoMultiplier': ?baoMultiplier,
        'winCircumstance': ?winCircumstance,
        'autoDealer': ?autoDealer,
        'doubleWind': ?doubleWind,
        'drawRule': ?drawRule,
        'scoreLabel': ?scoreLabel,
        ...?payouts,
        'tai': ?tai,
        if (resume != null) 'resume': resume.toJson(),
        'leaderboardResetAt': ?leaderboardResetAt,
        'aiScan': ?aiScan,
        'aiModel': ?aiModel,
        'animals': ?animals,
      });

  /// Kinds of instant payout available with this set (animal payouts only when the set has animals).
  Iterable<String> get payoutKinds => instantKinds.keys.where((k) => animals || !k.startsWith('animal'));

  /// Catalogue items that apply to this set.
  bool usesPattern(String id) => animals || (id != 'animal' && id != 'animalPair');

  /// Actual Tai value of a catalogue item (effective Tai = min(value, cap)).
  int taiValue(String id) => tai[id] ?? taiById[id]?.def ?? 0;
}

class DealerState {
  final bool enabled;
  final int dealer, round, hand, streak;
  const DealerState(this.enabled, this.dealer, this.round, this.hand, this.streak);
}

/// Minimal view of an event needed for dealer tracking.
abstract class DealerEvent {
  bool get voided;
  String get type;
  int? get winner;
}

/// Dealer / round tracking derived from the event log. Starts at seat 0 (East), round wind East,
/// or at settings.resume when the table continues an earlier game.
DealerState dealerState(Iterable<DealerEvent> events, Rules settings) {
  final rs = settings.resume;
  var dealer = rs?.dealer ?? 0, round = rs?.round ?? 0, hand = 1, streak = rs?.streak ?? 0;
  if (!settings.autoDealer) return DealerState(false, dealer, round, hand, streak);
  void rotate() {
    dealer = (dealer + 1) % 4;
    streak = 0;
    if (dealer == 0) round = (round + 1) % 4;
  }

  for (final ev in events) {
    if (ev.voided) continue;
    if (ev.type == 'win') {
      hand++;
      if (ev.winner == dealer) {
        streak++;
      } else {
        rotate();
      }
    } else if (ev.type == 'draw') {
      hand++;
      if (settings.drawRule == 'rotate') {
        rotate();
      } else {
        streak++;
      }
    }
  }
  return DealerState(true, dealer, round, hand, streak);
}
