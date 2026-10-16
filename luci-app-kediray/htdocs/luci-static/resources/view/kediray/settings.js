'use strict';
'require view';
'require ui';
'require form';
'require uci';
'require rpc';
'require fs';
'require dom';

/* KediRay - Ayarlar */

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

/* Lisanssızken ayarlar kaydedilmez (panel yanıt vermezse engellenmez) */
function krLicGuard() {
	return fs.exec('/usr/bin/kediray', ['license', 'status', '--json']).then(r => {
		let j = null; try { j = JSON.parse((r.stdout || '').trim()); } catch (e) { }
		if (!j || j.licensed) return true;
		ui.addNotification(null, E('p', {}, 'Lisans gerekli: ayarlar lisans girilene kadar kaydedilemez (Hakkında → Lisans). Modem IMEI: ' + (j.imei || '—')), 'warning');
		return false;
	}).catch(() => true);
}

const callHostHints = rpc.declare({ object: 'luci-rpc', method: 'getHostHints', expect: { '': {} } });

// Tarayıcıda saklanan eski menüyü (Hizmetler altındaki kayıt) bir kez temizle
try {
	if (!sessionStorage.getItem('kediray-menu-v2')) {
		sessionStorage.setItem('kediray-menu-v2', '1');
		if (ui.menu && ui.menu.flushCache) ui.menu.flushCache();
	}
} catch (e) {}

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

/* Akıllı band seçimi (Ayarlar → Bant): seçilen bantları tek tek kilitler, her birinde gerçek hız ve sinyal ölçer,
 * en iyisini seçer. Arka plandaki işi "kediray band smart" yürütür; bu kart yalnızca başlatır, durumu okur ve gösterir. */
