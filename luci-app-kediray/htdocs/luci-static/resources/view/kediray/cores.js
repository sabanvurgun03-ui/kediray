'use strict';
'require view';
'require view.kediray.i18n as i18n';
'require ui';
'require fs';
'require dom';

/* KediRay - Çekirdekler: Xray dışındaki motor ikilileri (sing-box, mihomo) için kur / dosyadan yükle / kaldır.
 * Bu sürümde yalnızca ikililer yönetilir; VPN'i Xray çalıştırmaya devam eder. */

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
const UP = '/tmp/kediray-core-upload';

const CSS = `
.kc-desc{opacity:.8;margin:4px 0 14px;max-width:900px;line-height:1.5}
.kc-warn{border:1px solid rgba(224,168,46,.5);border-left:4px solid #e0a82e;border-radius:8px;padding:10px 14px;margin:0 0 16px;background:rgba(224,168,46,.07);max-width:900px;line-height:1.5}
.kc-grid{display:grid;grid-template-columns:repeat(auto-fill,minmax(260px,1fr));gap:14px;max-width:960px}
.kc-card{border:1px solid rgba(128,128,128,.25);border-radius:12px;padding:16px 18px;background:rgba(128,128,128,.04);display:flex;flex-direction:column;gap:10px}
.kc-head{display:flex;align-items:center;gap:10px;flex-wrap:wrap}
.kc-name{font-size:1.25em;font-weight:700;margin:0}
.kc-badge{display:inline-block;padding:1px 9px;border-radius:9px;font-size:.78em;font-weight:600;background:rgba(128,128,128,.18)}
.kc-badge.on{background:rgba(34,163,85,.18);color:#3fb950}
.kc-rows{display:grid;grid-template-columns:auto 1fr;gap:6px 14px;align-items:baseline}
.kc-k{opacity:.75}
.kc-v{font-weight:600;font-variant-numeric:tabular-nums;word-break:break-all;text-align:right}
.kc-path{font-size:.8em;opacity:.65;word-break:break-all}
.kc-note{font-size:.85em;opacity:.75;line-height:1.45}
.kc-act{display:flex;gap:8px;flex-wrap:wrap;margin-top:auto}
.kc-log{max-height:260px;overflow:auto;white-space:pre-wrap;word-break:break-all;margin:8px 0;font-size:.85em;background:rgba(128,128,128,.1);padding:8px 10px;border-radius:8px}
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

function fmtSize(n) {
	n = Number(n) || 0;
	if (n <= 0) return '—';
	return (n / 1048576).toFixed(1) + ' MB';
}

const KIND = { kediray: 'KediRay klasörü', system: 'Sistem paketi' };
const NOTES = {
	'xray': 'Ana çekirdek: VPN şu an bununla çalışıyor.',
	'sing-box': 'Modemin paket deposundan kurulur (apk ya da opkg). Paketin kendi servisi kapalı tutulur.',
	'mihomo': 'GitHub\'daki MetaCubeX/mihomo son sürümünden indirilir (arm64 ve armv7). İndirme sağlama toplamıyla doğrulanmaz; güvenmiyorsan kendin indirip "Dosya yükle…" ile yükle.'
};

return view.extend({
	load() {
		return fs.exec(CLI, ['cores']).then(r => {
			try { return JSON.parse(r.stdout || '[]'); } catch (e) { return []; }
		}).catch(() => []);
	},

	runJob(args, title) {
		const msg = h('p', {}, 'Bu işlem birkaç dakika sürebilir; sayfayı kapatma.');
		const pre = h('pre', { 'class': 'kc-log' }, 'Başlatılıyor…');
		const closeBtn = h('button', { 'class': 'btn cbi-button', 'disabled': '', 'click': () => { ui.hideModal(); location.reload(); } }, 'Kapat');
		ui.showModal(title, [ msg, pre, h('div', { 'class': 'right' }, closeBtn) ]);
		return fs.exec(CLI, ['core-bg'].concat(args)).catch(() => ({ code: 0 })).then(() => {
			let n = 0;
			const tick = () => fs.exec(CLI, ['core-log']).then(r => r, () => null).then(r => {
				const out = r ? (r.stdout || '') : '';
				const nl = out.indexOf('\n'), first = nl < 0 ? out : out.slice(0, nl), body = nl < 0 ? '' : out.slice(nl + 1).trim();
				if (body) pre.textContent = body;
				if (first.indexOf('DONE') === 0) {
					const code = parseInt(first.slice(5), 10);
					msg.textContent = code === 0 ? 'Çekirdek işlemi tamamlandı.' : 'Çekirdek işlemi hata ile bitti (kod ' + code + ').';
					closeBtn.disabled = false;
					return;
				}
				if (++n > 450) { msg.textContent = 'İşlem uzun sürdü; durumu sayfayı yenileyerek kontrol et.'; closeBtn.disabled = false; return; }
				setTimeout(tick, 2000);
			});
			tick();
		});
	},

	doInstall(c) {
		if (!window.confirm('İndirme/kurulum internetten onlarca MB çekebilir; mobil veride kotandan düşer. Devam edilsin mi?')) return;
		return this.runJob(['install', c.id], c.name + ' kuruluyor…');
	},

	doUpload(c, ev) {
		return ui.uploadFile(UP, ev.target).then(() => this.runJob(['install', c.id, UP], c.name + ' kuruluyor…'), e => {
			const m = (e && e.message) || String(e || '');
			if (!/cancel|iptal/i.test(m)) ui.addNotification(null, h('p', {}, 'Dosya yüklenemedi: ' + m), 'error');
			return null;
		});
	},

	doRemove(c) {
		if (!window.confirm(c.name + ' kaldırılsın mı?')) return;
		return this.runJob(['remove', c.id], c.name + ' kaldırılıyor…');
	},

	card(c) {
		const kind = c.id === 'xray' ? 'Ana çekirdek' : (c.installed ? (KIND[c.source] || '—') : '—');
		const acts = [];
		if (c.id !== 'xray') {
			if (!c.installed) acts.push(h('button', { 'class': 'btn cbi-button cbi-button-positive', 'click': ui.createHandlerFn(this, () => this.doInstall(c)) }, 'Çekirdeği kur'));
			acts.push(h('button', { 'class': 'btn cbi-button', 'click': ui.createHandlerFn(this, ev => this.doUpload(c, ev)) }, 'Dosya yükle…'));
			if (c.installed) acts.push(h('button', { 'class': 'btn cbi-button cbi-button-negative', 'click': ui.createHandlerFn(this, () => this.doRemove(c)) }, 'Çekirdeği kaldır'));
		}
		return h('div', { 'class': 'kc-card' }, [
			h('div', { 'class': 'kc-head' }, [
				h('h4', { 'class': 'kc-name' }, c.name),
				h('span', { 'class': 'kc-badge' + (c.installed ? ' on' : '') }, c.installed ? 'Kurulu' : 'Kurulu değil')
			]),
			h('div', { 'class': 'kc-rows' }, [
				h('span', { 'class': 'kc-k' }, 'Tür'), h('span', { 'class': 'kc-v' }, kind),
				h('span', { 'class': 'kc-k' }, 'Sürüm'), h('span', { 'class': 'kc-v' }, c.installed ? (c.version || '—') : '—'),
				h('span', { 'class': 'kc-k' }, 'Boyut'), h('span', { 'class': 'kc-v' }, c.installed ? fmtSize(c.size) : '—')
			]),
			c.path ? h('div', { 'class': 'kc-path' }, c.path) : '',
			h('div', { 'class': 'kc-note' }, NOTES[c.id] || ''),
			acts.length ? h('div', { 'class': 'kc-act' }, acts) : ''
		]);
	},

	render(list) {
		list = Array.isArray(list) ? list : [];
		return h('div', {}, [
			h('style', {}, CSS),
			h('h2', {}, [h('img', { 'src': '/luci-static/kedi-logo.svg', 'style': 'height:1.3em;vertical-align:-0.25em;margin-right:8px;border-radius:6px' }), 'Çekirdekler']),
			h('p', { 'class': 'kc-desc' }, 'VPN motorlarının ikili dosyalarını buradan yönetirsin: kur, dosyadan yükle, kaldır. Şimdilik VPN yalnızca Xray ile çalışır; sing-box ve mihomo hazır tutulur, onlarla çalışma sonraki sürümlerde eklenecek.'),
			h('div', { 'class': 'kc-warn' }, 'İndirmeler onlarca MB tutar; mobil veride kotandan düşer. Çevrimdışıysan çekirdeğin arşivini kendi sayfasından indirip "Dosya yükle…" ile yükle.'),
			h('div', { 'class': 'kc-grid' }, list.map(c => this.card(c)))
		]);
	},

	handleSaveApply: null,
	handleSave: null,
	handleReset: null
});
