// Scores bench output against online.jsonl (R = IDSBK raptor, I = imhd): node score.mjs offline.jsonl [baseline.jsonl]
// An offline journey covers an online one when it leaves no more than 1 min earlier, arrives no more than 1 min later
// and has no more rides. Like the router, a journey dominates another only with no more rides.
import fs from 'node:fs';
const rd = (f) => Object.fromEntries(fs.readFileSync(f, 'utf8').trim().split('\n').map(JSON.parse).map((x) => [x.label, x]));
const qs = JSON.parse(fs.readFileSync('queries.json', 'utf8')), off = rd(process.argv[2] ?? 'offline.jsonl'), on = rd('online.jsonl');
const base = process.argv[3] ? rd(process.argv[3]) : null;
// imhd times carry no zone and are Bratislava wall-clock time; read them as such whatever the host's zone.
const bratislavaOffset = (d) => new Date(d.toLocaleString('sv-SE', { timeZone: 'Europe/Bratislava' }).replace(' ', 'T') + 'Z') - d;
const t = (s) => {
  if (/(Z|[+-]\d\d:?\d\d)$/.test(s)) return new Date(s).getTime() / 1000;
  const wall = new Date(`${s.replace(' ', 'T')}Z`);
  return (wall - bratislavaOffset(wall)) / 1000;
};
const hm = (s) => new Date(t(s) * 1000).toLocaleTimeString('sv-SE', { timeZone: 'Europe/Bratislava' }).slice(0, 5);
const fmt = (js) => js.map((j) => `${hm(j.dep)}-${hm(j.arr)} ${j.lines.join('>')}${j.src ? `(${j.src})` : ''}`).join(' | ');
const covers = (j, p) => t(j.dep) >= t(p.dep) - 60 && t(j.arr) <= t(p.arr) + 60 && j.lines.length <= p.lines.length;
const best = (js) => Math.min(...js.map((j) => t(j.arr)));
const tally = (d, into) => into[d < -60 ? 'earlier' : d > 60 ? 'later' : 'same']++;
const cov = { 900: [0, 0], 3600: [0, 0] }, vsOnline = { earlier: 0, same: 0, later: 0 }, vsBase = { earlier: 0, same: 0, later: 0 };
const ms = [], counts = [], rows = [], baseLater = [];
for (const q of qs) {
  const q0 = t(q.iso), o = off[q.label], n = on[q.label];
  const inWin = (w) => (j) => t(j.dep) >= q0 - 60 && t(j.dep) <= q0 + w;
  const online = [...n.r.map((j) => ({ ...j, src: 'R' })), ...n.i.map((j) => ({ ...j, src: 'I' }))].filter((j) => j.dep && j.arr && inWin(3600)(j));
  const pareto = online.filter((a) => !online.some((b) => b !== a && t(b.dep) >= t(a.dep) && t(b.arr) <= t(a.arr) && b.lines.length <= a.lines.length && (t(b.dep) > t(a.dep) || t(b.arr) < t(a.arr) || b.lines.length < a.lines.length)));
  const uniq = [...new Map(pareto.map((j) => [`${hm(j.dep)}-${hm(j.arr)}-${j.lines.length}`, j])).values()];
  for (const w of [900, 3600]) {
    const target = uniq.filter(inWin(w));
    cov[w][0] += target.filter((p) => o.journeys.some((j) => covers(j, p))).length;
    cov[w][1] += target.length;
  }
  const offW = o.journeys.filter(inWin(3600)), bo = best(offW), bn = best(online);
  counts.push(offW.length); ms.push(o.ms);
  if (isFinite(bo) && isFinite(bn)) tally(bo - bn, vsOnline);
  if (base) {
    const bb = best(base[q.label].journeys.filter(inWin(3600)));
    if (isFinite(bo) && isFinite(bb)) tally(bo - bb, vsBase);
    if (!(bo <= bb + 60) && isFinite(bb)) baseLater.push(`${q.label}: ${isFinite(bo) ? (bo - bb) / 60 + ' min later' : 'no journey'} (baseline ${fmt(base[q.label].journeys.filter(inWin(3600)).filter((j) => t(j.arr) === bb))})`);
  }
  const missed = uniq.filter((p) => !o.journeys.some((j) => covers(j, p)));
  rows.push(`${q.label} ${q.iso.slice(11, 16)} ${q.from} -> ${q.to}: offline ${offW.length} (${o.ms}ms), onlinePareto ${uniq.length}, missed ${missed.length}, bestArrΔ ${isFinite(bo) && isFinite(bn) ? (bo - bn) / 60 : isFinite(bn) ? 'NO OFFLINE' : 'n/a'}min` +
    (missed.length ? `\n    missed: ${fmt(missed)}\n    offline: ${fmt(offW.slice(0, 8))}` : ''));
}
const med = (a) => [...a].sort((x, y) => x - y)[a.length >> 1], sorted = [...ms].sort((a, b) => a - b);
console.log(rows.join('\n'));
for (const w of [900, 3600]) console.log(`coverage first ${w / 60} min: ${cov[w][0]}/${cov[w][1]} = ${(100 * cov[w][0] / cov[w][1]).toFixed(0)}% of online Pareto journeys`);
console.log(`best arrival vs online (±1 min): earlier ${vsOnline.earlier}, same ${vsOnline.same}, later ${vsOnline.later}`);
if (base) console.log(`best arrival vs baseline (±1 min): earlier ${vsBase.earlier}, same ${vsBase.same}, later ${vsBase.later}${baseLater.length ? '\n  ' + baseLater.join('\n  ') : ''}`);
console.log(`offline ms: median ${med(ms)}, p90 ${sorted[Math.floor(ms.length * 0.9)]}, max ${sorted.at(-1)}; journeys leaving in the first hour: median ${med(counts)}`);
