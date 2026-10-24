import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'core/models.dart';
import 'core/rule_diff.dart';
import 'core/rules.dart';
import 'data/repository.dart';
import 'notifier.dart';

class AppNotification {
  final String key, title, body;
  final int at;
  bool read;
  AppNotification(this.key, this.title, this.body, this.at, {this.read = false});

  Map<String, dynamic> toJson() => {'key': key, 'title': title, 'body': body, 'at': at, 'read': read};
  factory AppNotification.fromJson(Map<String, dynamic> j) =>
      AppNotification('${j['key']}', '${j['title']}', '${j['body'] ?? ''}', (j['at'] as num?)?.toInt() ?? 0, read: j['read'] == true);
}

/// App-wide state: the repository, shared house rules, the player roster, recent games and notifications on this device.
class AppState extends ChangeNotifier {
  AppState(this.repo, {Notifier? notifier}) : _notifier = notifier ?? Notifier();
  final Repository repo;
  final Notifier _notifier;

  Rules house = const Rules();
  List<Player> roster = [];
  List<String> recent = [];
  List<AppNotification> notifications = [];
  bool unlocked = false;
  bool initialised = false;
  Object? initError;
  String myName = '';

  Snapshot? _cache;
  DateTime? _cacheAt;
  SharedPreferences? _prefs;
  StreamSubscription<RuleChange>? _ruleSub;

  static const _recentKey = 'mjsg-recent';
  static const _nameKey = 'mjsg-my-name';
  static const _notesKey = 'mjsg-notifications';
  static const _lastRuleKey = 'mjsg-last-rule-change';

  int get unread => notifications.where((n) => !n.read).length;

  Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
    recent = _prefs!.getStringList(_recentKey) ?? [];
    myName = _prefs!.getString(_nameKey) ?? '';
    try {
      notifications = (jsonDecode(_prefs!.getString(_notesKey) ?? '[]') as List).map((e) => AppNotification.fromJson(Map<String, dynamic>.from(e as Map))).toList();
    } catch (_) {
      notifications = [];
    }
    try {
      await repo.init();
      unlocked = await repo.hasAccess();
      if (unlocked) await _afterUnlock();
    } catch (e) {
      initError = e;
    }
    initialised = true;
    notifyListeners();
  }

  Future<void> _afterUnlock() async {
    await refresh();
    await _notifier.init();
    _ruleSub?.cancel();
    _ruleSub = repo.watchRuleChanges().listen(_onRuleChange, onError: (Object e) => debugPrint('rule watch: $e'));
  }

  void _onRuleChange(RuleChange c) {
    final seen = _prefs?.getInt(_lastRuleKey) ?? 0;
    if (c.at <= seen) return;
    _prefs?.setInt(_lastRuleKey, c.at);
    if (seen == 0 || c.byName == myName) return; // first run on this device, or my own change
    notify('rules-${c.at}', '⚙️ House rules changed', '${c.byName}: ${c.summary}');
    refresh();
  }

  /// Add to the in-app list and show a phone alert. [key] de-duplicates.
  void notify(String key, String title, String body) {
    if (notifications.any((n) => n.key == key)) return;
    notifications.insert(0, AppNotification(key, title, body, DateTime.now().millisecondsSinceEpoch));
    if (notifications.length > 40) notifications.removeRange(40, notifications.length);
    _saveNotifications();
    _notifier.show(title, body);
    notifyListeners();
  }

  void markAllRead() {
    for (final n in notifications) {
      n.read = true;
    }
    _saveNotifications();
    notifyListeners();
  }

  void clearNotifications() {
    notifications = [];
    _saveNotifications();
    notifyListeners();
  }

  void _saveNotifications() => _prefs?.setString(_notesKey, jsonEncode(notifications.map((n) => n.toJson()).toList()));

  Future<bool> unlock(String password) async {
    final ok = await repo.unlock(password);
    if (ok) {
      unlocked = true;
      await _afterUnlock();
      notifyListeners();
    }
    return ok;
  }

  Future<void> refresh() async {
    house = (await repo.getHouseRules()) ?? const Rules();
    await refreshRoster();
  }

  Future<void> refreshRoster() async {
    roster = (await repo.listPlayers())..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    _cache = null;
    notifyListeners();
  }

  Future<Snapshot> snapshot({bool force = false}) async {
    if (!force && _cache != null && DateTime.now().difference(_cacheAt!) < const Duration(seconds: 30)) return _cache!;
    _cache = await repo.loadAll();
    _cacheAt = DateTime.now();
    return _cache!;
  }

  void invalidate() => _cache = null;

  Future<void> saveHouse(Rules r) async {
    final changes = rulesDiff(house, r);
    final change = changes.isEmpty ? null : RuleChange(DateTime.now().millisecondsSinceEpoch, myName.isEmpty ? 'Someone' : myName, changes.take(6).join(' · '));
    await repo.saveHouseRules(r, change: change);
    if (change != null) _prefs?.setInt(_lastRuleKey, change.at); // don't notify myself
    house = r;
    notifyListeners();
  }

  Future<void> savePlayer(Player p) async {
    await repo.savePlayer(p);
    await refreshRoster();
  }

  void remember(String code) {
    if (recent.isNotEmpty && recent.first == code) return;
    recent = [code, ...recent.where((c) => c != code)].take(20).toList();
    _prefs?.setStringList(_recentKey, recent);
    notifyListeners();
  }

  Future<void> setMyName(String n) async {
    myName = n;
    await _prefs?.setString(_nameKey, n);
  }

  @override
  void dispose() {
    _ruleSub?.cancel();
    super.dispose();
  }
}
