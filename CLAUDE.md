# KediRay (OpenWrt VPN) — proje notları

Şaban Vurgun'un kendi VPN paketi (LuCI arayüzü + ucode + shell). Repo: sabanvurgun03-ui/kediray.
Düğüm: `package/kediray/files/usr/bin/kediray` (shell), `.../usr/share/kediray/gen.uc`, `traffic.uc`; LuCI: `luci-app-kediray/htdocs/luci-static/` (`kedi.css`, `resources/view/kediray/*.js`).

## Çalışma kuralları
- Cevaplar kısa; dosya yolunu tam yaz; sürümü kendin artır (`VERSION`; kurulum başlığı KR_VERSION ile senkron kalır).
- Teslimde her zaman `/tmp/claude-0/out/kediray/kediray-install.sh` gönder.
- Tahmin etme, araştır ve kaynak göster; karar veremezsen sor. İş bitince `/compact` hatırlat.
- Bulutta ucode yok: kod çalıştırılamaz, modemde denenir.

## Derleme
`./build.sh --out /tmp/claude-0/out/kediray`

## Teknik notlar
- mihomo yerel mod: TUN `kediray0`, güvenlik duvarı masq → mihomo kaynak IP'yi 198.18.0.1 görür; SRC-IP/exclude-mac işe yaramaz. Cihaz Direkt/İnternetsiz `ip rule` pref 8990 (lookup main / prohibit) ile yapılır (`dev_route_sync`, `devip_watch`).
- Tema CSS: `html[data-kedi] body button.cbi-button` genel kuralı yüksek özgüllükte; renkli düğme kuralları ona göre yazılmalı.

## Yapılanlar (yeniden eskiye)
- 1.20.3: Hız testini durdurma: rpcd `speedtest_stop` (betiği ve curl'leri sonlandırır, durumu idle yapar).
- 1.20.2: AW1K Panel hız testi için modem tarafı: `package/aw1k-panel/files/usr/bin/aw1k-speedtest` (Cloudflare speed.cloudflare.com, curl, 4 paralel, 8 sn) + rpcd `speedtest_start/speedtest_status` + ACL.
- 1.20.0 (sürüm aynı): Hakkında sayfasına "Kedi LuCI teması" kartı + `kediray theme` komutu (temayı GitHub'dan indirip kurar/günceller).
- 1.20.1: Uygulamadan KediRay Başlat, LuCI'den Durdur sonrası çalışmıyordu (rpcd init.d'yi doğrudan çağırıyordu; artık `kediray start` ve enabled=1 yapıyor).
- 1.20.0: Bağlantıyı kes / Sil (negative) düğmeleri kırmızı (CSS özgüllük düzeltmesi).
- 1.19.99: mihomo yerel modda cihaz Direkt/İnternetsiz çalışıyor (kernel ip rule).
- 1.19.98: SRC-IP kuralı denemesi (masq yüzünden yetersiz kaldı).
- 1.19.97: 12 aydan eski aylık trafik toplamları silinir.
