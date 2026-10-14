'use strict';
'require view';
'require fs';
'require ui';
'require poll';
'require dom';

/* KediRay - Kontrol paneli */

/* Güvenli öğe oluşturucu: LuCI'nin E()'si iç içe dizileri "[object HTMLButtonElement]," diye metne çevirir ve
 * tek bir metni innerHTML olarak basar (abonelikten gelen bir sunucu adı HTML çalıştırabilir). h() dizileri
 * düzleştirir, boşları atar ve her metni düz metin düğümü olarak ekler. */
function h(tag, attrs, children) {
	if (attrs != null && (typeof attrs !== 'object' || Array.isArray(attrs) || attrs.nodeType)) { children = attrs; attrs = {}; }
	const out = [];
	(function walk(c) {
		if (Array.isArray(c)) c.forEach(walk);
		else if (c != null && c !== false && c !== '') out.push((typeof c === 'object' && c.nodeType) ? c : String(c));
	})(children);
	return E(tag, attrs || {}, out);
}

const CLI = '/usr/bin/kediray';


function run(args) {
	return fs.exec(CLI, args).catch(e => ({ code: 1, stdout: '', stderr: String(e) }));
}
/* İzinli anonim sayaç: ilk açılışta bir kez sorar. Cevap verilmezse (pencere kapatılırsa) hiçbir şey gönderilmez ve sonraki girişte yine sorulur. */
function askStats() {
	const done = (v, msg) => run(['count', v]).then(() => { ui.hideModal(); ui.addNotification(null, h('p', {}, msg), 'info'); });
	ui.showModal('KediRay\'i geliştirmeye yardımcı olur musun?', [
		h('p', {}, 'Kaç kişinin KediRay kullandığını görmek istiyorum. Onay verirsen günde bir kez şunlar gönderilir:'),
		h('ul', {}, [h('li', {}, 'rastgele bir kurulum kimliği (seni tanıtmaz)'), h('li', {}, 'KediRay sürümü'), h('li', {}, 'uygulama adı')]),
		h('p', {}, 'Sunucu bilgilerin, trafiğin, adın ya da IP adresin kaydedilmez. Ayarlar → "Geliştirmeye yardımcı ol" bölümünden istediğin an kapatabilirsin.'),
		h('div', { 'class': 'right' }, [
			h('button', { 'class': 'btn', 'click': () => done('off', 'Tamam, hiçbir şey gönderilmeyecek.') }, 'Hayır'),
			' ',
			h('button', { 'class': 'btn cbi-button-positive important', 'style': 'font-weight:bold;padding:6px 22px', 'click': () => done('on', 'Teşekkürler! Anonim kullanım sayısı açıldı.') }, 'Evet, yardımcı olayım')
		])
	]);
}

function runJson(args) {
	return run(args).then(r => { try { return JSON.parse(r.stdout || 'null'); } catch (e) { return null; } });
}
function fmtBytes(b) {
	b = +b || 0;
	const u = ['B', 'KB', 'MB', 'GB', 'TB']; let i = 0;
	while (b >= 1024 && i < u.length - 1) { b /= 1024; i++; }
	return (i ? b.toFixed(1) : b) + ' ' + u[i];
}
function fmtRate(b) { return fmtBytes(b) + '/s'; }
// süre: 3 gün 5 sa 22 dk · 5 sa 22 dk 10 sn · 14 dk 49 sn · 49 sn
function fmtDur(s) {
	s = Math.max(0, Math.floor(+s || 0));
	const g = Math.floor(s / 86400), h2 = Math.floor(s % 86400 / 3600), m = Math.floor(s % 3600 / 60), sn = s % 60;
	const p = v => String(v).padStart(2, '0');
	if (g) return g + ' gün ' + h2 + ' sa ' + p(m) + ' dk';
	if (h2) return h2 + ' sa ' + p(m) + ' dk ' + p(sn) + ' sn';
	if (m) return m + ' dk ' + p(sn) + ' sn';
	return sn + ' sn';
}
/* Canlı sayaç: değer render anında damgalanır, her saniye tarayıcıda ilerler
   (modem saatiyle tarayıcı saati farklı olabilir; fark değil, geçen süre sayılır) */
function live(seconds, cls) {
	const v = Math.max(0, Math.floor(+seconds || 0));
	return h('span', {
		'class': 'kr-live' + (cls ? ' ' + cls : ''),
		'data-base': String(v),
		'data-at': String(Date.now())
	}, fmtDur(v));
}
function tickLive(root) {
	const now = Date.now();
	(root || document).querySelectorAll('.kr-live').forEach(e => {
		const base = +e.getAttribute('data-base'), at = +e.getAttribute('data-at');
		if (!isFinite(base) || !isFinite(at)) return;
		e.textContent = fmtDur(base + (now - at) / 1000);
	});
}
// üst köşeleri r kadar yuvarlak, tabanı düz çubuk yolu (SVG path)
function roundTop(x, y, w, hgt, r) {
	r = Math.max(0, Math.min(r, hgt, w / 2));
	const f = v => v.toFixed(1);
	return 'M' + f(x) + ',' + f(y + hgt) + ' V' + f(y + r) + ' Q' + f(x) + ',' + f(y) + ' ' + f(x + r) + ',' + f(y) +
		' H' + f(x + w - r) + ' Q' + f(x + w) + ',' + f(y) + ' ' + f(x + w) + ',' + f(y + r) + ' V' + f(y + hgt) + ' Z';
}
// rtt = gerçek ağ gecikmesi (sunucuya TCP), ms = tünel testi (yeni bağlantı + tam web isteği)
function pingBadge(ms, rtt, warm) {
	if (ms == null && rtt == null) return h('span', { 'class': 'kr-ping kr-na' }, '—');
	if (ms != null && ms < 0) return h('span', { 'class': 'kr-ping kr-bad', 'title': 'Tünel kurulamadı' }, 'yok');
	const tip = 'Ping: modemden sunucuya gerçek ağ gecikmesi.\n' +
		'Tünel (yeni): sıfırdan bağlantı açıp tam bir web isteği yapma süresi — TCP + TLS + WebSocket el sıkışmaları dahil (v2rayNG "gerçek gecikme").\n' +
		'Tünel (açık): aynı bağlantıdan giden ikinci isteğin süresi — sayfaların ve oyunun gerçekte hissettiği gecikme budur.';
	const parts = [];
	if (rtt != null && rtt > 0)
		parts.push(h('span', { 'class': 'kr-ping ' + (rtt < 60 ? 'kr-good' : rtt < 150 ? 'kr-mid' : 'kr-bad') }, rtt + ' ms'));
	if (warm != null && warm > 0)
		parts.push(h('span', { 'class': 'kr-sub', 'style': 'font-size:.8em;margin-left:4px' }, 'tünel ' + warm));
	else if (ms != null && ms > 0 && rtt != null && rtt > 0)
		parts.push(h('span', { 'class': 'kr-sub', 'style': 'font-size:.8em;margin-left:4px' }, 'tünel ' + ms));
	if (ms != null && ms > 0 && warm != null && warm > 0 && ms > warm)
		parts.push(h('span', { 'class': 'kr-sub', 'style': 'font-size:.8em;margin-left:4px;opacity:.55' }, '(ilk ' + ms + ')'));
	if (!parts.length)
		return h('span', { 'class': 'kr-ping ' + (ms < 150 ? 'kr-good' : ms < 400 ? 'kr-mid' : 'kr-bad'), 'title': tip }, ms + ' ms');
	return h('span', { 'style': 'white-space:nowrap', 'title': tip }, parts);
}
function btn(label, cls, fn, title) {
	return h('button', { 'class': 'btn cbi-button ' + (cls || ''), 'title': title || '', 'click': ui.createHandlerFn(this, fn) }, label);
}

/* Katı JSON denetleyici: ilk hatanın satır/sütununu ve Türkçe açıklamasını verir (null = hatasız) */
function jsonCheck(s) {
	let i = 0, err = null;
	const n = s.length;
	const ch = () => (i < n ? s[i] : '');
	const fail = m => { if (!err) err = { pos: i, msg: m }; return false; };
	const ws = () => { while (i < n && ' \t\r\n'.indexOf(s[i]) >= 0) i++; };
	const str = () => {
		i++;
		while (i < n) {
			const c = s[i];
			if (c === '"') { i++; return true; }
			if (c === '\\') { i += 2; continue; }
			if (c === '\n') return fail('Metin bitmeden satır sonu geldi (kapanış tırnağı " eksik)');
			i++;
		}
		return fail('Kapanış tırnağı " eksik');
	};
	const num = () => {
		const m = /^-?(0|[1-9]\d*)(\.\d+)?([eE][+-]?\d+)?/.exec(s.slice(i, i + 64));
		if (!m) return fail('Geçersiz sayı');
		i += m[0].length; return true;
	};
	let value;
	const obj = () => {
		i++; ws();
		if (ch() === '}') { i++; return true; }
		for (;;) {
			ws();
			const c = ch();
			if (c === '}') return fail("Son öğeden sonra fazladan virgül var (',' sil)");
			if (c === "'") return fail('Anahtarlar tek tırnakla değil çift tırnakla (") yazılmalı');
			if (c !== '"') return fail(i >= n ? "'}' kapanmamış (metin erken bitti)" : 'Anahtar çift tırnak (") içinde olmalı');
			if (!str()) return false;
			ws();
			if (ch() !== ':') return fail("Anahtardan sonra ':' bekleniyordu");
			i++;
			if (!value()) return false;
			ws();
			const d = ch();
			if (d === ',') { i++; continue; }
			if (d === '}') { i++; return true; }
			if (i >= n) return fail("'}' kapanmamış (metin erken bitti)");
			return fail("',' veya '}' bekleniyordu (önceki satırın sonunda virgül eksik olabilir)");
		}
	};
	const arr = () => {
		i++; ws();
		if (ch() === ']') { i++; return true; }
		for (;;) {
			ws();
			if (ch() === ']') return fail("Son öğeden sonra fazladan virgül var (',' sil)");
			if (!value()) return false;
			ws();
			const d = ch();
			if (d === ',') { i++; continue; }
			if (d === ']') { i++; return true; }
			if (i >= n) return fail("']' kapanmamış (metin erken bitti)");
			return fail("',' veya ']' bekleniyordu");
		}
	};
	value = () => {
		ws();
		const c = ch();
		if (c === '{') return obj();
		if (c === '[') return arr();
		if (c === '"') return str();
		if (c === '-' || (c >= '0' && c <= '9')) return num();
		if (s.startsWith('true', i) || s.startsWith('null', i)) { i += 4; return true; }
		if (s.startsWith('false', i)) { i += 5; return true; }
		if (c === "'") return fail('Metinler tek tırnakla değil çift tırnakla (") yazılmalı');
		if (i >= n) return fail('Beklenmedik son: değer bekleniyordu');
		return fail("Geçersiz değer '" + c + "' (metinler çift tırnak içinde olmalı)");
	};
	if (value()) { ws(); if (i < n) fail('JSON bittikten sonra fazladan içerik var'); }
	if (!err) return null;
	let line = 1, col = 1;
	for (let k = 0; k < err.pos && k < n; k++) { if (s[k] === '\n') { line++; col = 1; } else col++; }
	return { line, col, msg: err.msg, pos: err.pos };
}

/* Form alanları: [ad, etiket, tür, seçenekler, görünür mü?] */
const isV = f => f.protocol === 'vless' || f.protocol === 'vmess';
const notSS = f => f.protocol !== 'shadowsocks';
const hasPath = f => notSS(f) && (['ws', 'xhttp', 'httpupgrade'].includes(f.network) || (f.network === 'tcp' && f.header_type === 'http'));
const isTLS = f => notSS(f) && (f.tls === 'tls' || f.tls === 'reality');
const FIELDS = [
	['protocol', 'Protokol', 'select', [['vless', 'VLESS'], ['vmess', 'VMess'], ['trojan', 'Trojan'], ['shadowsocks', 'Shadowsocks']]],
	['address', 'Adres (IP ya da alan adı)', 'text'],
	['port', 'Port', 'text'],
	['uuid', 'UUID', 'text', null, isV],
	['password', 'Parola', 'text', null, f => f.protocol === 'trojan' || f.protocol === 'shadowsocks'],
	['method', 'Şifreleme', 'select', ['aes-128-gcm', 'aes-256-gcm', 'chacha20-poly1305', 'chacha20-ietf-poly1305', 'xchacha20-poly1305',
		'2022-blake3-aes-128-gcm', '2022-blake3-aes-256-gcm', '2022-blake3-chacha20-poly1305'], f => f.protocol === 'shadowsocks'],
	['flow', 'Flow', 'select', [['', 'Yok'], ['xtls-rprx-vision', 'xtls-rprx-vision']], f => f.protocol === 'vless'],
	['network', 'Aktarım', 'select', [['ws', 'WebSocket (ws)'], ['tcp', 'TCP / raw'], ['grpc', 'gRPC'], ['xhttp', 'XHTTP'], ['httpupgrade', 'HTTPUpgrade']], notSS],
	['header_type', 'TCP başlık', 'select', [['', 'Yok'], ['http', 'HTTP gizleme']], f => notSS(f) && f.network === 'tcp'],
	['path', 'Yol (path)', 'text', null, hasPath],
	['host', 'Host', 'text', null, hasPath],
	['service_name', 'gRPC servis adı', 'text', null, f => notSS(f) && f.network === 'grpc'],
	['xhttp_mode', 'XHTTP modu', 'select', ['auto', 'packet-up', 'stream-up', 'stream-one'], f => notSS(f) && f.network === 'xhttp'],
	['tls', 'Güvenlik', 'select', [['none', 'Yok'], ['tls', 'TLS'], ['reality', 'REALITY']], notSS],
	['sni', 'SNI', 'text', null, isTLS],
	['fp', 'Parmak izi (uTLS)', 'select', [['', 'Yok (v2rayNG varsayılanı)'], 'chrome', 'firefox', 'safari', 'ios', 'android', 'edge', 'random', 'randomized'], isTLS],
	['alpn', 'ALPN', 'text', null, f => notSS(f) && f.tls === 'tls'],
	['insecure', 'Sertifikayı doğrulama (otomatik sabitlenir)', 'checkbox', null, f => notSS(f) && f.tls === 'tls'],
	['pbk', 'REALITY public key', 'text', null, f => notSS(f) && f.tls === 'reality'],
	['sid', 'REALITY short id', 'text', null, f => notSS(f) && f.tls === 'reality'],
	['spx', 'REALITY spiderX', 'text', null, f => notSS(f) && f.tls === 'reality']
];
const JSON_TEMPLATE = JSON.stringify({
	protocol: 'vless',
	settings: { vnext: [{ address: '1.2.3.4', port: 443, users: [{ id: 'UUID-BURAYA', encryption: 'none' }] }] },
	streamSettings: { network: 'ws', security: 'tls', tlsSettings: { serverName: 'alan.adi' }, wsSettings: { path: '/', host: 'alan.adi' } }
}, null, 2);
const STAGE = { syntax: 'Yazım hatası', fields: 'Eksik ya da hatalı alan', xray: 'Xray bu ayarı kabul etmedi', save: 'Kaydedilemedi', uci: 'Ayar dosyası okunamadı', node: 'Sunucu hatası', gen: 'Yapılandırma üretilemedi' };

