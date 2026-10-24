// End-of-game recap: standings, wins by method, what each player won with, all rounds, highest hand.
import 'hand.dart';
import 'models.dart';
import 'scoring.dart';

const _wind = ['East', 'South', 'West', 'North'];
const _wzh = ['東', '南', '西', '北'];

String methodText(GameEvent ev, List<String> names) {
  if (ev.baoBy != null) return 'Pay-all by ${names[ev.baoBy!]}';
  if (ev.selfDraw) return 'Self-draw';
  return 'Discard from ${names[ev.shooter ?? 0]}';
}

class WinDetail {
  final int round, tai, effective, base, points, winner;
  final int? shooter;
  final String method, patterns, remarks;
  final bool selfDraw, changeShooter;
  final String? id;
  const WinDetail(this.round, this.tai, this.effective, this.base, this.points, this.method, this.patterns, this.selfDraw, this.remarks, this.id,
      this.winner, this.shooter, this.changeShooter);
}

class RecapPlayer {
  final int seat;
  final String name, handle, wind, windZh;
  final int net, points;
  int wins = 0, selfDraws = 0, discardWins = 0, payAll = 0, shots = 0, kongs = 0, rank = 0;
  final List<WinDetail> winsDetail = [];
  RecapPlayer(this.seat, this.name, this.handle, this.net, this.points)
      : wind = _wind[seat],
        windZh = _wzh[seat];
}

class RecapRound {
  final int n;
  final String type, text, patterns;
  final int? tai;
  const RecapRound(this.n, this.type, this.text, this.tai, this.patterns);
}

class Recap {
  final String code, name, location, status;
  final int startedAt;
  final int? finishedAt;
  final int durationMs, roundCount, total, payouts;
  final List<RecapRound> rounds;
  final List<RecapPlayer> players, standings;
  final WinDetail? highest;
  final String? highestName;
  final bool balanced;
  RecapPlayer get winner => standings.first;
  const Recap(this.code, this.name, this.location, this.status, this.startedAt, this.finishedAt, this.durationMs, this.roundCount, this.total,
      this.payouts, this.rounds, this.players, this.standings, this.highest, this.highestName, this.balanced);
}

Recap buildRecap(Room room, List<GameEvent> events) {
  final names = room.players;
  final start = room.startingScore;
  final a = audit(events);
  final players = [for (var s = 0; s < 4; s++) RecapPlayer(s, names[s], room.handles[s], a.balances[s], start + a.balances[s])];
  final rounds = <RecapRound>[];
  var n = 0;
  WinDetail? highest;
  String? highestName;
  for (final ev in events) {
    if (ev.voided) continue;
    if (ev.type == 'win') {
      n++;
      final w = ev.winner!;
      final p = players[w];
      p.wins++;
      if (ev.baoBy != null) {
        p.payAll++;
      } else if (ev.selfDraw) {
        p.selfDraws++;
      } else {
        p.discardWins++;
      }
      if (!ev.selfDraw && ev.shooter != null) players[ev.shooter!].shots++;
      final cap = ev.cap ?? room.settings.taiCap;
      final detail = WinDetail(n, ev.tai, ev.tai < cap ? ev.tai : cap, basePoints(ev.tai, cap), ev.deltas[w], methodText(ev, names),
          patternText(ev.patterns), ev.selfDraw, ev.remarks ?? '', ev.id, w, ev.shooter, !ev.selfDraw && ev.baoBy == null && ev.shooter != null);
      p.winsDetail.add(detail);
      final how = ev.baoBy != null ? 'Pay-all' : ev.selfDraw ? 'Self-draw' : 'from ${names[ev.shooter ?? 0]}';
      rounds.add(RecapRound(n, 'win', '${names[w]} ($how)', ev.tai, detail.patterns));
      if (highest == null || ev.tai > highest.tai) {
        highest = detail;
        highestName = names[w];
      }
    } else if (ev.type == 'draw') {
      n++;
      rounds.add(RecapRound(n, 'draw', 'Draw', null, ''));
    } else if (ev.type == 'instant' || ev.type == 'kong') {
      if ((ev.type == 'kong' || (instantKinds[ev.kind]?.kong ?? false)) && ev.player != null) players[ev.player!].kongs++;
    }
  }
  final standings = [...players]..sort((x, y) => y.points != x.points ? y.points - x.points : (y.wins != x.wins ? y.wins - x.wins : x.seat - y.seat));
  var rank = 0;
  for (var i = 0; i < standings.length; i++) {
    if (i == 0 || standings[i - 1].points != standings[i].points) rank = i + 1;
    standings[i].rank = rank;
  }
  final end = room.finishedAt ?? DateTime.now().millisecondsSinceEpoch;
  return Recap(room.code, room.name, room.location, room.status, room.createdAt, room.finishedAt, (end - room.createdAt).clamp(0, 1 << 52), n, a.total,
      events.where((e) => !e.voided && (e.type == 'instant' || e.type == 'kong')).length, rounds, players, standings, highest, highestName, a.balanced);
}

