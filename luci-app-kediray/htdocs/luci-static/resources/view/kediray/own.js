'use strict';
'require view';
'require view.kediray.i18n as i18n';
'require ui';
'require fs';
'require dom';

/* KediRay - Çekirdek ayarı (Neko tarzı): mihomo için Clash YAML, sing-box için JSON yapılandırma dosyaları; kendi yapılandırma modu. */

/* Güvenli öğe oluşturucu: dizileri düzleştirir, metni her zaman düz metin olarak ekler (HTML çalışmaz) */
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
const UP = '/tmp/kediray-own-upload';

const CSS = `
.ko-desc{opacity:.8;margin:4px 0 14px;max-width:900px;line-height:1.5}
.ko-warn{border:1px solid rgba(224,168,46,.5);border-left:4px solid #e0a82e;border-radius:8px;padding:10px 14px;margin:0 0 16px;background:rgba(224,168,46,.07);max-width:900px;line-height:1.5}
.ko-tabs{display:flex;gap:8px;margin:0 0 14px;flex-wrap:wrap}
.ko-tab{border:1px solid rgba(128,128,128,.35);border-radius:999px;padding:5px 16px;cursor:pointer;background:transparent;color:inherit;font:inherit}
.ko-tab.on{background:var(--kr-accent,#2a7de1);border-color:var(--kr-accent,#2a7de1);color:#fff}
.ko-card{border:1px solid rgba(128,128,128,.25);border-radius:12px;padding:16px 18px;background:rgba(128,128,128,.04);max-width:960px;margin:0 0 14px}
.ko-row{display:flex;gap:10px;align-items:center;flex-wrap:wrap;margin:0 0 10px}
.ko-badge{display:inline-block;padding:1px 9px;border-radius:9px;font-size:.8em;font-weight:600;background:rgba(128,128,128,.18)}
.ko-badge.on{background:rgba(34,163,85,.18);color:#3fb950}
.ko-ed{width:100%;min-height:360px;font-family:monospace;font-size:.85em;line-height:1.4;white-space:pre;tab-size:2;box-sizing:border-box}
.ko-note{font-size:.85em;opacity:.75;line-height:1.45}
.ko-out{white-space:pre-wrap;word-break:break-all;margin:8px 0;font-size:.85em;background:rgba(128,128,128,.1);padding:8px 10px;border-radius:8px;max-height:220px;overflow:auto}
.ko-grp{display:flex;gap:10px;align-items:center;margin:6px 0;flex-wrap:wrap}
.ko-grp b{min-width:120px}
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
		/* Yakınlaştırma / uzaklaştırma: % değeri tarayıcıda saklanır; sağ alttaki − % + düğmeleri her KediRay sayfasında görünür */
		const zm = Math.min(160, Math.max(60, Math.round((+c.zoom || 100) / 10) * 10));
		if (zm !== 100) css += 'body #maincontent{zoom:' + (zm / 100) + '}';
		let zb = document.getElementById('kr-zoom');
		if (!zb && document.body) {
			zb = document.createElement('div'); zb.id = 'kr-zoom';
			zb.setAttribute('style', 'position:fixed;right:12px;bottom:12px;z-index:9999;display:flex;align-items:center;gap:2px;padding:3px;border-radius:999px;background:rgba(30,34,41,.88);color:#fff;box-shadow:0 2px 10px rgba(0,0,0,.35);font:600 13px system-ui,sans-serif;user-select:none');
			const mk = (t, title, fn, w) => {
				const b = document.createElement('button');
				b.type = 'button'; b.textContent = t; b.title = title;
				b.setAttribute('style', 'border:0;background:transparent;color:inherit;cursor:pointer;font:inherit;height:28px;min-width:' + w + 'px;padding:0 6px;border-radius:999px');
				b.addEventListener('click', ev => {
					ev.preventDefault();
					let cc = {}; try { cc = JSON.parse(localStorage.getItem('kediray-theme') || '{}') || {}; } catch (e) {}
					const cur = Math.min(160, Math.max(60, Math.round((+cc.zoom || 100) / 10) * 10));
					cc.zoom = fn(cur);
					try { localStorage.setItem('kediray-theme', JSON.stringify(cc)); } catch (e) {}
					krTheme();
				});
				zb.appendChild(b); return b;
			};
			mk('\u2212', 'Uzaklaştır', z => Math.max(60, z - 10), 28);
			mk('100%', 'Sıfırla (%100)', () => 100, 52).id = 'kr-zoom-val';
			mk('+', 'Yakınlaştır', z => Math.min(160, z + 10), 28);
			(() => {
				const tb = document.createElement('button');
				const lab = m => { tb.textContent = m === 'dark' ? '🌙' : (m === 'light' ? '☀️' : '◐'); tb.title = 'Tema: ' + (m === 'dark' ? 'Koyu' : (m === 'light' ? 'Açık\u200b' : 'Otomatik')) + ' (değiştirmek için tıkla)'; };
				const cur = () => { let cc = {}; try { cc = JSON.parse(localStorage.getItem('kediray-theme') || '{}') || {}; } catch (e) {} return (cc.mode === 'dark' || cc.mode === 'light') ? cc.mode : 'auto'; };
				tb.type = 'button';
				tb.setAttribute('style', 'border:0;background:transparent;color:inherit;cursor:pointer;font:inherit;height:28px;min-width:28px;padding:0 6px;border-radius:999px');
				tb.addEventListener('click', ev => {
					ev.preventDefault();
					let cc = {}; try { cc = JSON.parse(localStorage.getItem('kediray-theme') || '{}') || {}; } catch (e) {}
					const m = cur(), n = m === 'auto' ? 'dark' : (m === 'dark' ? 'light' : 'auto');
					cc.mode = n;
					try { localStorage.setItem('kediray-theme', JSON.stringify(cc)); } catch (e) {}
					lab(n); krTheme();
				});
				lab(cur()); zb.appendChild(tb);
			})();
			document.body.appendChild(zb);
		}
		const zv = document.getElementById('kr-zoom-val');
		if (zv) zv.textContent = zm + '%';
		st.textContent = css;
		document.documentElement.setAttribute('data-krt', mode);
	} catch (e) {}
}
krTheme();

/* Genel efektler: tüm KediRay sayfalarında (tek sefer eklenir). Mavi/yeşil düğmeler nefes alır gibi parlar, kartlar yumuşak belirir, giriş alanları odakta parlar. */
(function () {
	if (document.getElementById('kr-fx-css')) return;
	const st = document.createElement('style');
	st.id = 'kr-fx-css';
	st.textContent = `
