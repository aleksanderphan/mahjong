// Domain models. `fromJson`/`toJson` use the same camelCase shape as the legacy web app's backup JSON,
// so a backup exported from the old app imports unchanged. `toRow`/`fromRow` map to the Supabase tables.
import 'rules.dart';
import 'scoring.dart';

int? _intOrNull(dynamic v) => v is num ? v.toInt() : (v is String ? int.tryParse(v) : null);
List<T> _list<T>(dynamic v, T Function(dynamic) f) => v is List ? v.map(f).toList() : <T>[];

class Player {
  final String id, name, handle;
  final int createdAt;
  const Player({required this.id, required this.name, this.handle = '', this.createdAt = 0});

  factory Player.fromJson(Map<String, dynamic> j) => Player(
        id: '${j['id']}',
        name: '${j['name'] ?? ''}',
        handle: '${j['handle'] ?? ''}',
        createdAt: _intOrNull(j['createdAt'] ?? j['created_at']) ?? 0,
      );
  Map<String, dynamic> toJson() => {'id': id, 'name': name, 'handle': handle, 'createdAt': createdAt};
  Map<String, dynamic> toRow() => {'id': id, 'name': name, 'handle': handle, 'created_at': createdAt, 'updated_at': DateTime.now().millisecondsSinceEpoch};
}

class PatternUse {
  final String id;
  final int n;
  const PatternUse(this.id, [this.n = 1]);
  Map<String, dynamic> toJson() => {'id': id, 'n': n};
  factory PatternUse.fromJson(dynamic j) => PatternUse('${j['id']}', _intOrNull(j['n']) ?? 1);
}

class GameEvent implements LedgerEntry, DealerEvent {
  @override
  final String? id;
  @override
  final String type; // win | draw | instant | adjust | kong | bonus
  @override
  final List<int> deltas;
  @override
  final bool voided;
  final int createdAt;
  final String? voidReason;

  /// Type-specific fields (winner, shooter, tai, cap, patterns, kind, reason, …).
  final Map<String, dynamic> data;

  const GameEvent({this.id, required this.type, required this.deltas, this.voided = false, required this.createdAt, this.voidReason, this.data = const {}});

  @override
  int? get winner => _intOrNull(data['winner']);
  int? get shooter => _intOrNull(data['shooter']);
  int? get baoBy => _intOrNull(data['baoBy']);
  int? get player => _intOrNull(data['player']);
  bool get selfDraw => data['selfDraw'] == true;
  int get tai => _intOrNull(data['tai']) ?? 0;
  int? get cap => _intOrNull(data['cap']);
  String? get kind => data['kind'] as String?;
  String? get remarks => data['remarks'] as String?;
  List<PatternUse> get patterns => _list(data['patterns'], PatternUse.fromJson);

  GameEvent copyWith({bool? voided, String? voidReason, List<int>? deltas, int? createdAt, Map<String, dynamic>? data}) => GameEvent(
        id: id,
        type: type,
        deltas: deltas ?? this.deltas,
        voided: voided ?? this.voided,
        createdAt: createdAt ?? this.createdAt,
        voidReason: voidReason ?? this.voidReason,
        data: data ?? this.data,
      );

  static const _core = {'id', 'type', 'deltas', 'voided', 'createdAt', 'voidReason', 'voidedAt', 'by'};

  factory GameEvent.fromJson(Map<String, dynamic> j) => GameEvent(
        id: j['id'] as String?,
        type: '${j['type']}',
        deltas: _list(j['deltas'], (x) => (x as num).toInt()),
        voided: j['voided'] == true,
        createdAt: _intOrNull(j['createdAt']) ?? 0,
        voidReason: j['voidReason'] as String?,
        data: {for (final e in j.entries) if (!_core.contains(e.key)) e.key: e.value},
      );

  Map<String, dynamic> toJson() => {
        if (id != null) 'id': id,
        'type': type,
        'deltas': deltas,
        'voided': voided,
        'createdAt': createdAt,
        if (voidReason != null) 'voidReason': voidReason,
        ...data,
      };

  factory GameEvent.fromRow(Map<String, dynamic> r) => GameEvent(
        id: r['id'] as String,
        type: r['type'] as String,
        deltas: _list(r['deltas'], (x) => (x as num).toInt()),
        voided: r['voided'] == true,
        createdAt: _intOrNull(r['created_at']) ?? 0,
        voidReason: r['void_reason'] as String?,
        data: Map<String, dynamic>.from((r['data'] as Map?) ?? const {}),
      );

  Map<String, dynamic> toRow(String roomCode) => {
        if (id != null) 'id': id,
        'room_code': roomCode,
        'type': type,
        'deltas': deltas,
        'voided': voided,
        'void_reason': voidReason,
        'created_at': createdAt,
        'data': data,
      };
}

class Room {
  final String code, name, status;
  final List<String> players, playerIds, handles;
  final Rules settings;
  final String location, notes, scorekeeper, hostName, hostUid;
  final int startingScore, createdAt;
  final int? finishedAt, startedAt;
  final bool hasPin;
  final String? continuesFrom;

  const Room({
    required this.code,
    required this.name,
    required this.players,
    this.playerIds = const ['', '', '', ''],
    this.handles = const ['', '', '', ''],
    this.settings = const Rules(),
    this.status = 'active',
    this.location = '',
    this.notes = '',
    this.scorekeeper = '',
    this.hostName = '',
    this.hostUid = '',
    this.startingScore = 0,
    required this.createdAt,
    this.finishedAt,
    this.startedAt,
    this.hasPin = false,
    this.continuesFrom,
  });

