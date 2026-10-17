'use strict';
// KediRay link / JSON / abonelik ayrıştırıcı
// ucode link.uc parse <dosya>            -> JSON dizi olarak sunucular
// ucode link.uc apply <dosya> [sub_id]   -> UCI'ye ekler (sub_id verilirse o aboneliğin eskilerini siler)

const fs = require('fs');

function urldec(s) {
	if (s == null) return null;
	return replace(s, /%([0-9A-Fa-f]{2})/g, (m, h) => chr(hex(h)));
}

function b64(s) {
	s = replace(trim('' + s), /[\r\n\t ]/g, '');
	s = replace(s, /-/g, '+');
	s = replace(s, /_/g, '/');
	s = replace(s, /=+$/, '');
	while (length(s) % 4) s += '=';
	return b64dec(s);
}

function qs(q) {
	let o = {};
	if (!q) return o;
	for (let kv in split(q, '&')) {
		if (!length(kv)) continue;
		let i = index(kv, '=');
		if (i < 0) o[urldec(kv)] = '';
		else o[urldec(substr(kv, 0, i))] = urldec(substr(kv, i + 1));
	}
	return o;
}

function purl(link) {
	let m = match(link, /^([a-zA-Z0-9]+):\/\/(.*)$/);
	if (!m) return null;
	let rest = m[2], frag = '', q = '', user = null, i;
	i = index(rest, '#');
	if (i >= 0) { frag = urldec(substr(rest, i + 1)); rest = substr(rest, 0, i); }
	i = index(rest, '?');
	if (i >= 0) { q = substr(rest, i + 1); rest = substr(rest, 0, i); }
	rest = replace(rest, /\/+$/, '');
	i = rindex(rest, '@');
	if (i >= 0) { user = substr(rest, 0, i); rest = substr(rest, i + 1); }
	let host = rest, port = null;
	let hm = match(rest, /^\[([^\]]+)\]:([0-9]+)$/) || match(rest, /^([^:]+):([0-9]+)$/);
	if (hm) { host = hm[1]; port = hm[2]; }
	return { scheme: lc(m[1]), user: user, host: host, port: port, q: qs(q), name: frag };
}

function clean(n) {
	let o = {};
	for (let k, v in n) {
		if (v == null || v === '') continue;
		o[k] = '' + v;
	}
	return o;
}

function transport(n, q) {
	let net = lc(q.type || q.net || 'tcp');
	if (net == 'raw') net = 'tcp';
	if (net == 'websocket') net = 'ws';
	if (net == 'splithttp') net = 'xhttp';
	n.network = net;
	let sec = lc(q.security || '');
	n.tls = (sec == 'tls' || sec == 'xtls') ? 'tls' : (sec == 'reality' ? 'reality' : 'none');
	n.sni = q.sni || q.peer || q.serverName;
	n.host = q.host;
	n.path = q.path;
	if (net == 'grpc') {
		n.service_name = q.serviceName || q.path;
		n.path = null;
		if (q.mode == 'multi') n.grpc_mode = 'multi';
	}
	if (net == 'xhttp') n.xhttp_mode = q.mode;
	if (net == 'tcp' && q.headerType == 'http') n.header_type = 'http';
	n.alpn = q.alpn;
	n.ech = q.ech;   // 3x-ui / Xray: tlsSettings.echConfigList (base64 ECHConfigList ya da [ad+]https://… DNS adresi)
	n.fp = q.fp;
	n.pbk = q.pbk;
	n.sid = q.sid;
	n.spx = q.spx;
	n.flow = q.flow;
	if (q.allowInsecure == '1' || q.allowInsecure == 'true' || q.insecure == '1') n.insecure = '1';
	return n;
}

function p_vless(u) {
	let n = { protocol: 'vless', address: u.host, port: u.port, uuid: urldec(u.user), encryption: u.q.encryption };
	transport(n, u.q);
	n.remarks = u.name;
	return n;
}

function p_trojan(u) {
	let n = { protocol: 'trojan', address: u.host, port: u.port, password: urldec(u.user) };
	transport(n, u.q);
	if (!u.q.security) n.tls = 'tls';
	n.remarks = u.name;
	return n;
}

function p_vmess_obj(j) {
	let n = {
		protocol: 'vmess', address: j.add, port: j.port, uuid: j.id, cipher: j.scy,
		remarks: j.ps
	};
	transport(n, {
		type: j.net, security: j.tls, sni: j.sni, host: j.host, path: j.path,
		alpn: j.alpn, ech: j.ech, fp: j.fp, headerType: j.type, serviceName: (j.net == 'grpc' ? j.path : null),
		mode: (j.net == 'grpc' && j.type == 'multi') ? 'multi' : j.mode, allowInsecure: j.allowInsecure
	});
	return n;
}

function p_vmess(link) {
	let body = substr(link, 8);
	let i = index(body, '#');
	if (i >= 0) body = substr(body, 0, i);
	let j = null;
	try { j = json(b64(body)); } catch (e) { j = null; }
	if (type(j) == 'object') return p_vmess_obj(j);
	// vmess://uuid@host:port?... biçimi
	let u = purl(link);
	if (!u) return null;
	let n = { protocol: 'vmess', address: u.host, port: u.port, uuid: urldec(u.user), cipher: u.q.encryption };
	transport(n, u.q);
	n.remarks = u.name;
	return n;
}

