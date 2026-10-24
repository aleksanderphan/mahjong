import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';
import '../core/scan.dart';
import '../core/hand.dart';
import '../core/models.dart';
import '../core/rules.dart';
import '../core/scoring.dart';

enum PickerMode { quick, scan, limit, tai }

/// Selection state of the pattern picker; owned by the screen so it can read the result.
class PickerState extends ChangeNotifier {
  PickerMode mode = PickerMode.quick;
  Selection sel = Selection();
  int? directTai;

  void setMode(PickerMode m) {
    mode = m;
    notifyListeners();
  }

  void load({List<PatternUse>? patterns, int? tai}) {
    if (patterns != null && patterns.isNotEmpty) {
      sel = Selection.fromList(patterns);
      mode = sel.limit != null ? PickerMode.limit : PickerMode.quick;
    } else if (tai != null) {
      mode = PickerMode.tai;
      directTai = tai;
    }
    notifyListeners();
  }

  void clear() {
    sel = Selection();
    directTai = null;
    notifyListeners();
  }

  void update(void Function() f) {
    f();
    notifyListeners();
  }

  /// Evaluate with the current mode. In "Tai only" mode there is no pattern list.
  PickerResult result(Rules rules, {bool selfDraw = false, bool sameWind = false}) {
    if (mode == PickerMode.tai) {
      final t = directTai;
      final errors = t == null ? ['Pick the Tai'] : (t < rules.minTai ? ['Below the minimum of ${rules.minTai} Tai — not a valid win.'] : <String>[]);
      return PickerResult(HandResult(const [], t ?? 0, clampTai(t, rules.taiCap), rules.taiCap, basePoints(t ?? 0, rules.taiCap), errors), null);
    }
    final s = mode == PickerMode.limit ? (sel.copy()..base = null) : (sel.copy()..limit = null);
    final r = evaluateHand(s, rules, selfDraw: selfDraw, sameWind: sameWind);
    final list = s.toList().map((p) => p.id == 'sevenPairs' && selfDraw ? const PatternUse('sevenPairsSelf') : p).toList();
    return PickerResult(r, list);
  }
}

class PickerResult {
  final HandResult hand;
  final List<PatternUse>? patterns;
  const PickerResult(this.hand, this.patterns);
}

const _shapes = ['allChow', 'pingHu', 'allPong', 'sevenPairs', 'halfTerminals', 'mixedOrphans', 'pureOrphans'];

class PatternPicker extends StatelessWidget {
  const PatternPicker({super.key, required this.state, required this.rules, this.selfDraw = false, this.sameWind = false, this.allowTaiMode = true, this.scanContext});
  final PickerState state;
  final Rules rules;
  final bool selfDraw, sameWind, allowTaiMode;
  final ScanContext? scanContext;

  @override
  Widget build(BuildContext context) => ListenableBuilder(listenable: state, builder: (context, _) => _body(context));

