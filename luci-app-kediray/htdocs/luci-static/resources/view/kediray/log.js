'use strict';
'require view';
'require view.kediray.i18n as i18n';
'require ui';
'require fs';
'require poll';
'require dom';

/* KediRay - Günlük (hatalar ayrı ve kalıcı, akış seviye/bileşene göre süzülür) */

// Tarayıcıda saklanan eski menüyü (Hizmetler altındaki kayıt) bir kez temizle
try {
	if (!sessionStorage.getItem('kediray-menu-v2')) {
		sessionStorage.setItem('kediray-menu-v2', '1');
		if (ui.menu && ui.menu.flushCache) ui.menu.flushCache();
	}
} catch (e) {}

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
const LEVELS = { error: 'Hata', warn: 'Uyarı', info: 'Bilgi', debug: 'Ayıklama' };
const RANK = { error: 0, warn: 1, info: 2, debug: 3 };
const FILTERS = [['error', 'sadece hatalar'], ['warn', 'uyarı ve üstü'], ['info', 'bilgi ve üstü'], ['debug', 'hepsi (ayıklama dahil)']];

const CSS = `
.kl-desc{opacity:.8;margin:4px 0 14px}
.kl-sec{margin:18px 0 8px;font-size:1.25em}
.kl-row{display:flex;gap:10px;flex-wrap:wrap;align-items:center;margin:8px 0}
.kl-row label{opacity:.85}
.kl-err{border:1px solid rgba(210,63,63,.45);border-left:4px solid #d23f3f;border-radius:8px;padding:9px 12px;margin:8px 0;background:rgba(210,63,63,.06)}
.kl-err-h{display:flex;gap:8px;flex-wrap:wrap;align-items:baseline}
.kl-err-t{color:#e05252;font-weight:700}
.kl-fix{margin:6px 0 2px}
.kl-fix b{opacity:.85}
.kl-err details{margin-top:4px}
.kl-err pre,.kl-raw{white-space:pre-wrap;word-break:break-all;font-size:12px;margin:4px 0 0;opacity:.85}
.kl-badge{display:inline-block;padding:0 7px;border-radius:9px;font-size:.78em;font-weight:600;background:rgba(128,128,128,.18)}
.kl-cnt{font-size:.8em;opacity:.8}
.kl-time{font-variant-numeric:tabular-nums;opacity:.7;font-size:.85em}
.kl-stream{max-height:62vh;overflow:auto;border-radius:8px;background:rgba(128,128,128,.07);padding:6px 4px;font-family:ui-monospace,Menlo,Consolas,monospace;font-size:12.5px}
.kl-line{display:grid;grid-template-columns:84px 70px 130px 1fr;gap:8px;padding:3px 8px;border-bottom:1px solid rgba(128,128,128,.12);align-items:start}
.kl-line:last-child{border-bottom:0}
.kl-line.kl-lv-error{color:#e05252}
.kl-line.kl-lv-warn{color:#d9962b}
.kl-line.kl-lv-debug{opacity:.6}
.kl-lvb{display:inline-block;min-width:58px;text-align:center;border-radius:6px;font-size:.85em;font-weight:700;padding:0 4px}
.kl-lvb.error{background:rgba(210,63,63,.2);color:#e05252}
.kl-lvb.warn{background:rgba(230,160,20,.2);color:#d9962b}
.kl-lvb.info{background:rgba(42,125,225,.15);color:#5b9be8}
.kl-lvb.debug{background:rgba(128,128,128,.18)}
.kl-comp{opacity:.8;overflow:hidden;text-overflow:ellipsis;white-space:nowrap}
.kl-msg{word-break:break-word}
.kl-empty{font-style:italic;opacity:.75;padding:8px}
.kl-sum{display:flex;gap:6px;flex-wrap:wrap}
@media(max-width:700px){.kl-line{grid-template-columns:70px 1fr}.kl-line .kl-comp,.kl-line .kl-lvw{display:none}}
`;

function fmtTime(t, ts) {
	if (t == null) return ts || '';
	const d = new Date(t), n = new Date();
	const hm = d.toLocaleTimeString(i18n.locale(), { hour: '2-digit', minute: '2-digit', second: '2-digit' });
	return d.toDateString() === n.toDateString() ? hm : d.toLocaleDateString(i18n.locale(), { day: '2-digit', month: '2-digit' }) + ' ' + hm;
}

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

