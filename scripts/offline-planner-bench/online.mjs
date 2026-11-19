// Fetch R (IDSBK raptor) + I (imhd) journeys for queries.json; one session reused.
import fs from 'node:fs';
const cfgText = fs.readFileSync(process.argv[2], 'utf8');
const config = {};
for (const line of cfgText.split(/\r?\n/)) { const m = line.match(/^\s*([A-Z][A-Z0-9_]*)\s*=\s*(.*?)\s*$/); if (m) config[m[1]] = m[2].trim().replaceAll('/$()/', '//'); }
const UA = 'ProdProd/204 CFNetwork/3826.600.41 Darwin/24.6.0';
const GUA = 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/141.0.0.0 Safari/537.36';
const queries = JSON.parse(fs.readFileSync('queries.json', 'utf8'));
const body = JSON.stringify({ installation: crypto.randomUUID(), language: 'en', platform: 2 });
const session = (await (await fetch(`${config.B_API_URL}/mobile/v1/startup`, { method: 'POST', headers: { 'Content-Type': 'application/json', 'User-Agent': UA, 'x-api-key': config.B_API_KEY }, body })).json()).session;
const pv = (p, k) => p?.[k] ?? p?.[k.replace(/[A-Z]/g, (l) => `_${l.toLowerCase()}`)] ?? null;
const local = (iso) => { const f = new Intl.DateTimeFormat('sv-SE', { timeZone: 'Europe/Bratislava', year: 'numeric', month: '2-digit', day: '2-digit', hour: '2-digit', minute: '2-digit', hourCycle: 'h23' }).formatToParts(new Date(iso)); const o = Object.fromEntries(f.map((x) => [x.type, x.value])); return { date: `${o.year}-${o.month}-${o.day}`, time: `${o.hour}:${o.minute}` }; };
for (const q of queries) {
  const rb = JSON.stringify({ org_id: 120, max_walk_duration: 15, max_transfers: 3, search_to_hours: 2, search_from: q.iso, from_station_id: [Number(q.fromStation)], to_station_id: [Number(q.toStation)] });
  const r = await fetch(`${config.R_API_URL}/mobile/v1/raptor/`, { method: 'POST', headers: { 'Content-Type': 'application/json', 'User-Agent': UA, 'x-api-key': config.R_API_KEY, 'x-session': session }, body: rb }).then((x) => x.json()).catch((e) => ({ error: e.message }));
  const rj = (r.journey ?? []).map((j) => { const p = j.parts ?? []; return { dep: pv(p[0], 'startDeparture'), arr: pv(p.at(-1), 'endArrival'), lines: p.map((x) => pv(x, 'routeShortName')).filter(Boolean) }; });
  const { date, time } = local(q.iso);
  const ip = new URLSearchParams({ v: '7', a: `g${q.fromId}`, b: `g${q.toId}`, pd: date, pt: time, pa: '0', pl: '1.0-4.0', pp: '0', pc: '0', format: '0', op: 'Planner' });
  const i = await fetch(`${config.I_API_URL}/ba/api/cepo?${ip}`, { headers: { 'User-Agent': GUA } }).then((x) => x.json()).catch((e) => ({ error: e.message }));
  const ij = (i.journeys ?? []).map((j) => { const lines = j.lines ?? []; return { dep: j.departure?.date, arr: j.arrival?.date, lines: (j.linesMapping ?? j.lines_mapping ?? []).map((k) => lines[k]?.[1]).map((v) => typeof v === 'string' ? v : v?.value).filter((v) => v && v !== '🚶') }; });
  console.log(JSON.stringify({ label: q.label, r: rj, rErr: r.error ?? null, i: ij, iErr: i.error ?? null }));
  await new Promise((res) => setTimeout(res, 400));
}