String fmtDuration(int ms) {
  final m = (ms / 60000).round();
  final h = m ~/ 60;
  return h > 0 ? '$h h ${m % 60} min' : '$m min';
}

String gameNumber(String code, int createdAt) {
  final d = DateTime.fromMillisecondsSinceEpoch(createdAt);
  String p(int x) => x.toString().padLeft(2, '0');
  return 'MJ-${d.year}${p(d.month)}${p(d.day)}-$code';
}

const _medal = ['🥇', '🥈', '🥉', '4️⃣'];
String _sign(int x) => '${x > 0 ? '+' : ''}$x';

enum ShareFormat { whatsapp, teams, plain }

String recapText(Recap r, {ShareFormat format = ShareFormat.plain, String unit = 'pts'}) {
  String b(String s) => format == ShareFormat.whatsapp ? '*$s*' : format == ShareFormat.teams ? '**$s**' : s;
  final l = <String>[];
  l.add('🀄 ${b('Mahjong Recap')} — ${gameNumber(r.code, r.startedAt)}');
  if (r.name.isNotEmpty) l.add('${r.name}${r.location.isNotEmpty ? ' · ${r.location}' : ''}');
  l.add('Rounds: ${r.roundCount} · Duration: ${fmtDuration(r.durationMs)}');
  l.add('');
  l.add(b('Final standings'));
  for (var i = 0; i < r.standings.length; i++) {
    final p = r.standings[i];
    l.add('${_medal[(p.rank - 1).clamp(0, 3)]} ${p.name}${p.handle.isNotEmpty ? ' "${p.handle}"' : ''} — ${p.points} $unit (${_sign(p.net)}) · '
        '${p.wins}× win (${p.selfDraws} self-draw, ${p.discardWins} discard${p.payAll > 0 ? ', ${p.payAll} pay-all' : ''})');
  }
  l.add('');
  l.add(b('What they won with'));
  for (final p in r.standings) {
    if (p.winsDetail.isEmpty) continue;
    l.add('${p.name}:');
    for (final w in p.winsDetail) {
      l.add('  • R${w.round} ${w.tai} Tai ${_sign(w.points)} — ${w.patterns.isEmpty ? 'Tai entered directly' : w.patterns} (${w.method})');
    }
  }
  if (r.highest != null) {
    l.add('');
    l.add('${b('Highest hand')}: ${r.highestName} — ${r.highest!.tai} Tai${r.highest!.patterns.isNotEmpty ? ' (${r.highest!.patterns})' : ''}');
  }
  l.add('');
  l.add(r.balanced ? '✓ Zero-sum balanced' : '✗ Not balanced (Σ ${r.total})');
  return l.join('\n');
}

String recapCsv(Recap r) {
  String q(Object? v) {
    final t = '${v ?? ''}';
    return RegExp(r'[",\n]').hasMatch(t) ? '"${t.replaceAll('"', '""')}"' : t;
  }

  final rows = <List<Object?>>[
    ['Rank', 'Seat', 'Player', 'Handle', 'Points', 'Net', 'Wins', 'Self-draw', 'Discard', 'Pay-all', 'Shot', 'Kongs'],
    for (final p in r.standings) [p.rank, p.wind, p.name, p.handle, p.points, p.net, p.wins, p.selfDraws, p.discardWins, p.payAll, p.shots, p.kongs],
    [],
    ['Round', 'Result', 'Tai', 'Patterns'],
    for (final x in r.rounds) [x.n, x.text, x.tai ?? '', x.patterns],
  ];
  return '﻿${rows.map((row) => row.map(q).join(',')).join('\r\n')}';
}
