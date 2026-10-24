// Ranking page: player statistics & ranking across games.
import { computeLeaderboard, rankPlayers, SORTS, PERIODS, roomsInPeriod, tableGroups, tableBreakdown } from './stats.js';
import { prefs, unit } from './prefs.js';
import { app, getAll, recent, invalidate } from './data.js';
import { saveRules } from './prefs.js';
import { esc, sign, pct, cls, avatar, confirmBox, toast, fmtDate } from './ui.js';

const PREF_KEY = 'mjsg-lb-prefs';
let ui = { period: 'all', sort: 'points', scope: 'all', view: 'all', table: '' }; // view: 'all' players · 'table' = one table of 4 players
try { ui = { ...ui, ...JSON.parse(localStorage.getItem(PREF_KEY) || '{}') }; if (!PERIODS[ui.period]) ui.period = 'all'; if (!SORTS[ui.sort]) ui.sort = 'points'; if (!['all', 'table'].includes(ui.view)) ui.view = 'all'; } catch {}
const savePrefs = () => { try { localStorage.setItem(PREF_KEY, JSON.stringify(ui)); } catch {} };
const MEDAL = { 1: '🥇', 2: '🥈', 3: '🥉' };

const stat = (label, value, title = '') => `<span class="stat" title="${esc(title)}"><small>${label}</small><b>${value}</b></span>`;

function headline(p) {
  switch (ui.sort) {
    case 'avgPerTable': return sign(p.avgPerTable);
    case 'wins': return `${p.wins}W`;
    case 'winRate': return pct(p.winRate);
    case 'maxTai': return p.maxTai ? `${p.maxTai} Tai` : '–';
    case 'selfDraws': return p.selfDraws;
    case 'payAllWins': return p.payAllWins;
    case 'games': return p.games;
    case 'tableWins': return `${p.tableWins}×`;
    case 'safest': return pct(p.shotRate);
    default: return sign(p.points);
  }
}

