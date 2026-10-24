import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';
import '../core/models.dart';
import '../core/scoring.dart';
import 'game_screen.dart';
import 'new_game_screen.dart';
import 'notifications_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _code = TextEditingController();
  Future<Snapshot>? _snap;

  @override
  void initState() {
    super.initState();
    _snap = context.read<AppState>().snapshot(force: true);
  }

  void _open(String code) {
    final c = code.trim().toUpperCase();
    if (c.isEmpty) return;
    Navigator.push(context, MaterialPageRoute(builder: (_) => GameScreen(code: c)));
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    return RefreshIndicator(
      onRefresh: () async {
        setState(() => _snap = app.snapshot(force: true));
        await _snap;
      },
      child: ListView(padding: const EdgeInsets.all(16), children: [
        Row(children: [
          Expanded(child: Text('🀄 Mahjong SG Tracker', style: Theme.of(context).textTheme.headlineSmall)),
          const NotificationsBell(),
        ]),
        if (app.repo.mode == 'demo')
          const Card(child: ListTile(leading: Icon(Icons.info_outline), title: Text('Demo mode'), subtitle: Text('No Supabase configured — data stays on this device.'))),
        const SizedBox(height: 12),
        FilledButton.icon(
          icon: const Icon(Icons.add),
          label: const Text('New game'),
          onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const NewGameScreen())),
        ),
        const SizedBox(height: 12),
        Row(children: [
          Expanded(
            child: TextField(
              controller: _code,
              textCapitalization: TextCapitalization.characters,
              decoration: const InputDecoration(labelText: 'Join or resume with a game code'),
              onSubmitted: _open,
            ),
          ),
          const SizedBox(width: 8),
          FilledButton.tonal(onPressed: () => _open(_code.text), child: const Text('Open')),
        ]),
        const SizedBox(height: 16),
        FutureBuilder<Snapshot>(
          future: _snap,
          builder: (context, s) {
            if (s.connectionState != ConnectionState.done) return const Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator()));
            if (s.hasError) return Text('Could not load games: ${s.error}');
            final snap = s.data!;
            final rooms = [...snap.rooms]..sort((a, b) => b.createdAt - a.createdAt);
            final live = rooms.where((r) => r.status == 'active' || r.status == 'lobby').toList();
            final done = rooms.where((r) => r.status == 'completed').take(10).toList();
            return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              if (live.isNotEmpty) ...[Text('Games in progress', style: Theme.of(context).textTheme.titleMedium), ...live.map((r) => _tile(r, snap))],
              if (done.isNotEmpty) ...[const SizedBox(height: 12), Text('Recent games', style: Theme.of(context).textTheme.titleMedium), ...done.map((r) => _tile(r, snap))],
              if (rooms.isEmpty) const Padding(padding: EdgeInsets.all(24), child: Center(child: Text('No games yet — start one!'))),
            ]);
          },
        ),
      ]),
    );
  }

  Widget _tile(Room r, Snapshot snap) {
    final a = audit(snap.eventsByRoom[r.code] ?? const []);
    return Card(
      child: ListTile(
        title: Text(r.name.isEmpty ? r.code : r.name),
        subtitle: Text('${r.players.join(' · ')}\n${a.hands} rounds · ${r.status}'),
        isThreeLine: true,
        trailing: Text(r.code, style: const TextStyle(fontFamily: 'monospace')),
        onTap: () => _open(r.code),
      ),
    );
  }
}
