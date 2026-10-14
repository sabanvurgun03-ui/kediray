'use strict';
// KediRay trafik sayacı: VPN (tünelin dış baytları, nft sayacı) ve Direkt (WAN toplamı − VPN) günlük kovalarda.
// 1.19.6: ek olarak cihaz bazlı (LAN IP'si başına) indirme/yükleme günlük kovaları.
//   ucode traffic.uc sample    (KR_VR KR_VT KR_WR KR_WT KR_DEVF ortamdan)   -> farkı bugünün kovasına ekler
//   ucode traffic.uc report    (aynı ortam)                          -> şu anki sayaçlar + bugün/hafta/ay/30 gün + cihazlar
//   ucode traffic.uc save | restore | reset
const fs = require('fs');
const RUN = getenv('KR_RUN') || '/var/etc/kediray';
const RAMF = RUN + '/traffic.json';
const FLASHF = getenv('KR_TRAFFIC_FLASH') || '/etc/kediray.traffic.json';
const CMD = ARGV[0];

function readj(p) { try { let t = fs.readfile(p); return t ? json(t) : null; } catch (e) { return null; } }
function writej(p, v) { fs.writefile(p + '.tmp', sprintf('%J', v)); fs.rename(p + '.tmp', p); }
function n(v) { let x = int(v ?? 0); return x != x ? 0 : x; }
function dkey(ts) { let t = localtime(ts); return sprintf('%04d-%02d-%02d', t.year, t.mon, t.mday); }
function cur() { return { vr: n(getenv('KR_VR')), vt: n(getenv('KR_VT')), wr: n(getenv('KR_WR')), wt: n(getenv('KR_WT')), t: time() }; }
function load() {
	let s = readj(RAMF) ?? readj(FLASHF) ?? {};
	s.days ??= {};
	s.dev ??= {};
	return s;
}
// sayaç sıfırlanmışsa (tablo yeniden kuruldu / modem yeniden başladı) fark = şimdiki değer
function d(c, l) { return c >= l ? c - l : c; }

function delta(s, c) {
	let l = s.last;
	if (!l) return null;
	let vr = d(c.vr, l.vr), vt = d(c.vt, l.vt), wr = d(c.wr, l.wr), wt = d(c.wt, l.wt);
	// WAN sayacı VPN'den küçük kalamaz; kalırsa (farklı anlarda okuma) direkt 0 sayılır
	return { vr: vr, vt: vt, dr: wr > vr ? wr - vr : 0, dt: wt > vt ? wt - vt : 0 };
}
function add(b, x) { b.vr = n(b.vr) + x.vr; b.vt = n(b.vt) + x.vt; b.dr = n(b.dr) + x.dr; b.dt = n(b.dt) + x.dt; }

// ---------- cihaz bazlı sayaçlar ----------
// KR_DEVF satırları: "ip<TAB>rx|tx<TAB>bayt"  (rx = cihaza gelen, tx = cihazdan giden)
function readdev() {
	let r = {}, f = getenv('KR_DEVF');
	if (!f) return r;
	for (let l in split(fs.readfile(f) ?? '', '\n')) {
		let p = split(l, '\t');
		if (length(p) < 3 || !match(p[0], /^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$/)) continue;
		if (p[1] != 'rx' && p[1] != 'tx') continue;
		r[p[0]] ??= { rx: 0, tx: 0 };
		r[p[0]][p[1]] = n(p[2]);
	}
	return r;
}
function leases() { // ip -> { mac, name }
	let r = {};
	for (let l in split(fs.readfile('/tmp/dhcp.leases') ?? '', '\n')) {
		let f = split(l, ' ');
		if (length(f) >= 4) r[f[2]] = { mac: lc(f[1]), name: f[3] != '*' ? f[3] : '' };
	}
	return r;
}
function devlive(e, c) { // son örneklemeden bu yana (henüz kovaya yazılmamış) fark
	if (!c) return { rx: 0, tx: 0 };
	let l = e.last ?? { rx: 0, tx: 0 };
	return { rx: d(n(c.rx), n(l.rx)), tx: d(n(c.tx), n(l.tx)) };
}
function devsample(s, c) {
	let cd = readdev(), ls = leases(), day = dkey(c.t);
	for (let ip, v in cd) {
		s.dev[ip] ??= { days: {} };
		let e = s.dev[ip];
		let x = devlive(e, v);
		e.days ??= {};
		e.days[day] ??= { rx: 0, tx: 0 };
		e.days[day].rx = n(e.days[day].rx) + x.rx;
		e.days[day].tx = n(e.days[day].tx) + x.tx;
		e.last = { rx: n(v.rx), tx: n(v.tx) };
		if (ls[ip]) { e.mac = ls[ip].mac; if (ls[ip].name) e.name = ls[ip].name; }
		e.seen = c.t;
	}
	// 100 günden eski günleri ve boş kalan cihazları at
	let cut = dkey(c.t - 100 * 86400);
	for (let ip in keys(s.dev)) {
		let e = s.dev[ip];
		for (let k in keys(e.days ?? {})) if (k < cut) delete e.days[k];
		if (!length(keys(e.days ?? {})) && !cd[ip]) delete s.dev[ip];
	}
}

