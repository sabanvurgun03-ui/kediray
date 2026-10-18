'use strict';
// KediRay yapılandırma üreticisi
// Kullanım: ucode gen.uc <xray|nft|dnsmasq|nodes|test|check> [config.json]
//           ucode gen.uc outbound <bölüm>          -> o sunucunun Xray outbound'u (+ test için mini config)
//           ucode gen.uc outbound-json '<json>'    -> kaydedilmemiş aday sunucunun outbound'u
// config.json verilmezse UCI 'kediray' okunur (test için KR_CFG ile JSON fikstürü de verilebilir).

const fs = require('fs');
const WHAT = ARGV[0] || 'xray';
const DATA_MODES = { 'outbound': 1, 'outbound-json': 1 };

function load() {
	let f = DATA_MODES[WHAT] ? getenv('KR_CFG') : (ARGV[1] || getenv('KR_CFG'));
	if (f)
		return json(fs.readfile(f));
	return require('uci').cursor().get_all('kediray');
}

let raw = load() || {};
if (raw.values) raw = raw.values;
const SECS = sort(values(raw), (a, b) => (a['.index'] ?? 0) - (b['.index'] ?? 0));
const M = raw.main || {};

function of(t) { return filter(SECS, s => s['.type'] == t); }
function opt(k, d) { let v = M[k]; return (v == null || v === '') ? d : v; }
function on(v, d) { if (v == null || v === '') return d; return (v == '1' || v == 'true' || v == 'on' || v == 'yes'); }
function num(v, d) { let n = int(v); return (v == null || v === '' || n != n) ? d : n; }
function die(msg, code) { warn('kediray: ' + msg + '\n'); exit(code ?? 1); }

// Liste değerlerini diziye çevir (UCI list veya boşlukla ayrılmış option)
function L(v, sep) {
	if (v == null) return [];
	if (type(v) != 'array') v = [v];
	let out = [];
	for (let x in v)
		for (let y in split(trim('' + x), sep ?? /\s+/))
			if (length(y)) push(out, y);
	return out;
}

function dom(d) {
	d = trim(d);
	if (!length(d)) return null;
	if (index(d, ':') >= 0) return d;
	d = replace(d, /^\*?\./, '');
	return 'domain:' + d;
}

function is_v4(x) { return !!match(x, /^[0-9]{1,3}(\.[0-9]{1,3}){3}(\/[0-9]{1,2})?$/); }

// Tek IP'yi (ya da /25-/32'yi) komşularıyla birlikte /24'e genişletir.
// Oyun sunucuları aynı /24'te sıralanır: ışınlanırken başka bir kanal sunucusuna bağlanınca da direkt kalır.
function ip24(x) {
	let p = split(x, '/');
	if (length(p) > 1 && int(p[1]) <= 24) return x;
	let o = split(p[0], '.');
	if (length(o) != 4) return x;
	return o[0] + '.' + o[1] + '.' + o[2] + '.0/24';
}
// Uygulamanın IP listesi; expand='24' ise tek IP'ler /24'e genişletilir
function app_ips(a) {
	let l = L(a.ip);
	return int(a.expand ?? 0) == 24 ? uniq(map(l, ip24)) : l;
}
function is_v6(x) { return !!match(x, /^[0-9a-fA-F:]+:[0-9a-fA-F:.]*(\/[0-9]{1,3})?$/); }
function ipn(x) {
	x = trim(x);
	if (!length(x)) return null;
	if (match(x, /^(geoip|ext):/)) return x;
	if (is_v4(x) || is_v6(x)) return x;
	return null;
}

// Port aralıklarını ayrıştır, sırala ve birleştir -> [[a,b],...]
function ranges(v) {
	let r = [];
	for (let p in L(v, /[ \t\r\n,]+/)) {
		let m = match(p, /^([0-9]+)(-([0-9]+))?$/);
		if (!m) continue;
		let a = int(m[1]), b = m[3] ? int(m[3]) : a;
		if (a > b) { let t = a; a = b; b = t; }
		if (a < 1 || b > 65535) continue;
		push(r, [a, b]);
	}
	r = sort(r, (x, y) => x[0] - y[0]);
	let out = [];
	for (let x in r) {
		let last = out[length(out) - 1];
		if (last && x[0] <= last[1] + 1) { if (x[1] > last[1]) last[1] = x[1]; }
		else push(out, [x[0], x[1]]);
	}
	return out;
}
function rstr(r, sep) { return join(sep ?? ',', map(r, x => x[0] == x[1] ? '' + x[0] : x[0] + '-' + x[1])); }

// ---------- Sunucular ----------
function split_hostport(o) {
	// JSON outbound içinden adres/port çıkar (görüntüleme ve DNS için)
	let s = o?.settings || {};
	let t = s.vnext?.[0] || s.servers?.[0] || s;
	return { address: t.address, port: t.port };
}

const UUID_RE = /^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$/;
const PROTOS = { vless: 1, vmess: 1, trojan: 1, shadowsocks: 1 };
const NETS = { tcp: 1, raw: 1, ws: 1, grpc: 1, xhttp: 1, httpupgrade: 1 };

// Bir sunucu bölümünü hazırla; sorunları 'errs' dizisine yaz. Kullanılamazsa null döner.
function prep_node(n, errs) {
	let name = n.remarks || n['.name'] || 'yeni sunucu';
	let e = (field, msg) => push(errs, { node: n['.name'], name: name, field: field, msg: msg });
	if (n.raw) {
		let o = null;
		try { o = json(n.raw); } catch (x) { o = null; }
		if (type(o) != 'object') { e('raw', 'JSON okunamadı (yazım hatası)'); return null; }
		if (!o.protocol) { e('raw', 'JSON içinde "protocol" alanı yok'); return null; }
		if (!PROTOS[o.protocol]) { e('raw', '"' + o.protocol + '" protokolü desteklenmiyor (vless, vmess, trojan, shadowsocks)'); return null; }
		let hp = split_hostport(o);
		if (!hp.address) { e('raw', 'JSON içinde sunucu adresi (settings…address) yok'); return null; }
		if (!hp.port) { e('raw', 'JSON içinde port (settings…port) yok'); return null; }
		n.address = hp.address;
		n.port = '' + hp.port;
		n.protocol = o.protocol;
		n._json = o;
		return n;
	}
	let ok = true;
	if (!PROTOS[n.protocol]) { e('protocol', 'protokol seçilmemiş ya da desteklenmiyor'); ok = false; }
	if (!n.address) { e('address', 'adres boş'); ok = false; }
	let p = int(n.port);
	if (!n.port || p != p || p < 1 || p > 65535) { e('port', 'port 1-65535 arasında olmalı'); ok = false; }
	if (n.protocol == 'vless' || n.protocol == 'vmess') {
		if (!n.uuid) { e('uuid', 'UUID boş'); ok = false; }
		else if (!match(n.uuid, UUID_RE) && length(n.uuid) > 30) { e('uuid', 'UUID biçimi hatalı (ör. b831381d-6324-4d53-ad4f-8cda48b30811)'); ok = false; }
	}
	if ((n.protocol == 'trojan' || n.protocol == 'shadowsocks') && !n.password) { e('password', 'parola boş'); ok = false; }
	if (n.protocol == 'shadowsocks' && !n.method) { e('method', 'şifreleme yöntemi seçilmemiş'); ok = false; }
	if (n.network && !NETS[n.network]) { e('network', '"' + n.network + '" aktarımı desteklenmiyor'); ok = false; }
	if (n.path && substr(n.path, 0, 1) != '/') { e('path', 'yol (path) "/" ile başlamalı'); ok = false; }
	if (n.tls == 'reality') {
		if (!n.pbk) { e('pbk', 'REALITY public key boş'); ok = false; }
		if (!n.sni) { e('sni', 'REALITY için SNI gerekli'); ok = false; }
	}
	if (n.flow && n.protocol != 'vless') { e('flow', 'flow sadece VLESS ile kullanılır'); ok = false; }
	if (n.flow && n.network && n.network != 'tcp' && n.network != 'raw') { e('flow', 'xtls-rprx-vision sadece TCP aktarımıyla çalışır'); ok = false; }
	return ok ? n : null;
}

let ERRS = [];
let NODES = [];
for (let n in of('node')) {
	if (n.enabled == '0') continue;
	let r = prep_node(n, ERRS);
	if (r) push(NODES, r);
	else warn('kediray: hatalı sunucu atlandı: ' + (n.remarks || n['.name']) + '\n');
}
for (let i = 0; i < length(NODES); i++) {
	NODES[i]._tag = sprintf('node-%03d', i + 1);
	NODES[i]._tport = num(getenv('KR_TEST_BASE') || opt('test_base', null), 21000) + i + 1;
}

const SEL_NAME = opt('node', 'auto');
const DISC = SEL_NAME == 'none';   // "Bağlantıyı kes": sunucu yok, trafik direkt
let SEL = null;
for (let n in NODES) if (n['.name'] == SEL_NAME) SEL = n;

// 1.19.4: WS heartbeat ve TCP keepalive varsayılan 30 sn. Boşta kalan WebSocket tüneli sunucu önündeki proxy/CDN (60-100 sn) ve
// mobil operatör NAT'ı tarafından sessizce kesilince sunucudan gelen bildirimler (WhatsApp vb.) telefona ulaşmıyordu.
const HB = num(opt('ws_heartbeat'), 30);
const KA = num(opt('tcp_keepalive'), 30);

// Yakalama modu:
//   mixed   TCP çekirdekte NAT redirect ile (hızlı yol), UDP hev-socks5-tunnel TUN ile   [varsayılan]
//   tproxy  TCP+UDP TPROXY ile
//   redirect sadece TCP (UDP tünellenmez, QUIC reddedilir)
const CAPTURE = getenv('KR_CAPTURE') || opt('capture', 'mixed');
// Soket işaretleri: çekirdeğin kendi bağlantıları / TPROXY / TUN'a gidecek UDP
const MARK_CORE = hex(replace(getenv('KR_MARK_CORE') || '0x2e0', /^0x/, ''));
const MARK_TP = getenv('KR_MARK_TP') || '0x2e1';
const MARK_TUN = getenv('KR_MARK_TUN') || '0x2e2';
// Çekirdek allowInsecure destekliyor mu (kediray betiği test edip KR_CAP_INSECURE=1 verir; 26.x'te kaldırıldı)
const CAP_INSECURE = getenv('KR_CAP_INSECURE') == '1';

// Sunucuya IP ile bağlan: alan adı bir kez IP'ye çevrilir (KR_RESOLVE="alan=ip ..."),
// alan adı SNI/Host olarak kalır; böylece bağlantı DNS'e bağımlı olmaz.
const CONNECT_IP = on(opt('connect_ip'), true);
// Modeme operatörden gelen DNS sunucuları (CLI, KR_WAN_DNS ile geçirir)
const WAN_DNS = filter(L(getenv('KR_WAN_DNS')), is_v4);
// Direkt sorguların gideceği DNS: 'auto' -> operatör DNS'i.
// Ölçüldü: bazı hatlarda DoH adreslerine hiç ulaşılamıyor, her sorgu saniyelerce bekliyor.
function dns_direct_addr(o, i) {
	let v = opt(o, 'auto');
	if (v != 'auto' && v != '') return v;
	if (length(WAN_DNS) > i) return WAN_DNS[i];
	// Operatör DNS'i bilinmiyorsa DoH'a düş; yedek yuva her zaman farklı bir sağlayıcı olsun
	if (i == 0) return 'https+local://1.1.1.1/dns-query';
	return length(WAN_DNS) ? 'https+local://1.1.1.1/dns-query' : 'https+local://8.8.8.8/dns-query';
}
let RES = {};
for (let kv in L(getenv('KR_RESOLVE'))) {
	let i = index(kv, '=');
	if (i > 0) RES[substr(kv, 0, i)] = substr(kv, i + 1);
}
function by_ip(a) { return CONNECT_IP && a && RES[a] ? RES[a] : null; }

