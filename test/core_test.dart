// Ports of legacy_web/tests/{scoring,rules}.test.mjs plus hand, recap, stats and continuation checks.
import 'package:flutter_test/flutter_test.dart';
import 'package:mahjong_sg/core/continuation.dart';
import 'package:mahjong_sg/core/hand.dart';
import 'package:mahjong_sg/core/models.dart';
import 'package:mahjong_sg/core/recap.dart';
import 'package:mahjong_sg/core/rule_diff.dart';
import 'package:mahjong_sg/core/rules.dart';
import 'package:mahjong_sg/core/scan.dart';
import 'package:mahjong_sg/core/scoring.dart';
import 'package:mahjong_sg/core/stats.dart';

GameEvent win(int winner, {int? shooter, bool selfDraw = false, int tai = 2, int? baoBy, bool voided = false, int at = 1}) {
  final d = winDeltas(winner: winner, shooter: shooter, selfDraw: selfDraw, tai: tai, baoBy: baoBy);
  return GameEvent(id: 'e$at$winner', type: 'win', deltas: d, voided: voided, createdAt: at, data: {
    'winner': winner,
    'shooter': ?shooter,
    'selfDraw': selfDraw,
    'tai': tai,
    'baoBy': ?baoBy,
  });
}

GameEvent draw() => const GameEvent(type: 'draw', deltas: [0, 0, 0, 0], createdAt: 1);

Room room({String code = 'A', List<String> players = const ['Ann', 'Bo', 'Cy', 'Di'], String status = 'completed', int createdAt = 100}) =>
    Room(code: code, name: 'T', players: players, status: status, createdAt: createdAt);

