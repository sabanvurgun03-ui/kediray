'use strict';
'require view';
'require fs';
'require ui';

/* KediRay - Hakkında */

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

const ICONS = {
	coffee: [ '0 0 24 24', 'M2 21h18v-2H2v2zM20 8h-2V5h2v3zm0-5H4v10c0 2.21 1.79 4 4 4h6c2.21 0 4-1.79 4-4v-3h2c1.11 0 2-.89 2-2V5c0-1.11-.89-2-2-2z', '#ffdd00' ],
	update: [ '0 0 24 24', 'M17.65 6.35A7.958 7.958 0 0012 4c-4.42 0-7.99 3.58-7.99 8s3.57 8 7.99 8c3.73 0 6.84-2.55 7.73-6h-2.08A5.99 5.99 0 0112 18c-3.31 0-6-2.69-6-6s2.69-6 6-6c1.66 0 3.14.69 4.22 1.78L13 11h7V4l-2.35 2.35z', '' ],
	github: [ '0 0 16 16', 'M8 0C3.58 0 0 3.58 0 8c0 3.54 2.29 6.53 5.47 7.59.4.07.55-.17.55-.38 0-.19-.01-.82-.01-1.49-2.01.37-2.53-.49-2.69-.94-.09-.23-.48-.94-.82-1.13-.28-.15-.68-.52-.01-.53.63-.01 1.08.58 1.23.82.72 1.21 1.87.87 2.33.66.07-.52.28-.87.51-1.07-1.78-.2-3.64-.89-3.64-3.95 0-.87.31-1.59.82-2.15-.08-.2-.36-1.02.08-2.12 0 0 .67-.21 2.2.82.64-.18 1.32-.27 2-.27.68 0 1.36.09 2 .27 1.53-1.04 2.2-.82 2.2-.82.44 1.1.16 1.92.08 2.12.51.56.82 1.27.82 2.15 0 3.07-1.87 3.75-3.65 3.95.29.25.54.73.54 1.48 0 1.07-.01 1.93-.01 2.2 0 .21.15.46.55.38A8.013 8.013 0 0016 8c0-4.42-3.58-8-8-8z', '' ],
	license: [ '0 0 24 24', 'M12.65 10C11.83 7.67 9.61 6 7 6c-3.31 0-6 2.69-6 6s2.69 6 6 6c2.61 0 4.83-1.67 5.65-4H17v4h4v-4h2v-4H12.65zM7 14c-1.1 0-2-.9-2-2s.9-2 2-2 2 .9 2 2-.9 2-2 2z', '' ],
	stats: [ '0 0 24 24', 'M5 9.2h3V19H5zM10.6 5h2.8v14h-2.8zm5.6 8H19v6h-2.8z', '' ],
	backup: [ '0 0 24 24', 'M17 3H5a2 2 0 00-2 2v14a2 2 0 002 2h14a2 2 0 002-2V7l-4-4zm-5 16a3 3 0 110-6 3 3 0 010 6zm3-10H5V5h10v4z', '' ]
};

function title(name, text) {
	const i = ICONS[name], ico = document.createElement('span');
	ico.setAttribute('style', 'display:inline-flex;vertical-align:-3px;margin-right:8px' + (i[2] ? ';color:' + i[2] : ''));
	ico.innerHTML = '<svg xmlns="http://www.w3.org/2000/svg" width="22" height="22" viewBox="' + i[0] + '" fill="currentColor"><path d="' + i[1] + '"/></svg>';
	return h('h3', { 'style': 'margin:0 0 6px' }, [ ico, text ]);
}

const CLI = '/usr/bin/kediray';

