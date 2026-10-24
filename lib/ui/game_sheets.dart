import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';
import '../core/models.dart';
import '../core/rules.dart';
import '../core/scan.dart';
import '../core/scoring.dart';
import 'pattern_picker.dart';
import 'theme.dart';

Future<T?> _sheet<T>(BuildContext context, Widget Function(BuildContext) builder) => showModalBottomSheet<T>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (c) => Padding(padding: EdgeInsets.only(bottom: MediaQuery.of(c).viewInsets.bottom), child: builder(c)),
    );

Widget _seatChoice(Room room, DealerState ds, int? value, void Function(int) onTap, {List<int> exclude = const []}) => Wrap(spacing: 8, runSpacing: 8, children: [
      for (var i = 0; i < 4; i++)
        ChoiceChip(
          avatar: CircleAvatar(child: Text(windZh[ds.enabled ? (i - ds.dealer + 4) % 4 : i])),
          label: Text('${room.players[i]}${ds.enabled && ds.dealer == i ? ' 庄' : ''}'),
          selected: value == i,
          onSelected: exclude.contains(i) ? null : (_) => onTap(i),
        ),
    ]);

Widget _preview(BuildContext context, Room room, List<int> d) => Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(children: [
          for (var i = 0; i < 4; i++)
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              Text(room.players[i]),
              Text('${sign(d[i])} ${room.settings.scoreLabel}', style: TextStyle(fontWeight: FontWeight.bold, color: deltaColor(context, d[i]))),
            ]),
        ]),
      ),
    );

/* ------------------------------------------------------------------ Record / edit a win */
Future<void> showWinSheet(BuildContext context, Room room, List<GameEvent> events, {GameEvent? edit}) =>
    _sheet(context, (_) => _WinSheet(room: room, events: events, edit: edit, repo: context.read<AppState>()));

class _WinSheet extends StatefulWidget {
  const _WinSheet({required this.room, required this.events, required this.repo, this.edit});
  final Room room;
  final List<GameEvent> events;
  final GameEvent? edit;
  final AppState repo;
  @override
  State<_WinSheet> createState() => _WinSheetState();
}

class _WinSheetState extends State<_WinSheet> {
  final _picker = PickerState();
  final _remarks = TextEditingController();
  int? _winner, _shooter, _baoBy;
  String _method = 'self'; // self | discard | bao
  bool _baoSelf = false;
  String _reason = 'thirdDragon';
  bool _busy = false;

  Rules get rules => widget.room.settings;

  @override
  void initState() {
    super.initState();
    final e = widget.edit;
    if (e != null) {
      _winner = e.winner;
      _shooter = e.shooter;
      _baoBy = e.baoBy;
      _method = e.baoBy != null ? 'bao' : (e.selfDraw ? 'self' : 'discard');
      _baoSelf = e.selfDraw;
      _reason = (e.data['baoReason'] as String?) ?? 'thirdDragon';
      _remarks.text = e.remarks ?? '';
      _picker.load(patterns: e.patterns, tai: e.tai);
    }
  }

  DealerState get _ds => dealerState(widget.events.where((e) => widget.edit == null || e.createdAt < widget.edit!.createdAt), rules);

  bool get _selfDraw => _method == 'self' || (_method == 'bao' && _baoSelf);

  ({GameEvent? ev, String? error}) _build() {
    if (_winner == null) return (ev: null, error: 'Select the winner');
    final ds = _ds;
    final w = ds.enabled ? (_winner! - ds.dealer + 4) % 4 : _winner!;
    final res = _picker.result(rules, selfDraw: _selfDraw, sameWind: ds.enabled && w == ds.round);
    if (!res.hand.valid) return (ev: null, error: res.hand.errors.isEmpty ? 'Select the scoring patterns' : res.hand.errors.first);
    final data = <String, dynamic>{
      'winner': _winner,
      'tai': res.hand.actual,
      'cap': rules.taiCap,
      'patterns': (res.patterns ?? const []).map((p) => p.toJson()).toList(),
      'remarks': _remarks.text.trim().isEmpty ? null : _remarks.text.trim(),
    };
    if (_method == 'self') {
      data..['selfDraw'] = true..['shooter'] = null;
    } else if (_method == 'discard') {
      if (_shooter == null) return (ev: null, error: 'Select who discarded the winning tile');
      data..['selfDraw'] = false..['shooter'] = _shooter;
    } else {
      if (_baoBy == null) return (ev: null, error: 'Select the responsible player');
      data
        ..['selfDraw'] = _baoSelf
        ..['shooter'] = _baoSelf ? null : _baoBy
        ..['baoBy'] = _baoBy
        ..['baoReason'] = _reason
        ..['baoMultiplier'] = rules.baoMultiplier;
    }
    try {
      final d = winDeltas(
        winner: _winner!,
        shooter: data['shooter'] as int?,
        selfDraw: data['selfDraw'] == true,
        tai: res.hand.actual,
        cap: rules.taiCap,
        baoBy: data['baoBy'] as int?,
        baoMultiplier: rules.baoMultiplier,
      );
      return (ev: GameEvent(type: 'win', deltas: d, createdAt: DateTime.now().millisecondsSinceEpoch, data: data), error: null);
    } on ScoringError catch (e) {
      return (ev: null, error: e.message);
    }
  }

