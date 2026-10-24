import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';

import '../app_state.dart';
import '../core/models.dart';
import '../core/rules.dart';
import '../core/scoring.dart';
import 'scoring_screen.dart';
import 'theme.dart';

class MoreScreen extends StatelessWidget {
  const MoreScreen({super.key});

  @override
  Widget build(BuildContext context) => ListView(padding: const EdgeInsets.all(16), children: [
        Text('More', style: Theme.of(context).textTheme.headlineSmall),
        _tile(context, Icons.tune, 'House rules', 'Min Tai, cap, dealer, payouts, Tai per pattern', const HouseRulesScreen()),
        _tile(context, Icons.menu_book, 'Scoring guide', 'Tai → points chart, who pays whom, patterns with sample hands', const ScoringScreen()),
        _tile(context, Icons.backup, 'Backup & import', 'Export JSON, import from the old web app', const BackupScreen()),
        const AboutListTile(applicationName: 'Mahjong SG Tracker', applicationLegalese: 'Singapore / SEA mahjong scorekeeper', icon: Icon(Icons.info_outline)),
      ]);

  Widget _tile(BuildContext c, IconData i, String t, String s, Widget page) =>
      Card(child: ListTile(leading: Icon(i), title: Text(t), subtitle: Text(s), trailing: const Icon(Icons.chevron_right), onTap: () => Navigator.push(c, MaterialPageRoute(builder: (_) => page))));
}

/* ------------------------------------------------------------------ House rules */
class HouseRulesScreen extends StatefulWidget {
  const HouseRulesScreen({super.key});
  @override
  State<HouseRulesScreen> createState() => _HouseRulesScreenState();
}

class _HouseRulesScreenState extends State<HouseRulesScreen> {
  late Rules _r = context.read<AppState>().house;

  Widget _stepper(String label, int value, int min, int max, void Function(int) set, {String? sub}) => ListTile(
        title: Text(label),
        subtitle: sub == null ? null : Text(sub),
        trailing: Row(mainAxisSize: MainAxisSize.min, children: [
          IconButton(icon: const Icon(Icons.remove_circle_outline), onPressed: value > min ? () => setState(() => set(value - 1)) : null),
          Text('$value', style: const TextStyle(fontSize: 18)),
          IconButton(icon: const Icon(Icons.add_circle_outline), onPressed: value < max ? () => setState(() => set(value + 1)) : null),
        ]),
      );

  @override
  Widget build(BuildContext context) {
    final p = _r.payouts;
    return Scaffold(
      appBar: AppBar(title: const Text('House rules'), actions: [
        TextButton(
          onPressed: () async {
            await context.read<AppState>().saveHouse(_r);
            if (context.mounted) {
              toast(context, 'Rules saved');
              Navigator.pop(context);
            }
          },
          child: const Text('Save'),
        ),
      ]),
      body: ListView(children: [
        _stepper('Minimum Tai to win', _r.minTai, 0, 5, (v) => _r = _r.copyWith(minTai: v)),
        ListTile(
          title: const Text('Tai cap'),
          subtitle: const Text('Base = 2^min(Tai, cap)'),
          trailing: DropdownButton<int>(
            value: capOptions.contains(_r.taiCap) ? _r.taiCap : kMaxTai,
            items: [for (final c in capOptions) DropdownMenuItem(value: c, child: Text(c == noCap ? 'No cap' : '$c'))],
            onChanged: (v) => setState(() => _r = _r.copyWith(taiCap: v)),
          ),
        ),
        SwitchListTile(title: const Text('Special-win Tai'), subtitle: const Text('Kong replacement, last tile, robbing the kong'), value: _r.winCircumstance, onChanged: (v) => setState(() => _r = _r.copyWith(winCircumstance: v))),
        ListTile(
          title: const Text('Seat wind = prevailing wind'),
          trailing: SegmentedButton<String>(segments: const [ButtonSegment(value: '2x', label: Text('2×')), ButtonSegment(value: '1x', label: Text('1×'))], selected: {_r.doubleWind}, onSelectionChanged: (s) => setState(() => _r = _r.copyWith(doubleWind: s.first))),
        ),
        SwitchListTile(title: const Text('Track dealer 庄'), subtitle: const Text('Dealer wins → stays (连庄), else rotates'), value: _r.autoDealer, onChanged: (v) => setState(() => _r = _r.copyWith(autoDealer: v))),
        ListTile(
          title: const Text('On a draw'),
          trailing: SegmentedButton<String>(segments: const [ButtonSegment(value: 'stay', label: Text('Stay')), ButtonSegment(value: 'rotate', label: Text('Rotate'))], selected: {_r.drawRule}, onSelectionChanged: (s) => setState(() => _r = _r.copyWith(drawRule: s.first))),
        ),
        ListTile(
          title: const Text('Score label'),
          trailing: DropdownButton<String>(value: _r.scoreLabel, items: [for (final e in scoreLabels.entries) DropdownMenuItem(value: e.key, child: Text(e.value))], onChanged: (v) => setState(() => _r = _r.copyWith(scoreLabel: v))),
        ),
        SwitchListTile(
          title: const Text('Set includes animal tiles 🐱🐭🐓🐛'),
          subtitle: const Text('Singapore / Malaysia sets only. Off for a standard Chinese set: hides animal Tai and payouts.'),
          value: _r.animals,
          onChanged: (v) => setState(() => _r = _r.copyWith(animals: v)),
        ),
        const Divider(),
        const Padding(padding: EdgeInsets.all(16), child: Text('Instant payouts (each opponent pays)', style: TextStyle(fontWeight: FontWeight.bold))),
        for (final e in instantKinds.entries.where((e) => _r.payoutKinds.contains(e.key))) _stepper(e.value.label, p[e.key]!, 0, 99, (v) => _r = _r.copyWith(payouts: {...p, e.key: v}), sub: e.value.zh),
        _stepper('Pay-all multiplier 包赔', _r.baoMultiplier, 1, 12, (v) => _r = _r.copyWith(baoMultiplier: v), sub: 'Responsible player pays N × base alone'),
        SwitchListTile(
          title: const Text('📷 AI hand scan'),
          subtitle: const Text('Photograph the winning hand in Record win / Score'),
          value: _r.aiScan,
          onChanged: (v) => setState(() => _r = _r.copyWith(aiScan: v)),
        ),
        if (_r.aiScan)
          ListTile(
            title: const Text('AI model'),
            trailing: DropdownButton<String>(
              value: aiModels.containsKey(_r.aiModel) ? _r.aiModel : defaultAiModel,
              items: [for (final e in aiModels.entries) DropdownMenuItem(value: e.key, child: Text(e.value))],
              onChanged: (v) => setState(() => _r = _r.copyWith(aiModel: v)),
            ),
          ),
        const Divider(),
        ListTile(
          title: const Text('Tai per pattern'),
          subtitle: Text('${_r.tai.length} changed from the defaults'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () async {
            final t = await Navigator.push<Map<String, int>>(context, MaterialPageRoute(builder: (_) => _TaiValues(initial: _r.tai, animals: _r.animals)));
            if (t != null) setState(() => _r = _r.copyWith(tai: t));
          },
        ),
        TextButton(onPressed: () => setState(() => _r = const Rules()), child: const Text('Reset to Singapore defaults')),
        const SizedBox(height: 24),
      ]),
    );
  }
}

class _TaiValues extends StatefulWidget {
  const _TaiValues({required this.initial, required this.animals});
  final Map<String, int> initial;
  final bool animals;
  @override
  State<_TaiValues> createState() => _TaiValuesState();
}

class _TaiValuesState extends State<_TaiValues> {
  late final Map<String, int> _t = {...widget.initial};

