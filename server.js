'use strict';
const http = require('node:http');
const fs = require('node:fs');
const path = require('node:path');
const crypto = require('node:crypto');

const ROOT = __dirname;
const DATA = path.join(ROOT, 'data.json');
const PORT = Number(process.env.PORT || 8787);
const ADMIN_PASSWORD = process.env.ADMIN_PASSWORD || 'camkey2026';

const ALPHA = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';

function load() {
  if (!fs.existsSync(DATA)) {
    const init = {
      pkg: {
        slug: 'obs-cam',
        name: 'OBS Cam',
        bundleId: 'com.camkey.obscam',
        version: '1.0.0',
        size: '—',
        icon: '',
        plistUrl: '',
        ipaUrl: ''
      },
      keys: [],
      sessions: []
    };
    fs.writeFileSync(DATA, JSON.stringify(init, null, 2));
    return init;
  }
  return JSON.parse(fs.readFileSync(DATA, 'utf8'));
}
let db = load();
const save = () => fs.writeFileSync(DATA, JSON.stringify(db, null, 2));

function newKey() {
  const block = () => Array.from({ length: 4 }, () => ALPHA[crypto.randomInt(ALPHA.length)]).join('');
  return [block(), block(), block(), block()].join('-');
}
function token() { return crypto.randomBytes(24).toString('hex'); }
function now() { return Date.now(); }

function keyState(k) {
  if (k.revoked) return 'revoked';
  if (!k.udid) return 'unused';
  if (k.expiresAt && k.expiresAt < now()) return 'expired';
  return 'active';
}
function pubKey(k) {
  return {
    key: k.key, note: k.note || '', udid: k.udid || null,
    createdAt: k.createdAt, activatedAt: k.activatedAt || null,
    days: k.days || null,
    expiresAt: k.expiresAt || (k.createdAt + (k.days || 0) * 864e5),
    activated: !!k.udid,
    state: keyState(k)
  };
}
function findKey(s) { return db.keys.find(k => k.key === String(s || '').toUpperCase().trim()); }

function json(res, code, obj) {
  const body = JSON.stringify(obj);
  res.writeHead(code, {
    'content-type': 'application/json; charset=utf-8',
    'cache-control': 'no-store',
    'access-control-allow-origin': '*',
    'access-control-allow-headers': 'authorization,content-type',
    'access-control-allow-methods': 'GET,POST,DELETE,OPTIONS'
  });
  res.end(body);
}
function html(res, code, body) {
  res.writeHead(code, {
    'content-type': 'text/html; charset=utf-8',
    'cache-control': 'no-store, no-cache, must-revalidate, max-age=0',
    pragma: 'no-cache',
    expires: '0'
  });
  res.end(body);
}
function readBody(req) {
  return new Promise((resolve) => {
    let s = '';
    req.on('data', (c) => { s += c; if (s.length > 1e6) req.destroy(); });
    req.on('end', () => { try { resolve(s ? JSON.parse(s) : {}); } catch { resolve({}); } });
  });
}
function authed(req) {
  const h = String(req.headers.authorization || '');
  const bearer = h.replace(/^Bearer\s+/i, '');
  const ck = String(req.headers.cookie || '').match(/(?:^|;\s*)ck=([a-f0-9]+)/);
  const t = bearer || (ck ? ck[1] : '');
  return db.sessions.find(s => s.token === t && s.exp > now());
}
function formBody(req) {
  return new Promise((resolve) => {
    let s = '';
    req.on('data', (c) => { s += c; if (s.length > 1e5) req.destroy(); });
    req.on('end', () => resolve(new URLSearchParams(s)));
  });
}

/* ---------- public pages ---------- */