  Future<void> _save(GameEvent ev) async {
    setState(() => _busy = true);
    final repo = widget.repo.repo;
    try {
      final edit = widget.edit;
      if (edit == null) {
        await repo.addEvent(widget.room.code, ev);
      } else {
        await repo.addEvent(widget.room.code, GameEvent(type: 'win', deltas: ev.deltas, createdAt: edit.createdAt + 1, data: {...ev.data, 'replaces': edit.id}));
        await repo.setVoided(widget.room.code, edit.id!, true, reason: 'edited');
      }
      if (mounted) {
        Navigator.pop(context);
        toast(context, edit == null ? 'Win recorded' : 'Round corrected');
      }
    } catch (e) {
      if (mounted) {
        setState(() => _busy = false);
        toast(context, 'Save failed: $e');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final room = widget.room;
    final ds = _ds;
    return ListenableBuilder(
      listenable: _picker,
      builder: (context, _) {
        final b = _build();
        final w = _winner == null ? null : (ds.enabled ? (_winner! - ds.dealer + 4) % 4 : _winner!);
        return ListView(padding: const EdgeInsets.fromLTRB(16, 0, 16, 24), children: [
          Text(widget.edit == null ? '🀄 Record winning round' : '✏️ Edit round', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 12),
          Text('1 · Winner', style: Theme.of(context).textTheme.titleSmall),
          _seatChoice(room, ds, _winner, (i) => setState(() {
                _winner = i;
                if (_shooter == i) _shooter = null;
                if (_baoBy == i) _baoBy = null;
              })),
          const SizedBox(height: 12),
          Text('2 · How', style: Theme.of(context).textTheme.titleSmall),
          SegmentedButton<String>(
            segments: [
              const ButtonSegment(value: 'self', label: Text('Self-draw')),
              const ButtonSegment(value: 'discard', label: Text('Discard')),
              ButtonSegment(value: 'bao', label: Text('Pay-all ${rules.baoMultiplier}×')),
            ],
            selected: {_method},
            onSelectionChanged: (s) => setState(() => _method = s.first),
          ),
          if (_method == 'discard') ...[
            const SizedBox(height: 8),
            const Text('Who discarded the winning tile?'),
            _seatChoice(room, ds, _shooter, (i) => setState(() => _shooter = i), exclude: [?_winner]),
          ],
          if (_method == 'bao') ...[
            const SizedBox(height: 8),
            const Text('Responsible player pays everything'),
            _seatChoice(room, ds, _baoBy, (i) => setState(() => _baoBy = i), exclude: [?_winner]),
            DropdownButtonFormField<String>(
              initialValue: _reason,
              decoration: const InputDecoration(labelText: 'Trigger'),
              items: [for (final e in baoReasons.entries) DropdownMenuItem(value: e.key, child: Text(e.value.$1))],
              onChanged: (v) => setState(() => _reason = v ?? _reason),
            ),
            SwitchListTile(contentPadding: EdgeInsets.zero, title: const Text('Winner self-drew'), value: _baoSelf, onChanged: (v) => setState(() => _baoSelf = v)),
          ],
          const SizedBox(height: 12),
          Text('3 · Scoring patterns', style: Theme.of(context).textTheme.titleSmall),
          if (w != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text('Seat ${w + 1} · ${windNames[w]}${ds.enabled ? ' · round wind ${windNames[ds.round]}' : ''}', style: Theme.of(context).textTheme.bodySmall),
            ),
          PatternPicker(
            state: _picker,
            rules: rules,
            selfDraw: _selfDraw,
            sameWind: ds.enabled && w == ds.round,
            scanContext: ScanContext(
              seatWind: w == null ? '' : windNames[w],
              roundWind: windNames[ds.round],
              seatNo: w == null ? null : w + 1,
              selfDraw: _selfDraw,
            ),
          ),
          TextField(controller: _remarks, maxLength: 120, decoration: const InputDecoration(labelText: 'Round remarks (optional)')),
          if (b.ev != null) _preview(context, room, b.ev!.deltas),
          if (b.error != null) Padding(padding: const EdgeInsets.only(bottom: 8), child: Text(b.error!, style: TextStyle(color: Theme.of(context).colorScheme.error))),
          FilledButton(
            onPressed: b.ev == null || _busy ? null : () => _save(b.ev!),
            child: Text(b.ev == null ? 'Confirm win' : '✓ ${widget.edit == null ? 'Confirm win' : 'Save correction'}: ${sign(b.ev!.deltas[_winner!])} (${b.ev!.tai} Tai)'),
          ),
        ]);
      },
    );
  }
}

/* ------------------------------------------------------------------ Instant payout */
Future<void> showInstantSheet(BuildContext context, Room room, List<GameEvent> events) =>
    _sheet(context, (_) => _InstantSheet(room: room, events: events, app: context.read<AppState>()));

class _InstantSheet extends StatefulWidget {
  const _InstantSheet({required this.room, required this.events, required this.app});
  final Room room;
  final List<GameEvent> events;
  final AppState app;
  @override
  State<_InstantSheet> createState() => _InstantSheetState();
}

class _InstantSheetState extends State<_InstantSheet> {
  int? _player;
  String _kind = 'exposedKong';
  bool _fromDeal = false;
  final _notes = TextEditingController();

  @override
  Widget build(BuildContext context) {
    final room = widget.room;
    final ds = dealerState(widget.events, room.settings);
    final k = instantKinds[_kind]!;
    final fd = _fromDeal && k.fromDeal;
    List<int>? d;
    if (_player != null) d = instantDeltas(player: _player!, kind: _kind, fromDeal: fd, amounts: room.settings.payouts);
    return ListView(padding: const EdgeInsets.fromLTRB(16, 0, 16, 24), children: [
      Text('⚡ Immediate payout', style: Theme.of(context).textTheme.titleLarge),
      const SizedBox(height: 12),
      const Text('Receiver'),
      _seatChoice(room, ds, _player, (i) => setState(() => _player = i)),
      const SizedBox(height: 12),
      RadioGroup<String>(
        groupValue: _kind,
        onChanged: (v) => setState(() => _kind = v ?? _kind),
        child: Column(children: [
          for (final e in instantKinds.entries.where((e) => room.settings.payoutKinds.contains(e.key)))
            RadioListTile<String>(
              value: e.key,
              title: Text('${e.value.icon} ${e.value.label}'),
              subtitle: Text('Each opponent pays ${room.settings.payouts[e.key]} · ${e.value.zh}'),
            ),
        ]),
      ),
      if (k.fromDeal) CheckboxListTile(title: const Text('Held from the deal — pays double'), value: _fromDeal, onChanged: (v) => setState(() => _fromDeal = v == true)),
      if (d != null) _preview(context, room, d),
      TextField(controller: _notes, maxLength: 100, decoration: const InputDecoration(labelText: 'Notes (optional)')),
      FilledButton(
        onPressed: d == null
            ? null
            : () async {
                await widget.app.repo.addEvent(
                  room.code,
                  GameEvent(type: 'instant', deltas: d!, createdAt: DateTime.now().millisecondsSinceEpoch, data: {
                    'player': _player,
                    'kind': _kind,
                    'fromDeal': fd,
                    'notes': _notes.text.trim().isEmpty ? null : _notes.text.trim(),
                  }),
                );
                if (context.mounted) {
                  Navigator.pop(context);
                  toast(context, 'Payout recorded');
                }
              },
        child: const Text('✓ Confirm payout'),
      ),
    ]);
  }
}

/* ------------------------------------------------------------------ Manual adjustment */
const adjustReasons = {
  'miscount': 'Miscount correction',
  'penalty': 'Penalty',
  'sidebet': 'Side bet / agreed transfer',
  'other': 'Other (add a note)',
};

Future<void> showAdjustSheet(BuildContext context, Room room, List<GameEvent> events) => _sheet(context, (_) => _AdjustSheet(room: room, app: context.read<AppState>()));

class _AdjustSheet extends StatefulWidget {
  const _AdjustSheet({required this.room, required this.app});
  final Room room;
  final AppState app;
  @override
  State<_AdjustSheet> createState() => _AdjustSheetState();
}

class _AdjustSheetState extends State<_AdjustSheet> {
  final _d = [0, 0, 0, 0];
  String? _reason;
  final _note = TextEditingController();

  @override
  Widget build(BuildContext context) {
    final total = sum(_d);
    final valid = total == 0 && _d.any((x) => x != 0) && _reason != null && (_reason != 'other' || _note.text.trim().isNotEmpty);
    return ListView(padding: const EdgeInsets.fromLTRB(16, 0, 16, 24), children: [
      Text('⚖️ Manual score adjustment', style: Theme.of(context).textTheme.titleLarge),
      Text('Zero-sum enforced: the four values must add up to 0 (now ${sign(total)}).', style: TextStyle(color: total == 0 ? null : Theme.of(context).colorScheme.error)),
      for (var i = 0; i < 4; i++)
        ListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(widget.room.players[i]),
          subtitle: Wrap(spacing: 4, children: [
            for (final n in [-10, -5, -2, 2, 5, 10]) ActionChip(label: Text(sign(n)), onPressed: () => setState(() => _d[i] += n)),
          ]),
          trailing: Text(sign(_d[i]), style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: deltaColor(context, _d[i]))),
        ),
      DropdownButtonFormField<String>(
        initialValue: _reason,
        decoration: const InputDecoration(labelText: 'Reason *'),
        items: [for (final e in adjustReasons.entries) DropdownMenuItem(value: e.key, child: Text(e.value))],
        onChanged: (v) => setState(() => _reason = v),
      ),
      const SizedBox(height: 8),
      TextField(controller: _note, onChanged: (_) => setState(() {}), maxLength: 120, decoration: InputDecoration(labelText: 'Note${_reason == 'other' ? ' *' : ''}')),
      FilledButton(
        onPressed: !valid
            ? null
            : () async {
                try {
                  await widget.app.repo.addEvent(
                    widget.room.code,
                    GameEvent(type: 'adjust', deltas: manualDeltas(_d), createdAt: DateTime.now().millisecondsSinceEpoch, data: {
                      'reason': _reason,
                      'reasonText': adjustReasons[_reason],
                      'note': _note.text.trim().isEmpty ? null : _note.text.trim(),
                    }),
                  );
                  if (context.mounted) {
                    Navigator.pop(context);
                    toast(context, 'Adjustment applied');
                  }
                } catch (e) {
                  if (context.mounted) toast(context, '$e');
                }
              },
        child: const Text('✓ Apply adjustment'),
      ),
    ]);
  }
}