const CSS = `
.kr-grid{display:grid;grid-template-columns:repeat(auto-fit,minmax(300px,1fr));gap:14px;margin-bottom:14px}
.kr-card{border:1px solid rgba(128,128,128,.25);border-radius:10px;padding:14px 16px;background:rgba(128,128,128,.04)}
.kr-card h3{margin:0 0 10px;font-size:1.05em;opacity:.85}
.kr-ch{cursor:pointer;user-select:none;display:flex;align-items:center;gap:7px}
.kr-ch:hover{opacity:1}
.kr-caret{font-size:.85em;opacity:.7;width:12px}
.kr-ct{flex:1}
.kr-cbody.kr-fold{display:none}
.kr-blocked td{opacity:.75}
.kr-big{font-size:1.35em;font-weight:600;margin:2px 0 6px;word-break:break-all}
.kr-sub{opacity:.7;font-size:.9em}
.kr-addr{margin-top:6px;font-size:.92em;word-break:break-all}
.kr-mono{font-family:ui-monospace,Menlo,Consolas,monospace;background:rgba(128,128,128,.14);border-radius:5px;padding:1px 6px;user-select:all}
.kr-live{font-variant-numeric:tabular-nums}
.kr-row{display:flex;gap:8px;flex-wrap:wrap;align-items:center;margin-top:10px}
.kr-dot{display:inline-block;width:10px;height:10px;border-radius:50%;margin-right:6px;vertical-align:middle}
.kr-on{background:#22a355}.kr-off{background:#999}.kr-err{background:#d23f3f}
.kr-ping{display:inline-block;min-width:54px;text-align:center;padding:1px 8px;border-radius:10px;font-size:.85em;font-weight:600}
.kr-good{background:rgba(34,163,85,.18);color:#1b8a47}.kr-mid{background:rgba(230,160,20,.2);color:#a86d00}
.kr-bad{background:rgba(210,63,63,.18);color:#b52f2f}.kr-na{background:rgba(128,128,128,.15)}
.kr-seg{display:inline-flex;border:1px solid rgba(128,128,128,.4);border-radius:8px;overflow:hidden}
.kr-seg button{border:0;border-radius:0;margin:0;padding:4px 14px;background:transparent;cursor:pointer;color:inherit;white-space:nowrap;word-break:keep-all}
.kr-seg button.kr-act{background:#2a7de1;color:#fff}
.kr-seg button.kr-act.kr-direct{background:#22a355}
.kr-seg button.kr-act.kr-block{background:#d23f3f;color:#fff}
.kr-seg button.kr-blockbtn{color:#d23f3f}
.kr-seg button.kr-blockbtn:hover{background:rgba(210,63,63,.15)}
.kr-seg-sm button{padding:4px 10px;font-size:.92em}
@media (max-width:700px){.kr-seg-sm{display:grid;grid-template-columns:1fr 1fr}.kr-seg-sm button{padding:6px 8px;border-top:1px solid rgba(128,128,128,.25)}.kr-seg-sm button:nth-child(-n+2){border-top:0}.kr-seg-sm button:nth-child(odd){border-right:1px solid rgba(128,128,128,.25)}}
.kr-warn{border:1px solid #e0a100;background:rgba(224,161,0,.12);border-radius:8px;padding:8px 10px;margin:0 0 10px;font-size:.92em}
.kr-seg.kr-dim{opacity:.4}
.kr-seg.kr-dim button.kr-act{background:transparent;color:inherit}
.kr-app{display:flex;justify-content:space-between;align-items:center;padding:7px 0;border-bottom:1px dashed rgba(128,128,128,.25)}
.kr-app:last-child{border-bottom:0}
.kr-stat{display:grid;grid-template-columns:auto 1fr 1fr;gap:4px 14px;font-variant-numeric:tabular-nums}
.kr-tag{display:inline-block;padding:0 6px;border-radius:6px;background:rgba(42,125,225,.15);font-size:.8em;margin-left:6px}
.kr-tag.kr-tag-red{background:rgba(210,63,63,.2);color:#e05252}
.kr-table td,.kr-table th{padding:6px 8px!important;vertical-align:middle}
.kr-active{background:rgba(42,125,225,.08)}
.kr-tabs{display:flex;gap:4px;margin:8px 0}
.kr-tabs button{border:1px solid rgba(128,128,128,.4);background:transparent;color:inherit;padding:5px 16px;border-radius:8px 8px 0 0;cursor:pointer}
.kr-tabs button.kr-act{background:#2a7de1;color:#fff;border-color:#2a7de1}
.kr-form{display:grid;grid-template-columns:minmax(120px,190px) 1fr;gap:6px 12px;align-items:center}
.kr-form label{opacity:.85}
.kr-form input[type=text],.kr-form select{width:100%;box-sizing:border-box}
.kr-bad-input{outline:2px solid #d23f3f!important}
.modal.kr-wide{max-width:min(1150px,97vw)!important;width:97vw!important}
.kr-ed{display:flex;border:1px solid rgba(128,128,128,.45);border-radius:6px;overflow:hidden}
.kr-gut{margin:0;padding:6px 6px 6px 4px;min-width:34px;text-align:right;opacity:.5;user-select:none;overflow:hidden;background:rgba(128,128,128,.08);font-family:ui-monospace,Menlo,Consolas,monospace;font-size:12.5px;line-height:1.45}
.kr-json{flex:1;min-width:0;box-sizing:border-box;border:0!important;margin:0;padding:6px 8px;resize:vertical;height:420px;font-family:ui-monospace,Menlo,Consolas,monospace;font-size:12.5px;line-height:1.45;tab-size:2;white-space:pre;overflow:auto}
.kr-json.kr-wrap{white-space:pre-wrap;word-break:break-all}
.kr-view{max-height:72vh;overflow:auto;white-space:pre;font-size:12px;background:rgba(128,128,128,.08);padding:10px;border-radius:6px}
.kr-switch{display:flex;align-items:flex-start;gap:9px;cursor:pointer;user-select:none}
.kr-switch input{display:none}
/* flex:0 0 40px -> yazı uzayınca anahtarın rayı ezilmez (top raydan taşmaz) */
.kr-switch span.kr-knob{flex:0 0 40px;width:40px;height:22px;border-radius:11px;background:#999;position:relative;transition:.2s;margin-top:1px}
.kr-switch > span:last-child{flex:1;min-width:0}
.kr-switch span.kr-knob:after{content:'';position:absolute;top:3px;left:3px;width:16px;height:16px;border-radius:50%;background:#fff;transition:.2s}
.kr-switch input:checked + span.kr-knob{background:#22a355}
.kr-switch input:checked + span.kr-knob:after{left:21px}
.kr-srv{display:flex;gap:8px;align-items:center;flex-wrap:wrap;margin-top:8px}
.kr-srv select{min-width:220px;max-width:100%}
.kr-jstat{margin:6px 0;font-size:.9em}
.kr-ok{color:#1b8a47}.kr-no{color:#b52f2f}
.kr-errs{margin:8px 0;padding:8px 12px;border-radius:8px;background:rgba(210,63,63,.1);border:1px solid rgba(210,63,63,.4)}
.kr-errs li{margin:3px 0}
.kr-hint{font-size:.85em;opacity:.8;margin-top:6px}
.kr-traffic{--krc-vpn:#2a78d6;--krc-dir:#eb6834;--krc-surface:#fcfcfb}
@media (prefers-color-scheme: dark){:root:not([data-theme="light"]) .kr-traffic{--krc-vpn:#3987e5;--krc-dir:#d95926;--krc-surface:#1a1a19}}
:root[data-theme="dark"] .kr-traffic{--krc-vpn:#3987e5;--krc-dir:#d95926;--krc-surface:#1a1a19}
.krc-sw{display:inline-block;width:10px;height:10px;border-radius:2px;margin-right:6px;vertical-align:baseline}
.krc-vpn{fill:var(--krc-vpn);background:var(--krc-vpn)}
.krc-dir{fill:var(--krc-dir);background:var(--krc-dir)}
.krc-title{margin:14px 0 4px;font-weight:600;opacity:.85}
.krc-legend{display:flex;gap:16px;flex-wrap:wrap;font-size:.9em;margin:2px 0 6px}
.krc-wrap{position:relative;width:100%}
.krc-svg{display:block;max-width:100%}
.krc-grid{stroke:rgba(128,128,128,.25);stroke-width:1}
.krc-ax{fill:currentColor;opacity:.65;font-size:11px}
.krc-hit{fill:transparent;cursor:crosshair}
.krc-hit:hover{fill:rgba(128,128,128,.12)}
.krc-tip{position:absolute;z-index:5;pointer-events:none;padding:6px 10px;border-radius:8px;font-size:.88em;line-height:1.45;background:var(--krc-surface);color:inherit;border:1px solid rgba(128,128,128,.4);box-shadow:0 2px 8px rgba(0,0,0,.25);white-space:nowrap}
.krt-now{font-weight:600;opacity:.85;margin:0 0 6px}
.krt-lives{display:grid;grid-template-columns:repeat(auto-fit,minmax(200px,1fr));gap:10px}
.krt-live{border:1px solid rgba(128,128,128,.25);border-radius:8px;padding:8px 12px}
.krt-lh{font-weight:600;margin-bottom:4px}
.krt-lv{display:flex;gap:18px;flex-wrap:wrap;font-variant-numeric:tabular-nums;font-size:1.1em}
.krt-totals{display:grid;grid-template-columns:repeat(auto-fit,minmax(200px,1fr));gap:10px;margin:10px 0 4px}
.krt-tot{padding:2px 2px}
.krt-big{font-size:1.5em;font-weight:600;font-variant-numeric:tabular-nums}
.krt-table{margin-top:10px}
.krt-n{text-align:right;font-variant-numeric:tabular-nums;white-space:nowrap}
.krt-table th.krt-n{text-align:right}
.kr-warn{margin-top:10px;padding:8px 10px;border-radius:8px;background:rgba(230,160,20,.15);border:1px solid rgba(230,160,20,.45);font-size:.9em}
@media(max-width:600px){.kr-hide-sm{display:none}}
`;

// Tarayıcıda saklanan eski menüyü (Hizmetler altındaki kayıt) bir kez temizle
try {
	if (!sessionStorage.getItem('kediray-menu-v2')) {
		sessionStorage.setItem('kediray-menu-v2', '1');
		if (ui.menu && ui.menu.flushCache) ui.menu.flushCache();
	}
} catch (e) {}

function collapsed(key) {
	try { return localStorage.getItem('kediray-fold-' + key) === '1'; } catch (e) { return false; }
}