const CSS = `
.ka-card{border:1px solid rgba(128,128,128,.25);border-radius:12px;padding:20px 22px;background:rgba(128,128,128,.04);max-width:620px}
.ka-name{font-size:1.9em;font-weight:700;letter-spacing:-.02em;margin:0}
.ka-tag{opacity:.75;margin:2px 0 18px}
.ka-rows{display:grid;grid-template-columns:auto 1fr;gap:10px 18px;align-items:baseline}
.ka-k{opacity:.75}
.ka-v{font-weight:600;font-variant-numeric:tabular-nums;word-break:break-all}
.ka-sep{grid-column:1/-1;height:1px;background:rgba(128,128,128,.22);margin:6px 0}
.ka-dev{grid-column:1/-1;margin-top:4px}
.ka-dev b{font-size:1.05em}
.ka-note{opacity:.7;font-size:.9em;margin-top:16px;max-width:620px;line-height:1.5}
.ka-gh{display:grid;grid-template-columns:1fr 1fr;gap:10px;margin-top:10px}
.ka-gt{display:flex;flex-direction:column;align-items:center;gap:2px;padding:14px 8px 12px;border-radius:12px;border:1px solid rgba(128,128,128,.28);background:linear-gradient(160deg,rgba(128,128,128,.12),rgba(128,128,128,.02));color:inherit!important;text-decoration:none!important;transition:box-shadow .25s ease,transform .12s ease}
.ka-gt:hover{box-shadow:0 0 10px rgba(128,128,128,.45)}
.ka-gt:active{transform:scale(.98)}
.ka-gt i{font-style:normal;font-size:1.35em;line-height:1}
.ka-gt b{font-size:1.9em;font-weight:700;line-height:1.1;font-variant-numeric:tabular-nums}
.ka-gt small{opacity:.7;font-size:.84em}
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
				const lab = m => { tb.textContent = m === 'dark' ? '🌙' : (m === 'light' ? '☀️' : '◐'); tb.title = 'Tema: ' + (m === 'dark' ? 'Koyu' : (m === 'light' ? 'Açık' : 'Otomatik')) + ' (değiştirmek için tıkla)'; };
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
	load() {
		return fs.exec(CLI, ['version', '--json'])
			.then(r => { try { return JSON.parse(r.stdout); } catch (e) { return null; } })
			.catch(() => null);
	},

	showCachedUpdate() {
		return fs.exec(CLI, ['update', 'cached']).then(r => {
			let j = null; try { j = JSON.parse((r.stdout || '').trim()); } catch (e) { }
			const msg = document.getElementById('ka-upd-msg'), go = document.getElementById('ka-upd-go');
			this.setLast(j);
			if (j && j.ok && j.newer && msg && !msg.textContent) { msg.textContent = j.rev ? 'Aynı sürümde (' + j.current + ') depoda yeni değişiklikler var.' : 'Yeni sürüm var: ' + j.current + ' → ' + j.latest; if (go) go.style.display = ''; }
		}).catch(() => null);
	},

	render(d) {
		d = d || {};
		setTimeout(() => this.showCachedUpdate(), 400);
		setTimeout(() => this.showLicense(), 300);
		setTimeout(() => this.showRepoStats(), 600);
		const row = (k, v) => [h('div', { 'class': 'ka-k' }, k), h('div', { 'class': 'ka-v' }, v || '—')];
		return h('div', {}, [
			h('style', {}, CSS),
			h('h2', {}, [h('img', { 'src': '/luci-static/kedi-logo.svg', 'style': 'height:1.3em;vertical-align:-0.25em;margin-right:8px;border-radius:6px' }), 'Hakkında']),
			h('div', { 'class': 'ka-card' }, [
				h('h3', { 'class': 'ka-name' }, [h('img', { 'src': '/luci-static/kedi-logo.svg', 'style': 'height:1.1em;vertical-align:-0.15em;margin-right:8px;border-radius:6px' }), 'KediRay VPN']),
				h('div', { 'class': 'ka-tag' }, 'OpenWrt için Xray tabanlı akıllı VPN'),
				h('div', { 'class': 'ka-rows' }, [
					row('Sürüm', d.version),
					row('Proxy çekirdeği', d.core ? 'Xray ' + d.core : 'Xray —'),
					h('div', { 'class': 'ka-sep' }),
					h('div', { 'class': 'ka-dev' }, [h('span', { 'class': 'ka-k' }, 'Geliştirici: '), h('b', {}, 'Şaban Vurgun'), ' · 2026'])
				])
			]),
			h('div', { 'class': 'ka-card', 'style': 'margin-top:14px' }, [
				title('stats', 'İstatistikler'),
				h('div', { 'class': 'ka-k' }, 'GitHub deposundaki yıldız ve indirme sayısı'),
				h('div', { 'class': 'ka-gh' }, [
					h('a', { 'class': 'ka-gt', 'id': 'ka-gh-stars-a', 'href': 'https://github.com/sabanvurgun03-ui/kediray/stargazers', 'target': '_blank', 'rel': 'noopener noreferrer' }, [h('i', { 'style': 'color:#e3b341' }, '★'), h('b', { 'id': 'ka-gh-stars' }, '…'), h('small', {}, 'yıldız')]),
					h('a', { 'class': 'ka-gt', 'id': 'ka-gh-dl-a', 'href': 'https://github.com/sabanvurgun03-ui/kediray/releases', 'target': '_blank', 'rel': 'noopener noreferrer' }, [h('i', { 'style': 'color:#3b82f6' }, '⬇'), h('b', { 'id': 'ka-gh-dl' }, '…'), h('small', {}, 'indirme')])
				])
			]),
			h('div', { 'class': 'ka-card', 'id': 'ka-lic-card', 'style': 'margin-top:14px;display:none' }, [   // lisans kapalıyken hiç görünmesin (açılıp kapanma titremesi olmasın)
				title('license', 'Lisans'),
				h('div', { 'id': 'ka-lic-state', 'style': 'margin-bottom:8px;font-weight:600' }, 'Denetleniyor…'),
				h('div', { 'class': 'ka-k', 'style': 'margin-bottom:10px' }, [ 'Modem IMEI: ', h('b', { 'id': 'ka-lic-id', 'style': 'font-family:monospace' }, '—'), ' (lisans anahtarı bu IMEI numarasına göre üretilir; tek hanesi değişirse geçersiz olur)' ]),
				h('textarea', { 'id': 'ka-lic-key', 'rows': 3, 'style': 'width:100%;max-width:560px;font-family:monospace', 'placeholder': 'KR1.…' }),
				h('div', { 'style': 'margin-top:8px' }, [
					h('button', { 'class': 'btn cbi-button cbi-button-action', 'click': ui.createHandlerFn(this, 'doLicense') }, 'Etkinleştir'),
					' ',
					h('button', { 'id': 'ka-lic-rm', 'class': 'btn cbi-button', 'style': 'display:none', 'click': ui.createHandlerFn(this, 'doLicenseRemove') }, 'Lisansı kaldır')
				]),
				h('div', { 'id': 'ka-lic-msg', 'class': 'ka-k', 'style': 'margin-top:8px' }, '')
			]),
			h('div', { 'class': 'ka-card', 'style': 'margin-top:14px' }, [
				title('coffee', 'Beni destekle'),
				h('div', { 'style': 'margin-bottom:10px' }, h('a', { 'href': 'https://buymeacoffee.com/sabanvurgun', 'target': '_blank', 'rel': 'noopener noreferrer' }, 'https://buymeacoffee.com/sabanvurgun')),
				h('a', { 'class': 'btn cbi-button cbi-button-action', 'href': 'https://buymeacoffee.com/sabanvurgun', 'target': '_blank', 'rel': 'noopener noreferrer' }, 'Bana bir kahve ısmarla'),
				h('div', { 'class': 'ka-k', 'style': 'margin-top:10px' }, 'Bağışlarınız için teşekkürler, bu iş için harcanan emek için ufak bir hediye.')
			]),
			h('div', { 'class': 'ka-card', 'style': 'margin-top:14px' }, [
				title('update', 'Elle güncelle'),
				h('div', { 'class': 'ka-k', 'style': 'margin-bottom:10px' }, 'Yeni kediray-…-install.sh dosyasını seç; yüklenir ve otomatik kurulur.'),
				h('button', { 'class': 'btn cbi-button cbi-button-action', 'click': ui.createHandlerFn(this, 'doUpdate') }, 'Dosya seç ve güncelle')
			]),
			h('div', { 'class': 'ka-card', 'style': 'margin-top:14px' }, [
				title('github', 'GitHub\'dan güncelle'),
				h('div', { 'class': 'ka-k', 'style': 'margin-bottom:10px' }, 'En son sürüm GitHub Release\'ten indirilir, yayınlanan sha256sums ile doğrulanır ve kurulur. Doğrulama dosyası yoksa ya da uyuşmazsa kurulmaz.'),
				h('div', { 'id': 'ka-upd-msg', 'style': 'margin-bottom:10px;font-weight:600' }, ''),
				h('button', { 'class': 'btn cbi-button', 'click': ui.createHandlerFn(this, 'doCheck') }, 'Güncellemeyi denetle'),
				' ',
				h('button', { 'id': 'ka-upd-go', 'class': 'btn cbi-button cbi-button-action', 'style': 'display:none', 'click': ui.createHandlerFn(this, 'doOnline') }, 'Şimdi güncelle'),
				h('div', { 'id': 'ka-upd-last', 'class': 'ka-k', 'style': 'margin-top:10px' }, '')
			]),
			h('div', { 'class': 'ka-card', 'style': 'margin-top:14px' }, [
				title('update', 'Sıfırdan kur / Kaldır'),
				h('div', { 'class': 'ka-k', 'style': 'margin-bottom:10px' }, 'Sıfırdan kur: ayarların yedeklenip silinir, GitHub deposundaki son kod baştan kurulur. Kaldır: KediRay modemden kaldırılır. İkisi de iki kez onay ister.'),
				h('button', { 'class': 'btn cbi-button cbi-button-negative', 'click': ui.createHandlerFn(this, 'doFresh') }, 'Sıfırdan kur'),
				' ',
				h('button', { 'class': 'btn cbi-button cbi-button-negative', 'click': ui.createHandlerFn(this, 'doRemove') }, 'KediRay\'i kaldır')
			]),
			h('div', { 'class': 'ka-card', 'style': 'margin-top:14px' }, [
				title('backup', 'Yedekle / geri yükle'),
				h('div', { 'class': 'ka-k', 'style': 'margin-bottom:10px' }, 'Sunucuların, uygulama kuralların ve ayarların tek dosyada. Modemi sıfırlarsan bu dosyayla geri getirirsin. Dosya sunucu kimliklerini (UUID) içerir: kimseyle paylaşma, GitHub\'a yükleme.'),
				h('div', { 'id': 'ka-bk-msg', 'style': 'margin-bottom:10px;font-weight:600' }, ''),
				h('button', { 'class': 'btn cbi-button cbi-button-action', 'click': ui.createHandlerFn(this, 'doBackup') }, 'Yedek al'),
				' ',
				h('button', { 'class': 'btn cbi-button', 'click': ui.createHandlerFn(this, 'doRestore') }, 'Yedekten geri yükle')
			]),
			h('div', { 'class': 'ka-note' }, 'Çekirdeği güncellemek için SSH: kediray update-core · Coğrafi veriler: kediray update-geo')
		]);
	},

	/* GitHub yıldız ve indirme sayısı: modem GitHub API'sinden okur (6 saat önbellekli); ulaşılamazsa "—" gösterir */
	showRepoStats() {
		const st = document.getElementById('ka-gh-stars'), dl = document.getElementById('ka-gh-dl');
		if (!st || !dl) return Promise.resolve();
		const sa = document.getElementById('ka-gh-stars-a') || st, da = document.getElementById('ka-gh-dl-a') || dl;
		const none = why => { st.textContent = '—'; dl.textContent = '—'; sa.title = da.title = why; };
		return fs.exec(CLI, ['repostats', '--json']).then(r => {
			let j = null; try { j = JSON.parse((r.stdout || '').trim()); } catch (e) { }
			if (!j || !j.ok) return none('GitHub\'a ulaşılamadı');
			const d = new Date(j.ts * 1000), p = n => String(n).padStart(2, '0');
			const when = p(d.getDate()) + '.' + p(d.getMonth() + 1) + '.' + d.getFullYear() + ' ' + p(d.getHours()) + ':' + p(d.getMinutes());
			const tip = 'Son güncelleme: ' + when + (j.stale ? ' (GitHub\'a ulaşılamadı, son kayıtlı değer)' : '');
			st.textContent = j.stars;
			dl.textContent = j.releases ? j.downloads : '—';
			sa.title = tip;
			da.title = 'GitHub Releases\'teki kurulum dosyasının (kediray-install.sh) indirme sayısı. ' + tip;
		}).catch(() => none('Panel yanıt vermedi'));
	},

	showLicense() {
		return fs.exec(CLI, ['license', 'status', '--json']).then(r => {
			let j = null; try { j = JSON.parse((r.stdout || '').trim()); } catch (e) { }
			const st = document.getElementById('ka-lic-state'), id = document.getElementById('ka-lic-id'), rm = document.getElementById('ka-lic-rm');
			if (!st) return;
			const card = document.getElementById('ka-lic-card');
			if (j && j.state === 'off') return;   // lisans gerekmiyor: kart gizli kalır
			if (card) card.style.display = '';
			if (!j) { st.textContent = 'Lisans durumu okunamadı.'; return; }
			st.textContent = j.msg || (j.licensed ? 'Lisans geçerli' : 'Lisans gerekli');
			st.style.color = j.licensed ? '#22a355' : '#e0a020';
			if (id) id.textContent = j.imei || '—';
			if (rm) rm.style.display = (j.state && j.state !== 'none') ? '' : 'none';
			if (!j.licensed) {
				const note = document.getElementById('ka-lic-msg');
				if (note && !note.textContent) note.textContent = 'VPN çalışmaya devam eder; sunucu, uygulama ve cihaz ayarları lisans girilene kadar değiştirilemez.';
			}
		}).catch(() => null);
	},

	doLicense() {
		const key = document.getElementById('ka-lic-key'), msg = document.getElementById('ka-lic-msg');
		const v = key ? key.value.trim() : '';
		if (!v) { if (msg) msg.textContent = 'Önce lisans anahtarını yapıştır.'; return Promise.resolve(); }
		return fs.exec(CLI, ['license', 'activate', v]).then(r => {
			const out = ((r.stdout || '') + (r.stderr || '')).trim();
			if (msg) msg.textContent = out || (r.code === 0 ? 'Lisans etkinleştirildi.' : 'Etkinleştirilemedi.');
			if (r.code === 0) setTimeout(() => location.reload(), 1500);
		}).catch(() => { if (msg) msg.textContent = 'Panel yanıt vermedi; birkaç saniye sonra tekrar dene.'; });
	},

	doLicenseRemove() {
		const msg = document.getElementById('ka-lic-msg');
		return fs.exec(CLI, ['license', 'remove']).then(r => {
			if (msg) msg.textContent = ((r.stdout || '') + (r.stderr || '')).trim() || 'Lisans kaldırıldı.';
			setTimeout(() => location.reload(), 1200);
		}).catch(() => { if (msg) msg.textContent = 'Panel yanıt vermedi.'; });
	},

	setLast(j) {
		const el = document.getElementById('ka-upd-last');
		if (!el || !j || !j.checked) return;
		const d = new Date(j.checked * 1000), p = n => String(n).padStart(2, '0');
		el.textContent = 'Son denetleme: ' + p(d.getDate()) + '.' + p(d.getMonth() + 1) + '.' + d.getFullYear() + ' ' + p(d.getHours()) + ':' + p(d.getMinutes()) + ' (' + (j.src === 'auto' ? 'otomatik' : 'manuel') + ')';
	},

	doCheck() {
		const msg = document.getElementById('ka-upd-msg'), go = document.getElementById('ka-upd-go');
		if (msg) msg.textContent = 'Denetleniyor…';
		if (go) go.style.display = 'none';
		return fs.exec(CLI, ['update', 'check', '--json']).then(r => {
			let j = null; try { j = JSON.parse((r.stdout || '').trim()); } catch (e) { }
			if (!msg) return;
			this.setLast(j);
			if (!j || !j.ok) msg.textContent = 'Denetlenemedi: ' + ((j && j.error) || 'GitHub\'a ulaşılamadı') + '.';
			else if (j.newer) { msg.textContent = j.rev ? 'Aynı sürümde (' + j.current + ') depoda yeni değişiklikler var.' : 'Yeni sürüm var: ' + j.current + ' → ' + j.latest; if (go) go.style.display = ''; }
			else {
				const w = h('span', { 'style': 'display:inline-flex;align-items:center;gap:8px;color:#3fb950' });
				w.innerHTML = '<svg viewBox="0 0 24 24" width="22" height="22" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><circle cx="12" cy="12" r="10"/><path d="M7.5 12.5l3 3 6-6.5"/></svg>';
				w.appendChild(document.createTextNode('Güncelsin (' + j.current + ')'));
				msg.textContent = ''; msg.appendChild(w);
			}
		}).catch(() => { if (msg) msg.textContent = 'Denetlenemedi: panel yanıt vermedi.'; });
	},

	doBackup() {
		const msg = document.getElementById('ka-bk-msg');
		return fs.exec(CLI, ['backup']).then(r => {
			const txt = r.stdout || '';
			if (r.code !== 0 || !/^package kediray/.test(txt)) { if (msg) msg.textContent = 'Yedek alınamadı: ' + ((r.stderr || '').trim() || 'ayar boş'); return; }
			const d = new Date(), p = n => String(n).padStart(2, '0');
			const name = 'kediray-yedek-' + d.getFullYear() + p(d.getMonth() + 1) + p(d.getDate()) + '-' + p(d.getHours()) + p(d.getMinutes()) + '.conf';
			const a = document.createElement('a');
			a.href = URL.createObjectURL(new Blob([txt], { type: 'text/plain' }));
			a.download = name;
			document.body.appendChild(a); a.click(); a.remove();
			setTimeout(() => URL.revokeObjectURL(a.href), 4000);
			const n = (txt.match(/^config node\b/mg) || []).length;
			if (msg) msg.textContent = 'Yedek indirildi: ' + name + ' (' + n + ' sunucu)';
		}).catch(() => { if (msg) msg.textContent = 'Yedek alınamadı: panel yanıt vermedi.'; });
	},

	doRestore(ev) {
		const UP = '/tmp/kediray-restore.conf', msg = document.getElementById('ka-bk-msg');
		return ui.uploadFile(UP, ev.target).then(() => {
			return new Promise(resolve => {
				ui.showModal('Yedekten geri yükle', [
					h('p', {}, 'Mevcut sunucuların ve ayarların yedekteki ile DEĞİŞTİRİLECEK. Önceki ayar modemde /etc/kediray.pre-restore olarak saklanır. Devam edilsin mi?'),
					h('div', { 'class': 'right' }, [
						h('button', { 'class': 'btn cbi-button', 'click': () => { ui.hideModal(); resolve(false); } }, 'Vazgeç'),
						' ',
						h('button', { 'class': 'btn cbi-button cbi-button-negative', 'click': () => { ui.hideModal(); resolve(true); } }, 'Geri yükle')
					])
				]);
			});
		}, e => {
			const m = (e && e.message) || String(e || '');
			if (!/cancel|iptal/i.test(m) && msg) msg.textContent = 'Dosya yüklenemedi: ' + m;
			return null;
		}).then(go => {
			if (go === null) return;
			if (!go) { if (msg) msg.textContent = 'Vazgeçildi.'; return; }
			return fs.exec(CLI, ['restore', UP]).then(r => {
				const out = ((r.stdout || '') + (r.stderr || '')).trim();
				if (msg) msg.textContent = out || (r.code === 0 ? 'Geri yüklendi.' : 'Geri yüklenemedi.');
				if (r.code === 0) setTimeout(() => location.reload(), 2500);
			}).catch(() => { if (msg) msg.textContent = 'Panel yanıt vermedi; birkaç saniye sonra sayfayı yenile.'; });
		});
	},

	// İki aşamalı onay: ikisine de "evet" denmezse hiçbir şey yapılmaz
	confirm2(head, text1, text2, yes) {
		const ask = (t, txt, label) => new Promise(resolve => {
			ui.showModal(t, [
				h('p', {}, txt),
				h('div', { 'class': 'right' }, [
					h('button', { 'class': 'btn cbi-button', 'click': () => { ui.hideModal(); resolve(false); } }, 'Vazgeç'),
					' ',
					h('button', { 'class': 'btn cbi-button cbi-button-negative', 'click': () => { ui.hideModal(); resolve(true); } }, label)
				])
			]);
		});
		return ask(head + ' (1/2)', text1, 'Devam').then(ok => ok ? ask(head + ' (2/2) — son onay', text2, yes) : false);
	},

	doFresh() {
		return this.confirm2('Sıfırdan kur',
			'Sunucuların, uygulama kuralların ve ayarların SİLİNİR; GitHub deposundaki son kod baştan kurulur. Silmeden önce modemin /root klasörüne yedek alınır (kediray-backup-….uci). Devam edilsin mi?',
			'Emin misin? Ayarların sıfırlanacak ve kurulum sırasında VPN bir süre kesilecek. Hatta VPN dışında internet yoksa bağlantı kurulum bitene kadar gidebilir. Yedek dosyası modemde kalır; geri yüklemek için: kediray restore <dosya>.',
			'Evet, sıfırdan kur'
		).then(ok => {
			if (!ok) return;
			return fs.exec(CLI, ['reinstall', '--purge']).catch(() => ({ code: 0, stdout: '' })).then(r => this.runUpdate(r, 30));
		});
	},

	doRemove() {
		return this.confirm2('KediRay\'i kaldır',
			'KediRay modemden kaldırılır: VPN durur, güvenlik duvarı kuralları ve panel sayfaları silinir. Ayar dosyan (/etc/config/kediray) modemde kalır. Devam edilsin mi?',
			'Emin misin? Hattında VPN dışında internet yoksa kaldırınca internet bağlantın kesilir. Tekrar kurmak için kurulum dosyası ya da modemde elle kurulum gerekir.',
			'Evet, kaldır'
		).then(ok => {
			if (!ok) return;
			ui.showModal('KediRay kaldırılıyor', [h('p', {}, 'Kaldırılıyor… sayfa birazdan yenilenecek.')]);
			return fs.exec(CLI, ['uninstall']).catch(() => null).then(() => setTimeout(() => location.assign('/cgi-bin/luci/'), 5000));
		});
	},

	doOnline() {
		return fs.exec(CLI, ['update', 'install']).catch(() => ({ code: 0, stdout: '' })).then(r => this.runUpdate(r, 30));
	},

	doUpdate(ev) {
		const UP = '/tmp/kediray-update.sh';
		return ui.uploadFile(UP, ev.target).then(() => {
			// Başlatma isteği geç yanıtlanırsa (panel meşgulken) hata gösterme: kurulum günlüğünden ilerlemeyi izleriz
			return fs.exec(CLI, ['selfupdate', UP]).catch(() => ({ code: 0, stdout: '' }));
		}, e => {
			const msg = (e && e.message) || String(e || '');
			if (!/cancel|iptal/i.test(msg)) ui.addNotification(null, h('p', {}, 'Dosya yüklenemedi: ' + msg), 'error');
			return null;
		}).then(r => this.runUpdate(r));
	},

	runUpdate(r, grace) {   // grace: kurulum günlüğü henüz yokken kaç yoklama (2 sn) beklenir; depodan indirme uzun sürebilir
		const TOTAL = 7;   // kurulumun ana adımları (==> satırları)
		return Promise.resolve(r).then(r => {
			if (!r) return;
			if (r.code !== 0) {
				ui.addNotification(null, h('p', {}, ((r.stdout || '') + (r.stderr || '')).trim() || 'Güncelleme başlatılamadı.'), 'error');
				return;
			}
			const out = h('pre', { 'style': 'max-height:260px;overflow:auto;white-space:pre-wrap;margin:8px 0;font-size:.85em' }, (r.stdout || '').trim());
			const fill = h('div', { 'style': 'height:100%;width:3%;background:#3b82f6;border-radius:6px;transition:width .6s' });
			const label = h('div', { 'style': 'margin:6px 0 10px;font-weight:600' }, 'Güncelleme başlatılıyor…');
			const done = h('button', { 'class': 'btn cbi-button cbi-button-action', 'disabled': true, 'click': () => location.reload() }, 'Sayfayı yenile');
			ui.showModal('KediRay güncelleniyor', [
				h('p', {}, 'Kurulum arka planda çalışıyor. Panel birkaç saniye yanıt vermeyebilir, bu normal.'),
				h('div', { 'style': 'height:12px;border-radius:6px;background:rgba(128,128,128,.25);overflow:hidden' }, fill),
				label,
				h('details', {}, [h('summary', { 'style': 'cursor:pointer;opacity:.75' }, 'Ayrıntılı çıktı'), out]),
				h('div', { 'class': 'right' }, done)
			]);
			let fails = 0, seen = 0, polls = 0, finished = false;
			const bar = (pct, text) => { fill.style.width = Math.max(3, Math.min(100, pct)) + '%'; label.textContent = text; };
			const restarting = () => {
				bar(100, 'Güncelleme tamamlandı ✔ — LuCI yenileniyor, sayfa birazdan yeniden yüklenecek…');
				done.disabled = false;
				if (!finished) { finished = true; setTimeout(() => location.reload(), 5000); }
			};
			const poll = () => { polls++; return fs.exec(CLI, ['selfupdate', 'log']).then(x => {
				fails = 0;
				const lines = (x.stdout || '').split('\n'), st = lines.shift() || '', sl = lines.shift() || '';
				const m = /^STEPS (\d+)\|(.*)$/.exec(sl);
				if (m) { seen = +m[1]; if (seen) bar(Math.round(seen / TOTAL * 92), 'Güncelleme: ' + seen + '/' + TOTAL + ' — ' + (m[2] || 'çalışıyor')); }
				out.textContent = lines.join('\n').trim();
				out.scrollTop = out.scrollHeight;
				if (/^DONE/.test(st)) {
					if (st === 'DONE 0') restarting();
					else if (!seen && polls < (grace || 6)) setTimeout(poll, 2000);   // henüz başlamadı: birkaç saniye bekle
					else { bar(Math.round(seen / TOTAL * 92), seen ? 'Kurulum hata ile bitti (kod ' + st.slice(5) + '). Ayrıntılı çıktıya bak.' : 'Güncelleme başlatılamadı. Ayrıntılı çıktıya bak.'); done.disabled = false; }
				} else setTimeout(poll, 2000);
			}).catch(() => {
				// kurulumun sonunda LuCI'nin arka plan servisi (rpcd) yeniden başlar; bu sırada yanıt gelmez
				fails++;
				if (seen >= TOTAL - 1 || fails >= 8) restarting();
				else label.textContent = 'Panel yanıt vermiyor, bekleniyor… (güncelleme arka planda sürüyor)';
				if (!finished) setTimeout(poll, 2500);
			}); };
			setTimeout(poll, 2000);
		});
	},

	handleSaveApply: null,
	handleSave: null,
	handleReset: null
});
