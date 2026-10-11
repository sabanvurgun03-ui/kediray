# KediRay

**Türkçe** · [English](#english)

OpenWrt için Xray tabanlı VPN. LuCI arayüzü ve `kediray` komut satırı aracıyla gelir. Geliştirici: Şaban Vurgun.

## Özellikler

- Xray tabanlı VPN, birden fazla sunucu (düğüm), en iyi sunucuyu otomatik seçme
- **Bağlantıyı kes:** sunucudan ayrıl, VPN açık kalsın, trafik doğrudan çıksın
- **VPN Ayırma:** uygulama bazında yol seçimi (VPN, doğrudan, WARP, parçalama)
- Trafik sayfası: bugün / bu hafta / bu ay kullanımı, kartları gizle ve sırala
- Bant sekmesi: modem bant taraması ve akıllı bant seçimi (QModem gerekir)
- Görünüm: açık/koyu ve renk temaları
- **Yedekle / geri yükle:** sunucular, uygulama kuralları ve ayarlar tek dosyada (modemi sıfırlayınca geri getir)
- GitHub'dan güncelleme (SHA256 doğrulamalı)
- [AW1K Panel](https://github.com/sabanvurgun03-ui/aw1kpanel) Android uygulamasıyla uyumlu

## Kurulum

Modemde SSH ile:

    wget -O /tmp/kediray.sh https://raw.githubusercontent.com/sabanvurgun03-ui/kediray/main/kediray-install.sh
    sh /tmp/kediray.sh

Kurulumdan sonra LuCI'de **VPN → KediRay VPN** menüsünü aç. Sayfa eski görünürse Ctrl+Shift+R yap.

## Güncelleme

LuCI → KediRay → **Hakkında → GitHub'dan güncelle**, ya da SSH:

    kediray update check
    kediray update install

Dosya GitHub'dan indirilir ve `kediray-install.sh.sha256` ile doğrulanır. Uyuşmazsa kurulmaz.

## Yedekleme

LuCI → KediRay → **Hakkında → Yedekle / geri yükle**, ya da SSH:

    kediray backup /tmp/yedek.conf
    kediray restore /tmp/yedek.conf

Yedek dosyası sunucu kimliklerini (UUID) içerir. **Kimseyle paylaşma, GitHub'a yükleme.**

## Notlar

- Modemin GitHub'a erişebilmesi gerekir (`raw.githubusercontent.com`).
- Kurulum, aynı anda çalışan başka bir transparan proxy ile (örneğin xDivine-Ray) çakışabilir. Geçiş için: `kediray takeover`.

---

<a name="english"></a>
## English

Xray-based VPN for OpenWrt, with a LuCI interface and the `kediray` command-line tool. Developer: Şaban Vurgun.

### Features

- Xray-based VPN with multiple servers (nodes) and automatic best-server selection
- **Disconnect:** leave the server but keep the VPN on, traffic goes out directly
- **Split routing:** per-app route (VPN, direct, WARP, fragmentation)
- Traffic page: today / this week / this month usage, hide and reorder cards
- Band tab: modem band scan and smart band selection (needs QModem)
- Appearance: light/dark and color themes
- **Backup / restore:** servers, app rules and settings in one file (bring them back after a router reset)
- Update from GitHub (SHA256 verified)
- Works with the [AW1K Panel](https://github.com/sabanvurgun03-ui/aw1kpanel) Android app

### Install

Over SSH on the router:

    wget -O /tmp/kediray.sh https://raw.githubusercontent.com/sabanvurgun03-ui/kediray/main/kediray-install.sh
    sh /tmp/kediray.sh

Then open **VPN → KediRay VPN** in LuCI. If the page looks stale, press Ctrl+Shift+R.

### Update

LuCI → KediRay → **About → Update from GitHub**, or over SSH:

    kediray update check
    kediray update install

The file is downloaded from GitHub and checked against `kediray-install.sh.sha256`. It is not installed if they don't match.

### Backup

LuCI → KediRay → **About → Backup / restore**, or over SSH:

    kediray backup /tmp/backup.conf
    kediray restore /tmp/backup.conf

The backup file contains server IDs (UUIDs). **Do not share it or upload it to GitHub.**

### Notes

- The router must be able to reach GitHub (`raw.githubusercontent.com`).
- It can conflict with another transparent proxy running at the same time (e.g. xDivine-Ray). To switch: `kediray takeover`.
