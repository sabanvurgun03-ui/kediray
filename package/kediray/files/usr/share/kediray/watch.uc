'use strict';
// KediRay bağlantı kaydedicisi: bir cihazın bağlantılarını conntrack'ten izler.
// Hangi bağlantı hangi yoldan (VPN/Direkt) gitti, ne kadar yaşadı, kopunca boşta mıydı?
// Kullanım: ucode watch.uc <saniye> [istemci-ip] [tun-mark] [örnekleme-ms]
const fs = require('fs');
const SECS = int(ARGV[0]) || 180;
const IP = ARGV[1] ?? '';
const TUNMARK = int(ARGV[2]) || 738;
const IV = int(ARGV[3]) || 1000;
const CT = getenv('KR_CT') || '/proc/net/nf_conntrack';
// Test kancası: KR_CT bir dizinse her örnekte <dizin>/<sıra>.txt okunur, beklemeden sanal saat ilerler
const FAKE = fs.stat(CT)?.type == 'directory';
let clock = 0;

function snapshot(i) {
	if (FAKE) return fs.readfile(CT + '/' + i + '.txt') ?? fs.readfile(CT + '/last.txt') ?? '';
	let t = fs.readfile(CT);
	if (t === null) {
		let p = fs.popen('conntrack -L 2>/dev/null');
		if (p) { t = p.read('all'); p.close(); }
	}
	return t ?? '';
}
function now_s() { return FAKE ? clock : time(); }
function tick() { if (FAKE) clock += IV / 1000; else sleep(IV); }
const PRIV = /^(10\.|192\.168\.|127\.|169\.254\.|172\.(1[6-9]|2[0-9]|3[01])\.|22[4-9]\.|23[0-9]\.|255\.)/;

// Bir conntrack satırını çözümle (hem /proc/net/nf_conntrack hem conntrack -L biçimi)
function parse(l) {
	let pr = match(l, /(^| )(tcp|udp) /);
	if (!pr) return null;
	let srcs = match(l, /src=([0-9.]+)/g), dsts = match(l, /dst=([0-9.]+)/g);
	let sp = match(l, /sport=([0-9]+)/), dp = match(l, /dport=([0-9]+)/);
	if (!srcs || !dsts || !sp || !dp) return null;
	let to = match(l, /([0-9]+) +[A-Z_]* *src=/);
	let mk = match(l, /mark=([0-9]+)/);
	let st = match(l, / ([A-Z][A-Z_]+) +src=/);
	return {
		proto: pr[2], src: srcs[0][1], dst: dsts[0][1], sport: int(sp[1]), dport: int(dp[1]),
		// Tünelden mi? TCP: çekirdek 127.0.0.1'e yönlendirir (yanıt tarafının kaynağı 127.0.0.1)
		//              UDP: paket TUN işaretini taşır
		vpn: (length(srcs) > 1 && srcs[1][1] != dsts[0][1]) || (mk && int(mk[1]) == TUNMARK),
		timeout: to ? int(to[1]) : 0,
		state: st ? st[1] : ''
	};
}

let flows = {}, t0 = now_s(), n = 0;
while (now_s() - t0 < SECS) {
	let now = now_s(), seen = {};
	for (let l in split(snapshot(n), '\n')) {
		let c = parse(l);
		if (!c) continue;
		if (length(IP) && c.src != IP) continue;
		if (match(c.dst, PRIV)) continue;
		let k = c.proto + '|' + c.src + ':' + c.sport + '>' + c.dst + ':' + c.dport;
		seen[k] = true;
		let f = flows[k];
		if (!f) {
			flows[k] = f = { proto: c.proto, client: c.src, dst: c.dst, port: c.dport,
				vpn: c.vpn, flip: false, t0: now, t1: now, base: c.timeout, lastTo: c.timeout, idle: 0, state: c.state, open: true };
		}
		// Yol ortada değiştiyse (aynı bağlantı) işaretle
		if (c.vpn != f.vpn) { f.flip = true; f.vpn = c.vpn; }
		if (c.timeout > f.base) f.base = c.timeout;        // sayaç her pakette tazelenir -> tepe = taban
		f.idle = f.base - c.timeout > f.idle ? f.base - c.timeout : f.idle;
		f.lastTo = c.timeout; f.state = c.state; f.t1 = now; f.open = true;
	}
	for (let k, f in flows)
		if (f.open && !seen[k]) { f.open = false; f.end = now_s(); f.endIdle = f.base - f.lastTo; }
	n++;
	tick();
}
let tend = now_s();
for (let k, f in flows) if (f.open) { f.end = null; f.endIdle = f.base - f.lastTo; }

