// KediRay anonim kullanım sayacı (Cloudflare Worker). Yalnızca izin veren kullanıcılar günde bir kez POST /ping gönderir.
// Saklanan: rastgele kurulum kimliği, sürüm, uygulama adı, son görülme zamanı. IP ADRESİ SAKLANMAZ (kod CF-Connecting-IP'yi okumaz).
// Gerekenler: KV bağlantısı "STATS", gizli değişkenler "ADMIN_USER" (ana yönetici kullanıcı adı) ve "ADMIN_TOKEN" (ana yönetici şifresi).
// Şifremi unuttum için ayrıca: "RESEND_API_KEY" ve "RESET_EMAIL" (maillerin gideceği adres).

const APPS = ['kediray', 'aw1k'];
const TTL = 35 * 24 * 3600;          // 35 gün ping gelmeyen kayıt kendiliğinden silinir
const DAY = 24 * 3600 * 1000;
const SESSION_MS = 7 * DAY;          // admin oturumu 7 gün açık kalır
const MAX_FAILS = 10;                // 10 dakika içinde bu kadar hatalı girişten sonra giriş kilitlenir
const ITER = 20000;                  // PBKDF2 tur sayısı (ücretsiz planın CPU sınırına uygun tutuldu)
const USER_RE = /^[a-zA-Z0-9._-]{3,32}$/;
const enc = new TextEncoder();

const json = (o, st = 200, h = {}) => new Response(JSON.stringify(o), { status: st, headers: { 'content-type': 'application/json', 'cache-control': 'no-store', ...h } });

function safeEq(a, b) { // sabit zamanlı karşılaştırma
	if (typeof a !== 'string' || typeof b !== 'string' || a.length !== b.length) return false;
	let r = 0;
	for (let i = 0; i < a.length; i++) r |= a.charCodeAt(i) ^ b.charCodeAt(i);
	return r === 0;
}

