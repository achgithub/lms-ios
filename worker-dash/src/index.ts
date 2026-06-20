// No auth here — Cloudflare Access handles it at the edge before this Worker runs.

interface Env {
  PL_DB: D1Database;  ELC_DB: D1Database;  PD_DB: D1Database;
  PL_KV: KVNamespace; ELC_KV: KVNamespace; PD_KV: KVNamespace;
  // Same value as each league Worker's own ADMIN_TOKEN secret — needed to call
  // its public /admin/sync + /admin/probe-standings (season rollover actions).
  // Not needed for the phase buttons, which write the KV binding directly.
  PL_ADMIN_TOKEN?: string; ELC_ADMIN_TOKEN?: string; PD_ADMIN_TOKEN?: string;
}

type SyncRow    = { dataset: string; synced_at: string; row_count: number };
type GateState  = { call: number; refresh: number; ts: string | null };
type StatusRow  = { status: string; cnt: number };
type NextFixRow = { kickoff: string; matchday: number | null };
type SeasonPhase = "live" | "closed";

const GATES = ["scores", "fixtures", "standings"] as const;
type GateName = typeof GATES[number];

const PHASE_KEY = "season:phase";

const LEAGUES = [
  {
    key: "pl", name: "Premier League", db: "PL_DB" as const, kv: "PL_KV" as const,
    url: "https://pl.sportsmanager.site", tokenEnv: "PL_ADMIN_TOKEN" as const,
  },
  {
    key: "elc", name: "Championship", db: "ELC_DB" as const, kv: "ELC_KV" as const,
    url: "https://elc.sportsmanager.site", tokenEnv: "ELC_ADMIN_TOKEN" as const,
  },
  {
    key: "pd", name: "La Liga", db: "PD_DB" as const, kv: "PD_KV" as const,
    url: "https://pd.sportsmanager.site", tokenEnv: "PD_ADMIN_TOKEN" as const,
  },
];

function parseInt0(v: string | null): number {
  const n = parseInt(v ?? "0", 10);
  return Number.isFinite(n) ? n : 0;
}

async function fetchLeague(db: D1Database, kv: KVNamespace) {
  // No "demo:clock" read here — pl/elc/pd have no demo-clock capability at
  // all (see worker/src/demo.ts demoClockIfEnabled / DEMO_ENABLED), so this
  // dashboard has nothing to report for it. The standalone `demo` env isn't
  // in LEAGUES above and never will be.
  const kvKeys = [
    "scores",
    PHASE_KEY,
    ...GATES.flatMap((g) => [`${g}:call`, `${g}:refresh`, `${g}:ts`]),
  ];
  const [syncResult, statusResult, nextFixResult, ...kvVals] = await Promise.all([
    db.prepare("SELECT dataset, synced_at, row_count FROM sync_meta ORDER BY dataset").all<SyncRow>(),
    db.prepare("SELECT status, COUNT(*) as cnt FROM fixtures GROUP BY status ORDER BY cnt DESC").all<StatusRow>(),
    db.prepare("SELECT kickoff, matchday FROM fixtures WHERE status IN ('SCHEDULED','TIMED') ORDER BY kickoff ASC LIMIT 1").first<NextFixRow>(),
    ...kvKeys.map((k) => kv.get(k)),
  ]);

  const [scoresRaw, phaseRaw, ...gateVals] = kvVals;
  const phase: SeasonPhase = phaseRaw === "closed" ? phaseRaw : "live";

  const gates: Record<GateName, GateState> = {} as Record<GateName, GateState>;
  GATES.forEach((g, i) => {
    const base = i * 3;
    gates[g] = {
      call:    parseInt0(gateVals[base]     ?? null),
      refresh: parseInt0(gateVals[base + 1] ?? null),
      ts:      gateVals[base + 2]           ?? null,
    };
  });

  return {
    sync: syncResult.results,
    statusCounts: statusResult.results,
    nextFixture: nextFixResult ?? null,
    scoresCacheBytes: scoresRaw ? scoresRaw.length : null,
    gates,
    phase,
  };
}

