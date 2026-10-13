'use strict';
// KediRay günlük okuyucu: sistem günlüğünden KediRay / Xray / hev satırlarını seviye ve bileşene ayırır,
// bilinen hatalara Türkçe açıklama + "ne yapmalı" ekler, hataları ayrıca (bellekte) daha uzun süre saklar.
//   ucode logs.uc read <ubus-json|logread-metni> [--text]  -> { entries, errors }
//   ucode logs.uc clear-errors | clear-stream
const fs = require('fs');
const RUN = getenv('KR_RUN') || '/var/etc/kediray';
const ERRF = RUN + '/errors.json';
const SINCEF = RUN + '/log.since';
const CMD = ARGV[0];
const now_ms = () => time() * 1000;

function out(x) { print(sprintf('%J\n', x)); }
function readj(p, d) { try { let t = fs.readfile(p); return t ? json(t) : d; } catch (e) { return d; } }
function writej(p, v) { fs.mkdir(RUN); fs.writefile(p + '.tmp', sprintf('%J', v)); fs.rename(p + '.tmp', p); }

if (CMD == 'clear-errors') { writej(ERRF, { cleared: now_ms(), last_id: readj(ERRF, {}).last_id ?? 0, items: [] }); out({ ok: true }); exit(0); }
if (CMD == 'clear-stream') { fs.writefile(SINCEF, '' + now_ms()); out({ ok: true }); exit(0); }