  Widget _body(BuildContext context) {
    final res = state.result(rules, selfDraw: selfDraw, sameWind: sameWind).hand;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      SegmentedButton<PickerMode>(
        segments: [
          const ButtonSegment(value: PickerMode.quick, label: Text('Quick')),
          if (rules.aiScan) const ButtonSegment(value: PickerMode.scan, label: Text('📷 Scan')),
          const ButtonSegment(value: PickerMode.limit, label: Text('Limit')),
          if (allowTaiMode) const ButtonSegment(value: PickerMode.tai, label: Text('Tai only')),
        ],
        selected: {state.mode},
        onSelectionChanged: (s) => state.setMode(s.first),
      ),
      const SizedBox(height: 12),
      if (state.mode == PickerMode.quick) ..._quick(context),
      if (state.mode == PickerMode.scan) _ScanBox(state: state, rules: rules, ctx: scanContext ?? ScanContext(selfDraw: selfDraw)),
      if (state.mode == PickerMode.limit) ..._limit(context),
      if (state.mode == PickerMode.tai) _taiOnly(context),
      const SizedBox(height: 8),
      _summary(context, res),
    ]);
  }

  String _tai(String id) => '${rules.taiValue(id == 'sevenPairs' && selfDraw ? 'sevenPairsSelf' : id)} Tai';

  Widget _chip(String id, bool on, VoidCallback tap) => FilterChip(
        label: Text('${taiById[id]!.name} · ${_tai(id)}'),
        tooltip: taiById[id]!.desc,
        selected: on,
        onSelected: (_) => tap(),
      );

  List<Widget> _quick(BuildContext context) {
    final s = state.sel;
    return [
      Text('1 · Hand shape', style: Theme.of(context).textTheme.titleSmall),
      Wrap(spacing: 8, children: [
        for (final id in _shapes) _chip(id, s.base == id, () => state.update(() => s.base = s.base == id ? null : id)),
      ]),
      const SizedBox(height: 12),
      Text('2 · Suits', style: Theme.of(context).textTheme.titleSmall),
      Wrap(spacing: 8, children: [
        for (final x in suitItems) _chip(x.id, s.suit == x.id, () => state.update(() => s.suit = s.suit == x.id ? null : x.id)),
      ]),
      const SizedBox(height: 12),
      Text('3 · Bonus tiles & sets', style: Theme.of(context).textTheme.titleSmall),
      ..._bonuses(context),
    ];
  }

  List<Widget> _limit(BuildContext context) {
    final s = state.sel;
    return [
      Text('Limit hands score the Tai cap (${rules.taiCap}). Bonuses can still be added.', style: Theme.of(context).textTheme.bodySmall),
      Wrap(spacing: 8, children: [
        for (final x in limitItems) _chip(x.id, s.limit == x.id, () => state.update(() => s.limit = s.limit == x.id ? null : x.id)),
      ]),
      ExpansionTile(title: const Text('Add bonuses'), children: _bonuses(context)),
    ];
  }

  List<Widget> _bonuses(BuildContext context) {
    final s = state.sel;
    final flags = <Widget>[];
    for (final x in bonusItems) {
      if (x.cat == 'special' && !rules.winCircumstance) continue;
      if (x.input == TaiInput.flag) {
        flags.add(_chip(x.id, s.flags[x.id] == true, () => state.update(() => s.flags[x.id] = !(s.flags[x.id] == true))));
      }
    }
    return [
      Wrap(spacing: 8, children: flags),
      for (final x in bonusItems.where((x) => x.input == TaiInput.count && rules.usesPattern(x.id)))
        ListTile(
          dense: true,
          contentPadding: EdgeInsets.zero,
          title: Text(x.name),
          subtitle: Text('+${rules.taiValue(x.id)} Tai each'),
          trailing: Row(mainAxisSize: MainAxisSize.min, children: [
            IconButton(icon: const Icon(Icons.remove_circle_outline), onPressed: (s.counts[x.id] ?? 0) > 0 ? () => state.update(() => s.counts[x.id] = s.counts[x.id]! - 1) : null),
            Text('${s.counts[x.id] ?? 0}'),
            IconButton(icon: const Icon(Icons.add_circle_outline), onPressed: (s.counts[x.id] ?? 0) < x.max ? () => state.update(() => s.counts[x.id] = (s.counts[x.id] ?? 0) + 1) : null),
          ]),
        ),
    ];
  }

  Widget _taiOnly(BuildContext context) {
    final max = rules.taiCap > 5 ? rules.taiCap : 5;
    return Wrap(spacing: 8, children: [
      for (var t = rules.minTai; t <= max; t++)
        ChoiceChip(label: Text('$t Tai · ${basePoints(t, rules.taiCap)}'), selected: state.directTai == t, onSelected: (_) => state.update(() => state.directTai = t)),
    ]);
  }

  Widget _summary(BuildContext context, HandResult r) => Card(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            if (r.items.isNotEmpty) Text(describeItems(r.items), style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: 6),
            Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: [
              _stat('Actual Tai', '${r.actual}'),
              _stat('Effective', '${r.effective}/${r.cap}'),
              _stat('Base point', '${r.base}'),
            ]),
            if (r.errors.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 8), child: Text(r.errors.join('\n'), style: TextStyle(color: Theme.of(context).colorScheme.error))),
            if (state.sel.toList().isNotEmpty || state.directTai != null) TextButton(onPressed: state.clear, child: const Text('Clear all')),
          ]),
        ),
      );

  Widget _stat(String l, String v) => Column(children: [Text(l, style: const TextStyle(fontSize: 12)), Text(v, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold))]);
}