// Bağlantı varsayılanları xDivine-Ray'in (MIT, github.com/ozgunokan/xDivine-Ray) gerçek hatta ölçtüğü
// değerlere göre seçildi: TCP mux kapalı, UDP her zaman XUDP ile, QUIC tünelden, hedef IP korunur (routeOnly).

// WebSocket erken veri: varsayılan kapalı (bazı sunucu/CDN kurulumlarında sorun çıkarabiliyor).
const WS_EARLY = on(opt('ws_early'), false);
function ws_path(p) {
	p = p || '/';
	if (!WS_EARLY || match(p, /[?&]ed=/)) return p;
	return p + (index(p, '?') >= 0 ? '&' : '?') + 'ed=2048';
}
// Mux nesnesi iki ayrı şeyi taşır: TCP çoklama ve UDP'yi taşıyan XUDP.
//  - XUDP her zaman açık: onsuz bazı hedeflere UDP (oyun, arama, QUIC) tek yönlü kalıyor.
//  - xudpProxyUDP443 'allow': Xray'in varsayılanı QUIC'i sessizce atar, videolar takılır.
//  - TCP çoklama (concurrency > 0) varsayılan KAPALI (-1): hız düşürür; Vision ile hiç kullanılmaz.
const MUX = on(opt('mux'), false);
function mux_for(proto, flow, net) {
	return { enabled: true, concurrency: (MUX && !flow) ? 8 : -1, xudpConcurrency: 16, xudpProxyUDP443: 'allow' };
}

function sockopt(so) {
	so ??= {};
	so.mark ??= MARK_CORE;
	if (KA > 0) {
		so.tcpKeepAliveIdle ??= KA;
		so.tcpKeepAliveInterval ??= 15;
	}
	return so;
}

function stream(n) {
	let net = n.network || 'tcp';
	if (net == 'raw') net = 'tcp';
	let s = { network: net };
	let sec = n.tls || 'none';
	let host = n.host || '';
	// IP ile bağlanırken Host başlığı boş kalmasın: CDN/WS sunucusu alan adını görmeli
	if (!host && by_ip(n.address) && net != 'grpc') host = n.address;
	if (sec == 'tls') {
		s.security = 'tls';
		// fp boşsa telefondaki v2rayNG gibi Go varsayılan TLS kullanılır
		let t = { serverName: n.sni || host || n.address };
		if (n.fp && n.fp != 'none') t.fingerprint = n.fp;
		if (n.alpn) t.alpn = L(n.alpn, /[ \t\r\n,]+/);
		// ECH: abonelikten gelen echConfigList olduğu gibi Xray'e verilir (boşsa ECH kapalı; Xray ECH'i yalnızca bu alan doluysa açar)
		if (n.ech) t.echConfigList = n.ech;
		// sabitlenmiş sertifika varsa o; yoksa çekirdek destekliyorsa allowInsecure
		if (n.pin) t.pinnedPeerCertSha256 = n.pin;
		else if (n.insecure == '1' && CAP_INSECURE) t.allowInsecure = true;
		s.tlsSettings = t;
	}
	else if (sec == 'reality') {
		s.security = 'reality';
		s.realitySettings = {
			serverName: n.sni || n.host || '', fingerprint: n.fp || 'chrome',
			publicKey: n.pbk || '', shortId: n.sid || '', spiderX: n.spx || ''
		};
	}
	if (net == 'ws') {
		s.wsSettings = { path: ws_path(n.path) };
		if (host) { s.wsSettings.host = host; s.wsSettings.headers = { Host: host }; }
		if (HB > 0) s.wsSettings.heartbeatPeriod = HB;
	}
	else if (net == 'httpupgrade')
		s.httpupgradeSettings = { path: n.path || '/', host: host };
	else if (net == 'grpc') {
		s.grpcSettings = { serviceName: n.service_name || '', multiMode: (n.grpc_mode == 'multi') };
		if (by_ip(n.address)) s.grpcSettings.authority = n.host || n.address;
	}
	else if (net == 'xhttp') {
		s.xhttpSettings = { path: n.path || '/', host: host, mode: n.xhttp_mode || 'auto' };
	}
	else if (net == 'tcp' && n.header_type == 'http')
		s.tcpSettings = { header: { type: 'http', request: { path: [n.path || '/'], headers: { Host: L(host, /[ \t\r\n,]+/) } } } };
	s.sockopt = sockopt();
	return s;
}

function outbound(n) {
	let o;
	if (n._json) {
		o = n._json;
		o.tag = n._tag;
		o.streamSettings ??= {};
		let ss = o.streamSettings;
		ss.sockopt = sockopt(ss.sockopt);
		if (type(ss.tlsSettings) == 'object' && ss.tlsSettings.allowInsecure != null) {
			if (n.pin) { delete ss.tlsSettings.allowInsecure; ss.tlsSettings.pinnedPeerCertSha256 ??= n.pin; }
			else if (!CAP_INSECURE) delete ss.tlsSettings.allowInsecure;
		}
		if (ss.network == 'ws' || ss.network == 'websocket') {
			ss.wsSettings ??= {};
			if (HB > 0) ss.wsSettings.heartbeatPeriod ??= HB;
			ss.wsSettings.path = ws_path(ss.wsSettings.path);
		}
		// JSON'da TCP mux açıkça açılmamışsa XUDP'yi (UDP taşıma) ekle; açıksa kullanıcınınki kalır
		let uflow = o.settings?.vnext?.[0]?.users?.[0]?.flow;
		if (o.protocol == 'shadowsocks' && o.settings?.servers?.[0]) o.settings.servers[0].uot ??= true;
		if (!(o.mux?.enabled && (o.mux?.concurrency ?? 0) > 0)) {
			let m = mux_for(o.protocol, uflow, ss.network);
			if (m) o.mux = m;
		}
		// IP ile bağlan: adresi IP yap, alan adını SNI/Host olarak koru
		let st = o.settings || {}, tgt = st.vnext?.[0] || st.servers?.[0] || st;
		let ip = by_ip(tgt.address);
		if (ip) {
			let dom = tgt.address;
			tgt.address = ip;
			if (ss.security == 'tls') { ss.tlsSettings ??= {}; ss.tlsSettings.serverName ??= dom; }
			for (let k in ['wsSettings', 'httpupgradeSettings', 'xhttpSettings']) {
				let w = ss[k];
				if (type(w) == 'object' && !w.host) w.host = dom;
			}
			if (ss.network == 'ws' && !ss.wsSettings) ss.wsSettings = { host: dom };
			if (ss.network == 'grpc') { ss.grpcSettings ??= {}; ss.grpcSettings.authority ??= dom; }
		}
		return o;
	}
	let p = n.protocol, port = int(n.port);
	o = { tag: n._tag, protocol: p };
	if (p == 'vless') {
		let u = { id: n.uuid, encryption: n.encryption || 'none' };
		if (n.flow) u.flow = n.flow;
		o.settings = { vnext: [{ address: by_ip(n.address) || n.address, port: port, users: [u] }] };
	}
	else if (p == 'vmess')
		o.settings = { vnext: [{ address: by_ip(n.address) || n.address, port: port, users: [{ id: n.uuid, security: n.cipher || 'auto' }] }] };
	else if (p == 'trojan')
		o.settings = { servers: [{ address: by_ip(n.address) || n.address, port: port, password: n.password }] };
	else if (p == 'shadowsocks')
		o.settings = { servers: [{ address: by_ip(n.address) || n.address, port: port, method: n.method, password: n.password }] };
	else
		return null;
	o.streamSettings = stream(n);
	let m = mux_for(p, n.flow, n.network);
	if (m) o.mux = m;
	if (p == 'shadowsocks') o.settings.servers[0].uot = true;
	return o;
}

// ---------- Uygulamalar / kurallar ----------
// Direkt çıkış yoksa (KR_DIRECT_DEAD=1, kediray direct) "direkt" olan her şey VPN'e çevrilir
// Ham ölçüm: hat gerçekten direkt çıkamıyorsa. Otomatik çevirme kapalı olsa da bildirim düzeltmesi bu ölçüme bakar
// (direkt çıkış yokken FCM'i direkt göndermek bildirimleri tamamen keser).
const DIRECT_RAW_DEAD = getenv('KR_DIRECT_DEAD') == '1';
const DIRECT_DEAD = DIRECT_RAW_DEAD && opt('auto_direct', '1') != '0';
const APPS = map(filter(of('app'), a => a.enabled != '0'), a => (DIRECT_DEAD && a.route != 'warp') ? { ...a, route: 'vpn' } : a);
// Cloudflare WARP (WireGuard) çıkışı: 'warp' yönlü uygulamalar buradan çıkar. Anahtarlar `kediray warp register` ile alınır.
// warp_via=vpn: WARP, VPN sunucusunun içinden kurulur (operatör UDP'yi/WARP'ı görmez); direct: doğrudan hattan.
// TLS parçalama (SNI engeli aşma): 'frag' yönlü uygulamalar direkt çıkar ama TLS el sıkışması küçük parçalara bölünür.
const FRAG_ON = length(filter(APPS, a => a.route == 'frag')) > 0;
const WARP_ON = on(opt('warp'), false) && opt('warp_key', '') != '' && opt('warp_pub', '') != '' && opt('warp_v4', '') != '';
const RULES = map(filter(of('rule'), r => r.enabled != '0'), r => (DIRECT_DEAD && r.target == 'direct') ? { ...r, target: 'proxy' } : r);
// Bildirim (FCM/APNs) direkt istisnası: direkt çıkış yokken kapalı (yoksa bildirimler hiç gelmez)
const PUSH_FIX = on(opt('push_fix'), false) && !DIRECT_RAW_DEAD;
const PUSH_DOMAINS = [
	'domain:mtalk.google.com', 'regexp:^alt[0-9]*-mtalk\\.google\\.com$', 'domain:mtalk4.google.com',
	'domain:push.apple.com', 'domain:push-apple.com.akadns.net', 'domain:push.hicloud.com'
];
const PUSH_PORTS = '5223,5228-5230';
// Tarayıcıların kendi "Güvenli DNS"i (DoH): Chrome/Firefox sistem DNS'ini atlayıp doğrudan bu adreslere sorar.
// Bu hatta DoH adreslerine ulaşılamadığı ölçüldü -> tarayıcı her yeni ad için ~50 sn bekliyor, sayfa yarım kalıyor.
// Kapatınca (RST ile reddedince) tarayıcı anında sistem DNS'ine döner: KediRay'in DNS'i devreye girer.
const DOH_DOMAINS = [
	'domain:dns.google', 'domain:dns64.dns.google', 'domain:cloudflare-dns.com', 'domain:mozilla.cloudflare-dns.com',
	'domain:chrome.cloudflare-dns.com', 'domain:one.one.one.one', 'domain:security.cloudflare-dns.com',
	'domain:family.cloudflare-dns.com', 'domain:dns.quad9.net', 'domain:dns9.quad9.net', 'domain:dns11.quad9.net',
	'domain:doh.opendns.com', 'domain:doh.familyshield.opendns.com', 'domain:dns.nextdns.io', 'domain:doh.dns.sb',
	'domain:dns.adguard.com', 'domain:dns.adguard-dns.com', 'domain:doh.cleanbrowsing.org', 'domain:dns.alidns.com',
	'domain:doh.pub', 'domain:dns.controld.com', 'domain:freedns.controld.com', 'domain:dns.mullvad.net'
];
// Adresi elle yazan istemciler için IP listesi (yalnız 443/853: bu IP'lerin 53'ü DNS yönlendirmesiyle zaten ele alınır)
const DOH_IPS = ['1.1.1.1', '1.0.0.1', '8.8.8.8', '8.8.4.4', '9.9.9.9', '149.112.112.112',
	'208.67.222.222', '208.67.220.220', '94.140.14.14', '94.140.15.15', '45.90.28.0/24', '45.90.30.0/24'];