// Aynı sunucu ağına (cihaz + hedef /24) art arda açılan bağlantılarda yol değişmiş mi?
// Oyun ışınlanırken başka bir kanal sunucusuna/portuna bağlanır: biri Direkt biri VPN ise sunucu IP değişti sanıp atar.
let byTarget = {};
for (let k, f in flows) {
	let net = join('.', slice(split(f.dst, '.'), 0, 3)) + '.0/24';
	let key = f.client + ' -> ' + net;
	byTarget[key] ??= [];
	push(byTarget[key], f);
}
let flips = [];
for (let key, l in byTarget) {
	let sl = sort(l, (a, b) => a.t0 - b.t0), prev = null;
	for (let f in sl) {
		if (prev != null && prev.vpn != f.vpn)
			push(flips, { target: key, t: f.t0, from: prev.vpn ? 'VPN' : 'Direkt', to: f.vpn ? 'VPN' : 'Direkt',
				prev_dst: prev.dst, prev_port: prev.port, dst: f.dst, port: f.port });
		prev = f;
	}
	for (let f in sl) if (f.flip)
		push(flips, { target: key, t: f.t0, from: 'aynı bağlantı içinde', to: f.vpn ? 'VPN' : 'Direkt',
			prev_dst: f.dst, prev_port: f.port, dst: f.dst, port: f.port });
}

let out = [];
for (let k, f in flows) push(out, {
	proto: f.proto, client: f.client, dst: f.dst, port: f.port, vpn: f.vpn,
	t0: f.t0, end: f.end, dur: (f.end ?? tend) - f.t0, idle: f.idle, end_idle: f.endIdle,
	// kopma anında boşta değilse: bağlantı kullanılırken kesilmiş (oyundan atılma / zorla kapatma)
	cut_active: f.end != null && f.endIdle < 15 && ((f.end ?? tend) - f.t0) >= 20,
	web: f.port == 80 || f.port == 443, state: f.state, flip: f.flip
});
// Boşta kalma dayanıklılığı: bildirim bağlantısını kim öldürüyor?
// Uzun süre boşta kaldıktan sonra ölen bağlantılar -> araya giren bir şey boştaki bağlantıyı kapatıyor.
function idle_kill(vpn) {
	let min = null, alive = 0;
	for (let f in out) {
		if (f.vpn != vpn || f.web) continue;
		if (f.end != null && f.end_idle >= 30 && f.dur >= 30) { if (min == null || f.end_idle < min) min = f.end_idle; }
		if (f.end == null && f.idle > alive) alive = f.idle;
	}
	return { killed_at: min, survived: alive };
}
// conntrack dolmuşsa kayıtlar düşer -> hem oyun hem bildirim bağlantısı sebepsiz kopar
function ctinfo() {
	let rd = f => { let v = fs.readfile(f); return v ? int(trim(v)) : null; };
	let c = rd('/proc/sys/net/netfilter/nf_conntrack_count'), m = rd('/proc/sys/net/netfilter/nf_conntrack_max');
	return (c == null || !m) ? null : { count: c, max: m, pct: c * 100 / m };
}
print(sprintf('%J\n', {
	t0: t0, t1: tend, secs: tend - t0, samples: n, client: IP, conntrack: ctinfo(),
	idle: { vpn: idle_kill(true), direct: idle_kill(false) },
	flows: sort(out, (a, b) => (a.web - b.web) || (b.dur - a.dur)),
	flips: sort(flips, (a, b) => a.t - b.t)
}));
