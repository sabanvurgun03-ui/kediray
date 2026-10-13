// KediRay anonim kullanım sayacı (Cloudflare Worker). Yalnızca izin veren kullanıcılar günde bir kez POST /ping gönderir.
// Saklanan: rastgele kurulum kimliği, sürüm, uygulama adı, son görülme zamanı. IP ADRESİ SAKLANMAZ (kod CF-Connecting-IP'yi okumaz).
// Gerekenler: KV bağlantısı "STATS", gizli değişken "ADMIN_TOKEN" (yönetici şifresi).

const APPS = ['kediray', 'aw1k'];
const TTL = 35 * 24 * 3600;          // 35 gün ping gelmeyen kayıt kendiliğinden silinir
const DAY = 24 * 3600 * 1000;

const json = (o, st = 200) => new Response(JSON.stringify(o), { status: st, headers: { 'content-type': 'application/json', 'cache-control': 'no-store' } });

function safeEq(a, b) { // sabit zamanlı karşılaştırma
	if (typeof a !== 'string' || typeof b !== 'string' || a.length !== b.length) return false;
	let r = 0;
	for (let i = 0; i < a.length; i++) r |= a.charCodeAt(i) ^ b.charCodeAt(i);
	return r === 0;
}

async function ping(req, env) {
	let d;
	try { d = await req.json(); } catch (e) { return json({ ok: false }, 400); }
	const app = String(d.app || ''), id = String(d.id || ''), v = String(d.v || '');
	if (!APPS.includes(app) || !/^[0-9a-f]{16,64}$/.test(id) || !/^[0-9A-Za-z._-]{1,20}$/.test(v)) return json({ ok: false }, 400);
	const key = 'u:' + app + ':' + id, now = Date.now();
	if (!env.STATS) return json({ ok: false }, 500);
	const cur = await env.STATS.getWithMetadata(key);
	if (cur.metadata && cur.metadata.v === v && now - cur.metadata.t < 20 * 3600 * 1000) return json({ ok: true }); // günde bir yazma yeter
	await env.STATS.put(key, '1', { expirationTtl: TTL, metadata: { v, t: now } });
	return json({ ok: true });
}

async function stats(env) {
	const now = Date.now(), out = {};
	for (const a of APPS) out[a] = { total: 0, d1: 0, d7: 0, d30: 0, versions: {} };
	let cursor;
	do {
		const l = await env.STATS.list({ prefix: 'u:', cursor });
		for (const k of l.keys) {
			const a = k.name.split(':')[1], m = k.metadata || {}, o = out[a];
			if (!o || !m.t) continue;
			const age = now - m.t;
			o.total++;
			if (age <= 1.5 * DAY) o.d1++;
			if (age <= 7 * DAY) o.d7++;
			if (age <= 30 * DAY) { o.d30++; o.versions[m.v] = (o.versions[m.v] || 0) + 1; }
		}
		cursor = l.list_complete ? undefined : l.cursor;
	} while (cursor);
	return out;
}

const PAGE = `<!doctype html><meta charset=utf-8><meta name=viewport content="width=device-width,initial-scale=1"><title>KediRay sayaç</title>
<style>body{font:16px system-ui;max-width:640px;margin:24px auto;padding:0 16px;background:#14161a;color:#e8e8e8}input,button{font:inherit;padding:8px 12px;border-radius:8px;border:1px solid #444;background:#222;color:#eee}
button{cursor:pointer;background:#3b7;border:0;color:#052}.c{background:#1e2127;border-radius:12px;padding:14px 16px;margin:12px 0}.n{font-size:32px;font-weight:700}.g{display:flex;gap:12px;flex-wrap:wrap}.g div{flex:1;min-width:90px}small{opacity:.7}</style>
<h2>KediRay sayaç</h2><div id=lg><input id=t type=password placeholder="yönetici şifresi"> <button onclick=go()>Gir</button></div><div id=o></div>
<script>
async function go(){const t=document.getElementById('t')?document.getElementById('t').value:sessionStorage.k;
const r=await fetch('/api/stats',{headers:{authorization:'Bearer '+t}});if(!r.ok){let m='Şifre yanlış';if(r.status==500){try{m=(await r.json()).error}catch(e){m='Sunucu hatası'}}document.getElementById('o').textContent=m;return}
sessionStorage.k=t;document.getElementById('lg').style.display='none';const d=await r.json();let h='';
for(const a in d){const x=d[a];h+='<div class=c><b>'+a+'</b><div class=g><div><div class=n>'+x.d1+'</div><small>son 1 gün</small></div><div><div class=n>'+x.d7+'</div><small>son 7 gün</small></div><div><div class=n>'+x.d30+'</div><small>son 30 gün</small></div></div><small>Sürümler (30 gün): '+(Object.entries(x.versions).sort().map(e=>e[0]+': '+e[1]).join(' · ')||'—')+'</small></div>'}
document.getElementById('o').innerHTML=h+'<small>Yalnızca izin veren kullanıcılar sayılır.</small>'}
if(sessionStorage.k)go();
</script>`;

export default {
	async fetch(req, env) {
		const u = new URL(req.url);
		if (req.method === 'POST' && u.pathname === '/ping') return ping(req, env);
		if (req.method === 'GET' && u.pathname === '/admin') return new Response(PAGE, { headers: { 'content-type': 'text/html; charset=utf-8', 'cache-control': 'no-store' } });
		if (req.method === 'GET' && u.pathname === '/api/stats') {
			const t = (req.headers.get('authorization') || '').replace(/^Bearer /, '');
			if (!env.ADMIN_TOKEN || !safeEq(t, env.ADMIN_TOKEN)) return json({ ok: false }, 401);
			if (!env.STATS) return json({ ok: false, error: 'KV bağlı değil: Settings → Bindings → KV namespace, değişken adı STATS' }, 500);
			try { return json(await stats(env)); } catch (e) { return json({ ok: false, error: 'KV okunamadı' }, 500); }
		}
		return new Response('KediRay', { status: 404 });
	}
};
