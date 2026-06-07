import fs from 'node:fs';
import { spawnSync } from 'node:child_process';

const STOPS_PATH = '/Users/magic_sk/Developer/js/api/data/stops.json';
const OFFLINE_CHECK = '/tmp/transi-offline-routing-check';

const S_USER_AGENT = 'ProdProd/204 CFNetwork/3826.600.41 Darwin/24.6.0';
const G_USER_AGENT =
  'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/141.0.0.0 Safari/537.36';

function readJson(path) {
  try {
    return JSON.parse(fs.readFileSync(path, 'utf8'));
  } catch (error) {
    throw new Error(`Failed to read JSON from ${path}: ${error.message}`);
  }
}

function readConfig() {
  const path = new URL('../Release.xcconfig', import.meta.url);
  let text;
  try {
    text = fs.readFileSync(path, 'utf8');
  } catch (error) {
    throw new Error(`Failed to read Release.xcconfig: ${error.message}`);
  }

  const config = {};
  for (const line of text.split(/\r?\n/)) {
    const match = line.match(/^\s*([A-Z][A-Z0-9_]*)\s*=\s*(.*?)\s*$/);
    if (!match) continue;
    config[match[1]] = match[2].trim().replaceAll('/$()/', '//');
  }
  return config;
}

const stops = readJson(STOPS_PATH);
const config = readConfig();

for (const key of ['I_API_URL', 'B_API_URL', 'R_API_URL', 'B_API_KEY', 'R_API_KEY']) {
  if (!config[key]) {
    throw new Error(`Missing ${key} in Release.xcconfig`);
  }
}

function stopByName(name) {
  const matches = stops.filter((stop) => stop.name === name);
  if (matches.length === 0) {
    throw new Error(`Missing stop named "${name}" in ${STOPS_PATH}`);
  }

  const stop = matches.length === 1 ? matches[0] : matches.find((candidate) => candidate.city === 'Bratislava') ?? matches[0];
  const stationId = stop.station_id ?? stop.stationId;
  if (!stop.id || !stationId) {
    throw new Error(`Stop "${name}" is missing id or station_id`);
  }

  return {
    id: Number(stop.id),
    stationId: Number(stationId),
    name: stop.name,
    city: stop.city,
  };
}

const cases = [
  {
    label: 'short_city',
    from: stopByName('Hronská'),
    to: stopByName('Most SNP'),
    iso: '2026-06-02T08:00:00+02:00',
  },
  {
    label: 'medium_city',
    from: stopByName('Zlaté piesky'),
    to: stopByName('Hlavná stanica'),
    iso: '2026-06-02T08:00:00+02:00',
  },
  {
    label: 'train_station_pair',
    from: stopByName('Hlavná stanica'),
    to: stopByName('Stn. Petržalka'),
    iso: '2026-06-02T08:00:00+02:00',
  },
  {
    label: 'regional_bus',
    from: stopByName('Autobusová stanica'),
    to: stopByName('Rovinka, Obecný úrad'),
    iso: '2026-06-02T08:00:00+02:00',
  },
  {
    label: 'regional_train',
    from: stopByName('Hlavná stanica'),
    to: stopByName('Pezinok, Žel. stanica'),
    iso: '2026-06-02T08:00:00+02:00',
  },
  {
    label: 'long_suburban',
    from: stopByName('Most SNP'),
    to: stopByName('Senec, Žel. stanica'),
    iso: '2026-06-02T08:00:00+02:00',
  },
  {
    label: 'late_short',
    from: stopByName('Hronská'),
    to: stopByName('Most SNP'),
    iso: '2026-06-02T23:30:00+02:00',
  },
];

const fmt = new Intl.DateTimeFormat('sv-SE', {
  timeZone: 'Europe/Bratislava',
  year: 'numeric',
  month: '2-digit',
  day: '2-digit',
  hour: '2-digit',
  minute: '2-digit',
  hourCycle: 'h23',
});

function localDateParts(iso) {
  const parts = Object.fromEntries(fmt.formatToParts(new Date(iso)).map((part) => [part.type, part.value]));
  return {
    date: `${parts.year}-${parts.month}-${parts.day}`,
    time: `${parts.hour}:${parts.minute}`,
  };
}

function rPartValue(part, key) {
  const snake = key.replace(/[A-Z]/g, (letter) => `_${letter.toLowerCase()}`);
  return part?.[key] ?? part?.[snake] ?? null;
}

function summarizeRJourney(journey) {
  const parts = Array.isArray(journey?.parts) ? journey.parts : [];
  const first = parts[0];
  const last = parts.at(-1);
  const lines = parts.map((part) => rPartValue(part, 'routeShortName')).filter(Boolean);

  return {
    departure: rPartValue(first, 'startDeparture'),
    arrival: rPartValue(last, 'endArrival'),
    lines,
  };
}