// ---------- bilinen hatalar: başlık + ne yapmalı ----------
const HINTS = [
	[/connection reset by peer/, 'Bağlantı karşı taraftan sıfırlandı',
	 'Operatör ya da ağ, VPN sunucusuna açılan bağlantıyı kesti. Ara sıra olursa normaldir (mobil hatlarda sık görülür). Sık tekrarlanıyorsa sunucunun IP/SNI\'si engelleniyor olabilir: farklı port, SNI ya da sunucu dene. Oyun/arama bu anlarda koparsa o uygulamayı "Direkt" yap.'],
	[/(i\/o timeout|dial tcp [^ ]+: .*timeout|connect: connection timed out)/, 'Sunucuya ulaşılamadı (zaman aşımı)',
	 'Sunucu kapalı, IP\'si değişmiş ya da hat bu adresi engelliyor olabilir. Kontrol Paneli\'nden "Ping" ile ölç; çalışmıyorsa aboneliği güncelle ya da başka sunucu seç.'],
	[/connection refused/, 'Sunucu bağlantıyı reddetti',
	 'Sunucu açık ama o portta dinleyen yok. x-ui\'de inbound\'un açık ve portun doğru olduğunu kontrol et.'],
	[/app\/dns.*Post "https:.*(context deadline exceeded|timeout)/, 'Direkt DNS (DoH) yanıt vermedi',
	 'Türkiye\'ye direkt çıkan adresler için kullanılan DoH sunucusuna ulaşılamadı; 5G/mobil hatlarda sık olur. Adres yedek DNS ile çözülür ama sorgu birkaç saniye gecikir. Sürekli oluyorsa Ayarlar → DNS → "Direkt DNS (yedek)" zaten devrede; ilk sırayı değiştirmek için "Direkt DNS" alanına https+local://8.8.8.8/dns-query yaz.'],
	[/(failed to dial to|failed to dial).*> *EOF/, 'Sunucu el sıkışma sırasında bağlantıyı kapattı (EOF)',
	 'VPN sunucusu ya da önündeki ters vekil/CDN, bağlantıyı daha el sıkışma bitmeden kapattı. Sık oluyorsa: sunucunun WebSocket path/host değerlerini x-ui ile karşılaştır, sunucu yükünü kontrol et, ya da ikinci bir sunucu ekle (biri takılınca otomatik diğerine geçer). Bu anlarda açılan yeni bağlantılar başarısız olur; telefonun bildirim bağlantısı da o an kopabilir.'],
	[/app\/dns.*(context deadline exceeded|timeout|i\/o timeout)/, 'DNS sorgusu zamanında yanıtlanmadı',
	 'Tünel o an yavaş ya da takılı. "Tünel takılırsa önbellekten yanıt ver" açıkken daha önce çözülmüş adresler etkilenmez. Sık görülüyorsa Ayarlar → DNS\'te "Cloudflare DoH" seçmeyi dene.'],
	[/failed to read response length/, 'DNS-over-TCP bağlantısı kapandı',
	 'Karşı taraf boştaki DNS bağlantısını kapattı. Bu satır görünüyorsa "Uzak DNS" TCP\'dedir: Ayarlar → DNS → Uzak DNS → "Cloudflare DoH" seç. Gerçek hatta doğrulandı: TCP\'de bağlantı düşünce sorgu ölüyor ve sayfa askıda kalıyor, DoH kendi içinde yeniden deniyor.'],
	[/(pinnedPeerCertSha256|peer cert is unrecognized)/, 'Sunucunun sertifikası değişmiş',
	 'Sabitlenen sertifika artık sunucuda değil (panel/sertifika yenilenmiş). KediRay bir sonraki başlatmada otomatik yeniden sabitler; hemen düzeltmek için panelde Bağlı sunucu → \"🔒 Sertifikayı sabitle\" (ya da: kediray pin)'],
	[/(x509|certificate (is not valid|signed by unknown)|failed to verify certificate)/, 'Sunucunun sertifikası doğrulanamadı',
	 'Sunucu kendinden imzalı ya da başka ada ait sertifika kullanıyor. Sunucuyu düzenle → "Sertifikayı doğrulama" işaretle; KediRay sertifikayı sabitler.'],
	[/(REALITY|reality).*(invalid|failed|verif)/, 'REALITY el sıkışması başarısız',
	 'Public key / short id / SNI sunucuyla uyuşmuyor. Linki x-ui\'den yeniden kopyalayıp sunucuyu düzenle.'],
	[/(bad handshake|unexpected (HTTP )?status|websocket: .*40[0-9])/, 'WebSocket el sıkışması reddedildi',
	 'Path ya da Host yanlış, veya sunucunun önündeki CDN/ters vekil isteği geri çevirdi. Linkteki path ve host değerlerini x-ui ile karşılaştır.'],
	[/(tls: handshake failure|remote error: tls|tls: .*EOF|first record does not look like a TLS)/, 'TLS el sıkışması başarısız',
	 'SNI/ALPN sunucuyla uyuşmuyor, sunucu TLS kullanmıyor ya da operatör bu el sıkışmasını engelliyor. Linkteki security/SNI ayarını kontrol et.'],
	[/(invalid user|invalid request user id|not a valid user)/, 'Kullanıcı (UUID/parola) geçersiz',
	 'Hesap sunucudan silinmiş ya da süresi dolmuş olabilir. x-ui\'de kullanıcının açık olduğunu kontrol et, aboneliği güncelle.'],
	[/failed to find an available destination/, 'Hiçbir bağlanma denemesi başarılı olmadı',
	 'Asıl sebep yukarıdaki ayrıntıda (en sağdaki kısım). Sunucuya erişim yoksa internet VPN\'den gidemez.'],
	[/too many open files/, 'Açık dosya sınırı aşıldı', 'Modemi yeniden başlat; sürekli oluyorsa bağlantı sayısı çok yüksek demektir.'],
	[/yapılandırma testi başarısız/, 'Xray bir ayarı kabul etmedi',
	 'Kontrol Paneli → "✓ Ayarları denetle" hatalı alanı ve satırı gösterir. Son değiştirdiğin sunucu/kuralı düzelt.'],
	[/Yapılandırma üretilemedi/, 'Yapılandırma üretilemedi', 'Kontrol Paneli → "✓ Ayarları denetle" ile hatalı sunucuyu bul.'],
	[/TUN aygıtını/, 'UDP tüneli (hev) başlamadı',
	 'hev-socks5-tunnel kurulu mu? SSH: apk add hev-socks5-tunnel kmod-tun (opkg ile de olur). Olmazsa Ayarlar → Trafik yakalama → TPROXY seç.'],
	[/kural yüklemedi|kuralları yüklenemedi/, 'Güvenlik duvarı kuralı yüklenemedi',
	 'SSH\'ta "fw4 check" çalıştır: /etc/nftables.d içindeki bozuk bir dosya tüm güvenlik duvarını durdurur.'],
	[/sertifika alınamadı/, 'Sunucunun sertifikası alınamadı',
	 'openssl-util kurulu mu (apk add openssl-util)? Sunucu açık ve adres doğru mu?'],
	[/abonelik (indirilemedi|boş)/, 'Abonelik güncellenemedi', 'Abonelik linkini tarayıcıda açıp çalıştığını kontrol et; VPN kapalıyken de erişilebilmeli.'],
	[/socks5 client (connect|socket)/, 'UDP tüneli Xray\'e bağlanamadı',
	 'Xray çalışmıyor ya da SOCKS portu değişmiş. VPN\'i yeniden başlat; sürmezse Günlük\'teki Xray hatalarına bak.'],
	[/çekirdeği bulunamadı/, 'Xray çekirdeği yok', 'SSH: kediray update-core'],
	[/API yanıt vermedi/, 'Sunucu seçimi uygulanamadı', 'Xray yanıt vermiyor; VPN\'i yeniden başlat.']
];
function hint(text) {
	for (let hnt in HINTS) if (match(text, hnt[0])) return { title: hnt[1], fix: hnt[2] };
	return null;
}