function publicPage() {
  return `<!doctype html><html lang="vi"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>OBS Cam</title>
<link rel="stylesheet" href="/style.css"></head>
<body class="center">
<main class="card" id="app">
  <div class="icon" id="icon"></div>
  <h1 id="name">…</h1>
  <div class="meta"><span id="ver"></span><span id="size"></span></div>
  <a class="btn" id="install" href="#">Cài đặt</a>
  <div class="line" id="msg">Mở app và nhập key sau khi cài</div>
</main>
<script>
const slug = location.pathname.split('/').pop();
const $ = id => document.getElementById(id);
(async () => {
  const r = await fetch('/api/v1/public/package/' + slug).then(r => r.json());
  if (!r.ok) { $('msg').textContent = 'Không có gói'; return; }
  const p = r.package;
  $('name').textContent = p.name;
  $('ver').textContent = 'v' + p.version;
  $('size').textContent = p.size || '';
  if (p.icon) { $('icon').style.backgroundImage = 'url(' + p.icon + ')'; }
  if (p.plistUrl) $('install').href = 'itms-services://?action=download-manifest&url=' + encodeURIComponent(p.plistUrl);
  else { $('install').classList.add('off'); $('install').textContent = 'Chưa có gói'; }
})();

</script></body></html>`;
}

/* ---------- admin page ---------- */