const toHex = b => [...new Uint8Array(b)].map(x => x.toString(16).padStart(2, '0')).join('');
const randHex = n => toHex(crypto.getRandomValues(new Uint8Array(n)));
const lc = s => String(s || '').trim().toLowerCase();
const primaryOf = env => lc(env.ADMIN_USER);
const escHtml = s => String(s).replace(/[&<>"']/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));

async function sha256hex(s) { return toHex(await crypto.subtle.digest('SHA-256', enc.encode(s))); }

async function hmac(secret, data) {
	const key = await crypto.subtle.importKey('raw', enc.encode(secret), { name: 'HMAC', hash: 'SHA-256' }, false, ['sign']);
	return toHex(await crypto.subtle.sign('HMAC', key, enc.encode(data)));
}

async function pbkdf2(password, saltHex, iterations) {
	const key = await crypto.subtle.importKey('raw', enc.encode(password), 'PBKDF2', false, ['deriveBits']);
	const salt = new Uint8Array(saltHex.match(/../g).map(h => parseInt(h, 16)));
	return toHex(await crypto.subtle.deriveBits({ name: 'PBKDF2', salt, iterations, hash: 'SHA-256' }, key, 256));
}

// ---- Yöneticiler ----
// Ana yönetici: ADMIN_USER + ADMIN_TOKEN (secret). Şifresi sıfırlanırsa KV'de "a:<ad>" kaydı onun yerine geçer.
// Sonradan eklenenler: KV'de "a:<ad>" = { salt, hash, it, ver, t } (şifre hash'li saklanır, düz metin yok).

async function saveAdmin(env, u, pw) {
	const old = await env.STATS.get('a:' + u, 'json');
	const salt = randHex(16);
	const rec = { salt, hash: await pbkdf2(pw, salt, ITER), it: ITER, ver: randHex(8), t: (old && old.t) || Date.now() };
	await env.STATS.put('a:' + u, JSON.stringify(rec)); // yeni ver: bu kullanıcının açık oturumlarını kapatır
}

async function adminNames(env) {
	const names = [primaryOf(env)];
	let cursor;
	do {
		const l = await env.STATS.list({ prefix: 'a:', cursor });
		for (const k of l.keys) { const n = k.name.slice(2); if (!names.includes(n)) names.push(n); }
		cursor = l.list_complete ? undefined : l.cursor;
	} while (cursor);
	return names;
}

async function userVer(env, u) { // oturum doğrulaması için kullanıcının sürümü; kullanıcı yoksa null
	const rec = await env.STATS.get('a:' + u, 'json');
	if (rec) return rec.ver || '0';
	return u === primaryOf(env) ? '0' : null;
}

async function checkLogin(env, user, pass) { // doğruysa kullanıcı adını, değilse null döndürür
	const u = lc(user), k = env.ADMIN_TOKEN;
	const rec = await env.STATS.get('a:' + u, 'json');
	if (rec) return safeEq(await pbkdf2(pass, rec.salt, rec.it || ITER), rec.hash) ? u : null;
	if (u && u === primaryOf(env)) {
		return safeEq(await hmac(k, 'p:' + pass), await hmac(k, 'p:' + env.ADMIN_TOKEN)) ? u : null;
	}
	await pbkdf2(pass, '00'.repeat(16), ITER); // olmayan kullanıcıda da aynı sürede cevap ver
	return null;
}

async function sessionUser(req, env) {
	if (!env.STATS) return null;
	const m =(req.headers.get('cookie') || '').match(/(?:^|;\s*)ksid=([^;]+)/);
	if (!m) return null;
	const p = m[1].split(':');
	if (p.length !== 3) return null;
	let u;
	try { u = decodeURIComponent(p[1]); } catch (e) { return null; }
	const exp = p[0], sig = p[2];
	if (!u || !(Number(exp) > Date.now())) return null;
	const ver = await userVer(env, u);
	if (ver === null) return null;
	return safeEq(sig, await hmac(env.ADMIN_TOKEN, 'adm:' + exp + ':' + u + ':' + ver)) ? u : null;
}

async function whoAmI(req, env) {
	if (!env.ADMIN_TOKEN) return null;
	const t = (req.headers.get('authorization') || '').replace(/^Bearer /, '');
	if (t && safeEq(t, env.ADMIN_TOKEN)) return { user: primaryOf(env), primary: true }; // eski yöntem (betik/curl) çalışmaya devam eder
	const u = await sessionUser(req, env);
	return u ? { user: u, primary: u === primaryOf(env) } : null;
}

async function login(req, env) {
	if (!env.ADMIN_TOKEN || !env.ADMIN_USER) return json({ ok: false, error: 'ADMIN_USER ve ADMIN_TOKEN secret olarak eklenmemiş' }, 500);
	if (!env.STATS) return json({ ok: false, error: 'KV bağlı değil: Settings → Bindings → KV namespace, değişken adı STATS' }, 500);
	const fails = Number(await env.STATS.get('x:fail')) || 0;
	if (fails >= MAX_FAILS) return json({ ok: false, error: 'Çok fazla hatalı deneme. 10 dakika sonra tekrar dene.' }, 429);
	let d;
	try { d = await req.json(); } catch (e) { return json({ ok: false }, 400); }
	const u = await checkLogin(env, String(d.username || ''), String(d.password || ''));
	if (!u) {
		await env.STATS.put('x:fail', String(fails + 1), { expirationTtl: 600 });
		await new Promise(r => setTimeout(r, 800));
		return json({ ok: false, error: 'Kullanıcı adı veya şifre hatalı' }, 401);
	}
	if (fails) await env.STATS.delete('x:fail');
	const exp = Date.now() + SESSION_MS, ver = await userVer(env, u);
	const token = exp + ':' + encodeURIComponent(u) + ':' + await hmac(env.ADMIN_TOKEN, 'adm:' + exp + ':' + u + ':' + ver);
	return json({ ok: true }, 200, { 'set-cookie': 'ksid=' + token + '; Path=/; HttpOnly; Secure; SameSite=Strict; Max-Age=' + SESSION_MS / 1000 });
}

// ---- Şifremi unuttum ----
async function forgot(env, origin) {
	if (!env.RESEND_API_KEY || !env.RESET_EMAIL || !env.ADMIN_USER || !env.ADMIN_TOKEN) {
		return json({ ok: false, error: 'E-posta ayarı eksik (RESEND_API_KEY, RESET_EMAIL)' }, 500);
	}
	if (!env.STATS) return json({ ok: false, error: 'KV bağlı değil' }, 500);
	if (await env.STATS.get('x:forgot')) {
		return json({ ok: false, error: 'Yeni mail için 5 dakika beklemelisin. Önceki maili Spam klasöründe de ara.' }, 429);
	}
	await env.STATS.put('x:forgot', '1', { expirationTtl: 300 });
	const token = randHex(32);
	await env.STATS.put('r:' + await sha256hex(token), '1', { expirationTtl: 900 });
	const names = await adminNames(env);
	const link = (env.SITE_URL || origin) + '/admin/reset?token=' + token;
	const r = await fetch('https://api.resend.com/emails', {
		method: 'POST',
		headers: { Authorization: 'Bearer ' + env.RESEND_API_KEY, 'Content-Type': 'application/json' },
		body: JSON.stringify({
			from: 'KediRay Sayaç <onboarding@resend.dev>',
			to: [env.RESET_EMAIL],
			subject: 'KediRay sayaç: şifre sıfırlama',
			html: '<p>Yönetici kullanıcı adları: <b>' + names.map(escHtml).join('</b>, <b>') + '</b></p>' +
				'<p>Şifreyi sıfırlamak için bağlantıya tıkla (15 dakika geçerli, tek kullanımlık):</p>' +
				'<p><a href="' + link + '">' + link + '</a></p>' +
				'<p>Bunu sen istemediysen bu e-postayı yok say.</p>',
		}),
	});
	if (!r.ok) {
		await env.STATS.delete('x:forgot'); // gönderilemediyse bekletme
		let detail = '';
		try { detail = (await r.text()).slice(0, 300); } catch (e) {}
		return json({ ok: false, error: 'E-posta gönderilemedi (Resend ' + r.status + '): ' + detail }, 502);
	}
	return json({ ok: true });
}

async function tokenOk(env, token) {
	return !!token && !!(await env.STATS.get('r:' + await sha256hex(token)));
}

async function resetConfirm(req, env) {
	let d;
	try { d = await req.json(); } catch (e) { return json({ ok: false }, 400); }
	const token = String(d.token || ''), u = lc(d.username), pw = String(d.password || '');
	if (pw.length < 8) return json({ ok: false, error: 'Şifre en az 8 karakter olmalı' }, 400);
	if (!(await tokenOk(env, token))) return json({ ok: false, error: 'Bağlantı geçersiz veya süresi dolmuş' }, 400);
	if (!(await adminNames(env)).includes(u)) return json({ ok: false, error: 'Kullanıcı bulunamadı' }, 400);
	await saveAdmin(env, u, pw);
	await env.STATS.delete('r:' + await sha256hex(token));
	await env.STATS.delete('x:fail'); // giriş kilitliyse açılsın
	return json({ ok: true });
}

// ---- Yönetici ekleme / silme (yalnızca ana yönetici) ----
async function adminsApi(req, env, path) {
	const who = await whoAmI(req, env);
	if (!who) return json({ ok: false }, 401);
	if (path === '/api/me') return json({ ok: true, user: who.user, primary: who.primary });
	if (!who.primary) return json({ ok: false, error: 'Bu işlem için ana yönetici gerekli' }, 403);
	if (!env.STATS) return json({ ok: false, error: 'KV bağlı değil' }, 500);
	if (req.method === 'GET') return json({ ok: true, primary: primaryOf(env), users: await adminNames(env) });
	let d;
	try { d = await req.json(); } catch (e) { return json({ ok: false }, 400); }
	const u = lc(d.username);
	if (path === '/api/admins/delete') {
		if (u === primaryOf(env)) return json({ ok: false, error: 'Ana yönetici silinemez' }, 400);
		if (!(await env.STATS.get('a:' + u))) return json({ ok: false, error: 'Kullanıcı bulunamadı' }, 404);
		await env.STATS.delete('a:' + u); // kayıt gidince oturumları da geçersiz olur
		return json({ ok: true });
	}
	const pw = String(d.password || '');
	if (!USER_RE.test(u)) return json({ ok: false, error: 'Kullanıcı adı 3-32 karakter olmalı: harf, rakam, . _ -' }, 400);
	if (u === primaryOf(env) || (await env.STATS.get('a:' + u))) return json({ ok: false, error: 'Bu kullanıcı adı zaten var' }, 400);
	if (pw.length < 8) return json({ ok: false, error: 'Şifre en az 8 karakter olmalı' }, 400);
	await saveAdmin(env, u, pw);
	return json({ ok: true });
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
button{cursor:pointer;background:#3b7;border:0;color:#052}#lg input,#af input{display:block;width:100%;box-sizing:border-box;margin-bottom:8px}a{color:#7bf}#e,#am{color:#f66;margin:8px 0}#lo{margin-top:12px;background:#333;color:#eee;display:none}.c{background:#1e2127;border-radius:12px;padding:14px 16px;margin:12px 0}.n{font-size:32px;font-weight:700}.g{display:flex;gap:12px;flex-wrap:wrap}.g div{flex:1;min-width:90px}small{opacity:.7}.ar{display:flex;justify-content:space-between;align-items:center;padding:6px 0;border-bottom:1px solid #2a2e36}button.del{background:transparent;color:#f66;border:1px solid #444;padding:4px 10px}</style>
<h2>KediRay sayaç</h2>
<form id=lg><input id=u placeholder="kullanıcı adı" autocomplete=username><input id=p type=password placeholder="şifre" autocomplete=current-password><button>Giriş</button><p style="margin:12px 0 0"><a href="#" id=fg>Şifremi unuttum</a></p></form>
<div id=e></div><div id=o></div>
<div id=ad class=c style="display:none"><b>Yöneticiler</b><div id=al></div><div id=am></div>
<form id=af style="margin-top:12px"><input id=nu placeholder="yeni yönetici kullanıcı adı" autocomplete=off><input id=np type=password placeholder="şifre (en az 8 karakter)" autocomplete=new-password><button>Yönetici ekle</button></form></div>
<button id=lo>Çıkış</button>
<script>
const $=i=>document.getElementById(i);
const esc=s=>String(s).replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
async function jf(u,o){const r=await fetch(u,o);let d={};try{d=await r.json()}catch(e){}return{r,d}}
const post=(u,b)=>jf(u,{method:'POST',headers:{'content-type':'application/json'},body:JSON.stringify(b||{})});
function show(d){$('lg').style.display='none';$('lo').style.display='block';let h='';
for(const a in d){const x=d[a];h+='<div class=c><b>'+a+'</b><div class=g><div><div class=n>'+x.d1+'</div><small>son 1 gün</small></div><div><div class=n>'+x.d7+'</div><small>son 7 gün</small></div><div><div class=n>'+x.d30+'</div><small>son 30 gün</small></div></div><small>Sürümler (30 gün): '+(Object.entries(x.versions).sort().map(e=>e[0]+': '+e[1]).join(' · ')||'—')+'</small></div>'}
$('o').innerHTML=h+'<small>Yalnızca izin veren kullanıcılar sayılır.</small>'}
async function loadAdmins(){const{r,d}=await jf('/api/admins');if(!r.ok)return;
$('ad').style.display='block';
$('al').innerHTML=d.users.map(u=>'<div class=ar><span>'+esc(u)+(u==d.primary?' <small>(ana yönetici)</small>':'')+'</span>'+(u==d.primary?'':'<button class=del data-u="'+esc(u)+'">Sil</button>')+'</div>').join('')}
async function load(){const{r,d}=await jf('/api/stats');if(r.status==401)return;
if(!r.ok){$('e').textContent=d.error||'Sunucu hatası';return}
show(d);loadAdmins()}
$('lg').addEventListener('submit',async ev=>{ev.preventDefault();$('e').style.color='';$('e').textContent='';
const{r,d}=await post('/admin/login',{username:$('u').value,password:$('p').value});
if(r.ok){await load();return}
$('e').textContent=d.error||'Giriş başarısız'});
$('fg').addEventListener('click',async ev=>{ev.preventDefault();$('e').style.color='';$('e').textContent='Gönderiliyor...';
const{r,d}=await post('/admin/forgot');
if(r.ok){$('e').style.color='#3b7';$('e').textContent='Kullanıcı adları ve sıfırlama bağlantısı e-postana gönderildi (15 dk geçerli).'}
else{$('e').textContent=d.error||'Hata'}});
$('af').addEventListener('submit',async ev=>{ev.preventDefault();$('am').style.color='#f66';$('am').textContent='';
const{r,d}=await post('/api/admins',{username:$('nu').value,password:$('np').value});
if(r.ok){$('nu').value='';$('np').value='';$('am').style.color='#3b7';$('am').textContent='Yönetici eklendi';loadAdmins()}
else{$('am').textContent=d.error||'Hata'}});
$('al').addEventListener('click',async ev=>{const b=ev.target.closest('button.del');if(!b)return;
const u=b.getAttribute('data-u');if(!confirm(u+' yöneticisi silinsin mi?'))return;
const{r,d}=await post('/api/admins/delete',{username:u});
$('am').style.color='#f66';$('am').textContent=r.ok?'':(d.error||'Hata');loadAdmins()});
$('lo').addEventListener('click',async()=>{await post('/admin/logout');location.reload()});
load();
</script>`;

const RESET_PAGE = `<!doctype html><meta charset=utf-8><meta name=viewport content="width=device-width,initial-scale=1"><title>KediRay sayaç: yeni şifre</title>
<style>body{font:16px system-ui;max-width:420px;margin:12vh auto 0;padding:0 16px;background:#14161a;color:#e8e8e8}input,select,button{font:inherit;padding:8px 12px;border-radius:8px;border:1px solid #444;background:#222;color:#eee;display:block;width:100%;box-sizing:border-box;margin-bottom:8px}
button{cursor:pointer;background:#3b7;border:0;color:#052}#e{color:#f66;margin:8px 0}label{font-size:13px;opacity:.7}</style>
<h2>Yeni şifre belirle</h2>
<form id=f><label>Yönetici</label><select id=us></select><label>Yeni şifre (en az 8 karakter)</label><input id=p1 type=password autocomplete=new-password><label>Yeni şifre (tekrar)</label><input id=p2 type=password autocomplete=new-password><button>Şifreyi kaydet</button></form><div id=e></div>
<script>
const $=i=>document.getElementById(i);
const tk=new URLSearchParams(location.search).get('token')||'';
(async()=>{const r=await fetch('/admin/reset-users?token='+encodeURIComponent(tk));let d={};try{d=await r.json()}catch(e){}
if(!r.ok){$('f').style.display='none';$('e').textContent=d.error||'Bağlantı geçersiz veya süresi dolmuş';return}
d.users.forEach(u=>{const o=document.createElement('option');o.value=u;o.textContent=u;$('us').appendChild(o)})})();
$('f').addEventListener('submit',async ev=>{ev.preventDefault();$('e').style.color='';$('e').textContent='';
if($('p1').value!==$('p2').value){$('e').textContent='Şifreler aynı değil';return}
const r=await fetch('/admin/reset-confirm',{method:'POST',headers:{'content-type':'application/json'},body:JSON.stringify({token:tk,username:$('us').value,password:$('p1').value})});
let d={};try{d=await r.json()}catch(e){}
if(r.ok){$('e').style.color='#3b7';$('e').textContent='Şifre değişti, giriş sayfasına yönlendiriliyorsun...';setTimeout(()=>{location.href='/admin'},1500)}
else{$('e').textContent=d.error||'Hata'}});
</script>`;

const html = body => new Response(body, { headers: { 'content-type': 'text/html; charset=utf-8', 'cache-control': 'no-store' } });

export default {
	async fetch(req, env) {
		const u = new URL(req.url), p = u.pathname, m = req.method;
		if (m === 'POST' && p === '/ping') return ping(req, env);
		if (m === 'GET' && p === '/') return Response.redirect(u.origin + '/admin', 302);
		if (m === 'GET' && p === '/admin') return html(PAGE);
		if (m === 'GET' && p === '/admin/reset') return html(RESET_PAGE);
		if (m === 'POST' && p === '/admin/login') return login(req, env);
		if (m === 'POST' && p === '/admin/logout') return json({ ok: true }, 200, { 'set-cookie': 'ksid=; Path=/; HttpOnly; Secure; SameSite=Strict; Max-Age=0' });
		if (m === 'POST' && p === '/admin/forgot') return forgot(env, u.origin);
		if (m === 'GET' && p === '/admin/reset-users') {
			if (!env.STATS || !(await tokenOk(env, u.searchParams.get('token')))) return json({ ok: false, error: 'Bağlantı geçersiz veya süresi dolmuş' }, 400);
			return json({ ok: true, users: await adminNames(env) });
		}
		if (m === 'POST' && p === '/admin/reset-confirm') return env.STATS ? resetConfirm(req, env) : json({ ok: false, error: 'KV bağlı değil' }, 500);
		if ((m === 'GET' && (p === '/api/me' || p === '/api/admins')) || (m === 'POST' && (p === '/api/admins' || p === '/api/admins/delete'))) return adminsApi(req, env, p);
		if (m === 'GET' && p === '/api/stats') {
			if (!(await whoAmI(req, env))) return json({ ok: false }, 401);
			if (!env.STATS) return json({ ok: false, error: 'KV bağlı değil: Settings → Bindings → KV namespace, değişken adı STATS' }, 500);
			try { return json(await stats(env)); } catch (e) { return json({ ok: false, error: 'KV okunamadı' }, 500); }
		}
		return new Response('KediRay', { status: 404 });
	}
};