return view.extend({
	level: 'info',
	comp: '',
	data: null,

	load() {
		try { this.hideEof = localStorage.getItem('kediray-log-hideeof') === '1'; this.level = localStorage.getItem('kediray-log-level') || 'info'; this.comp = localStorage.getItem('kediray-log-comp') || ''; } catch (e) {}
		return fs.exec(CLI, ['logs']).then(r => { try { return JSON.parse(r.stdout); } catch (e) { return null; } }).catch(() => null);
	},

	async act(args) {
		await fs.exec(CLI, args).catch(() => null);
		this.update(await this.load());
	},

	skipEof(e) {
		return !!this.hideEof && /EOF/.test(String(e.title || '') + ' ' + String(e.text || '') + ' ' + String(e.raw || ''));
	},

	renderErrors(errs) {
		errs = (errs || []).filter(e => !this.skipEof(e));
		if (!errs.length)
			return h('p', { 'class': 'kl-empty' }, 'Kayıtlı hata yok.');
		return errs.map(e => h('div', { 'class': 'kl-err' }, [
			h('div', { 'class': 'kl-err-h' }, [
				h('span', { 'class': 'kl-err-t' }, e.title || e.text),
				h('span', { 'class': 'kl-badge' }, e.comp),
				e.count > 1 ? h('span', { 'class': 'kl-cnt' }, '×' + e.count) : '',
				h('span', { 'class': 'kl-time' }, e.count > 1 && e.first ? fmtTime(e.first) + ' – ' + fmtTime(e.last, e.ts) : fmtTime(e.last, e.ts))
			]),
			e.fix ? h('div', { 'class': 'kl-fix' }, [h('b', {}, 'Ne yapmalı: '), e.fix]) : '',
			h('details', {}, [h('summary', {}, 'Çıktı'), h('pre', {}, e.raw || e.text)])
		]));
	},

	renderStream(ents) {
		const lim = RANK[this.level] ?? 2;
		const rows = (ents || []).filter(e => (RANK[e.level] ?? 2) <= lim && (!this.comp || e.comp === this.comp) && !this.skipEof(e));
		if (!rows.length) return h('div', { 'class': 'kl-empty' }, 'Bu filtrelere uyan kayıt yok.');
		// Aynı hata/uyarı birden fazla geçtiyse tek satırda "×N" ile birleştir (bağlantı numarası [123456] yok sayılır);
		// satır son tekrarın yerinde durur, saat aralığı yanında yazılır. Bilgi/ayıklama satırları olduğu gibi kalır.
		const grouped = e => e.level === 'error' || e.level === 'warn';
		const plain = e => String(e.text == null ? '' : e.text).replace(/\[[0-9]{5,}\]\s*/g, '');
		const gkey = e => e.level + '|' + e.comp + '|' + (e.title || '') + '|' + plain(e);
		const grp = {};
		rows.forEach(e => {
			if (!grouped(e)) return;
			const k = gkey(e), g = grp[k] || (grp[k] = { n: 0, first: e });
			g.n++; g.last = e;
		});
		return rows.filter(e => !grouped(e) || grp[gkey(e)].last === e).map(e => {
			const g = grouped(e) ? grp[gkey(e)] : null, multi = !!g && g.n > 1;
			return h('div', { 'class': 'kl-line kl-lv-' + e.level, 'title': e.fix ? 'Ne yapmalı: ' + e.fix : null }, [
				h('span', { 'class': 'kl-time' }, fmtTime(e.t, e.ts)),
				h('span', { 'class': 'kl-lvw' }, h('span', { 'class': 'kl-lvb ' + e.level }, LEVELS[e.level] || e.level)),
				h('span', { 'class': 'kl-comp' }, e.comp),
				h('span', { 'class': 'kl-msg' }, [
					e.title ? h('b', {}, e.title + ': ') : '', multi ? plain(e) : e.text,
					multi ? [' ', h('span', { 'class': 'kl-cnt' }, '×' + g.n), ' ',
						h('span', { 'class': 'kl-time' }, fmtTime(g.first.t, g.first.ts) + ' – ' + fmtTime(e.t, e.ts))] : ''
				])
			]);
		});
	},

	update(d) {
		if (!d) return;
		this.data = d;
		// bileşen listesini güncel tut
		const comps = Array.from(new Set((d.entries || []).map(e => e.comp))).sort();
		const cur = this.comp;
		dom.content(this.selComp, [h('option', { 'value': '' }, 'tüm bileşenler'),
			...comps.map(c => h('option', { 'value': c, 'selected': c === cur ? '' : null }, c))]);
		if (cur && !comps.includes(cur)) this.selComp.appendChild(h('option', { 'value': cur, 'selected': '' }, cur));

		const cnt = { error: 0, warn: 0, info: 0 };
		(d.entries || []).forEach(e => { if (cnt[e.level] != null) cnt[e.level]++; });
		dom.content(this.elSum, [
			h('span', { 'class': 'kl-lvb error' }, cnt.error + ' hata'),
			h('span', { 'class': 'kl-lvb warn' }, cnt.warn + ' uyarı'),
			h('span', { 'class': 'kl-lvb info' }, cnt.info + ' bilgi')
		]);

		dom.content(this.elErrs, this.renderErrors(d.errors));
		const box = this.elStream;
		const atBottom = box.scrollHeight - box.scrollTop - box.clientHeight < 40;
		dom.content(box, this.renderStream(d.entries));
		if (atBottom || !this.scrolled) { box.scrollTop = box.scrollHeight; this.scrolled = true; }
	},

	render(d) {
		this.selLevel = h('select', { 'class': 'cbi-input-select', 'change': ev => {
			this.level = ev.target.value;
			try { localStorage.setItem('kediray-log-level', this.level); } catch (e) {}
			dom.content(this.elStream, this.renderStream(this.data && this.data.entries));
		} }, FILTERS.map(([v, l]) => h('option', { 'value': v, 'selected': v === this.level ? '' : null }, l)));
		this.selComp = h('select', { 'class': 'cbi-input-select', 'change': ev => {
			this.comp = ev.target.value;
			try { localStorage.setItem('kediray-log-comp', this.comp); } catch (e) {}
			dom.content(this.elStream, this.renderStream(this.data && this.data.entries));
		} });
		this.elErrs = h('div', {});
		this.elStream = h('div', { 'class': 'kl-stream' });
		this.elSum = h('div', { 'class': 'kl-sum' });

		const view = h('div', {}, [
			h('style', {}, CSS),
			h('h2', {}, [h('img', { 'src': '/luci-static/kedi-logo.svg', 'style': 'height:1.3em;vertical-align:-0.25em;margin-right:8px;border-radius:6px' }), 'Günlük']),
			h('label', { 'class': 'kl-row' }, [h('input', { 'type': 'checkbox', 'checked': this.hideEof ? '' : null, 'change': ev => { this.hideEof = ev.target.checked; try { localStorage.setItem('kediray-log-hideeof', this.hideEof ? '1' : '0'); } catch (e) {} this.update(this.data); } }), ' EOF hatalarını gizle']),
			h('p', { 'class': 'kl-desc' }, 'Yalnızca bellekte tutulur, flash belleğe hiçbir şey yazılmaz. Kaynak: sistem günlüğü (logread) — KediRay, Xray çekirdeği ve UDP tüneli (hev). Xray\'in bağlantı ayrıntıları için Ayarlar → Gelişmiş → Günlük seviyesi: info.'),

			h('h3', { 'class': 'kl-sec' }, 'Hatalar'),
			h('p', { 'class': 'kl-desc' }, 'Aşağıdaki akıştan daha uzun süre saklanır; aynı hata tekrarlanırsa tek kartta sayılır. Her kartta çıktı ve ne yapılması gerektiği vardır.'),
			h('div', { 'class': 'kl-row' }, h('button', { 'class': 'btn cbi-button cbi-button-negative', 'click': ui.createHandlerFn(this, () => this.act(['logs', 'clear-errors'])) }, 'Temizle')),
			this.elErrs,

			h('h3', { 'class': 'kl-sec' }, 'Akış'),
			h('div', { 'class': 'kl-row' }, [
				h('label', {}, 'Düzey'), this.selLevel,
				h('label', {}, 'Bileşen'), this.selComp,
				h('button', { 'class': 'btn cbi-button', 'click': () => { this.elStream.scrollTop = this.elStream.scrollHeight; } }, 'En alta git'),
				h('button', { 'class': 'btn cbi-button cbi-button-negative', 'click': ui.createHandlerFn(this, () => this.act(['logs', 'clear-stream'])) }, 'Akışı temizle'),
				this.elSum
			]),
			this.elStream
		]);

		this.update(d || { entries: [], errors: [] });
		poll.add(() => this.load().then(x => this.update(x)), 5);
		return view;
	},

	handleSaveApply: null,
	handleSave: null,
	handleReset: null
});
