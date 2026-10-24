import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';
import '../core/models.dart';
import '../core/rules.dart';
import '../core/scoring.dart';
import 'game_sheets.dart';
import 'recap_screen.dart';
import 'theme.dart';

/// The live game table. Only the host (the phone that created the game) can record; everyone else sees live scores.
class GameScreen extends StatefulWidget {
  const GameScreen({super.key, required this.code});
  final String code;

  @override
  State<GameScreen> createState() => _GameScreenState();
}

class _GameScreenState extends State<GameScreen> {
  String get code => widget.code;
  Room? _prev;
  late final Stream<Room?> _room = context.read<AppState>().repo.watchRoom(code);
  late final Stream<List<GameEvent>> _events = context.read<AppState>().repo.watchEvents(code);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => mounted ? context.read<AppState>().remember(code) : null);
  }

  /// Phone alert when the game starts / finishes or the host changes (while this screen is open).
  void _announce(Room room) {
    final prev = _prev;
    _prev = room;
    if (prev == null) return;
    final app = context.read<AppState>();
    String? title, body;
    if (prev.status != room.status) {
      if (room.status == 'active' && prev.status == 'lobby') {
        title = '▶️ Game started';
        body = '${room.name} — good luck!';
      } else if (room.status == 'completed') {
        title = '🏁 Game finished';
        body = '${room.name} — the recap is ready.';
      } else if (room.status == 'cancelled') {
        title = 'Game ended';
        body = room.name;
      }
    } else if (prev.hostUid != room.hostUid) {
      title = '🔑 New host';
      body = '${room.hostName.isEmpty ? 'Someone' : room.hostName} is now the host of ${room.name}.';
    }
    if (title != null) {
      final t = title, b = body ?? '';
      WidgetsBinding.instance.addPostFrameCallback((_) => app.notify('room-$code-${room.status}-${room.hostUid}', t, b));
    }
  }

  @override
  Widget build(BuildContext context) {
    final repo = context.read<AppState>().repo;
    return StreamBuilder<Room?>(
      stream: _room,
      builder: (context, rs) {
        if (rs.hasError) return Scaffold(appBar: AppBar(), body: Center(child: Text('${rs.error}')));
        if (rs.connectionState == ConnectionState.waiting) return Scaffold(appBar: AppBar(), body: const Center(child: CircularProgressIndicator()));
        final room = rs.data;
        if (room == null) return Scaffold(appBar: AppBar(title: Text(code)), body: const Center(child: Text('Game not found')));
        _announce(room);
        return StreamBuilder<List<GameEvent>>(
          stream: _events,
          builder: (context, es) => _Table(room: room, events: es.data ?? const [], isHost: room.hostUid == repo.uid),
        );
      },
    );
  }
}

class _Table extends StatelessWidget {
  const _Table({required this.room, required this.events, required this.isHost});
  final Room room;
  final List<GameEvent> events;
  final bool isHost;

