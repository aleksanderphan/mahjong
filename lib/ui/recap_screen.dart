import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';

import '../app_state.dart';
import '../core/models.dart';
import '../core/recap.dart';
import '../core/scoring.dart';
import 'theme.dart';

class RecapScreen extends StatelessWidget {
  const RecapScreen({super.key, required this.room, required this.events});
  final Room room;
  final List<GameEvent> events;

  @override
  Widget build(BuildContext context) {
    final app = context.read<AppState>();
    final r = buildRecap(room, events);
    final unit = room.settings.scoreLabel;
    final isHost = room.hostUid == app.repo.uid;
    const medals = ['🥇', '🥈', '🥉', '4️⃣'];
    return Scaffold(
      appBar: AppBar(title: const Text('Recap'), actions: [
        PopupMenuButton<String>(
          icon: const Icon(Icons.share),
          onSelected: (v) async {
            if (v == 'csv') {
              await Clipboard.setData(ClipboardData(text: recapCsv(r)));
              if (context.mounted) toast(context, 'CSV copied');
              return;
            }
            final fmt = v == 'whatsapp' ? ShareFormat.whatsapp : v == 'teams' ? ShareFormat.teams : ShareFormat.plain;
            final text = recapText(r, format: fmt, unit: unit);
            if (v == 'copy') {
              await Clipboard.setData(ClipboardData(text: text));
              if (context.mounted) toast(context, 'Copied');
            } else {
              await SharePlus.instance.share(ShareParams(text: text));
            }
          },
          itemBuilder: (_) => const [
            PopupMenuItem(value: 'whatsapp', child: Text('Share (WhatsApp format)')),
            PopupMenuItem(value: 'teams', child: Text('Share (Teams format)')),
            PopupMenuItem(value: 'copy', child: Text('Copy text')),
            PopupMenuItem(value: 'csv', child: Text('Copy CSV')),
          ],
        ),
      ]),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        Text('🏆 ${r.winner.name}', style: Theme.of(context).textTheme.headlineMedium),
        Text('${gameNumber(r.code, r.startedAt)} · ${r.roundCount} rounds · ${fmtDuration(r.durationMs)}'),
        const SizedBox(height: 12),
        for (final p in r.standings)
          Card(
            child: ListTile(
              leading: Text(medals[(p.rank - 1).clamp(0, 3)], style: const TextStyle(fontSize: 28)),
              title: Text('${p.name}${p.handle.isNotEmpty ? ' "${p.handle}"' : ''}'),
              subtitle: Text('${p.wins} wins · ${p.selfDraws} self-draw · ${p.discardWins} discard${p.payAll > 0 ? ' · ${p.payAll} pay-all' : ''} · ${p.shots} shot'),
              trailing: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.end, children: [
                Text('${p.points}', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                Text('${sign(p.net)} $unit', style: TextStyle(color: deltaColor(context, p.net), fontSize: 12)),
              ]),
            ),
          ),
        const SizedBox(height: 8),
        Text('What they won with', style: Theme.of(context).textTheme.titleMedium),
        for (final p in r.standings)
          if (p.winsDetail.isNotEmpty)
            ExpansionTile(
              title: Text(p.name),
              initiallyExpanded: true,
              children: [
                for (final w in p.winsDetail)
                  ListTile(
                    dense: true,
                    title: Text('R${w.round} · ${w.tai} Tai · ${sign(w.points)}'),
                    subtitle: Text('${w.patterns.isEmpty ? 'Tai entered directly' : w.patterns}\n${w.method}${w.remarks.isEmpty ? '' : ' · ${w.remarks}'}'),
                    isThreeLine: true,
                    trailing: isHost && w.changeShooter && w.id != null
                        ? IconButton(icon: const Icon(Icons.edit), tooltip: 'Change who discarded', onPressed: () => _changeShooter(context, app, w))
                        : null,
                  ),
              ],
            ),
        if (r.highest != null) Card(child: ListTile(leading: const Text('🔥', style: TextStyle(fontSize: 24)), title: Text('Highest hand: ${r.highestName} — ${r.highest!.tai} Tai'), subtitle: Text(r.highest!.patterns))),
        const SizedBox(height: 8),
        Text('All rounds', style: Theme.of(context).textTheme.titleMedium),
        for (final x in r.rounds) ListTile(dense: true, leading: Text('#${x.n}'), title: Text(x.text), trailing: Text(x.tai == null ? '—' : '${x.tai} Tai')),
        const SizedBox(height: 8),
        Text(r.balanced ? '✓ Zero-sum balanced' : '✗ Not balanced (Σ ${r.total})'),
      ]),
    );
  }

  /// Host fixes who discarded a winning tile: the same points, with the new discarder paying double.
  Future<void> _changeShooter(BuildContext context, AppState app, WinDetail w) async {
    final ev = events.firstWhere((e) => e.id == w.id);
    final pick = await showDialog<int>(
      context: context,
      builder: (c) => SimpleDialog(
        title: const Text('Who discarded?'),
        children: [
          for (var i = 0; i < 4; i++)
            if (i != w.winner) SimpleDialogOption(onPressed: () => Navigator.pop(c, i), child: Text('${room.players[i]}${i == w.shooter ? ' (current)' : ''}')),
        ],
      ),
    );
    if (pick == null || pick == w.shooter) return;
    final newId = await app.repo.addEvent(
      room.code,
      GameEvent(type: 'win', deltas: reassignShooter(ev.deltas, w.winner, w.shooter!, pick), createdAt: ev.createdAt + 1, data: {...ev.data, 'shooter': pick, 'replaces': ev.id}),
    );
    try {
      await app.repo.setVoided(room.code, ev.id!, true, reason: 'edited');
    } catch (_) {
      await app.repo.setVoided(room.code, newId, true, reason: 'undo'); // never leave both entries counting
      rethrow;
    }
    if (context.mounted) {
      toast(context, 'Discarder changed to ${room.players[pick]}');
      Navigator.pop(context);
    }
  }
}