void main() {
  scanTests();
  group('scoring', () {
    test('base points 2^Tai capped at 5', () {
      expect([0, 1, 2, 3, 4, 5, 6, 10].map(basePoints), [1, 2, 4, 8, 16, 32, 32, 32]);
    });
    test('discard win: shooter 2x, others 1x', () {
      expect(winDeltas(winner: 0, shooter: 2, tai: 3), [32, -8, -16, -8]);
    });
    test('self-draw: all pay 2x', () {
      expect(winDeltas(winner: 1, selfDraw: true, tai: 2), [-8, 24, -8, -8]);
    });
    test('configurable cap', () {
      expect(basePoints(7, 8), 128);
      expect(basePoints(9, 3), 8);
      expect(winDeltas(winner: 0, shooter: 1, tai: 6, cap: 6), [256, -128, -64, -64]);
    });
    test('shooter cannot be winner', () {
      expect(() => winDeltas(winner: 1, shooter: 1, tai: 1), throwsA(isA<ScoringError>()));
    });
    test('instant payouts', () {
      expect(instantDeltas(player: 0, kind: 'exposedKong'), [6, -2, -2, -2]);
      expect(instantDeltas(player: 1, kind: 'concealedKong'), [-4, 12, -4, -4]);
      expect(instantDeltas(player: 3, kind: 'flowerPair', amounts: {...defaultPayouts, 'flowerPair': 3}), [-3, -3, -3, 9]);
      expect(instantDeltas(player: 3, kind: 'flowerPair', fromDeal: true), [-4, -4, -4, 12]);
      expect(() => instantDeltas(player: 0, kind: 'bite'), throwsA(isA<ScoringError>()));
    });
    test('pay-all: responsible player pays 6x base alone', () {
      expect(winDeltas(winner: 0, shooter: 2, tai: 5, baoBy: 2), [192, 0, -192, 0]);
      expect(winDeltas(winner: 1, selfDraw: true, tai: 3, baoBy: 3), [0, 48, 0, -48]);
      expect(() => winDeltas(winner: 1, selfDraw: true, tai: 3, baoBy: 1), throwsA(isA<ScoringError>()));
    });
    test('manual adjustment must be zero-sum', () {
      expect(manualDeltas([5, -5, 0, 0]), [5, -5, 0, 0]);
      expect(() => manualDeltas([5, -4, 0, 0]), throwsA(isA<ScoringError>()));
      expect(() => manualDeltas([0, 0, 0, 0]), throwsA(isA<ScoringError>()));
    });
    test('change who discarded equals recording it correctly', () {
      for (var w = 0; w < 4; w++) {
        for (var o = 0; o < 4; o++) {
          for (var n = 0; n < 4; n++) {
            for (var tai = 1; tai <= 7; tai++) {
              if (o == w || n == w) continue;
              final fixed = reassignShooter(winDeltas(winner: w, shooter: o, tai: tai), w, o, n);
              expect(fixed, winDeltas(winner: w, shooter: n, tai: tai));
              expect(sum(fixed), 0);
            }
          }
        }
      }
    });
    test('change who discarded: only plain discard wins', () {
      expect(() => reassignShooter(winDeltas(winner: 1, selfDraw: true, tai: 3), 1, 0, 2), throwsA(isA<ScoringError>()));
      expect(() => reassignShooter(winDeltas(winner: 0, shooter: 2, tai: 3, baoBy: 2), 0, 2, 1), throwsA(isA<ScoringError>()));
      expect(() => reassignShooter([32, -8, -16, -8], 0, 3, 1), throwsA(isA<ScoringError>()));
    });
    test('every generated event is zero-sum', () {
      for (var k = 0; k < 2000; k++) {
        final w = k % 4, s = (w + 1 + (k % 3)) % 4;
        expect(sum(winDeltas(winner: w, shooter: s, tai: k % 7)), 0);
        expect(sum(winDeltas(winner: w, selfDraw: true, tai: k % 7)), 0);
      }
    });
    test('audit detects tampering and ignores voided', () {
      final evs = [
        win(0, shooter: 1, tai: 1),
        GameEvent(id: 'b', type: 'instant', deltas: instantDeltas(player: 2, kind: 'concealedKong'), createdAt: 2),
        const GameEvent(id: 'c', type: 'win', deltas: [100, 0, 0, 0], voided: true, createdAt: 3),
      ];
      final r = audit(evs);
      expect([r.balanced, r.total, r.hands, r.voided], [true, 0, 1, 1]);
      final bad = audit([...evs, const GameEvent(id: 'd', type: 'win', deltas: [5, 0, 0, 0], createdAt: 4)]);
      expect(bad.balanced, false);
      expect(bad.problems.first.id, 'd');
    });
    test('settlement clears balances', () {
      final bal = [37, -12, 5, -30];
      final after = [...bal];
      final tx = settlement(bal);
      for (final x in tx) {
        after[x.from] += x.units;
        after[x.to] -= x.units;
      }
      expect(after, [0, 0, 0, 0]);
      expect(tx.length <= 3, true);
    });
  });

  group('rules', () {
    test('validation clamps and drops junk', () {
      final r = Rules.fromJson({'minTai': 9, 'taiCap': 3, 'doubleWind': 'x', 'tai': {'allPong': 3, 'pingHu': 4, 'bogus': 5, 'bigDragons': 2}});
      expect([r.taiCap, r.minTai, r.doubleWind], [3, 3, '2x']);
      expect(r.tai, {'allPong': 3, 'bigDragons': 2});
      expect([r.taiValue('allPong'), r.taiValue('fullColour'), r.taiValue('bigDragons')], [3, 4, 2]);
    });
    test('house defaults (Mahjong Scoring ver1.2)', () {
      final r = Rules.fromJson({});
      expect([r.minTai, r.taiCap, r.winCircumstance, r.doubleWind, r.scoreLabel, r.autoDealer, r.drawRule, r.finalWallStacks], [1, 5, true, '2x', 'pts', true, 'stay', 12]);
      expect(['chicken', 'allChow', 'allPong', 'halfColour', 'halfTerminals', 'pingHu', 'fullColour', 'smallDragons', 'sevenPairs', 'sevenPairsSelf', 'mixedOrphans', 'pureOrphans'].map(r.taiValue),
          [0, 1, 2, 2, 4, 4, 4, 1, 2, 4, 2, 4]);
      expect(['bigDragons', 'thirteen', 'allTerminals', 'sevenFlowers', 'eightFlowers', 'bigWinds', 'nineGates', 'heavenly', 'earthly', 'human'].map(r.taiValue),
          [7, 8, 9, 10, 12, 12, 10, 5, 5, 5]);
    });
    test('JSON round trip keeps the rules', () {
      final r = Rules.fromJson({'taiCap': 8, 'tai': {'allPong': 3}, 'resume': {'dealer': 2, 'round': 1, 'streak': 1}});
      final back = Rules.fromJson(r.toJson());
      expect(back.toJson(), r.toJson());
    });
    test('copyWith keeps every setting it is given (scan, model, animals)', () {
      final r = const Rules().copyWith(aiScan: false, aiModel: 'gemini-3.5-flash', animals: true, taiCap: 8);
      expect([r.aiScan, r.aiModel, r.animals, r.taiCap], [false, 'gemini-3.5-flash', true, 8]);
      expect(const Rules().animals, false); // Chinese set by default
    });
    test('animals off: animal Tai and payouts are ignored and hidden', () {
      final s = Selection(base: 'allChow', counts: {'animal': 2, 'animalPair': 1});
      expect(evaluateHand(s, const Rules()).actual, 1);
      expect(evaluateHand(s, const Rules(animals: true)).actual, 1 + 2 + 2);
      expect(const Rules().payoutKinds, isNot(contains('animalSet')));
      expect(const Rules(animals: true).payoutKinds, contains('animalPair'));
      expect(buildScanPrompt(const Rules(), const ScanContext()), isNot(contains('- animal:')));
      expect(buildScanPrompt(const Rules(animals: true), const ScanContext()), contains('- animal:'));
    });
    test('dealer stays on dealer win, rotates otherwise, round advances', () {
      var d = dealerState([win(0, selfDraw: true), win(0, selfDraw: true)], const Rules());
      expect([d.dealer, d.streak, d.hand, d.round], [0, 2, 3, 0]);
      d = dealerState([win(2, shooter: 0), win(3, shooter: 0), win(2, shooter: 0), win(0, shooter: 1)], const Rules());
      expect([d.dealer, d.round], [3, 0]);
      d = dealerState([win(1, shooter: 0), win(2, shooter: 0), win(3, shooter: 0), win(0, shooter: 1)], const Rules());
      expect([d.dealer, d.round], [0, 1]);
    });
    test('a continued table starts where the last one stopped', () {
      const resume = Resume(2, 1, 1);
      var d = dealerState([], const Rules(resume: resume));
      expect([d.dealer, d.round, d.streak], [2, 1, 1]);
      d = dealerState([win(2, shooter: 0)], const Rules(resume: resume));
      expect([d.dealer, d.round, d.streak], [2, 1, 2]);
      d = dealerState([win(0, shooter: 1)], const Rules(resume: Resume(3, 1, 0)));
      expect([d.dealer, d.round, d.streak], [0, 2, 0]);
      expect(dealerState([win(1, shooter: 0)], const Rules(resume: resume, autoDealer: false)).enabled, false);
    });
    test('draw rule, voided and disabled', () {
      expect(dealerState([draw()], const Rules(drawRule: 'stay')).dealer, 0);
      expect(dealerState([draw()], const Rules(drawRule: 'rotate')).dealer, 1);
      expect(dealerState([win(1, shooter: 0, voided: true)], const Rules()).dealer, 0);
    });
  });

  group('hand', () {
    const rules = Rules();
    test('single primary hand rule', () {
      final r = evaluateHand(Selection(base: 'allPong', limit: 'bigDragons'), rules);
      expect(r.valid, false);
    });
    test('all pong + dragon pong x2 + half colour = 2 + 2 + 2', () {
      final s = Selection(base: 'allPong', suit: 'halfColour', counts: {'dragonPung': 2});
      final r = evaluateHand(s, rules);
      expect([r.actual, r.effective, r.base, r.valid], [6, 5, 32, true]);
    });
    test('seven pairs self-draw is 4 Tai', () {
      expect(evaluateHand(Selection(base: 'sevenPairs'), rules).actual, 2);
      expect(evaluateHand(Selection(base: 'sevenPairs'), rules, selfDraw: true).actual, 4);
    });
    test('ping hu rejects flowers; chicken is below minimum', () {
      expect(evaluateHand(Selection(base: 'pingHu', flags: {'flower': true}), rules).valid, false);
      expect(evaluateHand(Selection(base: 'chicken'), rules).valid, false);
    });
    test('seat wind equal to round wind counts once at 1x', () {
      final s = Selection(base: 'allChow', flags: {'seatWind': true, 'roundWind': true});
      expect(evaluateHand(s, rules, sameWind: true).actual, 3);
      expect(evaluateHand(s, const Rules(doubleWind: '1x'), sameWind: true).actual, 2);
    });
    test('selection <-> pattern list round trip', () {
      final s = Selection(base: 'allPong', suit: 'fullColour', flags: {'concealed': true}, counts: {'kong': 2});
      final back = Selection.fromList(s.toList());
      expect(back.toList().map((p) => '${p.id}:${p.n}').toList(), s.toList().map((p) => '${p.id}:${p.n}').toList());
    });
  });

  group('recap + stats', () {
    final r = room();
    final evs = [win(1, shooter: 0, tai: 3), win(2, selfDraw: true, tai: 2, at: 2), draw()];
    test('recap standings and zero-sum', () {
      final rc = buildRecap(r, evs);
      expect(rc.balanced, true);
      expect(rc.roundCount, 3);
      expect(rc.winner.name, anyOf('Bo', 'Cy'));
      expect(recapText(rc), contains('Final standings'));
      expect(recapCsv(rc), contains('Rank'));
    });
    test('leaderboard totals match audit', () {
      final lb = computeLeaderboard([r], {'A': evs});
      expect(sum(lb.map((p) => p.points)), 0);
      expect(lb.firstWhere((p) => p.name == 'Bo').wins, 1);
      expect(rankPlayers(lb).first.rank, 1);
    });
    test('tables group the same four players in any seat order', () {
      final r2 = room(code: 'B', players: const ['Di', 'Cy', 'Bo', 'Ann'], createdAt: 200);
      final g = tableGroups([r, r2], {'A': evs, 'B': evs});
      expect(g.length, 1);
      expect(g.first.games, 2);
      final bd = tableBreakdown(g.first, {'A': evs, 'B': evs});
      expect(bd.rows.length, 2);
      expect(sum(bd.columns.map((c) => c.total)), 0);
    });
  });

  group('continuation', () {
    test('resume dealer after a few wins', () {
      final rs = tableResume(room(), [win(1, shooter: 0), win(2, shooter: 0), win(2, shooter: 0)]);
      expect([rs!.dealer, rs.round, rs.streak], [2, 0, 1]);
    });
    test('no rounds played -> nothing to resume', () {
      expect(tableResume(room(), [win(1, shooter: 0, voided: true)]), isNull);
    });
    test('dealer moves with the person, and only for the same four', () {
      const prev = ['Ann', 'Bo', 'Cy', 'Di'];
      final rs = resumeForSeats(const Resume(2, 1, 1), prev, const ['Cy', 'Ann', 'Bo', 'Di']);
      expect(rs!.dealer, 0);
      expect(resumeForSeats(const Resume(2, 1, 1), prev, const ['Cy', 'Ann', 'Bo', 'Zed']), isNull);
    });
  });
}

