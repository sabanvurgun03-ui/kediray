'use strict';
'require view';
'require fs';
'require ui';
'require poll';
'require dom';

/* KediRay - VPN Ayırma: hangi motor çalışsın, hangi uygulama VPN'den / direkt gitsin */

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
function runJson(args) {
	return run(args).then(r => { try { return JSON.parse(r.stdout || 'null'); } catch (e) { return null; } });
}
function outOf(r) { return ((r.stdout || '') + (r.stderr || '')).trim(); }

const PRESETS = [
	{ name: 'WhatsApp', route: 'vpn', ports: '5222', domains: ['geosite:whatsapp', 'domain:whatsapp.com', 'domain:whatsapp.net', 'domain:wa.me'], ips: ['geoip:facebook'] },
	{ name: 'Metin2', route: 'direct', ports: '11000-13999', expand: '24',
	  domains: ['domain:gameforge.com', 'domain:metin2.gameforge.com', 'domain:gameforge.io', 'domain:gameforge.net'],
	  ips: ['79.110.80.0/20', '79.110.87.192/32', '79.110.92.148/32', '79.110.90.244/32', '79.110.90.99/32', '79.110.91.96/32', '79.110.91.98/32', '79.110.92.117/32', '79.110.92.96/32', '79.110.92.97/32', '79.110.92.98/32'] },
	{ name: 'Microsoft Teams', route: 'direct', domains: ['domain:teams.microsoft.com', 'domain:teams.live.com', 'domain:teams.cloud.microsoft', 'domain:skype.com', 'domain:lync.com'], ips: ['13.107.64.0/18', '52.112.0.0/14', '52.122.0.0/15'] },
	{ name: 'YouTube', domains: ['geosite:youtube', 'domain:googlevideo.com', 'domain:ytimg.com'] },
	{ name: 'Netflix', domains: ['geosite:netflix', 'domain:nflxvideo.net', 'domain:nflximg.net'] },
	{ name: 'Telegram', domains: ['geosite:telegram'], ips: ['geoip:telegram'] },
	{ name: 'Instagram', domains: ['domain:instagram.com', 'domain:cdninstagram.com'] },
	{ name: 'Discord', dns: true, domains: ['domain:discord.com', 'domain:discord.gg', 'domain:discordapp.com', 'domain:discord.media', 'domain:discordapp.net', 'domain:discordcdn.com'] },
	{ name: 'Steam', domains: ['domain:steampowered.com', 'domain:steamcommunity.com', 'domain:steamstatic.com'] },
	{ name: 'Spotify', domains: ['domain:spotify.com', 'domain:scdn.co'] },
	{ name: 'Zoom', domains: ['domain:zoom.us', 'domain:zoom.com'] }
];

const CSS = `
.ka-card{border:1px solid rgba(128,128,128,.3);border-radius:10px;padding:14px;margin:0 0 14px}
.ka-card h3{margin:0 0 10px}
.ka-row{display:flex;align-items:center;justify-content:space-between;gap:10px;padding:8px 0;border-top:1px solid rgba(128,128,128,.18);flex-wrap:wrap}
.ka-row:first-of-type{border-top:0}
.ka-sub{opacity:.65;font-size:.85em}
.ka-tag{display:inline-block;padding:1px 8px;border-radius:10px;font-size:.78em;margin-left:8px;background:rgba(128,128,128,.25)}
.ka-on{background:#22a04b;color:#fff}
.ka-seg{display:inline-flex;border:1px solid rgba(128,128,128,.45);border-radius:6px;overflow:hidden}
.ka-seg button{border:0;background:transparent;padding:4px 14px;cursor:pointer;color:inherit}
.ka-seg button.a-vpn{background:#3b82f6;color:#fff}
.ka-seg button.a-dir{background:#e08a1e;color:#fff}
.ka-seg button.a-warp{background:#f6821f;color:#fff}
.ka-seg button.a-frag{background:#8b5cf6;color:#fff}
.ka-form{display:grid;gap:8px;max-width:520px}
.ka-form textarea,.ka-form input,.ka-form select{width:100%}
.ka-chips{display:flex;flex-wrap:wrap;gap:6px;margin-top:6px}
`;

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

