import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';
import '../core/continuation.dart';
import '../core/models.dart';
import '../core/rules.dart';
import 'game_screen.dart';
import 'theme.dart';

class NewGameScreen extends StatefulWidget {
  const NewGameScreen({super.key});
  @override
  State<NewGameScreen> createState() => _NewGameScreenState();
}

class _NewGameScreenState extends State<NewGameScreen> {
  final List<Player?> _seats = [null, null, null, null];
  final _name = TextEditingController();
  final _start = TextEditingController(text: '0');
  final _location = TextEditingController();
  final _keeper = TextEditingController();
  bool _busy = false;
  Resume? _resume;
  Room? _prev;

  @override
  void initState() {
    super.initState();
    _keeper.text = context.read<AppState>().myName;
  }

  Future<void> _pick(int seat) async {
    final app = context.read<AppState>();
    final taken = _seats.whereType<Player>().map((p) => p.id).toSet();
    final p = await showModalBottomSheet<Player>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _PlayerPicker(roster: app.roster.where((p) => !taken.contains(p.id)).toList()),
    );
    if (p == null) return;
    var chosen = p;
    if (p.id.isEmpty) {
      await app.savePlayer(p);
      chosen = app.roster.firstWhere((x) => x.name == p.name);
    }
    setState(() => _seats[seat] = chosen);
    await _lookForEarlierTable();
  }

  /// If the 4 chosen players already played together, offer to continue where that table stopped.
  Future<void> _lookForEarlierTable() async {
    if (_seats.any((s) => s == null)) return;
    final names = _seats.map((s) => s!.name).toList();
    final snap = await context.read<AppState>().snapshot(force: true);
    final prev = latestRoomWith(snap.rooms, names);
    Resume? resume;
    if (prev != null && prev.isClosed) {
      resume = resumeForSeats(tableResume(prev, snap.eventsByRoom[prev.code] ?? const []), prev.players, names);
    }
    if (mounted) {
      setState(() {
      _prev = prev;
      _resume = resume;
    });
    }
  }

  bool _continue = true;

  Future<void> _start_() async {
    final app = context.read<AppState>();
    final ps = _seats.cast<Player>();
    setState(() => _busy = true);
    try {
      final settings = app.house.copyWith(resume: _continue ? _resume : null);
      final room = Room(
        code: '',
        name: _name.text.trim().isEmpty ? 'Mahjong ${DateTime.now().toString().substring(0, 10)}' : _name.text.trim(),
        players: ps.map((p) => p.name).toList(),
        playerIds: ps.map((p) => p.id).toList(),
        handles: ps.map((p) => p.handle).toList(),
        startingScore: int.tryParse(_start.text) ?? 0,
        scorekeeper: _keeper.text.trim(),
        hostName: _keeper.text.trim().isEmpty ? 'Host' : _keeper.text.trim(),
        location: _location.text.trim(),
        settings: settings,
        createdAt: DateTime.now().millisecondsSinceEpoch,
        continuesFrom: _continue && _resume != null ? _prev?.code : null,
      );
      final code = await app.repo.createRoom(room);
      if (_keeper.text.trim().isNotEmpty) await app.setMyName(_keeper.text.trim());
      app.remember(code);
      app.invalidate();
      if (!mounted) return;
      Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => GameScreen(code: code)));
    } catch (e) {
      if (mounted) {
        setState(() => _busy = false);
        toast(context, 'Could not start: $e');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final ready = _seats.every((s) => s != null);
    return Scaffold(
      appBar: AppBar(title: const Text('New game')),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        for (var i = 0; i < 4; i++)
          Card(
            child: ListTile(
              leading: CircleAvatar(child: Text(windZh[i])),
              title: Text(_seats[i]?.name ?? 'Choose player'),
              subtitle: Text('${windNames[i]} seat${_seats[i]?.handle.isNotEmpty == true ? ' · "${_seats[i]!.handle}"' : ''}'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => _pick(i),
            ),
          ),
        if (_resume != null)
          Card(
            color: Theme.of(context).colorScheme.secondaryContainer,
            child: SwitchListTile(
              title: const Text('↩ Continue this table'),
              subtitle: Text('Same four players: ${resumeText(_resume!, _seats.map((s) => s!.name).toList())}'),
              value: _continue,
              onChanged: (v) => setState(() => _continue = v),
            ),
          ),
        const SizedBox(height: 8),
        TextField(controller: _name, decoration: const InputDecoration(labelText: 'Game name (optional)')),
        const SizedBox(height: 12),
        Row(children: [
          Expanded(child: TextField(controller: _start, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Starting score'))),
          const SizedBox(width: 12),
          Expanded(child: TextField(controller: _location, decoration: const InputDecoration(labelText: 'Location'))),
        ]),
        const SizedBox(height: 12),
        TextField(controller: _keeper, decoration: const InputDecoration(labelText: 'Scorekeeper (you)')),
        const SizedBox(height: 20),
        FilledButton(onPressed: ready && !_busy ? _start_ : null, child: Text(_busy ? 'Starting…' : 'Start game')),
      ]),
    );
  }
}

/// Bottom sheet: pick an existing player or add a new one (returned with an empty id).
class _PlayerPicker extends StatefulWidget {
  const _PlayerPicker({required this.roster});
  final List<Player> roster;
  @override
  State<_PlayerPicker> createState() => _PlayerPickerState();
}

class _PlayerPickerState extends State<_PlayerPicker> {
  final _name = TextEditingController();
  final _handle = TextEditingController();

  @override
  Widget build(BuildContext context) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom, left: 16, right: 16, top: 16),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Flexible(
            child: ListView(shrinkWrap: true, children: [
              for (final p in widget.roster)
                ListTile(title: Text(p.name), subtitle: p.handle.isEmpty ? null : Text('"${p.handle}"'), onTap: () => Navigator.pop(context, p)),
            ]),
          ),
          const Divider(),
          Row(children: [
            Expanded(child: TextField(controller: _name, maxLength: 30, decoration: const InputDecoration(labelText: 'New player name'))),
            const SizedBox(width: 8),
            Expanded(child: TextField(controller: _handle, decoration: const InputDecoration(labelText: 'Handle (optional)'))),
            IconButton(
              icon: const Icon(Icons.add_circle),
              onPressed: () => _name.text.trim().isEmpty ? null : Navigator.pop(context, Player(id: '', name: _name.text.trim(), handle: _handle.text.trim())),
            ),
          ]),
          const SizedBox(height: 8),
        ]),
      );
}