@keyframes krIn{from{opacity:0;transform:translateY(8px)}to{opacity:1;transform:none}}
@keyframes krFade{from{opacity:0}to{opacity:1}}
@keyframes krBtnB{0%,100%{box-shadow:0 0 3px color-mix(in srgb,var(--kr-accent,#2a7de1) 25%,transparent)}50%{box-shadow:0 0 12px color-mix(in srgb,var(--kr-accent,#2a7de1) 70%,transparent)}}
@keyframes krBtnG{0%,100%{box-shadow:0 0 3px rgba(34,163,85,.25)}50%{box-shadow:0 0 12px rgba(34,163,85,.7)}}
@keyframes krChip{0%,100%{box-shadow:0 0 3px color-mix(in srgb,var(--kr-accent,#2a7de1) 30%,transparent)}50%{box-shadow:0 0 11px color-mix(in srgb,var(--kr-accent,#2a7de1) 70%,transparent)}}
.kr-card,.ka-card,.kr-smart,.cbi-map{animation:krIn .38s ease backwards}
.modal{animation:krFade .2s ease backwards}
.btn,.cbi-button{transition:background .2s ease,box-shadow .25s ease,border-color .2s ease,transform .12s ease,color .2s ease}
.cbi-button:not(:disabled):active{transform:scale(.97)}
.cbi-button-action:not(:disabled){animation:krBtnB 2.8s ease-in-out infinite}
.cbi-button-positive:not(:disabled){animation:krBtnG 2.8s ease-in-out infinite}
.cbi-button-action:not(:disabled):hover,.cbi-button-positive:not(:disabled):hover{animation-play-state:paused;filter:brightness(1.12)}
.cbi-button-negative:not(:disabled):hover{box-shadow:0 0 11px rgba(210,63,63,.6)}
.cbi-button:not(.cbi-button-action):not(.cbi-button-positive):not(.cbi-button-negative):not(:disabled):hover{box-shadow:0 0 8px rgba(128,128,128,.4)}
.cbi-input-text,.cbi-input-select,.cbi-dropdown,input[type=text],input[type=number],input[type=password],select,textarea{transition:box-shadow .2s ease,border-color .2s ease}
.cbi-input-text:focus,.cbi-input-select:focus,input[type=text]:focus,input[type=number]:focus,input[type=password]:focus,select:focus,textarea:focus,.cbi-dropdown:focus-within{box-shadow:0 0 0 3px color-mix(in srgb,var(--kr-accent,#2a7de1) 35%,transparent)!important;border-color:var(--kr-accent,#2a7de1)!important;outline:0}
.kr-switch input:checked + span.kr-knob{box-shadow:0 0 9px rgba(34,163,85,.65)}
.kr-smart .ks-chip{transition:background .2s ease,border-color .2s ease,box-shadow .25s ease}
.kr-smart .ks-chip:hover{box-shadow:0 0 8px rgba(128,128,128,.45)}
.kr-smart .ks-chip.ks-on{animation:krChip 2.6s ease-in-out infinite}
.kr-smart .ks-bar>div{box-shadow:0 0 8px color-mix(in srgb,var(--kr-accent,#2a7de1) 55%,transparent)}
.cbi-tabmenu li.cbi-tab,.cbi-tabmenu li{transition:background .2s ease,box-shadow .2s ease,color .2s ease}
.cbi-tabmenu li.cbi-tab:hover{box-shadow:0 2px 0 color-mix(in srgb,var(--kr-accent,#2a7de1) 60%,transparent)}
.kr-table tr,.table .tr{transition:background .2s ease}
.kr-table tr:hover td{background:rgba(128,128,128,.07)}
@media (prefers-reduced-motion:reduce){.kr-card,.ka-card,.kr-smart,.cbi-map,.modal,.cbi-button-action,.cbi-button-positive,.kr-smart .ks-chip.ks-on{animation:none!important}}
`;
	document.head.appendChild(st);
})();


const CORES = [ ['mihomo', 'mihomo (Clash YAML)'], ['sing-box', 'sing-box (JSON)'] ];
const EXT = { 'mihomo': '.yaml', 'sing-box': '.json' };

function run(args) {
	return fs.exec(CLI, args).then(r => ({ code: r.code, out: ((r.stdout || '') + (r.stderr || '')).trim() }),
		e => ({ code: 1, out: String((e && e.message) || e) }));
}
function toast(msg, bad) { ui.addNotification(null, h('p', { 'style': 'white-space:pre-wrap' }, msg), bad ? 'error' : 'info'); }

return view.extend({
	load() {
		return Promise.all([
			run(['own-list', 'mihomo']), run(['own-list', 'sing-box']), run(['cores']), run(['core-active']), run(['dash', 'info'])
		]).then(a => {
			const j = (r, d) => { try { return JSON.parse(r.out); } catch (e) { return d; } };
			return { lists: { 'mihomo': j(a[0], { files: [] }), 'sing-box': j(a[1], { files: [] }) }, cores: j(a[2], []), active: a[3].out || 'xray', dash: j(a[4], {}) };
		});
	},

	render(d) {
		this.d = d;
		this.tab = (d.active === 'sing-box') ? 'sing-box' : 'mihomo';
		this.sel = {};
		this.root = h('div', {});
		this.draw();
		return this.root;
	},

	core(id) { return (this.d.cores || []).filter(c => c.id === id)[0] || {}; },

	draw() {
		const root = this.root;
		while (root.firstChild) root.removeChild(root.firstChild);
		root.appendChild(h('style', {}, CSS));
		root.appendChild(h('h2', {}, [h('img', { 'src': '/luci-static/kedi-logo.svg', 'style': 'height:1.3em;vertical-align:-0.25em;margin-right:8px;border-radius:6px' }), 'Çekirdek ayarı']));
		root.appendChild(h('p', { 'class': 'ko-desc' }, 'Seçtiğin çekirdeğin kendi yapılandırma dosyasıyla çalış: mihomo için Clash YAML, sing-box için JSON. Dosyayı buradan düzenler, doğrular ve seçersin. Bu modda KediRay\'in sunucu, uygulama ve cihaz ayarları kullanılmaz; trafiği dosyadaki TUN ya da redirect girişi yakalar.'));
		root.appendChild(this.dashCard());
		root.appendChild(h('div', { 'class': 'ko-tabs' }, CORES.map(c => h('button', {
			'class': 'ko-tab' + (this.tab === c[0] ? ' on' : ''), 'type': 'button',
			'click': () => { this.tab = c[0]; this.draw(); }
		}, c[1]))));
		root.appendChild(this.panel(this.tab));
	},

	/* Dashboard (MetaCubeXD): çekirdeğin kendi web arayüzü, LAN'dan açılır */
	dashCard() {
		const D = this.d.dash || {}, out = h('pre', { 'class': 'ko-out', 'style': 'display:none' });
		const say = (t, bad) => { out.style.display = t ? '' : 'none'; out.textContent = t || ''; out.style.borderLeft = bad ? '4px solid #d23f3f' : '4px solid #22a355'; };
		const host = location.hostname, port = D.port || '10085';
		const url = 'http://' + host + ':' + port + '/ui/#/setup?http=1&hostname=' + encodeURIComponent(host) + '&port=' + encodeURIComponent(port) + '&secret=' + encodeURIComponent(D.secret || '');
		const row = [h('b', {}, 'Dashboard (MetaCubeXD)'), h('span', { 'class': 'ko-badge' + (D.on ? ' on' : '') }, D.on ? 'Açık' : 'Kapalı')];
		const card = h('div', { 'class': 'ko-card' }, [h('div', { 'class': 'ko-row' }, row)]);
		if (!D.installed) {
			card.appendChild(h('div', { 'class': 'ko-note' }, 'Dashboard dosyaları kurulu değil. Kurulum dosyasını yeniden çalıştır (kediray reinstall).'));
			return card;
		}
		if (D.engine === 'xray') {
			card.appendChild(h('div', { 'class': 'ko-note' }, 'Dashboard mihomo ve sing-box için çalışır. Önce Çekirdekler sayfasından birini etkin yap.'));
			return card;
		}
		const btns = h('div', { 'class': 'ko-row' });
		if (!D.own) btns.appendChild(h('button', { 'class': 'cbi-button ' + (D.on ? 'cbi-button-negative' : 'cbi-button-positive'), 'type': 'button', 'click': ev => {
			ev.target.disabled = true; say('Uygulanıyor…');
			return run(['dash', D.on ? 'off' : 'on']).then(r => { say(r.out, r.code !== 0); return run(['dash', 'info']).then(x => { try { this.d.dash = JSON.parse(x.out); } catch (e) {} if (r.code === 0) this.draw(); else ev.target.disabled = false; }); });
		} }, D.on ? 'Dashboard\'u kapat' : 'Dashboard\'u aç'));
		if (D.on) btns.appendChild(h('a', { 'class': 'cbi-button cbi-button-action', 'href': url, 'target': '_blank', 'rel': 'noopener' }, 'Dashboard\'u aç \u2197'));
		card.appendChild(btns);
		if (D.on) card.appendChild(h('div', { 'class': 'ko-note' }, 'Adres: http://' + host + ':' + port + '/ui/   Parola: ' + (D.secret || '(yok)')));
		if (D.own && D.on && !D.lan) card.appendChild(h('div', { 'class': 'ko-warn' }, 'Dosyandaki external-controller yalnızca 127.0.0.1\'de dinliyor; LAN\'dan açılmaz. 0.0.0.0:PORT yap ve external-ui: ui satırını ekle.'));
		else if (D.own) card.appendChild(h('div', { 'class': 'ko-note' }, 'Kendi yapılandırma modunda dashboard, dosyandaki external-controller / secret / external-ui: ui ayarlarıyla çalışır (yukarıdaki adres dosyadan okunur).'));
		else card.appendChild(h('div', { 'class': 'ko-note' }, 'Açıkken çekirdeğin API\'si LAN\'a parolayla açılır. İnternete açma.'));
		card.appendChild(out);
		return card;
	},

	panel(id) {
		const L = this.d.lists[id] || { files: [] }, c = this.core(id), files = L.files || [];
		let cur = this.sel[id] || L.selected || (files[0] && files[0].name) || '';
		if (!files.some(f => f.name === cur)) cur = (files[0] && files[0].name) || '';
		this.sel[id] = cur;
		const isActiveCore = (this.d.active === id), modeOn = !!L.active;
		const ed = h('textarea', { 'class': 'cbi-input-text ko-ed', 'spellcheck': 'false', 'placeholder': files.length ? 'Yükleniyor…' : 'Dosya yok. "Sunucu listemden oluştur" ya da "Yeni" ile başla.' });
		const out = h('pre', { 'class': 'ko-out', 'style': 'display:none' });
		const say = (t, bad) => { out.style.display = t ? '' : 'none'; out.textContent = t || ''; out.style.borderLeft = bad ? '4px solid #d23f3f' : '4px solid #22a355'; };
		const load = name => {
			if (!name) { ed.value = ''; return Promise.resolve(); }
			return run(['own-get', id, name]).then(r => { ed.value = r.out; });
		};
		const save = name => {
			if (!name) return Promise.resolve({ code: 1, out: 'dosya adı yok' });
			return fs.write(UP, ed.value).then(() => run(['own-put', id, name]), e => ({ code: 1, out: 'yazılamadı: ' + ((e && e.message) || e) }));
		};
		const reload = (keep) => run(['own-list', id]).then(r => {
			try { this.d.lists[id] = JSON.parse(r.out); } catch (e) {}
			if (keep) this.sel[id] = keep;
			this.draw();
		});
		const ask = (title, label, def, cb) => {
			const inp = h('input', { 'type': 'text', 'class': 'cbi-input-text', 'value': def || '', 'style': 'width:100%' });
			ui.showModal(title, [ h('p', {}, label), inp, h('div', { 'class': 'right', 'style': 'margin-top:12px' }, [
				h('button', { 'class': 'btn cbi-button', 'click': ui.hideModal }, 'Vazgeç'), ' ',
				h('button', { 'class': 'btn cbi-button cbi-button-action', 'click': () => { const v = inp.value.trim(); ui.hideModal(); cb(v); } }, 'Tamam')
			]) ]);
			inp.focus();
		};
		const fixName = n => (n && !/\.[A-Za-z]+$/.test(n)) ? n + EXT[id] : n;

		const dd = h('select', { 'class': 'cbi-input-select', 'change': ev => { this.sel[id] = ev.target.value; load(ev.target.value); say(''); } },
			files.length ? files.map(f => h('option', { 'value': f.name, 'selected': f.name === cur ? '' : null }, f.name + (f.name === L.selected ? '  ✓ seçili' : ''))) : h('option', { 'value': '' }, '— dosya yok —'));

		const btn = (label, cls, fn) => h('button', { 'class': 'btn cbi-button ' + (cls || ''), 'type': 'button', 'click': ui.createHandlerFn(this, fn) }, label);

		const top = h('div', { 'class': 'ko-card' }, [
			h('div', { 'class': 'ko-row' }, [
				h('b', {}, id), h('span', { 'class': 'ko-badge' + (c.installed ? ' on' : '') }, c.installed ? ('Kurulu ' + (c.version || '')) : 'Kurulu değil'),
				h('span', { 'class': 'ko-badge' + (modeOn ? ' on' : '') }, modeOn ? 'Kendi yapılandırma modu AÇIK' : 'Kendi yapılandırma modu kapalı')
			]),
			!c.installed ? h('p', { 'class': 'ko-note' }, 'Önce Çekirdekler sayfasından ' + id + ' kur.') :
			(!isActiveCore ? h('p', { 'class': 'ko-note' }, 'Bu mod için ' + id + ' etkin çekirdek olmalı: Çekirdekler sayfasında "Etkin yap".') : ''),
			c.installed && isActiveCore ? h('div', { 'class': 'ko-row' }, [
				btn(modeOn ? 'Kendi yapılandırma modunu kapat' : 'Kendi yapılandırma modunu aç', modeOn ? '' : 'cbi-button-action', () => {
					if (!window.confirm(modeOn ? 'Kapatılsın mı? VPN, KediRay\'in kendi ayarlarına (sunucu listesi) döner ve birkaç saniye yeniden başlar.' : 'Kendi yapılandırma modu açılsın mı? VPN, seçili dosyayla çalışır; KediRay\'in sunucu/uygulama/cihaz ayarları kullanılmaz. Başlamazsa eski ayara dönülür.')) return;
					say('Uygulanıyor…');
					return run(['core-own', modeOn ? 'off' : 'on']).then(r => { say(r.out, r.code !== 0); return reload(); });
				})
			]) : ''
		]);

		const edit = h('div', { 'class': 'ko-card' }, [
			h('div', { 'class': 'ko-row' }, [ h('span', {}, 'Dosya:'), dd,
				btn('Yeni', '', () => ask('Yeni dosya', 'Dosya adı (' + EXT[id] + ')', 'yeni' + EXT[id], v => { v = fixName(v); if (!v) return; ed.value = ''; this.sel[id] = v; files.push({ name: v, size: 0 }); L.files = files; this.draw(); })),
				btn('Sunucu listemden oluştur', '', () => ask('Sunucu listesinden oluştur', 'Yeni dosya adı (' + EXT[id] + ')', 'kediray' + EXT[id], v => { v = fixName(v); if (!v) return; return run(['own-template', id, v]).then(r => { say(r.out, r.code !== 0); return reload(v); }); })),
				btn('Dosya yükle…', '', ev => ui.uploadFile(UP, ev.target).then(() => ask('Dosya adı', 'Kaydedilecek ad (' + EXT[id] + ')', 'yuklenen' + EXT[id], v => { v = fixName(v); return run(['own-put', id, v]).then(r => { say(r.out, r.code !== 0); return reload(v); }); }), e => { const m = (e && e.message) || String(e || ''); if (!/cancel|iptal/i.test(m)) toast('Dosya yüklenemedi: ' + m, true); }))
			]),
			ed,
			h('div', { 'class': 'ko-row', 'style': 'margin-top:10px' }, [
				btn('Kaydet', '', () => save(cur).then(r => { say(r.out, r.code !== 0); return reload(cur); })),
				btn('Doğrula', '', () => save(cur).then(r => r.code !== 0 ? (say(r.out, true)) : run(['own-check', id, cur]).then(q => say(q.out, q.code !== 0)))),
				btn('Seç (çalışacak dosya)', 'cbi-button-positive', () => save(cur).then(r => r.code !== 0 ? say(r.out, true) : run(['own-select', id, cur]).then(q => { say(q.out, q.code !== 0); return reload(cur); }))),
				btn('Uygula (yeniden başlat)', 'cbi-button-action', () => save(cur).then(() => run(['own-select', id, cur])).then(() => { say('Yeniden başlatılıyor…'); return run(['own-apply', id]); }).then(r => { say(r.out, r.code !== 0); return reload(cur); })),
				btn('Sil', 'cbi-button-negative', () => { if (!cur || !window.confirm(cur + ' silinsin mi?')) return; return run(['own-del', id, cur]).then(r => { say(r.out, r.code !== 0); return reload(); }); })
			]),
			out,
			h('p', { 'class': 'ko-note' }, id === 'mihomo'
				? 'İpucu: dosyada "tun:" (enable: true, device: …) ya da "redir-port" bulunmalı; ayrıca "external-controller" varsa aşağıdaki canlı kontrol çalışır. proxy-provider/rule-provider dosyaları /etc/kediray/own/mihomo/proxy_provider ve rule_provider klasörlerinde durur.'
				: 'İpucu: "inbounds" içinde "tun" ya da "redirect" girişi bulunmalı; "experimental.clash_api" varsa canlı kontrol çalışır.')
		]);
		load(cur);

		const parts = [top, edit];
		if (modeOn) parts.push(this.live(id));
		return h('div', {}, parts);
	},

	live(id) {
		const box = h('div', { 'class': 'ko-card' }, [ h('div', { 'class': 'ko-row' }, h('b', {}, 'Canlı kontrol')), h('p', { 'class': 'ko-note' }, 'Çekirdeğin kendi API\'sinden okunuyor…') ]);
		const draw = (groups, mode) => {
			while (box.firstChild) box.removeChild(box.firstChild);
			box.appendChild(h('div', { 'class': 'ko-row' }, h('b', {}, 'Canlı kontrol')));
			if (mode) box.appendChild(h('div', { 'class': 'ko-row' }, [ h('span', {}, 'Mod:') ].concat(['rule', 'global', 'direct'].map(m =>
				h('button', { 'class': 'btn cbi-button' + (m === mode ? ' cbi-button-action' : ''), 'type': 'button', 'click': ui.createHandlerFn(this, () => run(['own-api', 'mode', m]).then(() => this.live2(id, box, draw))) }, m)))));
			if (!groups.length) box.appendChild(h('p', { 'class': 'ko-note' }, 'Seçilebilir grup yok ya da API yanıt vermedi (dosyada external-controller / clash_api olmalı).'));
			groups.forEach(g => box.appendChild(h('div', { 'class': 'ko-grp' }, [ h('b', {}, g.name),
				h('select', { 'class': 'cbi-input-select', 'change': ev => run(['own-api', 'select', g.name, ev.target.value]).then(r => { if (r.code !== 0) toast(r.out, true); }) },
					g.all.map(n => h('option', { 'value': n, 'selected': n === g.now ? '' : null }, n))) ])));
		};
		this.live2(id, box, draw);
		return box;
	},

	live2(id, box, draw) {
		return Promise.all([ run(['own-api', 'groups']), run(['own-api', 'mode-get']) ]).then(a => {
			let groups = [];
			try {
				const p = JSON.parse(a[0].out).proxies || {};
				groups = Object.keys(p).filter(k => p[k].type === 'Selector' && Array.isArray(p[k].all)).map(k => ({ name: k, now: p[k].now, all: p[k].all }));
			} catch (e) {}
			draw(groups, (a[1].out || '').trim());
		});
	},

	handleSaveApply: null,
	handleSave: null,
	handleReset: null
});
