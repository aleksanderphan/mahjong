// Gemini hand scan: prompt building and strict parsing of the AI's JSON reply (port of legacy_web/js/scan-core.js).
import 'dart:convert';
import 'dart:math' as math;

import 'hand.dart';
import 'rules.dart';

class ScanContext {
  final String seatWind, roundWind;
  final int? seatNo;
  final bool selfDraw;
  const ScanContext({this.seatWind = '', this.roundWind = '', this.seatNo, this.selfDraw = false});
}

String buildScanPrompt(Rules rules, ScanContext ctx) {
  String line(TaiItem x) => '- ${x.id}: ${x.name} (${x.zh}) — ${x.desc}${x.max > 0 ? ' [count 0-${x.max}]' : ''} = ${rules.taiValue(x.id)} Tai';
  Iterable<TaiItem> pick(TaiInput i) => taiCatalog.where((x) => x.input == i);
  final bonuses = taiCatalog.where((x) => (x.input == TaiInput.flag || x.input == TaiInput.count) && x.cat != 'special' && rules.usesPattern(x.id));
  return '''You are an expert Singapore / SEA mahjong scorer. Look at the photo of a WINNING mahjong hand (14+ tiles, possibly with exposed melds and bonus tiles: flowers, seasons${rules.animals ? ', animals' : ''}).

Context:
- Winner's seat wind: ${ctx.seatWind.isEmpty ? 'unknown' : ctx.seatWind} (seat flower/season number ${ctx.seatNo ?? 'unknown'}: 1=East 梅/春, 2=South 兰/夏, 3=West 菊/秋, 4=North 竹/冬)
- Prevailing (round) wind: ${ctx.roundWind.isEmpty ? 'unknown' : ctx.roundWind}
- Won by: ${ctx.selfDraw ? 'self-draw' : 'discard'}

Step 1: list every tile you can see (e.g. "1 wan", "5 dots", "7 bamboo", "East", "Red dragon", "Plum #1", "Cat").
Step 2: choose the scoring patterns using ONLY these ids.

BASE HAND — pick at most ONE (or null):
${pick(TaiInput.pattern).map(line).join('\n')}
SUIT — at most ONE (or null):
${pick(TaiInput.colour).map(line).join('\n')}
LIMIT HAND — at most ONE (or null); if you pick a limit hand, base and suit must be null:
${pick(TaiInput.limit).map(line).join('\n')}
BONUSES — any number (flags true/false, counts are integers):
${bonuses.map(line).join('\n')}

Rules: only mark seat flower/season if its number matches the winner's seat. Ping Hu requires zero flowers/animals. If a tile is unclear, say so in "notes" and lower "confidence".

Reply with JSON only, exactly this shape:
{"tiles": ["..."], "base": "id or null", "suit": "id or null", "limit": "id or null", "flags": {"id": true}, "counts": {"id": 1}, "confidence": 0.0, "notes": "short explanation"}''';
}

class ScanResult {
  final Selection selection;
  final List<String> tiles, warnings;
  final String notes;
  final double confidence;
  const ScanResult(this.selection, this.tiles, this.notes, this.confidence, this.warnings);
}

class ScanError implements Exception {
  final String message;
  ScanError(this.message);
  @override
  String toString() => message;
}

/// Parse & validate the model reply into a picker selection. Unknown ids are dropped with a warning.
ScanResult parseScan(String? text) {
  var raw = (text ?? '').trim();
  final fence = RegExp(r'```(?:json)?\s*([\s\S]*?)```').firstMatch(raw);
  if (fence != null) raw = fence.group(1)!;
  final start = raw.indexOf('{'), end = raw.lastIndexOf('}');
  if (start < 0 || end < start) throw ScanError('The AI did not return a readable answer. Try another photo.');
  final Map<String, dynamic> obj;
  try {
    obj = jsonDecode(raw.substring(start, end + 1)) as Map<String, dynamic>;
  } catch (_) {
    throw ScanError('The AI answer was not valid JSON. Try again.');
  }
  final warnings = <String>[];
  final sel = Selection();
  String? one(dynamic v, TaiInput input) {
    if (v == null || v == '' || v == 'null') return null;
    final x = taiById['$v'];
    if (x == null || x.input != input) {
      warnings.add('Ignored unknown ${input.name} “$v”');
      return null;
    }
    return '$v';
  }

  sel.base = one(obj['base'] == 'sevenPairsSelf' ? 'sevenPairs' : obj['base'], TaiInput.pattern);
  sel.suit = one(obj['suit'], TaiInput.colour);
  sel.limit = one(obj['limit'], TaiInput.limit);
  if (sel.limit != null) {
    if (sel.base != null || sel.suit != null) warnings.add('Limit hand chosen — base hand and suit removed.');
    sel.base = null;
    sel.suit = null;
  }
  final flags = obj['flags'];
  if (flags is Map) {
    flags.forEach((id, on) {
      if (on != true) return;
      final x = taiById['$id'];
      if (x?.input == TaiInput.flag) {
        sel.flags['$id'] = true;
      } else if (x?.input == TaiInput.count) {
        sel.counts['$id'] = 1;
      } else {
        warnings.add('Ignored unknown bonus “$id”');
      }
    });
  }
  final counts = obj['counts'];
  if (counts is Map) {
    counts.forEach((id, n) {
      final x = taiById['$id'];
      final k = math.max(0, (n is num ? n.floor() : int.tryParse('$n') ?? 0));
      if (k == 0) return;
      if (x?.input == TaiInput.count) {
        sel.counts['$id'] = math.min(x!.max > 0 ? x.max : 9, k);
      } else if (x?.input == TaiInput.flag) {
        sel.flags['$id'] = true;
      } else {
        warnings.add('Ignored unknown bonus “$id”');
      }
    });
  }
  final c = obj['confidence'];
  final conf = (c is num ? c.toDouble() : 0.0).clamp(0.0, 1.0);
  final notes = '${obj['notes'] ?? ''}';
  return ScanResult(
    sel,
    obj['tiles'] is List ? (obj['tiles'] as List).map((t) => '$t').take(30).toList() : const [],
    notes.length > 400 ? notes.substring(0, 400) : notes,
    conf,
    warnings,
  );
}

/// Friendly message for a failed scan call.
String scanErrorMessage(Object err) {
  final m = '$err';
  final detail = ' (Details: ${m.replaceAll(RegExp(r'\s+'), ' ').substring(0, math.min(m.length, 300))})';
  String msg;
  if (RegExp(r'quota|429|RESOURCE_EXHAUSTED', caseSensitive: false).hasMatch(m)) {
    msg = 'The free Gemini limit is used up for now — try again later, or pick the patterns by hand.';
  } else if (RegExp(r'404|NOT_FOUND|is not found|Unknown model', caseSensitive: false).hasMatch(m)) {
    msg = 'The AI model is not available. Choose another model in More → House rules → AI hand scan.';
  } else if (RegExp(r'GEMINI_API_KEY|API key not valid|PERMISSION_DENIED|not configured', caseSensitive: false).hasMatch(m)) {
    msg = 'The scan server is not set up: add the GEMINI_API_KEY secret to the scan-hand Edge Function.';
  } else if (RegExp(r'SocketException|Failed host lookup|ClientException|network|offline', caseSensitive: false).hasMatch(m)) {
    msg = 'Could not reach the scan server — check the internet connection.';
  } else if (RegExp(r'SAFETY|blocked', caseSensitive: false).hasMatch(m)) {
    msg = 'The photo was blocked by the AI safety filter. Try a clearer photo of just the tiles.';
  } else {
    msg = 'Scan failed.';
  }
  return msg + detail;
}
