import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';
import '../core/models.dart';
import '../core/stats.dart';
import 'theme.dart';

class PlayersScreen extends StatelessWidget {
  const PlayersScreen({super.key});

  Future<void> _edit(BuildContext context, Player? p) async {
    final name = TextEditingController(text: p?.name);
    final handle = TextEditingController(text: p?.handle);
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(p == null ? 'New player' : 'Edit player'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(controller: name, maxLength: 30, decoration: const InputDecoration(labelText: 'Name')),
          TextField(controller: handle, decoration: const InputDecoration(labelText: 'Handle, e.g. "Dragon Master"')),
        ]),
        actions: [TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')), FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Save'))],
      ),
    );
    if (ok != true || name.text.trim().isEmpty || !context.mounted) return;
    await context.read<AppState>().savePlayer(Player(id: p?.id ?? '', name: name.text.trim(), handle: handle.text.trim(), createdAt: p?.createdAt ?? 0));
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    return Scaffold(
      floatingActionButton: FloatingActionButton(onPressed: () => _edit(context, null), child: const Icon(Icons.person_add)),
      body: FutureBuilder<Snapshot>(
        future: app.snapshot(),
        builder: (context, s) {
          final stats = s.hasData ? {for (final x in computeLeaderboard(s.data!.rooms, s.data!.eventsByRoom, s.data!.players)) x.id: x} : <String?, PlayerStats>{};
          return ListView(padding: const EdgeInsets.all(16), children: [
            Text('👥 Players', style: Theme.of(context).textTheme.headlineSmall),
            if (app.roster.isEmpty) const Padding(padding: EdgeInsets.all(24), child: Center(child: Text('Add the people you play with.'))),
            for (final p in app.roster)
              Card(
                child: ListTile(
                  leading: CircleAvatar(child: Text(p.name.characters.first.toUpperCase())),
                  title: Text(p.name),
                  subtitle: Text([if (p.handle.isNotEmpty) '"${p.handle}"', if (stats[p.id] != null) '${stats[p.id]!.games} games · ${stats[p.id]!.wins} wins · ${sign(stats[p.id]!.points)} pts'].join(' · ')),
                  onTap: () => _edit(context, p),
                ),
              ),
          ]);
        },
      ),
    );
  }
}
