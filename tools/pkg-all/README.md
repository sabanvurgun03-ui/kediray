# KediRay @VERSION@ — kediray-all (firmware'e gömme paketi)

KediRay'i OpenWrt imajına hazır gömmek içindir. Kurulum betiğinin (`kediray-install.sh`) çalışma anında yazdığı dosyalar
olduğu gibi `files/` altında; betiğin ilk açılışta yaptığı işler de `files/etc/uci-defaults/99-kediray` oldu.

Bu paket **mimariden bağımsızdır** (aarch64, armv7, mips, mipsel, riscv64, x86_64 ... hepsinde aynı): KediRay yalnızca betik,
ucode ve JavaScript'ten oluşur, derlenmiş dosya içermez. Xray çekirdeği ve `hev-socks5-tunnel` imaja paket olarak eklenir (aşağıda).

| Yol | Ne |
|---|---|
| `files/` | İmaja kopyalanacak dosya ağacı (`/usr/bin/kediray`, `/etc/init.d/kediray`, LuCI görünümleri, ACL, menü, varsayılan `/etc/config/kediray`, **AW1K Panel** dosyaları...) |
| `files/etc/uci-defaults/99-kediray` | İlk açılışta bir kez çalışır: izinler, yakalama modu seçimi, güvenlik duvarı bölgesi (`kediray0`), cron (bekçi + gece 01:00 sürüm denetimi + AW1K veri kaydı), servis etkinleştirme |
| `packages.txt` | İmaja eklenecek paketler (satır satır) |
| `LICENSE`, `NOTICE` | GPL-3.0-or-later, telif bildirimi |
| `README-KediRay.md`, `docs/` | GitHub deposundaki README ve görseller |

## Kullanım

**Image Builder:**
```sh
tar xzf kediray-all.tar.gz
make image PROFILE=<profil> PACKAGES="$(tr '\n' ' ' < kediray-all-@VERSION@/packages.txt)" FILES=$PWD/kediray-all-@VERSION@/files
```
**Buildroot:** `files/` içeriğini kaynak ağacındaki `files/` dizinine kopyala, paketleri `make menuconfig`ten seç.
Dosya izinleri korunmalı (`tar -p`); korunmasa da `99-kediray` ilk açılışta düzeltir.

**Bütünlük:** release'teki `sha256sums` ile doğrula: `sha256sum -c sha256sums`.

## Gereksinimler

- OpenWrt **22.03 ve üstü** (fw4/nftables), LuCI (`luci-base`); `apk` ya da `opkg` fark etmez.
- `xray-core`: KediRay yeni Xray sürümlerine göre yazıldı. **Beslemendeki `xray-core` sürümünü kontrol et**; eskiyse
  `/usr/share/kediray/bin/xray` olarak daha yeni bir ikili koy ya da ilk açılıştan sonra internetle `kediray update-core` çalıştır
  (GitHub'dan çekirdek + geoip/geosite indirir, ~70 MB boş alan ister).
- `v2ray-geoip` / `v2ray-geosite` paketleri `/usr/share/v2ray` altına kurulur, KediRay orayı da tanır. Dosyalar yoksa Xray başlamaz.
- Yer kısıtlıysa `kmod-nft-tproxy` ve `kmod-nft-socket` çıkarılabilir (sadece yedek mod); `conntrack` isteğe bağlıdır.

## Davranış notları

- Varsayılan ayarda VPN **kapalı** gelir (`enabled '0'`). Sunucu eklenip panelden açılır: LuCI → VPN → KediRay VPN.
- Yakalama modu ilk açılışta seçilir: `hev-socks5-tunnel` + TUN varsa `mixed`, yoksa `tproxy`, o da yoksa `redirect` (sadece TCP).
- Kurulum betiğindeki "çakışan VPN servisleri", port çakışması kontrolü, Metin2/Teams soruları ve QModem yaması pakete alınmadı
  (cihaza özel ya da etkileşimli adımlar). Gerekirse `kediray conflicts` ve panel ayarları aynı işi görür.
- Gece 01:00 `kediray update auto` yalnızca sürüm denetler (otomatik kurulum ayarı kapalıdır). İstemiyorsan
  `99-kediray` içindeki iki cron satırından ikincisini sil ya da panelde "Güncellemeleri kontrol et"i kapat.

## AW1K Panel (Android uygulaması) tarafı

GitHub'daki kurulum betiğinin kurduğu her şey pakette: `/usr/bin/aw1k-usage` (günlük mobil veri kaydı, 2 dakikada bir cron),
`/usr/libexec/rpcd/aw1k` (uygulamanın konuştuğu ubus eklentisi: veri kullanımı, KediRay aç/kapat, cihaz yönleri, Wi-Fi istemcileri,
misafir Wi-Fi, WAN bilgisi) ve `/usr/share/rpcd/acl.d/aw1k-panel.json`. İlk açılışta rpcd bunları kendiliğinden yükler.

- `aw1k-usage` ve `wan_info` mobil arayüz olarak **`wwan0_1`**'i (AW1000'deki modem arayüzü) kullanır; bu cihaz yoksa
  `wan` arayüzünün cihazına (ör. `eth1`), o da çözülemezse `wan` adına düşer. Başka bir ad istersen iki dosyada da `wwan0_1`'i değiştir.
- `wifi_clients` / `kediray_devices` için `hostapd` ve `iwinfo` ubus nesneleri gerekir (Wi-Fi'lı standart imajlarda vardır).
- Android uygulamasının kendisi (APK / proje kaynağı) pakette **yok**; paket yalnızca modemde çalışan arka ucu içerir.
  APK, deponun Releases sayfasında ayrı bir sürüm olarak durur.

## Yeniden üretmek

Paket, depodaki kaynak ağacından üretilir (kurulum betiği de aynı ağaçtan çıkar): `./build.sh`.
Aynı girdiden her seferinde birebir aynı dosya çıkar. `kediray-src.tar.gz` kaynak ağacının kendisidir.

Kaynak ve güncel sürüm: https://github.com/sabanvurgun03-ui/kediray

---

# English (short)

`kediray-all` is a drop-in overlay to bake KediRay @VERSION@ into an OpenWrt image. It is **architecture-independent** (shell, ucode and
JavaScript only; no compiled binaries), so one package fits aarch64, armv7, mips, mipsel, riscv64, x86_64 and so on.
`files/` is the exact file tree the installer writes at runtime; `files/etc/uci-defaults/99-kediray` does the installer's
first-boot work (permissions, capture mode, `kediray0` firewall zone, cron, service enable). Use `packages.txt` with
`PACKAGES=` and `FILES=` in Image Builder (or copy `files/` into buildroot). Needs OpenWrt 22.03+ (fw4/nftables) and LuCI;
check that your feed's `xray-core` is recent enough. The AW1K Panel router-side files (usage logger, rpcd plugin, ACL) are
included too; the Android app itself is not. VPN ships disabled until a server is added. Verify with `sha256sum -c sha256sums`.
Rebuild from the repo with `./build.sh`. GPL-3.0-or-later.