function adminPage(authedNow) {
  return `<!doctype html><html lang="vi"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>CAMKEY</title><link rel="stylesheet" href="/style.css"></head>
<body>
<div id="login" class="center"${authedNow ? ' hidden' : ''}>
  <form class="card narrow" method="post" action="/keys?v=5">
    <h1>CAMKEY</h1>
    <input id="pw" name="p" type="password" placeholder="Mật khẩu" autocomplete="off" autofocus>
    <button class="btn" type="submit">Đăng nhập</button>
    <div class="line" id="lerr"></div>
  </form>
</div>

<div id="app" class="wrap"${authedNow ? '' : ' hidden'}>
  <header>
    <b>CAMKEY</b><span class="muted" style="font-size:11px">v5</span>
    <span class="grow"></span>
    <span id="stat" class="muted"></span>
    <button class="btn tiny ghost" id="out">Thoát</button>
  </header>

  <section class="card">
    <div class="row">
      <label>Số lượng<input id="qty" type="number" value="10" min="1" max="500"></label>
      <label>Số ngày<input id="days" type="number" value="30" min="1" max="3650"></label>
      <label>Ghi chú<input id="note" placeholder="—"></label>
      <button class="btn" id="gen">Tạo key</button>
    </div>
    <pre id="out2" class="out"></pre>
  </section>

  <section class="card">
    <div class="row between"><b>Key</b><input id="search" placeholder="Tìm key / UDID"></div>
    <div class="tablewrap">
    <table id="tbl"><thead><tr><th>Key</th><th>Trạng thái</th><th class="col-udid">UDID</th><th>Hết hạn</th><th></th></tr></thead><tbody></tbody></table>
    </div>
  </section>

  <section class="card">
    <div class="row between"><b>Gói</b><span class="muted" id="slug"></span></div>
    <div class="row">
      <label>Tên<input id="pname"></label>
      <label>Phiên bản<input id="pver"></label>
      <label>Bundle ID<input id="pbundle"></label>
    </div>
    <div class="row">
      <label class="wide">Icon URL<input id="picon"></label>
      <label class="wide">IPA URL<input id="pipa"></label>
    </div>
    <div class="row">
      <label class="wide">Plist URL (tự sinh nếu để trống)<input id="pplist"></label>
    </div>
    <button class="btn" id="savepkg">Lưu</button>
    <div class="line" id="pmsg"></div>
  </section>
</div>

<script>
const $ = id => document.getElementById(id);
let T = localStorage.getItem('camkey_token') || '';

if (location.search.indexOf('e=1') >= 0) { $('lerr').textContent = 'Sai mật khẩu'; $('lerr').style.color = '#f87171'; $('lerr').style.fontWeight = '600'; }

const api = async (p, o = {}) => {
  const r = await fetch('/api/v1' + p, {
    ...o,
    headers: { 'content-type': 'application/json', ...(T ? { authorization: 'Bearer ' + T } : {}), ...(o.headers || {}) }
  });
  return r.json();
};

$('out').onclick = async () => { localStorage.removeItem('camkey_token'); location.href = '/logout'; };

function fmt(t) { if (!t) return '—'; const d = new Date(t); return d.toLocaleDateString('vi-VN') + ' ' + d.toLocaleTimeString('vi-VN', { hour: '2-digit', minute: '2-digit' }); }
const badge = s => '<span class="badge ' + s + '">' + ({ unused: 'Chưa dùng', active: 'Hoạt động', expired: 'Hết hạn', revoked: 'Thu hồi' }[s] || s) + '</span>';

async function refresh() {
  const r = await api('/admin/keys');
  if (!r.ok) return;
  const q = $('search').value.toLowerCase();
  const rows = r.keys.filter(k => !q || k.key.toLowerCase().includes(q) || (k.udid || '').toLowerCase().includes(q));
  $('tbl').tBodies[0].innerHTML = rows.map(k => '<tr><td class="mono">' + k.key + '</td><td>' + badge(k.state) + '</td><td class="mono muted col-udid">' + (k.udid ? k.udid.slice(0, 16) + '…' : '—') + '</td><td class="nowrap">' + fmt(k.expiresAt) + '</td><td class="right nowrap"><button class="btn tiny ghost" data-copy="' + k.key + '">Copy</button> ' + (k.state === 'revoked' ? '' : '<button class="btn tiny warn" data-rev="' + k.key + '">Thu hồi</button> ') + '<button class="btn tiny danger" data-del="' + k.key + '">Xóa</button></td></tr>').join('');
  const s = r.stats;
  $('stat').textContent = s.total + ' key · ' + s.active + ' active · ' + s.unused + ' chưa dùng';
}

document.addEventListener('click', async (e) => {
  const c = e.target.dataset.copy, rv = e.target.dataset.rev, dl = e.target.dataset.del;
  if (c) navigator.clipboard.writeText(c);
  if (rv) { await api('/admin/keys/' + rv, { method: 'DELETE' }); refresh(); }
  if (dl) { await api('/admin/keys/' + dl + '?hard=1', { method: 'DELETE' }); refresh(); }
});

$('gen').onclick = async () => {
  const r = await api('/admin/keys', {
    method: 'POST',
    body: JSON.stringify({ count: +$('qty').value, days: +$('days').value, note: $('note').value })
  });
  if (!r.ok) return;
  $('out2').textContent = r.keys.join('\\n');
  $('out2').classList.add('show');
  refresh();
};
$('search').oninput = refresh;

async function loadPkg() {
  const r = await api('/admin/package');
  if (!r.ok) return;
  const p = r.package;
  $('slug').textContent = '/p/' + p.slug;
  $('pname').value = p.name || ''; $('pver').value = p.version || '';
  $('pbundle').value = p.bundleId || ''; $('picon').value = p.icon || '';
  $('pplist').value = p.plistUrl || '';
  $('pipa').value = p.ipaUrl || '';
}
$('savepkg').onclick = async () => {
  const r = await api('/admin/package', {
    method: 'POST',
    body: JSON.stringify({ name: $('pname').value, version: $('pver').value, bundleId: $('pbundle').value, icon: $('picon').value, plistUrl: $('pplist').value, ipaUrl: $('pipa').value })
  });
  $('pmsg').textContent = r.ok ? 'Đã lưu' : 'Lỗi';
  setTimeout(() => $('pmsg').textContent = '', 2000);
};

async function boot() {
  const me = await api('/user/me');
  if (!me.ok) { $('login').hidden = false; $('app').hidden = true; return; }
  $('login').hidden = true; $('app').hidden = false;
  await Promise.all([refresh(), loadPkg()]);
}
boot();
</script></body></html>`;
}

/* ---------- style ---------- */