if (CMD == 'sample') {
	let s = load(), c = cur(), x = delta(s, c);
	if (x) { s.days[dkey(c.t)] ??= {}; add(s.days[dkey(c.t)], x); }
	s.last = c;
	devsample(s, c);
	// 100 günden eskiyi at
	let ks = sort(keys(s.days));
	while (length(ks) > 100) delete s.days[shift(ks)];
	fs.mkdir(RUN);
	writej(RAMF, s);
	if (ARGV[1] == 'save' || time() - n(s.saved) >= 3600) { s.saved = time(); writej(RAMF, s); writej(FLASHF, s); }
	print('ok\n');
	exit(0);
}
if (CMD == 'save') { let s = load(); s.saved = time(); fs.mkdir(RUN); writej(RAMF, s); writej(FLASHF, s); print('ok\n'); exit(0); }
if (CMD == 'restore') {
	if (!readj(RAMF) && readj(FLASHF)) {
		fs.mkdir(RUN);
		let s = readj(FLASHF);
		delete s.last;
		for (let ip, e in (s.dev ?? {})) delete e.last;   // modem açıldı: nft sayaçları sıfırdan başlar
		writej(RAMF, s);
	}
	print('ok\n');
	exit(0);
}
if (CMD == 'reset') { fs.unlink(RAMF); fs.unlink(FLASHF); print('ok\n'); exit(0); }

