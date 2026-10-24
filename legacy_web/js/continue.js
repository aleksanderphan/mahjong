// Continue a closed table: work out where the wind table stopped (dealer, round wind, dealer streak) so a new game can pick it up.
// Pure helpers + one loader; no DOM.
import { dealerState, WIND_NAMES } from './rules.js';

export const CLOSED = ['completed', 'cancelled'];
const played = (events = []) => events.filter((e) => !e.voided && (e.type === 'win' || e.type === 'draw')).length;

/** Where the wind table stopped: { dealer, round, streak }. null when the game did not track a dealer or no round was played. */
export function tableResume(room, events = []) {
  if (!played(events)) return null;
  const ds = dealerState(events, room.settings || {});
  return ds.enabled ? { dealer: ds.dealer, round: ds.round, streak: ds.streak } : null;
}

const norm = (s) => String(s || '').trim().toLowerCase();
/** Are these exactly the same four players (names, any seat order)? */
export const samePlayers = (a = [], b = []) => a.length === 4 && b.length === 4 && a.every(Boolean) && b.every(Boolean) && a.map(norm).sort().join('|') === b.map(norm).sort().join('|');

/** The newest game (any status) these four players played together, or null. */
export function latestRoomWith(rooms, names) {
  return rooms.filter((r) => samePlayers(r.players, names)).sort((a, b) => (b.createdAt || 0) - (a.createdAt || 0))[0] || null;
}

/**
 * The wind table only carries over to the same four players. The dealer is a person, so if they sit in another seat this time
 * the dealer moves with them. Returns the resume for the new seats, or null when the four players are not the same.
 */
export function resumeForSeats(resume, prevPlayers, names) {
  if (!resume || !samePlayers(prevPlayers, names)) return null;
  const dealer = names.findIndex((n) => norm(n) === norm(prevPlayers[resume.dealer]));
  return dealer < 0 ? null : { ...resume, dealer };
}

/** "South round · dealer Cara (连+1)" */
export function resumeText(resume, players) {
  return `${WIND_NAMES[resume.round]} round · dealer ${players[resume.dealer]}${resume.streak ? ` (连+${resume.streak})` : ''}`;
}

/** Same four players in the same seats: roster ids for each seat (null if someone is no longer in the player list). */
export function seatsFor(room, roster) {
  return room.players.map((name, i) => {
    const id = room.playerIds?.[i];
    return (id && roster.some((p) => p.id === id) ? id : roster.find((p) => p.name === name)?.id) || null;
  });
}

/**
 * The closed game to offer. With `code` that game; otherwise the newest of the games opened on this phone (`codes`).
 * Only a game that is closed and had rounds played qualifies; if the newest one is still open there is nothing to continue.
 * Reads a handful of documents, not the whole database. Returns { room, events, resume } or null.
 */
export async function loadContinuation(store, { code = '', codes = [] } = {}) {
  const list = code ? [code] : codes.slice(0, 5);
  const rooms = (await Promise.all(list.map((c) => store.getRoom(c).catch(() => null)))).filter(Boolean);
  const room = rooms.sort((a, b) => (b.createdAt || 0) - (a.createdAt || 0))[0];
  if (!room || !CLOSED.includes(room.status)) return null;
  const events = await new Promise((res) => {
    const un = store.watchEvents(room.code, (evs) => { res(evs); setTimeout(() => un && un(), 0); }, () => res([]));
  });
  return played(events) ? { room, events, resume: tableResume(room, events) } : null;
}