// 1.17.1: "Akıllı (Türkiye direkt)" modu kaldırıldı; 'rule' ayarı artık 'global' gibi çalışır (her şey VPN, yalnız seçilen uygulamalar direkt)
const MODE = (opt('mode', 'global') == 'list' && !DIRECT_DEAD) ? 'list' : 'global';
// Kullanıcının kendi seçtiği DNS IP'si DoH engelinin içine düşmesin (ör. dns_direct=1.1.1.1 düz DNS)
function rem_ip4() {
	let m = match(opt('dns_remote', 'https://1.1.1.1/dns-query'), /([0-9]{1,3}(\.[0-9]{1,3}){3})/);
	return m ? m[1] : '';
}
// DNS: varsayılan 'private' = dnsmasq -> çekirdeğin DNS portu -> tünel.
// Sorgu tünelin veri yoluna (TUN/TPROXY) girmez, çekirdek kendisi çözer -> hızlı ve sızıntısız.
// 'off' (DNS'e dokunma) TUN yakalamasında hiçbir adı çözemez (cihazın 53 portu TUN'a girer, yanıt dönmez):
// bu birleşimde sessizce 'private'a düşüyoruz.
const DNS_MODE = (opt('dns_mode', 'private') == 'off' && CAPTURE == 'tun') ? 'private' : opt('dns_mode', 'private');
// Uygulama bazlı "DNS'i tünelden çöz" (tunnel_dns=1): global DNS modu 'off' olsa bile yalnız bu uygulamaların
// alan adları dnsmasq -> çekirdek -> tünel yolundan çözülür; diğer her şey modemin kendi DNS'inde kalır.
let TDOMS = [];
for (let a in APPS) if (a.tunnel_dns == '1') for (let d in L(a.domain)) push(TDOMS, dom(d));
TDOMS = uniq(TDOMS);
const DNS_PART = (DNS_MODE == 'off' && length(TDOMS) > 0);
const DNS_ON = (DNS_MODE != 'off' || DNS_PART);

function tgt(t) {
	if (t == 'warp' && WARP_ON) return { outboundTag: 'warp' };
	if (t == 'frag') return { outboundTag: 'direct-frag' };
	if (t == 'proxy' || t == 'vpn' || t == 'warp') return { balancerTag: 'proxy' };
	if (t == 'block') return { outboundTag: 'block' };
	return { outboundTag: 'direct' };
}

function add_match(R, m, t) {
	let base = { ruleTag: m.tag };
	if (m.inbound) base.inboundTag = m.inbound;
	let d = filter(map(L(m.domain), dom), x => x);
	let ip = filter(map(L(m.ip), ipn), x => x);
	let pr = ranges(m.port ?? m.ports);
	// Yeni Xray sürümleri aynı ruleTag'in tekrarını reddeder ("duplicate ruleTag"): her kural benzersiz etiket alır.
	if (length(d)) push(R, { ...base, domain: d, ...tgt(t) });
	if (length(ip)) push(R, { ...base, ruleTag: m.tag + '-ip', ip: ip, ...tgt(t) });
	if (length(pr)) push(R, { ...base, ruleTag: m.tag + '-port', port: rstr(pr), network: 'tcp,udp', ...tgt(t) });
}

function xray() {
	if (!length(NODES))
		die('hiç sunucu yok; önce link, JSON veya abonelik ekleyin', 2);

	let tp_port = num(opt('tproxy_port'), 12345), dns_port = num(opt('dns_port'), 15353);
	let socks_port = num(opt('socks_port'), 10808), api_port = num(opt('api_port'), 10085);
	// Ölçüm: hedefi alan adıyla değiştirmek (sunucuya tekrar çözdürmek) her yeni bağlantıya
	// bir tur ekliyor (47 ms yerine 100 ms, ara ara 700 ms). routeOnly: alan adı sadece kurallar için okunur,
	// hedef IP korunur; adres zaten tünelden çözüldüğü için doğru bölgeden gelir.
	let sniff = {
		enabled: on(opt('sniff'), true), destOverride: ['http', 'tls', 'quic'],
		// sniff_mode=off: hiçbir durumda hedefi alan adıyla değiştirme (her bağlantıda sunucuya alan adı çözdürmez; hız testi/indirme daha çabuk açılır)
		routeOnly: opt('sniff_mode', 'auto') == 'off' || !(on(opt('sniff_override'), false) || length(filter(APPS, x => x.route == 'warp' || x.route == 'frag' || x.tunnel_dns == '1')) > 0)
	};

	// ÖLÇÜLDÜ (Xray 26.3.27): UDP girişinde içerik tanıma (sniffing) her UDP oturumuna SABİT ~200 ms ekliyor.
	// Çıplak Xray, ağ gecikmesi sıfır: sniffing kapalı 0 ms, açık 201 ms. TCP'de böyle bir bekleme yok
	// (TLS ClientHello ilk pakette gelir). DNS ve oyun/arama UDP'si bu yüzden geç açılıyordu.
	// TCP'de sniffing açık kalır (kural eşleştirme için gerekli), UDP girişlerinde kapatılır.
	// tun modunda TCP de socks-in'den geldiği için orada içerik tanıma gerekir (alan adı kuralları).
	// mixed/redirect/tproxy'de socks-in yalnız UDP taşır: kapalı kalır.
	const sniff_udp = (CAPTURE == 'tun');

	// Yakalama moduna göre LAN girişi
	let lan_in = { tag: 'lan-in', listen: '0.0.0.0', port: tp_port, protocol: 'dokodemo-door',
		settings: { network: 'tcp', followRedirect: true }, sniffing: sniff };
	// tproxy: TCP ve UDP ayrı girişlere ayrılır; UDP girişinde sniffing yok (200 ms bekleme yok)
	let lan_in_udp = null;
	if (CAPTURE == 'tproxy') {
		lan_in.streamSettings = { sockopt: { tproxy: 'tproxy' } };
		lan_in_udp = { tag: 'lan-in-udp', listen: '0.0.0.0', port: tp_port + 1, protocol: 'dokodemo-door',
			settings: { network: 'udp', followRedirect: true },
			streamSettings: { sockopt: { tproxy: 'tproxy' } } };
	}

	let inb = [
		lan_in,
		...(lan_in_udp ? [lan_in_udp] : []),
		// LAN'dan gelen DNS de buraya yönlendirilir (çekirdekte, tünele hiç girmeden): sniffing yok, hızlı.
		// WAN tarafı fw4'ün varsayılan kuralıyla kapalıdır. DNS modu 'off' iken bu giriş hiç açılmaz.
		...(!DNS_ON ? [] : [{ tag: 'dns-in', listen: '0.0.0.0', port: dns_port, protocol: 'dokodemo-door',
		  settings: { address: '1.1.1.1', port: 53, network: 'tcp,udp' } }]),
		// mixed modda hev-socks5-tunnel UDP'yi buraya getirir
		// mixed modda UDP'nin tamamı buradan geçer: sniffing KAPALI (yukarıdaki ölçüme bakın)
		{ tag: 'socks-in', listen: '127.0.0.1', port: socks_port, protocol: 'socks',
		  settings: { auth: 'noauth', udp: true, ip: '127.0.0.1' },
		  ...(sniff_udp ? { sniffing: sniff } : {}) },
		{ tag: 'api', listen: '127.0.0.1', port: api_port, protocol: 'dokodemo-door',
		  settings: { address: '127.0.0.1' } }
	];
	for (let n in NODES)
		push(inb, { tag: 't-' + n._tag, listen: '127.0.0.1', port: n._tport, protocol: 'socks', settings: { udp: false } });

	let outb = [
		{ tag: 'direct', protocol: 'freedom', settings: { domainStrategy: on(opt('ipv6'), false) ? 'UseIP' : 'UseIPv4' },
		  streamSettings: { sockopt: { mark: MARK_CORE } } },
		{ tag: 'block', protocol: 'blackhole' },
		{ tag: 'dns-out', protocol: 'dns', settings: { network: 'tcp', address: '1.1.1.1', port: 53 },
		  streamSettings: { sockopt: { mark: MARK_CORE } } }
	];
	for (let n in NODES) {
		let o = outbound(n);
		if (o) push(outb, o);
	}
	if (FRAG_ON) push(outb, { tag: 'direct-frag', protocol: 'freedom',
		settings: { domainStrategy: on(opt('ipv6'), false) ? 'UseIP' : 'UseIPv4',
			fragment: { packets: opt('frag_packets', 'tlshello'), length: opt('frag_length', '100-200'), interval: opt('frag_interval', '10-20') } },
		streamSettings: { sockopt: { mark: MARK_CORE } } });
	if (WARP_ON) {
		let res = map(split(opt('warp_reserved', '0,0,0'), ','), x => int(x));
		let via = (opt('warp_via', 'vpn') == 'vpn');
		let vtag = (SEL ? SEL._tag : NODES[0]._tag);
		push(outb, { tag: 'warp', protocol: 'wireguard',
			settings: {
				secretKey: opt('warp_key'),
				address: filter([opt('warp_v4') + '/32', opt('warp_v6', '') != '' ? opt('warp_v6') + '/128' : null], x => x),
				peers: [{ publicKey: opt('warp_pub'), allowedIPs: ['0.0.0.0/0', '::/0'], endpoint: opt('warp_endpoint', 'engage.cloudflareclient.com:2408') }],
				mtu: num(opt('warp_mtu'), 1280),
				reserved: length(res) == 3 ? res : [0, 0, 0],
				domainStrategy: 'ForceIPv4'
			},
			streamSettings: { sockopt: via ? { dialerProxy: vtag } : { mark: MARK_CORE } } });
	}

	// --- Yönlendirme kuralları (ilk eşleşen kazanır) ---
	let R = [];
	push(R, { inboundTag: ['api'], outboundTag: 'api' });
	if (DNS_ON) push(R, { inboundTag: ['dns-in'], outboundTag: 'dns-out' });
	// İstemcinin kendi seçtiği DNS (8.8.8.8 vb.) de KediRay DNS'inden yanıtlanır (sızıntı yok)
	// off modunda 53 numaralı port normal trafik gibi yönlendirilir (modemin kendi DNS'i devrede kalır)
	if (DNS_MODE != 'off') push(R, { inboundTag: ['lan-in', 'lan-in-udp', 'socks-in'], port: '53', outboundTag: 'dns-out' });
	for (let n in NODES)
		push(R, { inboundTag: ['t-' + n._tag], outboundTag: n._tag });
	// Operatör DNS'ine (ve genel olarak düz IP yazılmış direkt DNS'e) giden sorgular tünelden GEÇMEZ:
	// aksi halde tünel takıldığında alan adı çözülemez ve tarayıcı 50 sn döner.
	// Uzak DNS ile aynı IP varsa dışarıda bırakılır: yoksa tünelden gitmesi gereken sorgu direkt çıkar (sızıntı).
	let rem = opt('dns_remote', 'https://1.1.1.1/dns-query');
	let rem_ip = match(rem, /([0-9]{1,3}(\.[0-9]{1,3}){3})/);
	rem_ip = rem_ip ? rem_ip[1] : '';
	let dns_direct_ips = filter([...WAN_DNS, dns_direct_addr('dns_direct', 0), dns_direct_addr('dns_direct2', 1)],
		x => is_v4(x) && x != rem_ip);
	if (DNS_ON) {
		if (length(dns_direct_ips))
			push(R, { ruleTag: 'dns-local', inboundTag: ['dns-internal'], ip: uniq(dns_direct_ips), outboundTag: 'direct' });
		push(R, { inboundTag: ['dns-internal'], balancerTag: 'proxy' });
	}

	// Tarayıcının kendi DoH'u: engelle -> tarayıcı anında sistem DNS'ine düşer (50 sn'lik askıda kalma biter).
	// Kural DNS kurallarından SONRA: KediRay'in kendi DoH sorguları (dns-internal) yukarıda çözülmüş olur.
	if (on(opt('block_doh'), false))
		push(R, { ruleTag: 'doh-block', inboundTag: ['lan-in', 'lan-in-udp', 'socks-in'],
			domain: DOH_DOMAINS, port: '443,853', outboundTag: 'block' });

	// Uygulamalar (VPN / Direkt kullanıcı seçimi) - en yüksek öncelik
	for (let a in APPS)
		add_match(R, { domain: a.domain, ip: app_ips(a), port: a.ports, tag: 'app-' + a['.name'] }, a.route == 'vpn' ? 'proxy' : a.route == 'warp' ? 'warp' : a.route == 'frag' ? 'frag' : 'direct');

	// Bildirim (FCM / APNs) direkt
	if (PUSH_FIX)
		add_match(R, { domain: PUSH_DOMAINS, port: PUSH_PORTS, tag: 'push' }, 'direct');

	if (on(opt('ad_block'), false))
		push(R, { ruleTag: 'ads', domain: ['geosite:category-ads-all'], outboundTag: 'block' });

	for (let r in RULES)
		add_match(R, { domain: r.domain, ip: r.ip, port: r.port, tag: 'rule-' + r['.name'] }, r.target || 'proxy');

	push(R, { ruleTag: 'private', ip: ['geoip:private'], outboundTag: 'direct' });
	push(R, { ruleTag: 'final', network: 'tcp,udp', ...tgt(MODE == 'list' ? 'direct' : 'proxy') });

	// --- DNS ---
	// Gerçek hatta ölçüldü: tünelden DNS-over-TCP kullanılırken sunucu bir bağlantıyı düşürünce
	// ("failed to read response length -> read/write on closed pipe") sorgu ölüyor ve sayfa askıda kalıyor.
	// DoH (HTTP/2) aynı durumda kendi içinde yeniden deniyor. Kurulumla gelen varsayılan Google TCP'dir (uyumluluk); bu belirti görülürse DoH seçilir.
	let remote = opt('dns_remote', 'https://1.1.1.1/dns-query');
	if (match(remote, /^[0-9.]+$/)) remote = 'tcp://' + remote;
	let direct = dns_direct_addr('dns_direct', 0);
	// Direkt sorgular için yedek: ilk DoH takılırsa (5G hatlarında sık) sorgu saniyelerce beklemez
	let direct2 = dns_direct_addr('dns_direct2', 1);
	if (direct2 == direct) direct2 = '';
	let ddom = [], pdom = [];
	for (let a in APPS) for (let d in L(a.domain)) push((a.route == 'direct' || a.route == 'frag') ? ddom : pdom, dom(d));
	if (PUSH_FIX) for (let d in PUSH_DOMAINS) push(ddom, d);
	for (let r in RULES) {
		if (r.target == 'block') continue;
		for (let d in L(r.domain)) push(r.target == 'direct' ? ddom : pdom, dom(d));
	}
	let servers = [];
	if (length(TDOMS)) push(servers, { address: remote, domains: TDOMS, skipFallback: true });
	pdom = filter(uniq(pdom), x => index(TDOMS, x) < 0);
	if (length(pdom) && DNS_MODE != 'fast') push(servers, { address: remote, domains: pdom, skipFallback: true });
	if (length(ddom)) {
		push(servers, { address: direct, domains: uniq(ddom), skipFallback: true });
		if (length(direct2)) push(servers, { address: direct2, domains: uniq(ddom), skipFallback: true });
	}
	// dns_mode=private (varsayılan): listede olmayan adlar tünelden çözülür
	//   (hiçbir sorgu operatöre sızmaz; çekirdek kendi çözdüğü için sorgu TUN/TPROXY yoluna girmez).
	// dns_mode=fast: varsayılan sorgular direkt çıkar (tünel koparsa da ad çözülür, karşılığında gizlilik azalır).
	if (MODE == 'list' || DNS_MODE == 'fast') { push(servers, direct); if (length(direct2)) push(servers, direct2); push(servers, remote); }
	else { push(servers, remote); push(servers, direct); if (length(direct2)) push(servers, direct2); }

	let fb = SEL ? SEL._tag : NODES[0]._tag;
	// connIdle 4 saat: telefonun bildirim bağlantısı saatlerce veri taşımadan açık durur
	let pol = { connIdle: num(opt('conn_idle'), 14400) };
	// Hız ayarı: bağlantı başına tampon (KB). Küçük tampon yüksek hızda akışı boğar ve hız testinin yükselmesini geciktirir.
	if (on(opt('speed_tune'), true)) pol.bufferSize = num(opt('buffer_size'), 1024);
	let cfg = {
		log: { loglevel: opt('log_level', 'warning'), access: (opt('log_level', 'warning') == 'info' || opt('log_level') == 'debug') ? '' : 'none' },
		api: { tag: 'api', services: ['RoutingService', 'StatsService'] },
		stats: {},
		policy: {
			// v2rayNG JSON'ları kullanıcı seviyesi 8 kullanır: ikisine de aynı uzun bağlantı süresi
			levels: { '0': pol, '8': pol },
			system: { statsOutboundUplink: true, statsOutboundDownlink: true }
		},
		// DNS modu 'off': yönlendiricinin kendi DNS'ine hiç dokunulmaz.
		// Alan adı kuralları yine çalışır: bağlantıdaki SNI okunur (sniffing/routeOnly).
		...(!DNS_ON ? {} : { dns: {
			tag: 'dns-internal',
			queryStrategy: on(opt('ipv6'), false) ? 'UseIP' : 'UseIPv4',
			// Tünel anlık takılırsa (mobil hatta bağlantı sıfırlanması vb.) bilinen adresi beklemeden ver, arkada yenile:
			// uygulama/oyun "DNS zaman aşımı" yüzünden bağlantı kuramama yaşamaz.
			// Süre kısa tutulur: CDN adresleri sık değişir, bir gün önceki adres ölü olabilir ve
			// tarayıcı o adrese bağlanmaya çalışırken sayfa "yükleniyor" kalır (yuvarlak döner).
			serveStale: on(opt('dns_stale'), true),
			serveExpiredTTL: num(opt('dns_stale_ttl'), 600),
			servers: servers
		} }),
		inbounds: inb,
		outbounds: outb,
		observatory: {
			subjectSelector: ['node-'],
			probeUrl: opt('probe_url', 'https://www.gstatic.com/generate_204'),
			probeInterval: opt('probe_interval', '2m'),
			enableConcurrency: true
		},
		routing: {
			domainStrategy: 'AsIs',
			balancers: [{ tag: 'proxy', selector: DISC ? ['__yok__'] : ['node-'], strategy: { type: 'leastPing' }, fallbackTag: DISC ? 'direct' : fb }],
			rules: R
		}
	};
	print(sprintf('%.J\n', cfg));
}

