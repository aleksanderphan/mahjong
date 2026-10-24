// Continue a closed table: work out where the wind table stopped (dealer, round wind, dealer streak).
import 'models.dart';
import 'rules.dart';

int _played(List<GameEvent> events) => events.where((e) => !e.voided && (e.type == 'win' || e.type == 'draw')).length;

/// Where the wind table stopped. null when the game did not track a dealer or no round was played.
Resume? tableResume(Room room, List<GameEvent> events) {
  if (_played(events) == 0) return null;
  final ds = dealerState(events, room.settings);
  return ds.enabled ? Resume(ds.dealer, ds.round, ds.streak) : null;
}

String _norm(String? s) => (s ?? '').trim().toLowerCase();

/// Are these exactly the same four players (names, any seat order)?
bool samePlayers(List<String> a, List<String> b) {
  if (a.length != 4 || b.length != 4 || a.any((x) => x.isEmpty) || b.any((x) => x.isEmpty)) return false;
  final x = a.map(_norm).toList()..sort();
  final y = b.map(_norm).toList()..sort();
  return x.join('|') == y.join('|');
}

/// The newest game (any status) these four players played together, or null.
Room? latestRoomWith(List<Room> rooms, List<String> names) {
  final m = rooms.where((r) => samePlayers(r.players, names)).toList()..sort((a, b) => b.createdAt - a.createdAt);
  return m.isEmpty ? null : m.first;
}

/// The wind table only carries over to the same four players. The dealer is a person, so if they sit
/// in another seat this time the dealer moves with them. Null when the four players are not the same.
Resume? resumeForSeats(Resume? resume, List<String> prevPlayers, List<String> names) {
  if (resume == null || !samePlayers(prevPlayers, names)) return null;
  final dealer = names.indexWhere((n) => _norm(n) == _norm(prevPlayers[resume.dealer]));
  return dealer < 0 ? null : Resume(dealer, resume.round, resume.streak);
}

/// "South round · dealer Cara (连+1)"
String resumeText(Resume r, List<String> players) =>
    '${windNames[r.round]} round · dealer ${players[r.dealer]}${r.streak > 0 ? ' (连+${r.streak})' : ''}';

/// Same four players in the same seats: roster ids for each seat (null if someone is no longer in the player list).
List<String?> seatsFor(Room room, List<Player> roster) => [
      for (var i = 0; i < 4; i++)
        () {
          final id = room.playerIds[i];
          if (id.isNotEmpty && roster.any((p) => p.id == id)) return id;
          for (final p in roster) {
            if (p.name == room.players[i]) return p.id;
          }
          return null;
        }()
    ];