/// 📷 Photograph the winning hand; Gemini (through the scan-hand Edge Function) fills in the patterns for you to check.
class _ScanBox extends StatefulWidget {
  const _ScanBox({required this.state, required this.rules, required this.ctx});
  final PickerState state;
  final Rules rules;
  final ScanContext ctx;
  @override
  State<_ScanBox> createState() => _ScanBoxState();
}

class _ScanBoxState extends State<_ScanBox> {
  bool _busy = false;
  String? _error;
  ScanResult? _result;
  Uint8List? _preview;

  Future<void> _scan(ImageSource source) async {
    final repo = context.read<AppState>().repo;
    final XFile? file;
    try {
      file = await ImagePicker().pickImage(source: source, maxWidth: 1600, maxHeight: 1600, imageQuality: 85);
    } catch (e) {
      setState(() => _error = 'Could not open the camera: $e');
      return;
    }
    if (file == null) return;
    final bytes = await file.readAsBytes();
    setState(() {
      _busy = true;
      _error = null;
      _result = null;
      _preview = bytes;
    });
    try {
      final text = await repo.scanHand(
        prompt: buildScanPrompt(widget.rules, widget.ctx),
        image: bytes,
        mimeType: 'image/jpeg',
        model: widget.rules.aiModel,
      );
      final r = parseScan(text);
      widget.state.update(() => widget.state.sel = r.selection);
      if (mounted) setState(() => _result = r);
    } catch (e) {
      if (mounted) setState(() => _error = e is ScanError ? e.message : scanErrorMessage(e));
    }
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final repo = context.read<AppState>().repo;
    if (repo.mode != 'cloud') {
      return const Card(child: ListTile(leading: Icon(Icons.cloud_off), title: Text('AI hand scan needs the shared Supabase backend'), subtitle: Text('In demo mode, pick the patterns by hand.')));
    }
    final r = _result;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      if (_preview != null) ClipRRect(borderRadius: BorderRadius.circular(8), child: Image.memory(_preview!, height: 180, fit: BoxFit.cover, width: double.infinity)),
      if (_busy) const Padding(padding: EdgeInsets.all(12), child: Row(children: [SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)), SizedBox(width: 12), Text('Gemini is reading the tiles…')])),
      if (_error != null) Padding(padding: const EdgeInsets.symmetric(vertical: 8), child: Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error))),
      if (r != null)
        Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('✨ AI suggestion applied — ${(r.confidence * 100).round()}% sure', style: const TextStyle(fontWeight: FontWeight.bold)),
              if (r.tiles.isNotEmpty) Wrap(spacing: 4, children: [for (final t in r.tiles) Chip(label: Text(t), visualDensity: VisualDensity.compact)]),
              if (r.notes.isNotEmpty) Text(r.notes),
              for (final w in r.warnings) Text(w, style: Theme.of(context).textTheme.bodySmall),
              const Text('Please check the patterns before confirming — the AI can misread tiles.'),
              TextButton(onPressed: () => widget.state.setMode(r.selection.limit != null ? PickerMode.limit : PickerMode.quick), child: const Text('✏️ Review / change')),
            ]),
          ),
        ),
      const SizedBox(height: 8),
      Row(children: [
        Expanded(child: FilledButton.icon(icon: const Icon(Icons.photo_camera), label: Text(_preview == null ? 'Take photo' : 'Scan again'), onPressed: _busy ? null : () => _scan(ImageSource.camera))),
        const SizedBox(width: 8),
        OutlinedButton.icon(icon: const Icon(Icons.photo_library), label: const Text('Gallery'), onPressed: _busy ? null : () => _scan(ImageSource.gallery)),
      ]),
      const Padding(
        padding: EdgeInsets.only(top: 8),
        child: Text('Lay all tiles flat and face-up in good light, including exposed sets and bonus tiles. The photo is sent to Google Gemini to read the tiles and is not stored.'),
      ),
    ]);
  }
}
