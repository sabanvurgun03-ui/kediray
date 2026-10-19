'use strict';
'require view';
'require view.kediray.i18n as i18n';
'require ui';
'require fs';
'require dom';

/* KediRay - Dashboard: mihomo / sing-box çalışırken menüde görünür; tıklayınca MetaCubeXD (çekirdeğin kendi web arayüzü) sayfanın içinde açılır.
 * Adres, port ve parola `kediray dash info` çıktısından gelir (yerel mod ve kendi yapılandırma modunda aynı yoldan). */

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

const CSS = `
.kd-desc{opacity:.8;margin:4px 0 14px;max-width:900px;line-height:1.5}
.kd-card{border:1px solid rgba(128,128,128,.25);border-radius:12px;padding:16px 18px;background:rgba(128,128,128,.04);max-width:960px;margin:0 0 14px}
.kd-row{display:flex;gap:10px;align-items:center;flex-wrap:wrap;margin:0 0 10px}
.kd-bar{display:flex;gap:10px;align-items:center;flex-wrap:wrap;margin:0 0 10px}
.kd-bar .kd-sp{flex:1}
.kd-badge{display:inline-block;padding:1px 9px;border-radius:9px;font-size:.8em;font-weight:600;background:rgba(128,128,128,.18)}
.kd-badge.on{background:rgba(34,163,85,.18);color:#3fb950}
.kd-note{font-size:.85em;opacity:.75;line-height:1.45}
.kd-warn{border:1px solid rgba(224,168,46,.5);border-left:4px solid #e0a82e;border-radius:8px;padding:10px 14px;margin:0 0 14px;background:rgba(224,168,46,.07);max-width:900px;line-height:1.5}
.kd-out{white-space:pre-wrap;word-break:break-all;margin:8px 0;font-size:.85em;background:rgba(128,128,128,.1);padding:8px 10px;border-radius:8px;max-height:220px;overflow:auto}
.kd-frame{display:block;width:100%;height:calc(100vh - 230px);min-height:520px;border:1px solid rgba(128,128,128,.3);border-radius:10px;background:#fff}
`;

function run(args) {
	return fs.exec(CLI, args).then(r => ({ code: r.code, out: ((r.stdout || '') + (r.stderr || '')).trim() }),
		e => ({ code: 1, out: String((e && e.message) || e) }));
}
function info() {
	return run(['dash', 'info']).then(r => { try { return JSON.parse(r.out) || {}; } catch (e) { return {}; } });
}