if (CMD == 'report') {
	let s = load(), c = cur(), live = delta(s, c) ?? { vr: 0, vt: 0, dr: 0, dt: 0 };
	let today = dkey(c.t);
	let day = k => ({ vr: n(s.days[k]?.vr), vt: n(s.days[k]?.vt), dr: n(s.days[k]?.dr), dt: n(s.days[k]?.dt) });
	let sum = (from) => {
		let t = { vr: 0, vt: 0, dr: 0, dt: 0 };
		for (let k, v in s.days) if (k >= from && k <= today) add(t, day(k));
		add(t, live);   // son örneklemeden bu yana (henüz kovaya yazılmamış) kısım
		return t;
	};
	let lt = localtime(c.t);
	// haftanın başı Pazartesi
	let wd = lt.wday == 0 ? 6 : lt.wday - 1;
	let week = dkey(c.t - wd * 86400);
	let month = sprintf('%04d-%02d-01', lt.year, lt.mon);
	let yest = dkey(c.t - 86400);
	let t_today = day(today); add(t_today, live);
	let hist = [];
	for (let i = 29; i >= 0; i--) {
		let k = dkey(c.t - i * 86400), v = day(k);
		if (k == today) add(v, live);
		push(hist, { day: k, ...v });
	}
	let first = sort(keys(s.days))[0];

	// cihazlar: bugün / hafta / ay / toplam (rx = indirme, tx = yükleme) + canlı hız için ham sayaç
	let cd = readdev(), devs = [];
	// Bağlı mı? Wi-Fi: "iw station dump" listesi (anında). Kablolu/bilinmeyen: `kediray devices` yoklamasının
	// bıraktığı presence.json (cli.uc) 150 sn içinde doğrulandıysa. İkisi de yoksa canlı trafik kanıt sayılır.
	let rd = (cmd) => { let p = fs.popen(cmd + ' 2>/dev/null'); if (!p) return ''; let o = p.read('all') ?? ''; p.close(); return o; };
	let assoc = {}, haveAssoc = false, pres = {}, arpmac = {};
	for (let l in split(rd('for i in $(iw dev | awk \'$1=="Interface"{print $2}\'); do echo "IF $i"; iw dev "$i" station dump | awk \'/^Station/{print $2}\'; done'), '\n')) {
		if (match(l, /^IF /)) { haveAssoc = true; continue; }
		if (match(l, /^[0-9a-fA-F]{2}(:[0-9a-fA-F]{2}){5}$/)) assoc[lc(l)] = true;
	}
	pres = readj(RUN + '/presence.json') ?? {};
	let leaseip = {};
	for (let lip, lv in leases()) leaseip[lv.mac] = lip;
	for (let l in split(fs.readfile('/proc/net/arp') ?? '', '\n')) {
		let f = filter(split(l, ' '), x => length(x));
		if (length(f) >= 6 && match(f[0], /^[0-9.]+$/) && f[3] != '00:00:00:00:00:00') arpmac[f[0]] = lc(f[3]);
	}
	let online = (ip, e, lv) => {
		let mac = lc(e.mac || arpmac[ip] || '');
		if (!length(mac)) return lv.rx + lv.tx > 0;
		// aynı cihazın eski IP'si (yeni kira aldıysa) bağlı sayılmaz: yalnız şu anki IP'si listede kalır
		if (leaseip[mac] != null ? leaseip[mac] != ip : (arpmac[ip] != null && arpmac[ip] != mac)) return false;
		if (assoc[mac]) return true;
		let p = pres[mac];
		if (p?.wifi && haveAssoc) return false;        // Wi-Fi'daydı, şimdi bağlı listesinde yok: ayrıldı
		if (p) return c.t - n(p.last) < 150;
		return lv.rx + lv.tx > 0;
	};
	let others = { n: 0, today: { rx: 0, tx: 0 }, month: { rx: 0, tx: 0 }, total: { rx: 0, tx: 0 } };
	let add2 = (t, v) => { t.rx += v.rx; t.tx += v.tx; };
	for (let ip, e in s.dev) {
		let lv = devlive(e, cd[ip]);
		let dsum = (from) => {
			let t = { rx: 0, tx: 0 };
			for (let k, v in (e.days ?? {})) if (k >= from && k <= today) { t.rx += n(v.rx); t.tx += n(v.tx); }
			t.rx += lv.rx; t.tx += lv.tx;
			return t;
		};
		let tot = dsum('0000-00-00');
		if (tot.rx + tot.tx <= 0) continue;
		// Ağdan ayrılan cihaz listeden kalkar; verisi saklanır, geri bağlanınca geri gelir (toplamlar eksilmez)
		if (!online(ip, e, lv)) {
			others.n += 1;
			add2(others.today, dsum(today)); add2(others.month, dsum(month)); add2(others.total, tot);
			continue;
		}
		push(devs, { ip: ip, name: e.name ?? '', mac: e.mac ?? '', counter: cd[ip] ?? null,
			today: dsum(today), week: dsum(week), month: dsum(month), total: tot });
	}
	devs = sort(devs, (a, b) => ((b.today.rx + b.today.tx) - (a.today.rx + a.today.tx)) || ((b.total.rx + b.total.tx) - (a.total.rx + a.total.tx)));
	if (length(devs) > 40) devs = slice(devs, 0, 40);

	print(sprintf('%J\n', {
		t: c.t, counters: c, today: t_today, yesterday: day(yest), week: sum(week), month: sum(month),
		total: sum('0000-00-00'), since: first, days: hist, devices: devs, others: others
	}));
	exit(0);
}
warn('kullanım: traffic.uc sample [save] | report | save | restore | reset\n');
exit(1);