// ---------- satır ayrıştırma ----------
const LV = { Error: 'error', Warning: 'warn', Info: 'info', Debug: 'debug', E: 'error', W: 'warn', I: 'info', D: 'debug' };

function comp_of(tag, text) {
	if (tag == 'kediray') return 'KediRay';
	if (tag == 'hev') return 'UDP tüneli';
	if (match(text, /^app\/dns/)) return 'DNS';
	if (match(text, /^(transport\/internet|proxy\/(vless|vmess|trojan|shadowsocks|freedom)|app\/proxyman\/outbound|common\/retry)/)) return 'Sunucu bağlantısı';
	if (match(text, /^app\/observatory/)) return 'Sağlık ölçümü';
	if (match(text, /^(app\/proxyman\/inbound|proxy\/(dokodemo|socks)|from [0-9])/)) return 'Giriş';
	if (match(text, /^app\/router/)) return 'Yönlendirme';
	return 'Xray';
}

function summarize(text) {
	// "a/b: x > c/d: y > z" -> "x → z" (ilk ve son halka)
	let segs = map(split(text, ' > '), s => trim(replace(s, /^[a-z0-9_]+(\/[a-z0-9_.-]+)+: /, '')));
	segs = filter(segs, s => length(s));
	if (length(segs) <= 1) return segs[0] ?? text;
	let last = replace(segs[length(segs) - 1], /^(read|write|dial) (tcp|udp) [^ ]+: /, '');
	return segs[0] + ' → ' + last;
}