/* ------------------------------------------------------------------ Audit log */
String eventTitle(Room room, GameEvent e) {
  final n = room.players;
  switch (e.type) {
    case 'win':
      final how = e.baoBy != null ? 'pay-all by ${n[e.baoBy!]}' : e.selfDraw ? 'self-draw' : 'from ${n[e.shooter ?? 0]}';
      return '${n[e.winner ?? 0]} wins ${e.tai} Tai ($how)';
    case 'draw':
      return 'Draw round';
    case 'instant':
      return '${n[e.player ?? 0]}: ${instantKinds[e.kind]?.label ?? e.kind}';
    case 'adjust':
      return 'Adjustment: ${e.data['reasonText'] ?? e.data['reason'] ?? ''}';
    default:
      return e.type;
  }
}

Future<void> showAuditLog(BuildContext context, Room room, List<GameEvent> events, bool isHost) => _sheet(context, (_) => _AuditLog(room: room, events: events, isHost: isHost, app: context.read<AppState>()));

class _AuditLog extends StatelessWidget {
  const _AuditLog({required this.room, required this.events, required this.isHost, required this.app});
  final Room room;
  final List<GameEvent> events;
  final bool isHost;
  final AppState app;

  @override
  Widget build(BuildContext context) {
    if (events.isEmpty) return const Padding(padding: EdgeInsets.all(32), child: Center(child: Text('No entries yet.')));
    return ListView(padding: const EdgeInsets.fromLTRB(16, 0, 16, 24), children: [
      Text('📜 Audit log · ${events.length} entries', style: Theme.of(context).textTheme.titleLarge),
      const Text('Append-only: void reverses an entry but keeps it here.'),
      for (var i = events.length - 1; i >= 0; i--)
        Card(
          child: ListTile(
            title: Text('#${i + 1} ${eventTitle(room, events[i])}', style: TextStyle(decoration: events[i].voided ? TextDecoration.lineThrough : null)),
            subtitle: Text([
              DateTime.fromMillisecondsSinceEpoch(events[i].createdAt).toString().substring(0, 16),
              events[i].deltas.map(sign).join(' / '),
              if (events[i].voided) events[i].voidReason == 'edited' ? 'edited (replaced)' : 'voided',
              if (events[i].data['replaces'] != null) 'corrected',
            ].join(' · ')),
            trailing: !isHost || events[i].voidReason == 'edited'
                ? null
                : Row(mainAxisSize: MainAxisSize.min, children: [
                    if (events[i].type == 'win' && !events[i].voided)
                      IconButton(
                        icon: const Icon(Icons.edit),
                        tooltip: 'Edit round',
                        onPressed: () {
                          Navigator.pop(context);
                          showWinSheet(context, room, events, edit: events[i]);
                        },
                      ),
                    TextButton(
                      onPressed: () async {
                        final toVoid = !events[i].voided;
                        if (toVoid && !await confirm(context, 'Void this entry?', 'Its points are reversed. It stays in the log and can be restored.', ok: 'Void', danger: true)) return;
                        await app.repo.setVoided(room.code, events[i].id!, toVoid, reason: toVoid ? 'manual' : null);
                        if (context.mounted) Navigator.pop(context);
                      },
                      child: Text(events[i].voided ? 'Restore' : 'Void'),
                    ),
                  ]),
          ),
        ),
    ]);
  }
}

