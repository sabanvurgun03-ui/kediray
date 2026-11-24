'use strict';
'require baseclass';
'require fs';
'require ui';
'require dom';

/* KediRay - Bağlantı testi: cihazların açık bağlantıları ve her birinin gerçekte hangi yoldan çıktığı.
 * mihomo / sing-box'ta çekirdeğin kendi bağlantı listesinden (alan adı, eşleşen kural, çıkış) okunur; Xray'de modemin
 * bağlantı tablosundan. Bir uygulama kuralıyla eşleşen bağlantı kuralın yolundan gitmiyorsa "Yanlış yol" diye işaretlenir.
 * Kontrol paneli, Trafik ve VPN Ayırma sayfaları ortak kullanır. */

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
function runJson(args) {
	return fs.exec(CLI, args).then(r => { try { return JSON.parse(r.stdout || 'null'); } catch (e) { return null; } }).catch(() => null);
}

(function css() {
	if (document.getElementById('kc-style')) return;
	const st = document.createElement('style');
	st.id = 'kc-style';
	st.textContent = `
.modal.kc-wide{max-width:min(1150px,97vw)!important;width:97vw!important}
.kc-bar{display:flex;flex-wrap:wrap;gap:8px;align-items:center;margin:0 0 10px}
.kc-bar select{max-width:100%}
.kc-sum{display:flex;flex-wrap:wrap;gap:6px 14px;margin:0 0 8px;font-weight:600}
.kc-sub{opacity:.75;font-size:.88em;line-height:1.45;margin:0 0 8px}
.kc-wrap{overflow-x:auto;-webkit-overflow-scrolling:touch;max-height:60vh;overflow-y:auto}
.kc-t{width:100%;border-collapse:collapse;font-size:.9em}
.kc-t th,.kc-t td{padding:5px 8px;text-align:left;border-bottom:1px solid rgba(128,128,128,.18);vertical-align:top}
.kc-t th{position:sticky;top:0;background:var(--background-color-high,#fff);z-index:1;white-space:nowrap}
.kc-t td.kc-h{max-width:260px;overflow-wrap:anywhere}
.kc-p{display:inline-block;padding:1px 8px;border-radius:10px;font-size:.85em;font-weight:600;white-space:nowrap}
.kc-d{background:rgba(34,163,85,.18);color:#1b8a47}.kc-v{background:rgba(42,125,225,.16);color:#1f63b8}
.kc-b{background:rgba(128,128,128,.18)}.kc-x{background:rgba(210,63,63,.18);color:#b52f2f}
.kc-t tr.kc-bad td{background:rgba(210,63,63,.07)}
.kc-s{opacity:.7;font-size:.85em}
@media (max-width:640px){.kc-t{font-size:.82em}.kc-t th,.kc-t td{padding:4px 5px}.kc-hide{display:none}}
`;
	document.head.appendChild(st);
})();

const ROUTE = { direct: 'Direkt', frag: 'Direkt', vpn: 'VPN', warp: 'VPN (WARP)', block: 'Engel' };

function pill(c) {
	if (c.via === 'direct') return h('span', { 'class': 'kc-p kc-d' }, 'Direkt');
	if (c.via === 'block') return h('span', { 'class': 'kc-p kc-b' }, 'Engel');
	return h('span', { 'class': 'kc-p kc-v', 'title': c.out ? 'Çıkış: ' + c.out : '' }, 'VPN');
}
function verdict(c) {
	if (c.bad) return h('span', { 'class': 'kc-p kc-x', 'title': 'Kurala göre ' + (ROUTE[c.want] || c.want) + ' gitmeliydi' }, '✖ ' + (ROUTE[c.want] || c.want) + ' olmalı');
	if (c.want) return h('span', { 'class': 'kc-p kc-d' }, '✔ Doğru');
	return h('span', { 'class': 'kc-s' }, '—');
}

