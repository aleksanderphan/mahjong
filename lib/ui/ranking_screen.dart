import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';
import '../core/models.dart';
import '../core/stats.dart';
import 'theme.dart';

/// Ranking: everyone accumulated, or one table of 4 players game by game.
class RankingScreen extends StatefulWidget {
  const RankingScreen({super.key});
  @override
  State<RankingScreen> createState() => _RankingScreenState();
}

class _RankingScreenState extends State<RankingScreen> {
  String _period = 'all', _sort = 'points', _view = 'all';
  String? _tableKey;
  Future<Snapshot>? _snap;

  @override
  void initState() {
    super.initState();
    _snap = context.read<AppState>().snapshot(force: true);
  }

  String _metric(PlayerStats p) => switch (_sort) {
        'avgPerTable' => p.avgPerTable.toStringAsFixed(1),
        'wins' => '${p.wins}',
        'winRate' => '${(p.winRate * 100).toStringAsFixed(1)}%',
        'maxTai' => '${p.maxTai} Tai',
        'selfDraws' => '${p.selfDraws}',
        'payAllWins' => '${p.payAllWins}',
        'games' => '${p.games}',
        'tableWins' => '${p.tableWins}',
        'safest' => '${(p.shotRate * 100).toStringAsFixed(1)}%',
        _ => sign(p.points),
      };

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    return FutureBuilder<Snapshot>(
      future: _snap,
      builder: (context, s) {
        if (s.connectionState != ConnectionState.done) return const Center(child: CircularProgressIndicator());
        if (s.hasError) return Center(child: Text('${s.error}'));
        final snap = s.data!;
        final since = periods[_period]!.since(DateTime.now());
        final rooms = roomsInPeriod(snap.rooms, snap.eventsByRoom, since, app.house.leaderboardResetAt);
        return ListView(padding: const EdgeInsets.all(16), children: [
          Text('🏆 Ranking', style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 8),
          SegmentedButton<String>(
            segments: const [ButtonSegment(value: 'all', label: Text('All players')), ButtonSegment(value: 'table', label: Text('By table (4)'))],
            selected: {_view},
            onSelectionChanged: (v) => setState(() => _view = v.first),
          ),
          const SizedBox(height: 8),
          Wrap(spacing: 8, children: [
            for (final e in periods.entries) ChoiceChip(label: Text(e.value.label), selected: _period == e.key, onSelected: (_) => setState(() => _period = e.key)),
          ]),
          if (_view == 'all') ..._all(snap, rooms) else ..._byTable(snap, rooms),
        ]);
      },
    );
  }

  List<Widget> _all(Snapshot snap, List<Room> rooms) {
    final ranked = rankPlayers(computeLeaderboard(rooms, snap.eventsByRoom, snap.players).where((p) => p.games > 0).toList(), _sort);
    return [
      DropdownButton<String>(
        value: _sort,
        isExpanded: true,
        items: [for (final e in sorts.entries) DropdownMenuItem(value: e.key, child: Text('Rank by ${e.value.label}'))],
        onChanged: (v) => setState(() => _sort = v ?? _sort),
      ),
      if (ranked.isEmpty) const Padding(padding: EdgeInsets.all(24), child: Center(child: Text('No finished rounds in this period.'))),
      for (final r in ranked)
        Card(
          child: ListTile(
            leading: CircleAvatar(child: Text('${r.rank}')),
            title: Text('${r.stats.name}${r.stats.handle.isNotEmpty ? ' "${r.stats.handle}"' : ''}'),
            subtitle: Text('${r.stats.games} games · ${r.stats.wins} wins · ${sign(r.stats.points)} pts total'),
            trailing: Text(_metric(r.stats), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          ),
        ),
    ];
  }

  List<Widget> _byTable(Snapshot snap, List<Room> rooms) {
    final groups = tableGroups(rooms, snap.eventsByRoom, snap.players);
    if (groups.isEmpty) return const [Padding(padding: EdgeInsets.all(24), child: Center(child: Text('No tables yet.')))];
    final g = groups.firstWhere((x) => x.key == _tableKey, orElse: () => groups.first);
    final bd = tableBreakdown(g, snap.eventsByRoom, snap.players);
    return [
      DropdownButton<String>(
        value: g.key,
        isExpanded: true,
        items: [for (final x in groups) DropdownMenuItem(value: x.key, child: Text('${x.players.join(' · ')} (${x.games})', overflow: TextOverflow.ellipsis))],
        onChanged: (v) => setState(() => _tableKey = v),
      ),
      for (var i = 0; i < bd.columns.length; i++)
        Card(child: ListTile(leading: CircleAvatar(child: Text('${i + 1}')), title: Text(bd.columns[i].name), trailing: Text(sign(bd.columns[i].total), style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: deltaColor(context, bd.columns[i].total))))),
      const SizedBox(height: 8),
      SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: DataTable(
          columns: [const DataColumn(label: Text('Game')), for (final c in bd.columns) DataColumn(label: Text(c.name), numeric: true)],
          rows: [
            for (final r in bd.rows)
              DataRow(cells: [
                DataCell(Text(DateTime.fromMillisecondsSinceEpoch(r.createdAt).toString().substring(5, 10))),
                for (final c in bd.columns) DataCell(Text(sign(r.nets[c.key] ?? 0), style: TextStyle(color: deltaColor(context, r.nets[c.key] ?? 0)))),
              ]),
            DataRow(cells: [const DataCell(Text('Total', style: TextStyle(fontWeight: FontWeight.bold))), for (final c in bd.columns) DataCell(Text(sign(c.total), style: const TextStyle(fontWeight: FontWeight.bold)))]),
          ],
        ),
      ),
    ];
  }
}