// ---------- nftables ----------
const BYPASS4 = [
	'0.0.0.0/8', '10.0.0.0/8', '100.64.0.0/10', '127.0.0.0/8', '169.254.0.0/16',
	'172.16.0.0/12', '192.0.0.0/24', '192.168.0.0/16', '224.0.0.0/4', '240.0.0.0/4'
];

function nft() {
	let ifs = L(getenv('KR_LAN_IFS') || 'br-lan');
	let tp_port = num(opt('tproxy_port'), 12345);
	let bypass = [...BYPASS4, ...filter(L(getenv('KR_SERVER_IPS')), is_v4)];
	let dips = [], dports = [];
	for (let a in APPS) {
		if (a.route == 'vpn' || a.route == 'warp' || a.route == 'frag') continue;
		for (let x in app_ips(a)) if (is_v4(x)) push(dips, x);
		for (let r in ranges(a.ports)) push(dports, r);
	}
	for (let r in RULES) {
		if (r.target != 'direct') continue;
		for (let x in L(r.ip)) if (is_v4(x)) push(dips, x);
		for (let p in ranges(r.port)) push(dports, p);
	}
	dports = ranges(rstr(dports));

	let dev = { vpn: { mac: [], ip: [] }, direct: { mac: [], ip: [] }, block: { mac: [], ip: [] } };
	for (let d in of('device')) {
		let m = d.mode;
		if (m != 'vpn' && m != 'direct' && m != 'block') continue;
		if (DIRECT_DEAD && m == 'direct') m = 'vpn';
		if (d.mac && match(d.mac, /^([0-9A-Fa-f]{2}:){5}[0-9A-Fa-f]{2}$/)) push(dev[m].mac, lc(d.mac));
		for (let x in L(d.ip)) if (is_v4(x)) push(dev[m].ip, x);
	}
	let defdev = DIRECT_DEAD ? 'vpn' : opt('default_device', 'vpn');
	let q = x => '"' + x + '"';
	let lanset = '{ ' + join(', ', map(ifs, q)) + ' }';

	let o = [];
	let set = (name, typ, els, iv) => {
		push(o, '\tset ' + name + ' {');
		push(o, '\t\ttype ' + typ + ';' + (iv ? ' flags interval; auto-merge;' : ''));
		if (length(els)) push(o, '\t\telements = { ' + join(', ', uniq(els)) + ' }');
		push(o, '\t}');
	};
	// Ortak eleme: LAN dışı, yerel/özel hedefler, sunucu IP'leri, Direkt uygulamalar (Metin2/Teams IP ve portları),
	// bildirim portları; ardından cihaz kuralı ve eylem zinciri.
	let guards = (act, protos) => {
		push(o, '\t\tmeta nfproto != ipv4 return');
		push(o, '\t\tiifname != ' + lanset + ' return');
		push(o, '\t\tmeta l4proto != ' + protos + ' return');
		push(o, '\t\tfib daddr type { local, broadcast, multicast } return');
		// Ağdan engellenen cihaz: yakalanmaz (yakalansa yönlendirme forward zincirini atlar ve engel işlemez)
		if (length(dev.block.mac)) push(o, '\t\tether saddr @dev_block return');
		if (length(dev.block.ip)) push(o, '\t\tip saddr @devip_block return');
		push(o, '\t\tip daddr @bypass4 return');
		push(o, '\t\tip daddr @direct4 return');
		if (length(dports))
			push(o, '\t\tmeta l4proto { tcp, udp } th dport { ' + rstr(dports, ', ') + ' } return');
		if (PUSH_FIX)
			push(o, '\t\ttcp dport { 5223, 5228-5230 } return');
		if (defdev == 'direct') {
			push(o, '\t\tether saddr @dev_vpn jump ' + act);
			push(o, '\t\tip saddr @devip_vpn jump ' + act);
		} else {
			push(o, '\t\tether saddr @dev_direct return');
			push(o, '\t\tip saddr @devip_direct return');
			push(o, '\t\tjump ' + act);
		}
	};

	push(o, 'table inet kediray');
	push(o, 'delete table inet kediray');
	push(o, 'table inet kediray {');
	set('bypass4', 'ipv4_addr', bypass, true);
	set('direct4', 'ipv4_addr', dips, true);
	set('dev_vpn', 'ether_addr', dev.vpn.mac, false);
	set('dev_direct', 'ether_addr', dev.direct.mac, false);
	set('devip_vpn', 'ipv4_addr', dev.vpn.ip, true);
	set('devip_direct', 'ipv4_addr', dev.direct.ip, true);
	// Tarayıcıların kendi DoH sunucuları (443/853 reddedilir; 53 zaten DNS yönlendirmesine takılır)
	set('doh4', 'ipv4_addr', on(opt('block_doh'), false) ? filter(DOH_IPS, x => x != rem_ip4()) : [], true);
	set('dev_block', 'ether_addr', dev.block.mac, false);
	set('devip_block', 'ipv4_addr', dev.block.ip, true);
	// Trafik sayacı: tünelin dış baytları (modemin kendi bağlantısı; donanım hızlandırmaya girmez, kesin sayılır)
	set('srv4', 'ipv4_addr', filter(L(getenv('KR_SERVER_IPS')), is_v4), true);
	push(o, '\tcounter vpn_rx { }');
	push(o, '\tcounter vpn_tx { }');
	push(o, '\tchain acct_in {');
	push(o, '\t\ttype filter hook input priority filter - 5; policy accept;');
	push(o, '\t\tip saddr @srv4 counter name "vpn_rx"');
	push(o, '\t}');
	push(o, '\tchain acct_out {');
	push(o, '\t\ttype filter hook output priority filter - 5; policy accept;');
	push(o, '\t\tip daddr @srv4 counter name "vpn_tx"');
	push(o, '\t}');

	if (CAPTURE == 'tun') {
		// Her şey (TCP+UDP) işaretlenir; ip rule işaretli paketi TUN'a (hev-socks5-tunnel) yollar.
		// "tun" modu: çekirdekte NAT yok, tüm oturum hev'in kendi TCP yığınında.
		push(o, '\tchain tun_pre {');
		push(o, '\t\ttype filter hook prerouting priority mangle; policy accept;');
		guards('tun_act', '{ tcp, udp }');
		push(o, '\t}');
		push(o, '\tchain tun_act {');
		if (on(opt('dns_hijack'), true) && DNS_MODE != 'off') push(o, '\t\tmeta l4proto { tcp, udp } th dport 53 return');
		if (on(opt('block_quic'), true)) push(o, '\t\tudp dport 443 return');
		push(o, '\t\tmeta mark set ' + MARK_TUN + ' ct mark set ' + MARK_TUN);
		push(o, '\t}');
	} else if (CAPTURE == 'tproxy') {
		push(o, '\tchain prerouting {');
		push(o, '\t\ttype filter hook prerouting priority mangle; policy accept;');
		guards('tp', '{ tcp, udp }');
		push(o, '\t}');
		push(o, '\tchain tp {');
		if (on(opt('dns_hijack'), true)) push(o, '\t\tmeta l4proto { tcp, udp } th dport 53 return');
		if (on(opt('block_quic'), true)) push(o, '\t\tudp dport 443 return');
		push(o, '\t\tmeta l4proto { tcp, udp } socket transparent 1 meta mark set ' + MARK_TP + ' accept');
		// TCP ve UDP ayrı portlara: UDP girişinde sniffing kapalı (her UDP oturumuna ~200 ms ekliyordu)
		push(o, '\t\tmeta l4proto tcp meta mark set ' + MARK_TP + ' tproxy ip to :' + tp_port + ' accept');
		push(o, '\t\tmeta l4proto udp meta mark set ' + MARK_TP + ' tproxy ip to :' + (tp_port + 1) + ' accept');
		push(o, '\t}');
	} else {
		// TCP: çekirdekte NAT redirect. fw4'ün dstnat'ından (-100) önce.
		push(o, '\tchain nat_pre {');
		push(o, '\t\ttype nat hook prerouting priority dstnat - 5; policy accept;');
		guards('nat_act', 'tcp');
		push(o, '\t}');
		push(o, '\tchain nat_act {');
		push(o, '\t\tmeta l4proto tcp redirect to :' + tp_port);
		push(o, '\t}');
		if (CAPTURE == 'mixed') {
			// UDP: sadece işaretlenir; ip rule işaretli paketi TUN (hev-socks5-tunnel) tablosuna gönderir
			push(o, '\tchain udp_pre {');
			push(o, '\t\ttype filter hook prerouting priority mangle; policy accept;');
			guards('udp_act', 'udp');
			push(o, '\t}');
			push(o, '\tchain udp_act {');
			if (on(opt('dns_hijack'), true) && DNS_MODE != 'off') push(o, '\t\tudp dport 53 return');
			if (on(opt('block_quic'), true)) push(o, '\t\tudp dport 443 return');
			push(o, '\t\tmeta mark set ' + MARK_TUN + ' ct mark set ' + MARK_TUN);
			push(o, '\t}');
		}
	}

	// DNS (53): cihaz hangi DNS'i yazarsa yazsın çekirdekte KediRay DNS'ine gider.
	// Böylece sorgu TUN/hev yoluna hiç girmez (ölçüm: o yol UDP başına ~200 ms ekliyor) ve
	// Xray'in DNS önbelleği devreye girer. Kural tünelden geçen cihazlar için geçerli (Direkt cihaz kendi DNS'ini kullanır).
	if (on(opt('dns_hijack'), true) && DNS_MODE != 'off') {
		push(o, '\tchain dns_nat {');
		push(o, '\t\ttype nat hook prerouting priority dstnat - 6; policy accept;');
		guards('dns_act', '{ tcp, udp }');
		push(o, '\t}');
		push(o, '\tchain dns_act {');
		push(o, '\t\tmeta l4proto { tcp, udp } th dport 53 redirect to :' + num(opt('dns_port'), 15353));
		push(o, '\t}');
	}

	// TCP MSS ayarı: SYN paketlerindeki MSS, çıkış yolunun MTU'suna göre kısılır. Yol MTU'su 1500'den küçükse (hücresel hat,
	// tünel sarmalaması) büyük indirmeler (WhatsApp foto/video) takılıyor ya da hiç açılmıyordu. Küçük paketler etkilenmez.
	if (on(opt('mss_clamp'), true)) {
		push(o, '\tchain mss_fwd {');
		push(o, '\t\ttype filter hook forward priority mangle; policy accept;');
		push(o, '\t\ttcp flags syn tcp option maxseg size set rt mtu');
		push(o, '\t}');
		push(o, '\tchain mss_out {');
		push(o, '\t\ttype filter hook output priority mangle; policy accept;');
		push(o, '\t\ttcp flags syn tcp option maxseg size set rt mtu');
		push(o, '\t}');
	}

	// QUIC (UDP 443): tünelde (UDP-over-TCP) tarayıcıyı takılı bırakabiliyor — ör. Google giriş sayfası dönüp duruyor.
	// v2rayNG ve Xray'in kendi varsayılanı gibi reddedilir; ICMP yanıtı anında gider, tarayıcı beklemeden TCP'ye (tünele) geçer.
	if (on(opt('block_quic'), true)) {
		push(o, '\tchain quic_fwd {');
		push(o, '\t\ttype filter hook forward priority filter - 5; policy accept;');
		guards('quic_act', 'udp');
		push(o, '\t}');
		push(o, '\tchain quic_act {');
		push(o, '\t\tudp dport 443 reject with icmpx type port-unreachable');
		push(o, '\t}');
	}

	// Tarayıcının kendi DoH'u, adresi elle yazılmışsa (IP ile): 443/853 anında reddedilir.
	// Alan adıyla gidenler Xray tarafında engellenir; ikisi birlikte tarayıcıyı sistem DNS'ine döndürür.
	if (on(opt('block_doh'), false)) {
		push(o, '\tchain doh_fwd {');
		push(o, '\t\ttype filter hook forward priority filter - 6; policy accept;');
		push(o, '\t\tmeta nfproto != ipv4 return');
		push(o, '\t\tiifname != ' + lanset + ' return');
		push(o, '\t\tip daddr @doh4 meta l4proto { tcp, udp } th dport { 443, 853 } reject with icmpx type port-unreachable');
		push(o, '\t}');
	}

	// Ağdan engellenen cihazlar: internet yok (yerel ağ ve DHCP çalışmaya devam eder)
	if (length(dev.block.mac) || length(dev.block.ip)) {
		push(o, '\tchain block_fwd {');
		push(o, '\t\ttype filter hook forward priority filter - 10; policy accept;');
		push(o, '\t\tiifname != ' + lanset + ' return');
		if (length(dev.block.mac)) push(o, '\t\tether saddr @dev_block reject with icmpx type admin-prohibited');
		if (length(dev.block.ip)) push(o, '\t\tip saddr @devip_block reject with icmpx type admin-prohibited');
		push(o, '\t}');
		// modemin kendi DNS'i de cevap vermesin: sayfa beklemeden "bağlanılamadı" desin
		push(o, '\tchain block_in {');
		push(o, '\t\ttype filter hook input priority filter - 10; policy accept;');
		push(o, '\t\tiifname != ' + lanset + ' return');
		push(o, '\t\tmeta l4proto { tcp, udp } th dport != 53 return');
		if (length(dev.block.mac)) push(o, '\t\tether saddr @dev_block reject');
		if (length(dev.block.ip)) push(o, '\t\tip saddr @devip_block reject');
		push(o, '\t}');
	}

	// IPv6 sızıntı koruması: VPN cihazlarının IPv6 ile tüneli atlamasını engelle
	if (!on(opt('ipv6'), false) && on(opt('v6_block'), true)) {
		push(o, '\tchain forward6 {');
		push(o, '\t\ttype filter hook forward priority filter - 1; policy accept;');
		push(o, '\t\tmeta nfproto != ipv6 return');
		push(o, '\t\tiifname != ' + lanset + ' return');
		push(o, '\t\tip6 daddr { fc00::/7, fe80::/10, ff00::/8 } return');
		if (length(dev.block.mac)) push(o, '\t\tether saddr @dev_block reject with icmpv6 type admin-prohibited');
		if (defdev == 'direct')
			push(o, '\t\tether saddr @dev_vpn reject with icmpv6 type admin-prohibited');
		else {
			push(o, '\t\tether saddr @dev_direct return');
			push(o, '\t\treject with icmpv6 type admin-prohibited');
		}
		push(o, '\t}');
	}
	push(o, '}');
	print(join('\n', o), '\n');
}