function iLineNames(journey) {
  const lines = Array.isArray(journey?.lines) ? journey.lines : [];
  const mapping = Array.isArray(journey?.linesMapping)
    ? journey.linesMapping
    : Array.isArray(journey?.lines_mapping)
      ? journey.lines_mapping
      : [];

  return mapping
    .map((index) => {
      const value = lines[index]?.[1];
      if (typeof value === 'string') return value;
      if (typeof value?.value === 'string') return value.value;
      return null;
    })
    .filter(Boolean);
}

function summarizeIJourney(journey) {
  return {
    departure: journey?.departure?.date ?? null,
    arrival: journey?.arrival?.date ?? null,
    lines: iLineNames(journey),
  };
}

async function fetchJson(url, options = {}) {
  try {
    const response = await fetch(url, options);
    const text = await response.text();
    try {
      return {
        status: response.status,
        json: text ? JSON.parse(text) : null,
      };
    } catch (error) {
      return {
        status: response.status,
        error: `Invalid JSON: ${error.message}`,
        body: text.slice(0, 500),
      };
    }
  } catch (error) {
    return {
      status: null,
      error: error.message,
    };
  }
}

async function getSession() {
  const body = JSON.stringify({
    installation: globalThis.crypto?.randomUUID?.() ?? '00000000-0000-4000-8000-000000000010',
    language: 'en',
    platform: 2,
  });
  const result = await fetchJson(`${config.B_API_URL}/mobile/v1/startup`, {
    method: 'POST',
    headers: {
      'Content-Length': String(Buffer.byteLength(body)),
      'Content-Type': 'application/json',
      'User-Agent': S_USER_AGENT,
      'x-api-key': config.B_API_KEY,
    },
    body,
  });

  if (result.status !== 200 || !result.json?.session) {
    return {
      startupStatus: result.status,
      error: result.error ?? 'Startup response did not include a session token',
      body: result.body,
    };
  }

  return {
    startupStatus: result.status,
    session: result.json.session,
  };
}

function summarizeRResult(result, retried) {
  if (result.error) {
    return {
      status: result.status,
      error: result.error,
      body: result.body,
      retried,
    };
  }

  const journeys = Array.isArray(result.json?.journey) ? result.json.journey : [];
  return {
    status: result.status,
    count: journeys.length,
    journeys: journeys.slice(0, 3).map(summarizeRJourney),
    retried,
  };
}

async function fetchR(c) {
  const session = await getSession();
  if (!session.session) {
    return {
      status: null,
      startupStatus: session.startupStatus,
      error: session.error,
      body: session.body,
    };
  }

  const url = `${config.R_API_URL}/mobile/v1/raptor/`;
  const baseBody = {
    org_id: 120,
    max_walk_duration: 15,
    max_transfers: 3,
    search_to_hours: 2,
    search_from: c.iso,
    from_station_id: [c.from.stationId],
    to_station_id: [c.to.stationId],
  };

  async function post(body) {
    const jsonBody = JSON.stringify(body);
    return fetchJson(url, {
      method: 'POST',
      headers: {
        'Content-Length': String(Buffer.byteLength(jsonBody)),
        'Content-Type': 'application/json',
        'User-Agent': S_USER_AGENT,
        'x-api-key': config.R_API_KEY,
        'x-session': session.session,
      },
      body: jsonBody,
    });
  }

  const first = await post(baseBody);
  if (first.status !== 200 || (Array.isArray(first.json?.journey) && first.json.journey.length > 0)) {
    return summarizeRResult(first, false);
  }

  const retry = await post({ ...baseBody, search_to_hours: 8 });
  return summarizeRResult(retry, true);
}

async function fetchI(c) {
  const { date, time } = localDateParts(c.iso);
  const params = new URLSearchParams({
    v: '7',
    a: `g${c.from.id}`,
    b: `g${c.to.id}`,
    pd: date,
    pt: time,
    pa: '0',
    pl: '1.0-4.0',
    pp: '0',
    pc: '0',
    format: '0',
    op: 'Planner',
  });

  const result = await fetchJson(`${config.I_API_URL}/ba/api/cepo?${params}`, {
    headers: {
      'User-Agent': G_USER_AGENT,
    },
  });

  if (result.error) {
    return {
      status: result.status,
      error: result.error,
      body: result.body,
    };
  }

  const journeys = Array.isArray(result.json?.journeys) ? result.json.journeys : [];
  return {
    status: result.status,
    count: journeys.length,
    journeys: journeys.slice(0, 3).map(summarizeIJourney),
  };
}

for (const c of cases) {
  const offline = spawnSync(OFFLINE_CHECK, [c.label], { encoding: 'utf8' });
  if (offline.error || offline.status !== 0) {
    console.error(`Offline harness failed for ${c.label} with status ${offline.status ?? 'unknown'}`);
    if (offline.error) console.error(offline.error.message);
    if (offline.stdout) console.error(offline.stdout.trim());
    if (offline.stderr) console.error(offline.stderr.trim());
    process.exit(offline.status || 1);
  }

  const [r, i] = await Promise.all([fetchR(c), fetchI(c)]);
  console.log(
    JSON.stringify({
      label: c.label,
      offline: offline.stdout.trim(),
      r,
      i,
    })
  );
}
