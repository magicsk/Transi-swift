import fs from 'node:fs';
import { spawnSync } from 'node:child_process';

const STOPS_PATH = '/Users/magic_sk/Developer/js/api/data/stops.json';
const OFFLINE_CHECK = '/tmp/transi-offline-routing-check';

const S_USER_AGENT = 'ProdProd/204 CFNetwork/3826.600.41 Darwin/24.6.0';
const G_USER_AGENT =
  'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/141.0.0.0 Safari/537.36';
const TEST_ISO = process.env.TRANSI_COMPARE_ISO ?? '2026-07-13T14:00:00+02:00';
const BRODNA_KRCE_ISO = process.env.TRANSI_BRODNA_KRCE_ISO ?? '2026-07-13T15:00:00+02:00';
const MAX_WALK_DURATION = Number(process.env.TRANSI_COMPARE_MAX_WALK_DURATION ?? 15);
const MAX_TRANSFERS = Number(process.env.TRANSI_COMPARE_MAX_TRANSFERS ?? 3);
const SEARCH_WINDOW_HOURS = Number(process.env.TRANSI_COMPARE_SEARCH_HOURS ?? 2);
const RETRY_SEARCH_WINDOW_HOURS = Number(process.env.TRANSI_COMPARE_RETRY_SEARCH_HOURS ?? 8);

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
    iso: TEST_ISO,
  },
  {
    label: 'medium_city',
    from: stopByName('Zlaté piesky'),
    to: stopByName('Hlavná stanica'),
    iso: TEST_ISO,
  },
  {
    label: 'train_station_pair',
    from: stopByName('Hlavná stanica'),
    to: stopByName('Stn. Petržalka'),
    iso: TEST_ISO,
  },
  {
    label: 'regional_bus',
    from: stopByName('Autobusová stanica'),
    to: stopByName('Rovinka, Obecný úrad'),
    iso: TEST_ISO,
  },
  {
    label: 'regional_train',
    from: stopByName('Hlavná stanica'),
    to: stopByName('Pezinok, Žel. stanica'),
    iso: TEST_ISO,
  },
  {
    label: 'long_suburban',
    from: stopByName('Most SNP'),
    to: stopByName('Senec, Žel. stanica'),
    iso: TEST_ISO,
  },
  {
    label: 'day_short_repeat',
    from: stopByName('Hronská'),
    to: stopByName('Most SNP'),
    iso: TEST_ISO,
    offlineLabel: 'late_short',
  },
  {
    label: 'hill_destination_direct',
    from: stopByName('Hodžovo nám.'),
    to: stopByName('Hrad'),
    iso: TEST_ISO,
  },
  {
    label: 'hill_destination_hub',
    from: stopByName('Hlavná stanica'),
    to: stopByName('Hrad'),
    iso: TEST_ISO,
  },
  {
    label: 'brodna_krce_afternoon',
    from: stopByName('Brodná'),
    to: stopByName('Krče'),
    iso: BRODNA_KRCE_ISO,
  },
];

const bratislavaDateTimeFormatter = new Intl.DateTimeFormat('sv-SE', {
  timeZone: 'Europe/Bratislava',
  year: 'numeric',
  month: '2-digit',
  day: '2-digit',
  hour: '2-digit',
  minute: '2-digit',
  hourCycle: 'h23',
});

function fmt(dateLike) {
  if (!dateLike) return null;
  const date = new Date(dateLike);
  if (Number.isNaN(date.getTime())) return null;
  return bratislavaDateTimeFormatter.format(date);
}

function localDateParts(iso) {
  const parts = Object.fromEntries(bratislavaDateTimeFormatter.formatToParts(new Date(iso)).map((part) => [part.type, part.value]));
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
    departure: fmt(rPartValue(first, 'startDeparture')),
    arrival: fmt(rPartValue(last, 'endArrival')),
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
    departure: fmt(journey?.departure?.date),
    arrival: fmt(journey?.arrival?.date),
    lines: iLineNames(journey),
  };
}