/* KR-PANEL-BASLA */
/* IP/MAC gizleme (Cihazlar tablosu) */
(function () {
	var KEY = 'kr_hide_ids', busy = false;
	var on = function () { try { return localStorage.getItem(KEY) === '1'; } catch (e) { return false; } };
	var isIp = /^\d+\.\d+\.\d+\.\d+$/, isMac = /^([0-9a-f]{2}:){5}[0-9a-f]{2}$/i;
	function mask(t, n) {
		if (n === 0 && isIp.test(t)) return '•••.•••.•••.' + t.split('.')[3];
		if (n === 1 && isMac.test(t)) return '••:••:••:••:' + t.split(':').slice(4).join(':');
		return t;
	}
	function apply() {
		if (busy) return; busy = true;
		try {
			document.querySelectorAll('table.kr-table').forEach(function (tb) {
				var hdr = tb.querySelector('tr.table-titles'); if (!hdr) return;
				var ths = [].map.call(hdr.children, function (c) { return c.textContent.trim(); });
				var ii = ths.indexOf('IP'), mi = ths.indexOf('MAC'); if (ii < 0 || mi < 0) return;
				var host = tb.parentNode;
				if (host && !host.querySelector('.kr-hide-box')) {
					var cb = document.createElement('input'); cb.type = 'checkbox'; cb.checked = on();
					cb.addEventListener('change', function () { try { localStorage.setItem(KEY, cb.checked ? '1' : '0'); } catch (e) {} apply(); });
					var lb = document.createElement('label'); lb.className = 'kr-hide-box'; lb.style.cssText = 'display:inline-flex;gap:6px;align-items:center;margin:0 0 8px;cursor:pointer';
					lb.appendChild(cb); lb.appendChild(document.createTextNode('IP ve MAC adreslerini gizle'));
					host.insertBefore(lb, tb);
				}
				var box = host && host.querySelector('.kr-hide-box input'); if (box) box.checked = on();
				[].forEach.call(tb.querySelectorAll('tr'), function (tr) {
					if (tr === hdr) return;
					[ii, mi].forEach(function (ix, n) {
						var td = tr.children[ix]; if (!td) return;
						var orig = td.getAttribute('data-orig'), cur = td.textContent;
						if (orig === null || (cur !== orig && cur !== td.getAttribute('data-masked'))) {
							if (!(n === 0 ? isIp : isMac).test(cur)) return;
							orig = cur; td.setAttribute('data-orig', cur);
						}
						var want = on() ? mask(orig, n) : orig;
						if (td.textContent !== want) { td.setAttribute('data-masked', want); td.textContent = want; }
					});
				});
			});
		} finally { busy = false; }
	}
	new MutationObserver(function () { apply(); }).observe(document.documentElement, { childList: true, subtree: true });
})();
/* Sunucu bilgilerini / bağlı sunucu IP'sini gizleme */
(function () {
	var KS = 'kr_hide_srv', KI = 'kr_hide_srvip', secrets = [], orig = new WeakMap(), pend = false;
	var get = function (k) { try { return localStorage.getItem(k) === '1'; } catch (e) { return false; } };
	var set = function (k, v) { try { localStorage.setItem(k, v ? '1' : '0'); } catch (e) {} };
	var IPRE = /\b(\d{1,3})\.(\d{1,3})\.(\d{1,3})\.(\d{1,3})\b/g;
	function priv(a, b) { return a === 10 || a === 127 || a === 0 || (a === 192 && b === 168) || (a === 172 && b >= 16 && b <= 31) || (a === 169 && b === 254); }
	function loadSecrets() {
		try {
			var env = (window.L && L.env) || {};
			fetch(env.ubuspath || '/ubus/', { method: 'POST', body: JSON.stringify({ jsonrpc: '2.0', id: 1, method: 'call',
				params: [env.sessionid, 'uci', 'get', { config: 'kediray' }] }) })
			.then(function (r) { return r.json(); }).then(function (j) {
				var v = (j.result && j.result[1] && j.result[1].values) || {}, out = {};
				Object.keys(v).forEach(function (k) {
					if (v[k]['.type'] !== 'node') return;
					['address', 'sni', 'host', 'uuid', 'server'].forEach(function (f) {
						var x = v[k][f]; if (typeof x === 'string' && x.length >= 4) out[x] = 1;
					});
				});
				secrets = Object.keys(out).sort(function (a, b) { return b.length - a.length; });
				schedule();
			}).catch(function () {});
		} catch (e) {}
	}
	function conv(s, srv, ip) {
		if (srv) secrets.forEach(function (x) { if (s.indexOf(x) >= 0) s = s.split(x).join('••••••'); });
		if (ip) s = s.replace(IPRE, function (m, a, b, c, d) { return priv(+a, +b) ? m : '•••.•••.•••.' + d; });
		return s;
	}
	function ui() {
		if (document.querySelector('.kr-srv-box')) return;
		var h2 = [].filter.call(document.querySelectorAll('h2'), function (x) { return /KediRay VPN/.test(x.textContent); })[0];
		if (!h2 || !h2.parentNode) return;
		var bar = document.createElement('div'); bar.className = 'kr-srv-box';
		bar.style.cssText = 'display:flex;gap:18px;flex-wrap:wrap;margin:4px 0 10px';
		[['Sunucu bilgilerini gizle', KS]].forEach(function (p) {
			var lb = document.createElement('label'), cb = document.createElement('input');
			lb.style.cssText = 'display:inline-flex;gap:6px;align-items:center;cursor:pointer';
			cb.type = 'checkbox'; cb.checked = get(p[1]);
			cb.addEventListener('change', function () { set(p[1], cb.checked); apply(); });
			lb.appendChild(cb); lb.appendChild(document.createTextNode(p[0])); bar.appendChild(lb);
		});
		h2.parentNode.insertBefore(bar, h2.nextSibling);
	}
	function apply() {
		ui();
		var srv = get(KS), ip = srv;
		var w = document.createTreeWalker(document.body, NodeFilter.SHOW_TEXT, null), n, list = [];
		while ((n = w.nextNode())) list.push(n);
		list.forEach(function (n) {
			var p = n.parentNode; if (!p || /^(SCRIPT|STYLE|TEXTAREA)$/.test(p.nodeName) || (p.closest && p.closest('.kr-srv-box'))) return;
			var rec = orig.get(n), base = (rec && n.data === rec.m) ? rec.o : n.data;
			var m = conv(base, srv, ip);
			if (m !== n.data) { orig.set(n, { o: base, m: m }); n.data = m; }
			else if (m === base) orig.delete(n);
		});
	}
	function schedule() { if (pend) return; pend = true; setTimeout(function () { pend = false; apply(); }, 50); }
	loadSecrets();
	new MutationObserver(schedule).observe(document.documentElement, { childList: true, subtree: true, characterData: true });
})();
/* KR-PANEL-SON */

/* Tema (Ayarlar → Görünüm): mod ve vurgu rengi tarayıcıda saklanır, tüm KediRay sayfalarında uygulanır.
 * Mod "Otomatik" ise LuCI'nin kendi teması aynen kalır. Açık/Koyu seçilince sayfa renkleri zorlanır. */
function krTheme() {
	try {
		let c = {};
		try { c = JSON.parse(localStorage.getItem('kediray-theme') || '{}') || {}; } catch (e) {}
		const mode = (c.mode === 'dark' || c.mode === 'light') ? c.mode : 'auto';
		const ac = /^#[0-9a-f]{6}$/i.test(c.accent || '') ? c.accent : '';
		let st = document.getElementById('kr-theme-css');
		if (!st) { st = document.createElement('style'); st.id = 'kr-theme-css'; document.head.appendChild(st); }
		let css = '';
		if (mode !== 'auto') {
			const d = mode === 'dark';
			const bg = d ? '#14181e' : '#f3f5f8', fg = d ? '#e4e8ee' : '#1b2330', card = d ? '#1d232c' : '#ffffff',
				bd = d ? '#333b47' : '#d3dae3', inp = d ? '#252c37' : '#ffffff';
			css += 'html,body,body .main,body .main-right,body #maincontent,body #view,body .cbi-map,body .cbi-section,body .cbi-tabcontainer,body .cbi-section-node{background:' + bg + '!important;color:' + fg + '!important}'
				+ 'body header,body .modal{background:' + card + '!important;color:' + fg + '!important}'
				+ 'body header a,body .menu a,body label,body h1,body h2,body h3,body p,body td,body th{color:' + fg + '!important}'
				+ '.kr-card{background:' + card + '!important;border-color:' + bd + '!important}'
				+ 'body input,body select,body textarea,body .cbi-dropdown{background:' + inp + '!important;color:' + fg + '!important;border-color:' + bd + '!important}'
				+ 'body .table .tr,body .table .th,body .table .td,body .cbi-section-table-row{background:transparent!important}'
				+ 'body .btn,body .cbi-button{background:' + inp + '!important;color:' + fg + '!important;border-color:' + bd + '!important}'
				+ 'body .cbi-button-negative{color:#e05252!important;border-color:#e05252!important}'
				+ 'body .cbi-button-positive{background:#22a355!important;color:#fff!important;border-color:#22a355!important}'
				+ 'body .cbi-button-action{background:' + (ac || '#2a7de1') + '!important;color:#fff!important;border-color:' + (ac || '#2a7de1') + '!important}';
		}
		if (ac) {
			css += ':root{--kr-accent:' + ac + '}'
				+ '.kr-seg button.kr-act:not(.kr-direct):not(.kr-block),.kr-tabs button.kr-act{background:' + ac + '!important;border-color:' + ac + '!important;color:#fff!important}'
				+ '.kr-tag:not(.kr-tag-red){background:' + ac + '2e!important}'
				+ '.kr-active{background:' + ac + '16!important}'
				+ '.kr-card{border-top:3px solid ' + ac + '!important}'
				+ '.kr-traffic{--krc-vpn:' + ac + '!important}'
				+ 'body .cbi-button-action{background:' + ac + '!important;border-color:' + ac + '!important;color:#fff!important}';
		}
		st.textContent = css;
		document.documentElement.setAttribute('data-krt', mode);
	} catch (e) {}
}
krTheme();

/* Lisans uyarısı: lisanssızsa sayfanın üstünde bant gösterir (VPN çalışmaya devam eder; ayar değişiklikleri kilitlidir) */
function krLicBanner() {
	const box = document.createElement('div');
	fs.exec('/usr/bin/kediray', ['license', 'status', '--json']).then(r => {
		let j = null; try { j = JSON.parse((r.stdout || '').trim()); } catch (e) { }
		if (!j || j.licensed) return;
		const d = document.createElement('div'), b = document.createElement('b'), c = document.createElement('code'), a = document.createElement('a');
		d.setAttribute('style', 'margin:0 0 14px;padding:12px 16px;border:1px solid #e0a020;border-left-width:5px;border-radius:10px;background:rgba(224,160,32,.12);max-width:900px;line-height:1.5');
		b.textContent = 'Lisans gerekli. ';
		c.textContent = j.imei || '—';
		a.href = L.url('admin', 'vpn', 'kediray', 'about'); a.textContent = 'Lisansı gir';
		d.appendChild(b);
		d.appendChild(document.createTextNode('VPN çalışmaya devam ediyor; ancak sunucu, uygulama ve cihaz ayarları lisans girilene kadar değiştirilemez. Modem IMEI: '));
		d.appendChild(c);
		d.appendChild(document.createTextNode(' · '));
		d.appendChild(a);
		box.appendChild(d);
	}).catch(() => { });
	return box;
}