// ---------- hev-socks5-tunnel (mixed modda UDP) ----------
// Geliştiricinin bulduğu bildirim hatasının düzeltmesi: hev'in kendi zaman aşımları TCP 5 dk / UDP 1 dk.
// Ayarlanmazsa telefonun bildirim bağlantısı 5 dakikada kapanır, bildirimler toplu ve geç gelir.
// Burada boşta kalma süresi (conn_idle) hev'e de yazılır; UDP en fazla 10 dk (bellek için).
function hev() {
	let idle = num(opt('conn_idle'), 14400);
	if (idle > 86400) idle = 86400;
	let udp = idle > 600 ? 600 : idle;
	let o = [
		'tunnel:',
		'  name: ' + (getenv('KR_TUN') || 'kediray0'),
		'  mtu: ' + (num(opt('tun_mtu'), 1380) < 576 ? 576 : (num(opt('tun_mtu'), 1380) > 9000 ? 9000 : num(opt('tun_mtu'), 1380))),
		'  multi-queue: false',
		'  ipv4: ' + (getenv('KR_TUN_ADDR') || '198.19.0.1'),
		'',
		'socks5:',
		'  port: ' + num(opt('socks_port'), 10808),
		'  address: 127.0.0.1',
		"  udp: 'udp'",
		'  pipeline: false',
		'',
		'misc:',
		'  task-stack-size: 86016'
	];
	if (idle > 0) {
		if (getenv('KR_HEV_KEYS') == 'single')
			push(o, '  read-write-timeout: ' + idle * 1000);
		else {
			push(o, '  tcp-read-write-timeout: ' + idle * 1000);
			push(o, '  udp-read-write-timeout: ' + udp * 1000);
		}
	}
	push(o, '  log-file: stderr');
	push(o, '  log-level: ' + ({ debug: 'debug', info: 'info', error: 'error', none: 'error' }[opt('log_level', 'warning')] ?? 'warn'));
	push(o, '  limit-nofile: 65535');
	print(join('\n', o), '\n');
}

