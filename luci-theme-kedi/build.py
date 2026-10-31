#!/usr/bin/env python3
"""luci-theme-kedi tek dosyalık kurulum betiğini üretir: dist/luci-theme-kedi-install.sh
Kullanım: python3 luci-theme-kedi/build.py   (önce gen-css.py çalışır)"""
import os, base64, subprocess, sys
here = os.path.dirname(os.path.abspath(__file__))
subprocess.check_call([sys.executable, os.path.join(here, 'gen-css.py')])
ver = open(os.path.join(here, 'VERSION')).read().strip()
H = os.path.join(here, 'htdocs/luci-static')
FILES = [  # (kaynak, hedef, kip)
    ('htdocs/luci-static/kedi/cascade.css', '/www/luci-static/kedi/cascade.css', '644'),
    ('htdocs/luci-static/kedi/mobile.css', '/www/luci-static/kedi/mobile.css', '644'),
    ('htdocs/luci-static/kedi/kedi.css', '/www/luci-static/kedi/kedi.css', '644'),
    ('htdocs/luci-static/kedi/logo.svg', '/www/luci-static/kedi/logo.svg', '644'),
    ('htdocs/luci-static/kedi/logo_48.png', '/www/luci-static/kedi/logo_48.png', '644'),
    ('htdocs/luci-static/resources/menu-kedi.js', '/www/luci-static/resources/menu-kedi.js', '644'),
    ('htdocs/luci-static/resources/view/kedi/sysauth.js', '/www/luci-static/resources/view/kedi/sysauth.js', '644'),
    ('ucode/template/themes/kedi/header.ut', '@TPL@/kedi/header.ut', '644'),
    ('ucode/template/themes/kedi/footer.ut', '@TPL@/kedi/footer.ut', '644'),
    ('ucode/template/themes/kedi/sysauth.ut', '@TPL@/kedi/sysauth.ut', '644'),
]
out = ['''#!/bin/sh
# ============================================================================
#  luci-theme-kedi %s — OpenWrt LuCI için mor Kedi teması (koyu / açık / otomatik)
#  Bootstrap temasından türetilmiştir (Apache-2.0); Kedi renkleri ve düzeni eklidir.
#
#  Kurulum:  sh luci-theme-kedi-install.sh            (temayı kurar ve etkinleştirir)
#            sh luci-theme-kedi-install.sh --no-activate   (kurar, etkinleştirmez)
#  Kaldırma: sh luci-theme-kedi-install.sh --remove   (eski temaya döner, dosyaları siler)
#  Seçim:    Sistem → Görünüm (System → Style) → Tema: Kedi
# ============================================================================
KT_VERSION="%s"
ROOT="${KT_ROOT:-}"          # yalnızca deneme için: dosyalar bu klasörün altına yazılır
MODE=install
for a in "$@"; do case "$a" in --remove) MODE=remove ;; --no-activate) MODE=noact ;; esac; done

TPL=/usr/share/ucode/luci/template/themes
[ -d "$ROOT$TPL" ] || [ -n "$ROOT" ] || { echo "Bu LuCI sürümü desteklenmiyor (ucode şablon klasörü yok: $TPL). OpenWrt 23.05 ve üstü gerekir."; exit 1; }
[ -d "$ROOT/www/luci-static" ] || [ -n "$ROOT" ] || { echo "/www/luci-static bulunamadı; LuCI kurulu görünmüyor."; exit 1; }

clear_cache() { rm -rf /tmp/luci-indexcache* /tmp/luci-modulecache 2>/dev/null; }

if [ "$MODE" = remove ]; then
	if [ -z "$ROOT" ] && command -v uci >/dev/null 2>&1; then
		cur=$(uci -q get luci.main.mediaurlbase)
		if [ "$cur" = /luci-static/kedi ]; then
			prev=$(cat /etc/luci-theme-kedi.prev 2>/dev/null)
			[ -n "$prev" ] || prev=/luci-static/bootstrap
			uci set luci.main.mediaurlbase="$prev"
		fi
		uci -q delete luci.themes.Kedi
		uci commit luci
	fi
	rm -rf "$ROOT/www/luci-static/kedi" "$ROOT/www/luci-static/resources/menu-kedi.js" "$ROOT/www/luci-static/resources/view/kedi" "$ROOT$TPL/kedi" "$ROOT/etc/luci-theme-kedi.prev"
	[ -z "$ROOT" ] && clear_cache
	echo "luci-theme-kedi kaldırıldı."
	exit 0
fi

put() { # put <hedef> <kip> ; içerik stdin'den
	mkdir -p "$(dirname "$1")" && cat > "$1" && chmod "$2" "$1"
}
''' % (ver, ver)]
n = 0
for src, dst, mode in FILES:
    n += 1
    path = os.path.join(here, src)
    dstq = dst.replace('@TPL@', '$TPL')
    data = open(path, 'rb').read()
    if src.endswith('.png'):
        b = base64.b64encode(data).decode()
        lines = '\n'.join(b[i:i+76] for i in range(0, len(b), 76))
        out.append('base64 -d <<\'KT_EOF_%d\' | put "$ROOT%s" %s\n%s\nKT_EOF_%d\n' % (n, dstq, mode, lines, n))
    else:
        t = data.decode()
        assert ('\nKT_EOF_%d\n' % n) not in t
        out.append('put "$ROOT%s" %s <<\'KT_EOF_%d\'\n%s%sKT_EOF_%d\n' % (dstq, mode, n, t, '' if t.endswith('\n') else '\n', n))
out.append('''
if [ -z "$ROOT" ] && command -v uci >/dev/null 2>&1; then
	uci set luci.themes.Kedi=/luci-static/kedi
	if [ "$MODE" = install ]; then
		cur=$(uci -q get luci.main.mediaurlbase)
		[ "$cur" != /luci-static/kedi ] && [ -n "$cur" ] && echo "$cur" > /etc/luci-theme-kedi.prev
		uci set luci.main.mediaurlbase=/luci-static/kedi
	fi
	uci commit luci
	clear_cache
fi
echo "luci-theme-kedi $KT_VERSION kuruldu."
[ "$MODE" = install ] && echo "Tema etkin. Tarayıcıda sayfayı yenile (Ctrl+Shift+R). Geri almak için: sh $0 --remove"
[ "$MODE" = noact ] && echo "Etkinleştirmek için: Sistem → Görünüm → Tema: Kedi"
exit 0
''')
dist = os.path.join(here, '..', 'dist'); os.makedirs(dist, exist_ok=True)
p = os.path.join(dist, 'luci-theme-kedi-install.sh')
open(p, 'w').write(''.join(out)); os.chmod(p, 0o755)
print(p, os.path.getsize(p))