function krSmartBand() {
	const kr = a => fs.exec('/usr/bin/kediray', a);
	const CLS = [['NR_NSA', 'NSA (4G çapa + 5G)'], ['NR', 'SA (yalnız 5G)'], ['LTE', '4G (LTE)']];
	const S = { lb: null, cls: null, picked: {}, wait: 15, meas: 'speed', apply: true, running: false, t0: 0, last: null, timer: null, err: '', miss: 0, cancelling: false };

	const h = (tag, attrs, kids) => {
		const el = document.createElement(tag);
		for (const k in (attrs || {})) {
			const v = attrs[k];
			if (v == null || v === false) continue;
			if (k === 'class') el.className = v;
			else if (k === 'style') el.style.cssText = v;
			else if (k.slice(0, 2) === 'on') el.addEventListener(k.slice(2), v);
			else el.setAttribute(k, v === true ? '' : v);
		}
		const add = c => {
			if (c == null || c === false) return;
			if (Array.isArray(c)) c.forEach(add);
			else el.appendChild(c.nodeType ? c : document.createTextNode(String(c)));
		};
		add(kids);
		return el;
	};

	if (!document.getElementById('kr-smart-css')) {
		const st = document.createElement('style');
		st.id = 'kr-smart-css';
		st.textContent = '.kr-smart{max-width:900px}'
			+ '.kr-smart .ks-row{display:flex;flex-wrap:wrap;gap:12px;margin:0 0 12px}'
			+ '.kr-smart .ks-f{flex:1 1 200px;min-width:170px}'
			+ '.kr-smart .ks-f label{display:block;font-size:12px;opacity:.75;margin-bottom:4px}'
			+ '.kr-smart .ks-f select,.kr-smart .ks-f input[type=number]{width:100%;box-sizing:border-box}'
			+ '.kr-smart .ks-head{display:flex;align-items:center;gap:10px;margin:2px 0 4px}'
			+ '.kr-smart .ks-chips{display:flex;flex-wrap:wrap;gap:6px;margin:6px 0 12px}'
			+ '.kr-smart .ks-chip{padding:4px 12px;border-radius:7px;border:1px solid rgba(128,128,128,.45);background:rgba(128,128,128,.12);cursor:pointer;font-size:13px;user-select:none}'
			+ '.kr-smart .ks-chip.ks-on{background:var(--kr-accent,#2a7de1);border-color:var(--kr-accent,#2a7de1);color:#fff}'
			+ '.kr-smart.ks-busy .ks-chip{pointer-events:none;opacity:.6}'
			+ '.kr-smart .ks-bar{height:7px;border-radius:4px;background:rgba(128,128,128,.25);overflow:hidden;margin:6px 0}'
			+ '.kr-smart .ks-bar>div{height:100%;background:linear-gradient(90deg,#14b8a6,var(--kr-accent,#2a7de1));transition:width .4s}'
			+ '.kr-smart .ks-line{display:flex;justify-content:space-between;gap:10px;font-size:13px}'
			+ '.kr-smart table{width:100%;border-collapse:collapse;margin-top:10px}'
			+ '.kr-smart th{font-size:11px;text-transform:uppercase;opacity:.65;text-align:left;padding:6px 8px;border-bottom:1px solid rgba(128,128,128,.35)}'
			+ '.kr-smart td{padding:7px 8px;border-bottom:1px solid rgba(128,128,128,.2);vertical-align:middle}'
			+ '.kr-smart tr.ks-best td{background:rgba(34,163,85,.14)}'
			+ '.kr-smart .ks-tag{display:inline-block;margin-left:6px;padding:0 6px;border-radius:5px;font-size:10px;background:rgba(34,163,85,.25);color:#22a355;font-weight:600}'
			+ '.kr-smart .ks-sub{display:block;font-size:11px;opacity:.6}'
			+ '.kr-smart .ks-sig{display:inline-flex;align-items:flex-end;gap:2px;height:14px}'
			+ '.kr-smart .ks-sig i{display:block;width:4px;background:rgba(128,128,128,.35);border-radius:1px}'
			+ '.kr-smart .ks-sig i.on{background:#22a355}'
			+ '.kr-smart .ks-bad{color:#e05252}'
			+ '.kr-smart .ks-note{margin:8px 0;font-size:13px}';
		document.head.appendChild(st);
	}

	const classes = () => CLS.filter(c => S.lb && S.lb[c[0]] && (S.lb[c[0]].available_band || []).length);
	const bandsOf = c => ((S.lb && S.lb[c] && S.lb[c].available_band) || []).map(b => ({ id: String(b.band_id), name: String(b.band_name || b.band_id) }));
	const picked = () => {
		if (!S.picked[S.cls]) { S.picked[S.cls] = {}; bandsOf(S.cls).forEach(b => { S.picked[S.cls][b.id] = true; }); }
		return S.picked[S.cls];
	};

	const root = h('div', { 'class': 'kr-smart' });
	const ctl = h('div');
	const out = h('div');

	const sigBars = rsrp => {
		const n = rsrp == null ? 0 : (rsrp >= -85 ? 5 : rsrp >= -95 ? 4 : rsrp >= -105 ? 3 : rsrp >= -115 ? 2 : 1);
		const el = h('span', { 'class': 'ks-sig', 'title': rsrp == null ? '' : rsrp + ' dBm' });
		for (let i = 1; i <= 5; i++) el.appendChild(h('i', { 'class': i <= n ? 'on' : '', 'style': 'height:' + (3 + i * 2) + 'px' }));
		return el;
	};
	const num = (v, d) => (v == null || isNaN(v)) ? '—' : Number(v).toFixed(d);

	const drawCtl = () => {
		root.classList.toggle('ks-busy', S.running);
		ctl.textContent = '';
		if (S.err && !S.lb) { ctl.appendChild(h('div', { 'class': 'ks-bad ks-note' }, S.err)); return; }
		if (!S.lb) { ctl.appendChild(h('div', { 'class': 'ks-note' }, 'Modemin bant bilgisi okunuyor…')); return; }
		const cl = classes();
		if (!cl.length) { ctl.appendChild(h('div', { 'class': 'ks-bad ks-note' }, 'Modemde taranabilecek bant listesi bulunamadı.')); return; }
		if (!S.cls || !cl.some(c => c[0] === S.cls)) S.cls = cl[0][0];
		const sel = (opts, cur, on) => {
			const el = h('select', { 'class': 'cbi-input-select', 'disabled': S.running },
				opts.map(o => h('option', { 'value': o[0] }, o[1])));
			el.value = cur;
			el.addEventListener('change', () => on(el.value));
			return el;
		};
		const wait = h('input', { 'type': 'number', 'class': 'cbi-input-text', 'min': 10, 'max': 120, 'step': 5, 'value': S.wait, 'disabled': S.running });
		wait.addEventListener('change', () => { S.wait = Math.max(10, Math.min(120, parseInt(wait.value, 10) || 15)); wait.value = S.wait; });
		ctl.appendChild(h('div', { 'class': 'ks-row' }, [
			h('div', { 'class': 'ks-f' }, [h('label', {}, 'Şebeke / 5G tipi'), sel(cl, S.cls, v => { S.cls = v; drawCtl(); })]),
			h('div', { 'class': 'ks-f' }, [h('label', {}, 'Ölçüm'), sel([['speed', 'Speedtest (önerilen)'], ['signal', 'Sadece sinyal (hızlı, veri harcamaz)']], S.meas, v => { S.meas = v; })]),
			h('div', { 'class': 'ks-f' }, [h('label', {}, 'Bekleme / aday (sn)'), wait])
		]));
		const pk = picked();
		const setAll = v => { bandsOf(S.cls).forEach(b => { pk[b.id] = v; }); drawCtl(); };
		ctl.appendChild(h('div', { 'class': 'ks-head' }, [
			h('b', { 'style': 'flex:1' }, 'Denenecek bantlar'),
			h('button', { 'class': 'btn cbi-button', 'disabled': S.running, 'onclick': () => setAll(true) }, 'Tümü'),
			h('button', { 'class': 'btn cbi-button', 'disabled': S.running, 'onclick': () => setAll(false) }, 'Kaldır')
		]));
		ctl.appendChild(h('div', { 'class': 'ks-chips' }, bandsOf(S.cls).map(b =>
			h('span', { 'class': 'ks-chip' + (pk[b.id] ? ' ks-on' : ''), 'onclick': ev => { pk[b.id] = !pk[b.id]; ev.currentTarget.classList.toggle('ks-on', !!pk[b.id]); } }, b.name))));
		const ap = h('input', { 'type': 'checkbox', 'id': 'ks-apply', 'disabled': S.running });
		ap.checked = S.apply;
		ap.addEventListener('change', () => { S.apply = ap.checked; });
		ctl.appendChild(h('div', { 'style': 'margin:0 0 12px' }, [ap, ' ', h('label', { 'for': 'ks-apply' }, 'En iyisini otomatik uygula')]));
		ctl.appendChild(S.running
			? h('button', { 'class': 'btn cbi-button cbi-button-negative', 'disabled': S.cancelling, 'onclick': cancel }, S.cancelling ? 'İptal ediliyor…' : 'İptal')
			: h('button', { 'class': 'btn cbi-button cbi-button-action', 'onclick': start }, 'Taramayı başlat'));
		ctl.appendChild(h('div', { 'class': 'cbi-value-description', 'style': 'margin-top:6px' },
			'Tarama sırasında internet her bant için kısa süre kesilir. Hız ölçümü VPN açıksa tünel üzerinden yapılır (bu hatta direkt internet olmayabilir), aynı koşulda bantlar kıyaslanır. İptalde ya da internet gelmezse eski band kilidi geri yüklenir.'));
	};

	const drawOut = () => {
		out.textContent = '';
		const j = S.last;
		if (!j) return;
		const rows = (j.rows || []).slice().sort((a, b) => {
			const ao = a.status === 'ok' ? 1 : 0, bo = b.status === 'ok' ? 1 : 0;
			return (bo - ao) || ((b.score || 0) - (a.score || 0));
		});
		const total = parseInt(j.total, 10) || 0, done = Math.min(parseInt(j.done, 10) || 0, total);
		if (S.running) {
			let eta = '';
			if (total > done) {
				const per = (S.t0 && done > 0) ? (Date.now() - S.t0) / 1000 / done : (14 + (S.meas === 'speed' ? 9 : 2));
				eta = ' · ~' + Math.max(1, Math.round(per * (total - done))) + ' sn kaldı';
			}
			out.appendChild(h('div', { 'style': 'margin-top:14px' }, [
				h('div', { 'class': 'ks-line' }, [h('b', {}, j.phase || 'Çalışıyor…'), h('span', {}, done + '/' + total + eta)]),
				h('div', { 'class': 'ks-bar' }, h('div', { 'style': 'width:' + (total ? Math.round(done / total * 100) : 0) + '%' }))
			]));
		} else if (j.note) {
			out.appendChild(h('div', { 'class': 'ks-note', 'style': 'margin-top:14px' }, j.note));
		}
		if (!rows.length) return;
		const bandName = {};
		bandsOf(j.cls || S.cls).forEach(b => { bandName[b.id] = b.name; });
		const errTxt = { nocov: 'bağlanamadı (bu bantta kapsama yok)', nomeas: 'sinyal ölçülemedi' };
		out.appendChild(h('table', {}, [
			h('thead', {}, h('tr', {}, ['Bant', 'Hız', 'SNR', 'RSRP', 'Sinyal', 'Skor'].map(t => h('th', {}, t)))),
			h('tbody', {}, rows.map(r => {
				const best = j.best && String(j.best) === String(r.id) && r.status === 'ok';
				const nm = [r.name || bandName[r.id] || r.id, best ? h('span', { 'class': 'ks-tag' }, 'EN İYİ') : null];
				if (r.used && r.used !== '-' && r.used.toUpperCase() !== String(r.name).toUpperCase()) nm.push(h('span', { 'class': 'ks-sub' }, r.used));
				if (errTxt[r.status]) return h('tr', {}, [h('td', {}, nm), h('td', { 'colspan': 5, 'class': 'ks-bad' }, errTxt[r.status])]);
				return h('tr', { 'class': best ? 'ks-best' : '' }, [
					h('td', {}, nm),
					h('td', { 'style': 'font-weight:600' }, r.status === 'nospeed' ? 'ölçülemedi' : (r.mbps == null ? '—' : num(r.mbps, 1) + ' Mbps')),
					h('td', {}, num(r.sinr, 1)),
					h('td', {}, num(r.rsrp, 1)),
					h('td', {}, sigBars(r.rsrp)),
					h('td', { 'style': 'opacity:.7' }, r.status === 'ok' ? num(r.score, 1) : '—')
				]);
			}))
		]));
	};

	const poll = () => {
		clearTimeout(S.timer);
		if (!root.isConnected && ++S.miss > 3) return;
		kr(['band', 'smart-status']).then(r => {
			let j = null;
			try { j = JSON.parse(r.stdout); } catch (e) {}
			if (j) {
				const was = S.running;
				S.last = j; S.running = !!j.running;
				if (!S.running) S.cancelling = false;
				if (was !== S.running) drawCtl();
			}
			drawOut();
			if (S.running) S.timer = setTimeout(poll, 2500);
		}).catch(() => { S.timer = setTimeout(poll, 4000); });
	};

	const go = ids => {
		S.running = true; S.cancelling = false; S.t0 = Date.now(); S.last = { running: 1, total: ids.length, done: 0, phase: 'Başlatılıyor…', cls: S.cls, rows: [] };
		drawCtl(); drawOut();
		kr(['band', 'smart', '--bg', '--class', S.cls, '--bands', ids.join(' '), '--wait', String(S.wait), '--measure', S.meas, '--apply', S.apply ? '1' : '0'])
			.then(r => {
				const t = ((r && r.stdout) || '') + ((r && r.stderr) || '');
				if (/zaten/.test(t)) ui.addNotification(null, h('p', {}, 'Bir band taraması zaten sürüyor.'), 'warning');
				S.timer = setTimeout(poll, 1500);
			})
			.catch(e => { S.running = false; ui.addNotification(null, h('p', {}, 'Tarama başlatılamadı: ' + e), 'danger'); drawCtl(); drawOut(); });
	};

	const start = () => {
		const pk = picked();
		const ids = bandsOf(S.cls).filter(b => pk[b.id]).map(b => b.id);
		if (!ids.length) { ui.addNotification(null, h('p', {}, 'En az bir bant seç.'), 'warning'); return; }
		const mins = Math.ceil(ids.length * (14 + (S.meas === 'speed' ? 9 : 2)) / 60);
		ui.showModal('Tarama başlatılsın mı?', [
			h('p', {}, ids.length + ' bant sırayla denenecek (yaklaşık ' + mins + ' dk). Her denemede internet kısa süre kesilir. '
				+ (S.apply ? 'Bitince en iyi bant kilitlenir. ' : 'Bitince eski band kilidi geri yüklenir. ')
				+ 'İptal edersen ya da seçilen bantla internet gelmezse de eski kilit geri yüklenir.'),
			h('div', { 'class': 'right' }, [
				h('button', { 'class': 'btn', 'onclick': () => ui.hideModal() }, 'Vazgeç'), ' ',
				h('button', { 'class': 'btn cbi-button cbi-button-action', 'onclick': () => { ui.hideModal(); go(ids); } }, 'Başlat')])
		]);
	};

	const cancel = () => {
		S.cancelling = true; drawCtl();
		kr(['band', 'cancel']).catch(() => {});
	};

	root.appendChild(h('div', { 'class': 'cbi-value-description', 'style': 'margin-bottom:10px' },
		'Seçtiğin bantları tek tek kilitler, her birinde gerçek hız (speedtest) ve sinyali ölçer, en hızlısını seçer. 5G kilidi internetini düşürmez: NSA seçiliyken 4G çapa açık kalır.'));
	root.appendChild(ctl);
	root.appendChild(out);
	drawCtl();
	kr(['band', 'info']).then(r => {
		try { const j = JSON.parse(r.stdout); S.lb = j.lockband || null; S.err = j.error || ''; }
		catch (e) { S.err = 'Modemin bant bilgisi okunamadı (qmodem kurulu mu?).'; }
		if (!S.lb && !S.err) S.err = 'Modemin bant bilgisi okunamadı.';
		drawCtl();
	}).catch(e => { S.err = 'Bant bilgisi alınamadı: ' + e; drawCtl(); });
	S.timer = setTimeout(poll, 600);   // sayfa yenilense bile süren / biten taramayı göster
	return root;
}


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
		return Promise.all([uci.load('kediray'), L.resolveDefault(callHostHints(), {})]);
	},

	render(data) {
		const hosts = data[1] || {};
		let m, s, o;

		m = new form.Map('kediray', 'KediRay — Ayarlar',
			'Kaydet & Uygula dediğinde VPN yeniden başlar. Çekirdekte direkt geçen uygulamalar bundan etkilenmez.');

		/* ---------------- Genel ---------------- */
		s = m.section(form.NamedSection, 'main', 'main');
		s.tab('general', 'Genel');
		s.tab('look', 'Görünüm');
		s.tab('band', 'Bant');
		s.tab('dns', 'DNS');
		s.tab('stable', 'Hız, Bildirim & Kararlılık');
		s.tab('sub', 'Abonelik');
		s.tab('adv', 'Gelişmiş');

		o = s.taboption('general', form.Flag, 'enabled', 'VPN açık · açılışta otomatik bağlan');
		o.rmempty = false;
		o.description = 'İşaretliyken VPN şimdi çalışır ve modem her açıldığında internet gelince kendiliğinden bağlanır (seçili sunucuya, "Sunucu: Auto" ise en hızlısına). İşareti kaldırırsan VPN durur ve açılışta başlamaz; internet doğrudan çıkar.';

		o = s.taboption('general', form.ListValue, 'mode', 'Yönlendirme modu');
		o.value('global', 'Tümü VPN (yerel ağ hariç)');
		o.value('list', 'Sadece seçilenler VPN — Kurallar ve VPN\'e ayarlı uygulamalar');
		o.default = 'global';

		o = s.taboption('general', form.ListValue, 'node', 'Sunucu');
		o.value('auto', 'Otomatik — en hızlı, düşerse diğerine geç');
		uci.sections('kediray', 'node', n => o.value(n['.name'], n.remarks || (n.address + ':' + n.port)));
		o.default = 'auto';
		o.description = 'Sunucu değiştirmek için Kontrol Paneli\'ndeki "Bağlan" butonu bağlantıları koparmadan geçer.';

		o = s.taboption('general', form.Flag, 'connect_ip', 'Sunucuya IP ile bağlan',
			'Adreste alan adı olsa bile bir kez IP\'ye çevrilir ve doğrudan IP\'ye bağlanılır; alan adı SNI/Host olarak kalır. DNS sorunlarından etkilenmez.');
		o.default = '1';
		o.rmempty = false;

		o = s.taboption('general', form.ListValue, 'capture', 'Trafik yakalama modu');
		o.value('mixed', 'Mixed — TCP çekirdekte (NAT), UDP hev-socks5-tunnel ile  [önerilen]');
		o.value('tun', 'TUN — her şey (TCP+UDP) hev-socks5-tunnel üzerinden');
		o.value('tproxy', 'TPROXY — TCP ve UDP çekirdekte TPROXY ile');
		o.value('redirect', 'Redirect — sadece TCP (UDP/oyun/arama direkt çıkar)');
		o.default = 'mixed';
		o.description = 'Mixed: TCP çekirdekten, UDP TUN\'dan. TUN: her şey TUN\'dan geçer; bazı hatlarda sayfalar hızlanır, UDP biraz gecikir. TPROXY: TCP ve UDP çekirdekte. Redirect: yalnız TCP. Paketler yoksa otomatik TPROXY\'ye düşer (apk add hev-socks5-tunnel kmod-tun). Karşılaştırmak için Kontrol Paneli → "🐢 Sayfa gecikmesi".';

		o = s.taboption('general', form.ListValue, 'default_device', 'Listede olmayan cihazlar');
		o.value('vpn', 'VPN kurallarını kullansın');
		o.value('direct', 'Direkt çıksın (sadece listedekiler VPN)');
		o.default = 'vpn';

		o = s.taboption('general', form.ListValue, 'failsafe', 'VPN çekirdeği çökerse');
		o.value('killswitch', 'Kill switch — VPN trafiğini kes (WhatsApp asla direkt çıkmaz)');
		o.value('open', 'İnterneti direkt aç');
		o.default = 'killswitch';

		o = s.taboption('general', form.DynamicList, 'lan', 'LAN arayüzleri');
		o.default = 'lan';
		o.description = 'Trafiği yakalanacak ağlar (misafir ağı eklemek için guest yaz).';

		o = s.taboption('general', form.Flag, 'update_check', 'Güncellemeleri kontrol et');
		o.default = '1';
		o.description = 'Her gece 01:00\'de GitHub\'da yeni bir sürüm çıkmış mı diye sorar ve Hakkında sayfasında söyler. Sen düğmeye basmadan hiçbir şey kurulmaz; bu yalnızca sorunun sorulup sorulmayacağına karar verir.';

		o = s.taboption('general', form.Flag, 'update_auto_install', 'Otomatik kur');
		o.default = '0';
		o.depends('update_check', '1');
		o.description = 'Gece denetiminde yeni sürüm çıkmışsa kendiliğinden indirilir (SHA256 ile doğrulanır) ve kurulur; kurulum sırasında VPN kısa süre yeniden başlar. Ayarların ve sunucuların korunur. Kapalıysa yalnızca haber verilir.';

		o = s.taboption('general', form.Flag, 'stats', 'Geliştirmeye yardımcı ol');
		o.default = '0';
		o.rmempty = false;
		o.description = 'İşaretliyse anonim kullanım sayısı gönderilir; işaretsizken hiçbir şey gönderilmez. Açıksa günde bir kez şunlar gönderilir: rastgele bir kurulum kimliği, KediRay sürümü ve uygulama adı. Sunucu bilgilerin, trafiğin, adın ya da IP adresin kaydedilmez. İstediğin an kapatabilirsin; kapatınca kimlik silinir. Ne gönderileceğini görmek için: kediray count show';

		o = s.taboption('general', form.Value, 'update_repo', 'Güncelleme kaynağı');
		o.placeholder = 'sabanvurgun03-ui/kediray';
		o.rmempty = true;
		o.description = 'Sürümlerin alınacağı GitHub deposu, sahip/depo biçiminde. Yalnızca bir fork\'tan kuruyorsan değiştir; boş bırakırsan varsayılan kullanılır.';
		o.validate = (sid, v) => (!v || /^[A-Za-z0-9_.-]+\/[A-Za-z0-9_.-]+$/.test(v)) ? true : 'sahip/depo biçiminde yaz';

		o = s.taboption('dns', form.ListValue, 'dns_mode', 'DNS modu');
		o.value('private', 'Tünelden — dnsmasq sorguları çekirdeğe, çekirdek tünele verir  [önerilen]');
		o.value('fast', 'Direkt — sorgular çekirdekten ama tünele girmeden çıkar');
		o.value('off', 'DNS\'e dokunma — modemin kendi DNS\'i aynen kalır (sorun giderme için)');
		o.default = 'private';
		o.description = '"Tünelden": sorgular tünel içinden gider, operatöre sızmaz; hızlıdır, TUN modunda tek çalışan seçenektir. "Direkt": tünele girmez, tünel kopsa da çalışır; ziyaret ettiğin siteler operatörün DNS\'ine görünür. "DNS\'e dokunma": KediRay ad çözümlemeye karışmaz; TUN modunda ad çözülemediği için otomatik "Tünelden"e döner. Yalnız sorun gidermek için.';

		o = s.taboption('dns', form.Value, 'dns_remote', 'Uzak DNS (VPN üzerinden)');
		o.value('tcp://8.8.8.8', 'Google, TCP  [önerilen]');
		o.value('https://1.1.1.1/dns-query', 'Cloudflare DoH');
		o.value('https://8.8.8.8/dns-query', 'Google DoH');
		o.value('tcp://1.1.1.1', 'Cloudflare, TCP');
		o.default = 'tcp://8.8.8.8';
		o.description = 'Tünelden çözülen sorguların gittiği sunucu (VPN üzerinden). Varsayılan Google TCP: en uyumlusu. Bu hatta ölçüldü: DNS-over-TCP kullanılırken tünelde tek bir bağlantı düşünce sorgu ölebiliyor (günlükte "failed to read response length → read/write on closed pipe") ve sayfalar askıda kalıyor. Bu belirtiyi görürsen Cloudflare ya da Google DoH\'a geç: HTTP/2 üzerinden kendi içinde yeniden dener. VPN sunucun DoH\'a çıkamıyorsa TCP\'ye dön. Adres IP olmalı.';

		o = s.taboption('dns', form.Value, 'dns_direct', 'Direkt DNS (Türkiye/direkt alan adları)',
			'auto = modeme operatörden gelen DNS (önerilen): her zaman ayakta ve tünele girmez. Bazı hatlarda DoH adreslerine hiç ulaşılamıyor ve o zaman her sorgu saniyelerce bekleyip sayfayı kilitliyor.');
		o.value('auto', 'Otomatik — operatörün DNS sunucusu');
		o.value('https+local://1.1.1.1/dns-query', 'Cloudflare DoH (sansürsüz, direkt)');
		o.value('https+local://8.8.8.8/dns-query', 'Google DoH (direkt)');
		o.default = 'auto';
		o = s.taboption('dns', form.Flag, 'dns_hijack', 'Cihazların DNS\'ini çekirdekte yakala',
			'Cihaz kendi DNS\'ini (8.8.8.8 gibi) yazsa bile sorgu modemin DNS\'ine yönlendirilir. Kapatmayın: açıkken sorgu tünel/TUN yoluna hiç girmez ve sayfalar belirgin şekilde hızlı açılır (ölçüm: 205 ms yerine 1 ms).');
		o.default = '1';
		o = s.taboption('dns', form.Flag, 'block_doh', 'Tarayıcıların kendi DNS\'ini (DoH) engelle',
			'Chrome ve Firefox "Güvenli DNS" ile sistem DNS\'ini atlayıp doğrudan dns.google / cloudflare-dns.com gibi adreslere sorar. Bu hatta o adreslere ulaşılamadığı için sayfa başına 1-3 istek ~50 saniye askıda kalıyor ve tarayıcıda çark dönmeye devam ediyor. Açıkken bu istekler anında reddedilir (RST/ICMP), tarayıcı hemen KediRay\'in DNS\'ine döner. Alan adı kuralların ve gizliliğin etkilenmez. Varsayılan KAPALI: açıkken telefonun "Özel DNS" ayarı da reddedildiği için Speedtest gibi uygulamalar "Check your connection" uyarısı verebilir. Sayfalar askıda kalıyorsa açın.');
		o.default = '0';
		o.rmempty = false;

		o = s.taboption('dns', form.Value, 'dns_direct2', 'Direkt DNS (yedek)',
			'İlki yanıt vermezse buraya düşer. auto = operatörün ikinci DNS sunucusu.');
		o.value('auto', 'Otomatik — operatörün ikinci DNS sunucusu');
		o.value('https+local://8.8.8.8/dns-query', 'Google DoH (direkt)');
		o.value('https+local://1.1.1.1/dns-query', 'Cloudflare DoH (direkt)');
		o.value('', 'Yedek yok');
		o.default = 'auto';

		o = s.taboption('dns', form.Flag, 'dns_stale', 'Tünel takılırsa önbellekten yanıt ver',
			'Mobil hatta tünel anlık koparsa bilinen adresler beklemeden verilir, arkada yenilenir (Xray serveStale). Uygulamalar "DNS zaman aşımı" yaşamaz.');
		o.default = '1';
		o.rmempty = false;

		o = s.taboption('dns', form.Value, 'dns_bootstrap', 'Önyükleme DNS', 'Sunucu adreslerini çözmek için düz DNS IP\'si.');
		o.datatype = 'ip4addr';
		o.default = '1.1.1.1';

		o = s.taboption('dns', form.Flag, 'ipv6', 'IPv6 desteği', 'Kapalıyken IPv6 (AAAA) kayıtları filtrelenir; sızıntı olmaz.');
		o = s.taboption('dns', form.Flag, 'v6_block', 'IPv6 sızıntı koruması', 'VPN cihazlarının IPv6 ile tüneli atlamasını engeller.');
		o.default = '1';
		o.depends('ipv6', '0');

		o = s.taboption('dns', form.Button, '_dnstest', 'Metin2 DNS testi');
		o.inputtitle = 'Testi çalıştır';
		o.inputstyle = 'action';
		o.description = 'Gameforge alan adlarını her DNS yolundan çözer: yanıt var mı, kaç ms sürdü.';
		o.onclick = function () {
			const pre = E('pre', { 'style': 'white-space:pre-wrap;max-height:60vh;overflow:auto' }, 'Ölçüm başlatılıyor…');
			let closed = false;
			ui.showModal('Metin2 DNS testi', [pre, E('div', { 'class': 'right' }, E('button', { 'class': 'btn', 'click': () => { closed = true; ui.hideModal(); } }, 'Kapat'))]);
			const run = a => fs.exec('/usr/bin/kediray', a);
			return run(['dnstest', '--bg']).then(async () => {
				// Ölçüm arka planda sürer; bitene kadar 2 sn'de bir oku (tek istek zaman aşımına düşmesin)
				for (let i = 0; i < 60 && !closed; i++) {
					await new Promise(res => setTimeout(res, 2000));
					const r = await run(['dnstest', '--read']);
					const txt = (r.stdout || '').trim();
					const nl = txt.indexOf('\n');
					const state = (nl < 0 ? txt : txt.slice(0, nl)).trim();
					const body = nl < 0 ? '' : txt.slice(nl + 1);
					pre.textContent = (body || 'Ölçülüyor…') + (state === 'BITTI' ? '\n\n[Bitti]' : '');
					if (state === 'BITTI') return;
				}
				if (!closed) pre.textContent += '\n\n(zaman aşımı: ölçüm hâlâ sürüyor olabilir; `kediray dnstest --read` ile bak)';
			}).catch(e => { pre.textContent = 'Çalıştırılamadı: ' + e; });
		};

		o = s.taboption('stable', form.Flag, 'push_fix', 'Bildirimleri direkt gönder',
			'Önerilen: KAPALI. Kapalıyken Google (FCM) / Apple (APNs) bildirim bağlantıları tünelden gider; tünel heartbeat ile canlı kaldığı için bağlantı kesilmez. Açıkken bu bağlantılar operatörden direkt gider ve operatör boştaki bağlantıyı sessizce kesebilir: bildirimler gecikir ya da gelmez.');
		o.default = '0';
		o = s.taboption('stable', form.Value, 'conn_idle', 'Boşta bağlantı süresi (sn)',
			'Xray varsayılanı 300 sn; telefonun bildirim bağlantısını koparır. Önerilen 14400 (4 saat): bildirim bağlantısı gece boyunca yaşar.');
		o.datatype = 'range(60,86400)';
		o.default = '14400';
		o = s.taboption('stable', form.Value, 'ws_heartbeat', 'WebSocket heartbeat (sn)',
			'Boştaki WebSocket tünelini canlı tutar (varsayılan 30). Sunucu önündeki proxy/CDN ya da operatör boş bağlantıyı keserse bildirimler (WhatsApp vb.) telefona ulaşmaz; bu ayar onu önler. 0 = kapalı.');
		o.datatype = 'range(0,600)';
		o.default = '30';
		o = s.taboption('stable', form.Value, 'tcp_keepalive', 'TCP keepalive (sn)', 'Sunucuya giden TCP bağlantısında keepalive (varsayılan 30). Operatör NAT kaydı boş bağlantıyı unutmasın. 0 = kapalı.');
		o.datatype = 'range(0,600)';
		o.default = '30';
		o = s.taboption('stable', form.Flag, 'block_quic', 'QUIC\'i (UDP 443) reddet — önerilen',
			'Tarayıcıların QUIC bağlantısı tünelde takılabiliyor (ör. Google giriş sayfası dönüp duruyor). Reddedilince tarayıcı beklemeden TCP\'ye (tünele) geçer; v2rayNG ve Xray\'in varsayılanı da budur. Oyun, arama ve DNS gibi diğer UDP trafiği etkilenmez.');
		o.default = '1';
		o.rmempty = false;
		o = s.taboption('stable', form.ListValue, 'sniff_mode', 'Alan adı yönlendirme (hız / uyumluluk)');
		o.value('auto', 'Otomatik — DNS\'i bozuk uygulama (Discord, WARP) varsa sunucu çözer');
		o.value('off', 'Hız öncelikli — hiçbir zaman sunucuya çözdürme');
		o.default = 'auto';
		o.description = 'Otomatik modda tüm bağlantılarda hedef alan adı sunucuya çözdürülür; bu her yeni bağlantıya bir miktar gecikme ekler ve hız testi gibi çok bağlantılı yüklemelerde yavaş hızlanmaya yol açabilir. "Hız öncelikli" seçersen bu gecikme olmaz, ama operatörün DNS\'i bozduğu siteler (ör. Discord) açılmayabilir.';
		o = s.taboption('stable', form.Flag, 'sniff_override', 'Alan adını VPN sunucusu çözsün',
			'Varsayılan kapalı: hedef IP korunur, her bağlantıda ikinci DNS sorgusu olmaz (daha düşük gecikme).');
		o.default = '0';
		o.rmempty = false;
		o = s.taboption('stable', form.Flag, 'speed_tune', 'Hız ayarı (TCP tamponları + Xray tamponu)');
		o.default = '1';
		o.description = 'Hız testi ya da büyük indirme yavaş hızlanıyorsa: çekirdeğin TCP tamponlarını büyütür ve Xray\'in bağlantı başına tamponunu artırır (yaklaşık 1 MB). Bellek yalnızca yük gelince kullanılır. Sorun çıkarsa kapat.';
		o = s.taboption('stable', form.Value, 'buffer_size', 'Xray bağlantı tamponu (KB)');
		o.datatype = 'range(64,8192)'; o.placeholder = '1024';
		o.depends('speed_tune', '1');
		o = s.taboption('stable', form.Flag, 'mobile_tune', 'Mobil hat ayarı (5G/CGNAT)',
			'Sunucuya giden bağlantı isteği (SYN) düşerse çekirdek varsayılan olarak ~50 saniye yeniden dener; tarayıcı o isteği 50 saniye askıda tutar ve sayfa "yükleniyor" kalır. Açıkken 3 denemeye (≈15 sn) iner: bağlantı hızlı başarısız olur, tarayıcı kendisi tekrar dener ve sayfa tamamlanır. (tcp_syn_retries=3, tcp_retries2=8)');
		o.default = '1';
		o.rmempty = false;
		o = s.taboption('stable', form.Flag, 'mux', 'TCP Mux ⓘ',
			'Oyun oynuyorsan (Metin2 vb.) KAPALI tut: açıkken oyuna girilemiyor ya da oyundan atılıyorsun. Kapalıyken her istek sunucuya yeni bir bağlantı açar: bir sayfa 70-100 bağlantı demektir. Hattın ara sıra bağlantı düşürüyorsa (Günlük\'te "failed to dial / EOF / connection reset") her sayfada birkaç istek askıda kalır ve tarayıcı dönmeye devam eder. Açıldığında tek bağlantı çok isteği taşır, açılan bağlantı sayısı ~10 kat azalır. Hız biraz düşebilir; takılma yaşıyorsan aç, "kediray doctor" ile önce/sonra ölç. UDP (oyun, arama) için XUDP bu ayardan bağımsız olarak hep açıktır.');
		o.default = '0';
		o.rmempty = false;
		// Fare ile üzerine gelince (ya da dokunup basılı tutunca) görünen hatırlatma
		o.render = function () {
			return Promise.resolve(form.Flag.prototype.render.apply(this, arguments)).then(function (node) {
				var tip = 'Oyun (Metin2 vb.) oynuyorsan TCP Mux KAPALI kalsın: açıkken oyuna girilemiyor ya da oyundan atılıyorsun. Varsayılan: kapalı.';
				if (node && node.setAttribute) {
					node.setAttribute('title', tip);
					var lab = node.querySelector('.cbi-value-title');
					if (lab) lab.setAttribute('title', tip);
				}
				return node;
			});
		};
		o = s.taboption('stable', form.Flag, 'ws_early', 'WebSocket erken veri',
			'Path\'e "?ed=2048" ekler. Bazı sunucu/CDN kurulumlarında sorun çıkarabildiği için varsayılan kapalı.');
		o.default = '0';
		o.rmempty = false;
		o = s.taboption('stable', form.Flag, 'ad_block', 'Reklam engelleme', 'geosite:category-ads-all');

		o = s.taboption('sub', form.DynamicList, 'sub_url', 'Abonelik adresleri', 'x-ui / 3x-ui abonelik linki (base64 veya düz liste).');
		o = s.taboption('sub', form.ListValue, 'sub_interval', 'Otomatik güncelleme');
		o.value('0', 'Kapalı');
		['3', '6', '12', '24'].forEach(h => o.value(h, h + ' saatte bir'));
		o.default = '12';

		o = s.taboption('adv', form.ListValue, 'log_level', 'Günlük seviyesi');
		['none', 'error', 'warning', 'info', 'debug'].forEach(v => o.value(v));
		o.default = 'warning';
		o = s.taboption('adv', form.Value, 'probe_url', 'Ölçüm adresi (ping / sağlık)',
			'Listeden seç ya da kendi adresini yaz. 204 döndüren küçük bir adres olmalı.');
		o.value('https://www.gstatic.com/generate_204', 'Google (gstatic)');
		o.value('https://cp.cloudflare.com/generate_204', 'Cloudflare');
		o.default = 'https://www.gstatic.com/generate_204';
		o = s.taboption('adv', form.Value, 'probe_url2', 'Yedek ölçüm adresi',
			'Birincisi yanıt vermezse bu denenir; ikisi de yanıt vermezse sunucu düşmüş sayılır. Boş = yedek yok.');
		o.value('https://cp.cloudflare.com/generate_204', 'Cloudflare');
		o.value('https://www.gstatic.com/generate_204', 'Google (gstatic)');
		o.value('', 'Yedek yok');
		o.default = 'https://cp.cloudflare.com/generate_204';
		o = s.taboption('adv', form.Value, 'probe_interval', 'Otomatik mod ölçüm aralığı');
		o.default = '2m';
		o = s.taboption('adv', form.Value, 'tproxy_port', 'Yakalama (redirect/TPROXY) portu'); o.datatype = 'port'; o.default = '12345';
		o = s.taboption('adv', form.Value, 'dns_port', 'Xray DNS portu'); o.datatype = 'port'; o.default = '15353';
		o = s.taboption('adv', form.Value, 'socks_port', 'Yerel SOCKS5 portu (hev bu porta bağlanır)'); o.datatype = 'port'; o.default = '10808';
		o = s.taboption('adv', form.Value, 'tun_mtu', 'TUN MTU', 'Yalnızca TUN yakalama modunda ve UDP için kullanılır. Varsayılan 8500; hat ya da sunucu büyük paketleri düşürüyorsa 1400-1500 dene. 576-9000 arası. Değiştirince VPN yeniden başlar.');
		o.datatype = 'range(576,9000)'; o.placeholder = '8500';
		o = s.taboption('adv', form.Value, 'hev_bin', 'hev-socks5-tunnel yolu', 'Boş = sistemdeki hev-socks5-tunnel');
		o = s.taboption('adv', form.Value, 'api_port', 'Xray API portu'); o.datatype = 'port'; o.default = '10085';
		o = s.taboption('adv', form.Value, 'xray_bin', 'Xray çekirdek yolu', 'Boş = /usr/share/kediray/bin/xray');

		o = s.taboption('band', form.DummyValue, '_smart', 'Akıllı band seçimi');
		o.cfgvalue = () => '';
		o.renderWidget = function () { return krSmartBand(); };

		o = s.taboption('band', form.Button, '_bandunlock', 'Bant kilidini kaldır');
		o.inputtitle = 'Tüm bantları aç';
		o.inputstyle = 'remove';
		o.onclick = function () {
			return fs.exec('/usr/bin/kediray', ['band', 'unlock']).then(r => ui.addNotification(null, E('p', {}, (r.stdout || r.stderr || 'Tamam').trim()), 'info'));
		};

		o = s.taboption('look', form.DummyValue, '_look', 'Tema');
		o.cfgvalue = () => '';
		o.renderWidget = function () {
			const get = () => { try { return JSON.parse(localStorage.getItem('kediray-theme') || '{}') || {}; } catch (e) { return {}; } };
			const put = v => { try { localStorage.setItem('kediray-theme', JSON.stringify(v)); } catch (e) {} krTheme(); draw(); };
			const root = E('div', {});
			const draw = () => {
				const c = get(), mode = c.mode || 'auto', ac = c.accent || '';
				const seg = (val, label) => E('button', { 'class': 'btn cbi-button' + (mode === val ? ' cbi-button-action' : ''), 'style': 'margin-right:6px',
					'click': ui.createHandlerFn(this, () => put(Object.assign({}, get(), { mode: val }))) }, label);
				const presets = [['#2a7de1', 'Mavi'], ['#22a355', 'Yeşil'], ['#8b5cf6', 'Mor'], ['#f08c1b', 'Turuncu'], ['#e5487f', 'Pembe'], ['#d23f3f', 'Kırmızı'], ['#14b8a6', 'Turkuaz']];
				const sw = presets.map(x => E('button', { 'title': x[1], 'class': 'btn',
					'style': 'width:34px;height:34px;padding:0;margin:0 6px 6px 0;border-radius:50%;background:' + x[0] + '!important;border:' + (ac.toLowerCase() === x[0] ? '3px solid #fff;box-shadow:0 0 0 2px ' + x[0] : '2px solid rgba(128,128,128,.4)'),
					'click': ui.createHandlerFn(this, () => put(Object.assign({}, get(), { accent: x[0] }))) }, ''));
				const pick = E('input', { 'type': 'color', 'value': ac || '#2a7de1', 'style': 'width:46px;height:34px;padding:0;vertical-align:middle' });
				pick.addEventListener('change', () => put(Object.assign({}, get(), { accent: pick.value })));
				dom.content(root, [
					E('div', { 'style': 'margin-bottom:6px' }, E('b', {}, 'Mod')),
					E('div', { 'style': 'margin-bottom:14px' }, [seg('auto', 'Otomatik'), seg('light', 'Açık'), seg('dark', 'Koyu')]),
					E('div', { 'style': 'margin-bottom:6px' }, E('b', {}, 'Vurgu rengi')),
					E('div', { 'style': 'margin-bottom:8px' }, sw),
					E('div', { 'style': 'margin-bottom:14px' }, [E('span', {}, 'Kendi rengin: '), pick, ' ',
						E('button', { 'class': 'btn cbi-button', 'click': ui.createHandlerFn(this, () => { const v = get(); delete v.accent; put(v); }) }, 'Rengi sıfırla')]),
					E('div', { 'class': 'cbi-value-description' }, 'Otomatik: LuCI\'nin kendi teması kalır. Açık/Koyu yalnızca KediRay sayfalarının renklerini zorlar. Vurgu rengi butonlara, seçili sekmelere, kart çizgisine ve trafik grafiğindeki VPN rengine uygulanır. Seçim bu tarayıcıda saklanır (telefonda ve bilgisayarda ayrı ayrı seçilir).')
				]);
			};
			draw();
			return root;
		};

		return m.render().then(n => { const w = document.createElement('div'); w.appendChild(krLicBanner()); w.appendChild(n); return w; });
	},

	handleSave: function () {
		const a = arguments;
		return krLicGuard().then(ok => ok ? this.super('handleSave', a) : null);
	},

	handleSaveApply: function () {
		const a = arguments;
		return krLicGuard().then(ok => ok ? this.super('handleSaveApply', a) : null);
	}
});