function parse(msg, prio, t, id, ts) {
	let m = match(msg, /^([A-Za-z0-9_.-]+)(\[[0-9]+\])?: ?(.*)$/s);
	if (!m) return null;
	let tag = m[1], rest = m[3], level = 'info', text = rest;
	if (tag == 'hev-socks5-tunnel') tag = 'hev';
	if (tag != 'kediray' && tag != 'xray' && tag != 'hev') return null;
	if (tag == 'xray') {
		let x = match(rest, /^[0-9]{4}\/[0-9]{2}\/[0-9]{2} [0-9:.]+ (\[(Error|Warning|Info|Debug)\] )?(.*)$/s);
		if (x) { text = x[3]; level = x[2] ? LV[x[2]] : 'info'; }
		else if (match(rest, /^(Failed to start|panic|fatal)/i)) level = 'error';
		// her başlangıçta çıkan kullanım dışı uyarıları bilgi seviyesine indir
		if (level == 'warn' && match(text, /deprecated|will be removed|Please (migrate|update)/)) level = 'info';
		if (match(text, /^Xray [0-9.]+ started$/)) level = 'info';
	} else if (tag == 'hev') {
		let x = match(rest, /^\[[^\]]+\] \[([EWID])\] (0x[0-9a-f]+ )?(.*)$/s);
		if (x) { level = LV[x[1]]; text = x[3]; }
	} else {
		let sev = prio != null ? (prio & 7) : 6;
		level = sev <= 3 ? 'error' : (sev == 4 ? 'warn' : (sev == 7 ? 'debug' : 'info'));
	}
	let h = (level == 'error' || level == 'warn') ? hint(text) : null;
	return { id: id, t: t, ts: ts, level: level, comp: comp_of(tag, text), text: tag == 'xray' ? summarize(text) : text,
		raw: text, title: h?.title, fix: h?.fix };
}

// ---------- oku ----------
if (CMD != 'read') { warn('kullanım: logs.uc read <dosya> [--text] | clear-errors | clear-stream\n'); exit(1); }
const src = fs.readfile(ARGV[1]) ?? '';
let ents = [];
if (ARGV[2] != '--text') {
	let j = null;
	try { j = json(src); } catch (e) { j = null; }
	for (let e in (j?.log ?? []))
		push(ents, parse(e.msg ?? '', e.priority, e.time, e.id, null));
} else {
	// logread metni: "Wed Sep 30 08:44:46 2026 daemon.info xray[12040]: ..."
	let n = 0;
	for (let l in split(src, '\n')) {
		let m = match(l, /^([A-Z][a-z]{2} [A-Z][a-z]{2} +[0-9]+ [0-9:]+ [0-9]{4}) [a-z]+\.([a-z]+) (.*)$/);
		if (!m) continue;
		let sev = { emerg: 0, alert: 1, crit: 2, err: 3, warn: 4, warning: 4, notice: 5, info: 6, debug: 7 }[m[2]] ?? 6;
		push(ents, parse(m[3], sev, null, ++n, m[1]));
	}
}
ents = filter(ents, e => e);

// Hatalar: bellekte kalıcı, aynı hata gruplanır (sayaç + ilk/son zaman)
let st = readj(ERRF, { cleared: 0, last_id: 0, items: [] });
let byKey = {};
for (let it in st.items) byKey[it.key] = it;
let maxid = st.last_id ?? 0;
let restarted = length(ents) && ents[length(ents) - 1].id != null && ents[length(ents) - 1].id < maxid;
for (let e in ents) {
	if (e.level != 'error') continue;
	if (e.t != null && e.t <= (st.cleared ?? 0)) continue;
	if (e.id != null && !restarted && e.id <= maxid) continue;
	let key = e.comp + '|' + replace(replace(e.title ?? e.text, /[0-9]+(\.[0-9]+){3}(:[0-9]+)?/g, '#'), /[0-9]+/g, '#');
	let it = byKey[key];
	if (!it) {
		it = byKey[key] = { key: key, first: e.t, count: 0, comp: e.comp, title: e.title, fix: e.fix };
		push(st.items, it);
	}
	it.count++;
	it.last = e.t;
	it.ts = e.ts;
	it.text = e.text;
	it.raw = e.raw;
}
for (let e in ents) if (e.id != null && e.id > maxid) maxid = e.id;
st.last_id = maxid;
st.items = slice(sort(st.items, (a, b) => (b.last ?? 0) - (a.last ?? 0)), 0, 100);
writej(ERRF, st);

const since = int(fs.readfile(SINCEF) ?? '0') || 0;
let stream = filter(ents, e => e.t == null || e.t > since);
if (length(stream) > 500) stream = slice(stream, length(stream) - 500);
out({ now: now_ms(), since: since, entries: stream, errors: st.items });