const CSS = `
*{box-sizing:border-box}
[hidden]{display:none !important}
:root{--bg:#0b0d12;--card:#141821;--line:#242b39;--fg:#e8ecf4;--mut:#8b96ab;--acc:#3b82f6;--ok:#16a34a;--warn:#d97706;--bad:#dc2626}
html,body{margin:0;height:100%}
body{background:var(--bg);color:var(--fg);font:14px/1.5 -apple-system,BlinkMacSystemFont,"Segoe UI",Roboto,sans-serif}
.center{display:flex;align-items:center;justify-content:center;min-height:100vh;padding:20px}
.wrap{max-width:1220px;margin:0 auto;padding:20px;display:flex;flex-direction:column;gap:14px}
header{display:flex;align-items:center;gap:10px}
.grow{flex:1}
.card{background:var(--card);border:1px solid var(--line);border-radius:14px;padding:16px;display:flex;flex-direction:column;gap:12px}
.card.narrow{width:320px}
h1{font-size:20px;margin:0 0 4px;text-align:center}
.row{display:flex;gap:10px;flex-wrap:wrap;align-items:flex-end}
.row.between{justify-content:space-between;align-items:center}
label{display:flex;flex-direction:column;gap:6px;font-size:12px;color:var(--mut);flex:1;min-width:110px}
label.wide{min-width:240px}
input{background:#0e1218;border:1px solid var(--line);border-radius:10px;padding:10px 12px;color:var(--fg);font:inherit;width:100%}
input:focus{outline:none;border-color:var(--acc)}
.btn{background:var(--acc);border:0;border-radius:10px;padding:10px 16px;color:#fff;font:inherit;font-weight:600;cursor:pointer;text-align:center;text-decoration:none;display:inline-block;white-space:nowrap}
.btn.ghost{background:transparent;border:1px solid var(--line);color:var(--fg)}
.btn.danger{background:transparent;border:1px solid var(--bad);color:var(--bad)}
.btn.warn{background:transparent;border:1px solid var(--warn);color:var(--warn)}
.btn.tiny{padding:5px 10px;font-size:12px;font-weight:500}
.btn.off{opacity:.5;pointer-events:none}
.muted{color:var(--mut)}
.mono{font-family:ui-monospace,Menlo,Consolas,monospace}
.right{text-align:right}
.line{font-size:12px;color:var(--mut);min-height:16px;text-align:center}
table{width:100%;border-collapse:collapse;font-size:13px;table-layout:auto}
th{text-align:left;color:var(--mut);font-weight:500;font-size:12px;padding:8px 10px;border-bottom:1px solid var(--line);white-space:nowrap}
td{padding:10px;border-bottom:1px solid #1b2130;white-space:nowrap}
.nowrap{white-space:nowrap}
.tablewrap{overflow-x:auto;max-width:100%}
.badge{font-size:11px;padding:2px 8px;border-radius:20px;border:1px solid currentColor}
.badge.unused{color:var(--mut)}.badge.active{color:var(--ok)}.badge.expired{color:var(--warn)}.badge.revoked{color:var(--bad)}
.out{display:none;background:#0e1218;border:1px solid var(--line);border-radius:10px;padding:12px;margin:0;font:12px/1.7 ui-monospace,Consolas,monospace;white-space:pre-wrap;max-height:220px;overflow:auto}
.out.show{display:block}
#app .card{min-width:300px;max-width:360px;align-items:stretch}
.icon{width:84px;height:84px;margin:4px auto 0;border-radius:20px;background:#1b2130 center/cover no-repeat}
.meta{display:flex;gap:10px;justify-content:center;color:var(--mut);font-size:12px}
.kv{display:flex;flex-direction:column;gap:6px;background:#0e1218;border:1px solid var(--line);border-radius:10px;padding:10px 12px;font-size:12px}
.kv>div{display:flex;justify-content:space-between;gap:10px}
.kv span{color:var(--mut)}
.kv b{font-weight:600;text-align:right}
@media(max-width:640px){.wrap{padding:12px}.card{padding:14px}.col-udid{display:none}table{font-size:12px}th,td{padding:8px 6px}.btn.tiny{padding:5px 8px;font-size:11px}}
`;

/* ---------- router ---------- */