void scanTests() {
  group('scan + rule diff', () {
    test('prompt lists the catalogue ids with current Tai values', () {
      final p = buildScanPrompt(const Rules(tai: {'allPong': 3}), const ScanContext(seatWind: 'East', roundWind: 'South', seatNo: 1, selfDraw: true));
      expect(p, contains('- allPong: All Pong'));
      expect(p, contains('= 3 Tai'));
      expect(p, contains('self-draw'));
      expect(p, isNot(contains('- kongWin'))); // special wins are not offered as bonuses
    });
    test('parses a fenced reply into a selection and drops unknown ids', () {
      final r = parseScan('```json\n{"tiles":["1 wan"],"base":"allPong","suit":"halfColour","limit":null,"flags":{"concealed":true,"bogus":true,"kong":true},"counts":{"dragonPung":2,"animal":9},"confidence":1.7,"notes":"ok"}\n```');
      expect(r.selection.base, 'allPong');
      expect(r.selection.suit, 'halfColour');
      expect(r.selection.flags['concealed'], true);
      expect(r.selection.counts['kong'], 1); // a count item given as a flag becomes 1
      expect(r.selection.counts['dragonPung'], 2);
      expect(r.selection.counts['animal'], 4); // capped at the item's max
      expect(r.confidence, 1.0);
      expect(r.warnings.single, contains('bogus'));
    });
    test('a limit hand removes base and suit; junk is rejected', () {
      final r = parseScan('{"base":"allPong","suit":"fullColour","limit":"bigDragons","confidence":0.5}');
      expect([r.selection.base, r.selection.suit, r.selection.limit], [null, null, 'bigDragons']);
      expect(() => parseScan('sorry, cannot read'), throwsA(isA<ScanError>()));
      expect(() => parseScan('{not json}'), throwsA(isA<ScanError>()));
    });
    test('rule diff lists changes with before and after', () {
      final d = rulesDiff(const Rules(), Rules(taiCap: 8, tai: {'allPong': 3}, payouts: {...defaultPayouts, 'exposedKong': 3}));
      expect(d, containsAll(['Tai cap 5 → 8', 'All Pong 2 → 3 Tai', 'Exposed kong 2 → 3']));
      expect(rulesDiff(const Rules(), const Rules()), isEmpty);
    });
  });
}
