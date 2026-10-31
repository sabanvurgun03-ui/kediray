# luci-theme-kedi

OpenWrt LuCI için mor **Kedi** teması: koyu / açık / otomatik (sistem teması). Bootstrap temasından türetilmiştir (Apache-2.0); renkler CSS değişkenleriyle değiştirilir, bu yüzden tüm LuCI sayfaları (Ağ, Güvenlik Duvarı, Sistem, giriş ekranı…) uyum sağlar. Telefonda da çalışır.

## Kurulum (modemde)

```sh
sh luci-theme-kedi-install.sh              # kurar ve etkinleştirir
sh luci-theme-kedi-install.sh --no-activate  # kurar, Sistem → Görünüm'den sen seçersin
sh luci-theme-kedi-install.sh --remove     # eski temaya döner, dosyaları siler
```

Gerekli: OpenWrt 23.05+ (ucode tabanlı LuCI). Kurulumdan sonra sayfayı Ctrl+Shift+R ile yenile.

## Koyu / açık seçimi

Otomatik: tarayıcı/sistem temasını izler. KediRay sayfalarındaki sağ alt tema düğmesi (🌙 ☀️ ◐) tüm LuCI için de geçerlidir.

## Derleme

```sh
python3 luci-theme-kedi/build.py   # dist/luci-theme-kedi-install.sh
```

`gen-css.py` tema CSS'ini üretir: `theme-vars.css` + `luci-app-kediray/.../kedi.css` (ortak kurallar) + `theme-extra.css`. OpenWrt kaynak ağacında `Makefile` ile paket (`luci-theme-kedi`) olarak da derlenebilir.