/* ------------------------------------------------------------------ Host tools / take over */
Future<void> showHostTools(BuildContext context, Room room) => _sheet(context, (_) => _HostTools(room: room, app: context.read<AppState>()));

class _HostTools extends StatelessWidget {
  const _HostTools({required this.room, required this.app});
  final Room room;
  final AppState app;

  @override
  Widget build(BuildContext context) {
    final pin = TextEditingController();
    return ListView(padding: const EdgeInsets.fromLTRB(16, 0, 16, 24), children: [
      Text('Host tools', style: Theme.of(context).textTheme.titleLarge),
      ListTile(
        contentPadding: EdgeInsets.zero,
        leading: const Icon(Icons.share),
        title: Text('Game code ${room.code}'),
        subtitle: const Text('Others open it from Home → "Join or resume with a game code".'),
        trailing: IconButton(
          icon: const Icon(Icons.copy),
          onPressed: () {
            Clipboard.setData(ClipboardData(text: room.code));
            toast(context, 'Code copied');
          },
        ),
      ),
      const Divider(),
      TextField(controller: pin, keyboardType: TextInputType.number, maxLength: 8, decoration: InputDecoration(labelText: room.hasPin ? 'Change host PIN (4–8 digits)' : 'Set a host PIN (4–8 digits)')),
      FilledButton.tonal(
        onPressed: () async {
          if (!RegExp(r'^\d{4,8}$').hasMatch(pin.text)) return toast(context, 'Host PIN must be 4 to 8 digits');
          await app.repo.setHostPin(room.code, pin.text);
          if (context.mounted) {
            Navigator.pop(context);
            toast(context, 'Host PIN saved — others can take over with it');
          }
        },
        child: const Text('Save PIN'),
      ),
      const SizedBox(height: 12),
      OutlinedButton(
        style: OutlinedButton.styleFrom(foregroundColor: Theme.of(context).colorScheme.error),
        onPressed: () async {
          if (await confirm(context, 'End game without a result?', 'The game is cancelled and ignored by rankings.', ok: 'End game', danger: true)) {
            await app.repo.updateRoom(room.code, status: 'cancelled', finishedAt: DateTime.now().millisecondsSinceEpoch);
            if (context.mounted) Navigator.pop(context);
          }
        },
        child: const Text('End / quit game'),
      ),
    ]);
  }
}

Future<void> takeOver(BuildContext context, Room room) async {
  final app = context.read<AppState>();
  final pin = TextEditingController();
  final name = TextEditingController(text: app.myName);
  final ok = await showDialog<bool>(
    context: context,
    builder: (c) => AlertDialog(
      title: const Text('Take over as host'),
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        TextField(controller: name, decoration: const InputDecoration(labelText: 'Your name')),
        const SizedBox(height: 8),
        TextField(controller: pin, obscureText: true, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Host PIN')),
      ]),
      actions: [TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')), FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Take over'))],
    ),
  );
  if (ok != true) return;
  final done = await app.repo.claimHost(room.code, pin.text, name.text.trim());
  if (context.mounted) toast(context, done ? 'You are now the host' : 'Wrong PIN');
}