function iconSvg(): Response {
  const svg = `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 512 512">
  <rect width="512" height="512" rx="80" fill="#0d0d0d"/>
  <text x="256" y="320" font-family="ui-monospace,monospace" font-size="200" font-weight="bold"
        fill="#e0e0e0" text-anchor="middle">⚽</text>
</svg>`;
  return new Response(svg, {
    headers: { "Content-Type": "image/svg+xml", "Cache-Control": "public, max-age=86400" },
  });
}

function manifestJson(): Response {
  const m = {
    name: "LMS Dashboard", short_name: "LMS", start_url: "/",
    display: "standalone", background_color: "#0d0d0d", theme_color: "#0d0d0d",
    icons: [{ src: "/icon.svg", sizes: "any", type: "image/svg+xml", purpose: "any maskable" }],
  };
  return new Response(JSON.stringify(m), {
    headers: { "Content-Type": "application/manifest+json", "Cache-Control": "public, max-age=3600" },
  });
}

function serviceWorkerJs(): Response {
  const sw = `self.addEventListener('install',()=>self.skipWaiting());
self.addEventListener('activate',(e)=>e.waitUntil(clients.claim()));
self.addEventListener('fetch',(e)=>e.respondWith(fetch(e.request)));`;
  return new Response(sw, { headers: { "Content-Type": "application/javascript" } });
}

