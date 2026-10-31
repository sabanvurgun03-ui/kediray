#!/usr/bin/env python3
"""luci-theme-kedi/htdocs/luci-static/kedi/kedi.css = tema değişkenleri + ortak kurallar (luci-app-kediray/.../kedi.css'in Kontrol Paneli öncesi bölümü) + genel LuCI kuralları."""
import os
here = os.path.dirname(os.path.abspath(__file__))
src = open(os.path.join(here, '..', 'luci-app-kediray/htdocs/luci-static/kedi.css')).read()
body = src[:src.index('/* ---------- Kontrol Paneli: canlı trafik bandı')]
head = open(os.path.join(here, 'theme-vars.css')).read()
extra = open(os.path.join(here, 'theme-extra.css')).read()
open(os.path.join(here, 'htdocs/luci-static/kedi/kedi.css'), 'w').write(head + body + extra)