function p_ss(link) {
	let u = purl(link);
	if (!u) return null;
	let method, password, host = u.host, port = u.port;
	if (u.user != null) {
		let ui = urldec(u.user);
		if (index(ui, ':') < 0) ui = b64(ui);
		let i = index(ui, ':');
		method = substr(ui, 0, i); password = substr(ui, i + 1);
	} else {
		// eski biçim: ss://BASE64(method:pass@host:port)
		let d = b64(host);
		let m = match(d, /^([^:]+):(.*)@([^@]+):([0-9]+)$/);
		if (!m) return null;
		method = m[1]; password = m[2]; host = m[3]; port = m[4];
	}
	if (u.q.plugin) return null; // eklenti gerektiren SS desteklenmiyor
	return { protocol: 'shadowsocks', address: host, port: port, method: method, password: password, network: 'tcp', tls: 'none', remarks: u.name };
}

// ---- JSON (Xray outbound / tam config / vmess json) ----
const PROXY = { vless: 1, vmess: 1, trojan: 1, shadowsocks: 1 };

function from_outbound(o, idx) {
	if (type(o) != 'object' || !PROXY[o.protocol]) return null;
	let s = o.settings || {};
	let t = s.vnext?.[0] || s.servers?.[0] || s;
	if (!t.address || !t.port) return null;
	let copy = { ...o };
	delete copy.tag;
	return {
		protocol: o.protocol, address: t.address, port: t.port,
		network: o.streamSettings?.network,
		tls: o.streamSettings?.security,
		remarks: (o.tag && !match(o.tag, /^(proxy|outbound|out|node)$/)) ? o.tag : (o.protocol + ' ' + t.address + (idx ? ' #' + idx : '')),
		raw: sprintf('%J', copy)
	};
}

function from_json(j) {
	let out = [];
	if (type(j) == 'array') {
		for (let i = 0; i < length(j); i++) {
			let x = j[i];
			if (type(x) == 'object' && x.outbounds) push(out, ...from_json(x));
			else { let n = from_outbound(x, i + 1); if (n) push(out, n); }
		}
	}
	else if (type(j) == 'object') {
		if (type(j.outbounds) == 'array') {
			let k = 0;
			for (let o in j.outbounds) { let n = from_outbound(o, ++k); if (n) push(out, n); }
			// v2rayNG tam config: tag genelde 'proxy' -> config 'remarks' alanını kullan
			if (length(out) == 1 && j.remarks) out[0].remarks = j.remarks;
		}
		else if (j.protocol) { let n = from_outbound(j); if (n) push(out, n); }
		else if (j.add && j.id) push(out, p_vmess_obj(j));
	}
	return out;
}

function parse_text(txt) {
	txt = trim(txt || '');
	if (!length(txt)) return [];
	// JSON mu?
	if (substr(txt, 0, 1) == '{' || substr(txt, 0, 1) == '[') {
		let j = null;
		try { j = json(txt); } catch (e) { j = null; }
		if (j != null) return from_json(j);
	}
	// base64 abonelik mi?
	if (index(txt, '://') < 0) {
		let d = b64(txt);
		if (d && index(d, '://') >= 0) txt = d;
		else if (d && (substr(trim(d), 0, 1) == '{' || substr(trim(d), 0, 1) == '[')) return parse_text(d);
	}
	let out = [];
	for (let line in split(txt, /[\r\n]+/)) {
		line = trim(line);
		let n = null;
		if (match(line, /^vless:\/\//i)) n = p_vless(purl(line));
		else if (match(line, /^vmess:\/\//i)) n = p_vmess(line);
		else if (match(line, /^trojan:\/\//i)) n = p_trojan(purl(line));
		else if (match(line, /^ss:\/\//i)) n = p_ss(line);
		if (n && n.address && n.port) push(out, n);
	}
	return out;
}

const CMD = ARGV[0] || 'parse';
const FILE = ARGV[1];
const text = FILE && FILE != '-' ? fs.readfile(FILE) : fs.stdin.read('all');
let nodes = map(parse_text(text), clean);

if (CMD == 'parse') {
	print(sprintf('%.J\n', nodes));
	exit(0);
}

if (CMD == 'apply') {
	const SUB = ARGV[2];
	const uci = require('uci').cursor();
	let selname = uci.get('kediray', 'main', 'node');
	let selrem = null;
	if (SUB) {
		// Bu aboneliğin eski sunucularını sil (seçili olanın adını hatırla)
		let del = [];
		uci.foreach('kediray', 'node', s => {
			if (s.sub == SUB) {
				if (s['.name'] == selname) selrem = s.remarks;
				push(del, s['.name']);
			}
		});
		if (!length(nodes)) { warn('kediray: abonelik boş geldi, eski sunucular korunuyor\n'); exit(3); }
		for (let d in del) uci.delete('kediray', d);
	}
	let added = 0, newsel = null;
	for (let n in nodes) {
		let s = uci.add('kediray', 'node');
		for (let k, v in n) uci.set('kediray', s, k, v);
		if (SUB) uci.set('kediray', s, 'sub', SUB);
		if (selrem && n.remarks == selrem && !newsel) newsel = s;
		added++;
	}
	if (selrem) uci.set('kediray', 'main', 'node', newsel || 'auto');
	uci.save('kediray');
	uci.commit('kediray');
	print(added, '\n');
	exit(added ? 0 : 3);
}
