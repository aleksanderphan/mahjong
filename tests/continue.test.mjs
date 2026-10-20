// Run: node tests/continue.test.mjs
import assert from 'node:assert/strict';
import { loadContinuation } from '../js/continue.js';

let n = 0; const t = async (name, fn) => { await fn(); n++; console.log('  ok -', name); };
const win = (winner) => ({ type: 'win', winner, voided: false });
const room = (over = {}) => ({ code: 'A', players: ['Ann', 'Bo', 'Cy', 'Di'], status: 'completed', createdAt: 100, settings: {}, ...over });
const rooms = { A: room({ createdAt: 100 }), B: room({ code: 'B', createdAt: 200 }), C: room({ code: 'C', createdAt: 300, status: 'active' }), D: room({ code: 'D', status: 'cancelled', createdAt: 50 }) };
const events = { A: [win(1), win(2), win(2)], B: [win(0)], C: [win(0)], D: [{ type: 'win', winner: 0, voided: true }] };
const store = { getRoom: async (c) => rooms[c] || null, watchEvents: (c, cb) => { cb(events[c] || []); return () => {}; } };

await t('offers the newest closed game from this phone\'s history', async () => {
  assert.equal((await loadContinuation(store, { codes: ['A', 'B'] })).room.code, 'B');
  assert.equal((await loadContinuation(store, { codes: ['missing', 'A'] })).room.code, 'A'); // unknown codes are skipped
});
await t('nothing to continue while the newest game is still open', async () => {
  assert.equal(await loadContinuation(store, { codes: ['C', 'A', 'B'] }), null);
  assert.equal(await loadContinuation(store, { codes: [] }), null);
});
await t('a given game carries where the wind table stopped', async () => {
  const c = await loadContinuation(store, { code: 'A' });
  assert.deepEqual(c.resume, { dealer: 2, round: 0, streak: 1 }); // Bo won, Cy won, Cy won again
  assert.equal(c.events.length, 3);
});
await t('a game with no rounds played (or a still-open one) cannot be continued', async () => {
  assert.equal(await loadContinuation(store, { code: 'D' }), null); // only a voided win
  assert.equal(await loadContinuation(store, { code: 'C' }), null); // active
});
await t('a failing read does not break the page', async () => {
  const bad = { getRoom: async () => { throw new Error('offline'); }, watchEvents: () => () => {} };
  assert.equal(await loadContinuation(bad, { codes: ['A'] }), null);
  const noEvents = { getRoom: async () => rooms.A, watchEvents: (c, cb, onErr) => { onErr(new Error('denied')); return () => {}; } };
  assert.equal(await loadContinuation(noEvents, { code: 'A' }), null);
});
console.log(`\n${n} tests passed`);