export async function renderLeaderboard($app, force = false) {
  $app.innerHTML = '<p class="muted center pad">Loading leaderboard…</p>';
  let d;
  try { d = await getAll(force); } catch (err) {
    $app.innerHTML = `<div class="card"><h2>Couldn't load the leaderboard</h2><p class="muted">${esc(err.message)}</p><p class="small">If this says "permissions", publish the latest <code>firestore.rules</code>.</p></div>`; return;
  }
  const draw = () => {
    const mine = new Set(recent().map((r) => r.code));
    let rooms = roomsInPeriod(d.rooms, d.eventsByRoom, PERIODS[ui.period].since(), prefs.rules.leaderboardResetAt || 0);
    // By table: the games of exactly one set of 4 players, ranked on their points together (default: the table you last played at).
    const byTable = ui.view === 'table';
    const groups = byTable ? tableGroups(rooms, d.eventsByRoom, d.players) : [];
    const sel = byTable ? groups.find((g) => g.key === ui.table) || groups.find((g) => g.rooms.some((r) => mine.has(r.code))) || groups[0] || null : null;
    if (byTable) rooms = sel ? sel.rooms : [];
    else if (ui.scope === 'mine') rooms = rooms.filter((r) => mine.has(r.code));
    const list = rankPlayers(computeLeaderboard(rooms, d.eventsByRoom, byTable || (ui.period === 'all' && ui.scope === 'all') ? d.players : []), ui.sort).filter((p) => !byTable || p.games > 0);
    const brk = sel ? tableBreakdown(sel, d.eventsByRoom, d.players) : null;
    const games = rooms.filter((r) => r.status !== 'cancelled' && (d.eventsByRoom[r.code] || []).some((e) => !e.voided)).length;
    const total = list.reduce((s, p) => s + p.points, 0);
    const u = esc(unit());
    $app.innerHTML = `
      <div class="pagehead row-between"><div><h1>🏆 Mahjong leaderboard</h1><p class="muted">${byTable ? `${games} game${games === 1 ? '' : 's'} by this table` : `${games} game${games === 1 ? '' : 's'} recorded · ${d.players.length} players`}</p></div><span class="row-gap-h"><button class="btn sm danger" data-lbreset>Reset</button><button class="btn sm" data-refresh aria-label="Refresh">↻</button></span></div>
      <div class="chips2 views"><button data-view="all" class="${byTable ? '' : 'on'}">👥 All players</button><button data-view="table" class="${byTable ? 'on' : ''}">🀄 By table (4 players)</button></div>
      ${byTable ? (groups.length ? `<label class="field"><span>Table <small class="muted">(the same 4 players)</small></span><select data-table>${groups.map((g) => `<option value="${esc(g.key)}" ${sel && sel.key === g.key ? 'selected' : ''}>${esc(g.players.join(' · '))} — ${g.games} game${g.games === 1 ? '' : 's'}</option>`).join('')}</select></label>` : '')
        : ''}
      <div class="chips2">${Object.entries(PERIODS).map(([k, p]) => `<button data-period="${k}" class="${ui.period === k ? 'on' : ''}">${p.label}</button>`).join('')}</div>
      <div class="chips2"><span class="small muted">Rank by:</span>${Object.entries(SORTS).map(([k, s]) => `<button data-sort="${k}" class="${ui.sort === k ? 'on' : ''}">${s.label}</button>`).join('')}</div>
      ${byTable ? '' : `<label class="check small"><input type="checkbox" data-scope ${ui.scope === 'mine' ? 'checked' : ''}/> Only games opened on this phone</label>`}
      ${byTable && sel ? `<section class="card tablehead2"><div class="small muted">Table of 4</div><b>${sel.players.map(esc).join(' · ')}</b>
        <div class="small muted">${sel.games} game${sel.games === 1 ? '' : 's'} together · ${brk.hands} hand${brk.hands === 1 ? '' : 's'} · last played ${fmtDate(sel.lastPlayed)}</div></section>` : ''}
      ${list.length === 0 ? `<div class="card center muted">${byTable ? 'No table has played in this period yet.' : 'No games in this period yet.'}</div>` : `
      <ol class="lb card">${list.map((p) => `
        <li><a class="lbrow" href="${p.id ? `#/players/${esc(p.id)}` : '#/players'}">
          <span class="rank">${MEDAL[p.rank] || p.rank}</span>${avatar(p.name)}
          <span class="lbname"><b>${esc(p.name)}</b><small>${p.handle ? `“${esc(p.handle)}” · ` : ''}${p.games} game${p.games === 1 ? '' : 's'} played</small></span>
          <span class="lbpts"><b class="${ui.sort === 'points' ? (p.points > 0 ? 'pos' : p.points < 0 ? 'neg' : '') : ''}">${headline(p)}</b><small>${ui.sort === 'points' ? `avg ${sign(p.avgPerTable)} / game` : `${sign(p.points)} ${u}`}</small></span></a>
          <div class="stats">
            ${stat('Win rate', pct(p.winRate))}${stat('Wins', `${p.wins}W`)}${stat('Self-draw', p.selfDraws)}${stat('Max Tai', p.maxTai ? `${p.maxTai} Tai` : '–')}
            ${stat('Pay-all wins', p.payAllWins)}${stat('Shot', `${p.shots} (${pct(p.shotRate)})`, 'Times discarded the winning tile')}${stat('Kongs', p.kongs)}${stat('#1 finish', p.tableWins)}
          </div></li>`).join('')}</ol>
      <p class="small ${total === 0 ? 'pos' : 'neg'}">${total === 0 ? '✓ Zero-sum check: all players’ points add up to 0.' : `✗ Points add up to ${total}.`}</p>`}
      ${brk && brk.rows.length ? `<section class="card"><h2>Game by game</h2><p class="small muted">Points of each player in every game this table played. Tap a date to open the recap.</p>
        <div class="tscroll"><table class="simple tgames"><tr><th>Game</th>${brk.columns.map((c) => `<th>${esc(c.name.length > 9 ? `${c.name.slice(0, 8)}…` : c.name)}</th>`).join('')}</tr>
          ${brk.rows.map((r) => `<tr><td><a href="#/t/${esc(r.code)}/recap">${fmtDate(r.createdAt)}</a>${['active', 'lobby'].includes(r.status) ? ' 🟢' : ''}</td>${brk.columns.map((c) => `<td class="${cls(r.nets[c.key] || 0)}">${sign(r.nets[c.key] || 0)}</td>`).join('')}</tr>`).join('')}
          <tr class="ttotal"><td><b>Total</b></td>${brk.columns.map((c) => `<td class="${cls(c.total)}"><b>${sign(c.total)}</b></td>`).join('')}</tr></table></div></section>` : ''}
      ${prefs.rules.leaderboardResetAt ? `<p class="small muted">Rankings were reset on ${new Date(prefs.rules.leaderboardResetAt).toLocaleString()} — older games are not counted. <button class="btn sm" data-lbundo>Undo reset</button></p>` : ''}`;
  };
  draw();
  $app.onclick = async (e) => {
    const b = e.target.closest('button'); if (!b) return;
    if (b.dataset.period) { ui.period = b.dataset.period; savePrefs(); return draw(); }
    if (b.dataset.sort) { ui.sort = b.dataset.sort; savePrefs(); return draw(); }
    if (b.dataset.view) { ui.view = b.dataset.view; savePrefs(); return draw(); }
    if (b.dataset.refresh !== undefined) return renderLeaderboard($app, true);
    if (b.dataset.lbreset !== undefined) {
      if (!await confirmBox({ title: 'Reset all rankings to 0?', text: 'The leaderboard, home champions and career stats will only count games from now on. No games are deleted and you can undo this.', ok: 'Reset rankings', danger: true })) return;
      await saveRules(app.store, { ...prefs.rules, leaderboardResetAt: Date.now() }); invalidate(); toast('Rankings reset'); return renderLeaderboard($app, true);
    }
    if (b.dataset.lbundo !== undefined) { await saveRules(app.store, { ...prefs.rules, leaderboardResetAt: 0 }); invalidate(); toast('Reset undone'); return renderLeaderboard($app, true); }
  };
  $app.onchange = (e) => {
    if (e.target.matches('[data-scope]')) { ui.scope = e.target.checked ? 'mine' : 'all'; savePrefs(); draw(); }
    if (e.target.matches('[data-table]')) { ui.table = e.target.value; savePrefs(); draw(); }
  };
}
