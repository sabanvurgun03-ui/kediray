'use strict';
// KediRay sunucu düzenleme ve yapılandırma denetimi
//   ucode node.uc check-json '<metin>'                 -> JSON yazım denetimi (satır/sütun, Türkçe)
//   ucode node.uc get <bölüm>                           -> düzenleme ekranı için alanlar
//   ucode node.uc save <bölüm|new> form '<alanlar>'     -> denetlemeden kaydet (alan/Xray testi yok; elle denetle: validate)
//   ucode node.uc save <bölüm|new> json '<outbound>' [ad]
//   ucode node.uc del <bölüm>
//   ucode node.uc validate                              -> tüm yapılandırmayı denetle
// Ortam: KR_SHARE, KR_XRAY, KR_ASSET, KR_RUN (kediray betiği verir)

const fs = require('fs');
const CMD = ARGV[0];
const SHARE = getenv('KR_SHARE') || '/usr/share/kediray';
const RUN = getenv('KR_RUN') || '/var/etc/kediray';
const PROTOS = { vless: 1, vmess: 1, trojan: 1, shadowsocks: 1 };

function out(x) { print(sprintf('%J\n', x)); }
function q(s) { return "'" + replace('' + s, /'/g, "'\\''") + "'"; }
function sh(cmd) { let p = fs.popen(cmd); let o = p.read('all') ?? ''; let rc = p.close(); return { out: o, rc: rc }; }
function cur() { return require('uci').cursor(); }

// ---------- katı JSON denetleyici: ilk hatanın satır/sütunu ve Türkçe açıklaması ----------
function json_check(s) {
	let i = 0, n = length(s), err = null;
	let ch = () => (i < n ? substr(s, i, 1) : '');
	let fail = (msg) => { if (!err) err = { pos: i, msg: msg }; return false; };
	let ws = () => { while (i < n && index(' \t\r\n', ch()) >= 0) i++; };
	let value, str, num, obj, arr;
	str = () => {
		i++;
		while (i < n) {
			let c = ch();
			if (c == '"') { i++; return true; }
			if (c == '\\') { i += 2; continue; }
			if (c == '\n') return fail('Metin bitmeden satır sonu geldi (kapanış tırnağı " eksik)');
			i++;
		}
		return fail('Kapanış tırnağı " eksik');
	};
	num = () => {
		let m = match(substr(s, i, 64), /^-?(0|[1-9][0-9]*)(\.[0-9]+)?([eE][+-]?[0-9]+)?/);
		if (!m) return fail('Geçersiz sayı');
		i += length(m[0]);
		return true;
	};
	obj = () => {
		i++; ws();
		if (ch() == '}') { i++; return true; }
		while (true) {
			ws();
			let c = ch();
			if (c == '}') return fail("Son öğeden sonra fazladan virgül var (',' sil)");
			if (c == "'") return fail('Anahtarlar tek tırnakla değil çift tırnakla (") yazılmalı');
			if (c != '"') return fail(i >= n ? "'}' kapanmamış (metin erken bitti)" : 'Anahtar çift tırnak (") içinde olmalı');
			if (!str()) return false;
			ws();
			if (ch() != ':') return fail("Anahtardan sonra ':' bekleniyordu");
			i++;
			if (!value()) return false;
			ws();
			c = ch();
			if (c == ',') { i++; continue; }
			if (c == '}') { i++; return true; }
			if (i >= n) return fail("'}' kapanmamış (metin erken bitti)");
			return fail("',' veya '}' bekleniyordu (önceki satırın sonunda virgül eksik olabilir)");
		}
	};
	arr = () => {
		i++; ws();
		if (ch() == ']') { i++; return true; }
		while (true) {
			ws();
			if (ch() == ']') return fail("Son öğeden sonra fazladan virgül var (',' sil)");
			if (!value()) return false;
			ws();
			let c = ch();
			if (c == ',') { i++; continue; }
			if (c == ']') { i++; return true; }
			if (i >= n) return fail("']' kapanmamış (metin erken bitti)");
			return fail("',' veya ']' bekleniyordu");
		}
	};
	value = () => {
		ws();
		let c = ch();
		if (c == '{') return obj();
		if (c == '[') return arr();
		if (c == '"') return str();
		if (c == '-' || (c >= '0' && c <= '9')) return num();
		if (substr(s, i, 4) == 'true' || substr(s, i, 4) == 'null') { i += 4; return true; }
		if (substr(s, i, 5) == 'false') { i += 5; return true; }
		if (c == "'") return fail('Metinler tek tırnakla değil çift tırnakla (") yazılmalı');
		if (i >= n) return fail('Beklenmedik son: değer bekleniyordu');
		return fail("Geçersiz değer '" + c + "' (metinler çift tırnak içinde olmalı)");
	};
	if (value()) { ws(); if (i < n) fail('JSON bittikten sonra fazladan içerik var'); }
	if (!err) return null;
	let line = 1, col = 1;
	for (let k = 0; k < err.pos && k < n; k++) {
		if (substr(s, k, 1) == '\n') { line++; col = 1; } else col++;
	}
	return { line: line, col: col, msg: err.msg };
}

// Xray'in İngilizce hata zincirinden en anlamlı kısmı çıkar
function xray_errors(log) {
	let res = [];
	for (let l in split(log, '\n')) {
		if (!match(l, /(Failed|failed|invalid|error|Error|unknown|not supported|removed)/)) continue;
		if (match(l, /\[Warning\]/)) continue;
		let parts = split(l, ' > ');
		push(res, { msg: trim(parts[length(parts) - 1]), detail: trim(l) });
	}
	return length(res) ? res : [{ msg: 'Xray yapılandırmayı kabul etmedi', detail: trim(log) }];
}

function xray_test(cfg) {
	let xb = getenv('KR_XRAY') || SHARE + '/bin/xray';
	if (!fs.access(xb, 'x')) return null;   // çekirdek yoksa bu aşama atlanır
	let f = RUN + '/cand.' + time() + '.json';
	fs.mkdir(RUN);
	fs.writefile(f, sprintf('%J', cfg));
	let r = sh('XRAY_LOCATION_ASSET=' + q(getenv('KR_ASSET') || SHARE) + ' ' + q(xb) + ' run -test -c ' + q(f) + ' 2>&1');
	fs.unlink(f);
	return r.rc == 0 ? [] : xray_errors(r.out);
}

const FORM_FIELDS = ['remarks', 'protocol', 'address', 'port', 'uuid', 'password', 'method', 'flow', 'encryption', 'cipher',
	'network', 'path', 'host', 'service_name', 'grpc_mode', 'xhttp_mode', 'header_type',
	'tls', 'sni', 'fp', 'alpn', 'insecure', 'pin', 'pbk', 'sid', 'spx', 'enabled'];

function write_node(sec, kind, payload) {
	let u = cur();
	if (sec == 'new' || !sec) sec = u.add('kediray', 'node');
	else if (u.get('kediray', sec) != 'node') return null;
	let keep = { remarks: u.get('kediray', sec, 'remarks'), sub: u.get('kediray', sec, 'sub'), enabled: u.get('kediray', sec, 'enabled') };
	for (let k in [...FORM_FIELDS, 'raw']) u.delete('kediray', sec, k);
	if (kind == 'json') {
		let ob = payload.outbound, st = ob.settings || {}, t = st.vnext?.[0] || st.servers?.[0] || st;
		u.set('kediray', sec, 'raw', sprintf('%J', ob));
		u.set('kediray', sec, 'protocol', '' + ob.protocol);
		u.set('kediray', sec, 'address', '' + t.address);
		u.set('kediray', sec, 'port', '' + t.port);
		if (ob.streamSettings?.network) u.set('kediray', sec, 'network', '' + ob.streamSettings.network);
		if (ob.streamSettings?.security) u.set('kediray', sec, 'tls', '' + ob.streamSettings.security);
		let rm = payload.remarks || keep.remarks;
		if (rm) u.set('kediray', sec, 'remarks', '' + rm);
	} else {
		for (let k, v in payload) {
			if (index(FORM_FIELDS, k) < 0 || v == null || v === '') continue;
			u.set('kediray', sec, k, '' + v);
		}
	}
	if (keep.sub) u.set('kediray', sec, 'sub', keep.sub);
	if (keep.enabled != null && payload.enabled == null) u.set('kediray', sec, 'enabled', keep.enabled);
	u.save('kediray');
	u.commit('kediray');
	return sec;
}

// ================= komutlar =================
if (CMD == 'check-json') {
	let e = json_check(ARGV[1] ?? '');
	out(e ? { ok: false, errors: [e] } : { ok: true });
	exit(e ? 3 : 0);
}

if (CMD == 'get') {
	let s = cur().get_all('kediray', ARGV[1]);
	if (!s || s['.type'] != 'node') { out({ ok: false, errors: [{ msg: 'böyle bir sunucu yok' }] }); exit(1); }
	let f = {};
	for (let k in FORM_FIELDS) if (s[k] != null) f[k] = s[k];
	let pretty = null, gen = null;
	if (s.raw) { try { pretty = sprintf('%.J', json(s.raw)); } catch (e) { pretty = s.raw; } }
	// Form sunucusu için Xray'in kullanacağı outbound'u da göster (JSON sekmesinde düzenlenebilsin)
	let g = sh('ucode ' + q(SHARE + '/gen.uc') + ' outbound ' + q(s['.name']) + ' 2>/dev/null');
	try { gen = json(g.out); } catch (e) { gen = null; }
	if (!pretty && gen?.outbound) {
		let o = { ...gen.outbound };
		delete o.tag;
		pretty = sprintf('%.J', o);
	}
	out({ ok: true, sec: s['.name'], mode: s.raw ? 'json' : 'form', fields: f, json: pretty, sub: s.sub ?? null, errors: gen?.errors ?? [] });
	exit(0);
}

if (CMD == 'save') {
	let sec = ARGV[1], kind = ARGV[2], text = ARGV[3] ?? '', rname = ARGV[4] ?? '';
	let res = { ok: false, stage: null, errors: [] };
	let fail = (stage, errs) => { res.stage = stage; res.errors = errs; out(res); exit(3); };
	let payload;

	// Alan denetimi ve Xray testi yapılmaz: sunucu olduğu gibi kaydedilir; denetimi kullanıcı elle yapar
	// (Kontrol Paneli → "✓ Ayarları denetle" / kediray validate). Yalnızca metnin okunabilmesi için JSON ayrıştırılır.
	let e = json_check(text);
	if (e) fail('syntax', [e]);
	let data = json(text);

	if (kind == 'json') {
		let ob = data;
		if (type(data) == 'object' && type(data.outbounds) == 'array') {
			ob = null;
			for (let o in data.outbounds) if (type(o) == 'object' && PROTOS[o.protocol]) { ob = o; break; }
			if (!rname && data.remarks) rname = data.remarks;
		}
		if (type(ob) != 'object') fail('fields', [{ msg: 'JSON bir Xray outbound nesnesi olmalı ({ "protocol": ..., "settings": ... })' }]);
		ob = { ...ob };
		delete ob.tag;
		payload = { outbound: ob, remarks: rname };
	} else {
		if (type(data) != 'object') fail('fields', [{ msg: 'form verisi okunamadı' }]);
		payload = {};
		for (let k, v in data) if (index(FORM_FIELDS, k) >= 0 && v != null && v !== '') payload[k] = '' + v;
	}

	let saved = write_node(sec, kind, payload);
	if (!saved) fail('save', [{ msg: 'böyle bir sunucu yok' }]);
	res.ok = true; res.sec = saved;
	out(res);
	exit(0);
}

if (CMD == 'del') {
	let u = cur(), sec = ARGV[1];
	if (u.get('kediray', sec) != 'node') { out({ ok: false, errors: [{ msg: 'böyle bir sunucu yok' }] }); exit(1); }
	u.delete('kediray', sec);
	if (u.get('kediray', 'main', 'node') == sec) u.set('kediray', 'main', 'node', 'auto');
	u.save('kediray');
	u.commit('kediray');
	out({ ok: true });
	exit(0);
}

if (CMD == 'validate') {
	let res = { ok: true, errors: [] };
	let add = (stage, e) => { res.ok = false; push(res.errors, { stage: stage, ...e }); };
	// a) UCI dosyası okunabiliyor mu (tırnak/yazım hatası)
	if (!getenv('KR_CFG')) {
		let u = sh('uci -q show kediray 2>&1 >/dev/null');
		if (u.rc != 0) {
			let m = match(u.out, /line ([0-9]+)/);
			add('uci', { line: m ? int(m[1]) : null, msg: '/etc/config/kediray okunamadı: ' + trim(u.out) });
			out(res); exit(3);
		}
	}
	// b) sunucu alanları
	let c = sh('ucode ' + q(SHARE + '/gen.uc') + ' check 2>/dev/null'), chk = null;
	try { chk = json(c.out); } catch (x) { chk = null; }
	for (let e in (chk?.errors ?? [])) {
		// Bozuk JSON sunucusunda hatanın yerini de göster
		if (e.field == 'raw' && e.node) {
			let rawtxt = null;
			if (getenv('KR_CFG')) { let d = json(fs.readfile(getenv('KR_CFG'))); rawtxt = d?.[e.node]?.raw; }
			else rawtxt = cur().get('kediray', e.node, 'raw');
			let je = rawtxt ? json_check(rawtxt) : null;
			if (je) { e.line = je.line; e.col = je.col; e.msg = e.msg + ' — ' + je.msg; }
		}
		add('node', e);
	}
	if (chk && chk.nodes == 0) add('node', { msg: 'hiç geçerli sunucu yok' });
	// c) tam yapılandırma + Xray testi
	fs.mkdir(RUN);
	let x = sh('ucode ' + q(SHARE + '/gen.uc') + ' xray 2>' + q(RUN + '/gen.err')), cfg = null;
	try { cfg = json(x.out); } catch (e2) { cfg = null; }
	if (!cfg) { if (chk?.nodes) add('gen', { msg: trim(fs.readfile(RUN + '/gen.err') ?? '') || 'yapılandırma üretilemedi' }); }
	else {
		let xe = xray_test(cfg);
		for (let e in (xe ?? [])) add('xray', e);
	}
	out(res);
	exit(res.ok ? 0 : 3);
}

warn('kullanım: node.uc check-json|get|save|del|validate\n');
exit(1);
