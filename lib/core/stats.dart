// Cross-game player statistics for the ranking / player directory (pure functions).
// Port of legacy_web/js/stats.js.
import 'models.dart';
import 'scoring.dart';

String playerKey(String? name) => (name ?? '').trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');

String _seatKey(Room room, int seat, Map<String, Player> byName) {
  final id = room.playerIds[seat];
  if (id.isNotEmpty) return 'id:$id';
  final r = byName[playerKey(room.players[seat])];
  return r != null ? 'id:${r.id}' : 'name:${playerKey(room.players[seat])}';
}

class PlayerStats {
  final String key;
  final String? id;
  String name, handle;
  int tables = 0, tableWins = 0, hands = 0, points = 0;
  int wins = 0, selfDraws = 0, discardWins = 0, payAllWins = 0, shots = 0, kongs = 0, limitHands = 0;
  int taiSum = 0, maxTai = 0, bestWin = 0, lastPlayed = 0;
  int? bestTable, worstTable;

  PlayerStats(this.key, this.name, {this.handle = '', this.id});

  int get games => tables;
  double get winRate => hands > 0 ? wins / hands : 0;
  double get shotRate => hands > 0 ? shots / hands : 0;
  double get avgTai => wins > 0 ? taiSum / wins : 0;
  double get avgPerTable => tables > 0 ? points / tables : 0;
}

int _lastActivity(Room r, List<GameEvent> evs) {
  var last = r.createdAt;
  for (final e in evs) {
    if (e.createdAt > last) last = e.createdAt;
  }
  return last;
}

List<PlayerStats> computeLeaderboard(List<Room> rooms, Map<String, List<GameEvent>> eventsByRoom, [List<Player> roster = const []]) {
  final map = <String, PlayerStats>{};
  final byName = {for (final p in roster) playerKey(p.name): p};
  PlayerStats get(Room room, int seat) {
    final k = _seatKey(room, seat, byName);
    return map.putIfAbsent(k, () {
      Player? r;
      if (k.startsWith('id:')) {
        for (final p in roster) {
          if ('id:${p.id}' == k) r = p;
        }
      }
      return PlayerStats(k, r?.name ?? room.players[seat].trim(),
          handle: r?.handle ?? room.handles[seat], id: r?.id);
    });
  }

  for (final p in roster) {
    map.putIfAbsent('id:${p.id}', () => PlayerStats('id:${p.id}', p.name, handle: p.handle, id: p.id));
  }

  for (final room in rooms) {
    if (room.status == 'cancelled') continue;
    final evs = eventsByRoom[room.code] ?? const <GameEvent>[];
    final a = audit(evs);
    if (a.active == 0) continue; // skip empty games
    final top = a.balances.reduce((x, y) => x > y ? x : y);
    final played = _lastActivity(room, evs);
    for (var seat = 0; seat < 4; seat++) {
      final p = get(room, seat);
      if (played >= p.lastPlayed) {
        p.lastPlayed = played;
        if (p.id == null) p.name = room.players[seat].trim();
      }
      p.tables++;
      p.hands += a.hands;
      p.points += a.balances[seat];
      if (a.balances[seat] == top && top > 0) p.tableWins++;
      if (p.bestTable == null || a.balances[seat] > p.bestTable!) p.bestTable = a.balances[seat];
      if (p.worstTable == null || a.balances[seat] < p.worstTable!) p.worstTable = a.balances[seat];
    }
    for (final ev in evs) {
      if (ev.voided) continue;
      if (ev.type == 'win') {
        final w = get(room, ev.winner!);
        final cap = ev.cap ?? room.settings.taiCap;
        final tai = ev.tai;
        w.wins++;
        w.taiSum += tai < cap ? tai : cap;
        if (tai > w.maxTai) w.maxTai = tai;
        if (tai >= cap) w.limitHands++;
        if (ev.baoBy != null) {
          w.payAllWins++;
        } else if (ev.selfDraw) {
          w.selfDraws++;
        } else {
          w.discardWins++;
        }
        if (!ev.selfDraw && ev.shooter != null) get(room, ev.shooter!).shots++;
        final gain = ev.deltas[ev.winner!];
        if (gain > w.bestWin) w.bestWin = gain;
      } else if (ev.type == 'kong' || (ev.type == 'instant' && (instantKinds[ev.kind]?.kong ?? false))) {
        if (ev.player != null) get(room, ev.player!).kongs++;
      }
    }
  }
  return map.values.toList();
}

class SortSpec {
  final String label;
  final int Function(PlayerStats, PlayerStats) cmp;
  const SortSpec(this.label, this.cmp);
}

int _cmpD(double a, double b) => a.compareTo(b);

final Map<String, SortSpec> sorts = {
  'points': SortSpec('Total points', (a, b) => b.points - a.points),
  'avgPerTable': SortSpec('Avg points / game', (a, b) => _cmpD(b.avgPerTable, a.avgPerTable)),
  'wins': SortSpec('Total wins', (a, b) => b.wins - a.wins != 0 ? b.wins - a.wins : b.points - a.points),
  'winRate': SortSpec('Win rate %', (a, b) => _cmpD(b.winRate, a.winRate) != 0 ? _cmpD(b.winRate, a.winRate) : b.wins - a.wins),
  'maxTai': SortSpec('Highest Tai', (a, b) => b.maxTai - a.maxTai != 0 ? b.maxTai - a.maxTai : b.points - a.points),
  'selfDraws': SortSpec('Self-draws', (a, b) => b.selfDraws - a.selfDraws != 0 ? b.selfDraws - a.selfDraws : b.wins - a.wins),
  'payAllWins': SortSpec('Pay-all wins', (a, b) => b.payAllWins - a.payAllWins != 0 ? b.payAllWins - a.payAllWins : b.wins - a.wins),
  'games': SortSpec('Games played', (a, b) => b.games - a.games != 0 ? b.games - a.games : b.points - a.points),
  'tableWins': SortSpec('Games won (#1 finish)', (a, b) => b.tableWins - a.tableWins != 0 ? b.tableWins - a.tableWins : b.points - a.points),
  'safest': SortSpec('Safest (lowest shoot rate)', (a, b) => _cmpD(a.shotRate, b.shotRate) != 0 ? _cmpD(a.shotRate, b.shotRate) : b.hands - a.hands),
};