return baseclass.extend({
	/* opts: { ip: cihaz IP'si (boş = tüm cihazlar), sec: başta seçili uygulama, title, directApps: [{sec,name}], onDirect(sec, c) } */
	show(opts) {
		opts = opts || {};
		const body = h('div', {}, h('p', { 'class': 'spinning' }, 'Bağlantılar okunuyor…'));
		ui.showModal((opts.title || 'Bağlantı testi') + ' — ' + (opts.ip || 'tüm cihazlar'), [
			body,
			h('div', { 'class': 'right' }, [
				h('button', { 'class': 'btn cbi-button cbi-button-action', 'click': () => this.load(body, opts) }, 'Yenile'), ' ',
				h('button', { 'class': 'btn', 'click': ui.hideModal }, 'Kapat')
			])
		], 'kc-wide');
		this.filter = opts.sec ? 'app:' + opts.sec : (opts.badOnly ? 'bad' : 'all');
		return this.load(body, opts);
	},

	load(body, opts) {
		dom.content(body, h('p', { 'class': 'spinning' }, 'Bağlantılar okunuyor…'));
		return Promise.all([
			runJson(['conns', opts.ip || '', '--json']),
			opts.ip ? Promise.resolve(null) : runJson(['devices'])
		]).then(([list, devs]) => {
			this.list = Array.isArray(list) ? list : [];
			this.names = {};
			(Array.isArray(devs) ? devs : []).forEach(d => { if (d.ip) this.names[d.ip] = d.name || d.ip; });
			this.draw(body, opts);
		});
	},

	draw(body, opts) {
		const list = this.list, all = !opts.ip;
		const src = list.length ? list[0].src : '';
		const apps = [];
		const seen = {};
		list.forEach(c => { if (c.sec && !seen[c.sec]) { seen[c.sec] = 1; apps.push({ sec: c.sec, name: c.app }); } });
		if (opts.sec && !seen[opts.sec]) apps.unshift({ sec: opts.sec, name: opts.appName || opts.sec });
		const sel = h('select', { 'class': 'cbi-input-select', 'change': ev => { this.filter = ev.target.value; this.draw(body, opts); } }, [
			h('option', { 'value': 'all' }, 'Tüm bağlantılar'),
			h('option', { 'value': 'bad' }, 'Yalnız yanlış yoldakiler'),
			h('option', { 'value': 'apps' }, 'Uygulamayla eşleşenler'),
			...apps.map(a => h('option', { 'value': 'app:' + a.sec }, a.name))
		]);
		sel.value = this.filter;
		if (sel.value !== this.filter) { this.filter = 'all'; sel.value = 'all'; }
		const f = this.filter;
		const rows = list.filter(c => f === 'all' || (f === 'bad' && c.bad) || (f === 'apps' && c.want) || (f.startsWith('app:') && c.sec === f.slice(4)));
		const nBad = list.filter(c => c.bad).length, nApp = list.filter(c => c.want).length;
		const api = src === 'api';
		const direct = (opts.directApps || []);
		const dsel = h('select', { 'class': 'cbi-input-select' }, direct.map(a => h('option', { 'value': a.sec }, a.name)));

		const head = [all ? 'Cihaz' : null, 'Uygulama', 'Hedef', 'Port', 'Yol', 'Durum', api ? 'Kural' : null, 'Adet', direct.length && opts.onDirect ? '' : null].filter(x => x !== null);
		const tr = rows.slice(0, 300).map(c => h('tr', { 'class': c.bad ? 'kc-bad' : '' }, [
			all ? h('td', {}, c.client ? (this.names[c.client] || c.client) : h('span', { 'class': 'kc-s', 'title': 'Cihaz bulunamadı: modemin kendi bağlantısı ya da kapanmak üzere olan bir bağlantı olabilir' }, '?')) : null,
			h('td', {}, c.app || h('span', { 'class': 'kc-s' }, '—')),
			h('td', { 'class': 'kc-h', 'title': c.dst || '' }, [c.host || c.dst || '?', c.host && c.dst ? h('div', { 'class': 'kc-s' }, c.dst) : '']),
			h('td', {}, [String(c.port), h('div', { 'class': 'kc-s' }, c.proto)]),
			h('td', {}, [pill(c), c.via === 'vpn' && c.out ? h('div', { 'class': 'kc-s kc-hide' }, c.out) : '']),
			h('td', {}, verdict(c)),
			api ? h('td', { 'class': 'kc-h kc-s' }, c.rule || '—') : null,
			h('td', {}, String(c.n)),
			direct.length && opts.onDirect ? h('td', {}, c.via === 'vpn' && !c.web && c.want !== 'vpn' && c.want !== 'warp'
				? h('button', { 'class': 'btn cbi-button cbi-button-action', 'title': 'Bu sunucuyu (aynı /24 komşularıyla) ve portunu seçili Direkt uygulamaya ekler',
					'click': ui.createHandlerFn(this, () => opts.onDirect(dsel.value, c)) }, 'Direkt yap')
				: '') : null
		].filter(x => x !== null)));

		dom.content(body, [
			h('div', { 'class': 'kc-sum' }, [
				h('span', {}, list.length + ' bağlantı'),
				h('span', {}, nApp + ' tanesi uygulama kuralıyla eşleşti'),
				h('span', { 'style': nBad ? 'color:#b52f2f' : 'color:#1b8a47' }, nBad ? nBad + ' tanesi yanlış yolda ✖' : 'yanlış yolda giden yok ✔')
			]),
			h('p', { 'class': 'kc-sub' }, !list.length
				? 'Şu an açık bağlantı yok. Denemek istediğin uygulamayı aç ve kullan (ör. aramayı başlat, videoyu oynat), sonra "Yenile"ye bas.'
				: (api
					? 'Kaynak: çekirdeğin kendi bağlantı listesi. "Yol" bağlantının gerçekte hangi çıkıştan gittiğini, "Kural" hangi kuralın eşleştiğini gösterir.'
					: 'Kaynak: modemin bağlantı tablosu (Xray). Alan adı görünmez: uygulamalar yalnız IP ve port kurallarıyla tanınır; yalnız alan adıyla tanımlı uygulamaların bağlantıları "Uygulama" sütununda boş kalabilir.')
				+ (list.length && list[0].own ? ' Çekirdek ayarı modu açık: KediRay uygulama kuralları kullanılmadığı için doğru/yanlış denetimi yapılmaz; yönü kendi dosyandaki kurallar belirler.' : '')),
			h('div', { 'class': 'kc-bar' }, [h('label', {}, 'Göster:'), sel,
				direct.length && opts.onDirect ? [h('label', {}, 'Direkt yap → eklenecek uygulama:'), dsel] : '']),
			rows.length
				? h('div', { 'class': 'kc-wrap' }, h('table', { 'class': 'kc-t' }, [h('tr', {}, head.map(x => h('th', {}, x))), ...tr]))
				: (list.length ? h('p', { 'class': 'kc-sub' }, 'Bu seçimde bağlantı yok. Uygulamayı kullanırken "Yenile"ye bas.') : ''),
			rows.length > 300 ? h('p', { 'class': 'kc-sub' }, 'İlk 300 satır gösteriliyor.') : ''
		]);
	}
});
