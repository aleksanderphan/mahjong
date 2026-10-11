// Sample winning hands for the scoring guide, drawn with the same CSS tiles as the simulator.
// Every sample is checked against the scoring engine by the self-test, so a picture can never disagree with the rules.
import { FLOWERS, ANIMALS, THIRTEEN, blankHand, setTiles } from './handcalc.js';
import { tile, bonusTile } from './tileui.js';

const esc = (s) => String(s ?? '').replace(/[&<>"']/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));

// sets: [type, tile] — chow tile = lowest of the run · flowers / seasons: seat numbers 1-4 · animals: cat | mouse | rooster | centipede
const PLAIN = { sets: [['chow', 'm2'], ['chow', 'm5'], ['pong', 'p3'], ['chow', 's6']], pair: 'p8' }; // scores nothing by itself
const RUNS = { sets: [['chow', 'm2'], ['chow', 'm5'], ['chow', 'p3'], ['chow', 's6']], pair: 'p8' };
const RUNS_AND = (set) => ({ sets: [set, ['chow', 'm2'], ['chow', 'p4'], ['chow', 's6']], pair: 's2' });
const SEAT_EAST = { seatWind: 0, roundWind: 1 }; // you sit East, the round is South

export const SAMPLES = {
  chicken: { ...PLAIN, note: 'No pattern and no bonus tile: 0 Tai, not a winning hand.' },
  allChow: { ...RUNS, seasons: [2], note: 'Four runs and a plain pair. Any bonus tile makes it All Chow (1 Tai) instead of Ping Hu.' },
  pingHu: { ...RUNS },
  allPong: { sets: [['pong', 'm3'], ['pong', 'p7'], ['pong', 's5'], ['pong', 'm8']], pair: 'p2' },
  sevenPairs: { kind: 'sevenPairs', pairs: ['m2', 'm5', 'p3', 'p7', 's4', 's8', 'w2'], note: '2 Tai off a discard.' },
  sevenPairsSelf: { kind: 'sevenPairs', pairs: ['m2', 'm5', 'p3', 'p7', 's4', 's8', 'w2'], ctx: { selfDraw: true }, note: 'Same hand, self-drawn: 4 Tai.' },
  halfColour: { sets: [['chow', 's2'], ['chow', 's5'], ['pong', 's8'], ['pong', 'w4']], pair: 's3', note: 'One suit (bamboo) plus a wind.' },
  fullColour: { sets: [['chow', 'p2'], ['chow', 'p3'], ['pong', 'p6'], ['pong', 'p8']], pair: 'p5', note: 'One suit only (dots), no honours.' },
  halfTerminals: { sets: [['pong', 'm1'], ['pong', 'm9'], ['pong', 's1'], ['pong', 'w3']], pair: 'p1' },
  mixedOrphans: { sets: [['chow', 'm1'], ['chow', 'p7'], ['pong', 's9'], ['pong', 'w4']], pair: 'm9' },
  pureOrphans: { sets: [['chow', 'm1'], ['chow', 'm7'], ['chow', 'p7'], ['pong', 's9']], pair: 'p1' },

  pureStraight: { sets: [['chow', 'm1'], ['chow', 'm4'], ['chow', 'm7'], ['pong', 'p5']], pair: 's2' },
  concealed: { ...RUNS, called: false },
  kong: { sets: [['kong', 'p5'], ['chow', 'm2'], ['chow', 'm5'], ['chow', 's6']], pair: 'p8' },
  dragonPung: { ...RUNS_AND(['pong', 'd1']) },
  seatWind: { ...RUNS_AND(['pong', 'w1']), ctx: SEAT_EAST, note: 'You sit East, so a pong of East 東 scores.' },
  roundWind: { ...RUNS_AND(['pong', 'w2']), ctx: SEAT_EAST, note: 'The round is South, so a pong of South 南 scores.' },
  smallWinds: { sets: [['pong', 'w1'], ['pong', 'w2'], ['pong', 'w3'], ['chow', 'm2']], pair: 'w4' },
  smallDragons: { sets: [['pong', 'd1'], ['pong', 'd2'], ['chow', 'm2'], ['chow', 'p5']], pair: 'd3' },

  flower: { ...PLAIN, flowers: [1], note: 'You sit East (1), so Plum 梅 is your flower.' },
  season: { ...PLAIN, seasons: [1], note: 'You sit East (1), so Spring 春 is your season.' },
  flowerSet: { ...PLAIN, flowers: [1, 2, 3, 4] },
  animal: { ...PLAIN, animals: ['cat'] },
  animalPair: { ...PLAIN, animals: ['cat', 'mouse'] },

  bigDragons: { sets: [['pong', 'd1'], ['pong', 'd2'], ['pong', 'd3'], ['chow', 'm2']], pair: 'p5' },
  thirteen: { kind: 'thirteen', thirteenDouble: 'm1' },
  allTerminals: { sets: [['pong', 'm1'], ['pong', 'm9'], ['pong', 'p1'], ['pong', 's9']], pair: 'p9' },
  sevenFlowers: { ...PLAIN, flowers: [1, 2, 3, 4], seasons: [1, 2, 3], ctx: { selfDraw: true } },
  eightFlowers: { kind: 'limit', limit: 'eightFlowers', flowers: [1, 2, 3, 4], seasons: [1, 2, 3, 4] },
  bigWinds: { sets: [['pong', 'w1'], ['pong', 'w2'], ['pong', 'w3'], ['pong', 'w4']], pair: 'm5' },
  nineGates: { sets: [['pong', 'm1'], ['chow', 'm2'], ['chow', 'm5'], ['pong', 'm9']], pair: 'm8', called: false },
  allHonours: { sets: [['pong', 'w1'], ['pong', 'w2'], ['pong', 'd1'], ['pong', 'd2']], pair: 'd3' },
  allKongs: { sets: [['kong', 'm1'], ['kong', 'p2'], ['kong', 's3'], ['kong', 'm9']], pair: 'p5' },
  fourConcealed: { sets: [['pong', 'm1'], ['pong', 'p2'], ['pong', 's3'], ['pong', 'm9']], pair: 'p5', called: false, ctx: { selfDraw: true } },
  pureGreen: { sets: [['chow', 's2'], ['pong', 's6'], ['pong', 's8'], ['pong', 'd2']], pair: 's4' },
};

/** A complete hand in the shape the simulator uses. */
export function sampleHand(id) {
  const { sets, ctx, note, ...rest } = SAMPLES[id];
  return { ...blankHand(), ...rest, ...(sets ? { sets: sets.map(([type, t]) => ({ type, tile: t })) } : {}) };
}
export const sampleCtx = (id) => ({ seatWind: 0, roundWind: 0, ...(SAMPLES[id].ctx || {}) });

/** HTML for a sample hand picture (empty string when a pattern has no picture). */
export function sampleHtml(id) {
  const s = SAMPLES[id]; if (!s) return '';
  const h = sampleHand(id);
  const groups = h.kind === 'normal' ? [...h.sets.map(setTiles), [h.pair, h.pair]]
    : h.kind === 'sevenPairs' ? h.pairs.map((t) => [t, t])
      : h.kind === 'thirteen' ? [[...THIRTEEN, h.thirteenDouble].sort()] : [];
  const bonus = [
    ...FLOWERS.filter((f) => (f.kind === 'flower' ? h.flowers : h.seasons).includes(f.n)).map((f) => bonusTile(f.ch, f.n)),
    ...ANIMALS.filter((a) => h.animals.includes(a.id)).map((a) => `<span class="emo">${a.emoji}</span>`),
  ];
  return `<div class="sample" aria-label="Sample hand">
    ${groups.length ? `<div class="handline">${groups.map((g) => `<span class="grp">${g.map((t) => tile(t)).join('')}</span>`).join('')}</div>` : ''}
    ${bonus.length ? `<div class="handline bonus">${bonus.join('')}</div>` : ''}
    ${s.note ? `<div class="small muted">${esc(s.note)}</div>` : ''}</div>`;
}