class Ranked {
  final int rank;
  final PlayerStats stats;
  const Ranked(this.rank, this.stats);
}

/// Sort and assign ranks (ties share a rank).
List<Ranked> rankPlayers(List<PlayerStats> list, [String sortKey = 'points']) {
  final s = sorts[sortKey] ?? sorts['points']!;
  final sorted = [...list]..sort((a, b) {
      final c = s.cmp(a, b);
      return c != 0 ? c : a.name.compareTo(b.name);
    });
  var rank = 0;
  final out = <Ranked>[];
  for (var i = 0; i < sorted.length; i++) {
    if (i == 0 || s.cmp(sorted[i - 1], sorted[i]) != 0) rank = i + 1;
    out.add(Ranked(rank, sorted[i]));
  }
  return out;
}

class Period {
  final String label;
  final int Function(DateTime now) since;
  const Period(this.label, this.since);
}

int _ms(DateTime d) => d.millisecondsSinceEpoch;
DateTime _startOfDay(DateTime n) => DateTime(n.year, n.month, n.day);

final Map<String, Period> periods = {
  'today': Period('Today', (n) => _ms(_startOfDay(n))),
  'week': Period('This week', (n) => _ms(_startOfDay(n).subtract(Duration(days: (n.weekday - 1))))),
  'month': Period('This month', (n) => _ms(DateTime(n.year, n.month, 1))),
  'year': Period('This year', (n) => _ms(DateTime(n.year, 1, 1))),
  'all': Period('All-time', (n) => 0),
};

/// Games active since a timestamp, ignoring games from before a leaderboard reset.
List<Room> roomsInPeriod(List<Room> rooms, Map<String, List<GameEvent>> eventsByRoom, int since, [int resetAt = 0]) => rooms.where((r) {
      final last = _lastActivity(r, eventsByRoom[r.code] ?? const []);
      return last >= since && r.createdAt >= resetAt;
    }).toList();

class TableGroup {
  final String key;
  final List<Room> rooms; // newest first
  final List<String> players; // names, newest game's seats
  final int lastPlayed;
  const TableGroup(this.key, this.rooms, this.players, this.lastPlayed);
  int get games => rooms.length;
}

/// Tables: games played by exactly the same four players (any seat order). Most recently played first.
List<TableGroup> tableGroups(List<Room> rooms, Map<String, List<GameEvent>> eventsByRoom, [List<Player> roster = const []]) {
  final byName = {for (final p in roster) playerKey(p.name): p};
  final groups = <String, (List<Room>, int)>{};
  for (final room in rooms) {
    if (room.status == 'cancelled') continue;
    final evs = eventsByRoom[room.code] ?? const <GameEvent>[];
    if (audit(evs).active == 0) continue;
    final key = ([for (var s = 0; s < 4; s++) _seatKey(room, s, byName)]..sort()).join('|');
    final last = _lastActivity(room, evs);
    final g = groups.putIfAbsent(key, () => (<Room>[], 0));
    g.$1.add(room);
    groups[key] = (g.$1, last > g.$2 ? last : g.$2);
  }
  final out = groups.entries.map((e) {
    final rs = [...e.value.$1]..sort((a, b) => b.createdAt - a.createdAt);
    return TableGroup(e.key, rs, rs.first.players.map((n) => n.trim()).toList(), e.value.$2);
  }).toList()
    ..sort((a, b) => b.lastPlayed - a.lastPlayed);
  return out;
}

class BreakdownColumn {
  final String key, name;
  final int total;
  const BreakdownColumn(this.key, this.name, this.total);
}

class BreakdownRow {
  final String code, status;
  final int createdAt, hands;
  final Map<String, int> nets;
  const BreakdownRow(this.code, this.createdAt, this.status, this.hands, this.nets);
}

class TableBreakdown {
  final List<BreakdownColumn> columns;
  final List<BreakdownRow> rows;
  final int hands;
  const TableBreakdown(this.columns, this.rows, this.hands);
}

/// Game by game for one table: net points of the four players in every game plus totals.
TableBreakdown tableBreakdown(TableGroup group, Map<String, List<GameEvent>> eventsByRoom, [List<Player> roster = const []]) {
  final byName = {for (final p in roster) playerKey(p.name): p};
  final newest = group.rooms.first;
  final rows = group.rooms.map((room) {
    final a = audit(eventsByRoom[room.code] ?? const []);
    final nets = <String, int>{for (var s = 0; s < 4; s++) _seatKey(room, s, byName): a.balances[s]};
    return BreakdownRow(room.code, room.createdAt, room.status, a.hands, nets);
  }).toList();
  final cols = [
    for (var s = 0; s < 4; s++)
      () {
        final key = _seatKey(newest, s, byName);
        return BreakdownColumn(key, newest.players[s].trim(), rows.fold(0, (t, r) => t + (r.nets[key] ?? 0)));
      }()
  ]..sort((a, b) => b.total - a.total != 0 ? b.total - a.total : a.name.compareTo(b.name));
  return TableBreakdown(cols, rows, rows.fold(0, (t, r) => t + r.hands));
}