// ---------- dnsmasq ----------
function dnsmasq() {
	// 'off': yönlendiricinin DNS'ine dokunma
	if (DNS_MODE == 'off' && !DNS_PART) { print(''); return; }
	if (DNS_PART) {
		// Kısmi mod: modemin kendi DNS'i aynen kalır (no-resolv YOK); yalnız listedeki alan adları çekirdeğe gider
		let q = ['# KediRay - otomatik üretildi (yalnız uygulama bazlı DNS)'];
		for (let d in TDOMS) {
			let b = replace(replace(d, /^(domain|full):/, ''), /^[a-z]+:.*$/, '');
			if (b != '' && match(b, /^[A-Za-z0-9._-]+$/)) push(q, 'server=/' + b + '/127.0.0.1#' + num(opt('dns_port'), 15353));
		}
		print(join('\n', q), '\n');
		return;
	}
	// Önyükleme adresleri (sunucu alan adı, saat sunucusu, güncelleme adresleri) tünel kurulmadan çözülmeli.
	// Ölçüldü: bu hatta 1.1.1.1:53'e ulaşılamıyor -> sabit 1.1.1.1 yazarsak bu adlar HİÇ çözülmüyor
	// (ör. gstatic.com). Operatörün kendi DNS'i her zaman ayakta, o yüzden önce o kullanılır.
	let doms = [];
	for (let n in NODES) if (!is_v4(n.address) && !is_v6(n.address)) push(doms, n.address);
	for (let u in L(M.sub_url)) {
		let m = match(u, /^https?:\/\/([^\/:?#]+)/);
		if (m && !is_v4(m[1])) push(doms, m[1]);
	}
	for (let d in ['pool.ntp.org', 'time.google.com', 'time.cloudflare.com', 'openwrt.org', 'github.com', 'githubusercontent.com', 'gstatic.com'])
		push(doms, d);
	for (let d in L(getenv('KR_EXTRA_DIRECT'))) push(doms, d);
	let boots = length(WAN_DNS) ? WAN_DNS : [opt('dns_bootstrap', '1.1.1.1')];
	let o = ['# KediRay - otomatik üretildi', 'no-resolv', 'server=127.0.0.1#' + num(opt('dns_port'), 15353)];
	for (let d in uniq(doms)) for (let b in boots) push(o, 'server=/' + d + '/' + b);
	if (!on(opt('ipv6'), false)) push(o, 'filter-AAAA');
	print(join('\n', o), '\n');
}

// ---------- düğüm listesi (CLI/panel için) ----------
function nodes() {
	for (let n in NODES) {
		let j = n._json, ts = j?.streamSettings?.tlsSettings;
		let insecure = (n.insecure == '1' || ts?.allowInsecure === true) ? 1 : 0;
		let sni = n.sni || n.host || ts?.serverName || n.address;
		let net = n.network || (j?.streamSettings?.network ?? 'tcp');
		print(join('\t', [n._tag, n['.name'], n._tport, n.address, n.port, n.protocol, net, insecure, sni,
			n.pin || '-', replace(n.remarks || (n.address + ':' + n.port), /[\t\n]/g, ' ')]), '\n');
	}
}

// ---------- VPN kapalıyken ping için geçici test çekirdeği ----------
function testcfg() {
	if (!length(NODES)) die('hiç geçerli sunucu yok', 2);
	let inb = [], outb = [{ tag: 'direct', protocol: 'freedom' }], R = [];
	for (let n in NODES) {
		let o = outbound(n);
		if (!o) continue;
		push(outb, o);
		push(inb, { tag: 't-' + n._tag, listen: '127.0.0.1', port: n._tport, protocol: 'socks', settings: { udp: false } });
		push(R, { inboundTag: ['t-' + n._tag], outboundTag: n._tag });
	}
	print(sprintf('%.J\n', { log: { loglevel: 'none' }, inbounds: inb, outbounds: outb, routing: { rules: R } }));
}

// ---------- tek sunucunun outbound'u (düzenleme ekranı ve kayıt öncesi doğrulama) ----------
function one_outbound(n) {
	let errs = [];
	n = prep_node(n, errs);
	let res = { errors: errs, outbound: null, test: null };
	if (n) {
		n._tag = 'node-001';
		let o = outbound(n);
		if (o) {
			res.outbound = o;
			res.test = { log: { loglevel: 'warning' }, outbounds: [o, { tag: 'direct', protocol: 'freedom' }] };
		}
	}
	print(sprintf('%.J\n', res));
	exit(length(errs) ? 3 : 0);
}

// ---------- Diğer çekirdekler: sing-box ve mihomo ----------
// Aynı sunucu / uygulama / DNS modelinden, çekirdeğe göre ayrı yapılandırma üretir (Xray'in yaptığının karşılığı).
// Çekirdeğin desteklemediği bir şey (ör. sing-box'ta xhttp) uyarı olarak yazılır ve o parça atlanır.
function cwarn(msg) { warn('kediray: ' + msg + '\n'); }
function aslist(v) { return v == null ? [] : (type(v) == 'array' ? v : [v]); }

// Sunucuyu çekirdekten bağımsız bir tanıma çevir (form alanları ya da Xray outbound JSON'u).
function spec(n) {
	let j = n._json, s = { tag: n._tag, name: n.remarks || n['.name'] };
	if (j) {
		let st = j.settings || {}, tg = st.vnext?.[0] || st.servers?.[0] || st, u = st.vnext?.[0]?.users?.[0] || {};
		let ss = j.streamSettings || {}, ts = ss.tlsSettings || {}, rs = ss.realitySettings || {};
		s.proto = j.protocol; s.addr = tg.address; s.port = int(tg.port);
		s.uuid = u.id; s.flow = u.flow; s.cipher = u.security;
		s.password = tg.password; s.method = tg.method;
		s.net = ss.network || 'tcp';
		if (s.net == 'raw') s.net = 'tcp';
		if (s.net == 'websocket') s.net = 'ws';
		s.tls = ss.security || 'none';
		let rl = (s.tls == 'reality');
		s.sni = rl ? rs.serverName : ts.serverName;
		s.fp = rl ? rs.fingerprint : ts.fingerprint;
		s.alpn = aslist(ts.alpn);
		s.insecure = (ts.allowInsecure === true);
		s.pin = n.pin || ts.pinnedPeerCertSha256;
		s.pbk = rs.publicKey; s.sid = rs.shortId;
		if (s.net == 'ws') { s.path = ss.wsSettings?.path; s.host = ss.wsSettings?.host || ss.wsSettings?.headers?.Host; }
		else if (s.net == 'httpupgrade') { s.path = ss.httpupgradeSettings?.path; s.host = ss.httpupgradeSettings?.host; }
		else if (s.net == 'xhttp') { s.path = ss.xhttpSettings?.path; s.host = ss.xhttpSettings?.host; s.mode = ss.xhttpSettings?.mode; }
		else if (s.net == 'grpc') s.svc = ss.grpcSettings?.serviceName;
		else if (s.net == 'tcp' && ss.tcpSettings?.header?.type == 'http') s.htype = 'http';
	} else {
		s.proto = n.protocol; s.addr = n.address; s.port = int(n.port);
		s.uuid = n.uuid; s.flow = n.flow; s.cipher = n.cipher; s.password = n.password; s.method = n.method;
		s.net = n.network || 'tcp';
		if (s.net == 'raw') s.net = 'tcp';
		s.tls = n.tls || 'none';
		s.sni = n.sni; s.fp = n.fp; s.alpn = L(n.alpn, /[ \t\r\n,]+/);
		s.insecure = (n.insecure == '1'); s.pin = n.pin;
		s.pbk = n.pbk; s.sid = n.sid;
		s.path = n.path; s.host = n.host; s.svc = n.service_name; s.mode = n.xhttp_mode;
		if (n.header_type == 'http') s.htype = 'http';
	}
	if (s.ech || n.ech) cwarn('ECH bu çekirdekte desteklenmiyor, ECH olmadan bağlanılıyor: ' + s.name);
	// IP ile bağlan (alan adı SNI/Host olarak kalır): Xray ile aynı kural
	let ip = by_ip(s.addr);
	s.server = ip || s.addr;
	if (!s.host && ip && s.net != 'grpc') s.host = s.addr;
	if (s.tls != 'none' && !s.sni) s.sni = s.host || s.addr;
	return s;
}

// Xray tarzı alan adı girdisini (domain:/full:/keyword:/regexp:) çekirdek anahtarlarına ayır
function dsplit(lst) {
	let r = { domain: [], domain_suffix: [], domain_keyword: [], domain_regex: [] };
	for (let d in lst) {
		let m = match(d, /^([a-z]+):(.*)$/);
		if (!m) { push(r.domain_suffix, d); continue; }
		if (m[1] == 'domain') push(r.domain_suffix, m[2]);
		else if (m[1] == 'full') push(r.domain, m[2]);
		else if (m[1] == 'keyword') push(r.domain_keyword, m[2]);
		else if (m[1] == 'regexp') push(r.domain_regex, m[2]);
		else cwarn('bu çekirdekte desteklenmeyen alan adı biçimi atlandı: ' + d);
	}
	return r;
}
// IP girdileri: CIDR'ler kalır (maskesiz IP /32 olur); geoip:/ext: bu çekirdeklerde yok, atlanır
function cidrs(lst) {
	let out = [];
	for (let x0 in lst) {
		let x = ipn(x0);
		if (!x) continue;
		if (match(x, /^(geoip|ext):/)) { cwarn('bu çekirdekte desteklenmeyen IP listesi atlandı: ' + x); continue; }
		push(out, index(x, '/') >= 0 ? x : (is_v4(x) ? x + '/32' : x + '/128'));
	}
	return out;
}
// Uzak/direkt DNS adresini ayrıştır: tcp://8.8.8.8, https://1.1.1.1/dns-query, https+local://..., düz IP
function dsrv(addr) {
	let a = trim('' + addr), m = match(a, /^([A-Za-z0-9+-]+):\/\/(\[[0-9a-fA-F:]+\]|[^\/:]+)(:([0-9]+))?(\/[^ ]*)?$/);
	let r = { sch: null, host: null, port: null, path: null, local: false };
	if (m) { r.sch = lc(m[1]); r.host = m[2]; r.port = m[4]; r.path = m[5]; }
	else if (is_v4(a)) { r.sch = 'udp'; r.host = a; }
	else return null;
	if (match(r.sch, /\+local$/)) { r.local = true; r.sch = replace(r.sch, '+local', ''); }
	if (r.sch == 'h2') r.sch = 'https';
	if (r.sch == 'tcp-tls') r.sch = 'tls';
	if (!({ tcp: 1, udp: 1, https: 1, tls: 1, quic: 1 })[r.sch]) return null;
	return r;
}

const SB_NET = { tcp: 1, ws: 1, grpc: 1, httpupgrade: 1 };
function sb_out(s) {
	if (s.htype == 'http') { cwarn('TCP HTTP başlığı sing-box ile desteklenmiyor, sunucu atlandı: ' + s.name); return null; }
	if (!SB_NET[s.net]) { cwarn('"' + s.net + '" aktarımı sing-box ile desteklenmiyor, sunucu atlandı: ' + s.name); return null; }
	if (!PROTOS[s.proto]) return null;
	let o = { type: s.proto, tag: s.tag, server: s.server, server_port: s.port };
	if (s.proto == 'vless') { o.uuid = s.uuid; if (s.flow) o.flow = s.flow; o.packet_encoding = 'xudp'; }
	else if (s.proto == 'vmess') { o.uuid = s.uuid; o.security = s.cipher || 'auto'; o.alter_id = 0; o.packet_encoding = 'xudp'; }
	else if (s.proto == 'trojan') o.password = s.password;
	else { o.method = s.method; o.password = s.password; o.udp_over_tcp = { enabled: true, version: 2 }; }
	if (KA > 0) { o.tcp_keep_alive = KA + 's'; o.tcp_keep_alive_interval = '15s'; }
	if (s.tls != 'none') {
		let t = { enabled: true, server_name: s.sni };
		if (s.tls == 'reality') {
			t.reality = { enabled: true, public_key: s.pbk, short_id: s.sid };
			t.utls = { enabled: true, fingerprint: (s.fp && s.fp != 'none') ? s.fp : 'chrome' };
		} else if (s.fp && s.fp != 'none')
			t.utls = { enabled: true, fingerprint: s.fp };
		if (length(s.alpn)) t.alpn = s.alpn;
		if (s.pin) cwarn('sertifika sabitleme (SHA-256) sing-box ile yok, doğrulama kapatıldı: ' + s.name);
		if (s.insecure || s.pin) t.insecure = true;
		o.tls = t;
	}
	if (s.net == 'ws') {
		let w = { type: 'ws', path: s.path || '/' };
		if (s.host) w.headers = { Host: s.host };
		if (WS_EARLY) { w.max_early_data = 2048; w.early_data_header_name = 'Sec-WebSocket-Protocol'; }
		o.transport = w;
	}
	else if (s.net == 'grpc') {
		o.transport = { type: 'grpc', service_name: s.svc || '' };
		if (HB > 0) { o.transport.idle_timeout = HB + 's'; o.transport.ping_timeout = '15s'; }
	}
	else if (s.net == 'httpupgrade')
		o.transport = { type: 'httpupgrade', path: s.path || '/', host: s.host || '' };
	return o;
}

// Çekirdeğin kabul ettiği sunucular: [{ n, s, o }]
function sb_nodes() {
	let res = [];
	for (let n in NODES) {
		let s = spec(n), o = s ? sb_out(s) : null;
		if (o) push(res, { n: n, s: s, o: o });
	}
	return res;
}

function sb_tgt(t) {
	if (t == 'warp') cwarn('WARP yönlendirmesi bu çekirdekte yok, trafik VPN\'e yönlendirildi');
	if (t == 'frag') cwarn('TLS parçalama bu çekirdekte yok, trafik direkt gönderildi');
	if (t == 'proxy' || t == 'vpn' || t == 'warp') return { outbound: 'proxy' };
	if (t == 'block') return { action: 'reject' };
	return { outbound: 'direct' };
}
// Xray'deki add_match'in karşılığı: alan adı, IP ve port ayrı kurallar (her biri kendi başına eşleşir)
function sb_match(m, t) {
	let R = [], tg = sb_tgt(t), d = dsplit(filter(map(L(m.domain), dom), x => x)), ip = cidrs(L(m.ip)), pr = ranges(m.port ?? m.ports);
	for (let k in ['domain', 'domain_suffix', 'domain_keyword', 'domain_regex']) {
		if (!length(d[k])) continue;
		let r = {};
		r[k] = d[k];
		push(R, { ...r, ...tg });
	}
	if (length(ip)) push(R, { ip_cidr: ip, ...tg });
	if (length(pr)) {
		let one = [], rg = [];
		for (let x in pr) { if (x[0] == x[1]) push(one, x[0]); else push(rg, x[0] + ':' + x[1]); }
		if (length(one)) push(R, { port: one, ...tg });
		if (length(rg)) push(R, { port_range: rg, ...tg });
	}
	return R;
}

function sb_dnssrv(addr, tag, remote) {
	let a = dsrv(addr);
	if (!a) { cwarn('DNS adresi anlaşılamadı: ' + addr); return null; }
	let o = { type: a.sch, tag: tag, server: a.host };
	if (a.port) o.server_port = int(a.port);
	if (a.sch == 'https') o.path = a.path || '/dns-query';
	if (remote && !a.local) o.detour = 'proxy';
	else o.routing_mark = MARK_CORE;
	if (tag != 'direct-dns' && !is_v4(a.host) && !is_v6(a.host)) o.domain_resolver = 'direct-dns';
	return o;
}

const LOGLV = { debug: 'debug', info: 'info', warning: 'warn', error: 'error', none: 'panic' };

function singbox() {
	if (!length(NODES))
		die('hiç sunucu yok; önce link, JSON veya abonelik ekleyin', 2);
	let SN = sb_nodes();
	if (!length(SN))
		die('bu çekirdekle çalışabilecek sunucu yok (sing-box: xhttp ve TCP HTTP başlığı desteklenmez)', 2);
	let tp_port = num(opt('tproxy_port'), 12345), dns_port = num(opt('dns_port'), 15353);
	let socks_port = num(opt('socks_port'), 10808), api_port = num(opt('api_port'), 10085);
	let ok = {};
	for (let x in SN) ok[x.n._tag] = 1;
	let fb = (SEL && ok[SEL._tag]) ? SEL._tag : SN[0].n._tag;

	// --- Girişler ---
	let inb = [];
	if (CAPTURE == 'tproxy') {
		push(inb, { type: 'tproxy', tag: 'lan-in', listen: '0.0.0.0', listen_port: tp_port, network: 'tcp' });
		push(inb, { type: 'tproxy', tag: 'lan-in-udp', listen: '0.0.0.0', listen_port: tp_port + 1, network: 'udp' });
	} else
		push(inb, { type: 'redirect', tag: 'lan-in', listen: '0.0.0.0', listen_port: tp_port });
	if (DNS_ON) push(inb, { type: 'direct', tag: 'dns-in', listen: '0.0.0.0', listen_port: dns_port });
	push(inb, { type: 'socks', tag: 'socks-in', listen: '127.0.0.1', listen_port: socks_port });
	for (let x in SN)
		push(inb, { type: 'socks', tag: 't-' + x.n._tag, listen: '127.0.0.1', listen_port: x.n._tport });

	// --- Çıkışlar ---
	let outb = [{ type: 'direct', tag: 'direct' }];
	let tags = [];
	for (let x in SN) { push(outb, x.o); push(tags, x.n._tag); }
	push(outb, DISC ? { type: 'selector', tag: 'proxy', outbounds: ['direct'], default: 'direct' }
		: { type: 'selector', tag: 'proxy', outbounds: tags, default: fb, interrupt_exist_connections: false });

	// --- Yönlendirme ---
	let ins = CAPTURE == 'tproxy' ? ['lan-in', 'lan-in-udp', 'socks-in'] : ['lan-in', 'socks-in'];
	let R = [];
	if (DNS_ON) push(R, { inbound: ['dns-in'], action: 'hijack-dns' });
	if (DNS_MODE != 'off') push(R, { inbound: ins, port: [53], action: 'hijack-dns' });
	for (let x in SN) push(R, { inbound: ['t-' + x.n._tag], outbound: x.n._tag });
	// İçerik tanıma yalnızca kural eşleştirme için (hedef IP korunur; Xray'deki routeOnly gibi).
	// UDP'de (hev) kapalı: her UDP oturumuna bekleme eklemesin; tun modunda TCP de socks-in'den geldiği için orada açık.
	push(R, { inbound: CAPTURE == 'tproxy' ? ['lan-in'] : (CAPTURE == 'tun' ? ['lan-in', 'socks-in'] : ['lan-in']), action: 'sniff' });
	if (on(opt('block_doh'), false)) {
		let dd = dsplit(DOH_DOMAINS);
		push(R, { inbound: ins, domain_suffix: dd.domain_suffix, port: [443, 853], action: 'reject' });
	}
	for (let a in APPS)
		for (let r in sb_match({ domain: a.domain, ip: app_ips(a), port: a.ports }, a.route == 'vpn' ? 'proxy' : a.route == 'warp' ? 'warp' : a.route == 'frag' ? 'frag' : 'direct'))
			push(R, r);
	if (PUSH_FIX)
		for (let r in sb_match({ domain: PUSH_DOMAINS, port: PUSH_PORTS }, 'direct')) push(R, r);
	if (on(opt('ad_block'), false)) cwarn('reklam engelleme (geosite) bu çekirdekte yok, atlandı');
	for (let r0 in RULES)
		for (let r in sb_match({ domain: r0.domain, ip: r0.ip, port: r0.port }, r0.target || 'proxy'))
			push(R, r);
	push(R, { ip_is_private: true, outbound: 'direct' });

	// --- DNS ---
	let remote = opt('dns_remote', 'https://1.1.1.1/dns-query');
	if (match(remote, /^[0-9.]+$/)) remote = 'tcp://' + remote;
	let direct = dns_direct_addr('dns_direct', 0);
	let ddom = [], pdom = [];
	for (let a in APPS) for (let d in L(a.domain)) push((a.route == 'direct' || a.route == 'frag') ? ddom : pdom, dom(d));
	if (PUSH_FIX) for (let d in PUSH_DOMAINS) push(ddom, d);
	for (let r in RULES) {
		if (r.target == 'block') continue;
		for (let d in L(r.domain)) push(r.target == 'direct' ? ddom : pdom, dom(d));
	}
	pdom = filter(uniq(pdom), x => index(TDOMS, x) < 0);
	let dsv = [sb_dnssrv(remote, 'remote', true), sb_dnssrv(direct, 'direct-dns', false)];
	dsv = filter(dsv, x => x);
	let dr = [];
	let dm = (lst, srv) => {
		let d = dsplit(filter(lst, x => x));
		for (let k in ['domain', 'domain_suffix', 'domain_keyword', 'domain_regex']) {
			if (!length(d[k])) continue;
			let r = {};
			r[k] = d[k];
			push(dr, { ...r, action: 'route', server: srv });
		}
	};
	if (length(TDOMS)) dm(TDOMS, 'remote');
	if (length(pdom) && DNS_MODE != 'fast') dm(pdom, 'remote');
	if (length(ddom)) dm(uniq(ddom), 'direct-dns');

	let cfg = {
		log: { level: LOGLV[opt('log_level', 'warning')] ?? 'warn', timestamp: false },
		...(!DNS_ON ? {} : { dns: {
			servers: dsv, rules: dr,
			final: (MODE == 'list' || DNS_MODE == 'fast') ? 'direct-dns' : 'remote',
			strategy: on(opt('ipv6'), false) ? 'prefer_ipv4' : 'ipv4_only'
		} }),
		inbounds: inb,
		outbounds: outb,
		route: {
			rules: R,
			final: (MODE == 'list') ? 'direct' : 'proxy',
			default_mark: MARK_CORE,
			default_domain_resolver: { server: 'direct-dns' },
			auto_detect_interface: false
		},
		experimental: { clash_api: { external_controller: '127.0.0.1:' + api_port } }
	};
	// DNS kapalıyken bile sunucu alan adlarını çözecek bir sunucu gerekir (çıkışlar alan adıyla dial edebilir)
	if (!DNS_ON) cfg.dns = { servers: filter([sb_dnssrv(direct, 'direct-dns', false)], x => x), strategy: 'ipv4_only' };
	print(sprintf('%.J\n', cfg));
}

// VPN kapalıyken ping için geçici sing-box yapılandırması (her sunucu için ayrı SOCKS portu)
function singbox_test() {
	let SN = sb_nodes();
	if (!length(SN)) die('hiç geçerli sunucu yok', 2);
	let inb = [], outb = [{ type: 'direct', tag: 'direct' }], R = [];
	for (let x in SN) {
		push(outb, x.o);
		push(inb, { type: 'socks', tag: 't-' + x.n._tag, listen: '127.0.0.1', listen_port: x.n._tport });
		push(R, { inbound: ['t-' + x.n._tag], outbound: x.n._tag });
	}
	print(sprintf('%.J\n', { log: { level: 'panic' }, dns: { servers: filter([sb_dnssrv(dns_direct_addr('dns_direct', 0), 'direct-dns', false)], x => x) },
		inbounds: inb, outbounds: outb, route: { rules: R, default_domain_resolver: { server: 'direct-dns' } } }));
}

// ---------- mihomo (Clash.Meta) ----------
// mihomo JSON'u YAML olarak okur; bu yüzden aynı JSON üretici kullanılır.
const MH_NET = { tcp: 1, ws: 1, grpc: 1, httpupgrade: 1 };
function mh_proxy(s) {
	if (s.htype == 'http') { cwarn('TCP HTTP başlığı mihomo ile desteklenmiyor, sunucu atlandı: ' + s.name); return null; }
	if (!MH_NET[s.net]) { cwarn('"' + s.net + '" aktarımı mihomo ile desteklenmiyor, sunucu atlandı: ' + s.name); return null; }
	if (!PROTOS[s.proto]) return null;
	let p = { name: s.tag, type: (s.proto == 'shadowsocks' ? 'ss' : s.proto), server: s.server, port: s.port, udp: true };
	if (s.proto == 'vless') { p.uuid = s.uuid; if (s.flow) p.flow = s.flow; p['packet-encoding'] = 'xudp'; }
	else if (s.proto == 'vmess') { p.uuid = s.uuid; p.alterId = 0; p.cipher = s.cipher || 'auto'; p['packet-encoding'] = 'xudp'; }
	else if (s.proto == 'trojan') p.password = s.password;
	else { p.cipher = s.method; p.password = s.password; p['udp-over-tcp'] = true; p['udp-over-tcp-version'] = 2; }
	if (s.tls != 'none' && s.proto != 'shadowsocks') {
		p.tls = true;
		p.servername = s.sni;
		if (s.proto == 'trojan') p.sni = s.sni;
		if (s.tls == 'reality') {
			p['reality-opts'] = { 'public-key': s.pbk, 'short-id': s.sid || '' };
			p['client-fingerprint'] = (s.fp && s.fp != 'none') ? s.fp : 'chrome';
		} else if (s.fp && s.fp != 'none')
			p['client-fingerprint'] = s.fp;
		if (length(s.alpn)) p.alpn = s.alpn;
		if (s.pin) {
			if (match(s.pin, /^[0-9a-fA-F:]{64,95}$/)) p.fingerprint = s.pin;
			else { cwarn('sertifika sabitleme biçimi mihomo ile uyumsuz, doğrulama kapatıldı: ' + s.name); p['skip-cert-verify'] = true; }
		} else if (s.insecure)
			p['skip-cert-verify'] = true;
	}
	if (s.net == 'ws') {
		p.network = 'ws';
		p['ws-opts'] = { path: s.path || '/' };
		if (s.host) p['ws-opts'].headers = { Host: s.host };
		if (WS_EARLY) { p['ws-opts']['max-early-data'] = 2048; p['ws-opts']['early-data-header-name'] = 'Sec-WebSocket-Protocol'; }
	}
	else if (s.net == 'grpc') { p.network = 'grpc'; p['grpc-opts'] = { 'grpc-service-name': s.svc || '' }; }
	else if (s.net == 'httpupgrade') {
		p.network = 'ws';
		p['ws-opts'] = { path: s.path || '/', 'v2ray-http-upgrade': true };
		if (s.host) p['ws-opts'].headers = { Host: s.host };
	}
	return p;
}
function mh_nodes() {
	let res = [];
	for (let n in NODES) {
		let s = spec(n), p = s ? mh_proxy(s) : null;
		if (p) push(res, { n: n, s: s, p: p });
	}
	return res;
}
function mh_tgt(t) {
	if (t == 'warp') cwarn('WARP yönlendirmesi bu çekirdekte yok, trafik VPN\'e yönlendirildi');
	if (t == 'frag') cwarn('TLS parçalama bu çekirdekte yok, trafik direkt gönderildi');
	if (t == 'proxy' || t == 'vpn' || t == 'warp') return 'proxy';
	if (t == 'block') return 'REJECT';
	return 'DIRECT';
}
function mh_match(m, t) {
	let R = [], tg = mh_tgt(t), d = dsplit(filter(map(L(m.domain), dom), x => x));
	for (let x in d.domain) push(R, 'DOMAIN,' + x + ',' + tg);
	for (let x in d.domain_suffix) push(R, 'DOMAIN-SUFFIX,' + x + ',' + tg);
	for (let x in d.domain_keyword) push(R, 'DOMAIN-KEYWORD,' + x + ',' + tg);
	for (let x in d.domain_regex) push(R, 'DOMAIN-REGEX,' + x + ',' + tg);
	for (let x in cidrs(L(m.ip))) push(R, (index(x, ':') >= 0 ? 'IP-CIDR6,' : 'IP-CIDR,') + x + ',' + tg + ',no-resolve');
	for (let x in ranges(m.port ?? m.ports))
		push(R, 'DST-PORT,' + (x[0] == x[1] ? x[0] : x[0] + '-' + x[1]) + ',' + tg);
	return R;
}
// DNS adresi -> mihomo biçimi (https://host/path, tls://host, udp/tcp düz); tünelden çözülecekse '#proxy' eki
function mh_dns(addr, via) {
	let a = dsrv(addr);
	if (!a) { cwarn('DNS adresi anlaşılamadı: ' + addr); return null; }
	let hp = a.host + (a.port ? ':' + a.port : '');
	let u = a.sch == 'udp' ? hp : (a.sch == 'https' ? 'https://' + hp + (a.path || '/dns-query') : a.sch + '://' + hp);
	if (via && !a.local) u += '#proxy';
	return u;
}

function mihomo() {
	if (!length(NODES))
		die('hiç sunucu yok; önce link, JSON veya abonelik ekleyin', 2);
	let MN = mh_nodes();
	if (!length(MN))
		die('bu çekirdekle çalışabilecek sunucu yok (mihomo: xhttp ve TCP HTTP başlığı desteklenmez)', 2);
	let tp_port = num(opt('tproxy_port'), 12345), dns_port = num(opt('dns_port'), 15353);
	let socks_port = num(opt('socks_port'), 10808), api_port = num(opt('api_port'), 10085);
	let ok = {};
	for (let x in MN) ok[x.n._tag] = 1;
	let fb = (SEL && ok[SEL._tag]) ? SEL._tag : MN[0].n._tag;

	// Sunucu listesi: seçilen en başta (select grubu ilk elemanı varsayılan yapar)
	let names = [fb];
	for (let x in MN) if (x.n._tag != fb) push(names, x.n._tag);
	let proxies = map(MN, x => x.p);
	push(proxies, { name: 'dns-out', type: 'dns' });

	let lis = [];
	if (CAPTURE == 'tproxy') {
		push(lis, { name: 'lan-in', type: 'tproxy', listen: '0.0.0.0', port: tp_port, udp: false });
		push(lis, { name: 'lan-in-udp', type: 'tproxy', listen: '0.0.0.0', port: tp_port + 1, udp: true });
	} else
		push(lis, { name: 'lan-in', type: 'redir', listen: '0.0.0.0', port: tp_port });
	push(lis, { name: 'socks-in', type: 'socks', listen: '127.0.0.1', port: socks_port, udp: true });
	for (let x in MN)
		push(lis, { name: 't-' + x.n._tag, type: 'socks', listen: '127.0.0.1', port: x.n._tport, udp: false, proxy: x.n._tag });

	let R = [];
	if (DNS_MODE != 'off') push(R, 'DST-PORT,53,dns-out');
	if (on(opt('block_doh'), false))
		for (let r in mh_match({ domain: DOH_DOMAINS }, 'block')) push(R, r);
	for (let a in APPS)
		for (let r in mh_match({ domain: a.domain, ip: app_ips(a), port: a.ports }, a.route == 'vpn' ? 'proxy' : a.route))
			push(R, r);
	if (PUSH_FIX)
		for (let r in mh_match({ domain: PUSH_DOMAINS, port: PUSH_PORTS }, 'direct')) push(R, r);
	if (on(opt('ad_block'), false)) cwarn('reklam engelleme (geosite) bu çekirdekte yok, atlandı');
	for (let r0 in RULES)
		for (let r in mh_match({ domain: r0.domain, ip: r0.ip, port: r0.port }, r0.target || 'proxy'))
			push(R, r);
	for (let c in BYPASS4) push(R, 'IP-CIDR,' + c + ',DIRECT,no-resolve');
	push(R, 'MATCH,' + (MODE == 'list' ? 'DIRECT' : 'proxy'));

	// --- DNS ---
	let remote = opt('dns_remote', 'https://1.1.1.1/dns-query');
	if (match(remote, /^[0-9.]+$/)) remote = 'tcp://' + remote;
	let direct = dns_direct_addr('dns_direct', 0), direct2 = dns_direct_addr('dns_direct2', 1);
	let ddom = [], pdom = [];
	for (let a in APPS) for (let d in L(a.domain)) push((a.route == 'direct' || a.route == 'frag') ? ddom : pdom, dom(d));
	if (PUSH_FIX) for (let d in PUSH_DOMAINS) push(ddom, d);
	for (let r in RULES) {
		if (r.target == 'block') continue;
		for (let d in L(r.domain)) push(r.target == 'direct' ? ddom : pdom, dom(d));
	}
	let pol = {}, mp = (lst, srv) => {
		for (let d in uniq(filter(lst, x => x))) {
			let m = match(d, /^([a-z]+):(.*)$/);
			if (!m) { pol['+.' + d] = srv; continue; }
			if (m[1] == 'domain') pol['+.' + m[2]] = srv;
			else if (m[1] == 'full') pol[m[2]] = srv;
			else if (m[1] == 'keyword') pol['*' + m[2] + '*'] = srv;
		}
	};
	pdom = filter(uniq(pdom), x => index(TDOMS, x) < 0);
	let rem = mh_dns(remote, true), dir = mh_dns(direct, false), dir2 = (direct2 != direct) ? mh_dns(direct2, false) : null;
	let dirs = filter([dir, dir2], x => x);
	if (length(ddom)) mp(uniq(ddom), dirs);
	if (length(TDOMS)) mp(TDOMS, [rem]);
	if (length(pdom) && DNS_MODE != 'fast') mp(pdom, [rem]);
	let ns = (MODE == 'list' || DNS_MODE == 'fast') ? dirs : [rem];

	let cfg = {
		'mixed-port': 0,
		'allow-lan': true,
		'bind-address': '*',
		mode: 'rule',
		'log-level': ({ debug: 'debug', info: 'info', warning: 'warning', error: 'error', none: 'silent' })[opt('log_level', 'warning')] ?? 'warning',
		ipv6: on(opt('ipv6'), false),
		'routing-mark': MARK_CORE,
		'unified-delay': true,
		'tcp-concurrent': true,
		'geodata-mode': false,
		'external-controller': '127.0.0.1:' + api_port,
		profile: { 'store-selected': false, 'store-fake-ip': false },
		sniffer: { enable: on(opt('sniff'), true), 'parse-pure-ip': true, 'force-dns-mapping': true, 'override-destination': false,
			sniff: { TLS: { ports: [443, 8443] }, HTTP: { ports: [80, 8080] }, QUIC: { ports: [443] } } },
		listeners: lis,
		proxies: proxies,
		'proxy-groups': [DISC ? { name: 'proxy', type: 'select', proxies: ['DIRECT'] } : { name: 'proxy', type: 'select', proxies: names }],
		rules: R
	};
	if (KA > 0) { cfg['keep-alive-interval'] = 15; cfg['keep-alive-idle'] = KA; }
	if (DNS_ON && length(ns)) {
		cfg.dns = {
			enable: true, listen: '0.0.0.0:' + dns_port, ipv6: on(opt('ipv6'), false), 'enhanced-mode': 'normal',
			'use-hosts': false, 'use-system-hosts': false,
			'default-nameserver': length(filter([...WAN_DNS, direct], is_v4)) ? filter([...WAN_DNS, direct], is_v4) : ['1.1.1.1'],
			nameserver: ns,
			'proxy-server-nameserver': length(dirs) ? dirs : ['1.1.1.1'],
			'respect-rules': false
		};
		if (length(keys(pol))) cfg.dns['nameserver-policy'] = pol;
	}
	print(sprintf('%.J\n', cfg));
}

function mihomo_test() {
	let MN = mh_nodes();
	if (!length(MN)) die('hiç geçerli sunucu yok', 2);
	let lis = [], pr = [];
	for (let x in MN) {
		push(pr, x.p);
		push(lis, { name: 't-' + x.n._tag, type: 'socks', listen: '127.0.0.1', port: x.n._tport, udp: false, proxy: x.n._tag });
	}
	print(sprintf('%.J\n', { 'mixed-port': 0, mode: 'rule', 'log-level': 'silent', 'routing-mark': MARK_CORE,
		listeners: lis, proxies: pr, rules: ['MATCH,DIRECT'] }));
}

if (WHAT == 'xray') xray();
else if (WHAT == 'singbox') singbox();
else if (WHAT == 'singbox-test') singbox_test();
else if (WHAT == 'mihomo') mihomo();
else if (WHAT == 'mihomo-test') mihomo_test();
else if (WHAT == 'nft') nft();
else if (WHAT == 'dnsmasq') dnsmasq();
else if (WHAT == 'hev') hev();
else if (WHAT == 'nodes') nodes();
else if (WHAT == 'test') testcfg();
else if (WHAT == 'check') print(sprintf('%.J\n', { errors: ERRS, nodes: length(NODES) }));
else if (WHAT == 'outbound') {
	let n = raw[ARGV[1]];
	if (!n || n['.type'] != 'node') die('böyle bir sunucu yok: ' + ARGV[1]);
	one_outbound({ ...n });
}
else if (WHAT == 'outbound-json') {
	let n = null, arg = ARGV[1] ?? '';
	if (substr(arg, 0, 1) == '@') arg = fs.readfile(substr(arg, 1)) ?? '';
	try { n = json(arg); } catch (e) { n = null; }
	if (type(n) != 'object') die('aday sunucu JSON olarak okunamadı');
	one_outbound(n);
}
else die('bilinmeyen komut: ' + WHAT);