return view.extend({
	load() { return info(); },

	render(D) {
		this.D = D || {};
		this.root = h('div', {});
		this.draw();
		return this.root;
	},

	/* MetaCubeXD'nin kurulum sayfası: adres, port ve parola bağlantıda hazır gelir (parola yalnızca LAN'a açık API içindir) */
	url(D) {
		const host = location.hostname, port = D.port || '10085';
		return 'http://' + host + ':' + port + '/ui/#/setup?http=1&hostname=' + encodeURIComponent(host) + '&port=' + encodeURIComponent(port) + '&secret=' + encodeURIComponent(D.secret || '');
	},

	draw() {
		const root = this.root, D = this.D;
		while (root.firstChild) root.removeChild(root.firstChild);
		root.appendChild(h('style', {}, CSS));
		root.appendChild(h('h2', {}, [h('img', { 'src': '/luci-static/kedi-logo.svg', 'style': 'height:1.3em;vertical-align:-0.25em;margin-right:8px;border-radius:6px' }), 'Dashboard']));
		root.appendChild(h('p', { 'class': 'kd-desc' }, 'MetaCubeXD: bağlantıları, trafiği, grupları ve günlüğü canlı gör; sunucu seç. Çekirdek mihomo ya da sing-box iken çalışır.'));

		const card = h('div', { 'class': 'kd-card' });
		root.appendChild(card);
		const out = h('pre', { 'class': 'kd-out', 'style': 'display:none' });
		const say = (t, bad) => { out.style.display = t ? '' : 'none'; out.textContent = t || ''; out.style.borderLeft = bad ? '4px solid #d23f3f' : '4px solid #22a355'; };
		const badge = h('span', { 'class': 'kd-badge' + (D.on ? ' on' : '') }, D.on ? 'Açık' : 'Kapalı');
		card.appendChild(h('div', { 'class': 'kd-row' }, [h('b', {}, 'MetaCubeXD'), badge]));

		if (!D.installed) {
			card.appendChild(h('div', { 'class': 'kd-note' }, 'Dashboard dosyaları kurulu değil. Kurulum dosyasını yeniden çalıştır (kediray reinstall).'));
			return;
		}
		if (D.engine === 'xray') {
			card.appendChild(h('div', { 'class': 'kd-note' }, 'Dashboard mihomo ve sing-box için çalışır. Önce Çekirdekler sayfasından birini etkin yap.'));
			card.appendChild(h('div', { 'class': 'kd-row' }, [h('a', { 'class': 'cbi-button cbi-button-action', 'href': L.url('admin', 'vpn', 'kediray', 'cores') }, 'Çekirdekler')]));
			return;
		}
		if (D.own && !D.on) {
			card.appendChild(h('div', { 'class': 'kd-warn' }, 'Kendi yapılandırma modu açık ama dosyanda external-controller yok. Dosyaya "external-controller: 0.0.0.0:PORT", "secret" ve "external-ui: ui" satırlarını ekle (Çekirdek ayarı sayfası).'));
			return;
		}
		if (!D.on) {
			card.appendChild(h('div', { 'class': 'kd-note' }, 'Dashboard kapalı. Açınca çekirdeğin API\'si LAN\'a parolayla açılır ve VPN birkaç saniye yeniden başlar. İnternete açma.'));
			const btn = h('button', { 'class': 'cbi-button cbi-button-positive', 'type': 'button', 'click': ev => {
				btn.disabled = true; say('Uygulanıyor…');
				return run(['dash', 'on']).then(r => {
					if (r.code !== 0) { say(r.out, true); btn.disabled = false; return; }
					return info().then(x => { this.D = x; this.draw(); });
				});
			} }, 'Dashboard\'u aç');
			card.appendChild(h('div', { 'class': 'kd-row' }, [btn]));
			card.appendChild(out);
			return;
		}

		const url = this.url(D), host = location.hostname, port = D.port || '10085';
		card.appendChild(h('div', { 'class': 'kd-bar' }, [
			h('a', { 'class': 'cbi-button cbi-button-action', 'href': url, 'target': '_blank', 'rel': 'noopener' }, 'Yeni sekmede aç ↗'),
			h('span', { 'class': 'kd-note' }, 'Adres: http://' + host + ':' + port + '/ui/   Parola: ' + (D.secret || '(yok)'))
		]));
		if (D.own && !D.lan)
			card.appendChild(h('div', { 'class': 'kd-warn' }, 'Dosyandaki external-controller yalnızca 127.0.0.1\'de dinliyor; LAN\'dan açılmaz. 0.0.0.0:PORT yap ve external-ui: ui satırını ekle.'));
		if (location.protocol !== 'http:') {
			/* https sayfaya http çerçeve konamaz (tarayıcı engeller): yalnızca yeni sekme bağlantısı */
			card.appendChild(h('div', { 'class': 'kd-note' }, 'Bu sayfa https ile açık; tarayıcı http dashboard\'u sayfa içinde göstermez. Yukarıdaki düğmeyle yeni sekmede aç.'));
			return;
		}
		root.appendChild(h('iframe', { 'class': 'kd-frame', 'src': url, 'title': 'MetaCubeXD', 'referrerpolicy': 'no-referrer' }));
	},

	handleSaveApply: null,
	handleSave: null,
	handleReset: null
});