function shellHtml(): Response {
  const leagueSections = LEAGUES.map((l) => `
    <section id="s-${l.key}">
      <div class="league-header">
        <h2>${l.name}</h2>
        <button onclick="load('${l.key}')">Load</button>
      </div>
      <div id="d-${l.key}" class="league-data">—</div>
      <h3>API control</h3>
      <div class="toggle-row">
        <button id="toggle-${l.key}" class="api-toggle" onclick="toggleApi('${l.key}')">—</button>
        <span class="toggle-hint">One switch, mutually exclusive — live or blocked, never both.
        Blocked = zero upstream calls, regardless of TTL/cron; serves whatever's cached, however
        stale. Use it for a season-end freeze (most common) or to ride out a worker deploy/incident
        without users seeing errors. Correctness is unaffected either way — every call is always
        pinned to the right season.</span>
      </div>
      <div class="season-actions">
        <input id="year-${l.key}" type="number" placeholder="auto (current season)" style="width:9em">
        <button onclick="probeSeason('${l.key}')">Probe (read-only check)</button>
        <button onclick="syncSeason('${l.key}')">Sync now (updates cache, switch unchanged)</button>
      </div>
      <div id="season-msg-${l.key}" class="season-msg"></div>
    </section>`).join("");

  const html = `<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width,initial-scale=1">
  <title>LMS Dashboard</title>
  <link rel="manifest" href="/manifest.json">
  <meta name="theme-color" content="#0d0d0d">
  <link rel="apple-touch-icon" href="/icon.svg">
  <meta name="apple-mobile-web-app-capable" content="yes">
  <meta name="apple-mobile-web-app-status-bar-style" content="black">
  <meta name="apple-mobile-web-app-title" content="LMS">
  <style>
    *, *::before, *::after { box-sizing: border-box; margin: 0; padding: 0; }
    body { font-family: ui-monospace, monospace; background: #0d0d0d; color: #e0e0e0;
           padding: 1.5rem; font-size: 14px; max-width: 720px; }
    h1 { font-size: 1.2rem; margin-bottom: 2rem; color: #fff; }
    section { margin-bottom: 1.5rem; border: 1px solid #1e1e1e; border-radius: 6px; padding: 1rem; }
    .league-header { display: flex; align-items: center; justify-content: space-between; margin-bottom: 0.8rem; }
    h2 { font-size: 0.9rem; color: #aaa; text-transform: uppercase; letter-spacing: 0.08em; }
    h3 { font-size: 0.75rem; color: #555; text-transform: uppercase; letter-spacing: 0.06em;
         margin: 0.8rem 0 0.4rem; }
    button { background: #1a1a1a; color: #e0e0e0; border: 1px solid #333;
             padding: 0.3rem 0.9rem; font-family: inherit; font-size: 12px;
             cursor: pointer; border-radius: 4px; }
    button:active { background: #222; }
    button:disabled { opacity: 0.4; cursor: default; }
    .league-data { color: #555; font-size: 12px; }
    table { width: 100%; border-collapse: collapse; }
    th, td { text-align: left; padding: 0.3rem 0.5rem; border-bottom: 1px solid #1a1a1a; }
    th { color: #444; font-weight: normal; font-size: 11px; text-transform: uppercase; }
    td.num { color: #6cf; }
    td.ts  { color: #888; }
    .missing { color: #553; }
    .badge { display: inline-block; margin-top: 0.6rem; padding: 0.3rem 0.6rem;
             border-radius: 4px; font-size: 11px; }
    .badge-live   { background: #0d1a0d; color: #4a4; border: 1px solid #1a331a; }
    .badge-flight { background: #1a0a0a; color: #f66; border: 1px solid #330000; }
    .season { color: #e0e0e0; margin-top: 0.6rem; font-size: 13px; }
    .next   { color: #888; font-size: 12px; margin-top: 0.2rem; margin-bottom: 0.2rem; }
    .fetched { color: #333; font-size: 11px; margin-top: 0.6rem; }
    .toggle-row { display: flex; align-items: flex-start; gap: 0.7rem; margin-bottom: 0.7rem; }
    .toggle-hint { font-size: 11px; color: #777; line-height: 1.4; padding-top: 0.3rem; }
    .api-toggle { flex-shrink: 0; min-width: 9.5em; font-size: 12px; font-weight: bold;
                  padding: 0.5rem 0.8rem; border-radius: 6px; cursor: pointer; }
    .api-toggle.live    { background: #0d1a0d; color: #4f4; border: 1px solid #2a5; }
    .api-toggle.closed  { background: #260d0d; color: #f55; border: 1px solid #722; }
    .season-actions { display: flex; gap: 0.5rem; margin-bottom: 0.5rem; flex-wrap: wrap; }
    input { background: #1a1a1a; color: #e0e0e0; border: 1px solid #333; border-radius: 4px;
            padding: 0.3rem 0.5rem; font-family: inherit; font-size: 12px; }
    .season-msg { font-size: 11px; color: #888; white-space: pre-wrap; }
  </style>
</head>
<body>
  <h1>⚽ LMS Dashboard</h1>
  ${leagueSections}
  <script>
    if ('serviceWorker' in navigator) navigator.serviceWorker.register('/sw.js');

    function esc(s) {
      return String(s).replace(/&/g,'&amp;').replace(/</g,'&lt;').replace(/>/g,'&gt;').replace(/"/g,'&quot;');
    }
    function fmt(iso) {
      if (!iso) return '—';
      return new Date(iso).toLocaleString('en-GB', {
        day:'2-digit', month:'short', hour:'2-digit', minute:'2-digit',
        timeZone:'UTC', timeZoneName:'short'
      });
    }

    async function load(key) {
      const btn = document.querySelector('#s-' + key + ' button');
      const out = document.getElementById('d-' + key);
      btn.disabled = true; btn.textContent = '…';
      try {
        const d = await fetch('/data/' + key).then(r => r.json());
        setToggle(key, d.phase);

        // D1 sync table
        const datasets = ['fixtures','standings','teams'];
        const syncRows = datasets.map(ds => {
          const r = d.sync.find(s => s.dataset === ds);
          return r
            ? '<tr><td>'+esc(ds)+'</td><td class="num">'+esc(r.row_count)+'</td><td class="ts">'+esc(fmt(r.synced_at))+'</td></tr>'
            : '<tr><td>'+esc(ds)+'</td><td colspan="2" class="missing">no sync yet</td></tr>';
        }).join('');

        // Fixture status breakdown
        const finished  = d.statusCounts.find(s => s.status === 'FINISHED')?.cnt  ?? 0;
        const scheduled = d.statusCounts.find(s => s.status === 'TIMED' || s.status === 'SCHEDULED');
        const inPlay    = d.statusCounts.find(s => s.status === 'IN_PLAY')?.cnt   ?? 0;
        const total     = d.statusCounts.reduce((a, s) => a + s.cnt, 0);
        const nextFix   = d.nextFixture
          ? 'Next: matchday '+esc(d.nextFixture.matchday)+' · '+esc(fmt(d.nextFixture.kickoff))
          : 'No upcoming fixtures';
        const seasonLine = '<div class="season">'
          + esc(finished)+' played · '+(inPlay ? esc(inPlay)+' live · ' : '')
          + esc(total - finished - (inPlay))+' remaining'
          + '</div><div class="next">'+nextFix+'</div>';

        // KV gate table
        const gateRows = ['scores','fixtures','standings'].map(g => {
          const gate = d.gates[g];
          const inFlight = gate.call > gate.refresh;
          const status = inFlight ? '<span style="color:#f66">in flight</span>' : '<span style="color:#4a4">settled</span>';
          return '<tr><td>'+esc(g)+'</td><td class="num">'+esc(gate.call)+'/'+esc(gate.refresh)+'</td>'
            + '<td>'+status+'</td><td class="ts">'+esc(fmt(gate.ts))+'</td></tr>';
        }).join('');

        // Scores cache
        const cacheNote = d.scoresCacheBytes !== null
          ? '<span class="badge badge-live">Scores cache: '+esc((d.scoresCacheBytes/1024).toFixed(1))+' KB</span>'
          : '<span class="badge badge-flight">Scores cache: empty</span>';

        out.innerHTML =
          '<h3>D1 — sync</h3>'
          + '<table><thead><tr><th>Dataset</th><th>Rows</th><th>Last synced</th></tr></thead><tbody>'+syncRows+'</tbody></table>'
          + seasonLine
          + '<h3>KV — gates</h3>'
          + '<table><thead><tr><th>Resource</th><th>call/refresh</th><th>Status</th><th>Last reset</th></tr></thead><tbody>'+gateRows+'</tbody></table>'
          + '<div style="margin-top:0.5rem">'+cacheNote+'</div>'
          + '<div class="fetched">Fetched '+esc(d.fetchedAt)+'</div>';
      } catch(e) {
        out.textContent = 'Error: ' + e.message;
      } finally {
        btn.disabled = false; btn.textContent = 'Refresh';
      }
    }

    function setToggle(key, phase) {
      const btn = document.getElementById('toggle-' + key);
      const isLive = phase !== 'closed';
      btn.textContent = isLive ? '🟢 LIVE — tap to block' : '🔴 BLOCKED — serving stale, tap to go live';
      btn.className = 'api-toggle ' + (isLive ? 'live' : 'closed');
      btn.dataset.phase = isLive ? 'live' : 'closed';
    }

    async function toggleApi(key) {
      const btn = document.getElementById('toggle-' + key);
      const next = btn.dataset.phase === 'closed' ? 'live' : 'closed';
      const msg = document.getElementById('season-msg-' + key);
      msg.textContent = 'Setting to ' + next + '…';
      try {
        const r = await fetch('/action/' + key + '/phase?value=' + next, { method: 'POST' }).then(r => r.json());
        if (!r.ok) { msg.textContent = 'Error: ' + (r.error || 'unknown'); return; }
        setToggle(key, r.phase);
        msg.textContent = r.phase === 'closed'
          ? 'Blocked — serving cached data only, no upstream calls.'
          : 'Live — normal polling resumed.';
      } catch (e) { msg.textContent = 'Error: ' + e.message; }
    }

    async function probeSeason(key) {
      const msg = document.getElementById('season-msg-' + key);
      const year = document.getElementById('year-' + key).value;
      msg.textContent = 'Probing ' + (year || 'current season') + ' upstream (read-only)…';
      try {
        const q = year ? ('?season=' + year) : '';
        const r = await fetch('/action/' + key + '/probe' + q, { method: 'POST' }).then(r => r.json());
        msg.textContent = r.ok
          ? 'Season ' + r.season + ': ' + r.rowCount + ' rows. Sample team ids: ' + (r.sampleTeamIds || []).join(', ')
          : 'Probe failed: ' + (r.error || 'unknown');
      } catch (e) { msg.textContent = 'Error: ' + e.message; }
    }

    async function syncSeason(key) {
      const msg = document.getElementById('season-msg-' + key);
      const year = document.getElementById('year-' + key).value;
      if (!confirm('Sync ' + (year || 'current season') + ' for ' + key.toUpperCase() + ' now?\\n\\nThis replaces teams/fixtures/standings in D1 immediately. Phase is left exactly as it is — this does not go Live.')) return;
      msg.textContent = 'Syncing ' + (year || 'current season') + '…';
      try {
        const q = year ? ('?season=' + year) : '';
        const r = await fetch('/action/' + key + '/sync' + q, { method: 'POST' }).then(r => r.json());
        msg.textContent = r.ok ? 'Synced: ' + JSON.stringify(r.synced) + '.' : 'Sync failed: ' + JSON.stringify(r);
      } catch (e) { msg.textContent = 'Error: ' + e.message; }
    }
  </script>
</body>
</html>`;
  return new Response(html, { headers: { "Content-Type": "text/html; charset=utf-8" } });
}

