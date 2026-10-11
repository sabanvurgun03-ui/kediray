<img width="1280" height="640" alt="Adsız" src="https://github.com/user-attachments/assets/8e70a937-f925-4329-a42f-e500c324ed05" />
# KediRay

OpenWrt için Xray tabanlı VPN
Özellikler

VPN ve sunucular

Xray tabanlı VPN. vless://, vmess://, trojan://, ss:// linkleri ya da Xray JSON’u ile sunucu ekleme
Birden fazla sunucu, abonelik desteği, sunucuyu açma/kapama ve düzenleme (kaydetmeden önce denetler)
En hızlı sunucuyu bulma ve otomatik geçiş (açıp kapatılabilir); geçişte mevcut bağlantılar kopmaz
Bağlantıyı kes: sunucudan ayrıl, VPN açık kalsın, trafik doğrudan çıksın
Sunucu sertifikasını sabitleme ve görüntüleme (pin, cert)
xDivine-Ray sunucularını aktarma; başka VPN’den güvenli geçiş (takeover), internet gelmezse otomatik geri alır

Yönlendirme

VPN Ayırma: uygulama bazında yol seçimi (VPN, doğrudan, WARP, parçalama). Hazır WhatsApp, Metin2, Teams kuralları; kendi uygulamanı alan adı, IP ve portla ekleyebilirsin
Cihaz bazında yön (VPN, doğrudan, engelle, varsayılan)
Doğrudan çıkış yoksa “doğrudan” seçilenleri otomatik VPN’e alma
DNS tünelleme seçeneği; DoH engelleme

Hız ve teşhis

Hız testi (doğrudan ve VPN), sunucu gecikmesi ölçümü
Tek komutluk teşhis (doctor, check), sayfa açılış gecikmesi, DNS yolu testleri
Aktif bağlantılar, bağlantı kaydı ve kopma teşhisi
Yapılandırma denetimi (validate, Xray testi)

Arayüz (LuCI)

Kontrol Paneli, Trafik, VPN Ayırma, Ayarlar, Günlük, Hakkında sayfaları
Trafik: bugün / hafta / ay kullanımı; kartları gizleme ve sıralama
Açık/koyu ve renk temaları
Günlük: hata gruplama

Modem (QModem)

Otomatik en iyi bant / frekans seçimi (isteğe bağlı)
Akıllı bant seçimi: bantları tek tek dener, hız ve sinyale göre seçer
QModem açılış yavaşlığı yaması

Bakım

GitHub’dan güncelleme (SHA256 doğrulamalı), dosyayla güncelleme
Xray çekirdeği ve coğrafi veri güncelleme
AW1K Panel Android uygulamasıyla uyumlu

#English

Features

VPN and servers

Xray-based VPN. Add servers from vless://, vmess://, trojan://, ss:// links or Xray JSON
Multiple servers, subscriptions, enable/disable and edit servers (validated before saving)
Find the fastest server and switch automatically (can be turned on/off); switching doesn’t drop existing connections
Disconnect: leave the server but keep the VPN on; traffic goes out directly
Server certificate pinning and inspection (pin, cert)
Import xDivine-Ray servers; safe takeover from another VPN (takeover) with automatic rollback if the internet breaks

Routing

Split routing: per-app route (VPN, direct, WARP, fragmentation). Ready-made WhatsApp, Metin2 and Teams rules; add your own apps by domain, IP and port
Per-device route (VPN, direct, block, default)
Automatically send “direct” apps through the VPN when there is no direct internet
DNS tunnelling option; DoH blocking

Speed and diagnostics

Speed test (direct and VPN), server latency measurement
One-command diagnosis (doctor, check), page-load latency, DNS path tests
Active connections, connection logging and drop diagnosis
Configuration validation (validate, Xray test)

Interface (LuCI)

Dashboard, Traffic, Split Routing, Settings, Log and About pages
Traffic: today / week / month usage; hide and reorder cards
Light/dark and color themes
Log: error grouping

Modem (QModem)

Optional automatic best band / frequency selection
Smart band selection: tries each band in turn and picks by speed and signal
QModem slow-boot patch

Maintenance

Update from GitHub (SHA256 verified), update from a file
Xray core and geo-data updates
Works with the AW1K Panel Android app

## Kurulum

Modemde SSH ile:

    wget -O /tmp/kediray.sh https://raw.githubusercontent.com/sabanvurgun03-ui/kediray/main/kediray-install.sh
    sh /tmp/kediray.sh

## Güncelleme

LuCI > KediRay > Hakkında > **GitHub'dan güncelle**, ya da SSH: `kediray update install`

## Install

Over SSH on the router:

wget -O /tmp/kediray.sh https://raw.githubusercontent.com/sabanvurgun03-ui/kediray/main/kediray-install.sh
sh /tmp/kediray.sh

## Update

LuCI > KediRay > About > Update from GitHub, or over SSH: kediray update install

Geliştirici: Şaban Vurgun