return view.extend({
	load() {
		return Promise.all([runJson(['engines']), runJson(['apps']), runJson(['warp', 'status', '--json'])]);
	},

	render(data) {
		this.elEng = h('div', { 'class': 'ka-card' });
		this.elApps = h('div', { 'class': 'ka-card' });
		this.elWarp = h('div', { 'class': 'ka-card' });
		const root = h('div', {}, [
			h('style', {}, CSS),
			h('h2', {}, 'VPN Ayırma'),
			krLicBanner(),
			h('p', { 'class': 'ka-sub' }, 'Hangi VPN motorunun çalışacağını seç ve hangi uygulamaların VPN\'den, hangilerinin direkt gideceğini belirle.'),
			this.elEng, this.elWarp, this.elApps, this.buildAdd()
		]);
		this.fill(data[0], data[1], data[2]);
		poll.add(() => this.refresh(), 6);
		return root;
	},

	refresh() {
		if (this.busyNow) return Promise.resolve();
		return Promise.all([runJson(['engines']), runJson(['apps']), runJson(['warp', 'status', '--json'])]).then(d => this.fill(d[0], d[1], d[2]));
	},

	fill(engines, apps, warp) {
		this.warp = warp || {};
		this.renderEngines(engines || []);
		this.renderWarp(this.warp);
		this.renderApps(apps || []);
	},

	renderEngines(list) {
		const rows = list.map(e => h('div', { 'class': 'ka-row' }, [
			h('div', {}, [h('b', {}, e.name), h('span', { 'class': 'ka-tag' + (e.running ? ' ka-on' : '') }, e.running ? 'Çalışıyor' : 'Durdu'),
				e.id !== 'kediray' ? h('div', { 'class': 'ka-sub' }, 'servis: ' + e.id) : '']),
			h('div', {}, e.running
				? h('button', { 'class': 'btn cbi-button cbi-button-negative', 'click': ui.createHandlerFn(this, () => this.engine(e, 'stop')) }, 'Durdur')
				: h('button', { 'class': 'btn cbi-button cbi-button-action', 'click': ui.createHandlerFn(this, () => this.engine(e, 'start')) }, 'Başlat'))
		]));
		dom.content(this.elEng, [
			h('h3', {}, 'VPN motoru'),
			...rows,
			h('div', { 'class': 'ka-sub', 'style': 'margin-top:8px' }, 'Aynı anda yalnızca biri çalışır: birini başlatınca çalışan diğeri durdurulur ve açılışta da seçtiğin motor çalışır. KediRay\'de internet gelmezse otomatik geri alınır.')
		]);
	},

	engine(e, act) {
		const label = e.name;
		return new Promise(resolve => {
			ui.showModal(label + (act === 'start' ? ' başlatılsın mı?' : ' durdurulsun mu?'), [
				h('p', {}, act === 'start'
					? 'Çalışan diğer VPN motorları durdurulur ve ' + label + ' başlatılır. İnternet birkaç saniye kesilebilir.'
					: label + ' durdurulur. Başka bir motor çalışmıyorsa internet VPN\'siz (kendi hattınla) devam eder.'),
				h('div', { 'class': 'right' }, [
					h('button', { 'class': 'btn', 'click': () => { ui.hideModal(); resolve(); } }, 'Vazgeç'), ' ',
					h('button', { 'class': 'btn cbi-button cbi-button-action', 'click': () => { resolve(this.runEngine(e, act)); } }, 'Evet')
				])
			]);
		});
	},

	runEngine(e, act) {
		this.busyNow = true;
		const out = h('pre', { 'style': 'max-height:260px;overflow:auto;white-space:pre-wrap;font-size:.85em' }, 'Başlatılıyor…');
		const close = h('button', { 'class': 'btn', 'disabled': true, 'click': () => { ui.hideModal(); this.busyNow = false; this.refresh(); } }, 'Kapat');
		ui.showModal(e.name + (act === 'start' ? ' başlatılıyor…' : ' durduruluyor…'), [
			h('p', {}, 'İşlem arka planda sürüyor; bu sayfa donarsa birkaç saniye bekle.'), out, h('div', { 'class': 'right' }, close)
		]);
		let fails = 0;
		const poll1 = () => run(['engine-log']).then(r => {
			fails = 0;
			const lines = (r.stdout || '').split('\n'), st = lines.shift() || '';
			out.textContent = lines.join('\n').trim();
			out.scrollTop = out.scrollHeight;
			if (/^DONE/.test(st)) {
				out.textContent += '\n\n' + (st === 'DONE 0' ? 'Tamamlandı ✔' : 'Hata ile bitti (' + st.slice(5) + ')');
				close.disabled = false;
			} else setTimeout(poll1, 2000);
		}).catch(() => { if (++fails < 10) setTimeout(poll1, 2500); else { close.disabled = false; } });
		return run(['engine-bg', e.id, act]).then(r => {
			if (r.code !== 0) { out.textContent = outOf(r) || 'Başlatılamadı'; close.disabled = false; return; }
			setTimeout(poll1, 1500);
		});
	},

	renderWarp(w) {
		const reg = !!w.registered;
		const via = h('select', { 'change': ui.createHandlerFn(this, ev => this.app(['warp', 'via', ev.target.value])) }, [
			h('option', { 'value': 'vpn' }, 'VPN sunucusunun içinden (önerilen)'), h('option', { 'value': 'direct' }, 'Doğrudan hattan')]);
		via.value = w.via || 'vpn';
		dom.content(this.elWarp, [
			h('h3', {}, 'Cloudflare WARP'),
			h('div', { 'class': 'ka-sub' }, 'Seçtiğin uygulamaların çıkışı Cloudflare WARP olur: site seni VPN sunucusunun değil Cloudflare\'in IP\'si olarak görür. Her uygulamanın yanındaki "WARP" düğmesiyle seçilir.'),
			h('div', { 'class': 'ka-row' }, [
				h('div', {}, [h('b', {}, 'Durum'), h('span', { 'class': 'ka-tag' + (reg && w.enabled ? ' ka-on' : '') }, !reg ? 'Hesap yok' : (w.enabled ? 'Açık' : 'Kapalı'))]),
				h('div', { 'style': 'display:flex;gap:8px;flex-wrap:wrap' }, !reg
					? [h('button', { 'class': 'btn cbi-button cbi-button-action', 'click': ui.createHandlerFn(this, () => this.warpRegister()) }, 'WARP hesabı oluştur')]
					: [h('button', { 'class': 'btn cbi-button', 'click': ui.createHandlerFn(this, () => this.app(['warp', w.enabled ? 'off' : 'on'])) }, w.enabled ? 'Kapat' : 'Aç'),
						h('button', { 'class': 'btn cbi-button cbi-button-negative', 'click': ui.createHandlerFn(this, () => this.app(['warp', 'forget'])) }, 'Hesabı sil')])
			]),
			reg ? h('div', { 'class': 'ka-row' }, [h('div', {}, 'WARP bağlantı yolu'), via]) : ''
		]);
	},

	warpRegister() {
		ui.showModal('WARP hesabı oluşturuluyor…', [h('p', { 'class': 'spinning' }, 'Cloudflare\'e kaydolunuyor, 30 sn kadar sürebilir')]);
		return run(['warp', 'register']).then(r => {
			ui.hideModal();
			if (r.code !== 0) ui.addNotification(null, h('p', {}, outOf(r) || 'Kayıt başarısız'), 'error');
			return this.refresh();
		});
	},

	renderApps(apps) {
		const rows = apps.map(a => h('div', { 'class': 'ka-row', 'style': a.enabled ? '' : 'opacity:.55' }, [
			h('div', {}, [h('b', {}, a.name),
				h('div', { 'class': 'ka-sub' }, [a.ports ? 'port ' + a.ports : '', a.ips ? ' · ' + a.ips + ' IP bloğu' : '', a.domains ? ' · ' + a.domains + ' alan adı' : ''].join('').replace(/^ · /, ''))]),
			h('div', { 'style': 'display:flex;gap:8px;align-items:center;flex-wrap:wrap' }, [
				h('div', { 'class': 'ka-seg' }, [
					h('button', { 'title': 'VPN: Bu uygulamanın trafiği VPN tünelinden çıkar. Operatör ne yaptığını görmez, siteler seni VPN sunucusunun IP\'siyle görür. Tünel koparsa bağlantı da kopar.', 'class': a.route === 'vpn' ? 'a-vpn' : '', 'click': ui.createHandlerFn(this, () => a.route !== 'vpn' && this.app(['app', a.sec, 'vpn'])) }, 'VPN'),
					h('button', { 'title': 'Direkt: Tünele girmez, doğrudan hattan çıkar. En düşük ping; VPN yeniden başlasa bile bağlantı kopmaz. Siteler seni operatörün IP\'siyle görür (oyun ve görüntülü görüşme için uygun).', 'class': a.route === 'direct' ? 'a-dir' : '', 'click': ui.createHandlerFn(this, () => a.route !== 'direct' && this.app(['app', a.sec, 'direct'])) }, 'Direkt'),
					h('button', { 'title': 'Parçala: Direkt çıkar (VPN yok, ping düşük) ama TLS el sıkışması parçalanır; operatörün site adı (SNI) engelini aşabilir. IP\'n operatörün IP\'si kalır.', 'class': a.route === 'frag' ? 'a-frag' : '', 'click': ui.createHandlerFn(this, () => a.route !== 'frag' && this.app(['app', a.sec, 'frag'])) }, 'Parçala'),
					(this.warp && this.warp.registered) || a.route === 'warp' ? h('button', { 'title': 'WARP: Çıkış Cloudflare WARP ağından olur; siteler seni VPN sunucusunun değil Cloudflare\'in IP\'siyle görür. VPN sunucusunun IP\'sini engelleyen siteler için.', 'class': a.route === 'warp' ? 'a-warp' : '', 'click': ui.createHandlerFn(this, () => a.route !== 'warp' && this.app(['app', a.sec, 'warp'])) }, 'WARP') : ''
				]),
				h('button', { 'class': 'btn cbi-button' + (a.tunnel_dns ? ' cbi-button-action' : ''), 'title': a.tunnel_dns ? 'DNS: tünel: Bu uygulamanın alan adları tünel içinden çözülür; yanlış ya da engelli adres geliyorsa işe yarar. Tıkla: normale döndür.' : 'DNS: normal: Bu uygulamanın alan adları normal DNS ayarınla çözülür. Tıkla: tünel DNS\'ine al (Discord gibi DNS\'i bozulan uygulamalar için).',
					'click': ui.createHandlerFn(this, () => this.app(['app', a.sec, 'dns', a.tunnel_dns ? 'off' : 'on'])) }, a.tunnel_dns ? 'DNS: tünel ✔' : 'DNS: normal'),
				h('button', { 'class': 'btn cbi-button', 'title': 'Bir ad yaz (örn. discord.com): yönlendirici çözer, ilgili ve alt alan adlarını listeler, seçtiklerin bu uygulamaya eklenir. Uygulamanın bazı adresleri kurala girmiyorsa kullan.', 'click': ui.createHandlerFn(this, () => this.finder(a)) }, 'Alan adı bul'),
				h('button', { 'class': 'btn cbi-button', 'title': a.enabled ? 'Kapat: Bu uygulama kuralını geçici kapatır (silinmez); trafik genel kurala göre gider.' : 'Aç: Bu uygulama kuralını yeniden etkinleştirir.', 'click': ui.createHandlerFn(this, () => this.app(['app', a.sec, a.enabled ? 'off' : 'on'])) }, a.enabled ? 'Kapat' : 'Aç'),
				h('button', { 'class': 'btn cbi-button cbi-button-negative', 'title': 'Sil: Bu uygulama kuralını kalıcı olarak siler.', 'click': ui.createHandlerFn(this, () => this.delApp(a)) }, 'Sil')
			])
		]));
		const have = new Set(apps.map(a => (a.name || '').toLowerCase()));
		const chips = PRESETS.filter(p => !have.has(p.name.toLowerCase())).map(p =>
			h('button', { 'class': 'btn cbi-button', 'click': ui.createHandlerFn(this, () => this.preset(p)) }, '+ ' + p.name));
		dom.content(this.elApps, [
			h('h3', {}, 'Uygulamalar (' + apps.length + ')'),
			...rows,
			chips.length ? h('div', { 'class': 'ka-sub', 'style': 'margin-top:10px' }, 'Hazır uygulamalar:') : '',
			chips.length ? h('div', { 'class': 'ka-chips' }, chips) : '',
			h('div', { 'class': 'ka-sub', 'style': 'margin-top:8px' }, 'Direkt: çekirdekte bypass, VPN yeniden başlasa bile bağlantı kopmaz.')
		]);
	},

	async app(args) {
		const r = await run(args);
		if (r.code !== 0) ui.addNotification(null, h('p', {}, outOf(r) || 'İşlem başarısız'), 'error');
		return this.refresh();
	},

	delApp(a) {
		return new Promise(resolve => {
			ui.showModal(a.name + ' silinsin mi?', [
				h('p', {}, 'Bu uygulama kuralı kalıcı olarak silinir.'),
				h('div', { 'class': 'right' }, [
					h('button', { 'class': 'btn', 'click': () => { ui.hideModal(); resolve(); } }, 'Vazgeç'), ' ',
					h('button', { 'class': 'btn cbi-button cbi-button-negative', 'click': () => { ui.hideModal(); resolve(this.app(['app-del', a.sec])); } }, 'Sil')
				])
			]);
		});
	},

	// Alan adı bulucu: adı yaz -> yönlendirici çözer, ilgili/alt alan adlarını listeler -> seçilenler eklenir.
	// onAdd(seçilen alan adları dizisi) -> Promise
	finder(a, onAdd) {
		const inp = h('input', { 'type': 'text', 'placeholder': 'ör. discord.com', 'style': 'width:100%' });
		const res = h('div', { 'style': 'margin:10px 0;max-height:300px;overflow:auto' });
		const have = new Set(a ? (a.domain_list || []).map(x => x.replace(/^domain:/, '')) : []);
		let found = [];
		const add = h('button', { 'class': 'btn cbi-button cbi-button-positive', 'disabled': true });
		const search = () => {
			const v = inp.value.trim();
			if (!v) return;
			res.textContent = 'Aranıyor…'; add.disabled = true;
			return run(['domain-find', v]).then(r => {
				if (r.code !== 0) { res.textContent = outOf(r) || 'Hata'; return; }
				found = (r.stdout || '').split('\n').map(l => l.split('\t')).filter(x => x[0]);
				const rows = found.map((f, i) => {
					const ok = f[1] !== 'yok';
					const cb = h('input', { 'type': 'checkbox', 'data-d': f[0] });
					cb.disabled = !ok || have.has(f[0]);
					cb.checked = ok && !have.has(f[0]) && (f[1] === 'ana' || f[1] === 'ilgili');
					return h('label', { 'style': 'display:flex;gap:8px;align-items:center;padding:3px 0' }, [cb, h('span', {}, f[0]),
						h('span', { 'class': 'ka-tag' }, have.has(f[0]) ? 'listede' : f[1] === 'ana' ? 'ana alan adı' : f[1] === 'ilgili' ? 'ilgili hizmet' : f[1] === 'yok' ? 'çözülemedi' : 'alt alan adı')]);
				});
				dom.content(res, rows.length ? rows : 'Sonuç yok');
				add.disabled = !found.some(f => f[1] !== 'yok');
			});
		};
		add.textContent = 'Seçilenleri listeye ekle';
		add.addEventListener('click', ui.createHandlerFn(this, () => {
			const sel = Array.from(res.querySelectorAll('input[type=checkbox]')).filter(c => c.checked && !c.disabled).map(c => c.getAttribute('data-d'));
			ui.hideModal();
			// ana alan adı "domain:" ile eklenir: alt alan adlarının hepsini kapsar
			const base = sel.filter(d => !sel.some(o => o !== d && d.endsWith('.' + o)));
			return a ? this.addDomains(a, base) : onAdd(base);
		}));
		inp.addEventListener('keydown', ev => { if (ev.key === 'Enter') { ev.preventDefault(); search(); } });
		ui.showModal('Alan adı bul' + (a ? ' — ' + a.name : ''), [
			h('p', { 'class': 'ka-sub' }, 'Uygulamanın bilinen bir adresini yaz; ana alan adı, yaygın alt alan adları ve (biliniyorsa) ilgili hizmetlerin adları aranır. "domain:" kaydı alt alan adlarını da kapsar.'),
			h('div', { 'style': 'display:flex;gap:8px' }, [inp, h('button', { 'class': 'btn cbi-button cbi-button-action', 'click': ui.createHandlerFn(this, search) }, 'Bul')]),
			res,
			h('div', { 'class': 'right' }, [h('button', { 'class': 'btn', 'click': ui.hideModal }, 'Vazgeç'), ' ', add])
		]);
		inp.focus();
	},

	async addDomains(a, list) {
		for (const d of list) {
			const r = await run(['app', a.sec, 'add-domain', d]);
			if (r.code !== 0) ui.addNotification(null, h('p', {}, outOf(r) || 'Eklenemedi: ' + d), 'error');
		}
		return this.refresh();
	},

	preset(p) {
		return this.app(['app-add', p.name, p.route || 'vpn', p.ports || '', (p.domains || []).join(','), (p.ips || []).join(','), p.dns ? 'dns' : '', p.expand || '']);
	},

	buildAdd() {
		const name = h('input', { 'type': 'text', 'placeholder': 'Uygulama / oyun adı' });
		const route = h('select', {}, [h('option', { 'value': 'vpn' }, 'VPN'), h('option', { 'value': 'direct' }, 'Direkt'), h('option', { 'value': 'warp' }, 'WARP (Cloudflare)'), h('option', { 'value': 'frag' }, 'Direkt + TLS parçala (SNI engeli)')]);
		const ports = h('input', { 'type': 'text', 'placeholder': 'Portlar (boşlukla): 5222 11000-13999' });
		const doms = h('textarea', { 'rows': 3, 'placeholder': 'Alan adları (satır ya da virgülle): example.com, domain:foo.net, geosite:youtube' });
		const ips = h('textarea', { 'rows': 2, 'placeholder': 'IP / CIDR (satır ya da virgülle): 79.110.80.0/20' });
		const clean = s => s.value.split(/[\n,]+/).map(x => x.trim()).filter(x => x).join(',');
		const dns = h('input', { 'type': 'checkbox' });
		const find = h('button', { 'class': 'btn cbi-button', 'click': ui.createHandlerFn(this, () => this.finder(null, list => {
			const cur = clean(doms);
			doms.value = (cur ? cur + ',' : '') + list.map(d => 'domain:' + d).join(',');
		})) }, 'Alan adı bul…');
		const btn = h('button', { 'class': 'btn cbi-button cbi-button-positive', 'click': ui.createHandlerFn(this, () => {
			if (!name.value.trim()) { ui.addNotification(null, h('p', {}, 'Bir ad yaz.'), 'error'); return; }
			return this.app(['app-add', name.value.trim(), route.value, ports.value.trim(), clean(doms), clean(ips), dns.checked ? 'dns' : '']).then(() => {
				name.value = ports.value = doms.value = ips.value = ''; dns.checked = false;
			});
		}) }, 'Ekle');
		return h('div', { 'class': 'ka-card' }, [
			h('h3', {}, 'Yeni uygulama ekle'),
			h('div', { 'class': 'ka-form' }, [name, route, ports, doms, h('div', {}, find), ips,
				h('label', { 'style': 'display:flex;gap:8px;align-items:center' }, [dns, 'Alan adlarını tünel DNS\'iyle çöz (DNS\'i bozulan uygulamalar için)']),
				h('div', {}, btn)])
		]);
	},

	handleSaveApply: null,
	handleSave: null,
	handleReset: null
});