function normalizedSignature(lines) {
  return lines.filter(Boolean).join('>');
}

function parseOfflineJourneys(output) {
  return output
    .split(/\r?\n/)
    .map((line) => line.match(/^\s+\[\d+\]\s+(.*)$/)?.[1])
    .filter(Boolean)
    .map((signature) => {
      const routeSignature = signature.replace(/^\d{2}:\d{2}-\d{2}:\d{2}\s+/, '');
      const lines = routeSignature
        .split(' | ')
        .map((part) => part.split(':')[0])
        .filter((line) => line && line !== 'walk');
      return { lines };
    });
}

function compareOverallResult(offlineJourneys, r, i) {
  const offline = offlineJourneys.slice(0, 5).map((journey) => normalizedSignature(journey.lines)).filter(Boolean);
  const online = [
    ...(Array.isArray(r.journeys) ? r.journeys : []),
    ...(Array.isArray(i.journeys) ? i.journeys : []),
  ]
    .slice(0, 6)
    .map((journey) => normalizedSignature(journey.lines))
    .filter(Boolean);
  const onlineSet = new Set(online);
  const matched = offline.find((signature) => onlineSet.has(signature)) ?? null;
  return {
    offline,
    online,
    matched,
    alternative: matched ? null : offline[0] ?? null,
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
    max_walk_duration: MAX_WALK_DURATION,
    max_transfers: MAX_TRANSFERS,
    search_to_hours: SEARCH_WINDOW_HOURS,
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

  const retry = await post({ ...baseBody, search_to_hours: RETRY_SEARCH_WINDOW_HOURS });
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

const failures = [];

console.log(JSON.stringify({
  settings: {
    iso: TEST_ISO,
    mode: 'departure',
    maxWalkDuration: MAX_WALK_DURATION,
    maxTransfers: MAX_TRANSFERS,
    raptorSearchHours: SEARCH_WINDOW_HOURS,
    raptorRetrySearchHours: RETRY_SEARCH_WINDOW_HOURS,
    imhdParams: { pa: '0', pl: '1.0-4.0', pp: '0', pc: '0' },
  },
}));

for (const c of cases) {
  const offline = spawnSync(OFFLINE_CHECK, [c.offlineLabel ?? c.label], {
    encoding: 'utf8',
    env: {
      ...process.env,
      TRANSI_ROUTING_DEBUG: '1',
      TRANSI_CHECK_ISO: c.iso,
      TRANSI_MAX_WALK_DURATION: String(MAX_WALK_DURATION),
      TRANSI_MAX_TRANSFERS: String(MAX_TRANSFERS),
      TRANSI_SKIP_EXPECTATIONS: '1',
    },
  });
  if (offline.error || offline.status !== 0) {
    console.error(`Offline harness failed for ${c.label} with status ${offline.status ?? 'unknown'}`);
    if (offline.error) console.error(offline.error.message);
    if (offline.stdout) console.error(offline.stdout.trim());
    if (offline.stderr) console.error(offline.stderr.trim());
    process.exit(offline.status || 1);
  }

  const [r, i] = await Promise.all([fetchR(c), fetchI(c)]);
  const offlineJourneys = parseOfflineJourneys(offline.stdout);
  const comparison = compareOverallResult(offlineJourneys, r, i);
  const hasOnlineReference = comparison.online.length > 0;
  if (hasOnlineReference && comparison.offline.length === 0) {
    failures.push(`${c.label}: online APIs returned journeys but offline returned no parsed journeys`);
  }
  if (hasOnlineReference && comparison.offline.length > 0 && !comparison.matched) {
    failures.push(
      `${c.label}: offline top routes did not match IDSBK/IMHD top routes; best offline alternative ${comparison.alternative}`
    );
  }
  console.log(
    JSON.stringify({
      label: c.label,
      offline: offline.stdout.trim(),
      r,
      i,
      comparison,
    })
  );
}

if (failures.length > 0) {
  for (const failure of failures) {
    console.error(`FAIL: ${failure}`);
  }
  process.exit(1);
}