return view.extend({
	/* Kart: başlığa tıklayınca içerik katlanır (tercih tarayıcıda saklanır) */
	card(el, key, title, children, right) {
		const open = !collapsed(key);
		const body = h('div', { 'class': 'kr-cbody' + (open ? '' : ' kr-fold') }, children);
		const cap = h('span', { 'class': 'kr-caret' }, open ? '▾' : '▸');
		const head = h('h3', { 'class': 'kr-ch', 'title': 'Küçült / aç' }, [cap, h('span', { 'class': 'kr-ct' }, title), right || '']);
		head.addEventListener('click', ev => {
			if (ev.target.closest('button, select, input, a')) return;
			const now = body.classList.toggle('kr-fold');
			cap.textContent = now ? '▸' : '▾';
			try { localStorage.setItem('kediray-fold-' + key, now ? '1' : '0'); } catch (e) {}
		});
		dom.content(el, [head, body]);
	},

	/* Kart içindeki bölüm: başlığa tıklayınca katlanır (tercih tarayıcıda saklanır) */
	fold(key, title, content) {
		const open = !collapsed(key);
		const body = h('div', { 'class': 'kr-cbody' + (open ? '' : ' kr-fold') }, content);
		const cap = h('span', { 'class': 'kr-caret' }, open ? '▾' : '▸');
		const head = h('div', { 'class': 'krc-title kr-ch', 'title': 'Küçült / aç' }, [cap, h('span', { 'class': 'kr-ct' }, title)]);
		head.addEventListener('click', () => {
			const now = body.classList.toggle('kr-fold');
			cap.textContent = now ? '▸' : '▾';
			try { localStorage.setItem('kediray-fold-' + key, now ? '1' : '0'); } catch (e) {}
		});
		return h('div', {}, [head, body]);
	},

	lastStats: null,
	liveRate: null,
	trafficBuilt: false,
	chartSig: '',
	days: null,

	load() {
		return Promise.all([
			runJson(['status', '--json']),
			runJson(['nodes']),
			runJson(['apps']),
			runJson(['devices'])
		]);
	},

	/* ---------- işlemler ---------- */
	busy(msg, p) {
		ui.showModal(null, [h('p', { 'class': 'spinning' }, msg)]);
		return p.then(r => { ui.hideModal(); return r; }, e => { ui.hideModal(); throw e; });
	},
	note(msg, type) { ui.addNotification(null, h('p', msg), type || 'info'); },

	fetchDirect() {
		return run(['direct']).then(r => {
			const dead = /Direkt çıkış: YOK/.test(r.stdout || '');
			const off = /Otomatik direkt denetimi: KAPALI/.test(r.stdout || '');
			const ch = dead !== this.directDead || off !== this.autoOff;
			this.directDead = dead;
			this.autoOff = off;
			return ch;
		});
	},
	async doAutoDirect(off) {
		await this.busy('Uygulanıyor…', run(['autodirect', off ? 'off' : 'on']));
		return this.refreshAll();
	},
	async doDirectCheck() {
		await this.busy('Direkt çıkış ölçülüyor…', run(['direct', 'check']));
		return this.refreshAll();
	},

	async refreshAll() {
		const [st, nodes, apps, devs] = await this.load();
		await this.fetchDirect();
		this.nodes = nodes || [];
		this.apps = apps || [];
		this.renderStatus(st);
		this.renderNodes(nodes || [], st);
		this.renderApps(apps || []);
		this.devSig = JSON.stringify((devs || []).map(x => [x.mac, x.ip, x.name, x.mode, x.online])) + '|' + this.directDead + this.autoOff;
		this.renderDevices(devs || []);
	},

	async doToggle(st) {
		const on = st && st.enabled;
		if (!on && st && st.conflict && st.conflict.length)
			return this.doTakeover(st);
		await this.busy(on ? 'VPN durduruluyor…' : 'VPN başlatılıyor…', run([on ? 'stop' : 'start']));
		return this.refreshAll();
	},
	async doTakeover(st) {
		const names = (st && st.conflict || []).join(', ');
		if (!confirm(names + ' durdurulup KediRay başlatılacak.\nİnternet gelmezse otomatik olarak ' + names + ' geri açılır.\n\nDevam edilsin mi?'))
			return;
		const r = await this.busy('Geçiş yapılıyor (en fazla ~40 sn)…', run(['takeover']));
		this.note((r.stdout || '') + (r.stderr ? '\n' + r.stderr : ''), r.code === 0 ? 'info' : 'warning');
		return this.refreshAll();
	},
	async doRestart() {
		await this.busy('Yeniden başlatılıyor…', run(['restart']));
		return this.refreshAll();
	},
	async doPing(sec) {
		await this.busy(sec ? 'Ölçülüyor…' : 'Tüm sunucular ölçülüyor…', runJson(['ping', sec || 'all', '--json']));
		return this.refreshAll();
	},
	async doBest() {
		const r = await this.busy('En hızlı sunucu aranıyor…', run(['best']));
		this.note(r.code === 0 ? (r.stdout || 'En hızlı sunucuya geçildi') : ('Bulunamadı: ' + (r.stderr || '')), r.code === 0 ? 'info' : 'warning');
		return this.refreshAll();
	},
	async doUse(sec) {
		await this.busy('Sunucu değiştiriliyor (bağlantılar kopmadan)…', run(['use', sec]));
		return this.refreshAll();
	},
	async doApp(sec, route) {
		await this.busy('Uygulanıyor…', run(['app', sec, route]));
		return this.refreshAll();
	},
	async doDevice(d, mode) {
		await this.busy('Uygulanıyor…', run(['device', d.mac, mode, d.name || '']));
		return this.refreshAll();
	},
	async doSub() {
		const r = await this.busy('Abonelikler güncelleniyor…', run(['sub']));
		this.note((r.stdout || '') + (r.stderr ? ' ' + r.stderr : ''));
		return this.refreshAll();
	},
	async doCheck() {
		const r = await this.busy('Bağlantı test ediliyor…', runJson(['check']));
		if (!r || !r.running) return this.note('VPN çalışmıyor.', 'warning');
		const ok = v => v ? '✅' : '❌';
		ui.showModal('Bağlantı teşhisi', [
			h('ul', {}, [
				h('li', {}, ok(r.dns) + ' DNS (Xray üzerinden)'),
				h('li', {}, ok(r.vpn) + ' VPN tüneli' + (r.vpn_ip ? ' — çıkış IP: ' + r.vpn_ip : '')),
				h('li', {}, ok(r.direct) + ' Direkt internet')
			]),
			h('div', { 'class': 'right' }, h('button', { 'class': 'btn', 'click': ui.hideModal }, 'Kapat'))
		]);
	},
	errList(res) {
		const errs = (res && res.errors) || [];
		if (!errs.length) return h('div', { 'class': 'kr-errs' }, 'Bilinmeyen hata: ' + ((res && res.raw) || 'yanıt alınamadı'));
		return h('div', { 'class': 'kr-errs' }, [
			h('b', {}, STAGE[res.stage] || 'Hata'),
			h('ul', {}, errs.map(e => h('li', {}, [
				e.name && e.stage ? h('b', {}, e.name + ': ') : '',
				e.line ? 'Satır ' + e.line + (e.col ? ', sütun ' + e.col : '') + ' — ' : '',
				e.field && !e.line ? '[' + e.field + '] ' : '',
				e.msg || '',
				e.detail && e.detail !== e.msg ? h('div', { 'class': 'kr-sub', 'style': 'font-size:.8em;word-break:break-all' }, e.detail) : ''
			])))
		]);
	},

	async doValidate() {
		const r = await this.busy('Yapılandırma denetleniyor…', runJson(['validate', '--json']));
		ui.showModal('Yapılandırma denetimi', [
			r && r.ok ? h('p', { 'class': 'kr-ok' }, '✅ Yazım, alan ve Xray denetimi: hata yok.') : this.errList(r),
			h('div', { 'class': 'right' }, h('button', { 'class': 'btn', 'click': ui.hideModal }, 'Kapat'))
		]);
	},

	async doDelete(n) {
		if (!confirm('"' + n.name + '" silinsin mi?')) return;
		const r = await this.busy('Siliniyor…', runJson(['node', 'del', n.sec]));
		if (!r || !r.ok) this.note('Silinemedi', 'error');
		return this.refreshAll();
	},

	/* ---------- sunucu düzenleyici: Form + JSON ---------- */
	async openEditor(sec) {
		let d;
		if (sec) {
			d = await runJson(['node', 'get', sec]);
			if (!d || !d.ok) return this.note('Sunucu okunamadı', 'error');
		} else {
			d = { mode: 'form', fields: { protocol: 'vless', network: 'ws', tls: 'tls', port: '443' }, json: JSON_TEMPLATE };
		}
		const f = Object.assign({}, d.fields || {});
		const inputs = {}, rows = {};
		let tab = d.mode === 'json' ? 'json' : 'form';

		const name = h('input', { 'type': 'text', 'class': 'cbi-input-text', 'style': 'width:100%', 'value': f.remarks || '', 'placeholder': 'ör. Almanya WS' });
		const errBox = h('div', {});
		const hint = h('div', { 'class': 'kr-hint' });

		const readForm = () => {
			const o = {};
			FIELDS.forEach(([k, , t]) => {
				const el = inputs[k];
				o[k] = t === 'checkbox' ? (el.checked ? '1' : '') : el.value.trim();
			});
			return o;
		};
		const refreshVis = () => {
			const cur = readForm();
			FIELDS.forEach(([k, , , , vis]) => { rows[k].forEach(el => el.style.display = (!vis || vis(cur)) ? '' : 'none'); });
			const ipTLS = /^\d+\.\d+\.\d+\.\d+$/.test(cur.address) && cur.tls === 'tls' && !cur.sni && !cur.insecure;
			hint.textContent = ipTLS ? 'IP adresiyle TLS kullanıyorsan SNI alanına alan adını yaz ya da "Sertifikayı doğrulama"yı işaretle.' : '';
		};
		const formGrid = h('div', { 'class': 'kr-form' });
		FIELDS.forEach(([k, label, t, opts]) => {
			let el;
			if (t === 'select') {
				el = h('select', { 'class': 'cbi-input-select' }, (opts || []).map(o => {
					const [v, l] = Array.isArray(o) ? o : [o, o];
					return h('option', { 'value': v, 'selected': (f[k] || '') === v ? '' : null }, l);
				}));
			} else if (t === 'checkbox') {
				el = h('input', { 'type': 'checkbox', 'checked': f[k] === '1' ? '' : null });
			} else {
				el = h('input', { 'type': 'text', 'class': 'cbi-input-text', 'value': f[k] || '', 'spellcheck': 'false', 'autocomplete': 'off' });
			}
			el.addEventListener('change', refreshVis);
			el.addEventListener('input', () => { el.classList.remove('kr-bad-input'); if (k === 'address' || k === 'sni') refreshVis(); });
			inputs[k] = el;
			const lab = h('label', {}, label);
			rows[k] = [lab, el];
			formGrid.appendChild(lab);
			formGrid.appendChild(el);
		});

		const ta = h('textarea', { 'class': 'kr-json', 'spellcheck': 'false', 'wrap': 'off' });
		ta.value = d.json || JSON_TEMPLATE;
		const gut = h('pre', { 'class': 'kr-gut' });
		const syncGut = () => {
			const nl = ta.value.split('\n').length;
			if (gut._n !== nl) { gut._n = nl; gut.textContent = Array.from({ length: nl }, (_, k) => k + 1).join('\n'); }
			gut.scrollTop = ta.scrollTop;
		};
		const fitHeight = () => {
			const nl = ta.value.split('\n').length;
			ta.style.height = Math.min(Math.max(nl + 2, 16), 44) * 18.2 + 14 + 'px';
		};
		ta.addEventListener('scroll', syncGut);
		ta.addEventListener('input', syncGut);
		const editor = h('div', { 'class': 'kr-ed' }, [gut, ta]);
		const wrapBtn = h('button', { 'class': 'btn cbi-button', 'click': ev => {
			ev.preventDefault();
			ta.classList.toggle('kr-wrap');
			ta.setAttribute('wrap', ta.classList.contains('kr-wrap') ? 'soft' : 'off');
			gut.style.display = ta.classList.contains('kr-wrap') ? 'none' : '';
			wrapBtn.textContent = ta.classList.contains('kr-wrap') ? '↔ Satırları kaydırma' : '↵ Uzun satırları kaydır';
		} }, '↵ Uzun satırları kaydır');
		const fullBtn = h('button', { 'class': 'btn cbi-button', 'click': ev => {
			ev.preventDefault();
			ta.style.height = ta.style.height === '78vh' ? '' : '78vh';
			if (!ta.style.height) fitHeight();
			syncGut();
		} }, '⤢ Büyüt / küçült');
		const jstat = h('div', { 'class': 'kr-jstat' });
		let lastErr = null;
		const checkJson = () => {
			lastErr = jsonCheck(ta.value);
			jstat.className = 'kr-jstat ' + (lastErr ? 'kr-no' : 'kr-ok');
			jstat.textContent = lastErr ? '❌ Satır ' + lastErr.line + ', sütun ' + lastErr.col + ': ' + lastErr.msg : '✅ Geçerli JSON';
		};
		let tmr = null;
		ta.addEventListener('input', () => { clearTimeout(tmr); tmr = setTimeout(checkJson, 250); });
		ta.addEventListener('keydown', ev => {   // Tab tuşu girinti eklesin
			if (ev.key === 'Tab') {
				ev.preventDefault();
				const a = ta.selectionStart, b = ta.selectionEnd;
				ta.value = ta.value.slice(0, a) + '  ' + ta.value.slice(b);
				ta.selectionStart = ta.selectionEnd = a + 2;
			}
		});
		const gotoErr = e => {
			if (!e) return;
			ta.focus();
			const pos = e.pos != null ? e.pos : ta.value.split('\n').slice(0, e.line - 1).join('\n').length + (e.line > 1 ? 1 : 0) + (e.col - 1);
			ta.setSelectionRange(pos, Math.min(pos + 1, ta.value.length));
			const lh = parseFloat(getComputedStyle(ta).lineHeight) || 18;
			ta.scrollTop = Math.max(0, (e.line - 4) * lh);
		};
		const fmtBtn = h('button', { 'class': 'btn cbi-button', 'click': ev => {
			ev.preventDefault();
			checkJson();
			if (lastErr) return gotoErr(lastErr);
			ta.value = JSON.stringify(JSON.parse(ta.value), null, 2);
			checkJson(); fitHeight(); syncGut();
		} }, '⇆ Biçimlendir (girintiyi düzelt)');
		const goBtn = h('button', { 'class': 'btn cbi-button', 'click': ev => { ev.preventDefault(); checkJson(); gotoErr(lastErr); } }, 'Hataya git');

		const formPane = h('div', {}, [
			d.mode === 'json' ? h('p', { 'class': 'kr-hint' }, 'Bu sunucu JSON ile eklenmiş. Form ile kaydedersen JSON\'a özel ince ayarlar kaybolabilir; o ayarlar için JSON sekmesini kullan.') : '',
			formGrid, hint
		]);
		const jsonPane = h('div', {}, [
			h('p', { 'class': 'kr-hint' }, 'Xray outbound JSON\'u. v2rayNG\'nin tam yapılandırmasını da yapıştırabilirsin, içinden sunucu kısmı alınır. Girinti hata değildir, "Biçimlendir" ile düzeltilir; virgül/tırnak hataları anında satır ve sütunuyla gösterilir.'),
			editor, jstat, h('div', { 'class': 'kr-row', 'style': 'margin-top:4px' }, [fmtBtn, goBtn, wrapBtn, fullBtn])
		]);
		const tFormBtn = h('button', {}, 'Form');
		const tJsonBtn = h('button', {}, '{ } JSON');
		const setTab = t => {
			tab = t;
			formPane.style.display = t === 'form' ? '' : 'none';
			jsonPane.style.display = t === 'json' ? '' : 'none';
			tFormBtn.className = t === 'form' ? 'kr-act' : '';
			tJsonBtn.className = t === 'json' ? 'kr-act' : '';
			if (t === 'json') { checkJson(); fitHeight(); syncGut(); }
		};
		tFormBtn.addEventListener('click', ev => { ev.preventDefault(); setTab('form'); });
		tJsonBtn.addEventListener('click', ev => { ev.preventDefault(); setTab('json'); });

		const save = async () => {
			dom.content(errBox, '');
			let args;
			if (tab === 'json') {
				checkJson();
				if (lastErr) { dom.content(errBox, this.errList({ stage: 'syntax', errors: [lastErr] })); gotoErr(lastErr); return; }
				args = ['node', 'save', sec || 'new', 'json', ta.value, name.value.trim()];
			} else {
				const o = readForm();
				o.remarks = name.value.trim();
				const vis = {};
				FIELDS.forEach(([k, , , , v]) => { if (!v || v(o)) vis[k] = o[k]; });
				vis.remarks = o.remarks;
				args = ['node', 'save', sec || 'new', 'form', JSON.stringify(vis)];
			}
			const r = await run(args);
			let res = null;
			try { res = JSON.parse(r.stdout); } catch (e) { res = { ok: false, raw: (r.stdout || '') + (r.stderr || '') }; }
			if (res && res.ok) {
				ui.hideModal();
				this.note('Kaydedildi' + (sec ? '' : ' (yeni sunucu eklendi)') + '. Ayar denetimden ve Xray testinden geçti.');
				return this.refreshAll();
			}
			dom.content(errBox, this.errList(res));
			(res.errors || []).forEach(e => { if (e.field && inputs[e.field]) inputs[e.field].classList.add('kr-bad-input'); });
			if (tab === 'json' && res.stage === 'syntax' && res.errors && res.errors[0]) gotoErr(res.errors[0]);
		};

		ui.showModal(sec ? 'Sunucuyu düzenle' : 'Yeni sunucu', [
			h('div', { 'class': 'kr-form', 'style': 'margin-bottom:6px' }, [h('label', {}, 'Ad'), name]),
			d.sub ? h('p', { 'class': 'kr-hint' }, 'Not: Bu sunucu abonelikten geliyor; abonelik güncellenince değişikliğin üzerine yazılabilir.') : '',
			(d.errors && d.errors.length) ? this.errList({ stage: 'node', errors: d.errors }) : '',
			h('div', { 'class': 'kr-tabs' }, [tFormBtn, tJsonBtn]),
			formPane, jsonPane, errBox,
			h('div', { 'class': 'right', 'style': 'margin-top:10px' }, [
				h('button', { 'class': 'btn', 'click': ui.hideModal }, 'İptal'), ' ',
				h('button', { 'class': 'btn cbi-button-positive', 'click': ui.createHandlerFn(this, save) }, 'Denetle ve kaydet')
			])
		], 'kr-wide');
		refreshVis();
		setTab(tab);
	},

	showAdd() {
		const ta = h('textarea', { 'style': 'width:100%;height:190px;font-family:monospace', 'placeholder':
			'vless://...  vmess://...  trojan://...  ss://...\n(birden fazla satır olabilir)\n\nveya Xray JSON: tek outbound, outbound dizisi\nya da v2rayNG "tam yapılandırma" JSON\'u' });
		ui.showModal('Sunucu ekle — link veya JSON', [
			ta,
			h('p', { 'class': 'kr-sub' }, 'İpucu: v2rayNG\'de sunucuya uzun bas → "Tam yapılandırmayı panoya aktar" ile JSON\'u birebir alabilirsin.'),
			h('div', { 'class': 'right' }, [
				h('button', { 'class': 'btn', 'click': ui.hideModal }, 'İptal'), ' ',
				h('button', { 'class': 'btn cbi-button-positive', 'click': ui.createHandlerFn(this, async () => {
					const v = ta.value.trim();
					if (!v) return;
					const r = await this.busy('Ekleniyor…', run(['add', v]));
					this.note(r.code === 0 ? r.stdout : ('Eklenemedi: ' + (r.stderr || 'geçerli link/JSON yok')), r.code === 0 ? 'info' : 'error');
					return this.refreshAll();
				}) }, 'Ekle')
			])
		]);
	},
	async showConns(ip) {
		const list = await this.busy('Bağlantılar okunuyor…', runJson(['conns', ip, '--json']));
		const apps = (this.apps || []).filter(a => a.route === 'direct');
		const sel = h('select', { 'class': 'cbi-input-select' }, apps.map(a => h('option', { 'value': a.sec }, a.name)));
		const rows = (list || []).slice(0, 60).map(c => h('tr', { 'class': 'tr' }, [
			h('td', { 'class': 'td' }, c.proto),
			h('td', { 'class': 'td' }, c.dst), h('td', { 'class': 'td' }, String(c.port)),
			h('td', { 'class': 'td' }, String(c.n)),
			h('td', { 'class': 'td' }, h('span', { 'class': 'kr-ping ' + (c.vpn ? 'kr-mid' : 'kr-good') }, c.vpn ? 'VPN' : 'Direkt')),
			h('td', { 'class': 'td' }, c.web ? h('span', { 'class': 'kr-sub' }, 'web') : h('b', {}, 'oyun/uygulama?')),
			h('td', { 'class': 'td' }, c.vpn && apps.length
				? btn.call(this, 'Direkt yap', 'cbi-button-action', () => this.doDirect(sel.value, c), 'Bu sunucuyu (ve komşularını) seçili uygulamaya ekler')
				: '')
		]));
		ui.showModal('Aktif bağlantılar — ' + (ip || 'tüm cihazlar'), [
			h('p', { 'class': 'kr-sub' }, 'Oyun açıkken bak. Oyunun satırlarında "VPN" yazıyorsa oyun tünelden geçiyor: ışınlanırken sunucu IP değişti sanıp atabilir. "Direkt yap" o sunucuyu (aynı /24 komşuları) ve portunu seçili uygulamaya ekler.'),
			apps.length ? h('div', { 'class': 'kr-row', 'style': 'margin:0 0 8px' }, [h('label', {}, 'Eklenecek uygulama:'), sel]) : '',
			h('table', { 'class': 'table kr-table' }, [
				h('tr', { 'class': 'tr table-titles' }, ['Proto', 'Hedef', 'Port', 'Adet', 'Yol', '', ''].map(x => h('th', { 'class': 'th' }, x))),
				...rows
			]),
			h('div', { 'class': 'right' }, h('button', { 'class': 'btn', 'click': ui.hideModal }, 'Kapat'))
		], 'kr-wide');
	},

	async doDirect(sec, c) {
		if (!sec) return;
		const net = c.dst.split('.').slice(0, 3).join('.') + '.0/24';
		const r1 = await run(['app', sec, 'add-ip', net]);
		const r2 = c.web ? { code: 0 } : await run(['app', sec, 'add-port', String(c.port)]);
		ui.hideModal();
		if (r1.code === 0 && r2.code === 0)
			ui.addNotification(null, h('p', {}, net + (c.web ? '' : ' ve port ' + c.port) + ' direkt listeye eklendi. Oyunu yeniden başlatmadan denemek için önce oyundan çık.'), 'info');
		else
			ui.addNotification(null, h('p', {}, 'Eklenemedi: ' + ((r1.stderr || r2.stderr || '').trim() || 'bilinmeyen hata')), 'error');
	},

	/* ---------- çizim ---------- */
	renderStatus(st) {
		st = st || {};
		const dot = st.running ? 'kr-on' : (st.enabled ? 'kr-err' : 'kr-off');
		const txt = st.running ? 'Çalışıyor' : (st.enabled ? 'Durdu — Günlük sekmesine bak' : 'Kapalı');
		const modes = { rule: 'Tümü VPN', global: 'Tümü VPN', list: 'Sadece liste VPN' };
		const cf = st.conflict || [];
		this.card(this.elStatus, 'status', 'Durum', [
			h('div', { 'class': 'kr-big' }, [h('span', { 'class': 'kr-dot ' + dot }), txt]),
			h('div', { 'class': 'kr-sub' }, [
				'Xray ', st.core || '?', ' · Mod: ', modes[st.mode] || st.mode || '-',
				' · Yakalama: ', ({ mixed: 'Mixed (TCP çekirdek + UDP hev)', tun: 'TUN (hepsi hev-socks5-tunnel)', tproxy: 'TPROXY', redirect: 'Redirect (sadece TCP)' })[st.capture] || st.capture || '-',
				st.running ? [' · Açık: ', live(st.uptime)] : '',
				st.direct_dead ? ' · Direkt çıkış yok: "direkt" uygulamalar da VPN\'den çıkıyor' : ''
			]),
			cf.length ? h('div', { 'class': 'kr-warn' }, [
				h('b', {}, 'Şu an ' + cf.join(', ') + ' çalışıyor. '),
				'İkisi aynı anda trafiği yönetemez; KediRay kapalı bekliyor. "Güvenli geçiş" ' + cf.join(', ') +
				'\'i durdurur, artıklarını temizler ve KediRay\'i başlatır. İnternet gelmezse otomatik geri alır.'
			]) : '',
			st.dns_rescue ? h('div', { 'class': 'kr-warn' }, [
				h('b', {}, 'DNS acil yedeği devrede. '),
				'Tünelden giden DNS yanıt vermedi, adresler geçici olarak operatörün DNS\'iyle çözülüyor — internet çalışmaya devam ediyor ama bu sorgular tünelden geçmiyor. Tünel düzelince kendiliğinden geri döner. Sebebini görmek için "🤝 Sunucu el sıkışması"na bas.'
			]) : '',
			st.last_error ? h('div', { 'class': 'kr-errs' }, [
				h('b', {}, 'Yapılandırma hatası — VPN başlatılamadı'),
				h('pre', { 'style': 'white-space:pre-wrap;margin:6px 0 0;font-size:.85em' }, st.last_error)
			]) : '',
			h('div', { 'class': 'kr-row' }, [
				cf.length && !st.enabled
					? btn.call(this, '⇄ Güvenli geçiş', 'cbi-button-positive', () => this.doTakeover(st))
					: btn.call(this, st.enabled ? 'Durdur' : 'Başlat', st.enabled ? 'cbi-button-negative' : 'cbi-button-positive', () => this.doToggle(st)),
				btn.call(this, 'Yeniden başlat', 'cbi-button-action', () => this.doRestart()),
				btn.call(this, 'Teşhis', '', () => this.doCheck()),
				btn.call(this, '✓ Ayarları denetle', '', () => this.doValidate(), 'Yazım/alan hatası ve Xray testi'),
				btn.call(this, '⏱ Hız testi', '', () => this.doSpeed(), 'Direkt ve VPN hızını karşılaştır'),
				btn.call(this, '🐢 Sayfa gecikmesi', '', () => this.doWebtest(), 'Sayfa neden geç açılıyor: DNS mi, tünel mi?'),
				btn.call(this, '🔎 Takılma avı', '', () => this.doHunt(), 'Tarayıcıda takılan adresleri arka arkaya dener: takılma DNS\'te mi bağlantıda mı?'),
				btn.call(this, '🤝 Sunucu el sıkışması', '', () => this.doDial(), 'Sunucu bağlantıyı kaç kez düşürüyor (günlükteki EOF hatası)'),
				btn.call(this, '{ } Xray yapılandırması', '', () => this.showConfig(), 'Üretilen tam config.json')
			])
		]);
		const a = st.active;
		// Kullanıcı açılır listeyi kullanırken periyodik yenileme listeyi bozmasın
		if (this.elNode.contains(document.activeElement) && document.activeElement.tagName === 'SELECT') return;
		const nodes = (this.nodes || []).filter(n => n.enabled !== false);
		const curSec = st.auto ? (a ? a.sec : '') : (st.selected ? st.selected.sec : '');
		const sel = h('select', { 'class': 'cbi-input-select' }, nodes.map(n =>
			h('option', { 'value': n.sec, 'selected': n.sec === curSec ? '' : null },
				n.name + (n.ping != null && n.ping < 0 ? '  (yok)' : n.rtt ? '  (' + n.rtt + ' ms)' : n.ping != null ? '  (tünel ' + n.ping + ' ms)' : ''))));
		const sw = h('input', { 'type': 'checkbox', 'checked': st.auto ? '' : null });
		sw.addEventListener('change', ui.createHandlerFn(this, () => this.doAuto(sw.checked)));
		this.card(this.elNode, 'node', 'Bağlı sunucu', [
			h('div', { 'class': 'kr-big' }, a ? a.name : (st.running ? '…' : (st.selected ? st.selected.name : '—'))),
			h('div', { 'class': 'kr-sub' }, [
				a ? [a.protocol, a.network].filter(Boolean).join(' · ') + ' · ' : '',
				st.auto ? h('span', { 'class': 'kr-tag' }, 'OTOMATİK') : h('span', { 'class': 'kr-tag' }, 'ELLE SEÇİLDİ'),
				' ', a ? pingBadge(a.ping, a.rtt, a.warm) : ''
			]),
			// Bağlanılan adres: alan adı ya da IP (alan adıyla bağlanıldıysa çözülen IP de yazar)
			a && a.address ? h('div', { 'class': 'kr-addr' }, [
				h('span', { 'class': 'kr-sub' }, a.ip ? 'Sunucu (alan adı): ' : 'Sunucu IP\'si: '),
				h('code', { 'class': 'kr-mono' }, a.address + (a.port ? ':' + a.port : '')),
				a.ip ? [h('span', { 'class': 'kr-sub' }, ' → IP: '), h('code', { 'class': 'kr-mono' }, a.ip)] : ''
			]) : '',
			h('label', { 'class': 'kr-switch', 'style': 'margin-top:10px' }, [
				sw, h('span', { 'class': 'kr-knob' }),
				h('span', {}, [h('b', {}, 'Otomatik geçiş'), h('span', { 'class': 'kr-sub' },
					st.auto ? ' — seçili sunucuda kalır, sadece o düşerse diğerine geçer (oyunda IP değişmez)' : ' — kapalı: seçtiğin sunucuda kalır, hiç geçiş yapılmaz')])
			]),
			h('div', { 'class': 'kr-srv' }, nodes.length ? [
				sel,
				btn.call(this, 'Bu sunucuya bağlan', 'cbi-button-action', () => this.doUse(sel.value), 'Elle seç (otomatik geçiş kapanır)')
			] : h('span', { 'class': 'kr-sub' }, 'Sunucu yok')),
			h('div', { 'class': 'kr-row' }, [
				btn.call(this, '⚡ Ping ölç', '', () => this.doPing(null)),
				btn.call(this, '🚀 En hızlıyı bul ve bağlan', 'cbi-button-positive', () => this.doBest()),
				(this.nodes || []).some(n => n.insecure) ? btn.call(this, '🔒 Sertifikayı sabitle', '', () => this.doPin(null), 'Sunucunun şu anki sertifikasını sabitler; değiştiyse tüneli yeniden başlatır (internet gittiyse bas)') : ''
			])
		]);
	},

	async doPin(sec) {
		const r = await this.busy('Sertifika sabitleniyor…', run(sec ? ['pin', sec] : ['pin']));
		const out = ((r.stdout || '') + ' ' + (r.stderr || '')).trim().split('\n').join(' · ');
		this.note(out || 'Bitti', r.code === 0 ? 'info' : 'warning');
		return this.refreshAll();
	},

	async doAuto(on) {
		await this.busy(on ? 'Otomatik geçiş açılıyor…' : 'Şu anki sunucuda sabitleniyor…', run(['auto', on ? 'on' : 'off']));
		return this.refreshAll();
	},

	async doWebtest() {
		const raw = await this.busy('Sayfa açılma süresi ölçülüyor (≈10 sn)…', run(['webtest', '--json']));
		let r = null;
		try { r = JSON.parse(raw.stdout || 'null'); } catch (e) { r = null; }
		if (!r || !r.tests)
			return ui.showModal('Sayfa gecikmesi — ölçüm yapılamadı', [
				h('p', {}, 'Komut beklenen çıktıyı vermedi. Terminalde şunu çalıştırıp çıktıyı paylaşabilirsin:'),
				h('pre', { 'class': 'kr-view' }, 'kediray webtest'),
				h('p', { 'class': 'kr-sub' }, 'Çıkış kodu: ' + raw.code),
				(raw.stderr || raw.stdout) ? h('details', {}, [h('summary', {}, 'Çıktı'), h('pre', { 'class': 'kr-view' }, ((raw.stderr || '') + '\n' + (raw.stdout || '')).trim())]) : '',
				h('div', { 'class': 'right' }, h('button', { 'class': 'btn', 'click': ui.hideModal }, 'Kapat'))
			], 'kr-wide');
		const ms = v => (v == null ? '—' : v + ' ms');
		const rows = [];
		r.tests.forEach(t => {
			const line = (label, x, cls) => h('tr', { 'class': 'tr' + (cls || '') }, [
				h('td', { 'class': 'td' }, label),
				h('td', { 'class': 'td krt-n' }, ms(x.dns)), h('td', { 'class': 'td krt-n' }, ms(x.connect)),
				h('td', { 'class': 'td krt-n' }, ms(x.tls)), h('td', { 'class': 'td krt-n' }, ms(x.ttfb)),
				h('td', { 'class': 'td krt-n' }, h('b', {}, ms(x.total))),
				h('td', { 'class': 'td' }, x.code ? String(x.code) : h('span', { 'style': 'color:#e05252' }, 'yanıt yok'))
			]);
			rows.push(h('tr', { 'class': 'tr' }, h('td', { 'class': 'td', 'colspan': 7 }, h('b', {}, t.host))));
			rows.push(line('  direkt', t.direct));
			if (r.running) rows.push(line('  VPN', t.vpn, ' kr-active'));
		});
		ui.showModal('Sayfa açılma gecikmesi', [
			h('p', { 'class': 'kr-sub' }, 'Bir sayfanın açılması: DNS (adres çözme) → bağlantı → TLS → ilk bayt. Hangi aşamada beklendiği aşağıda. DNS süresi ikisinde de aynıdır: o modemin kendi DNS yolu.'),
			h('table', { 'class': 'table kr-table' }, [
				h('tr', { 'class': 'tr table-titles' }, ['', 'DNS', 'Bağlantı', 'TLS', 'İlk bayt', 'Toplam', 'HTTP'].map((x, i) =>
					h('th', { 'class': 'th' + (i ? ' krt-n' : '') }, x))),
				...rows
			]),
			r.verdict && r.verdict.length ? h('ul', {}, r.verdict.map(v => h('li', {}, v))) : '',
			h('div', { 'class': 'right' }, h('button', { 'class': 'btn', 'click': ui.hideModal }, 'Kapat'))
		], 'kr-wide');
	},

	// Arka planda çalışan uzun ölçümü aç, bitene kadar canlı oku (arayüz isteği zaman aşımına düşmesin)
	async bgWatch(title, args, hint, verdict) {
		const kick = await run([args[0], '--bg', ...args.slice(1)]);
		if (kick.code !== 0)
			return ui.showModal(title + ' — başlatılamadı', [
				h('p', {}, 'Komut çalışmadı. SSH ile deneyebilirsin:'),
				h('pre', { 'class': 'kr-view' }, 'kediray ' + args.join(' ')),
				h('pre', { 'class': 'kr-view' }, ((kick.stderr || '') + '\n' + (kick.stdout || '')).trim() || 'çıkış kodu: ' + kick.code),
				h('div', { 'class': 'right' }, h('button', { 'class': 'btn', 'click': ui.hideModal }, 'Kapat'))
			], 'kr-wide');
		const pre = h('pre', { 'class': 'kr-view', 'style': 'max-height:50vh' }, 'Ölçüm başladı, ilk sonuçlar birkaç saniye içinde…');
		const head = h('p', {}, h('b', {}, 'Ölçüm sürüyor…'));
		const closed = { v: false };
		ui.showModal(title, [
			head, pre,
			h('p', { 'class': 'kr-sub' }, hint),
			h('div', { 'class': 'right' }, h('button', { 'class': 'btn', 'click': () => { closed.v = true; ui.hideModal(); } }, 'Kapat'))
		], 'kr-wide');
		for (let i = 0; i < 120 && !closed.v; i++) {
			const r = await run([args[0], '--read']);
			const nl = (r.stdout || '').indexOf('\n');
			const state = nl < 0 ? (r.stdout || '').trim() : r.stdout.slice(0, nl).trim();
			const body = nl < 0 ? '' : r.stdout.slice(nl + 1);
			if (closed.v) return;
			if (body.trim()) pre.textContent = body.trimEnd();
			if (state === 'BITTI') { head.textContent = ''; head.appendChild(h('b', {}, verdict(body))); return; }
			if (state === 'BASLAMADI' && i > 3) { head.textContent = 'Ölçüm çıktısı bulunamadı. SSH: kediray ' + args.join(' '); return; }
			await new Promise(res => setTimeout(res, 2000));
		}
		if (!closed.v) head.textContent = 'Ölçüm hâlâ sürüyor. Düğmeye tekrar basarak kaldığı yerden okuyabilirsin.';
	},

	doDial() {
		return this.bgWatch('Sunucu el sıkışması', ['dialtest', '10'],
			'Her sunucu adresine 10 kez sıfırdan bağlanılır. Alan adı birden çok IP\'ye çözülüyorsa her IP ayrı ölçülür.',
			out => this.dialVerdict(out));
	},

	dialVerdict(out) {
		const lines = (out || '').split('\n');
		if (!lines.some(l => /başarılı/.test(l))) return 'Ölçüm sonucu okunamadı: aşağıdaki çıktıyı paylaş ya da SSH ile "kediray dialtest" çalıştır.';
		const bad = lines.filter(l => /DÜŞTÜ/.test(l) && /\d+\/\d+ başarılı/.test(l));
		const good = lines.filter(l => /\d+\/\d+ başarılı/.test(l) && !/DÜŞTÜ/.test(l));
		if (!bad.length) return 'Sunucu her denemede el sıkıştı: bağlantı kurulumu sağlam. Sayfa takılmaları başka yerde.';
		if (good.length) return 'Bazı IP\'ler bağlantıyı düşürüyor, bazıları sağlam. Ayarlar → Genel → "Sunucuya IP ile bağlan" seçeneğini kapat: her bağlantıda çalışan IP denenir.';
		return 'Sunucu bağlantıları düşürüyor (günlükteki EOF hatası bu). Sayfalarda takılan istekler bunlar: sunucu yükü/port kısıtı olabilir — başka port ya da ikinci sunucu dene.';
	},

	async doHunt() {
		// Ölçüm 1 dk'yı aşabiliyor; arayüzün isteği o kadar bekleyemediği için arka planda çalıştırıp okuyoruz
		const kick = await run(['hunt', '--bg', '5']);
		if (kick.code !== 0)
			return ui.showModal('Takılma avı başlatılamadı', [
				h('p', {}, 'Komut çalışmadı. SSH ile şunu deneyip çıktıyı paylaşabilirsin:'),
				h('pre', { 'class': 'kr-view' }, 'kediray hunt 10'),
				h('pre', { 'class': 'kr-view' }, ((kick.stderr || '') + '\n' + (kick.stdout || '')).trim() || 'çıkış kodu: ' + kick.code),
				h('div', { 'class': 'right' }, h('button', { 'class': 'btn', 'click': ui.hideModal }, 'Kapat'))
			], 'kr-wide');

		const pre = h('pre', { 'class': 'kr-view', 'style': 'max-height:50vh' }, 'Ölçüm başladı, ilk sonuçlar birkaç saniye içinde…');
		const head = h('p', {}, h('b', {}, 'Ölçüm sürüyor…'));
		const closed = { v: false };
		const close = () => { closed.v = true; ui.hideModal(); };
		ui.showModal('Takılma avı', [
			head, pre,
			h('p', { 'class': 'kr-sub' }, 'Her adres 5 kez denenir. Pencereyi kapatsan da ölçüm arkada biter; tekrar bakmak için düğmeye bas.'),
			h('div', { 'class': 'right' }, h('button', { 'class': 'btn', 'click': close }, 'Kapat'))
		], 'kr-wide');

		for (let i = 0; i < 90 && !closed.v; i++) {
			const r = await run(['hunt', '--read']);
			const nl = (r.stdout || '').indexOf('\n');
			const state = nl < 0 ? (r.stdout || '').trim() : r.stdout.slice(0, nl).trim();
			const body = nl < 0 ? '' : r.stdout.slice(nl + 1);
			if (closed.v) return;
			if (body.trim()) pre.textContent = body.trimEnd();
			if (state === 'BITTI') {
				head.textContent = '';
				head.appendChild(h('b', {}, this.huntVerdict(body)));
				return;
			}
			if (state === 'BASLAMADI' && i > 3) {
				head.textContent = 'Ölçüm çıktısı bulunamadı. SSH: kediray hunt 10';
				return;
			}
			await new Promise(res => setTimeout(res, 2000));
		}
		if (!closed.v) head.textContent = 'Ölçüm hâlâ sürüyor. Düğmeye tekrar basarak kaldığı yerden okuyabilirsin.';
	},

	// Çıktıdan tek cümlelik sonuç. Çıktı yoksa ASLA "takılma yok" demeyiz: bilmiyoruz demektir.
	huntVerdict(out) {
		const lines = (out || '').split('\n');
		const tried = lines.filter(l => /deneme/.test(l) || /başarılı/.test(l));
		if (!tried.length) return 'Ölçüm sonucu okunamadı: aşağıdaki çıktıyı paylaş ya da SSH ile "kediray hunt 10" çalıştır.';
		const fails = lines.filter(l => /BAŞARISIZ/.test(l));
		const slow = lines.filter(l => /YAVAŞ/.test(l));
		if (fails.length)
			return /DNS aşamasında/.test(fails.join(' '))
				? 'Takılmalar ad çözümlemede (DNS): ' + fails.length + ' deneme DNS aşamasında düştü. Ayarlar → DNS bölümünden mod değiştirip tekrar ölçelim.'
				: 'Takılmalar bağlantı aşamasında: tünelin sunucuya bağlanması takılıyor. Sunucu/port/SNI ya da başka bir sunucu denenmeli.';
		if (slow.length)
			return 'Hiçbir deneme düşmedi ama ' + slow.length + ' deneme 3 sn üstünde kaldı: aşağıda hangi aşamanın beklediği yazıyor.';
		return 'Modem tarafında takılma yok: bu adresler her denemede hızlı açıldı. Takılma tarayıcı tarafındadır (Chrome → Gizlilik → "Güvenli DNS" kapalı olmalı; ayrıca IPv6/QUIC).';
	},

	async doSpeed() {
		const r = await this.busy('Hız testi yapılıyor (≈30 sn)…', runJson(['speedtest', '--json']));
		if (!r) return this.note('Hız testi yapılamadı', 'error');
		const tip = [];
		if (r.running && r.direct_mbps > 0) {
			const ratio = r.vpn_mbps / r.direct_mbps;
			if (ratio < 0.3) tip.push('VPN hızı direktin çok altında: sunucunun hattı/uzaklığı ya da sunucu tarafı sınırı olabilir. "En hızlıyı bul" ile başka sunucu dene.');
			else if (ratio < 0.7) tip.push('VPN hızı direktin bir miktar altında; WS+TLS tünelde bu normal sayılır.');
			else tip.push('VPN hızı direkte yakın, tünel sorunsuz.');
		}
		if (r.dns_ms > 300) tip.push('DNS yavaş (' + r.dns_ms + ' ms): Ayarlar → DNS → "Hızlı" modunu kullan.');
		ui.showModal('Hız testi (modem üzerinden)', [
			h('table', { 'class': 'table kr-table' }, [
				h('tr', { 'class': 'tr table-titles' }, ['', 'İndirme', 'Gecikme'].map(x => h('th', { 'class': 'th' }, x))),
				h('tr', { 'class': 'tr' }, [h('td', { 'class': 'td' }, 'Direkt'), h('td', { 'class': 'td' }, r.direct_mbps + ' Mbps'), h('td', { 'class': 'td' }, r.direct_ms + ' ms')]),
				h('tr', { 'class': 'tr' }, [h('td', { 'class': 'td' }, 'VPN'), h('td', { 'class': 'td' }, r.running ? r.vpn_mbps + ' Mbps' : 'kapalı'), h('td', { 'class': 'td' }, r.running ? r.vpn_ms + ' ms' : '—')]),
				h('tr', { 'class': 'tr' }, [h('td', { 'class': 'td' }, 'DNS çözümleme'), h('td', { 'class': 'td' }, ''), h('td', { 'class': 'td' }, r.dns_ms + ' ms')])
			]),
			tip.length ? h('ul', {}, tip.map(t => h('li', {}, t))) : '',
			h('p', { 'class': 'kr-sub' }, 'Ölçüm modemin kendi bağlantısıyla yapılır (Cloudflare, 20 MB). Wi-Fi hızın bundan düşükse darboğaz Wi-Fi\'dır.'),
			h('div', { 'class': 'right' }, h('button', { 'class': 'btn', 'click': ui.hideModal }, 'Kapat'))
		]);
	},

	async showConfig() {
		const r = await run(['show-config']);
		ui.showModal('Üretilen Xray yapılandırması (salt okunur)', [
			r.code === 0 ? h('pre', { 'class': 'kr-view' }, r.stdout) : h('p', {}, (r.stderr || 'Yapılandırma yok').trim()),
			h('div', { 'class': 'right' }, h('button', { 'class': 'btn', 'click': ui.hideModal }, 'Kapat'))
		], 'kr-wide');
	},

	/* Trafik: canlı hız + dönem tablosu (VPN ve Direkt ayrı) + 30 günlük yığılmış çubuk grafik.
	   Kaynak: `kediray stats` = { t, counters:{vr,vt,wr,wt}, today, yesterday, week, month, total, since, days:[{day,vr,vt,dr,dt}] }
	   vr/vt = VPN indirme/yükleme (tünelin dış baytları), dr/dt = Direkt = WAN toplamı − VPN. */
	trafficLive(s) {
		let r = { vd: 0, vu: 0, dd: 0, du: 0 };
		const p = this.lastStats, c = s.counters;
		if (p && s.t > p.t) {
			const dt = s.t - p.t, pc = p.counters;
			// sayaç sıfırlandıysa (tablo yeniden kuruldu) fark = şimdiki değer
			const d = (a, b) => (a >= b ? a - b : a) / dt;
			const vd = d(c.vr, pc.vr), vu = d(c.vt, pc.vt);
			r = { vd, vu, dd: Math.max(0, d(c.wr, pc.wr) - vd), du: Math.max(0, d(c.wt, pc.wt) - vu) };
		} else if (this.liveRate) r = this.liveRate;
		this.liveRate = r;
		this.lastStats = s;
		return r;
	},

	trafficChart(days) {
		const W = Math.max(280, Math.min(1100, this.elChart.clientWidth || 700)), H = 170;
		const L = 46, R = 8, T = 10, B = 24, pw = W - L - R, ph = H - T - B;
		const n = days.length, slot = pw / n, bw = Math.min(24, Math.max(4, slot - 4));
		const tot = days.map(x => x.vr + x.vt + x.dr + x.dt);
		const max = Math.max(1, ...tot);
		// "güzel" üst sınır: 1/2/5 × 10^k
		const pow = Math.pow(10, Math.floor(Math.log10(max))), top = [1, 2, 5, 10].map(m => m * pow).find(v => v >= max);
		const y = v => T + ph - (v / top) * ph;
		let g = '';
		for (let i = 0; i <= 4; i++) {
			const v = top * i / 4, yy = y(v).toFixed(1);
			g += '<line x1="' + L + '" x2="' + (W - R) + '" y1="' + yy + '" y2="' + yy + '" class="krc-grid"/>' +
				'<text x="' + (L - 6) + '" y="' + (+yy + 4) + '" text-anchor="end" class="krc-ax">' + (v ? fmtBytes(v) : '0') + '</text>';
		}
		let bars = '';
		days.forEach((x, i) => {
			const cx = L + slot * i + slot / 2, x0 = (cx - bw / 2).toFixed(1);
			const vpn = x.vr + x.vt, dir = x.dr + x.dt;
			const hv = vpn > 0 ? Math.max(1, (vpn / top) * ph) : 0, hd = dir > 0 ? Math.max(1, (dir / top) * ph) : 0;
			const base = T + ph;
			// alt: VPN, üst: Direkt; en üstteki parçanın ucu 4px yuvarlak, taban düz; ikisi arasında 2px yüzey boşluğu
			const gap = hv > 0 && hd > 2 ? 2 : 0;
			if (hv > 0) bars += hd > 0 ? '<rect x="' + x0 + '" y="' + (base - hv).toFixed(1) + '" width="' + bw.toFixed(1) + '" height="' + hv.toFixed(1) + '" class="krc-vpn"/>'
				: '<path d="' + roundTop(+x0, base - hv, bw, hv, 4) + '" class="krc-vpn"/>';
			if (hd > 0) bars += '<path d="' + roundTop(+x0, base - hv - hd, bw, hd - gap, 4) + '" class="krc-dir"/>';
			// gezinme hedefi: sütunun tamamı
			bars += '<rect x="' + (L + slot * i).toFixed(1) + '" y="' + T + '" width="' + slot.toFixed(1) + '" height="' + ph + '" class="krc-hit" data-i="' + i + '"/>';
			if (i % Math.ceil(n / (W < 500 ? 5 : 10)) === 0 || i === n - 1)
				bars += '<text x="' + cx.toFixed(1) + '" y="' + (H - 6) + '" text-anchor="middle" class="krc-ax">' + x.day.slice(8) + '.' + x.day.slice(5, 7) + '</text>';
		});
		return '<svg viewBox="0 0 ' + W + ' ' + H + '" width="' + W + '" height="' + H + '" class="krc-svg" role="img" aria-label="Son 30 gün trafik (VPN ve Direkt)">' + g + bars + '</svg>';
	},

	renderTraffic(s) {
		if (!s || !s.counters || !s.today) { this.card(this.elTraffic, 'traffic', 'Trafik', h('div', { 'class': 'kr-sub' }, 'Henüz veri yok')); this.trafficBuilt = false; return; }
		const r = this.trafficLive(s);
		if (!this.trafficBuilt) {
			this.elLive = h('div', {});
			this.elPeriods = h('div', {});
			this.elDevTr = h('div', {});
			this.elChart = h('div', { 'class': 'krc-wrap' });
			this.elTip = h('div', { 'class': 'krc-tip', 'style': 'display:none' });
			this.elChart.appendChild(this.elTip);
			this.elSvg = h('div', {});
			this.elChart.insertBefore(this.elSvg, this.elTip);
			this.elChart.addEventListener('mousemove', ev => this.trafficHover(ev));
			this.elChart.addEventListener('mouseleave', () => { this.elTip.style.display = 'none'; });
			this.elChart.addEventListener('click', ev => this.trafficHover(ev));
			this.card(this.elTraffic, 'traffic', 'Trafik', [
				this.elLive,
				this.fold('t-periods', 'Bugün / Dün / Bu hafta / Bu ay / Toplam', this.elPeriods),
				this.fold('t-devs', 'Cihaz bazında trafik', this.elDevTr),
				this.fold('t-chart', 'Son 30 gün (günlük)', h('div', {}, [
					h('div', { 'class': 'krc-legend' }, [
						h('span', {}, [h('i', { 'class': 'krc-sw krc-vpn' }), 'VPN']),
						h('span', {}, [h('i', { 'class': 'krc-sw krc-dir' }), 'Direkt'])
					]),
					this.elChart
				])),
				h('div', { 'class': 'kr-sub', 'style': 'margin-top:8px' }, 'VPN = tünel trafiği. Direkt = modem toplamı − VPN (VPN\'siz çıkan her şey). Sayaçlar yeniden başlatmada saklanır.')
			]);
			this.trafficBuilt = true;
		}

		const pill = (cls, label, d, u) => h('div', { 'class': 'krt-live ' + cls }, [
			h('div', { 'class': 'krt-lh' }, [h('i', { 'class': 'krc-sw ' + (cls === 'v' ? 'krc-vpn' : 'krc-dir') }), label]),
			h('div', { 'class': 'krt-lv' }, [h('span', {}, '↓ ' + fmtRate(d)), h('span', {}, '↑ ' + fmtRate(u))])
		]);
		dom.content(this.elLive, [
			h('div', { 'class': 'krt-now' }, 'Şu an'),
			h('div', { 'class': 'krt-lives' }, [pill('v', 'VPN', r.vd, r.vu), pill('d', 'Direkt', r.dd, r.du)]),
			h('div', { 'class': 'krt-totals' }, [
				h('div', { 'class': 'krt-tot' }, [h('div', { 'class': 'kr-sub' }, 'VPN toplam'), h('div', { 'class': 'krt-big' }, fmtBytes(s.total.vr + s.total.vt)),
					h('div', { 'class': 'kr-sub' }, '↓ ' + fmtBytes(s.total.vr) + ' · ↑ ' + fmtBytes(s.total.vt))]),
				h('div', { 'class': 'krt-tot' }, [h('div', { 'class': 'kr-sub' }, 'Direkt toplam'), h('div', { 'class': 'krt-big' }, fmtBytes(s.total.dr + s.total.dt)),
					h('div', { 'class': 'kr-sub' }, '↓ ' + fmtBytes(s.total.dr) + ' · ↑ ' + fmtBytes(s.total.dt))])
			])
		]);

		const rows = [['Bugün', s.today], ['Dün', s.yesterday], ['Bu hafta', s.week], ['Bu ay', s.month], ['Toplam', s.total]];
		const cell = b => [h('td', { 'class': 'td krt-n' }, fmtBytes(b.vr + b.vt)), h('td', { 'class': 'td krt-n kr-hide-sm kr-sub' }, '↓' + fmtBytes(b.vr) + ' ↑' + fmtBytes(b.vt))];
		dom.content(this.elPeriods, h('table', { 'class': 'table kr-table krt-table' }, [
			h('tr', { 'class': 'tr table-titles' }, [
				h('th', { 'class': 'th' }, 'Dönem'),
				h('th', { 'class': 'th krt-n', 'colspan': 2 }, [h('i', { 'class': 'krc-sw krc-vpn' }), 'VPN']),
				h('th', { 'class': 'th krt-n', 'colspan': 2 }, [h('i', { 'class': 'krc-sw krc-dir' }), 'Direkt']),
				h('th', { 'class': 'th krt-n' }, 'Hepsi')
			]),
			...rows.map(([l, b]) => h('tr', { 'class': 'tr' }, [
				h('td', { 'class': 'td' }, h('b', {}, l)), ...cell({ vr: b.vr, vt: b.vt }), ...cell({ vr: b.dr, vt: b.dt }),
				h('td', { 'class': 'td krt-n' }, fmtBytes(b.vr + b.vt + b.dr + b.dt))
			]))
		]));

		this.renderDevTraffic(s.devices || [], s.t, s.others);

		// grafik yalnızca veri ya da genişlik değişince yeniden çizilir (gezinme/ipucu titremesin)
		const sig = JSON.stringify(s.days) + '|' + (this.elChart.clientWidth || 0);
		if (sig !== this.chartSig) {
			this.chartSig = sig;
			this.days = s.days;
			this.elSvg.innerHTML = this.trafficChart(s.days);   // yalnızca sayılardan üretilen SVG
		}
	},

	/* Cihaz bazında trafik: indirme = cihaza gelen, yükleme = cihazdan giden (nft sayaçları, LAN IP'si başına).
	   Canlı hız, iki yoklama arasındaki sayaç farkından hesaplanır. */
	renderDevTraffic(devs, t, others) {
		const prev = this.devPrev || {}, next = {};
		if (!devs.length) {
			dom.content(this.elDevTr, h('div', { 'class': 'kr-sub' }, 'Henüz cihaz verisi yok; sayaçlar başladıktan 1-2 dakika sonra dolar.'));
			this.devPrev = next;
			return;
		}
		let sdd = 0, sdu = 0, srx = 0, stx = 0, mrx = 0, mtx = 0, trx = 0, ttx = 0;
		if (others && others.n) {   // ağdan ayrılmış cihazlar listede yok, ama toplamlara dahil
			srx += others.today.rx; stx += others.today.tx; mrx += others.month.rx; mtx += others.month.tx; trx += others.total.rx; ttx += others.total.tx;
		}
		const rows = devs.map(dv => {
			let dd = 0, du = 0;
			const c = dv.counter, p = prev[dv.ip];
			if (c) {
				if (p && t > p.t) {
					const dt = t - p.t, f = (a, b) => (a >= b ? a - b : a) / dt;
					dd = f(c.rx, p.rx); du = f(c.tx, p.tx);
				}
				next[dv.ip] = { t: t, rx: c.rx, tx: c.tx };
			}
			sdd += dd; sdu += du;
			srx += dv.today.rx; stx += dv.today.tx; mrx += dv.month.rx; mtx += dv.month.tx; trx += dv.total.rx; ttx += dv.total.tx;
			return h('tr', { 'class': 'tr' }, [
				h('td', { 'class': 'td' }, [h('b', {}, dv.name || dv.ip), dv.name ? h('div', { 'class': 'kr-sub' }, dv.ip) : '']),
				h('td', { 'class': 'td krt-n' }, '↓ ' + fmtRate(dd) + '  ↑ ' + fmtRate(du)),
				h('td', { 'class': 'td krt-n', 'title': 'Toplam (kurulumdan beri): ' + fmtBytes(dv.total.rx + dv.total.tx) + ' · Bu ay: ' + fmtBytes(dv.month.rx + dv.month.tx) }, '↓ ' + fmtBytes(dv.today.rx) + '  ↑ ' + fmtBytes(dv.today.tx))
			]);
		});
		this.devPrev = next;
		dom.content(this.elDevTr, [
			h('table', { 'class': 'table kr-table krt-table' }, [
				h('tr', { 'class': 'tr table-titles' }, [
					h('th', { 'class': 'th' }, 'Cihaz'),
					h('th', { 'class': 'th krt-n' }, 'Şu an'),
					h('th', { 'class': 'th krt-n' }, 'Bugün')
				]),
				...rows,
				h('tr', { 'class': 'tr kr-active' }, [
					h('td', { 'class': 'td' }, [h('b', {}, 'Tüm cihazlar (' + devs.length + ')'),
						h('div', { 'class': 'kr-sub' }, 'Bu ay ↓ ' + fmtBytes(mrx) + ' ↑ ' + fmtBytes(mtx) + ' · Toplam ↓ ' + fmtBytes(trx) + ' ↑ ' + fmtBytes(ttx))]),
					h('td', { 'class': 'td krt-n' }, h('b', {}, '↓ ' + fmtRate(sdd) + '  ↑ ' + fmtRate(sdu))),
					h('td', { 'class': 'td krt-n' }, h('b', {}, '↓ ' + fmtBytes(srx) + '  ↑ ' + fmtBytes(stx)))
				])
			]),
			h('div', { 'class': 'kr-sub', 'style': 'margin-top:6px' }, '↓ cihaza gelen (indirme), ↑ cihazdan giden (yükleme). VPN ve direkt trafik birlikte sayılır. Sayaçlar modem yeniden başlasa da saklanır; donanım hızlandırma (NSS) açıksa direkt giden büyük akışlar eksik görünebilir.')
		]);
	},

	trafficHover(ev) {
		const t = ev.target && ev.target.closest ? ev.target.closest('[data-i]') : null;
		if (!t || !this.days) { this.elTip.style.display = 'none'; return; }
		const x = this.days[+t.getAttribute('data-i')];
		if (!x) return;
		const dm = x.day.split('-').reverse().join('.');
		dom.content(this.elTip, [
			h('b', {}, dm),
			h('div', {}, [h('i', { 'class': 'krc-sw krc-vpn' }), 'VPN: ' + fmtBytes(x.vr + x.vt)]),
			h('div', {}, [h('i', { 'class': 'krc-sw krc-dir' }), 'Direkt: ' + fmtBytes(x.dr + x.dt)]),
			h('div', { 'class': 'kr-sub' }, 'Toplam: ' + fmtBytes(x.vr + x.vt + x.dr + x.dt))
		]);
		const box = this.elChart.getBoundingClientRect();
		let px = ev.clientX - box.left + 12;
		this.elTip.style.display = 'block';
		if (px + this.elTip.offsetWidth > box.width) px = ev.clientX - box.left - this.elTip.offsetWidth - 12;
		this.elTip.style.left = Math.max(0, px) + 'px';
		this.elTip.style.top = '4px';
	},

	renderApps(apps) {
		const rows = apps.filter(a => a.enabled).map(a => h('div', { 'class': 'kr-app' }, [
			h('div', {}, [h('b', {}, a.name), h('div', { 'class': 'kr-sub' }, [a.ports ? 'port ' + a.ports : '', a.ips ? ' · ' + a.ips + ' IP bloğu' : '', a.domains ? ' · ' + a.domains + ' alan adı' : ''])]),
			h('div', { 'class': 'kr-seg' }, [
				h('button', { 'title': 'VPN: Bu uygulamanın trafiği VPN tünelinden çıkar. Operatör ne yaptığını görmez, siteler seni VPN sunucusunun IP\'siyle görür. Tünel koparsa bağlantı da kopar.', 'class': a.route === 'vpn' ? 'kr-act' : '', 'click': ui.createHandlerFn(this, () => a.route !== 'vpn' && this.doApp(a.sec, 'vpn')) }, 'VPN'),
				h('button', { 'title': 'Direkt: Tünele girmez, doğrudan hattan çıkar. En düşük ping; VPN yeniden başlasa bile bağlantı kopmaz. Siteler seni operatörün IP\'siyle görür (oyun ve görüntülü görüşme için uygun).', 'class': a.route === 'direct' ? 'kr-act kr-direct' : '', 'click': ui.createHandlerFn(this, () => a.route !== 'direct' && this.doApp(a.sec, 'direct')) }, 'Direkt')
			])
		]));
		this.card(this.elApps, 'apps', 'Uygulamalar — VPN mi, Direkt mi?', [
			...rows,
			h('div', { 'class': 'kr-sub', 'style': 'margin-top:8px' }, 'Direkt: çekirdekte bypass, VPN yeniden başlasa bile bağlantı kopmaz. Yeni uygulama/oyun: Ayarlar → Uygulamalar.')
		]);
	},

	renderNodes(nodes, st) {
		const act = st && st.active ? st.active.sec : null;
		const rows = nodes.map(n => h('tr', { 'class': 'tr' + (n.sec === act ? ' kr-active' : '') }, [
			h('td', { 'class': 'td' }, [h('b', {}, n.name), n.sec === act && st && st.enabled && !st.disconnected ? h('span', { 'class': 'kr-tag' }, 'BAĞLI') : '', n.json ? h('span', { 'class': 'kr-tag' }, 'JSON') : '', n.sub ? h('span', { 'class': 'kr-tag' }, 'abonelik') : '']),
			h('td', { 'class': 'td' }, [n.protocol, n.network, n.tls].filter(x => x && x !== 'none').join(' · ')),
			h('td', { 'class': 'td kr-hide-sm' }, (n.address || '') + ':' + (n.port || '')),
			h('td', { 'class': 'td' }, pingBadge(n.ping, n.rtt, n.warm)),
			h('td', { 'class': 'td', 'style': 'white-space:nowrap' }, [
				btn.call(this, 'Ping', '', () => this.doPing(n.sec)), ' ',
				btn.call(this, 'Düzenle', '', () => this.openEditor(n.sec)), ' ',
				n.sec === act && st && st.enabled && !st.disconnected ? [btn.call(this, 'Bağlantıyı kes', 'cbi-button-negative', () => this.doUse('none'), 'Sunucudan kopar; VPN açık kalır, trafik doğrudan çıkar'), ' '] : '',
				n.sec === act && st && st.enabled && !st.auto && !st.disconnected ? '' : [btn.call(this, 'Bağlan', 'cbi-button-action', () => this.doUse(n.sec)), ' '],
				btn.call(this, '✕', 'cbi-button-negative', () => this.doDelete(n), 'Sil')
			])
		]));
		this.card(this.elNodes, 'nodes', 'Sunucular (' + nodes.length + ')', [
			h('div', { 'class': 'kr-row', 'style': 'margin:0 0 10px' }, [
				btn.call(this, '⚡ Tümünü ölç', 'cbi-button-action', () => this.doPing(null)),
				btn.call(this, '+ Link / JSON ekle', 'cbi-button-positive', () => this.showAdd()),
				btn.call(this, '+ Elle ekle', '', () => this.openEditor(null)),
				btn.call(this, '↻ Aboneliği güncelle', '', () => this.doSub()),
				nodes.some(n => n.insecure) ? btn.call(this, '🔒 Sertifikayı sabitle', '', () => this.doPin(null), 'Sunucunun şu anki sertifikasını sabitler; değiştiyse tüneli yeniden başlatır') : ''
			]),
			nodes.length ? h('table', { 'class': 'table kr-table' }, [
				h('tr', { 'class': 'tr table-titles' }, [
					h('th', { 'class': 'th' }, 'Ad'), h('th', { 'class': 'th' }, 'Tür'), h('th', { 'class': 'th kr-hide-sm' }, 'Adres'),
					h('th', { 'class': 'th', 'title': 'Ping = sunucuya ağ gecikmesi · tünel = açık bağlantıdaki istek (parantez içi: sıfırdan bağlanma)' }, 'Ping'), h('th', { 'class': 'th' }, '')
				]),
				...rows
			]) : h('p', {}, 'Henüz sunucu yok. "Link / JSON ekle" ile ekle ya da Ayarlar\'dan abonelik gir.')
		]);
	},

	renderDevices(devs) {
		const on = devs.filter(d => d.online).length;
		// Yön: dört buton — Varsayılan / VPN / Direkt / Engelle (engelli kırmızı)
		const MODES = [
			['default', 'Varsayılan', '', 'Varsayılan: Bu cihaza özel kural yok, genel ayara uyar.'],
			['vpn', 'VPN', '', 'VPN: Bu cihazın tüm trafiği VPN tünelinden çıkar; siteler VPN sunucusunun IP\'sini görür.'],
			['direct', 'Direkt', 'kr-direct', 'Direkt: Bu cihaz tüneli hiç kullanmaz, doğrudan hattan çıkar (en düşük ping; IP\'si operatörün IP\'si olur).'],
			['block', 'Engelle', 'kr-block', 'Engelle: Bu cihaz internete hiç çıkamaz (ne VPN ne direkt).']
		];
		const mkRow = (d, off) => {
			const cur = d.mode || 'default';
			const seg = h('div', { 'class': 'kr-seg kr-seg-sm' }, MODES.map(([v, label, cls, tip]) =>
				h('button', {
					'class': (cur === v ? 'kr-act ' + cls : (cls === 'kr-block' ? 'kr-blockbtn' : '')),
					'title': tip,
					'click': ui.createHandlerFn(this, () => cur !== v && this.doDevice(d, v))
				}, label)));
			return h('tr', { 'class': 'tr' + (cur === 'block' ? ' kr-blocked' : '') }, [
				h('td', { 'class': 'td' }, [
					h('span', { 'class': 'kr-dot ' + (cur === 'block' ? 'kr-err' : d.online ? 'kr-on' : 'kr-off') }),
					d.name || '(adsız)',
					cur === 'block' ? h('span', { 'class': 'kr-tag kr-tag-red' }, 'ENGELLİ') : ''
				]),
				h('td', { 'class': 'td' }, d.ip || '-'),
				h('td', { 'class': 'td kr-hide-sm' }, d.mac),
				h('td', { 'class': 'td kr-hide-sm krt-n' }, d.online && d.uptime != null ? live(d.uptime) : (d.off_for != null ? 'çevrimdışı ' + Math.max(1, Math.round(d.off_for / 60)) + ' dk' : '—')),
				h('td', { 'class': 'td' }, seg),
				h('td', { 'class': 'td' }, off ? (d.sec ? btn.call(this, 'Kaydı sil', '', () => this.doDevice(d, 'default'), 'Bu çevrimdışı cihazın kayıtlı yönünü sil') : '') : (d.ip ? btn.call(this, 'Bağlantılar', '', () => this.showConns(d.ip), 'Bu cihazın şu an açık olan bağlantılarını listeler: hangi adrese ve porta, VPN\'den mi direkt mi gittiği. Bir uygulamanın hangi adresi/portu kullandığını görüp yön kuralına eklemek için.') : ''))
			]);
		};
		// Çevrimdışı cihazlar (yalnızca kayıtlı yönü olanlar) varsayılan olarak gizli; istenirse açılır
		const offl = devs.filter(d => !d.online);
		const rows = devs.filter(d => d.online).map(d => mkRow(d, false));
		const offRows = this.showOff ? offl.map(d => mkRow(d, true)) : [];
		const offBar = offl.length ? h('div', { 'style': 'margin-top:8px' }, [
			btn.call(this, (this.showOff ? '▾ ' : '▸ ') + 'Çevrimdışı cihazlar (' + offl.length + ')', '',
				() => { this.showOff = !this.showOff; this.renderDevices(devs); },
				'Şu an bağlı olmayan cihazlar (rastgele MAC kullanan telefonlar kayıtlı yönüyle burada birikebilir)')
		]) : '';
		const warn = (this.directDead && !this.autoOff) ? h('div', { 'class': 'kr-warn' }, [
			'Direkt çıkış şu an YOK görünüyor (hat VPN olmadan internete çıkamıyor ya da denetim henüz tamamlanmadı). Bu yüzden "Direkt" seçili cihazlar ve uygulamalar da VPN üzerinden çıkıyor. ',
			btn.call(this, 'Yeniden denetle', '', () => this.doDirectCheck(), 'Direkt çıkışı şimdi ölç')
		]) : '';
		const chk = h('input', { 'type': 'checkbox', 'checked': this.autoOff ? '' : null, 'change': ui.createHandlerFn(this, ev => this.doAutoDirect(ev.target.checked)) });
		const autoRow = h('label', { 'style': 'display:flex;gap:8px;align-items:center;margin:0 0 10px;cursor:pointer' }, [chk, 'Direkt seçilenler her durumda direkt çıksın (hat VPN\'siz çıkamıyorsa o cihaz internetsiz kalabilir)']);
		this.card(this.elDevs, 'devs', 'Cihazlar (' + on + ' bağlı)', h('div', {}, [warn, autoRow, h('table', { 'class': 'table kr-table' }, [
			h('tr', { 'class': 'tr table-titles' }, ['Cihaz', 'IP', 'MAC', 'Bağlı süre', 'Yön', ''].map((x, i) =>
				h('th', { 'class': 'th' + (i === 2 || i === 3 ? ' kr-hide-sm' : '') }, x))),
			...rows, ...offRows
		]), offBar]));
	},

	render(data) {
		const [st, nodes, apps, devs] = data;
		this.nodes = nodes || [];
		this.elStatus = h('div', { 'class': 'kr-card' });
		this.elNode = h('div', { 'class': 'kr-card' });
		this.elApps = h('div', { 'class': 'kr-card' });
		this.elNodes = h('div', { 'class': 'kr-card', 'style': 'margin-bottom:14px' });
		this.elDevs = h('div', { 'class': 'kr-card' });

		this.renderStatus(st);
		this.renderApps(apps || []);
		this.renderNodes(nodes || [], st);
		this.renderDevices(devs || []);
		this.fetchDirect().then(ch => { if (ch) this.renderDevices(devs || []); });

		// canlı süre sayaçları (Açık / Bağlı süre) her saniye ilerler
		// poll ile: sayfadan çıkınca LuCI durdurur, sekme arkadayken boşa çalışmaz
		poll.add(() => tickLive(), 1);
		poll.add(() => runJson(['status', '--json']).then(s => { if (s) this.renderStatus(s); }), 5);
		// cihaz listesi: yeni bağlanan/ayrılan görünsün (değişmediyse tabloya dokunulmaz)
		poll.add(() => Promise.all([runJson(['devices']), this.fetchDirect()]).then(([d]) => {
			if (!d) return;
			const sig = JSON.stringify(d.map(x => [x.mac, x.ip, x.name, x.mode, x.online])) + '|' + this.directDead + this.autoOff;
			if (sig === this.devSig) return;
			this.devSig = sig;
			this.renderDevices(d);
		}), 30);

		setTimeout(() => run(['count', 'status']).then(r => { if ((r.stdout || '').trim() === 'unset') askStats(); }), 1200);

		return h('div', {}, [
			h('style', {}, CSS),
			h('h2', {}, [h('img', { 'src': '/luci-static/kedi-logo.svg', 'style': 'height:1.3em;vertical-align:-0.25em;margin-right:8px;border-radius:6px' }), 'KediRay VPN']),
			krLicBanner(),
			h('div', { 'class': 'kr-grid' }, [this.elStatus, this.elNode, this.elApps]),
			this.elNodes,
			this.elDevs
		]);
	},

	handleSaveApply: null,
	handleSave: null,
	handleReset: null
});