  @override
  Widget build(BuildContext context) {
    final a = audit(events);
    final ds = dealerState(events, room.settings);
    final unit = room.settings.scoreLabel;
    final open = !room.isClosed;
    final wins = [for (var s = 0; s < 4; s++) events.where((e) => !e.voided && e.type == 'win' && e.winner == s).length];
    return Scaffold(
      appBar: AppBar(
        title: Text(room.name.isEmpty ? room.code : room.name),
        actions: [
          IconButton(icon: const Icon(Icons.history), tooltip: 'Audit log', onPressed: () => showAuditLog(context, room, events, isHost)),
          IconButton(icon: const Icon(Icons.emoji_events_outlined), tooltip: 'Recap', onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => RecapScreen(room: room, events: events)))),
        ],
      ),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        Wrap(spacing: 8, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
          Chip(label: Text('Code ${room.code}')),
          Chip(label: Text(room.status)),
          Chip(label: Text('Round ${ds.hand}')),
          if (ds.enabled) Chip(label: Text('${windNames[ds.round]} round${ds.streak > 0 ? ' · 连+${ds.streak}' : ''}')),
          Chip(avatar: Icon(a.balanced ? Icons.check_circle : Icons.error, size: 18, color: a.balanced ? Colors.green : Colors.red), label: Text(a.balanced ? 'Balanced' : 'Σ ${a.total}')),
        ]),
        const SizedBox(height: 8),
        for (var i = 0; i < 4; i++) _playerCard(context, i, ds, a.balances[i], wins[i], unit),
        const SizedBox(height: 8),
        if (!isHost && open) _viewerBanner(context),
        if (isHost && open) _hostActions(context, ds),
        if (room.isClosed)
          FilledButton.icon(
            icon: const Icon(Icons.emoji_events),
            label: const Text('View recap'),
            onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => RecapScreen(room: room, events: events))),
          ),
      ]),
    );
  }

  Widget _playerCard(BuildContext context, int i, DealerState ds, int net, int wins, String unit) {
    final w = ds.enabled ? (i - ds.dealer + 4) % 4 : i;
    final score = room.startingScore + net;
    return Card(
      child: ListTile(
        leading: CircleAvatar(child: Text(windZh[w])),
        title: Row(children: [
          Flexible(child: Text(room.players[i], overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.bold))),
          if (ds.enabled && ds.dealer == i) const Padding(padding: EdgeInsets.only(left: 6), child: Chip(label: Text('庄'), visualDensity: VisualDensity.compact)),
        ]),
        subtitle: Text('${windNames[w]} · 🌸#${w + 1} · $wins win${wins == 1 ? '' : 's'}${room.handles[i].isNotEmpty ? ' · "${room.handles[i]}"' : ''}'),
        trailing: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.end, children: [
          Text('$score', style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
          Text('${sign(net)} $unit', style: TextStyle(color: deltaColor(context, net), fontSize: 12)),
        ]),
      ),
    );
  }

  Widget _viewerBanner(BuildContext context) => Card(
        child: ListTile(
          leading: const Icon(Icons.visibility),
          title: Text('Watching live${room.hostName.isEmpty ? '' : ' — host: ${room.hostName}'}'),
          subtitle: const Text('Only the host phone can record rounds.'),
          trailing: room.hasPin ? TextButton(onPressed: () => takeOver(context, room), child: const Text('Take over')) : null,
        ),
      );

  Widget _hostActions(BuildContext context, DealerState ds) {
    final repo = context.read<AppState>().repo;
    Future<void> save(GameEvent ev, String msg) async {
      try {
        await repo.addEvent(room.code, ev);
        if (context.mounted) toast(context, msg);
      } catch (e) {
        if (context.mounted) toast(context, 'Save failed: $e');
      }
    }

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      FilledButton.icon(icon: const Icon(Icons.add_task), label: const Text('Record win 和牌'), onPressed: () => showWinSheet(context, room, events)),
      const SizedBox(height: 8),
      Wrap(spacing: 8, runSpacing: 8, children: [
        OutlinedButton.icon(icon: const Icon(Icons.bolt), label: const Text('Payout'), onPressed: () => showInstantSheet(context, room, events)),
        OutlinedButton.icon(
          icon: const Icon(Icons.pause_circle_outline),
          label: const Text('Draw 流局'),
          onPressed: () async {
            if (await confirm(context, 'Record a draw round?', 'Nobody wins, 0 points.${ds.enabled ? ' Dealer ${room.settings.drawRule == 'rotate' ? 'moves to the next seat' : 'stays (连庄)'}.' : ''}', ok: 'Record draw')) {
              await save(GameEvent(type: 'draw', deltas: const [0, 0, 0, 0], createdAt: DateTime.now().millisecondsSinceEpoch), 'Draw recorded');
            }
          },
        ),
        OutlinedButton.icon(icon: const Icon(Icons.balance), label: const Text('Adjust'), onPressed: () => showAdjustSheet(context, room, events)),
        OutlinedButton.icon(
          icon: const Icon(Icons.undo),
          label: const Text('Undo last'),
          onPressed: () async {
            final last = events.lastWhere((e) => !e.voided, orElse: () => const GameEvent(type: '', deltas: [], createdAt: 0));
            if (last.id == null) return toast(context, 'Nothing to undo');
            if (await confirm(context, 'Undo last transaction?', 'This voids #${events.indexOf(last) + 1} and reverses its points. It stays in the audit log and can be restored.', ok: 'Undo')) {
              await repo.setVoided(room.code, last.id!, true, reason: 'undo');
            }
          },
        ),
      ]),
      const Divider(height: 32),
      Row(children: [
        Expanded(
          child: FilledButton.tonalIcon(
            icon: const Icon(Icons.flag),
            label: const Text('Finish game'),
            onPressed: () async {
              if (await confirm(context, 'Finish this game?', 'The game is closed and a recap is created.', ok: 'Finish')) {
                await repo.updateRoom(room.code, status: 'completed', finishedAt: DateTime.now().millisecondsSinceEpoch);
              }
            },
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: OutlinedButton.icon(
            icon: const Icon(Icons.admin_panel_settings_outlined),
            label: const Text('Host tools'),
            onPressed: () => showHostTools(context, room),
          ),
        ),
      ]),
    ]);
  }
}