  @override
  Widget build(BuildContext context) => PopScope(
        canPop: false,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop) Navigator.pop(context, _t);
        },
        child: Scaffold(
          appBar: AppBar(title: const Text('Tai per pattern')),
          body: ListView(children: [
            for (final x in taiCatalog.where((x) => Rules(animals: widget.animals).usesPattern(x.id)))
              ListTile(
                title: Text(x.name),
                subtitle: Text(x.zh),
                trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                  IconButton(icon: const Icon(Icons.remove_circle_outline), onPressed: (_t[x.id] ?? x.def) > 0 ? () => setState(() => _set(x, (_t[x.id] ?? x.def) - 1)) : null),
                  Text('${_t[x.id] ?? x.def}', style: TextStyle(fontSize: 18, fontWeight: _t.containsKey(x.id) ? FontWeight.bold : null)),
                  IconButton(icon: const Icon(Icons.add_circle_outline), onPressed: (_t[x.id] ?? x.def) < 13 ? () => setState(() => _set(x, (_t[x.id] ?? x.def) + 1)) : null),
                ]),
              ),
          ]),
        ),
      );

  void _set(TaiItem x, int v) => v == x.def ? _t.remove(x.id) : _t[x.id] = v;
}

/* ------------------------------------------------------------------ Backup / import */
class BackupScreen extends StatefulWidget {
  const BackupScreen({super.key});
  @override
  State<BackupScreen> createState() => _BackupScreenState();
}

class _BackupScreenState extends State<BackupScreen> {
  final _text = TextEditingController();
  bool _busy = false;

  Future<void> _export({required bool share}) async {
    final snap = await context.read<AppState>().snapshot(force: true);
    final json = const JsonEncoder.withIndent('  ').convert(snap.toJson());
    if (share) {
      await SharePlus.instance.share(ShareParams(text: json, subject: 'Mahjong backup'));
    } else {
      await Clipboard.setData(ClipboardData(text: json));
      if (mounted) toast(context, 'Backup copied (${snap.rooms.length} games, ${snap.players.length} players)');
    }
  }

  Future<void> _import() async {
    final app = context.read<AppState>();
    setState(() => _busy = true);
    try {
      final snap = Snapshot.fromJson(jsonDecode(_text.text) as Map<String, dynamic>);
      final n = await app.repo.importAll(snap);
      await app.refreshRoster();
      if (mounted) toast(context, 'Imported $n records (existing games are skipped)');
    } catch (e) {
      if (mounted) toast(context, 'Import failed: $e');
    }
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Backup & import')),
        body: ListView(padding: const EdgeInsets.all(16), children: [
          const Text('Export everything as JSON. The same format is what the old web app exported, so you can import its backup here (merge: games that already exist are skipped).'),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(child: FilledButton.tonalIcon(icon: const Icon(Icons.copy), label: const Text('Copy JSON'), onPressed: () => _export(share: false))),
            const SizedBox(width: 8),
            Expanded(child: FilledButton.tonalIcon(icon: const Icon(Icons.share), label: const Text('Share'), onPressed: () => _export(share: true))),
          ]),
          const Divider(height: 32),
          TextField(controller: _text, minLines: 6, maxLines: 12, decoration: const InputDecoration(labelText: 'Paste backup JSON here')),
          const SizedBox(height: 12),
          FilledButton(onPressed: _busy ? null : _import, child: Text(_busy ? 'Importing…' : 'Import (merge)')),
        ]),
      );
}
