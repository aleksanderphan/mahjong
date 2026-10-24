import 'dart:math';

import '../core/models.dart';
import '../core/rule_diff.dart';
import '../core/rules.dart';

const _alphabet = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
final _rng = Random.secure();

/// 6-character game code without look-alike characters.
String randomCode([int len = 6]) => List.generate(len, (_) => _alphabet[_rng.nextInt(_alphabet.length)]).join();
String newId(String prefix) => prefix + randomCode(12).toLowerCase();

/// Storage backend: Supabase (shared, realtime) or on-device (demo / offline).
abstract class Repository {
  /// 'cloud' or 'demo'.
  String get mode;
  String get uid;

  Future<void> init();

  // App password gate (Supabase: unlock_app RPC).
  Future<bool> hasAccess();
  Future<bool> unlock(String password);

  // Players
  Future<List<Player>> listPlayers();
  Future<String> savePlayer(Player p);

  // Games
  Future<String> createRoom(Room draft);
  Future<Room?> getRoom(String code);
  Stream<Room?> watchRoom(String code);
  Stream<List<GameEvent>> watchEvents(String code);
  Future<String> addEvent(String code, GameEvent ev);
  Future<void> setVoided(String code, String id, bool voided, {String? reason});

  /// Host-only fields: settings, status, finishedAt, startedAt, location, notes, scorekeeper, hostName, hasPin.
  Future<void> updateRoom(String code, {Rules? settings, String? status, int? finishedAt, int? startedAt, String? hostName});

  // Host control
  Future<void> setHostPin(String code, String pin);
  Future<bool> claimHost(String code, String pin, String name);
  Future<void> giveHost(String code, String newUid, String name);

  // House rules (shared)
  Future<Rules?> getHouseRules();
  Future<void> saveHouseRules(Rules rules, {RuleChange? change});

  /// Emits whenever someone saves new house rules (drives "rules changed" notifications).
  Stream<RuleChange> watchRuleChanges();

  /// Ask Gemini (via the scan-hand Edge Function) to read a photo; returns the model's raw JSON text.
  Future<String> scanHand({required String prompt, required List<int> image, required String mimeType, required String model});

  // Whole database (rankings, backup) and merge import (also used to migrate from the old Firebase app).
  Future<Snapshot> loadAll();
  Future<int> importAll(Snapshot data);
}