// Season-control actions — see lms-season-phase-rollover memory for the
// runbook these map to. The phase flag POSTs to the league's own KV directly
// (already bound here, same as the read-only gate display above); sync/probe
// instead proxy to the league Worker's public /admin endpoints, since only it
// holds the FOOTBALL_DATA_TOKEN needed to call football-data.org. `season` is
// optional on both — omitted, the league Worker defaults to the correct
// current season itself (currentSeasonYear()); this dashboard does NOT
// duplicate that calculation.
//
// Sync deliberately never touches the phase flag — phase is a pure on/off
// switch for automatic polling, sync is an explicit one-off pull, and the two
// are independent by design (see seasonPhase.ts on the league Worker).
async function setPhase(kv: KVNamespace, value: string): Promise<Response> {
  if (value !== "live" && value !== "closed") {
    return Response.json({ ok: false, error: "value must be live|closed" }, { status: 400 });
  }
  await kv.put(PHASE_KEY, value);
  return Response.json({ ok: true, phase: value });
}

async function proxySync(url: string, token: string | undefined, season: string | null): Promise<Response> {
  if (!token) return Response.json({ ok: false, error: "admin token not configured for this league" }, { status: 500 });
  const q = season ? `&season=${encodeURIComponent(season)}` : "";
  const upstream = await fetch(`${url}/admin/sync?what=all${q}`, {
    method: "POST",
    headers: { Authorization: `Bearer ${token}` },
  });
  const body = await upstream.json();
  if (!upstream.ok) return Response.json({ ok: false, ...(body as object) }, { status: upstream.status });
  return Response.json(body);
}

