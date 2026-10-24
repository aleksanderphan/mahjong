import 'dart:async';
import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../core/models.dart';
import '../core/rule_diff.dart';
import '../core/rules.dart';
import 'repository.dart';

/// On-device backend for demo mode (no Supabase configured) and tests. Data lives in SharedPreferences.
class LocalRepository implements Repository {
  LocalRepository({this.persist = true});
  final bool persist;

  static const _key = 'mjsg-demo-db';
  final _rooms = <String, Room>{};
  final _events = <String, List<GameEvent>>{};
  final _players = <String, Player>{};
  Rules? _house;
  final _changes = StreamController<void>.broadcast();
  SharedPreferences? _prefs;
  final String _uid = 'local-user';

  @override
  String get mode => 'demo';
  @override
  String get uid => _uid;

  @override
  Future<void> init() async {
    if (!persist) return;
    _prefs = await SharedPreferences.getInstance();
    final raw = _prefs!.getString(_key);
    if (raw == null) return;
    try {
      final j = jsonDecode(raw) as Map<String, dynamic>;
      final snap = Snapshot.fromJson(j);
      for (final r in snap.rooms) {
        _rooms[r.code] = r;
      }
      snap.eventsByRoom.forEach((k, v) => _events[k] = [...v]);
      for (final p in snap.players) {
        _players[p.id] = p;
      }
      if (j['house'] is Map) _house = Rules.fromJson(Map<String, dynamic>.from(j['house'] as Map));
    } catch (_) {/* corrupt data: start empty */}
  }

  void _save() {
    _changes.add(null);
    if (!persist) return;
    final j = Snapshot(_rooms.values.toList(), _events, _players.values.toList()).toJson();
    if (_house != null) j['house'] = _house!.toJson();
    _prefs?.setString(_key, jsonEncode(j));
  }

  @override
  Future<bool> hasAccess() async => true;
  @override
  Future<bool> unlock(String password) async => true;

  @override
  Future<List<Player>> listPlayers() async => _players.values.toList();

  @override
  Future<String> savePlayer(Player p) async {
    final id = p.id.isEmpty ? newId('p_') : p.id;
    _players[id] = Player(id: id, name: p.name, handle: p.handle, createdAt: p.createdAt == 0 ? DateTime.now().millisecondsSinceEpoch : p.createdAt);
    _save();
    return id;
  }

  @override
  Future<String> createRoom(Room draft) async {
    String code;
    do {
      code = randomCode();
    } while (_rooms.containsKey(code));
    _rooms[code] = Room.fromJson({...draft.toJson(), 'code': code, 'hostUid': _uid});
    _events[code] = [];
    _save();
    return code;
  }

  @override
  Future<Room?> getRoom(String code) async => _rooms[code];

  Stream<T> _watch<T>(T Function() read) async* {
    yield read();
    yield* _changes.stream.map((_) => read());
  }

  @override
  Stream<Room?> watchRoom(String code) => _watch(() => _rooms[code]);

  @override
  Stream<List<GameEvent>> watchEvents(String code) => _watch(() => [...(_events[code] ?? const <GameEvent>[])]);

  @override
  Future<String> addEvent(String code, GameEvent ev) async {
    final id = ev.id ?? newId('e_');
    final list = _events.putIfAbsent(code, () => []);
    list.add(GameEvent(id: id, type: ev.type, deltas: ev.deltas, createdAt: ev.createdAt == 0 ? DateTime.now().millisecondsSinceEpoch : ev.createdAt, data: ev.data));
    list.sort((a, b) => a.createdAt - b.createdAt);
    _save();
    return id;
  }

  @override
  Future<void> setVoided(String code, String id, bool voided, {String? reason}) async {
    final list = _events[code];
    if (list == null) return;
    final i = list.indexWhere((e) => e.id == id);
    if (i >= 0) list[i] = list[i].copyWith(voided: voided, voidReason: voided ? reason : null);
    _save();
  }

  @override
  Future<void> updateRoom(String code, {Rules? settings, String? status, int? finishedAt, int? startedAt, String? hostName}) async {
    final r = _rooms[code];
    if (r == null) return;
    _rooms[code] = r.copyWith(settings: settings, status: status, finishedAt: finishedAt, startedAt: startedAt, hostName: hostName);
    _save();
  }

  final _pins = <String, String>{};
  @override
  Future<void> setHostPin(String code, String pin) async {
    _pins[code] = pin;
    _rooms[code] = _rooms[code]!.copyWith(hasPin: true);
    _save();
  }

  @override
  Future<bool> claimHost(String code, String pin, String name) async => _pins[code] == pin;
  @override
  Future<void> giveHost(String code, String newUid, String name) async {
    _rooms[code] = _rooms[code]!.copyWith(hostUid: newUid, hostName: name);
    _save();
  }

  @override
  Future<Rules?> getHouseRules() async => _house;
  @override
  Future<void> saveHouseRules(Rules rules, {RuleChange? change}) async {
    _house = rules;
    _save();
  }

  @override
  Stream<RuleChange> watchRuleChanges() => const Stream.empty();

  @override
  Future<String> scanHand({required String prompt, required List<int> image, required String mimeType, required String model}) =>
      throw UnsupportedError('The AI hand scan needs the shared Supabase backend.');

  @override
  Future<Snapshot> loadAll() async => Snapshot(_rooms.values.toList(), {for (final e in _events.entries) e.key: [...e.value]}, _players.values.toList());

  @override
  Future<int> importAll(Snapshot data) async {
    var n = 0;
    for (final p in data.players) {
      _players[p.id] = p;
      n++;
    }
    for (final r in data.rooms) {
      if (_rooms.containsKey(r.code)) continue;
      _rooms[r.code] = r;
      _events[r.code] = [...(data.eventsByRoom[r.code] ?? const <GameEvent>[])];
      n += 1 + _events[r.code]!.length;
    }
    _save();
    return n;
  }
}
