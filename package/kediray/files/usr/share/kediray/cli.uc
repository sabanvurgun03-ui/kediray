'use strict';
// KediRay CLI yardımcıları (JSON çıktılar panel için)
const fs = require('fs');
const CMD = ARGV[0];
const RUN = getenv('KR_RUN') || '/var/etc/kediray';

function cursor() {
	const f = getenv('KR_CFG');   // test için JSON fikstürü
	if (!f) return require('uci').cursor();
	let d = json(fs.readfile(f));
	if (d.values) d = d.values;
	const secs = sort(values(d), (a, b) => (a['.index'] ?? 0) - (b['.index'] ?? 0));
	return {
		get_all: (c, s) => s ? d[s] : d,
		foreach: (c, t, cb) => { for (let s in secs) if (s['.type'] == t) cb(s); }
	};
}
function readlines(p) {
	let t = fs.readfile(p);
	return t ? filter(split(t, '\n'), l => length(l)) : [];
}
function nodes_tsv() {
	let out = [];
	for (let l in readlines(RUN + '/nodes.tsv')) {
		let f = split(l, '\t');
		push(out, { tag: f[0], sec: f[1], tport: int(f[2]), address: f[3], port: int(f[4]), protocol: f[5],
			network: f[6], insecure: f[7] == '1', sni: f[8], pinned: f[9] != '-', name: f[10] });
	}
	return out;
}
// address -> IP eşlemesi ($RUN/resolve: "alan.adi=1.2.3.4 alan2=5.6.7.8")
function resolved(addr) {
	if (!addr || match(addr, /^[0-9.]+$/)) return null;
	for (let kv in split(trim(fs.readfile(RUN + '/resolve') ?? ''), /[ \n]+/)) {
		let i = index(kv, '=');
		if (i > 0 && substr(kv, 0, i) == addr) return substr(kv, i + 1);
	}
	return null;
}
function pings() {
	let p = {};
	for (let l in readlines(RUN + '/ping.tsv')) {
		let f = split(l, '\t');
		p[f[0]] = { ms: int(f[1]), at: int(f[2]), rtt: (f[3] != null && int(f[3]) > 0) ? int(f[3]) : null,
			// açık bağlantıda ölçülen tünel gecikmesi (sayfaların/oyunun hissettiği)
			warm: (f[4] != null && int(f[4]) > 0) ? int(f[4]) : null };
	}
	return p;
}
function out(x) { print(sprintf('%J\n', x)); }

// Elle sıralama: main.node_order = "ad|adres:port" anahtarları. Abonelik güncellenip sunucular yeniden eklense de (bölüm adı değişir)
// aynı ad+adres+port aynı yerde kalır; listede olmayanlar sona gider.
function node_key(s) { return (s.remarks ?? '') + '|' + (s.address ?? '') + ':' + (s.port ?? ''); }
function ordered_nodes(c) {
	let list = [], ord = c.get_all('kediray', 'main')?.node_order ?? [], pos = {};
	if (type(ord) != 'array') ord = [ord];
	for (let i = 0; i < length(ord); i++) if (pos[ord[i]] == null) pos[ord[i]] = i;
	c.foreach('kediray', 'node', s => push(list, { s: s, k: node_key(s), i: length(list) }));
	return sort(list, (a, b) => ((pos[a.k] ?? 1000000) - (pos[b.k] ?? 1000000)) || (a.i - b.i));
}

