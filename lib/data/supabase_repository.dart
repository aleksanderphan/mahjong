import 'dart:convert';

import 'package:supabase_flutter/supabase_flutter.dart' hide Snapshot;

import '../core/models.dart';
import '../core/rule_diff.dart';
import '../core/rules.dart';
import 'repository.dart';

/// Supabase backend. Tables and RLS are defined in supabase/migrations/0001_init.sql.
class SupabaseRepository implements Repository {
  SupabaseClient get _db => Supabase.instance.client;

  @override
  String get mode => 'cloud';

  @override
  String get uid => _db.auth.currentUser?.id ?? '';

  @override
  Future<void> init() async {
    if (_db.auth.currentSession == null) await _db.auth.signInAnonymously();
  }

  @override
  Future<bool> hasAccess() async => (await _db.rpc('has_access')) == true;

  @override
  Future<bool> unlock(String password) async => (await _db.rpc('unlock_app', params: {'pw': password})) == true;

  @override
  Future<List<Player>> listPlayers() async =>
      (await _db.from('players').select()).map((r) => Player.fromJson({...r, 'createdAt': r['created_at']})).toList();

  @override
  Future<String> savePlayer(Player p) async {
    final id = p.id.isEmpty ? newId('p_') : p.id;
    await _db.from('players').upsert(Player(id: id, name: p.name, handle: p.handle, createdAt: p.createdAt == 0 ? DateTime.now().millisecondsSinceEpoch : p.createdAt).toRow());
    return id;
  }

  @override
  Future<String> createRoom(Room draft) async {
    for (var i = 0; i < 5; i++) {
      final code = randomCode();
      try {
        await _db.from('rooms').insert({
          ...Room.fromJson({...draft.toJson(), 'code': code}).toRow(),
          'host_uid': uid,
          'created_by': uid,
        });
        return code;
      } on PostgrestException catch (e) {
        if (e.code != '23505') rethrow; // 23505 = code already used, try another
      }
    }
    throw StateError('Could not allocate a game code, try again');
  }

  @override
  Future<Room?> getRoom(String code) async {
    final r = await _db.from('rooms').select().eq('code', code).maybeSingle();
    return r == null ? null : Room.fromRow(r);
  }

  @override
  Stream<Room?> watchRoom(String code) =>
      _db.from('rooms').stream(primaryKey: ['code']).eq('code', code).map((rows) => rows.isEmpty ? null : Room.fromRow(rows.first));

  @override
  Stream<List<GameEvent>> watchEvents(String code) => _db
      .from('events')
      .stream(primaryKey: ['id'])
      .eq('room_code', code)
      .order('created_at', ascending: true)
      .map((rows) => rows.map(GameEvent.fromRow).toList());

  @override
  Future<String> addEvent(String code, GameEvent ev) async {
    final row = ev.toRow(code)..['voided'] = false;
    final r = await _db.from('events').insert(row).select('id').single();
    return r['id'] as String;
  }

  @override
  Future<void> setVoided(String code, String id, bool voided, {String? reason}) => _db
      .from('events')
      .update({'voided': voided, 'void_reason': voided ? reason : null, 'voided_at': DateTime.now().millisecondsSinceEpoch})
      .eq('id', id)
      .eq('room_code', code);

  @override
  Future<void> updateRoom(String code, {Rules? settings, String? status, int? finishedAt, int? startedAt, String? hostName}) async {
    final patch = <String, dynamic>{
      if (settings != null) 'settings': settings.toJson(),
      'status': ?status,
      'finished_at': ?finishedAt,
      'started_at': ?startedAt,
      'host_name': ?hostName,
    };
    if (patch.isNotEmpty) await _db.from('rooms').update(patch).eq('code', code);
  }

  @override
  Future<void> setHostPin(String code, String pin) => _db.rpc('set_host_pin', params: {'code': code, 'pin': pin});