  bool get isClosed => status == 'completed' || status == 'cancelled';

  Room copyWith({String? status, Rules? settings, int? finishedAt, int? startedAt, String? hostUid, String? hostName, bool? hasPin}) => Room(
        code: code,
        name: name,
        players: players,
        playerIds: playerIds,
        handles: handles,
        settings: settings ?? this.settings,
        status: status ?? this.status,
        location: location,
        notes: notes,
        scorekeeper: scorekeeper,
        hostName: hostName ?? this.hostName,
        hostUid: hostUid ?? this.hostUid,
        startingScore: startingScore,
        createdAt: createdAt,
        finishedAt: finishedAt ?? this.finishedAt,
        startedAt: startedAt ?? this.startedAt,
        hasPin: hasPin ?? this.hasPin,
        continuesFrom: continuesFrom,
      );

  static List<String> _four(dynamic v) {
    final l = _list<String>(v, (x) => '${x ?? ''}');
    return [for (var i = 0; i < 4; i++) i < l.length ? l[i] : ''];
  }

  factory Room.fromJson(Map<String, dynamic> j) => Room(
        code: '${j['code']}',
        name: '${j['name'] ?? ''}',
        players: _four(j['players']),
        playerIds: _four(j['playerIds']),
        handles: _four(j['handles']),
        settings: Rules.fromJson(j['settings'] is Map ? Map<String, dynamic>.from(j['settings'] as Map) : null),
        status: '${j['status'] ?? 'active'}',
        location: '${j['location'] ?? ''}',
        notes: '${j['notes'] ?? ''}',
        scorekeeper: '${j['scorekeeper'] ?? ''}',
        hostName: '${j['hostName'] ?? ''}',
        hostUid: '${j['hostUid'] ?? ''}',
        startingScore: _intOrNull(j['startingScore']) ?? 0,
        createdAt: _intOrNull(j['createdAt']) ?? 0,
        finishedAt: _intOrNull(j['finishedAt']),
        startedAt: _intOrNull(j['startedAt']),
        hasPin: j['hasPin'] == true,
        continuesFrom: j['continuesFrom'] as String?,
      );

  Map<String, dynamic> toJson() => {
        'code': code,
        'name': name,
        'players': players,
        'playerIds': playerIds,
        'handles': handles,
        'settings': settings.toJson(),
        'status': status,
        'location': location,
        'notes': notes,
        'scorekeeper': scorekeeper,
        'hostName': hostName,
        'hostUid': hostUid,
        'startingScore': startingScore,
        'createdAt': createdAt,
        if (finishedAt != null) 'finishedAt': finishedAt,
        if (startedAt != null) 'startedAt': startedAt,
        'hasPin': hasPin,
        if (continuesFrom != null) 'continuesFrom': continuesFrom,
      };

  factory Room.fromRow(Map<String, dynamic> r) => Room(
        code: r['code'] as String,
        name: '${r['name'] ?? ''}',
        players: _four(r['players']),
        playerIds: _four(r['player_ids']),
        handles: _four(r['handles']),
        settings: Rules.fromJson(r['settings'] is Map ? Map<String, dynamic>.from(r['settings'] as Map) : null),
        status: '${r['status'] ?? 'active'}',
        location: '${r['location'] ?? ''}',
        notes: '${r['notes'] ?? ''}',
        scorekeeper: '${r['scorekeeper'] ?? ''}',
        hostName: '${r['host_name'] ?? ''}',
        hostUid: '${r['host_uid'] ?? ''}',
        startingScore: _intOrNull(r['starting_score']) ?? 0,
        createdAt: _intOrNull(r['created_at']) ?? 0,
        finishedAt: _intOrNull(r['finished_at']),
        startedAt: _intOrNull(r['started_at']),
        hasPin: r['has_pin'] == true,
        continuesFrom: r['continues_from'] as String?,
      );

  Map<String, dynamic> toRow() => {
        'code': code,
        'name': name,
        'players': players,
        'player_ids': playerIds,
        'handles': handles,
        'settings': settings.toJson(),
        'status': status,
        'location': location,
        'notes': notes,
        'scorekeeper': scorekeeper,
        'host_name': hostName,
        'starting_score': startingScore,
        'created_at': createdAt,
        'finished_at': finishedAt,
        'started_at': startedAt,
        'has_pin': hasPin,
        'continues_from': continuesFrom,
      };
}

/// Everything in the database: used by rankings, backup and the migration import.
class Snapshot {
  final List<Room> rooms;
  final Map<String, List<GameEvent>> eventsByRoom;
  final List<Player> players;
  const Snapshot(this.rooms, this.eventsByRoom, this.players);

  factory Snapshot.fromJson(Map<String, dynamic> j) {
    final evs = <String, List<GameEvent>>{};
    (j['eventsByRoom'] as Map? ?? const {}).forEach((k, v) {
      evs['$k'] = _list(v, (e) => GameEvent.fromJson(Map<String, dynamic>.from(e as Map)));
    });
    return Snapshot(
      _list(j['rooms'], (r) => Room.fromJson(Map<String, dynamic>.from(r as Map))),
      evs,
      _list(j['players'], (p) => Player.fromJson(Map<String, dynamic>.from(p as Map))),
    );
  }

  Map<String, dynamic> toJson() => {
        'rooms': rooms.map((r) => r.toJson()).toList(),
        'eventsByRoom': {for (final e in eventsByRoom.entries) e.key: e.value.map((x) => x.toJson()).toList()},
        'players': players.map((p) => p.toJson()).toList(),
      };
}
