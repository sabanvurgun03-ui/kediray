# KediRay (OpenWrt VPN) — proje notları

Şaban Vurgun'un kendi VPN paketi (LuCI arayüzü + ucode + shell). Repo: sabanvurgun03-ui/kediray.
Düğüm: `package/kediray/files/usr/bin/kediray` (shell), `.../usr/share/kediray/gen.uc`, `traffic.uc`; LuCI: `luci-app-kediray/htdocs/luci-static/` (`kedi.css`, `resources/view/kediray/*.js`).

## Çalışma kuralları
- Cevaplar kısa; dosya yolunu tam yaz; sürümü kendin artır (`VERSION`; kurulum başlığı KR_VERSION ile senkron kalır).
- Teslimde her zaman `/tmp/claude-0/out/kediray/kediray-install.sh` gönder.
- Tahmin etme, araştır ve kaynak göster; karar veremezsen sor. İş bitince `/compact` hatırlat.
- Bulutta ucode yok: kod çalıştırılamaz, modemde denenir. nft kuralları bulutta `apt-get install nftables iproute2` + `unshare -rnm` ile yalıtılmış ağ alanında denenebilir.

## Derleme
`./build.sh --out /tmp/claude-0/out/kediray`

## Teknik notlar
- mihomo yerel mod: TUN `kediray0`, güvenlik duvarı masq → mihomo kaynak IP'yi 198.18.0.1 görür; SRC-IP/exclude-mac işe yaramaz. Cihaz Direkt/İnternetsiz `ip rule` pref 8990 (lookup main / prohibit) ile yapılır (`dev_route_sync`, `devip_watch`).
- Tema CSS: `html[data-kedi] body button.cbi-button` genel kuralı yüksek özgüllükte; renkli düğme kuralları ona göre yazılmalı.

## Yapılanlar (yeniden eskiye)
- 1.21.0: **Bağlantı testi** (`kediray conns`, `view/kediray/conns.js`; Kontrol paneli/Trafik cihaz "Bağlantılar", VPN Ayırma "Bağlantı testi" ve uygulama başına "Test"): her bağlantının gerçekte hangi yoldan gittiği. mihomo/sing-box: çekirdeğin `/connections` + `/proxies` (chains[0] = gerçek çıkış, rule/rulePayload), cihaz conntrack'ten (kaynak port / NAT'lı yanıt portu) bulunur. Xray: conntrack; çekirdeğe girip modemden aynı hedefe direkt bağlantı açıldıysa Direkt. Uygulama kuralıyla eşleşen (alan adı/IP/port; geosite/geoip çekirdeğin kuralından) ve yolu tutmayan bağlantı "Yanlış yol". Kendi modda denetim yok (KediRay uygulamaları kullanılmıyor). TPROXY'de `ct mark` eklendi (tanıma için). Bulutta node uyarlamasıyla örnek veride denendi; modemde doğrulanmadı.
- 1.21.0 düzeltmeler: (1) `p_tcp` `|| [ $? = 22 ] || [ $? = 52 ]` zinciri 52/56'yı hiç başarılı saymıyordu. (2) DNS acil yedeğinde yoklama dnsmasq'a (operatör DNS) gidip yedeği bir dakikada kapatıyordu → yedekteyken çekirdek `127.0.0.1:dns_port` yoklanır (busybox nslookup host:port kabul eder, libbb str2sockaddr). (3) hotplug iface: kural denetimi her modda `lookup 107` (TPROXY) arıyordu; mixed'de (108) her ifup'ta kurallar söküp yeniden kuruluyordu. (4) Panel 5 sn'de bir mihomo/sing-box ikilisini sürüm için çalıştırıyordu → `$RUN/ver.<çekirdek>` önbelleği (yol+boyut). (5) Cihaz trafik sayacı: IP başına kural (128'e kadar, silinmiyordu, her paket hepsini geziyordu) → zincir başına tek kural + `ipv4_addr : counter` map (`u_`/`d_` + IP); eski tablo bir kez silinir. nft ile ağ ad alanında (unshare -rnm) denendi.
- 1.20.9: mihomo'da (kendi yapılandırma ve yerel mod) "QUIC'i reddet" çalışmıyordu: nft `quic_fwd` own/native'de kurulmuyor. Kendi modda çalıştırılan kopyanın `rules:` başına `AND,((NETWORK,UDP),(DST-PORT,443)),REJECT` eklenir (`mh_quic_inject`; kullanıcı dosyası değişmez, zaten varsa eklenmez, yapılandırma testi geçmezse kuralsız devam). Yerel modda gen.uc `R`'ye eklenir; şablona (MH_YAML) yazılmaz. Not: TCP Mux düğmesi mihomo'ya `smux` yazmıyor (yalnız Xray `mux_for`).
- 1.20.8: Uygulama profilinde sonu noktalı alan adı (googleusercontent.com.) mihomo'da 'trailing dot is not allowed' ile yapılandırmayı bozuyor, VPN başlamıyordu. `dom()` (gen.uc) ve `app-add`/`add-domain` sondaki noktayı kırpar.
- 1.20.7: Kendi modda LAN'a IPv6 DNS duyurulmaz (`dhcp.lan.ra_dns=0`, kapanınca eski değer); PC'de DNS 2 sn zaman aşımı biter.
- 1.20.6: Hız testi indirme: Cloudflare `__down` bu modemde bytes>=10000000 için 429 veriyor (5000000 ve altı 200; modemde ölçüldü) → istek 5 MB.
- 1.20.5: Hız testi indirmesinde Cloudflare 429 (istek sınırı) verirse Hetzner `fsn1-speed.hetzner.com/100MB.bin` yedeği (`aw1k-speedtest`). Yükleme hâlâ Cloudflare.
- 1.20.4: Hız testi indirme 0.00 çıkıyordu: her istekte HTTP kodu + curl çıkış kodu kaydedilir, yalnızca HTTP 200 baytları sayılır, hata kutusunda neden yazar (`aw1k-speedtest`).
- 1.20.3: Hız testini durdurma: rpcd `speedtest_stop` (betiği ve curl'leri sonlandırır, durumu idle yapar).
- 1.20.2: AW1K Panel hız testi için modem tarafı: `package/aw1k-panel/files/usr/bin/aw1k-speedtest` (Cloudflare speed.cloudflare.com, curl, 4 paralel, 8 sn) + rpcd `speedtest_start/speedtest_status` + ACL.
- 1.20.0 (sürüm aynı): Hakkında sayfasına "Kedi LuCI teması" kartı + `kediray theme` komutu (temayı GitHub'dan indirip kurar/günceller).
- 1.20.1: Uygulamadan KediRay Başlat, LuCI'den Durdur sonrası çalışmıyordu (rpcd init.d'yi doğrudan çağırıyordu; artık `kediray start` ve enabled=1 yapıyor).
- 1.20.0: Bağlantıyı kes / Sil (negative) düğmeleri kırmızı (CSS özgüllük düzeltmesi).
- 1.19.99: mihomo yerel modda cihaz Direkt/İnternetsiz çalışıyor (kernel ip rule).
- 1.19.98: SRC-IP kuralı denemesi (masq yüzünden yetersiz kaldı).
- 1.19.97: 12 aydan eski aylık trafik toplamları silinir.