  @override
  Future<bool> claimHost(String code, String pin, String name) async =>
      (await _db.rpc('claim_host', params: {'code': code, 'pin': pin, 'name': name})) == true;

  @override
  Future<void> giveHost(String code, String newUid, String name) => _db.rpc('give_host', params: {'code': code, 'new_uid': newUid, 'name': name});

  @override
  Future<Rules?> getHouseRules() async {
    final r = await _db.from('house_rules').select().eq('id', 'house').maybeSingle();
    return r == null ? null : Rules.fromJson(Map<String, dynamic>.from(r['rules'] as Map));
  }

  @override
  Future<void> saveHouseRules(Rules rules, {RuleChange? change}) => _db.from('house_rules').upsert({
        'id': 'house',
        'rules': rules.toJson(),
        if (change != null) 'last_change': change.toJson(),
        'updated_at': DateTime.now().millisecondsSinceEpoch,
      });

  @override
  Stream<RuleChange> watchRuleChanges() => _db
      .from('house_rules')
      .stream(primaryKey: ['id'])
      .where((rows) => rows.isNotEmpty && rows.first['last_change'] is Map)
      .map((rows) => RuleChange.fromJson(Map<String, dynamic>.from(rows.first['last_change'] as Map)));

  @override
  Future<String> scanHand({required String prompt, required List<int> image, required String mimeType, required String model}) async {
    final res = await _db.functions.invoke('scan-hand', body: {'prompt': prompt, 'image': base64Encode(image), 'mimeType': mimeType, 'model': model});
    final data = res.data;
    if (data is Map && data['text'] is String) return data['text'] as String;
    throw StateError(data is Map && data['error'] != null ? '${data['error']}' : 'Empty answer');
  }

  @override
  Future<Snapshot> loadAll() async {
    final res = await Future.wait([
      _db.from('rooms').select(),
      _fetchAllEvents(),
      _db.from('players').select(),
    ]);
    final rooms = (res[0] as List).map((r) => Room.fromRow(Map<String, dynamic>.from(r as Map))).toList();
    final byRoom = <String, List<GameEvent>>{};
    for (final r in res[1] as List) {
      final row = Map<String, dynamic>.from(r as Map);
      (byRoom[row['room_code'] as String] ??= []).add(GameEvent.fromRow(row));
    }
    for (final l in byRoom.values) {
      l.sort((a, b) => a.createdAt - b.createdAt);
    }
    final players = (res[2] as List).map((r) => Player.fromJson({...Map<String, dynamic>.from(r as Map), 'createdAt': r['created_at']})).toList();
    return Snapshot(rooms, byRoom, players);
  }

  /// PostgREST returns at most 1000 rows per request, so page through the events.
  Future<List<Map<String, dynamic>>> _fetchAllEvents() async {
    const page = 1000;
    final out = <Map<String, dynamic>>[];
    for (var from = 0;; from += page) {
      final rows = await _db.from('events').select().order('created_at').order('id').range(from, from + page - 1);
      out.addAll(rows.map((r) => Map<String, dynamic>.from(r)));
      if (rows.length < page) return out;
    }
  }

  @override
  Future<int> importAll(Snapshot data) async {
    var n = 0;
    for (final p in data.players) {
      await _db.from('players').upsert(p.toRow());
      n++;
    }
    final existing = {for (final r in await _db.from('rooms').select('code')) r['code'] as String};
    for (final r in data.rooms) {
      if (existing.contains(r.code)) continue;
      await _db.from('rooms').insert({...r.toRow(), 'host_uid': uid, 'created_by': uid});
      n++;
      final evs = [for (final e in data.eventsByRoom[r.code] ?? const <GameEvent>[]) e.toRow(r.code)];
      for (var i = 0; i < evs.length; i += 200) {
        await _db.from('events').insert(evs.sublist(i, i + 200 > evs.length ? evs.length : i + 200));
      }
      n += evs.length;
    }
    return n;
  }
}
