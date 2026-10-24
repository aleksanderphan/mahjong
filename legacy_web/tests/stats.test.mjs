// Run: node tests/stats.test.mjs
import assert from 'node:assert/strict';
import { winDeltas, kongDeltas } from '../js/scoring.js';
import { computeLeaderboard, rankPlayers, tableGroups, tableBreakdown } from '../js/stats.js';

const ev = (o) => ({ voided: false, createdAt: 1, ...o });
const win = (winner, shooter, tai, selfDraw = false) =>
  ev({ type: 'win', winner, shooter: selfDraw ? null : shooter, selfDraw, tai, deltas: winDeltas({ winner, shooter, selfDraw, tai }) });

const rooms = [
  { code: 'AAA', players: ['William', 'Mei', 'Hock', 'Lan'], createdAt: 1 },
  { code: 'BBB', players: ['mei', 'william ', 'Ah Kow', 'Lan'], createdAt: 2 },
  { code: 'CCC', players: ['A', 'B', 'C', 'D'], createdAt: 3 }, // empty -> skipped
];
const events = {
  AAA: [win(0, 1, 3), win(2, null, 5, true), ev({ type: 'kong', player: 3, kind: 'concealed', deltas: kongDeltas({ player: 3, kind: 'concealed' }) }),
        { ...win(1, 0, 5), voided: true }, ev({ type: 'draw', deltas: [0, 0, 0, 0] })],
  BBB: [win(1, 0, 2), win(1, 2, 1)],
  CCC: [],
};

const lb = computeLeaderboard(rooms, events);
const by = Object.fromEntries(lb.map((p) => [p.key.replace(/^name:/, ''), p]));
let n = 0; const t = (name, fn) => { fn(); n++; console.log('  ok -', name); };

t('names merged case-insensitively, empty tables skipped', () => {
  assert.equal(lb.length, 5);
  assert.equal(by.william.tables, 2);
  assert.equal(by.mei.tables, 2);
  assert.ok(!by.a);
});
t('points sum across tables and stay zero-sum', () => {
  // AAA: William +32 -64 -2 = -34 ; BBB: william wins 2tai (+16 from mei 8.. ) compute via deltas
  const total = lb.reduce((s, p) => s + p.points, 0);
  assert.equal(total, 0);
  assert.equal(by.william.points, 32 - 64 - 2 + 16 + 8);
});
t('wins, self-draws, shots, kongs, limit hands, voided ignored', () => {
  assert.equal(by.william.wins, 3);
  assert.equal(by.hock.selfDraws, 1);
  assert.equal(by.hock.limitHands, 1);
  assert.equal(by.mei.shots, 2);        // shot in AAA (to William) + BBB (seat0 = mei)
  assert.equal(by.lan.kongs, 1);
  assert.equal(by.mei.wins, 0);          // voided win not counted
});
t('hands and rates', () => {
  assert.equal(by.william.hands, 3 + 2); // AAA: 2 wins + 1 draw (voided excluded); BBB: 2
  assert.equal(by.william.winRate, 3 / 5);
});
t('ranking with ties', () => {
  const r = rankPlayers(lb, 'points');
  for (let i = 1; i < r.length; i++) assert.ok(r[i - 1].points >= r[i].points);
  const tie = rankPlayers([{ name: 'x', points: 5 }, { name: 'y', points: 5 }, { name: 'z', points: 1 }], 'points');
  assert.deepEqual(tie.map((p) => p.rank), [1, 1, 3]);
});
// ----- tables: the same four players, any seat order -----
const T = [
  { code: 'T1', players: ['Ann', 'Bo', 'Cy', 'Di'], createdAt: 10 },
  { code: 'T2', players: ['di', 'Cy', ' ann', 'Bo'], createdAt: 20 },          // same four, other seats, other spelling
  { code: 'T3', players: ['Ann', 'Bo', 'Cy', 'Ed'], createdAt: 30 },          // a different table
  { code: 'T4', players: ['Ann', 'Bo', 'Cy', 'Di'], createdAt: 40, status: 'cancelled' },
  { code: 'T5', players: ['Ann', 'Bo', 'Cy', 'Di'], createdAt: 50 },          // nothing played
];
const TE = {
  T1: [win(0, 1, 3)],                       // Ann wins off Bo
  T2: [win(3, null, 2, true)],              // seat 3 = Bo wins by self-draw
  T3: [win(1, 0, 4)],
  T4: [win(0, 1, 3)],
  T5: [],
};
const groups = tableGroups(T, TE);
t('tables group the same four players in any seat order; cancelled and empty games do not count', () => {
  assert.equal(groups.length, 2);
  assert.deepEqual(groups.map((g) => g.rooms.map((r) => r.code)), [['T3'], ['T2', 'T1']]);   // most recently played table first, newest game first
  assert.deepEqual(groups.map((g) => g.games), [1, 2]);
  assert.deepEqual(groups[1].players, ['di', 'Cy', 'ann', 'Bo']);                              // seats of the newest game
});
t('a table ranks its four players on their points together', () => {
  const board = rankPlayers(computeLeaderboard(groups[1].rooms, TE, []), 'points');
  assert.equal(board.length, 4);
  assert.equal(board.reduce((s, p) => s + p.points, 0), 0);
  assert.ok(board.every((p) => p.games === 2));
});
t('game by game breakdown adds up to the same totals', () => {
  const g = groups[1];
  const b = tableBreakdown(g, TE);
  assert.deepEqual(b.rows.map((r) => r.code), ['T2', 'T1']);
  const board = Object.fromEntries(computeLeaderboard(g.rooms, TE, []).map((p) => [p.key, p.points]));
  for (const c of b.columns) assert.equal(c.total, board[c.key]);                              // same numbers as the ranking
  for (const r of b.rows) assert.equal(Object.values(r.nets).reduce((s, x) => s + x, 0), 0);  // every game is zero-sum
  for (let i = 1; i < b.columns.length; i++) assert.ok(b.columns[i - 1].total >= b.columns[i].total);
});
t('directory ids keep a renamed player in the same table', () => {
  const r = [{ code: 'X1', players: ['Ann', 'Bo', 'Cy', 'Di'], playerIds: ['1', '2', '3', '4'], createdAt: 1 }, { code: 'X2', players: ['Annie', 'Bo', 'Cy', 'Di'], playerIds: ['1', '2', '3', '4'], createdAt: 2 }];
  assert.equal(tableGroups(r, { X1: [win(0, 1, 2)], X2: [win(1, 0, 2)] }).length, 1);
});
console.log(`\n${n} tests passed`);