const server = http.createServer(async (req, res) => {
  const url = new URL(req.url, 'http://x');
  const p = url.pathname;

  if (req.method === 'OPTIONS') return json(res, 204, {});

  if (p === '/style.css') {
    res.writeHead(200, { 'content-type': 'text/css; charset=utf-8', 'cache-control': 'max-age=3600' });
    return res.end(CSS);
  }
  if (p === '/' || p === '/admin' || p === '/keys' || p === '/panel') {
    if (req.method === 'POST') {
      const body = await formBody(req);
      const entered = String(body.get('p') ?? body.get('password') ?? '').trim();
      if (entered !== ADMIN_PASSWORD) {
        console.log('[login fail] len=' + entered.length);
        res.writeHead(302, { location: '/keys?e=1&v=3' });
        return res.end();
      }
      const t = token();
      db.sessions = db.sessions.filter(s => s.exp > now());
      db.sessions.push({ token: t, exp: now() + 7 * 864e5 });
      save();
      res.writeHead(302, {
        location: '/keys',
        'set-cookie': `ck=${t}; Path=/; HttpOnly; SameSite=Lax; Max-Age=604800`
      });
      return res.end();
    }
    return html(res, 200, adminPage(!!authed(req)));
  }
  if (p.startsWith('/p/')) return html(res, 200, publicPage());

  if (p === '/logout') {
    const ck = String(req.headers.cookie || '').match(/(?:^|;\s*)ck=([a-f0-9]+)/);
    if (ck) { db.sessions = db.sessions.filter(s => s.token !== ck[1]); save(); }
    res.writeHead(302, { location: '/keys', 'set-cookie': 'ck=; Path=/; Max-Age=0' });
    return res.end();
  }

  if (p === '/api/v1/auth/login' && req.method === 'POST') {
    const b = await readBody(req);
    if (String(b.password || '') !== ADMIN_PASSWORD) return json(res, 401, { ok: false });
    const t = token();
    db.sessions = db.sessions.filter(s => s.exp > now());
    db.sessions.push({ token: t, exp: now() + 7 * 864e5 });
    save();
    return json(res, 200, { ok: true, token: t });
  }
  if (p === '/api/v1/auth/logout') {
    const h = String(req.headers.authorization || '').replace(/^Bearer\s+/i, '');
    db.sessions = db.sessions.filter(s => s.token !== h);
    save();
    return json(res, 200, { ok: true });
  }
  if (p === '/api/v1/user/me') {
    return authed(req) ? json(res, 200, { ok: true }) : json(res, 401, { ok: false });
  }

  if (p === '/api/v1/admin/keys' && req.method === 'GET') {
    if (!authed(req)) return json(res, 401, { ok: false });
    const list = db.keys.map(pubKey).sort((a, b) => b.createdAt - a.createdAt);
    const stats = {
      total: list.length,
      unused: list.filter(k => k.state === 'unused').length,
      active: list.filter(k => k.state === 'active').length
    };
    return json(res, 200, { ok: true, keys: list, stats });
  }
  if (p === '/api/v1/admin/keys' && req.method === 'POST') {
    if (!authed(req)) return json(res, 401, { ok: false });
    const b = await readBody(req);
    const count = Math.max(1, Math.min(500, Number(b.count) || 1));
    const days = Math.max(1, Math.min(3650, Number(b.days) || 30));
    const out = [];
    for (let i = 0; i < count; i++) {
      let k = newKey();
      while (db.keys.some(x => x.key === k)) k = newKey();
      db.keys.push({ key: k, days, note: String(b.note || '').slice(0, 80), createdAt: now(), udid: null, expiresAt: null, revoked: false });
      out.push(k);
    }
    save();
    return json(res, 200, { ok: true, keys: out });
  }
  if (p.startsWith('/api/v1/admin/keys/') && req.method === 'DELETE') {
    if (!authed(req)) return json(res, 401, { ok: false });
    const key = decodeURIComponent(p.split('/').pop());
    const k = findKey(key);
    if (!k) return json(res, 404, { ok: false });
    if (url.searchParams.get('hard') === '1') {
      db.keys = db.keys.filter(x => x.key !== k.key);
    } else {
      k.revoked = true;
    }
    save();
    return json(res, 200, { ok: true });
  }

  if (p === '/api/v1/admin/package') {
    if (!authed(req)) return json(res, 401, { ok: false });
    if (req.method === 'GET') return json(res, 200, { ok: true, package: db.pkg });
    const b = await readBody(req);
    db.pkg = {
      ...db.pkg,
      name: String(b.name ?? db.pkg.name).slice(0, 60),
      version: String(b.version ?? db.pkg.version).slice(0, 20),
      bundleId: String(b.bundleId ?? db.pkg.bundleId).slice(0, 120),
      icon: String(b.icon ?? db.pkg.icon).slice(0, 500),
      plistUrl: String(b.plistUrl ?? db.pkg.plistUrl).slice(0, 500),
      ipaUrl: String(b.ipaUrl ?? db.pkg.ipaUrl).slice(0, 500),
      size: String(b.size ?? db.pkg.size).slice(0, 20)
    };
    save();
    return json(res, 200, { ok: true, package: db.pkg });
  }

  if (p.startsWith('/api/v1/public/package/')) {
    const slug = p.split('/').pop();
    if (slug !== db.pkg.slug) return json(res, 404, { ok: false });
    const proto = String(req.headers['x-forwarded-proto'] || 'http').split(',')[0];
    const host = req.headers.host;
    const pkg = { ...db.pkg };
    if (pkg.ipaUrl) pkg.plistUrl = `${proto}://${host}/plist/${pkg.slug}.plist`;
    return json(res, 200, { ok: true, package: pkg });
  }

  if (p.startsWith('/plist/') && p.endsWith('.plist')) {
    const slug = p.slice(7, -6);
    if (slug !== db.pkg.slug || !db.pkg.ipaUrl) {
      res.writeHead(404, { 'content-type': 'text/plain' });
      return res.end('no package');
    }
    const esc = (s) => String(s || '').replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;');
    const xml = `<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "https://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict><key>items</key><array><dict><key>assets</key><array><dict>
<key>kind</key><string>software-package</string>
<key>url</key><string>${esc(db.pkg.ipaUrl)}</string>
</dict>${db.pkg.icon ? `<dict><key>kind</key><string>display-image</string><key>needs-shine</key><false/><key>url</key><string>${esc(db.pkg.icon)}</string></dict>` : ''}</array>
<key>metadata</key><dict>
<key>bundle-identifier</key><string>${esc(db.pkg.bundleId)}</string>
<key>bundle-version</key><string>${esc(db.pkg.version)}</string>
<key>kind</key><string>software</string>
<key>title</key><string>${esc(db.pkg.name)}</string>
</dict></dict></array></dict></plist>`;
    res.writeHead(200, { 'content-type': 'application/xml; charset=utf-8', 'cache-control': 'no-store' });
    return res.end(xml);
  }

  if (p === '/api/v1/public/redeem' && req.method === 'POST') {
    const b = await readBody(req);
    const k = findKey(b.key);
    const udid = String(b.udid || '').trim();
    if (!k) return json(res, 404, { ok: false, message: 'Key không tồn tại' });
    if (k.revoked) return json(res, 403, { ok: false, message: 'Key đã bị thu hồi' });
    if (!udid) return json(res, 400, { ok: false, message: 'Thiếu UDID' });
    if (k.udid && k.udid !== udid) return json(res, 409, { ok: false, message: 'Key đã dùng trên thiết bị khác' });
    if (!k.udid) {
      k.udid = udid;
      k.deviceName = String(b.name || '').slice(0, 60) || null;
      k.activatedAt = now();
      k.expiresAt = now() + k.days * 864e5;
      save();
    }
    if (k.expiresAt < now()) return json(res, 403, { ok: false, message: 'Key đã hết hạn' });
    return json(res, 200, {
      ok: true,
      message: 'Kích hoạt · hết hạn ' + new Date(k.expiresAt).toLocaleDateString('vi-VN'),
      expiresAt: k.expiresAt,
      days: k.days,
      deviceName: k.deviceName || '',
      udid
    });
  }

  if (p === '/api/v1/public/check' && req.method === 'POST') {
    const b = await readBody(req);
    const k = findKey(b.key);
    const udid = String(b.udid || '').trim();
    if (!k) return json(res, 200, { ok: false, valid: false, message: 'invalid' });
    const valid = !k.revoked && k.udid === udid && k.expiresAt > now();
    return json(res, 200, {
      ok: true, valid, state: keyState(k),
      expiresAt: k.expiresAt || null,
      days: k.days,
      deviceName: k.deviceName || ''
    });
  }

  json(res, 404, { ok: false, message: 'not found' });
});

server.listen(PORT, () => console.log('CAMKEY on http://127.0.0.1:' + PORT));