async function proxyProbe(url: string, token: string | undefined, season: string | null): Promise<Response> {
  if (!token) return Response.json({ ok: false, error: "admin token not configured for this league" }, { status: 500 });
  const q = season ? `?season=${encodeURIComponent(season)}` : "";
  const upstream = await fetch(`${url}/admin/probe-standings${q}`, {
    headers: { Authorization: `Bearer ${token}` },
  });
  const body = await upstream.json() as { ok: boolean; season?: number; rowCount?: number; rows?: { teamId: number }[] };
  return Response.json({
    ok: body.ok, season: body.season, rowCount: body.rowCount,
    sampleTeamIds: body.rows?.slice(0, 5).map((r) => r.teamId),
  });
}

export default {
  async fetch(req: Request, env: Env): Promise<Response> {
    const { pathname, searchParams } = new URL(req.url);

    if (pathname === "/manifest.json") return manifestJson();
    if (pathname === "/sw.js")         return serviceWorkerJs();
    if (pathname === "/icon.svg")      return iconSvg();

    if (pathname.startsWith("/data/")) {
      const key = pathname.slice(6);
      const league = LEAGUES.find((l) => l.key === key);
      if (!league) return new Response("not found", { status: 404 });
      const data = await fetchLeague(env[league.db], env[league.kv]);
      return Response.json({
        fetchedAt: new Date().toLocaleString("en-GB", {
          day: "2-digit", month: "short", year: "numeric",
          hour: "2-digit", minute: "2-digit", timeZone: "UTC", timeZoneName: "short",
        }),
        ...data,
      });
    }

    const actionMatch = pathname.match(/^\/action\/([a-z]+)\/(phase|sync|probe)$/);
    if (actionMatch && req.method === "POST") {
      const [, key, action] = actionMatch;
      const league = LEAGUES.find((l) => l.key === key);
      if (!league) return new Response("not found", { status: 404 });
      if (action === "phase") return setPhase(env[league.kv], searchParams.get("value") ?? "");
      const season = searchParams.get("season"); // optional — null lets the league Worker pick the current season itself
      const token = env[league.tokenEnv];
      if (action === "sync") return proxySync(league.url, token, season);
      return proxyProbe(league.url, token, season);
    }

    return shellHtml();
  },
} satisfies ExportedHandler<Env>;