if (CMD == 'status') {
	let c = cursor();
	let m = c.get_all('kediray', 'main') || {};
	let ns = nodes_tsv(), active = getenv('KR_ACTIVE') || '', an = null;
	for (let n in ns) if (n.tag == active) an = n;
	let sel = m.node || 'auto', sn = null;
	for (let n in ns) if (n.sec == sel) sn = n;
	let p = pings();
	out({
		enabled: m.enabled == '1',
		running: getenv('KR_RUNNING') == '1',
		fw: getenv('KR_FW') == 'up',
		core: getenv('KR_CORE') || '',
		engine: getenv('KR_ENGINE') || 'Xray',
		// mihomo / sing-box + kendi yapılandırma modu: sunucu/uygulama/cihaz ayarları kullanılmaz
		own: (m.core == 'mihomo' || m.core == 'sing-box') && m.own_config == '1',
		own_file: ((m.core == 'mihomo' || m.core == 'sing-box') && m.own_config == '1') ? (m['own_cfg_' + replace(m.core, '-', '')] || null) : null,
		uptime: int(getenv('KR_UPTIME') || 0),
		mode: (m.mode == 'list') ? 'list' : 'global',
		auto: !sn && sel != 'none',
		disconnected: sel == 'none',
		selected: sn ? { sec: sn.sec, name: sn.name } : null,
		active: (an && sel != 'none') ? { sec: an.sec, name: an.name, tag: an.tag, address: an.address, port: an.port, sni: an.sni,
			// alan adı ile bağlanılıyorsa bir kez çözülen IP (Ayarlar > "IP ile bağlan")
			ip: resolved(an.address), protocol: an.protocol, network: an.network,
			ping: p[an.sec]?.ms, rtt: p[an.sec]?.rtt, warm: p[an.sec]?.warm } : null,
		nodes: length(ns),
		failsafe: m.failsafe || 'killswitch',
		// tünel DNS'i yanıt vermediği için geçici olarak operatör DNS'ine düşüldü mü
		dns_rescue: fs.stat(RUN + '/dns_rescue') != null,
		conflict: filter(split(getenv('KR_CONFLICT') || '', ' '), x => length(x)),
		direct_dead: m.auto_direct != '0' && trim(fs.readfile(RUN + '/direct') ?? '') == 'dead',
		capture: trim(fs.readfile(RUN + '/capture') ?? '') || (m.capture || 'mixed'),
		last_error: m.enabled == '1' && getenv('KR_RUNNING') != '1' ? trim(fs.readfile(RUN + '/last_error') ?? '') || null : null
	});
}
else if (CMD == 'node-move') {   // node-move <bölüm> up|down — komşusuyla yer değiştirir
	const u = require('uci').cursor();
	let list = ordered_nodes(u), sec = ARGV[1], dir = ARGV[2], idx = -1;
	for (let i = 0; i < length(list); i++) if (list[i].s['.name'] == sec) idx = i;
	let j = dir == 'up' ? idx - 1 : (dir == 'down' ? idx + 1 : -1);
	if (idx < 0 || j < 0 || j >= length(list)) { out({ ok: false, moved: false }); exit(idx < 0 ? 1 : 0); }
	let t = list[idx]; list[idx] = list[j]; list[j] = t;
	u.set('kediray', 'main', 'node_order', map(list, x => x.k));
	u.save('kediray');
	u.commit('kediray');
	out({ ok: true, moved: true });
}
else if (CMD == 'nodes') {
	let c = cursor(), p = pings(), res = [];
	let tsv = {};
	for (let n in nodes_tsv()) tsv[n.sec] = n;
	for (let it in ordered_nodes(c)) {
		let s = it.s;
		let t = tsv[s['.name']];
		push(res, {
			sec: s['.name'], name: s.remarks || ((s.address ?? '?') + ':' + (s.port ?? '')),
			protocol: s.protocol ?? t?.protocol, network: s.network ?? t?.network ?? 'tcp',
			address: s.address ?? t?.address, port: s.port ?? t?.port, tls: s.tls ?? '',
			json: !!s.raw, sub: s.sub ?? null, enabled: s.enabled != '0',
			tag: t?.tag, insecure: t?.insecure ?? false, pinned: t?.pinned ?? false,
			ping: p[s['.name']]?.ms, ping_at: p[s['.name']]?.at, rtt: p[s['.name']]?.rtt, warm: p[s['.name']]?.warm
		});
	}
	out(res);
}
else if (CMD == 'apps') {
	let c = cursor(), res = [];
	c.foreach('kediray', 'app', s => push(res, {
		sec: s['.name'], name: s.name || s['.name'], route: s.route || 'vpn', enabled: s.enabled != '0',
		ports: s.ports || '', ips: length(s.ip ?? []), domains: length(s.domain ?? []), domain_list: s.domain ?? [], tunnel_dns: s.tunnel_dns == '1'
	}));
	out(res);
}
else if (CMD == 'devices') {
	let c = cursor(), res = {}, order = [];
	let add = (mac, o) => {
		mac = lc(mac || '');
		if (!length(mac)) return;
		if (!res[mac]) { res[mac] = { mac: mac, ip: '', name: '', mode: 'default', sec: null, online: false }; push(order, mac); }
		for (let k, v in o) if (v != null && v !== '') res[mac][k] = v;
	};
	// Gerçekten bağlı mı? DHCP kirası ve ARP kayıtları cihaz ayrıldıktan sonra uzun süre kalır; bu yüzden
	// Wi-Fi'da asıl ölçüt "iw station dump" (bağlı istasyonlar), kablolu cihazda komşu tablosunun canlılığıdır.
	let rd = (cmd) => { let p = fs.popen(cmd + ' 2>/dev/null'); if (!p) return ''; let o = p.read('all') ?? ''; p.close(); return o; };
	// Bağlı kalma süresi: cihaz her görüldüğünde damgalanır; 10 dk hiç görünmezse yeniden bağlanmış sayılır
	const PF = RUN + '/presence.json';
	let pres = {};
	try { let t = fs.readfile(PF); if (t) pres = json(t); } catch (e) { pres = {}; }
	let assoc = {}, haveAssoc = false, neigh = {}, ndev = {}, nip = {}, probes = {}, fb = {};
	for (let l in split(rd('for i in $(iw dev | awk \'$1=="Interface"{print $2}\'); do echo "IF $i"; iw dev "$i" station dump | awk \'/^Station/{m=$2} /inactive time:/{print m, $3}\'; done'), '\n')) {
		if (match(l, /^IF /)) { haveAssoc = true; continue; }
		let m = match(l, /^([0-9a-fA-F]{2}(:[0-9a-fA-F]{2}){5}) ([0-9]+)/);
		if (m) assoc[lc(m[1])] = int(m[3]);   // son hareketten bu yana ms
	}
	for (let l in split(rd('ip -4 neigh show'), '\n')) {
		let m = match(l, /^([0-9.]+) dev ([^ ]+) lladdr ([0-9a-fA-F:]{17}).* (REACHABLE|DELAY|PROBE|STALE|FAILED|INCOMPLETE|PERMANENT|NOARP)/);
		if (m) { let k = lc(m[3]); neigh[k] = m[4]; ndev[k] = m[2]; nip[k] = m[1]; }
	}
	// Gerçekten bağlı mı? DHCP kirası, ARP kaydı ve Wi-Fi "bağlı" listesi cihaz ayrıldıktan sonra uzun süre kalır.
	// Asıl ölçüt: cihaz ARP'a şu an cevap veriyor mu. Cevabı belirsiz (bayat) olanlara komşu sınaması (ARP) gönderilir,
	// sonuç bir sonraki yoklamada okunur. Sınama yapılamıyorsa Wi-Fi hareketsizlik süresine bakılır.
	// Dönüş: 1 bağlı, 0 değil, -1 belirsiz (sınama sürüyor)
	let alive = (mac, ip) => {
		mac = lc(mac || '');
		if (assoc[mac] != null) return true;                 // Wi-Fi'a bağlı: uyku modunda olsa da (trafik göndermese de) bağlıdır
		if (pres[mac]?.wifi) return false;                   // daha önce Wi-Fi'daydı, şimdi bağlı listesinde yok: ayrıldı
		// Wi-Fi'da hiç görülmemiş (kablolu) cihaz: ARP cevabına bak
		let ns = neigh[mac];
		if (ns == 'REACHABLE' || ns == 'PERMANENT') return true;
		if (ns == 'FAILED' || ns == 'INCOMPLETE') return false;
		if (!haveAssoc && ns == null) return true;           // iw yok: eski davranış
		let a = nip[mac] || ip;
		if (a) {
			if (ns != 'PROBE') probes[mac] = { ip: a, dev: ndev[mac] || 'br-lan' };
			fb[mac] = ns != null;
			return -1;
		}
		return false;
	};
	for (let l in readlines('/tmp/dhcp.leases')) {
		let f = split(l, ' ');
		if (length(f) >= 4) add(f[1], { ip: f[2], name: f[3] != '*' ? f[3] : '', online: alive(f[1], f[2]) });
	}
	// ARP tablosundaki (statik IP) cihazlar
	for (let l in readlines('/proc/net/arp')) {
		let f = filter(split(l, ' '), x => length(x));
		if (length(f) >= 6 && f[3] != '00:00:00:00:00:00' && match(f[0], /^[0-9.]+$/) && f[2] != '0x0') add(f[3], { ip: res[lc(f[3])]?.ip || f[0], online: alive(f[3], f[0]) });
	}
	// Belirsiz cihazlara ARP sınaması gönder (asenkron; cevap sonraki yoklamada görünür)
	let probeOK = true;
	for (let mac, pr in probes) {
		let o = rd('ip neigh replace ' + pr.ip + ' lladdr ' + mac + ' dev ' + pr.dev + ' nud probe && echo ok');
		if (!match(o, /ok/)) { probeOK = false; break; }
	}
	c.foreach('kediray', 'device', s => {
		if (s.mac) add(s.mac, { name: s.name, mode: s.mode || 'default', sec: s['.name'], ip: res[lc(s.mac)]?.ip || s.ip });
	});
	let now = time(), keep = {};
	for (let mac, d in res) {
		let p = pres[mac];
		let sure = d.online === true;   // kesin doğrulanmış mı (ARP cevabı / Wi-Fi'da yeni hareket)
		if (d.online === -1) {
			// belirsiz: sınama çalışıyorsa son doğrulamadan 25 sn tolerans (süre dolunca çevrimdışı), çalışmıyorsa Wi-Fi hareketsizlik süresi
			d.online = probeOK ? (p ? (now - int(p.last ?? 0) < 25) : true) : !!fb[mac];
			sure = !probeOK;
		}
		if (d.online) {
			if (!p || now - int(p.last ?? 0) > 600) p = { first: now, last: now };
			if (sure) p.last = now;
			if (assoc[mac] != null) p.wifi = true;   // bu cihaz Wi-Fi'dan bağlanıyor: ayrılınca bağlı listesinden düşmesi yeterli kanıt
			pres[mac] = p;
			d.since = p.first;
			d.uptime = now - int(p.first);
		} else {
			// çevrimdışı: ilk görüldüğü andan (ya da son bağlı olduğu andan) itibaren say; 5 dk sonra listeden gizle
			if (!p) { p = { first: now, last: now }; pres[mac] = p; }
			d.since = p.first;
			d.uptime = 0;
			d.off_for = now - int(p.last ?? now);
			if (d.off_for >= 300) d.hidden = true;   // kuralı silinmez; cihaz tekrar bağlanınca kendi yönüyle geri gelir
		}
	}
	// 7 günden eski kayıtları at
	for (let mac, p in pres) if (now - int(p.last ?? 0) < 604800) keep[mac] = p;
	try { fs.mkdir(RUN); fs.writefile(PF + '.tmp', sprintf('%J', keep)); fs.rename(PF + '.tmp', PF); } catch (e) {}
	out(filter(map(order, k => res[k]), d => !d.hidden));
}
else if (CMD == 'stats') {
	// stdin: xray api statsquery çıktısı
	let j = null;
	try { j = json(fs.stdin.read('all')); } catch (e) { j = null; }
	let r = { vpn_up: 0, vpn_down: 0, direct_up: 0, direct_down: 0, t: time() };
	for (let s in (j?.stat ?? [])) {
		let m = match(s.name, /^outbound>>>([^>]+)>>>traffic>>>(uplink|downlink)$/);
		if (!m) continue;
		let v = int(s.value ?? 0), up = m[2] == 'uplink';
		if (substr(m[1], 0, 5) == 'node-') r[up ? 'vpn_up' : 'vpn_down'] += v;
		else if (m[1] == 'direct') r[up ? 'direct_up' : 'direct_down'] += v;
	}
	out(r);
}
else if (CMD == 'webtest') {
	// ARGV[1]: satır başına "host<TAB>dns con tls ttfb tot code<TAB>(vpn aynısı)" (curl -w saniye cinsinden)
	const running = ARGV[2] == '1';
	let tests = [], sd = 0, st = 0, sv = 0, n = 0;
	let part = (f, off) => {
		// curl kümülatif verir: connect DNS'i, appconnect connect'i içerir
		let dns = +f[0], con = +f[1], tls = +f[2], ttfb = +f[3], tot = +f[4];
		let m = x => int(x * 1000 + 0.5);
		return {
			dns: m(dns), connect: m(con > dns ? con - dns : 0), tls: m(tls > con ? tls - con : 0),
			ttfb: m(ttfb > tls ? ttfb - tls : (ttfb > con ? ttfb - con : 0)), total: m(tot), code: int(f[5])
		};
	};
	for (let l in readlines(ARGV[1])) {
		let c = split(l, '\t');
		if (length(c) < 3) continue;
		let d = part(split(trim(c[1]), /[ ]+/)), v = part(split(trim(c[2]), /[ ]+/));
		push(tests, { host: c[0], direct: d, vpn: v });
		n++; sd += d.dns; st += d.total; sv += v.total;
	}
	// Ortalamaya yalnız TAMAMLANAN ölçümler girer: başarısız denemede curl 0 yazar, 0 ms "iyi" demek değildir
	let okD = filter(tests, t => t.direct.code > 0), okV = filter(tests, t => t.vpn.code > 0);
	let dnsOk = filter(tests, t => t.direct.dns > 0 || t.direct.code > 0);
	let sdo = 0; for (let t in dnsOk) sdo += t.direct.dns;
	let sto = 0; for (let t in okD) sto += t.direct.total;
	let svo = 0; for (let t in okV) svo += t.vpn.total;
	let avg = { dns: length(dnsOk) ? int(sdo / length(dnsOk)) : null,
		direct_total: length(okD) ? int(sto / length(okD)) : null,
		vpn_total: length(okV) ? int(svo / length(okV)) : null };
	// Ad çözümlenemediyse curl DNS aşamasında 0 yazıp zaman aşımına düşer: bu "DNS 0 ms, iyi" DEĞİL, "DNS ölü"dür
	let deadDns = filter(tests, t => t.direct.code == 0 && t.direct.dns == 0);
	let deadV = filter(tests, t => t.vpn.code == 0);
	let verdict = [];
	if (length(deadDns) == n && n > 0) {
		push(verdict, 'Modem hiçbir adresi çözemedi: ' + n + ' adresin hepsi ad çözümleme aşamasında zaman aşımına düştü (curl "DNS 0 ms" yazar, bu iyi demek değil).');
		push(verdict, 'En olası sebep: DNS modu "Tünelden" ve tünel şu an bağlantıyı düşürüyor — çözümleme de tünelden gittiği için modem hiçbir adı çözemez. Günlükte "Sunucu el sıkışma sırasında bağlantıyı kapattı (EOF)" varsa sebep budur.');
		push(verdict, 'Hemen çözüm: Ayarlar → DNS → "Direkt" moduna al (sorgular tünelden bağımsız çözülür). Kalıcı çözüm: sunucunun el sıkışmayı neden düşürdüğünü bul — "kediray dialtest".');
	}
	else if (length(deadDns)) push(verdict, length(deadDns) + ' adres çözümlenemedi (DNS aşamasında zaman aşımı).');
	else if (avg.dns == null) push(verdict, 'DNS süresi ölçülemedi.');
	else if (avg.dns >= 1000) push(verdict, 'DNS çok yavaş (' + avg.dns + ' ms): sayfa daha açılmadan bekleniyor. Ayarlar → DNS → "Direkt" modunu ve direkt DNS yedeğini dene.');
	else if (avg.dns >= 300) push(verdict, 'DNS yavaş (' + avg.dns + ' ms): ilk açılışta hissedilir.');
	else push(verdict, 'DNS iyi (' + avg.dns + ' ms).');
	if (running) {
		if (length(deadV) && length(deadV) != length(deadDns))
			push(verdict, length(deadV) + ' adres VPN üzerinden hiç açılmadı: sunucu bağlantısı kopuyor (Günlük\'e bak, "kediray dialtest" ile ölç).');
		let ov = (avg.vpn_total != null && avg.direct_total != null) ? avg.vpn_total - avg.direct_total : null;
		if (ov == null) push(verdict, 'VPN ek gecikmesi hesaplanamadı: ölçümlerin bir kısmı tamamlanmadı.');
		else if (ov > 1500) push(verdict, 'VPN sayfayı ' + ov + ' ms geciktiriyor: sunucu uzak ya da yükte; başka sunucu dene.');
		else if (ov > 400) push(verdict, 'VPN ' + ov + ' ms ekliyor (normal aralık: 100-400 ms).');
		else push(verdict, 'VPN ek gecikmesi normal (' + ov + ' ms).');
	} else push(verdict, 'VPN kapalı: yalnızca direkt ölçüldü.');
	if (getenv('KR_SOCKS_OK') == '0')
		push(verdict, 'curl bu modemde SOCKS desteklemiyor: VPN sütunu ölçülemedi (apk add curl).');
	out({ running: running, tests: tests, avg: avg, verdict: verdict });
}
else if (CMD == 'conns') {
	// stdin: /proc/net/nf_conntrack ; ARGV[1] = istemci IP (boş = hepsi), ARGV[2] = TUN işareti (UDP tüneli), ARGV[3] = TPROXY işareti
	// KR_CONNS_SRC=api: $RUN/conns.api (mihomo / sing-box /connections) asıl kaynak; conntrack yalnız cihazı bulmak için.
	// Çıktı: [{ proto, dst, host, port, client, n, via: direct|vpn|block, vpn, out, rule, app, sec, want, bad, web, src }]
	const ip = ARGV[1] || '';
	const tunmark = int(ARGV[2] ?? 0) || 738, tpmark = int(ARGV[3] ?? 0) || 737;
	const SRC = getenv('KR_CONNS_SRC') == 'api' ? 'api' : 'ct';
	const OWN = getenv('KR_OWN') == '1';
	const DEAD = getenv('KR_DIRECT_DEAD') == '1';
	const PRIV = /^(0\.|10\.|127\.|169\.254\.|192\.168\.|172\.(1[6-9]|2[0-9]|3[01])\.|22[4-9]\.|23[0-9]\.|24[0-9]\.|25[0-5]\.)/;
	let lst = v => { let r = []; for (let x in (type(v) == 'array' ? v : [v ?? ''])) for (let y in split(trim('' + x), /[ \t\r\n,]+/)) if (length(y)) push(r, y); return r; };
	let ip2n = s => { let p = match(s ?? '', /^([0-9]+)\.([0-9]+)\.([0-9]+)\.([0-9]+)$/); return p ? int(p[1]) * 16777216 + int(p[2]) * 65536 + int(p[3]) * 256 + int(p[4]) : null; };
	let cidr = s => {
		let m = match(trim(s ?? ''), /^([0-9.]+)(\/([0-9]+))?$/);
		if (!m) return null;
		let n = ip2n(m[1]), b = (m[3] != null) ? int(m[3]) : 32;
		if (n == null || b < 0 || b > 32) return null;
		let size = 1;
		for (let i = 0; i < 32 - b; i++) size *= 2;
		return [n - n % size, size];   // [ağın ilk adresi, adres sayısı] (bit işlemi yok: 32 bit taşmasına karşı)
	};
	let in_cidr = (n, c) => n != null && c != null && n >= c[0] && n < c[0] + c[1];
	// LAN ağları ve modemin kendi LAN adresleri (192.168.1.1/24 -> ağ + kendi adresi)
	let lan = [], self = {};
	for (let x in lst(getenv('KR_LAN_NETS'))) { let c = cidr(x); if (c) { push(lan, c); self[split(x, '/')[0]] = true; } }
	if (!length(lan)) push(lan, cidr('192.168.0.0/16'));
	let is_client = s => !self[s] && length(filter(lan, c => in_cidr(ip2n(s), c))) > 0;
	let srv = {};
	for (let x in lst(getenv('KR_SERVER_IPS'))) srv[x] = true;

	// --- conntrack ---
	// orijinal yön: src0 -> dst0 (sport0 -> dport0); yanıt yönü: src1 -> dst1 (sport1 -> dport1)
	let ct = [], cl1 = {}, cl2 = {}, rout = {};
	for (let l in split(fs.stdin.read('all') ?? '', '\n')) {
		let pr = match(l, / (tcp|udp) /);
		let s = match(l, /src=([0-9.]+)/g), d = match(l, /dst=([0-9.]+)/g), sp = match(l, /sport=([0-9]+)/g), dp = match(l, /dport=([0-9]+)/g);
		if (!pr || !s || !d || !dp || !sp || length(s) < 2 || length(d) < 2 || length(dp) < 2 || length(sp) < 2) continue;
		let mk = match(l, /mark=([0-9]+)/);
		let e = { p: pr[1], s0: s[0][1], d0: d[0][1], sp0: int(sp[0][1]), dp0: int(dp[0][1]), s1: s[1][1], dp1: int(dp[1][1]),
			mark: mk ? int(mk[1]) : 0, unrep: index(l, '[UNREPLIED]') >= 0 };
		if (match(e.d0, PRIV)) continue;
		if (is_client(e.s0)) {
			push(ct, e);
			// Bağlantıyı açan cihaz: kaynak portu (NAT yoksa) ya da yanıt yönündeki hedef port (TUN'a girerken NAT'lanmışsa) ile
			cl1[e.p + '|' + e.d0 + '|' + e.dp0 + '|' + e.sp0] = e.s0;
			cl1[e.p + '|' + e.d0 + '|' + e.dp0 + '|' + e.dp1] ??= e.s0;
			let k2 = e.p + '|' + e.d0 + '|' + e.dp0;
			cl2[k2] ??= [];
			if (index(cl2[k2], e.s0) < 0) push(cl2[k2], e.s0);
		}
		else if (e.s0 != '127.0.0.1' && !srv[e.d0])
			rout[e.p + '|' + e.d0 + '|' + e.dp0] = true;   // modemin kendisinin (çekirdeğin direkt çıkışı) açtığı bağlantı
	}

	// --- uygulama kuralları (kendi yapılandırma modunda KediRay uygulamaları kullanılmaz) ---
	let c = cursor(), apps = [], devm = {};
	let mainc = c.get_all('kediray', 'main') ?? {};
	let defdev = DEAD ? 'vpn' : (mainc.default_device || 'vpn');
	if (!OWN) {
		c.foreach('kediray', 'app', s => {
			if (s.enabled == '0') return;
			let a = { sec: s['.name'], name: s.name || s['.name'], route: s.route || 'vpn', suf: [], full: [], kw: [], re: [], gs: [], gi: [], nets: [], ports: [] };
			for (let x in lst(s.domain)) {
				let m = match(x, /^([a-z]+):(.*)$/), t = m ? m[1] : 'domain', v = m ? m[2] : replace(x, /^\*?\./, '');
				if (t == 'regexp') { try { push(a.re, regexp(v)); } catch (e) { } continue; }
				v = lc(replace(v, /\.+$/, ''));
				if (!length(v)) continue;
				if (t == 'domain') push(a.suf, v);
				else if (t == 'full') push(a.full, v);
				else if (t == 'keyword') push(a.kw, v);
				else if (t == 'geosite') push(a.gs, v);
			}
			for (let x in lst(s.ip)) {
				let g = match(x, /^geoip:(.+)$/);
				if (g) { push(a.gi, lc(g[1])); continue; }
				if (int(s.expand ?? 0) == 24) {   // gen.uc app_ips ile aynı: tek IP'ler /24'e genişler
					let p = split(x, '/');
					if (!(length(p) > 1 && int(p[1]) <= 24) && match(p[0], /^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$/))
						x = join('.', slice(split(p[0], '.'), 0, 3)) + '.0/24';
				}
				let cc = cidr(x);
				if (cc) push(a.nets, cc);
			}
			for (let p in lst(s.ports)) {
				let m = match(p, /^([0-9]+)(-([0-9]+))?$/);
				if (m) { let x = int(m[1]), y = m[3] ? int(m[3]) : x; push(a.ports, x <= y ? [x, y] : [y, x]); }
			}
			push(apps, a);
		});
		// Cihaz yönleri: Direkt cihazın her bağlantısı direkt gider (uygulama kuralı uygulanmaz)
		let lease = {};
		for (let l in split(fs.readfile('/tmp/dhcp.leases') ?? '', '\n')) {
			let f = split(l, ' ');
			if (length(f) >= 3) lease[lc(f[1])] = f[2];
		}
		c.foreach('kediray', 'device', s => {
			let m = s.mode;
			if (m != 'vpn' && m != 'direct' && m != 'block') return;
			if (DEAD && m == 'direct') m = 'vpn';
			if (s.mac && lease[lc(s.mac)]) devm[lease[lc(s.mac)]] = m;
			for (let x in lst(s.ip)) if (ip2n(x) != null) devm[x] = m;
		});
	}
	let ends = (h, s) => h == s || (length(h) > length(s) && substr(h, length(h) - length(s) - 1) == '.' + s);
	let app_of = (host, dst, port, rule, pl) => {
		host = lc(host ?? ''); rule = lc(rule ?? ''); pl = lc(pl ?? '');
		let n = ip2n(dst);
		for (let a in apps) {
			if (length(host)) {
				for (let x in a.full) if (host == x) return a;
				for (let x in a.suf) if (ends(host, x)) return a;
				for (let x in a.kw) if (index(host, x) >= 0) return a;
				for (let x in a.re) if (match(host, x)) return a;
			}
			// geosite/geoip listeleri burada açılamaz: çekirdeğin eşleştirdiği kural (GEOSITE,whatsapp) uygulamanınsa sayılır
			if (rule == 'geosite' && index(a.gs, pl) >= 0) return a;
			if (rule == 'geoip' && index(a.gi, pl) >= 0) return a;
			for (let x in a.nets) if (in_cidr(n, x)) return a;
			for (let x in a.ports) if (port >= x[0] && port <= x[1]) return a;
		}
		return null;
	};

	// --- bağlantıları topla ---
	let agg = {};
	let add = (o) => {
		if (o.port == 53 || o.port == 123) return;
		if (length(ip) && o.client != ip) return;
		let a = OWN ? null : app_of(o.host, o.dst, o.port, o.rk, o.pl);
		let dm = (!OWN && length(o.client)) ? (devm[o.client] ?? defdev) : null;
		let want = null;
		if (dm == 'direct') want = 'direct';
		else if (a) want = (DEAD && a.route != 'warp') ? 'vpn' : a.route;
		let bad = false;
		if (want == 'direct' || want == 'frag') bad = (o.via == 'vpn');
		else if (want == 'vpn' || want == 'warp') bad = (o.via == 'direct');
		let k = join('|', [o.proto, o.host || o.dst, o.port, o.via, o.client]);
		agg[k] ??= { proto: o.proto, dst: o.dst, host: o.host, port: o.port, client: o.client, n: 0, via: o.via, vpn: o.via == 'vpn',
			out: o.out, rule: o.rule, app: a ? a.name : (dm == 'direct' ? 'Direkt cihaz' : ''), sec: a ? a.sec : '', want: want, bad: bad,
			web: (o.port == 80 || o.port == 443), src: SRC, own: OWN };
		agg[k].n++;
	};

	if (SRC == 'api') {
		let api = {}, px = {};
		try { api = json(fs.readfile(RUN + '/conns.api') ?? '{}') ?? {}; } catch (e) { api = {}; }
		try { px = (json(fs.readfile(RUN + '/conns.px') ?? '{}') ?? {}).proxies ?? {}; } catch (e) { px = {}; }
		let via_of = (nm) => {
			let t = lc(px[nm]?.type ?? ''), n = lc(nm ?? '');
			if (t == 'direct' || n == 'direct') return 'direct';
			if (t == 'reject' || t == 'rejectdrop' || t == 'block' || n == 'reject' || n == 'reject-drop' || n == 'block') return 'block';
			if (t == 'dns' || n == 'dns-out' || n == 'dns') return 'dns';
			return 'vpn';
		};
		for (let cn in (api.connections ?? [])) {
			let md = cn.metadata ?? {}, ch = cn.chains ?? [];
			if (match(md.inboundName ?? '', /^t-node-/)) continue;   // KediRay'in kendi gecikme ölçümleri
			let nm = ch[0] ?? '', via = via_of(nm);
			if (via == 'dns') continue;
			let p = lc(md.network ?? 'tcp'), dst = md.destinationIP ?? '', port = int(md.destinationPort ?? 0), sport = int(md.sourcePort ?? 0);
			if (length(dst) && match(dst, PRIV)) continue;
			let cli = '';
			if (is_client(md.sourceIP ?? '')) cli = md.sourceIP;
			else {
				cli = cl1[p + '|' + dst + '|' + port + '|' + sport] ?? '';
				if (!length(cli)) {
					let cs = cl2[p + '|' + dst + '|' + port] ?? [];
					cli = (length(ip) && index(cs, ip) >= 0) ? ip : (length(cs) == 1 ? cs[0] : '');
				}
			}
			let host = md.host || md.sniffHost || '';
			add({ proto: p, dst: dst, host: host, port: port, client: cli, via: via, out: via == 'vpn' ? nm : (via == 'direct' ? 'DIRECT' : 'REJECT'),
				rule: (cn.rule ?? '') + (length(cn.rulePayload ?? '') ? ' ' + cn.rulePayload : ''), rk: cn.rule, pl: cn.rulePayload });
		}
	} else {
		for (let e in ct) {
			// Çekirdeğe girdi mi? TCP NAT yönlendirmesi yanıt kaynağını değiştirir; UDP (TUN) ve TPROXY işaretle tanınır
			let core = (e.s1 != e.d0) || e.mark == tunmark || e.mark == tpmark;
			let via = 'direct';
			if (core) via = rout[e.p + '|' + e.d0 + '|' + e.dp0] ? 'direct' : 'vpn';   // çekirdek hedefe modemden bağlandıysa direkt
			else if (e.unrep && e.p == 'udp' && e.dp0 == 443) via = 'block';               // QUIC reddi
			add({ proto: e.p, dst: e.d0, host: '', port: e.dp0, client: e.s0, via: via, out: '', rule: '' });
		}
	}
	out(sort(values(agg), (a, b) => (b.bad - a.bad) || ((b.app ? 1 : 0) - (a.app ? 1 : 0)) || (a.web - b.web) || (b.n - a.n)));
}
else {
	warn('kullanım: cli.uc status|nodes|apps|devices|stats|conns\n');
	exit(1);
}
