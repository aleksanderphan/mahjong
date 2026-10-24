import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mahjong_sg/app_state.dart';
import 'package:mahjong_sg/core/models.dart';
import 'package:mahjong_sg/core/scoring.dart';
import 'package:mahjong_sg/data/local_repository.dart';
import 'package:mahjong_sg/core/rules.dart';
import 'package:mahjong_sg/main.dart';
import 'package:mahjong_sg/ui/scoring_screen.dart';
import 'package:mahjong_sg/ui/tile_widgets.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('repository: create game, record, void, audit stays balanced', () async {
    final repo = LocalRepository(persist: false);
    await repo.init();
    final code = await repo.createRoom(Room(code: '', name: 'T', players: const ['A', 'B', 'C', 'D'], createdAt: 1));
    await repo.addEvent(code, GameEvent(type: 'win', deltas: winDeltas(winner: 0, shooter: 1, tai: 3), createdAt: 2, data: const {'winner': 0, 'shooter': 1, 'tai': 3}));
    final id = await repo.addEvent(code, GameEvent(type: 'instant', deltas: instantDeltas(player: 2, kind: 'concealedKong'), createdAt: 3, data: const {'player': 2, 'kind': 'concealedKong'}));
    await repo.setVoided(code, id, true, reason: 'undo');
    final evs = await repo.watchEvents(code).first;
    final a = audit(evs);
    expect(a.balanced, true);
    expect(a.balances, [32, -16, -8, -8]);
    expect(a.voided, 1);
  });

  test('importing a backup in the legacy web format', () async {
    final repo = LocalRepository(persist: false);
    final snap = Snapshot.fromJson({
      'players': [{'id': 'p1', 'name': 'Ann', 'handle': 'Ace'}],
      'rooms': [{'code': 'ABC123', 'name': 'Old', 'players': ['Ann', 'Bo', 'Cy', 'Di'], 'createdAt': 5, 'status': 'completed', 'settings': {'taiCap': 5}}],
      'eventsByRoom': {'ABC123': [{'id': 'e1', 'type': 'win', 'winner': 0, 'shooter': 1, 'tai': 2, 'deltas': [16, -8, -4, -4], 'voided': false, 'createdAt': 6}]},
    });
    expect(await repo.importAll(snap), 3);
    final all = await repo.loadAll();
    expect(all.eventsByRoom['ABC123']!.single.winner, 0);
    expect(all.eventsByRoom['ABC123']!.single.toJson()['shooter'], 1);
  });

  testWidgets('app starts in demo mode and shows Home', (tester) async {
    final state = AppState(LocalRepository(persist: false));
    await tester.pumpWidget(ChangeNotifierProvider.value(value: state, child: const MahjongApp()));
    await state.init();
    await tester.pumpAndSettle();
    expect(find.text('New game'), findsOneWidget);
    await tester.tap(find.text('Ranking'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Ranking'), findsWidgets);
  });

  test('every catalogue pattern with a picture has a sample and samples only name real patterns', () {
    for (final id in samples.keys) {
      expect(taiById.containsKey(id), true, reason: id);
    }
    for (final x in taiCatalog.where((x) => x.input != TaiInput.variant && x.cat != 'special')) {
      if (const {'heavenly', 'earthly', 'human'}.contains(x.id)) continue; // situations, not hands
      expect(samples.containsKey(x.id) || x.id == 'kongWin', true, reason: x.id);
    }
  });

  testWidgets('scoring guide renders', (tester) async {
    final state = AppState(LocalRepository(persist: false));
    await tester.pumpWidget(ChangeNotifierProvider.value(value: state, child: const MaterialApp(home: ScoringScreen())));
    await tester.pumpAndSettle();
    expect(find.textContaining('Tai → base points'), findsOneWidget);
    expect(find.textContaining('Self-draw'), findsOneWidget);
    await tester.drag(find.byType(ListView), const Offset(0, -3000));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
