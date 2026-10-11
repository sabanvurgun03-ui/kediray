#!/bin/sh
# ============================================================================
#  KediRay 1.19.52 — OpenWrt için Xray tabanlı akıllı VPN (tek tık kurulum)
#
#  Copyright (C) 2026 Şaban Vurgun
#  SPDX-License-Identifier: GPL-3.0-or-later
#  Bu program özgür yazılımdır: GNU GPL 3. sürüm ya da (isteğe bağlı) sonrası koşullarında
#  dağıtabilir ve değiştirebilirsiniz. Garanti verilmez. Ayrıntı: LICENSE dosyası.
#
#  Kurulum:   sh kediray-install.sh
#  Sessiz:    sh kediray-install.sh -y --metin2 direct --teams direct --sub 'https://...'
#  Kaldırma:  kediray uninstall        (ayarlar dahil: kediray uninstall --purge)
#
#  Seçenekler:
#    -y                 Soru sorma, varsayılanları kullan
#    --metin2 vpn|direct
#    --teams  vpn|direct
#    --sub URL          Abonelik adresi ekle
#    --link 'vless://…' Sunucu linki veya JSON ekle
#    --core-version vX  Belirli Xray sürümü (varsayılan: en son)
#    --force-core       Xray kurulu olsa da yeniden indir
#    --gh-proxy URL     GitHub indirmeleri için ayna/önek
#
#  Not: Xray çekirdeği ve paketler zaten kuruluysa indirilmez; yeniden kurulum hızlıdır.
# ============================================================================

KR_VERSION="1.19.52"
AUTO=0; ARG_METIN2=""; ARG_TEAMS=""; ARG_SUB=""; ARG_LINK=""; CORE_VER="latest"; FORCE_CORE=0

while [ $# -gt 0 ]; do
	case "$1" in
		-y|--yes) AUTO=1 ;;
		--metin2) ARG_METIN2="$2"; shift ;;
		--teams) ARG_TEAMS="$2"; shift ;;
		--sub) ARG_SUB="$2"; shift ;;
		--link) ARG_LINK="$2"; shift ;;
		--core-version) CORE_VER="$2"; shift ;;
		--force-core) FORCE_CORE=1 ;;
		--gh-proxy) export GH_PROXY="$2"; shift ;;
		-h|--help) sed -n '2,20p' "$0"; exit 0 ;;
	esac
	shift
done

if [ -t 1 ]; then
	C_G='\033[1;32m'; C_Y='\033[1;33m'; C_R='\033[1;31m'; C_B='\033[1;36m'; C_0='\033[0m'
else
	C_G=''; C_Y=''; C_R=''; C_B=''; C_0=''
fi
step() { printf "\n${C_B}==> %s${C_0}\n" "$*"; }
ok()   { printf "${C_G}  ✔ %s${C_0}\n" "$*"; }
warn() { printf "${C_Y}  ! %s${C_0}\n" "$*"; }
die()  { printf "${C_R}  ✘ %s${C_0}\n" "$*"; exit 1; }

TTY=""
if [ "$AUTO" != 1 ]; then
	if [ -t 0 ]; then TTY=/dev/stdin
	elif [ -r /dev/tty ] && ( : < /dev/tty ) 2>/dev/null; then TTY=/dev/tty
	else AUTO=1; fi
fi

# ask "soru" "varsayılan" -> $REPLY
ask() {
	REPLY="$2"
	[ "$AUTO" = 1 ] && return 0
	printf "  %s [%s]: " "$1" "$2"
	read -r REPLY < "$TTY" || REPLY=""
	[ -n "$REPLY" ] || REPLY="$2"
}
yesno() { # "soru" E|H
	ask "$1 (E/H)" "$2"
	case "$REPLY" in [EeYy]*) return 0 ;; *) return 1 ;; esac
}

cat <<'BANNER'

   /\_/\    KediRay — OpenWrt Xray VPN
  ( o.o )   WS dostu · bildirim düzeltmeli · cihaz/uygulama bazlı ayırma
   > ^ <    Metin2 & Teams: VPN ya da Direkt — seçim senin

BANNER

# ---------------------------------------------------------------- 1. kontroller
step "Sistem kontrol ediliyor"
[ "$(id -u)" = 0 ] || die "root olarak çalıştır"
[ -f /etc/openwrt_release ] || die "Bu bir OpenWrt sistemi değil"
. /etc/openwrt_release
ok "$DISTRIB_DESCRIPTION ($DISTRIB_ARCH)"
command -v nft >/dev/null 2>&1 || die "nftables (fw4) yok. OpenWrt 22.03 ve üstü gerekir."
command -v fw4 >/dev/null 2>&1 && ok "firewall4 / nftables"

if command -v apk >/dev/null 2>&1; then PM=apk
elif command -v opkg >/dev/null 2>&1; then PM=opkg
else die "Paket yöneticisi bulunamadı (apk/opkg)"; fi
ok "Paket yöneticisi: $PM"

pkg_installed() {
	if [ "$PM" = apk ]; then
		apk info -e "$1" >/dev/null 2>&1 || apk list -I "$1" 2>/dev/null | grep -q "^$1-[0-9]"
	else opkg list-installed 2>/dev/null | grep -q "^$1 "; fi
}
pkg_add() {
	if [ "$PM" = apk ]; then apk add "$@" >/tmp/kr-pkg.log 2>&1
	else opkg install "$@" >/tmp/kr-pkg.log 2>&1; fi
}

FREE_KB=$(df -k /overlay 2>/dev/null | awk 'NR==2{print $4}')
[ -n "$FREE_KB" ] || FREE_KB=$(df -k / | awk 'NR==2{print $4}')
ok "Boş alan: $((FREE_KB / 1024)) MB"
if [ -z "$(ls /usr/share/kediray/bin/xray 2>/dev/null)" ] && [ "$FREE_KB" -lt 75000 ]; then
	warn "Xray çekirdeği + coğrafi veriler ~70 MB ister, yer az görünüyor."
	yesno "Yine de devam edilsin mi?" H || die "İptal edildi"
fi

# ---------------------------------------------------------------- 2. çakışmalar
step "Çakışan VPN servisleri aranıyor"
CONFLICTS=""
# Güncelleme mi? Önceden kurulu ve AÇIK bir KediRay'in durumu güncellemeyle değişmemeli (eskiden -y ile
# gelen güncelleme diğer VPN servisi kayıtlıysa KediRay'i kapatıyordu).
PREV_CONF=0; [ -f /etc/config/kediray ] && PREV_CONF=1
PREV_ENABLED=$(uci -q get kediray.main.enabled)
WAS_ON=0; [ "$PREV_CONF" = 1 ] && [ "$PREV_ENABLED" = 1 ] && WAS_ON=1
for s in xwrt passwall passwall2 openclash nikki mihomo homeproxy v2raya xray v2ray sing-box neko xlite shadowsocksr ssrplus bypass vssr; do
	[ -x "/etc/init.d/$s" ] || continue
	if /etc/init.d/"$s" enabled 2>/dev/null || /etc/init.d/"$s" running 2>/dev/null; then
		CONFLICTS="$CONFLICTS $s"
	fi
done
IMPORT_XWRT=0
KEEP_OTHER=0
if [ -n "$CONFLICTS" ] && [ "$WAS_ON" = 1 ]; then
	ok "Güncelleme: KediRay zaten açıktı; diğer servislere ($CONFLICTS ) dokunulmuyor, KediRay açık kalacak"
elif [ -n "$CONFLICTS" ]; then
	warn "Çalışan/etkin VPN servisleri:$CONFLICTS"
	case " $CONFLICTS " in *" xwrt "*)
		yesno "xDivine-Ray (xwrt) sunucuları/abonelikleri KediRay'e aktarılsın mı?" E && IMPORT_XWRT=1 ;;
	esac
	echo
	echo "  Kurulum bunları DURDURMADAN da yapılabilir: KediRay kurulur, kendi portlarını"
	echo "  seçer ve kapalı bekler. Hazır olunca panelde 'Güvenli geçiş' ya da 'kediray takeover'"
	echo "  ile geçersin; internet gelmezse eski VPN'e otomatik geri döner."
	if yesno "Şimdi durdurulsunlar mı? (önerilen: Hayır)" H; then
		for s in $CONFLICTS; do
			/etc/init.d/"$s" stop >/dev/null 2>&1
			/etc/init.d/"$s" disable >/dev/null 2>&1
			ok "$s durduruldu (geri açmak için: /etc/init.d/$s enable && /etc/init.d/$s start)"
		done
	else
		KEEP_OTHER=1
		ok "Diğer VPN açık kalıyor; KediRay kapalı kurulacak"
	fi
else
	ok "Çakışma yok"
fi

# ---------------------------------------------------------------- 3. paketler
step "Gerekli paketler kuruluyor"
REQ="ucode ucode-mod-uci ucode-mod-fs ip-full curl ca-bundle unzip openssl-util"
OPT="conntrack"
EXTRA="hev-socks5-tunnel kmod-tun kmod-nft-tproxy kmod-nft-socket"
# Paket listesi ancak eksik paket varsa güncellenir (yeniden kurulumda beklemeyi kaldırır)
MISSING=""
for p in $REQ $OPT $EXTRA; do pkg_installed "$p" || MISSING="$MISSING $p"; done
if [ -n "$MISSING" ]; then
	if [ "$PM" = apk ]; then apk update >/tmp/kr-pkg.log 2>&1 || warn "apk update başarısız (internet?)"
	else opkg update >/tmp/kr-pkg.log 2>&1 || warn "opkg update başarısız (internet?)"; fi
else
	ok "tüm paketler zaten kurulu (paket listesi güncellenmedi)"
fi
for p in $REQ; do
	if pkg_installed "$p"; then ok "$p (kurulu)"; continue; fi
	if pkg_add "$p"; then ok "$p"; else
		case "$p" in
			unzip) command -v unzip >/dev/null 2>&1 && ok "unzip (busybox)" || warn "unzip kurulamadı: Xray arşivi yerleşik çıkarıcıyla açılacak (sorun değil)" ;;
			openssl-util)
				if command -v openssl >/dev/null 2>&1; then ok "openssl (mevcut)"
				else warn "openssl-util kurulamadı: sertifikası doğrulanmayan (allowInsecure) sunucular sabitlenemez"; fi ;;
			*) tail -n 3 /tmp/kr-pkg.log; die "$p kurulamadı" ;;
		esac
	fi
done
for p in $OPT; do
	pkg_installed "$p" && continue
	pkg_add "$p" && ok "$p (isteğe bağlı)" || warn "$p kurulamadı (isteğe bağlı, sorun değil)"
done
# Trafik yakalama: mixed (önerilen, xDivine-Ray ile aynı) = TCP NAT redirect + UDP hev-socks5-tunnel TUN.
# Yedek: tproxy. İkisi de yoksa redirect (sadece TCP).
for p in hev-socks5-tunnel kmod-tun; do
	pkg_installed "$p" && { ok "$p (kurulu)"; continue; }
	pkg_add "$p" && ok "$p" || warn "$p kurulamadı"
done
modprobe tun 2>/dev/null
MIXED_OK=0
if command -v hev-socks5-tunnel >/dev/null 2>&1 && [ -c /dev/net/tun ]; then
	MIXED_OK=1; ok "mixed mod hazır (TCP: çekirdek NAT, UDP: hev-socks5-tunnel)"
fi
for p in kmod-nft-tproxy kmod-nft-socket; do
	pkg_installed "$p" && continue
	pkg_add "$p" >/dev/null 2>&1 || true
done
modprobe nft_tproxy 2>/dev/null; modprobe nft_socket 2>/dev/null
TPROXY_OK=0
# Gerçek test: çekirdek TPROXY + socket eşleşmesini destekliyor mu?
nft delete table inet kr_probe 2>/dev/null
if nft -f - 2>/tmp/kr-nft.log <<'NFT'
table inet kr_probe {
	chain c {
		type filter hook prerouting priority mangle; policy accept;
		meta l4proto tcp socket transparent 1 meta mark set 0x6b accept
		meta l4proto { tcp, udp } meta mark set 0x6b tproxy ip to 127.0.0.1:1 accept
	}
}
NFT
then
	nft delete table inet kr_probe 2>/dev/null
	TPROXY_OK=1; ok "Çekirdek TPROXY desteği de var (yedek mod)"
else
	nft delete table inet kr_probe 2>/dev/null
fi
if [ "$MIXED_OK" = 1 ]; then CAPTURE=mixed
elif [ "$TPROXY_OK" = 1 ]; then CAPTURE=tproxy; warn "hev-socks5-tunnel yok: tproxy modu kullanılacak"
else CAPTURE=redirect; warn "Ne hev-socks5-tunnel ne TPROXY var: sadece TCP tünellenecek (UDP/oyun/arama direkt çıkar)"; fi
command -v ucode >/dev/null 2>&1 || die "ucode yok"
ucode -e 'require("uci"); require("fs");' 2>/dev/null || die "ucode-mod-uci / ucode-mod-fs eksik"

# ---------------------------------------------------------------- 4. dosyalar
step "KediRay dosyaları yazılıyor"
[ -x /etc/init.d/kediray ] && /etc/init.d/kediray stop >/dev/null 2>&1
mkdir -p /usr/share/kediray/bin /var/etc/kediray /www/luci-static/resources/view/kediray \
	/usr/share/luci/menu.d /usr/share/rpcd/acl.d /etc/hotplug.d/iface /etc/hotplug.d/firewall /etc/init.d /usr/bin

write_files() {
cat > '/tmp/kediray.default' <<'KEDIRAY_EOF_1'

config main 'main'
	option enabled '0'
	# Sunucu: 'auto' = en hızlı sunucu (otomatik yedekleme), ya da bir sunucu bölümünün adı
	option node 'auto'
	# (rule = eski Türkiye-direkt modu kaldırıldı, global gibi çalışır)
	# global = her şey VPN (yerel ağ hariç)
	# list   = sadece listelenen siteler/uygulamalar VPN, geri kalan direkt
	option mode 'global'
	# Listede olmayan cihazlar: vpn | direct
	option default_device 'vpn'
	# Trafik yakalama (xDivine-Ray ile aynı):
	#   mixed    TCP çekirdekte NAT redirect, UDP hev-socks5-tunnel TUN  [önerilen]
	#   tun      TCP+UDP tamamen hev-socks5-tunnel TUN üzerinden (xDivine-Ray'in "tun" modu)
	#   tproxy   TCP+UDP TPROXY
	#   redirect sadece TCP (UDP tünellenmez)
	option capture 'mixed'
	# Sunucuya IP ile bağlan (alan adı bir kez IP'ye çevrilir, SNI/Host olarak kalır)
	option connect_ip '1'
	option lan 'lan'
	# DNS
	# Varsayılan: Google TCP + DNS'e dokunma (Metin2 atılması DNS'ten kaynaklanmıyor, sebep sunucu tarafı WS bağlantı hatası)
	option dns_remote 'tcp://8.8.8.8'
	# auto = modeme operatörden gelen DNS (xDivine-Ray gibi): her zaman ayakta, tünele girmez.
	# Yerine DoH yazılabilir: https+local://1.1.1.1/dns-query
	option dns_direct 'auto'
	option dns_direct2 'auto'
	option dns_bootstrap '1.1.1.1'
	# off     = DNS'e hiç dokunma (önerilen): modemin kendi DNS'i aynen kalır, sorgu tünele girmez
	# fast    = sorgular KediRay DNS'inden, tünelden bağımsız
	# private = sorgular tünelden: en gizli, ama tünel koparsa alan adı çözülemez (sayfa 50 sn dönebilir)
	option dns_mode 'off'
	# Tünel takılırsa bilinen adresi önbellekten ver (Xray serveStale)
	option dns_stale '1'
	option ipv6 '0'
	option v6_block '1'
	# Bildirim ve kararlılık (xDivine-Ray'in ölçülmüş varsayılanları)
	# push_fix=0: Google/Apple bildirim bağlantıları da TÜNELDEN gider (xDivine-Ray gibi). Tünelin kendisi heartbeat/keepalive ile canlı tutulur;
	# direkt gönderirsen operatör NAT'ı boştaki bağlantıyı sessizce keser ve bildirimler gecikir ya da hiç gelmez.
	option push_fix '0'
	option conn_idle '14400'
	# Boştaki WebSocket tüneli sunucu/CDN/operatör tarafından kesilmesin: 30 sn (0 = kapalı)
	option ws_heartbeat '30'
	option tcp_keepalive '30'
	# QUIC'i (UDP 443) reddet: tarayıcı anında TCP'ye (tünele) geçer (v2rayNG/Xray varsayılanı)
	option block_quic '1'
	# 1 = alan adını sunucu çözsün (her bağlantıya bir tur ekler); 0 = hedef IP korunur
	option sniff_override '0'
	# auto: Discord/WARP gibi DNS'i bozuk uygulamalar varsa hedef alan adıyla değiştirilir | off: hiç değiştirilmez (en hızlı)
	option sniff_mode 'auto'
	# TCP mux (0 önerilir; UDP için XUDP her zaman açık)
	option mux '0'
	# WebSocket erken veri
	option ws_early '0'
	option cfgver '14'
	option ad_block '0'
	# VPN süreci çökerse: killswitch = VPN trafiği kesilir (WhatsApp asla direkt çıkmaz) | open = internet direkt açılır
	# Mobil/CGNAT hatlar: düşen SYN yüzünden bağlantı 50 sn asılı kalmasın (3 deneme ≈ 15 sn)
	option mobile_tune '1'
	# Hız ayarı: TCP tamponları büyütülür (hız testi/indirme daha çabuk yükselir) ve Xray bağlantı tamponu 1 MB olur
	option speed_tune '1'
	option buffer_size '1024'
	option failsafe 'killswitch'
	# Abonelik otomatik güncelleme (saat, 0 = kapalı)
	option sub_interval '12'
	# Gelişmiş
	option log_level 'warning'
	option tproxy_port '12345'
	# Cihazların yazdığı DNS'i (8.8.8.8 vb.) çekirdekte KediRay DNS'ine çevir: tünele girmez, hızlıdır
	option dns_hijack '1'
	option block_doh '1'
	option dns_port '15353'
	option socks_port '10808'
	option api_port '10085'
	# Ölçüm (ping/sağlık) adresi ve yedeği: biri engellenirse diğeri kullanılır
	option probe_url 'https://www.gstatic.com/generate_204'
	option probe_url2 'https://cp.cloudflare.com/generate_204'
	option probe_interval '2m'

# Uygulamalar: başlangıçta boş. VPN Ayırma sayfasındaki "Hazır uygulamalar"dan (WhatsApp, Metin2, Teams, YouTube...)
# ya da "Yeni uygulama ekle"den eklenir. Her biri için route 'vpn' veya 'direct' seçilir.

config rule
	option name 'Discord (liste modu için örnek)'
	option enabled '1'
	option target 'proxy'
	list domain 'domain:discord.com'
	list domain 'domain:discord.gg'
	list domain 'domain:discordapp.com'
	list domain 'domain:discordapp.net'
	list domain 'domain:discord.media'
KEDIRAY_EOF_1
cat > '/etc/init.d/kediray' <<'KEDIRAY_EOF_2'
#!/bin/sh /etc/rc.common
# KediRay servis betiği

START=99
STOP=15
USE_PROCD=1

PROG=/usr/bin/kediray
RUN=/var/etc/kediray

start_service() {
	: > /tmp/kediray.started
	lock /var/lock/kediray.start 2>/dev/null
	_start_service
	local rc=$?
	lock -u /var/lock/kediray.start 2>/dev/null
	return $rc
}

# Açılışta (boot) hiçbir ağır iş yapma: S99'daki sonraki servisler (S99ledstatus = modem ışıkları, qmodem_network...)
# KediRay'in arkasında sıra bekliyordu; yapılandırma üretimi birkaç sn sürdüğü için ışıklar/servisler geç geliyordu.
# Burada hemen dönülür; WAN gelince (en çok 180 sn) normal başlatma arka planda yapılır.
boot() {
	: > /tmp/kediray.started
	$PROG fixboot >/dev/null 2>&1
	[ "$(uci -q get kediray.main.enabled)" = 1 ] || { start; return 0; }
	: > /tmp/kediray.waiting
	( i=0
	  while ! $PROG wan-ready && [ $i -lt 180 ]; do sleep 1; i=$((i + 1)); done
	  : > /tmp/kediray.waited; rm -f /tmp/kediray.waiting
	  logger -t kediray "WAN hazır ($i sn bekledi, modem açılışından $(cut -d. -f1 /proc/uptime) sn sonra): VPN başlatılıyor"
	  /etc/init.d/kediray start >/dev/null 2>&1 ) </dev/null >/dev/null 2>&1 &
	return 0
}

_start_service() {
	# trafik istatistiğini (modem yeniden başladıysa) flash'tan geri yükle
	$PROG traffic restore >/dev/null 2>&1
	config_load kediray
	local enabled
	config_get_bool enabled main enabled 0
	if [ "$enabled" != 1 ]; then
		$PROG fw-down >/dev/null 2>&1
		return 0
	fi

	# Modem açılırken WAN (5G/PPP) henüz gelmemişken VPN kuralları devreye girerse modemin kendi bağlantı kurma
	# adımları ve ilk istekler bozuluyordu. WAN'ın varsayılan rotası gelene kadar (en çok 3 dk) arka planda beklenir,
	# sonra normal başlatma yapılır. WAN zaten hazırsa (elle başlat/yeniden başlat) hiç beklenmez.
	if [ "$enabled" = 1 ] && [ ! -f /tmp/kediray.waited ] && ! $PROG wan-ready; then
		if [ ! -f /tmp/kediray.waiting ]; then
			: > /tmp/kediray.waiting
			logger -t kediray "WAN henüz hazır değil: VPN, WAN gelince başlayacak (en çok 180 sn beklenir)"
			( i=0
			  while ! $PROG wan-ready && [ $i -lt 180 ]; do sleep 1; i=$((i + 1)); done
			  : > /tmp/kediray.waited; rm -f /tmp/kediray.waiting
			  logger -t kediray "WAN hazır ($i sn bekledi, modem açılışından $(cut -d. -f1 /proc/uptime) sn sonra): VPN başlatılıyor"
			  /etc/init.d/kediray start >/dev/null 2>&1 ) </dev/null >/dev/null 2>&1 &
		fi
		return 0
	fi
	local T0 T1
	T0=$(cut -d. -f1 /proc/uptime)
	if ! $PROG gen; then
		logger -t kediray "yapılandırma üretilemedi, VPN başlatılmadı (internet direkt çalışır)"
		$PROG fw-down >/dev/null 2>&1
		return 1
	fi

	local bin asset cap
	T1=$(cut -d. -f1 /proc/uptime)
	logger -t kediray "açılış: başlatma modem açılışından ${T0} sn sonra, yapılandırma $((T1 - T0)) sn sürdü"
	bin=$($PROG corebin)
	asset=$($PROG assetdir)
	cap=$(cat "$RUN/capture" 2>/dev/null)

	procd_open_instance xray
	procd_set_param command "$bin" run -c "$RUN/config.json"
	procd_set_param env XRAY_LOCATION_ASSET="$asset"
	procd_set_param respawn 3600 5 10
	procd_set_param limits nofile="1048576 1048576"
	procd_set_param stdout 1
	procd_set_param stderr 1
	procd_close_instance

	# mixed: UDP'yi taşıyan TUN · tun: TCP+UDP hepsi TUN'dan (zaman aşımları hev.yaml'da)
	case "$cap" in mixed|tun) [ -s "$RUN/hev.yaml" ] && TUN_NEEDED=1 ;; esac
	if [ "${TUN_NEEDED:-0}" = 1 ]; then
		ip link del kediray0 >/dev/null 2>&1
		procd_open_instance hev
		procd_set_param command "$($PROG hevbin)" "$RUN/hev.yaml"
		procd_set_param respawn 3600 5 10
		procd_set_param limits nofile="65535 65535"
		procd_set_param stdout 1
		procd_set_param stderr 1
		procd_close_instance
	fi

	# Kuralları Xray portu (ve TUN) hazır olunca uygula (arka planda bekler)
	( sleep 1; $PROG fw-up ) >/dev/null 2>&1 &
}

stop_service() {
	# Önce kuralları kaldır, sonra süreçler dursun: trafik boşa düşmez
	$PROG fw-down >/dev/null 2>&1
}

service_stopped() {
	ip link del kediray0 >/dev/null 2>&1
	return 0
}

reload_service() {
	stop
	start
}

service_triggers() {
	procd_add_reload_trigger kediray
}
KEDIRAY_EOF_2
cat > '/etc/hotplug.d/iface/80-kediray' <<'KEDIRAY_EOF_3'
#!/bin/sh
# Arayüz yeniden kalktığında (WAN/LAN, güvenlik duvarı yeniden yüklemesi) KediRay kurallarını geri yükle
[ "$ACTION" = ifup ] || exit 0
[ "$(uci -q get kediray.main.enabled)" = 1 ] || exit 0
[ -f /var/etc/kediray/fw ] || exit 0
nft list table inet kediray >/dev/null 2>&1 && ip -4 rule | grep -q 'lookup 107' && exit 0
logger -t kediray "arayüz $INTERFACE kalktı, kurallar yeniden uygulanıyor"
/usr/bin/kediray fw-up >/dev/null 2>&1 &
KEDIRAY_EOF_3
cat > '/etc/hotplug.d/firewall/99-kediray' <<'KEDIRAY_EOF_4'
#!/bin/sh
# Güvenlik duvarı yeniden yüklenince KediRay kurallarını geri koy (bazı fw4 sürümleri tüm tabloları siler)
[ "$(uci -q get kediray.main.enabled)" = 1 ] || exit 0
[ -f /var/etc/kediray/fw ] || exit 0
nft list table inet kediray >/dev/null 2>&1 && exit 0
logger -t kediray "güvenlik duvarı yeniden yüklendi, kurallar geri uygulanıyor"
/usr/bin/kediray fw-up >/dev/null 2>&1 &
exit 0
KEDIRAY_EOF_4
cat > '/usr/bin/kediray' <<'KEDIRAY_EOF_5'
#!/bin/sh
# KediRay - OpenWrt için Xray tabanlı akıllı VPN yöneticisi
# Kullanım: kediray help

CONF=kediray
SHARE=/usr/share/kediray
RUN=/var/etc/kediray
# Soket işaretleri ve yönlendirme tabloları (xDivine'dan farklı değerler: ikisi aynı cihazda çakışmasın)
MARK_CORE=0x2e0   # Xray'in kendi bağlantıları
MARK_TP=0x2e1     # tproxy modu
MARK_TUN=0x2e2    # mixed modda TUN'a gidecek UDP
TABLE_TP=107; PREF_TP=107
TABLE_TUN=108; PREF_CORE=1071; PREF_TUN=1072
TUN_DEV=kediray0
TUN_ADDR=198.19.0.1
T="$(printf '\t')"
export KR_RUN="$RUN" KR_SHARE="$SHARE"

uget() { uci -q get "$CONF.$1"; }
# Günlük önem seviyeleri (panelde Hata / Uyarı / Bilgi olarak ayrılır)
log() { logger -t kediray -p daemon.info "$*"; }
say() { echo "$*" >&2; logger -t kediray -p daemon.warn "$*"; }      # uyarı
sayerr() { echo "$*" >&2; logger -t kediray -p daemon.err "$*"; }    # hata

api_addr() { echo "127.0.0.1:$(uget main.api_port || echo 10085)"; }
tp_port() { uget main.tproxy_port || echo 12345; }

corebin() {
	local c
	for c in "$(uget main.xray_bin)" "$SHARE/bin/xray" /usr/bin/xray; do
		[ -n "$c" ] && [ -x "$c" ] && { echo "$c"; return 0; }
	done
	return 1
}

assetdir() {
	local d
	for d in "$SHARE" /usr/share/xray /usr/share/v2ray; do
		[ -s "$d/geoip.dat" ] && [ -s "$d/geosite.dat" ] && { echo "$d"; return 0; }
	done
	echo "$SHARE"
}

xr() { XRAY_LOCATION_ASSET="$(assetdir)" "$(corebin)" "$@"; }

running() {
	ubus call service list '{"name":"kediray"}' 2>/dev/null | jsonfilter -e '@.kediray.instances.xray.running' 2>/dev/null | grep -q true
}

lan_ifs() {
	local out="" dev n
	. /lib/functions/network.sh
	for n in $(uget main.lan); do
		dev=""
		network_get_device dev "$n" 2>/dev/null
		[ -n "$dev" ] || network_get_physdev dev "$n" 2>/dev/null
		[ -n "$dev" ] && out="$out $dev"
	done
	[ -n "$out" ] || out="br-lan"
	echo $out
}

resolve4() {
	case "$1" in
		*[!0-9.]*) ;;
		*) echo "$1"; return 0 ;;
	esac
	nslookup "$1" "$(uget main.dns_bootstrap || echo 1.1.1.1)" 2>/dev/null | awk '
		/^Name:/ { f = 1 }
		f && /^Address/ { for (i = 2; i <= NF; i++) if ($i ~ /^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$/) { print $i; exit } }'
}

# procd, servis kayıtlı değilken (ilk kurulum, kapalıyken restart) stderr'e
# "Command failed: Not found" yazar; hata değildir, kullanıcıyı korkutmasın diye süzülür.
svc() { # <start|stop|restart|enable|disable|reload>
	/etc/init.d/kediray "$1" 2>&1 | grep -v '^Command failed: Not found$' >&2
	return 0
}

with_lock() {
	if command -v lock >/dev/null 2>&1; then
		lock /var/lock/kediray.lock
		"$@"; local rc=$?
		lock -u /var/lock/kediray.lock
		return $rc
	fi
	"$@"
}

# ---------- sertifika sabitleme (Xray 26'da allowInsecure yerine) ----------
# Sunucunun sunduğu sertifikayı al (doğrulama yapmadan) — xDivine-Ray'in fetch-cert yaklaşımı
run_to() { # <saniye> komut...  (busybox'ta timeout olmasa da çalışır)
	local s="$1" p w rc
	shift
	if command -v timeout >/dev/null 2>&1; then timeout "$s" "$@"; return; fi
	"$@" &
	p=$!
	( sleep "$s"; kill "$p" 2>/dev/null ) &
	w=$!
	wait "$p"; rc=$?
	kill "$w" 2>/dev/null
	return $rc
}
cert_pem() { # ip port sni
	command -v openssl >/dev/null 2>&1 || return 1
	echo | run_to 8 openssl s_client -connect "$1:$2" -servername "$3" 2>/dev/null | openssl x509 2>/dev/null
}

# Çekirdek allowInsecure'ü hâlâ tanıyor mu? (Xray 26'da kaldırıldı.) xDivine gibi gerçek bir testle öğrenilir.
cap_insecure() {
	local ver f
	ver=$(xr version 2>/dev/null | awk 'NR==1{print $2}')
	f="/etc/kediray.cap.$ver"   # kalıcı (flash): açılışta her seferinde Xray testi yapılmasın
	if [ ! -f "$f" ]; then
		mkdir -p "$RUN"
		rm -f /etc/kediray.cap.* 2>/dev/null
		printf '%s' '{"inbounds":[],"outbounds":[{"protocol":"vless","settings":{"vnext":[{"address":"probe.invalid","port":443,"users":[{"id":"b831381d-6324-4d53-ad4f-8cda48b30811","encryption":"none"}]}]},"streamSettings":{"network":"tcp","security":"tls","tlsSettings":{"serverName":"a.com","allowInsecure":true}}}]}' > "$RUN/cap.json"
		if xr run -test -c "$RUN/cap.json" 2>&1 | grep -q 'Configuration OK'; then echo 1 > "$f"; else echo 0 > "$f"; fi
		rm -f "$RUN/cap.json"
	fi
	[ "$(cat "$f")" = 1 ]
}

hevbin() {
	local h
	for h in "$(uget main.hev_bin)" "$(command -v hev-socks5-tunnel 2>/dev/null)" /usr/bin/hev-socks5-tunnel; do
		[ -n "$h" ] && [ -x "$h" ] && { echo "$h"; return 0; }
	done
	return 1
}

# Seçilen yakalama modu bu cihazda çalışabilir mi? Çalışamıyorsa en yakınına düş.
capture_eff() {
	local c
	c=$(uget main.capture); c=${c:-mixed}
	case "$c" in mixed|tun)
		if ! hevbin >/dev/null || [ ! -c /dev/net/tun ]; then
			[ -f "$RUN/capture.warned" ] || { say "$c modu için hev-socks5-tunnel/kmod-tun yok; tproxy moduna geçildi (kur: apk add hev-socks5-tunnel kmod-tun)"; touch "$RUN/capture.warned"; }
			c=tproxy
		fi ;;
	esac
	echo "$c"
}
cert_hash() { # ip port sni -> yaprak sertifikanın SHA-256'sı (Xray'in pinnedPeerCertSha256 biçimi)
	cert_pem "$@" | openssl x509 -outform DER 2>/dev/null | sha256sum | awk '{print $1}' | grep -E '^[0-9a-f]{64}$'
}

# allowInsecure (doğrulanmayan sertifika) kullanan sunucular: her başlangıçta sunucunun sertifikasını
# yeniden oku; değiştiyse yenisini sabitle (sunucu zaten doğrulanmıyor, amaç tüneli ayakta tutmak).
pin_nodes() { # [force|<bölüm>]
	local tag sec tp addr port proto net insecure sni pin name ip h changed=0
	[ -s "$RUN/nodes.tsv" ] || return 0
	[ "$(uget main.pin_refresh)" = 0 ] && [ -z "$1" ] && return 0
	# xDivine gibi: çekirdek allowInsecure'ü hâlâ destekliyorsa sabitlemeye gerek yok
	[ -z "$1" ] && cap_insecure && return 0
	while IFS="$T" read -r tag sec tp addr port proto net insecure sni pin name; do
		[ "$insecure" = 1 ] || continue
		case "$1" in ""|force) ;; *) [ "$1" = "$sec" ] || continue ;; esac
		: > "$RUN/pin.seen"
		ip=$(resolve4 "$addr")
		[ -n "$ip" ] || { say "$name: adres çözülemedi, sertifika okunamadı"; echo "$name: adres çözülemedi, sertifika okunamadı" >> "$RUN/pin.out"; : > "$RUN/pin.fail"; continue; }
		h=$(cert_hash "$ip" "$port" "$sni")
		if [ -z "$h" ]; then
			if [ "$pin" = "-" ]; then
				sayerr "$name: sertifika alınamadı ve daha önce sabitlenmemiş; bu sunucu bağlanamaz (openssl-util kurulu mu? sunucu açık mı?)"
			else
				log "$name: sertifika şu an okunamadı, kayıtlı sabitleme kullanılıyor"
			fi
			echo "$name: sertifika okunamadı (sunucu kapalı ya da openssl-util yok)" >> "$RUN/pin.out"
			: > "$RUN/pin.fail"
			continue
		fi
		if [ "$h" = "$pin" ]; then echo "$name: sertifika zaten sabit" >> "$RUN/pin.out"; continue; fi
		uci -q set "$CONF.$sec.pin=$h"
		changed=1
		: > "$RUN/pin.chg"
		if [ "$pin" = "-" ]; then log "$name: sertifika sabitlendi ($(echo "$h" | cut -c1-12)…)"; echo "$name: sertifika sabitlendi" >> "$RUN/pin.out"
		else log "$name: sunucunun sertifikası değişmiş, yenisi sabitlendi ($(echo "$pin" | cut -c1-12)… -> $(echo "$h" | cut -c1-12)…)"; echo "$name: sunucunun sertifikası değişmişti, yenisi sabitlendi" >> "$RUN/pin.out"; fi
	done < "$RUN/nodes.tsv"
	[ "$changed" = 1 ] && uci -q commit "$CONF"
	return 0
}

# Elle sabitleme (panelde "Sertifikayı sabitle"): sunucunun şu anki sertifikasını okuyup sabitler.
# Sertifika değiştiyse tüneli yeniden başlatır (internet kesildiyse düzelir); değişmediyse dokunmaz.
cmd_pin() { # [force|<bölüm>]
	mkdir -p "$RUN"
	rm -f "$RUN/pin.out" "$RUN/pin.chg" "$RUN/pin.seen" "$RUN/pin.fail"
	pin_nodes "${1:-force}"
	if [ ! -e "$RUN/pin.seen" ]; then
		echo "Sertifikası doğrulanmayan (allowInsecure) sunucu yok; sabitlenecek bir şey yok."
		return 0
	fi
	cat "$RUN/pin.out" 2>/dev/null
	if [ -e "$RUN/pin.chg" ]; then
		if [ "$(uget main.enabled)" = 1 ]; then echo "Tünel yeniden başlatılıyor…"; /etc/init.d/kediray restart; fi
	elif [ ! -e "$RUN/pin.fail" ]; then
		echo "Sertifika değişmemiş; internet gitmişse sorun sertifikadan değil."
	fi
	[ ! -e "$RUN/pin.fail" ] || [ -e "$RUN/pin.chg" ]
}

cmd_cert() { # <bölüm> [--json]  sunucunun sertifikasını göster
	local sec="$1" tag s tp addr port proto net insecure sni pin name ip pem subj iss nb na h trusted=0
	[ -s "$RUN/nodes.tsv" ] || ucode "$SHARE/gen.uc" nodes > "$RUN/nodes.tsv" 2>/dev/null
	while IFS="$T" read -r tag s tp addr port proto net insecure sni pin name; do
		[ "$s" = "$sec" ] && break
	done < "$RUN/nodes.tsv"
	[ "$s" = "$sec" ] || { echo '{"ok":false,"msg":"sunucu bulunamadı"}'; return 1; }
	command -v openssl >/dev/null 2>&1 || { echo '{"ok":false,"msg":"openssl-util kurulu değil (apk add openssl-util)"}'; return 1; }
	ip=$(resolve4 "$addr")
	pem=$(cert_pem "${ip:-$addr}" "$port" "$sni")
	[ -n "$pem" ] || { printf '{"ok":false,"msg":"%s:%s adresinden sertifika alınamadı (TLS yok ya da sunucu kapalı)"}\n' "${ip:-$addr}" "$port"; return 1; }
	subj=$(echo "$pem" | openssl x509 -noout -subject 2>/dev/null | sed 's/^subject= *//')
	iss=$(echo "$pem" | openssl x509 -noout -issuer 2>/dev/null | sed 's/^issuer= *//')
	nb=$(echo "$pem" | openssl x509 -noout -startdate 2>/dev/null | cut -d= -f2)
	na=$(echo "$pem" | openssl x509 -noout -enddate 2>/dev/null | cut -d= -f2)
	h=$(echo "$pem" | openssl x509 -outform DER 2>/dev/null | sha256sum | awk '{print $1}')
	echo | openssl s_client -connect "${ip:-$addr}:$port" -servername "$sni" 2>/dev/null | grep -q "Verify return code: 0 " && trusted=1
	KR_J_SUBJ="$subj" KR_J_ISS="$iss" KR_J_NB="$nb" KR_J_NA="$na" KR_J_H="$h" KR_J_PIN="$pin" KR_J_SNI="$sni" \
	KR_J_EP="${ip:-$addr}:$port" KR_J_INS="$insecure" KR_J_TR="$trusted" KR_J_NAME="$name" ucode -e '
		let g = getenv;
		print(sprintf("%J\n", { ok: true, name: g("KR_J_NAME"), endpoint: g("KR_J_EP"), sni: g("KR_J_SNI"), subject: g("KR_J_SUBJ"),
			issuer: g("KR_J_ISS"), not_before: g("KR_J_NB"), not_after: g("KR_J_NA"), sha256: g("KR_J_H"),
			pinned: g("KR_J_PIN") != "-" ? g("KR_J_PIN") : null, pin_match: g("KR_J_PIN") == g("KR_J_H"),
			insecure: g("KR_J_INS") == "1", trusted: g("KR_J_TR") == "1" }));'
}

# ---------- modemin kendi trafiği (apk, curl...) -> VPN (1.17.3: tünel doğrulanınca açılır) ----------
# Neden ayrı tablo: modem açılırken tünel henüz hazır değilken modemin kendi bağlantıları (hücresel modem
# denetimleri, saat, güncelleme...) tünele yönlenirse takılıyor ve internet geç geliyordu. Artık yalnızca
# tünelden gerçek bir istek geçtikten sonra eklenir; tünel iki kontrol üst üste başarısız olursa kalkar.
mvpn_wanted() { # modem_vpn açık ve yakalama modu uygun mu
	[ "$(uget main.modem_vpn)" != 0 ] || return 1
	case "$(cat "$RUN/capture" 2>/dev/null)" in mixed|redirect) return 0 ;; esac
	return 1
}
mvpn_on() { nft list table inet kediray_out >/dev/null 2>&1; }
mvpn_down() { nft delete table inet kediray_out 2>/dev/null; rm -f "$RUN/mvpn.bad"; return 0; }
mvpn_up() {
	local srv tp
	srv=$(tr ' ' ',' < "$RUN/server_ips" 2>/dev/null | sed 's/^,*//; s/,*$//; s/,,*/,/g')
	tp=$(uget main.tproxy_port); tp=${tp:-12345}
	nft -f - <<EOF 2>/dev/null
table inet kediray_out {
	chain nat_out {
		type nat hook output priority -105; policy accept;
		meta nfproto != ipv4 return
		meta l4proto != tcp return
		meta mark $MARK_CORE return
		fib daddr type { local, broadcast, multicast } return
		ip daddr { 0.0.0.0/8, 10.0.0.0/8, 100.64.0.0/10, 127.0.0.0/8, 169.254.0.0/16, 172.16.0.0/12, 192.168.0.0/16, 224.0.0.0/4, 240.0.0.0/4${srv:+, $srv} } return
		ip daddr { 1.1.1.1, 1.0.0.1, 8.8.8.8, 8.8.4.4, 9.9.9.9 } tcp dport { 443, 5053 } return
		meta l4proto tcp redirect to :$tp
	}
}
EOF
}
mvpn_watch() { # watchdog her dakika çağırır
	local sp
	if ! mvpn_wanted; then mvpn_on && mvpn_down; return 0; fi
	sp=$(uget main.socks_port); sp=${sp:-10808}
	if curl -s -m 6 -o /dev/null --noproxy '' -x "socks5h://127.0.0.1:$sp" "https://www.gstatic.com/generate_204" 2>/dev/null; then
		rm -f "$RUN/mvpn.bad"
		mvpn_on || { mvpn_up && log "modemin kendi trafiği de VPN'e alındı (tünel doğrulandı)"; }
	else
		if mvpn_on; then
			if [ -f "$RUN/mvpn.bad" ]; then mvpn_down; log "tünel yanıt vermiyor: modemin kendi trafiği geçici olarak direkt bırakıldı"
			else : > "$RUN/mvpn.bad"; fi
		fi
	fi
	return 0
}

# ---------- direkt (VPN'siz) çıkış denetimi (1.17) ----------
# Modemin kendi çıkışı çalışmıyorsa (ör. paketsiz hat) "direkt" giden her şey (Metin2, Teams,
# kullanıcı kuralları, direkt cihazlar) kendiliğinden VPN'e alınır. Hat düzelince eski yollar geri gelir.
# Kapatmak için: uci set kediray.main.auto_direct=0
direct_probe() { # 0: direkt çıkış var, 1: yok (üç yoldan hiçbiri açılmıyor)
	local d="$RUN/dp.$$" i
	mkdir -p "$d"
	( p_tcp 1.1.1.1 443 && : > "$d/a" ) >/dev/null 2>&1 &
	( p_tcp 8.8.8.8 443 && : > "$d/b" ) >/dev/null 2>&1 &
	( p_tcp 9.9.9.9 443 && : > "$d/c" ) >/dev/null 2>&1 &
	wait
	i=1
	if [ -e "$d/a" ] || [ -e "$d/b" ] || [ -e "$d/c" ]; then i=0; fi
	rm -rf "$d"
	return $i
}
direct_auto() { [ "$(uget main.auto_direct)" != 0 ]; }
direct_state() { # ok|dead  (önbellek; yoksa bir kez yoklar)
	# Önbellek yoksa (modem yeni açıldı) yoklama yapıp açılışı geciktirme: "yok" varsay (her şey VPN'den çıkar),
	# watchdog birkaç dakika içinde gerçek durumu ölçer
	[ -s "$RUN/direct" ] || { mkdir -p "$RUN"; echo dead > "$RUN/direct"; }
	cat "$RUN/direct"
}
direct_watch() { # dakikada bir: iki ardışık aynı sonuç gelirse durumu değiştir ve uygula (titremeyi önler)
	local new cur
	# Ölçüm otomatik VPN'e çevirme kapalıyken de sürer: bildirim düzeltmesi (FCM direkt) hat gerçekten direkt çıkabiliyorsa açılır
	if direct_probe; then new=ok; else new=dead; fi
	cur=$(cat "$RUN/direct" 2>/dev/null)
	if [ -z "$cur" ]; then echo "$new" > "$RUN/direct"; rm -f "$RUN/direct.cand"; return 0; fi
	if [ "$new" = "$cur" ]; then rm -f "$RUN/direct.cand"; return 0; fi
	if [ "$(cat "$RUN/direct.cand" 2>/dev/null)" = "$new" ]; then
		echo "$new" > "$RUN/direct"; rm -f "$RUN/direct.cand"
		if [ "$new" = dead ]; then log "direkt çıkış yok: direkt giden her şey VPN'e alınıyor"
		else log "direkt çıkış geri geldi: uygulama yolları eski haline dönüyor"; fi
		apply_changes
	else
		echo "$new" > "$RUN/direct.cand"
	fi
}
cmd_fixboot() { # QModem açılışta USB kök hub'larını (usbN) modem diye deniyor ve açılışı ~40 sn geciktiriyor; hub'ları atla
	local f=/usr/share/qmodem/modem_scan.sh t
	[ -f "$f" ] || return 0
	if grep -q 'kediray-hubfix' "$f"; then [ "$1" = -v ] && echo "QModem hub yaması zaten var"; return 0; fi
	grep -q '^    add)$' "$f" || { [ "$1" = -v ] && echo "modem_scan.sh beklenen yapıda değil, dokunulmadı"; return 0; }
	[ -f /root/modem_scan.sh.kediray.bak ] || cp "$f" /root/modem_scan.sh.kediray.bak 2>/dev/null
	t=/tmp/modem_scan.fix.$$
	awk '{ print } /^    add\)$/ && !d { print "        case \"$config\" in usb[0-9]*) exit 0 ;; esac # kediray-hubfix"; d = 1 }' "$f" > "$t" \
		&& sh -n "$t" && cat "$t" > "$f" \
		&& { logger -t kediray "QModem hub yaması uygulandı (sonraki açılış hızlanır)"; [ "$1" = -v ] && echo "QModem hub yaması uygulandı"; }
	rm -f "$t"
	return 0
}
cmd_selfupdate() { # <dosya> | log  — panelden yüklenen kurulum dosyasıyla kendini günceller
	local f="${1:-}" ver
	if [ "$f" = log ]; then
		if [ -f /tmp/kediray-update.rc ]; then echo "DONE $(cat /tmp/kediray-update.rc)"
		elif [ -f /tmp/kediray-update.log ]; then echo RUNNING
		else echo "DONE 1"; fi
		echo "STEPS $(grep -c '^==> ' /tmp/kediray-update.log 2>/dev/null)|$(grep '^==> ' /tmp/kediray-update.log 2>/dev/null | tail -n 1 | sed 's/^==> //')"
		tail -n 80 /tmp/kediray-update.log 2>/dev/null
		return 0
	fi
	[ -f "$f" ] || { echo "Dosya bulunamadı: $f"; return 1; }
	head -c 600 "$f" | grep -q 'KediRay' && grep -q '^KR_VERSION="' "$f" || { echo "Bu dosya bir KediRay kurulum dosyası gibi görünmüyor."; return 1; }
	sh -n "$f" 2>/dev/null || { echo "Dosyada sözdizimi hatası var (yükleme yarım kalmış olabilir). Yeniden dene."; return 1; }
	ver=$(sed -n 's/^KR_VERSION="\(.*\)"/\1/p' "$f" | head -1)
	rm -f /tmp/kediray-update.rc /tmp/kediray-update.log
	cp "$f" /tmp/kediray-update.run.sh 2>/dev/null && rm -f "$f"
	echo "Kurulum başlatıldı: $(kr_version) -> $ver"
	( $(command -v setsid) sh -c 'sh /tmp/kediray-update.run.sh -y; echo $? > /tmp/kediray-update.rc; rm -f /tmp/kediray-update.run.sh' >/tmp/kediray-update.log 2>&1 </dev/null & )   # setsid varsa panel servisi yeniden başlasa da kurulum yaşar; nohup BusyBox'ta yok
	return 0
}

# ---- GitHub'dan güncelleme: kediray update check [--json] | install -----------------------------------
# Depo: uci kediray.main.update_repo (varsayılan sabanvurgun03-ui/kediray), dal: update_branch (main).
# Depoda: VERSION, kediray-install.sh, kediray-install.sh.sha256. İndirilen dosya SHA256 ile doğrulanır.
UPD_REPO_DEF="sabanvurgun03-ui/kediray"
upd_base() {
	local r b
	r=$(uget main.update_repo); r=${r:-$UPD_REPO_DEF}
	b=$(uget main.update_branch); b=${b:-main}
	echo "https://raw.githubusercontent.com/$r/$b"
}
ver_gt() { # a b -> a, b'den yeni mi (1.19.36 > 1.19.9)
	awk -v a="$1" -v b="$2" 'BEGIN { na = split(a, x, "."); nb = split(b, y, "."); n = (na > nb ? na : nb)
		for (i = 1; i <= n; i++) { p = x[i] + 0; q = y[i] + 0; if (p > q) exit 0; if (p < q) exit 1 } exit 1 }'
}
upd_json() { # ok latest cur newer [hata]
	printf '{"ok":%s,"current":"%s","latest":"%s","newer":%s,"error":"%s"}\n' "$1" "$3" "$2" "$4" "$5"
}
UPD_CACHE=/etc/kediray.upd.json   # günde bir kez yazılır; yeniden başlatmada kaybolmasın
cmd_update() { # check [--json] | install | auto | cached
	case "$1" in
		auto) # cron: günde bir kez sessizce denetle (update_check=0 ise yapmaz); sonuç önbelleğe yazılır
			[ "$(uget main.update_check)" = 0 ] && { rm -f "$UPD_CACHE"; return 0; }
			cmd_update check --json > "$UPD_CACHE.$$" 2>/dev/null && mv "$UPD_CACHE.$$" "$UPD_CACHE" || { rm -f "$UPD_CACHE.$$"; return 0; }
			# "Otomatik kur" işaretliyse ve yeni sürüm varsa kur (indirme SHA256 ile doğrulanır; hata olursa mevcut sürüm kalır)
			if [ "$(uget main.update_auto_install)" = 1 ] && grep -q '"newer":true' "$UPD_CACHE"; then
				logger -t kediray "otomatik güncelleme başlıyor: $(sed -n 's/.*"latest":"\([0-9.]*\)".*/\1/p' "$UPD_CACHE")"
				cmd_update install 2>&1 | logger -t kediray
			fi
			return 0 ;;
		cached) # panel: son otomatik denetimin sonucu (yoksa boş)
			local latest cur
			[ "$(uget main.update_check)" = 0 ] && return 0
			[ -s "$UPD_CACHE" ] || return 0
			# önbellekteki "en son" sürümü şimdiki sürümle yeniden karşılaştır (güncelledikten sonra bayat uyarı kalmasın)
			latest=$(sed -n 's/.*"latest":"\([0-9.]*\)".*/\1/p' "$UPD_CACHE" | head -n1); cur=$(kr_version)
			[ -n "$latest" ] || return 0
			if ver_gt "$latest" "$cur"; then upd_json true "$latest" "$cur" true ""; else upd_json true "$latest" "$cur" false ""; fi
			return 0 ;;
	esac
	local act="${1:-check}" js=0 base cur latest t="/tmp/kediray-upd.$$" sum got ver
	[ "$2" = --json ] || [ "$1" = --json ] && js=1
	[ "$act" = --json ] && act=check
	cur=$(kr_version); base=$(upd_base)
	mkdir -p /tmp
	if ! ufetch "$base/VERSION?t=$(date +%s)" "$t.v" 7; then
		rm -f "$t.v"
		[ $js = 1 ] && upd_json false "" "$cur" false "GitHub'a ulaşılamadı" || echo "GitHub'a ulaşılamadı: $base"
		return 1
	fi
	latest=$(tr -cd '0-9.' < "$t.v" | head -c 20); rm -f "$t.v"
	[ -n "$latest" ] || { [ $js = 1 ] && upd_json false "" "$cur" false "VERSION okunamadı" || echo "VERSION dosyası okunamadı"; return 1; }
	case "$act" in
		check)
			if ver_gt "$latest" "$cur"; then
				[ $js = 1 ] && upd_json true "$latest" "$cur" true "" || echo "Yeni sürüm var: $cur -> $latest"
			else
				[ $js = 1 ] && upd_json true "$latest" "$cur" false "" || echo "Güncelsin ($cur)"
			fi
			return 0 ;;
		install)
			ver_gt "$latest" "$cur" || [ "$3" = force ] || [ "$2" = force ] || { echo "Zaten güncel ($cur). Zorla kurmak için: kediray update install force"; return 0; }
			ufetch "$base/kediray-install.sh.sha256?t=$(date +%s)" "$t.s" 7 && sum=$(awk '{print $1}' "$t.s" | head -n1); rm -f "$t.s"
			echo "$sum" | grep -Eq '^[0-9a-f]{64}$' || { echo "SHA256 dosyası okunamadı; güvenlik için kurulmadı."; return 1; }
			ufetch "$base/kediray-install.sh?t=$(date +%s)" /tmp/kediray-update.sh 15 || { echo "Kurulum dosyası indirilemedi."; rm -f /tmp/kediray-update.sh; return 1; }
			got=$(sha256sum /tmp/kediray-update.sh | awk '{print $1}')
			[ "$got" = "$sum" ] || { echo "SHA256 uyuşmuyor (indirme bozuk ya da dosya değişmiş); kurulmadı."; rm -f /tmp/kediray-update.sh; return 1; }
			ver=$(sed -n 's/^KR_VERSION="\(.*\)"/\1/p' /tmp/kediray-update.sh | head -1)
			# GitHub önbelleği dosyaları farklı anlarda yenileyebilir: VERSION eski, betik yeni olabilir (sorun değil, SHA256 betikle eşleşti).
			# Betik duyurulandan ESKİYSE (bayat önbellek) kurma.
			[ -n "$ver" ] && ! ver_gt "$latest" "$ver" || { echo "Dosya sürümü ($ver) duyurulan sürümden ($latest) eski; GitHub önbelleği henüz yenilenmemiş olabilir, birkaç dakika sonra tekrar dene. Kurulmadı."; rm -f /tmp/kediray-update.sh; return 1; }
			cmd_selfupdate /tmp/kediray-update.sh
			return $? ;;
		*) echo "kullanım: kediray update check [--json] | install [force] | auto | cached" >&2; return 1 ;;
	esac
}

# ---- Yedek: kediray backup [dosya] | restore <dosya> ---------------------------------------------------
# Yedek = /etc/config/kediray (sunucular, uygulama kuralları, cihaz yönleri, ayarlar) düz uci metni.
# DİKKAT: sunucu kimlikleri (UUID/şifre) içerir; yedek dosyasını kimseyle paylaşma, GitHub'a yükleme.
cmd_backup() { # [dosya]  (dosya verilmezse stdout'a yazar)
	local out="$1" tmp="/tmp/kediray-backup.$$"
	[ -s /etc/config/kediray ] || { echo "Yedeklenecek ayar yok (/etc/config/kediray boş)" >&2; return 1; }
	uci export kediray > "$tmp" 2>/dev/null && head -n1 "$tmp" | grep -q '^package kediray' || { rm -f "$tmp"; echo "Yedek alınamadı" >&2; return 1; }
	if [ -n "$out" ]; then
		mv "$tmp" "$out" || { rm -f "$tmp"; echo "Yazılamadı: $out" >&2; return 1; }
		echo "Yedek yazıldı: $out ($(uci show kediray 2>/dev/null | grep -c '=node$') sunucu)"
	else
		cat "$tmp"; rm -f "$tmp"
	fi
	return 0
}
cmd_restore() { # <dosya>
	local f="$1" d="/tmp/kediray-restore.chk" nn na
	[ -f "$f" ] || { echo "Dosya bulunamadı: $f" >&2; return 1; }
	[ "$(wc -c < "$f")" -lt 1048576 ] || { echo "Dosya çok büyük; KediRay yedeği değil." >&2; return 1; }
	head -n1 "$f" | grep -q '^package kediray' || { echo "Bu dosya bir KediRay yedeği değil (ilk satır 'package kediray' olmalı)." >&2; return 1; }
	grep -q '^config ' "$f" || { echo "Yedekte hiç ayar yok." >&2; return 1; }
	# önce geçici bir yerde dene: bozuksa gerçek ayarlara dokunma
	rm -rf "$d"; mkdir -p "$d"; : > "$d/kediray"
	uci -q -c "$d" import kediray < "$f" || { rm -rf "$d"; echo "Yedek okunamadı (bozuk dosya); mevcut ayarlar değişmedi." >&2; return 1; }
	nn=$(uci -q -c "$d" show kediray | grep -c '=node$'); na=$(uci -q -c "$d" show kediray | grep -c '=app$')
	rm -rf "$d"
	# geri dönüş için mevcut ayarı sakla
	cp /etc/config/kediray /etc/kediray.pre-restore 2>/dev/null
	uci -q import kediray < "$f" || { cp /etc/kediray.pre-restore /etc/config/kediray 2>/dev/null; echo "Geri yükleme başarısız; eski ayarlar korundu." >&2; return 1; }
	uci commit kediray
	apply_changes >/dev/null 2>&1
	echo "Yedek geri yüklendi: $nn sunucu, $na uygulama kuralı. (Önceki ayarlar: /etc/kediray.pre-restore)"
	return 0
}
cmd_engines() { # JSON: KediRay + kurulu diğer VPN motorları ve çalışma durumu
	local s name first=1 r
	printf '['
	if running; then r=true; else r=false; fi
	printf '{"id":"kediray","name":"KediRay","running":%s}' "$r"
	for s in $KNOWN_VPN; do
		[ -x "/etc/init.d/$s" ] || continue
		case "$s" in
			xwrt) name="xDivine-Ray" ;; neko) name="Neko" ;; passwall) name="PassWall" ;; passwall2) name="PassWall 2" ;;
			openclash) name="OpenClash" ;; nikki) name="Nikki" ;; mihomo) name="Mihomo" ;; homeproxy) name="HomeProxy" ;;
			v2raya) name="v2rayA" ;; sing-box) name="sing-box" ;; xlite) name="xlite" ;; *) name="$s" ;;
		esac
		if svc_running "$s"; then r=true; else r=false; fi
		printf ',{"id":"%s","name":"%s","running":%s}' "$s" "$name" "$r"
	done
	printf ']\n'
}
cmd_engine() { # <ad> start|stop  — aynı anda yalnızca bir motor çalışır
	local e="$1" act="$2" s
	case "$act" in start|stop) ;; *) echo "kullanım: kediray engine <ad> start|stop" >&2; return 1 ;; esac
	if [ "$e" = kediray ]; then
		if [ "$act" = stop ]; then
			uci set "$CONF.main.enabled=0"; uci commit "$CONF"
			svc stop
			echo "KediRay durduruldu"
			return 0
		fi
		cmd_takeover
		return $?
	fi
	case " $KNOWN_VPN " in *" $e "*) ;; *) echo "bilinmeyen motor: $e" >&2; return 1 ;; esac
	[ -x "/etc/init.d/$e" ] || { echo "böyle bir servis yok: $e" >&2; return 1; }
	if [ "$act" = stop ]; then
		/etc/init.d/"$e" stop >/dev/null 2>&1
		cleanup_other "$e"
		/etc/init.d/dnsmasq restart >/dev/null 2>&1
		echo "$e durduruldu"
		return 0
	fi
	if running; then
		uci set "$CONF.main.enabled=0"; uci commit "$CONF"
		svc stop
		/etc/init.d/kediray disable >/dev/null 2>&1
		echo "KediRay durduruldu"
	fi
	for s in $(conflicts); do
		[ "$s" = "$e" ] && continue
		/etc/init.d/"$s" stop >/dev/null 2>&1
		cleanup_other "$s"
		/etc/init.d/"$s" disable >/dev/null 2>&1
		echo "$s durduruldu"
	done
	/etc/init.d/dnsmasq restart >/dev/null 2>&1
	/etc/init.d/"$e" enable >/dev/null 2>&1
	/etc/init.d/"$e" start >/dev/null 2>&1
	sleep 3
	if svc_running "$e"; then echo "$e başlatıldı"; log "motor değişti: $e"; return 0; fi
	echo "$e başlatılamadı" >&2
	return 1
}
cmd_engine_bg() { # <ad> start|stop — arka planda çalıştırır (panel isteği zaman aşımına uğramasın)
	case "$1" in ''|*[!a-z0-9-]*) echo "geçersiz ad" >&2; return 1 ;; esac
	case "$2" in start|stop) ;; *) echo "start|stop olmalı" >&2; return 1 ;; esac
	rm -f /tmp/kediray-engine.rc
	: > /tmp/kediray-engine.log
	( $(command -v setsid) sh -c "/usr/bin/kediray engine $1 $2; echo \$? > /tmp/kediray-engine.rc" >/tmp/kediray-engine.log 2>&1 </dev/null & )
	echo "başlatıldı"
	return 0
}
cmd_engine_log() {
	if [ -f /tmp/kediray-engine.rc ]; then echo "DONE $(cat /tmp/kediray-engine.rc)"
	elif [ -f /tmp/kediray-engine.log ]; then echo RUNNING
	else echo "DONE 1"; fi
	tail -n 60 /tmp/kediray-engine.log 2>/dev/null
	return 0
}
cmd_app_add() { # <ad> <vpn|direct> <portlar> <alan adları (virgüllü)> <IP'ler (virgüllü)> [dns] [komşu /24 genişletme: 24]
	local name route ports doms ips id base n x tdns expand
	name=$(printf '%s' "$1" | tr -d '\r\n' | cut -c1-40); route="$2"; ports="$3"; doms="$4"; ips="$5"; tdns="$6"; expand="$7"
	case "$expand" in ''|16|24) ;; *) echo "genişletme 16 ya da 24 olmalı" >&2; return 1 ;; esac
	[ -n "$name" ] || { echo "ad gerekli" >&2; return 1; }
	case "$route" in vpn|direct|warp|frag) ;; *) echo "yol vpn, direct, warp ya da frag olmalı" >&2; return 1 ;; esac
	[ -n "$ports$doms$ips" ] || { echo "en az bir port, alan adı ya da IP gir" >&2; return 1; }
	for x in $ports; do
		echo "$x" | grep -qE '^[0-9]{1,5}(-[0-9]{1,5})?$' || { echo "geçersiz port: $x" >&2; return 1; }
	done
	set -f
	for x in $(echo "$doms" | tr ',' ' '); do
		echo "$x" | grep -qE '^[A-Za-z0-9._:-]+$' || { set +f; echo "geçersiz alan adı: $x" >&2; return 1; }
	done
	for x in $(echo "$ips" | tr ',' ' '); do
		echo "$x" | grep -qE '^([0-9]{1,3}(\.[0-9]{1,3}){3}(/[0-9]{1,2})?|geoip:[a-z0-9_-]+)$' || { set +f; echo "geçersiz IP: $x" >&2; return 1; }
	done
	base=$(printf '%s' "$name" | tr 'A-Z' 'a-z' | tr -c 'a-z0-9\n' '_' | sed 's/^_*//;s/_*$//' | cut -c1-24)
	[ -n "$base" ] || base=app
	id="$base"; n=1
	while [ -n "$(uci -q get "$CONF.$id")" ]; do n=$((n + 1)); id="${base}_$n"; done
	uci set "$CONF.$id=app"
	uci set "$CONF.$id.name=$name"
	uci set "$CONF.$id.enabled=1"
	uci set "$CONF.$id.route=$route"
	[ -n "$ports" ] && uci set "$CONF.$id.ports=$ports"
	[ "$tdns" = dns ] && [ -n "$doms" ] && uci set "$CONF.$id.tunnel_dns=1"
	[ -n "$expand" ] && uci set "$CONF.$id.expand=$expand"
	for x in $(echo "$doms" | tr ',' ' '); do
		case "$x" in *:*) ;; *) x="domain:$x" ;; esac
		uci add_list "$CONF.$id.domain=$x"
	done
	for x in $(echo "$ips" | tr ',' ' '); do uci add_list "$CONF.$id.ip=$x"; done
	set +f
	uci commit "$CONF"
	echo "$name eklendi ($route)"
	apply_changes
	return 0
}
cmd_app_del() { # <app>
	[ "$(uci -q get "$CONF.$1")" = app ] || { echo "böyle bir uygulama yok: $1" >&2; return 1; }
	uci delete "$CONF.$1"
	uci commit "$CONF"
	echo "silindi: $1"
	apply_changes
	return 0
}
cmd_wan_ready() { # WAN'ın (tünel dışı) varsayılan rotası var mı? 0 = hazır
	ip -4 route show default 2>/dev/null | awk -v t="dev $TUN_DEV" 'index($0, t) == 0 { f = 1 } END { exit !f }'
}
cmd_autodirect() { # on|off  — on: direkt çıkış yoksa direkt seçilenler otomatik VPN'e çevrilir; off: seçim her zaman uygulanır
	local v
	case "$1" in on) v=1 ;; off) v=0 ;; *) echo "kullanım: kediray autodirect on|off" >&2; return 1 ;; esac
	uci set "$CONF.main.auto_direct=$v"
	uci commit "$CONF"
	if [ "$v" = 0 ]; then echo "Direkt seçilenler her zaman direkt çıkar (otomatik VPN'e çevirme KAPALI)"; else echo "Direkt çıkış yoksa direkt seçilenler otomatik VPN'e çevrilir"; fi
	apply_changes
	return 0
}
cmd_direct() { # [check]  durumu gösterir; check: yeniden yoklar ve uygular
	local old new
	if [ "${1:-}" = check ]; then
		old=$(cat "$RUN/direct" 2>/dev/null)
		mkdir -p "$RUN"
		if direct_probe; then new=ok; else new=dead; fi
		echo "$new" > "$RUN/direct"; rm -f "$RUN/direct.cand"
		[ "$old" != "$new" ] && apply_changes
	fi
	if ! direct_auto; then echo "Otomatik direkt denetimi: KAPALI (seçimine hep uyulur). Ölçülen direkt çıkış: $(direct_state | sed 's/^dead$/YOK/;s/^ok$/VAR/') — YOK ise bildirimler (FCM) VPN'den gider"; return 0; fi
	case "$(direct_state)" in
		dead) echo "Direkt çıkış: YOK -> Metin2, Teams, kendi 'direkt' kuralların ve direkt cihazlar VPN'den çıkıyor" ;;
		*)    echo "Direkt çıkış: VAR -> uygulama yolları ayarlarındaki gibi" ;;
	esac
}

# ---------- yapılandırma üretimi ----------
cmd_gen() {
	local ips="" tag sec tp addr port proto net insecure sni pin name ip rc cap
	mkdir -p "$RUN"
	cap=$(capture_eff)
	echo "$cap" > "$RUN/capture"
	export KR_WAN_DNS="$(wan_dns)"
	export KR_CAPTURE="$cap" KR_MARK_CORE="$MARK_CORE" KR_MARK_TP="$MARK_TP" KR_MARK_TUN="$MARK_TUN" \
		KR_TUN="$TUN_DEV" KR_TUN_ADDR="$TUN_ADDR"
	if cap_insecure; then export KR_CAP_INSECURE=1; else export KR_CAP_INSECURE=0; fi
	if [ "$(direct_state)" = dead ]; then export KR_DIRECT_DEAD=1; else export KR_DIRECT_DEAD=0; fi
	ucode "$SHARE/gen.uc" nodes > "$RUN/nodes.tsv" 2>/dev/null
	pin_nodes
	ucode "$SHARE/gen.uc" nodes > "$RUN/nodes.tsv" 2>/dev/null
	resolve_all
	ips=$(cat "$RUN/server_ips")

	KR_RESOLVE="$(cat "$RUN/resolve" 2>/dev/null)" ucode "$SHARE/gen.uc" xray > "$RUN/config.new.json" 2> "$RUN/gen.err"
	rc=$?
	if [ $rc != 0 ]; then
		rm -f "$RUN/config.new.json"
		{ echo "Yapılandırma üretilemedi:"; cat "$RUN/gen.err"; } > "$RUN/last_error"
		return $rc
	fi
	corebin >/dev/null || { sayerr "Xray çekirdeği bulunamadı: kediray update-core"; echo "Xray çekirdeği bulunamadı (kediray update-core)" > "$RUN/last_error"; return 1; }
	# Aynı yapılandırma + aynı çekirdek + aynı geo dosyaları daha önce test edildiyse testi atla (açılışı birkaç sn kısaltır)
	local tkey tfile
	tkey="$(md5sum < "$RUN/config.new.json" | cut -d' ' -f1)-$(xr version 2>/dev/null | awk 'NR==1{print $2}')-$(wc -c < "$(assetdir)/geoip.dat" 2>/dev/null)-$(wc -c < "$(assetdir)/geosite.dat" 2>/dev/null)"
	tfile=/etc/kediray.tested
	if [ "$(cat "$tfile" 2>/dev/null)" = "$tkey" ]; then
		: > "$RUN/test.log"
	elif ! xr run -test -c "$RUN/config.new.json" > "$RUN/test.log" 2>&1; then
		rm -f "$tfile"
		sayerr "Xray yapılandırma testi başarısız:"
		grep -iE 'fail|error|invalid' "$RUN/test.log" | tail -n 3 >&2
		{ echo "Xray yapılandırma testi başarısız:"; grep -iE 'fail|error|invalid' "$RUN/test.log" | tail -n 3; } > "$RUN/last_error"
		logger -t kediray -p daemon.err "Xray yapılandırma testi başarısız: $(grep -iE 'fail|error|invalid' "$RUN/test.log" | tail -n 1)"
		return 1
	else
		echo "$tkey" > "$tfile"
	fi
	mv "$RUN/config.new.json" "$RUN/config.json"
	KR_LAN_IFS="$(lan_ifs)" KR_SERVER_IPS="$ips" ucode "$SHARE/gen.uc" nft > "$RUN/rules.nft" || return 1
	ucode "$SHARE/gen.uc" dnsmasq > "$RUN/dnsmasq.conf" || return 1
	case "$cap" in mixed|tun)
		# hev'in hangi anahtar adlarını tanıdığını ikili dosyadan oku (xDivine gibi)
		if grep -q 'tcp-read-write-timeout' "$(hevbin)" 2>/dev/null; then export KR_HEV_KEYS=split
		elif grep -q 'read-write-timeout' "$(hevbin)" 2>/dev/null; then export KR_HEV_KEYS=single
		else export KR_HEV_KEYS=split; fi
		ucode "$SHARE/gen.uc" hev > "$RUN/hev.yaml" || return 1 ;;
	esac
	rm -f "$RUN/last_error"
	return 0
}

# Sunucu alan adlarını bir kez IP'ye çevir (IP ile bağlanma + güvenlik duvarı istisnası)
resolve_all() { # [düğüm listesi]
	local tag sec tp addr port proto net insecure sni pin name ip ips="" map="" f="${1:-$RUN/nodes.tsv}"
	[ -s "$f" ] || { : > "$RUN/server_ips"; : > "$RUN/resolve"; return 0; }
	while IFS="$T" read -r tag sec tp addr port proto net insecure sni pin name; do
		ip=$(resolve4 "$addr")
		[ -n "$ip" ] || continue
		ips="$ips $ip"
		[ "$ip" != "$addr" ] && map="$map $addr=$ip"
	done < "$f"
	echo "$ips" > "$RUN/server_ips"
	echo "$map" > "$RUN/resolve"
}

# ---------- güvenlik duvarı + DNS ----------
dnsmasq_confdir() {
	local d
	d=$(uci -q get dhcp.@dnsmasq[0].confdir)
	[ -n "$d" ] || d=$(sed -n 's/^conf-dir=\([^,]*\).*/\1/p' /var/etc/dnsmasq.conf.* 2>/dev/null | head -n1)
	[ -n "$d" ] || d=/tmp/dnsmasq.d
	echo "$d"
}

# Mobil/CGNAT hatlarda (5G) sunucuya giden SYN paketi ara sıra düşüyor. Çekirdeğin varsayılanı
# 6 yeniden deneme = ~50 sn: tarayıcı o istek için 50 saniye asılı kalıyor ("pending"/"failed" satırları).
# 3 deneme ≈ 15 sn: bağlantı hızlı başarısız olur, tarayıcı kendi yeniden denemesiyle sayfayı tamamlar.
# tcp_retries2: kurulmuş ama sessizce ölmüş bağlantıların ne kadar süreyle beklendiği (15 ≈ 15+ dk).
# Hız ayarı: çekirdeğin TCP alma/gönderme tamponları küçük başlar ve yavaş büyür; 200 Mbps'lik bir hatta ilk saniyelerde
# hız yavaş yükselir. Başlangıç ve üst sınır büyütülür (yalnızca yükseltilir, mevcut değer daha büyükse dokunulmaz).
speed_tune() {
	[ "$(uget main.speed_tune)" = 0 ] && return 0
	local k v cur want conf=/etc/sysctl.d/99-kediray-speed.conf out=""
	for k in net.ipv4.tcp_rmem net.ipv4.tcp_wmem; do
		[ -w "/proc/sys/$(echo "$k" | tr . /)" ] || continue
		want="4096 262144 16777216"
		cur=$(cat "/proc/sys/$(echo "$k" | tr . /)")
		set -- $cur
		# orta değer (başlangıç) ve üst sınır mevcuttan küçükse yükselt
		[ "${2:-0}" -ge 262144 ] && [ "${3:-0}" -ge 16777216 ] || echo "$want" > "/proc/sys/$(echo "$k" | tr . /)" 2>/dev/null
		out="$out$k=$want\n"
	done
	for k in net.core.rmem_max net.core.wmem_max; do
		[ -w "/proc/sys/$(echo "$k" | tr . /)" ] || continue
		cur=$(cat "/proc/sys/$(echo "$k" | tr . /)")
		[ "$cur" -ge 16777216 ] 2>/dev/null || echo 16777216 > "/proc/sys/$(echo "$k" | tr . /)" 2>/dev/null
		out="$out$k=16777216\n"
	done
	# boşta kalan bağlantı yeniden yavaş başlamasın (ör. hız testi ile hemen sonraki test)
	[ -w /proc/sys/net/ipv4/tcp_slow_start_after_idle ] && echo 0 > /proc/sys/net/ipv4/tcp_slow_start_after_idle 2>/dev/null
	out="${out}net.ipv4.tcp_slow_start_after_idle=0\n"
	[ -d /etc/sysctl.d ] && printf "$out" > "$conf"
	return 0
}

net_tune() {
	speed_tune
	on_off() { [ "$(uget main.mobile_tune)" != 0 ]; }
	on_off || return 0
	local f
	for f in syn_retries:3 retries2:8; do
		[ -w "/proc/sys/net/ipv4/tcp_${f%%:*}" ] && echo "${f##*:}" > "/proc/sys/net/ipv4/tcp_${f%%:*}" 2>/dev/null
	done
	# kalıcı olsun (modem yeniden başlayınca da geçerli)
	if [ -d /etc/sysctl.d ] && [ ! -f /etc/sysctl.d/99-kediray.conf ]; then
		printf 'net.ipv4.tcp_syn_retries=3\nnet.ipv4.tcp_retries2=8\n' > /etc/sysctl.d/99-kediray.conf
	fi
	return 0
}

dns_up() {
	local dir new old
	# DNS modu 'off': üretilen dnsmasq parçası boştur -> modemin kendi DNS'ine hiç dokunma
	[ -s "$RUN/dnsmasq.conf" ] || { dns_down; return 0; }
	dir=$(dnsmasq_confdir)
	mkdir -p "$dir"
	new=$(md5sum "$RUN/dnsmasq.conf" 2>/dev/null | cut -d' ' -f1)
	old=$(md5sum "$dir/kediray.conf" 2>/dev/null | cut -d' ' -f1)
	if [ "$new" != "$old" ]; then
		cp "$RUN/dnsmasq.conf" "$dir/kediray.conf"
		/etc/init.d/dnsmasq restart >/dev/null 2>&1
	fi
	echo "$dir" > "$RUN/dnsdir"
}

# --- DNS acil yedeği ---------------------------------------------------------
# DNS modu "Tünelden" iken tünel bağlantıyı düşürürse modem HİÇBİR adı çözemez:
# tarayıcıda sayfalar yarım kalır, "bağlanılıyor" yazıp bekler. Ölçüldü (webtest): iki adres de
# ad çözümleme aşamasında zaman aşımına düştü. Bu yüzden tünel DNS'i yanıt vermediğinde
# geçici olarak operatörün DNS'ine düşülür; tünel düzelince kendiliğinden geri alınır.
dns_probe() { # çekirdeğin DNS'i (dnsmasq üzerinden) yanıt veriyor mu
	local t=""
	command -v timeout >/dev/null 2>&1 && t="timeout 6"
	$t nslookup www.gstatic.com 127.0.0.1 2>/dev/null | awk '
		/^Name:/ { f = 1 }
		f && /^Address/ { for (i = 2; i <= NF; i++) if ($i ~ /^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$/) { print $i; exit } }' | grep -q .
}

dns_rescue_on() { # operatör DNS'ine geç
	local dir w
	w=$(wan_dns)
	# Operatör DNS'i bilinmiyorsa (bazı WAN kurulumları) önyükleme adresine düş: ölü DNS'ten iyidir
	[ -n "$w" ] || w=$(uget main.dns_bootstrap); [ -n "$w" ] || w=1.1.1.1
	dir=$(dnsmasq_confdir); mkdir -p "$dir"
	{
		echo "# KediRay - DNS acil yedeği (tünel DNS'i yanıt vermiyor)"
		echo "no-resolv"
		for x in $w; do echo "server=$x"; done
		[ "$(uget main.ipv6)" = 1 ] || echo "filter-AAAA"
	} > "$dir/kediray.conf"
	echo "$dir" > "$RUN/dnsdir"
	: > "$RUN/dns_rescue"
	/etc/init.d/dnsmasq restart >/dev/null 2>&1
	log "DNS acil yedeği: tünel DNS'i yanıt vermedi, operatör DNS'ine geçildi ($w)"
}

dns_rescue_off() { # normal (tünel) DNS'ine dön
	rm -f "$RUN/dns_rescue"
	dns_up
	log "DNS acil yedeği kapatıldı: tünel DNS'i yeniden çalışıyor"
}

dns_guard() { # watchdog'dan çağrılır
	[ "$(uget main.dns_mode)" = private ] || { [ -f "$RUN/dns_rescue" ] && dns_rescue_off; return 0; }
	[ -s "$RUN/dnsmasq.conf" ] || return 0
	if dns_probe; then
		[ -f "$RUN/dns_rescue" ] && dns_rescue_off
		rm -f "$RUN/dns_fail"
		return 0
	fi
	# Tek seferlik takılma yüzünden DNS'i değiştirme: iki tur üst üste yanıtsız kalmalı
	if [ -f "$RUN/dns_fail" ]; then
		[ -f "$RUN/dns_rescue" ] || dns_rescue_on
	else
		: > "$RUN/dns_fail"
	fi
	return 0
}

dns_down() {
	local d removed=0
	rm -f "$RUN/dns_rescue" "$RUN/dns_fail"
	for d in "$(cat "$RUN/dnsdir" 2>/dev/null)" "$(dnsmasq_confdir)" /tmp/dnsmasq.d /tmp/dnsmasq.cfg01411c.d; do
		[ -n "$d" ] && [ -f "$d/kediray.conf" ] && { rm -f "$d/kediray.conf"; removed=1; }
	done
	[ "$removed" = 1 ] && /etc/init.d/dnsmasq restart >/dev/null 2>&1
	rm -f "$RUN/dnsdir"
	return 0
}

port_open() { # tcp port dinleniyor mu (IPv4 veya IPv6 soket)
	local hex f files=""
	hex=$(printf '%04X' "$1")
	for f in /proc/net/tcp /proc/net/tcp6; do [ -r "$f" ] && files="$files $f"; done
	[ -n "$files" ] || return 1
	# shellcheck disable=SC2086
	awk -v p=":$hex" 'FNR > 1 && $4 == "0A" && substr($2, length($2) - 4) == p { f = 1 } END { exit !f }' $files
}

fw_up_real() {
	[ -s "$RUN/config.json" ] && [ -s "$RUN/rules.nft" ] || return 1
	local i=0
	while ! port_open "$(tp_port)"; do
		i=$((i + 1))
		[ $i -gt 30 ] && { sayerr "Xray başlamadı (port $(tp_port) açılmadı); kurallar uygulanmadı"; return 1; }
		sleep 0.5 2>/dev/null || sleep 1
	done
	local cap
	cap=$(cat "$RUN/capture" 2>/dev/null); cap=${cap:-mixed}
	case "$cap" in mixed|tun)
		i=0
		while ! ip link show "$TUN_DEV" >/dev/null 2>&1; do
			i=$((i + 1))
			[ $i -gt 30 ] && { sayerr "hev-socks5-tunnel TUN aygıtını ($TUN_DEV) açmadı; kurallar uygulanmadı"; return 1; }
			sleep 0.5 2>/dev/null || sleep 1
		done
		ip addr show dev "$TUN_DEV" 2>/dev/null | grep -q 'inet ' || ip addr add "$TUN_ADDR/24" dev "$TUN_DEV" 2>/dev/null
		ip link set dev "$TUN_DEV" up
		fw_zone ;;
	esac
	rules_down
	traffic_sample
	nft -f "$RUN/rules.nft" || { sayerr "nftables kuralları yüklenemedi"; return 1; }
	case "$cap" in
		tproxy)
			ip -4 rule add fwmark $MARK_TP lookup $TABLE_TP pref $PREF_TP
			ip -4 route replace local 0.0.0.0/0 dev lo table $TABLE_TP ;;
		mixed|tun)
			# Çekirdeğin kendi bağlantıları her zaman ana tablodan; işaretli paketler TUN tablosuna
			# (mixed: sadece UDP · tun: TCP+UDP hepsi)
			ip -4 rule add fwmark $MARK_CORE lookup main pref $PREF_CORE
			ip -4 route replace default dev "$TUN_DEV" table $TABLE_TUN
			ip -4 rule add fwmark $MARK_TUN lookup $TABLE_TUN pref $PREF_TUN ;;
	esac
	net_tune
	dns_up
	apply_node
	echo up > "$RUN/fw"
	log "kurallar uygulandı ($(lan_ifs)) · modem açılışından $(cut -d. -f1 /proc/uptime) sn sonra"
}

rules_down() {
	local p i
	for p in $PREF_TP $PREF_CORE $PREF_TUN; do
		i=0
		while ip -4 rule del pref "$p" 2>/dev/null; do i=$((i + 1)); [ $i -gt 16 ] && break; done
	done
	ip -4 route flush table $TABLE_TP 2>/dev/null
	ip -4 route flush table $TABLE_TUN 2>/dev/null
}

fw_down_real() {
	traffic_sample save
	nft delete table inet kediray 2>/dev/null
	nft delete table inet kediray_out 2>/dev/null
	rules_down
	dns_down
	rm -f "$RUN/fw"
}

# mixed mod: TUN aygıtı için güvenlik duvarı bölgesi. fw4 bölgesi olmayan aygıta iletilen paketi sessizce
# düşürür; bölge yoksa bir kez oluşturulur ve çekirdekte gerçekten yüklendiği kontrol edilir (xDivine gibi).
fw_zone() {
	local lan_zone i name
	nft list ruleset 2>/dev/null | grep -q "\"$TUN_DEV\"" && return 0
	if ! uci -q get firewall.kediray >/dev/null; then
		uci -q batch <<-EOF
			set firewall.kediray=zone
			set firewall.kediray.name='kediray'
			set firewall.kediray.input='REJECT'
			set firewall.kediray.output='ACCEPT'
			set firewall.kediray.forward='REJECT'
			set firewall.kediray.masq='1'
			set firewall.kediray.mtu_fix='1'
			add_list firewall.kediray.device='$TUN_DEV'
		EOF
	fi
	if ! uci -q get firewall.kediray_fwd >/dev/null; then
		lan_zone=lan; i=0
		while name=$(uci -q get "firewall.@zone[$i].name"); do
			case " $(uci -q get "firewall.@zone[$i].network") " in *" lan "*) lan_zone="$name"; break ;; esac
			i=$((i + 1)); [ $i -gt 32 ] && break
		done
		uci -q batch <<-EOF
			set firewall.kediray_fwd=forwarding
			set firewall.kediray_fwd.src='$lan_zone'
			set firewall.kediray_fwd.dest='kediray'
		EOF
	fi
	uci -q commit firewall
	/etc/init.d/firewall reload >/dev/null 2>&1
	nft list ruleset 2>/dev/null | grep -q "\"$TUN_DEV\"" || say "uyarı: güvenlik duvarı $TUN_DEV için kural yüklemedi; UDP (oyun/arama) tünelden geçmeyebilir. Kontrol: fw4 check"
	return 0
}

# Sabit sunucu seçimini canlı uygula (yeniden başlatmadan)
# Sunucu seçimi her zaman sabitlenir (override). Otomatik modda bile seçilen sunucuda KALINIR ve sadece
# o sunucu düşünce başkasına geçilir: çıkış IP'si oturum ortasında değişmez -> Metin2 gibi oyunlar atmaz.
# (Xray'in kendi leastPing seçimi eşit hızdaki sunucular arasında sürekli gidip gelir.)
set_override() { # <etiket>
	local i=0
	while ! xr api bo -s "$(api_addr)" -b proxy "$1" >/dev/null 2>&1; do
		i=$((i + 1)); [ $i -gt 10 ] && { say "sunucu seçimi uygulanamadı (API yanıt vermedi)"; return 1; }
		sleep 1
	done
	echo "$1" > "$RUN/sticky"
	rm -f "$RUN/sticky.fail"
}

# Ölçüm adresleri: birincil + yedek. Biri engellenir/yavaşlarsa sunucu boş yere "düştü" sayılmasın.
probe_url_list() {
	local a b u
	a=$(uget main.probe_url); a=${a:-http://www.gstatic.com/generate_204}
	b=$(uget main.probe_url2); b=${b:-https://cp.cloudflare.com/generate_204}
	for u in "$a" "$b"; do
		[ -n "$u" ] || continue
		echo "$u" | sed 's#^https://#http://#'
	done | awk '!seen[$0]++'
}
probe_socks() { # <socks-port> [zaman aşımı] -> ms (ilk yanıt veren adres); hiçbiri olmazsa 1
	local u t m=${2:-6}
	for u in $(probe_url_list); do
		t=$(curl -s -o /dev/null --noproxy '' -m "$m" -w '%{http_code} %{time_total}' -x "socks5h://127.0.0.1:$1" "$u" 2>/dev/null)
		case "$t" in 2*|3*) echo "$t" | awk '{ printf "%d\n", $2 * 1000 }'; return 0 ;; esac
	done
	return 1
}
# Soğuk + sıcak ölçüm: aynı komutta iki istek. İlki TCP+TLS+WebSocket el sıkışmalarını içerir (yeni bağlantı),
# ikincisi açık bağlantıdan gider = tünelin gerçek gidiş-dönüş gecikmesi (sayfalar/oyun bunu hisseder).
probe_socks2() { # <socks-port> [zaman aşımı] -> "soğuk sıcak" (ms); başarısızsa 1
	local u out m=${2:-8}
	for u in $(probe_url_list); do
		out=$(curl -s -o /dev/null -o /dev/null --noproxy '' -m "$m" -x "socks5h://127.0.0.1:$1" \
			-w '%{http_code} %{time_starttransfer}\n' "$u" "$u" 2>/dev/null)
		echo "$out" | awk 'NR == 1 { if ($1 < 200 || $1 >= 400) exit 1; c = $2 } NR == 2 { w = $2 }
			END { if (c == "") exit 1; printf "%d %d\n", c * 1000, (w == "" ? c : w) * 1000 }' && return 0
	done
	return 1
}

probe_tag() { # <etiket> -> ms (başarısızsa dönüş kodu 1)
	local tp
	tp=$(awk -F"$T" -v g="$1" '$1 == g { print $3 }' "$RUN/nodes.tsv")
	[ -n "$tp" ] || return 1
	probe_socks "$tp"
}

auto_pick() { # [hariç etiket] -> en hızlı çalışan sunucunun etiketi (paralel ölçüm)
	local tag sec tp rest d
	d="$RUN/pick.$$"; mkdir -p "$d"
	while IFS="$T" read -r tag sec tp rest; do
		[ "$tag" = "$1" ] && continue
		( ms=$(probe_tag "$tag") && echo "$ms $tag" > "$d/$tag" ) &
	done < "$RUN/nodes.tsv"
	wait
	cat "$d"/* 2>/dev/null | sort -n | awk 'NR == 1 { print $2 }'
	rm -rf "$d"
}

apply_node() {
	local sel tag
	sel=$(uget main.node)
	[ "$sel" = none ] && return 0
	[ -s "$RUN/nodes.tsv" ] || return 0
	if [ -z "$sel" ] || [ "$sel" = auto ]; then
		tag=$(cat "$RUN/sticky" 2>/dev/null)
		# önceki seçim hâlâ listedeyse ve çalışıyorsa onda kal (yeniden başlatmada IP değişmesin)
		if [ -z "$tag" ] || ! grep -q "^$tag$T" "$RUN/nodes.tsv" || ! probe_tag "$tag" >/dev/null; then
			tag=$(auto_pick)
			[ -n "$tag" ] || tag=$(awk -F"$T" 'NR == 1 { print $1 }' "$RUN/nodes.tsv")
		fi
	else
		tag=$(awk -F"$T" -v s="$sel" '$2 == s { print $1 }' "$RUN/nodes.tsv")
	fi
	[ -n "$tag" ] && set_override "$tag"
}

# Otomatik modda: seçili sunucu 2 kez üst üste yanıt vermezse (≈2 dk) çalışan en hızlıya geç
sticky_check() {
	local cur n new
	[ "$(uget main.node)" = auto ] || return 0
	cur=$(cat "$RUN/sticky" 2>/dev/null)
	[ -n "$cur" ] || { apply_node; return 0; }
	if probe_tag "$cur" >/dev/null; then rm -f "$RUN/sticky.fail"; return 0; fi
	n=$(( $(cat "$RUN/sticky.fail" 2>/dev/null || echo 0) + 1 ))
	echo "$n" > "$RUN/sticky.fail"
	[ "$n" -lt 2 ] && return 0
	new=$(auto_pick "$cur")
	[ -n "$new" ] || { log "otomatik geçiş: $cur yanıt vermiyor ama çalışan başka sunucu da yok"; return 0; }
	set_override "$new"
	logger -t kediray -p daemon.warn "otomatik geçiş: $(awk -F"$T" -v g="$cur" '$1 == g { print $11 }' "$RUN/nodes.tsv") düştü -> $(awk -F"$T" -v g="$new" '$1 == g { print $11 }' "$RUN/nodes.tsv")"
}

# Ayar değişikliğini uygula; Xray'i sadece Xray yapılandırması gerçekten değiştiyse yeniden başlat.
# (Abonelik yenilemesi, cihaz/uygulama değişikliği oyundaki bağlantıyı gereksiz yere koparmasın.)
apply_changes() {
	local f
	[ "$(uget main.enabled)" = 1 ] || return 0
	if ! running || [ ! -s "$RUN/config.json" ]; then /etc/init.d/kediray restart >/dev/null 2>&1; return 0; fi
	for f in config.json rules.nft hev.yaml dnsmasq.conf; do cp "$RUN/$f" "$RUN/$f.old" 2>/dev/null || : > "$RUN/$f.old"; done
	if ! cmd_gen; then
		for f in config.json rules.nft hev.yaml dnsmasq.conf; do [ -s "$RUN/$f.old" ] && mv "$RUN/$f.old" "$RUN/$f"; done
		return 1
	fi
	if cmp -s "$RUN/config.json" "$RUN/config.json.old" && cmp -s "$RUN/hev.yaml" "$RUN/hev.yaml.old" 2>/dev/null; then
		if ! cmp -s "$RUN/rules.nft" "$RUN/rules.nft.old" || ! cmp -s "$RUN/dnsmasq.conf" "$RUN/dnsmasq.conf.old"; then
			with_lock fw_up_real
		fi
		log "değişiklik bağlantıları koparmadan uygulandı"
	else
		/etc/init.d/kediray restart >/dev/null 2>&1
	fi
	rm -f "$RUN"/*.old
}

active_tag() {
	xr api bi -s "$(api_addr)" proxy 2>/dev/null | awk '
		/Selecting Override/ { s = 1; next }
		/Selects/ { s = 2; next }
		s && NF >= 2 && $1 ~ /^[0-9]+$/ { if (s == 1 && o == "") o = $2; if (s == 2 && p == "") p = $2 }
		END { print (o != "" ? o : p) }'
}

# ---------- komutlar ----------
cmd_status() {
	local r=0 fw=down core="" up=0 act="" pid cf
	running && r=1
	[ -f "$RUN/fw" ] && fw=up
	cf=$(conflicts)
	if [ -s "$RUN/core.ver" ]; then core=$(cat "$RUN/core.ver"); else
		core=$(xr version 2>/dev/null | awk 'NR==1{print $2}'); mkdir -p "$RUN"; echo "$core" > "$RUN/core.ver"; fi
	if [ $r = 1 ]; then
		act=$(active_tag)
		pid=$(ubus call service list '{"name":"kediray"}' 2>/dev/null | jsonfilter -e '@.kediray.instances.xray.pid')
		[ -n "$pid" ] && [ -f "/proc/$pid/stat" ] && up=$(awk -v t="$(awk '{print int($1)}' /proc/uptime)" -v hz=100 '{print t - int($22 / hz)}' "/proc/$pid/stat")
	fi
	if [ "$1" = "--json" ]; then
		KR_RUNNING=$r KR_FW=$fw KR_CORE="$core" KR_UPTIME="$up" KR_ACTIVE="$act" KR_CONFLICT="$cf" ucode "$SHARE/cli.uc" status
	else
		KR_RUNNING=$r KR_FW=$fw KR_CORE="$core" KR_UPTIME="$up" KR_ACTIVE="$act" KR_CONFLICT="$cf" ucode "$SHARE/cli.uc" status | \
			ucode -e 'let s=json(require("fs").stdin.read("all")); print("Durum   : ", s.running ? "ÇALIŞIYOR" : (s.enabled ? "DURDU (hata?)" : "KAPALI"), "\nÇekirdek: Xray ", s.core, "\nMod     : ", s.mode, "\nSunucu  : ", s.active ? s.active.name + (s.active.ping ? " (" + s.active.ping + " ms)" : "") : "-", s.auto ? "  [otomatik]" : "  [sabit]", "\nSunucu sayısı: ", s.nodes, "\n", length(s.conflict) ? "UYARI   : çalışan başka VPN: " + join(" ", s.conflict) + "  ->  geçiş için: kediray takeover\n" : "");'
		[ "$(direct_state)" = dead ] && direct_auto && echo "Direkt  : YOK -> direkt giden her şey VPN'den çıkıyor (otomatik)"
	fi
}

# ---------- diğer VPN servisleriyle bir arada yaşama ----------
KNOWN_VPN="xwrt passwall passwall2 openclash nikki mihomo homeproxy v2raya xray v2ray sing-box neko xlite shadowsocksr ssrplus bypass vssr"

svc_running() {
	[ -x "/etc/init.d/$1" ] || return 1
	ubus call service list "{\"name\":\"$1\"}" 2>/dev/null | grep -q '"running": *true' && return 0
	/etc/init.d/"$1" running >/dev/null 2>&1
}

conflicts() { # çalışan diğer şeffaf proxy servisleri
	local s out=""
	for s in $KNOWN_VPN; do svc_running "$s" && out="$out $s"; done
	echo $out
}

cleanup_other() { # durdurulan servisin geride bıraktığı kural/DNS artıkları
	local s="$1" d f
	nft delete table ip "$s" 2>/dev/null
	nft delete table inet "$s" 2>/dev/null
	for d in /tmp/dnsmasq.d /tmp/dnsmasq.*.d "$(dnsmasq_confdir)"; do
		[ -d "$d" ] || continue
		for f in "$d"/*; do
			[ -f "$f" ] || continue
			case "$f" in */kediray.conf) continue ;; esac
			# adında servis adı geçen ya da servise ait yerel DNS yönlendirmesi içeren parçalar
			if echo "${f##*/}" | grep -qi "$s" || { grep -qi "$s" "$f" && grep -q 'server=127\.0\.0\.1#' "$f"; }; then
				rm -f "$f"
			fi
		done
	done
}

takeover_ok() { # KediRay gerçekten çalışıyor ve internet var mı
	local i=0 url
	while [ $i -lt 25 ]; do
		running && [ -f "$RUN/fw" ] && break
		i=$((i + 1)); sleep 1
	done
	running && [ -f "$RUN/fw" ] || return 1
	nslookup www.google.com 127.0.0.1 >/dev/null 2>&1 || { sleep 3; nslookup www.google.com 127.0.0.1 >/dev/null 2>&1; } || return 1
	probe_socks "$(uget main.socks_port || echo 10808)" 10 >/dev/null
}

cmd_takeover() { # [servisler]  diğer VPN'i durdur, KediRay'e geç; başarısızsa geri al
	local svcs="${*:-$(conflicts)}" s
	[ -s "$RUN/nodes.tsv" ] || ucode "$SHARE/gen.uc" nodes > "$RUN/nodes.tsv" 2>/dev/null
	[ -s "$RUN/nodes.tsv" ] || { echo "Önce en az bir sunucu ekle (panel: Link / JSON ekle)" >&2; return 1; }
	echo "Geçiş: ${svcs:-(başka VPN yok)} -> KediRay"
	for s in $svcs; do
		/etc/init.d/"$s" stop >/dev/null 2>&1
		cleanup_other "$s"
		echo "  $s durduruldu"
	done
	/etc/init.d/dnsmasq restart >/dev/null 2>&1
	uci set "$CONF.main.enabled=1"; uci commit "$CONF"
	/etc/init.d/kediray enable >/dev/null 2>&1
	svc restart
	if takeover_ok; then
		for s in $svcs; do /etc/init.d/"$s" disable >/dev/null 2>&1; done
		echo "Tamam: KediRay çalışıyor, internet VPN üzerinden geliyor."
		[ -n "$svcs" ] && echo "  ($svcs açılışta devre dışı bırakıldı; geri dönmek için: kediray rollback $svcs)"
		log "geçiş başarılı ($svcs -> kediray)"
		return 0
	fi
	echo "KediRay'de internet gelmedi, geri alınıyor..." >&2
	cmd_rollback $svcs
	return 1
}

cmd_rollback() { # [servisler]  KediRay'i kapat, eski VPN'i geri aç
	local s
	uci set "$CONF.main.enabled=0"; uci commit "$CONF"
	/etc/init.d/kediray stop >/dev/null 2>&1
	fw_down_real
	for s in "$@"; do
		/etc/init.d/"$s" enable >/dev/null 2>&1
		/etc/init.d/"$s" start >/dev/null 2>&1
		echo "  $s yeniden açıldı"
	done
	/etc/init.d/dnsmasq restart >/dev/null 2>&1
	log "geri alındı (kediray kapalı; açılan: $*)"
	echo "Geri alındı. Ayrıntı: kediray log"
}

# ---------- Metin2 DNS testi: Gameforge adlarını her DNS yolundan çöz (yanıt var mı, kaç ms, hangi IP) ----------
dnst_ms() { awk '{printf "%d", $1 * 1000}' /proc/uptime; }
dnst_ns() { # <alan adı> <dns sunucusu> -> ilk IPv4
	run_to 4 nslookup "$1" "$2" 2>/dev/null | awk '/^Name:/ { f = 1 } f && /^Address/ { for (i = 2; i <= NF; i++) if ($i ~ /^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$/) { print $i; exit } }'
}
dnst_doh() { # <url> <alan adı> [curl argümanları] -> ilk IPv4
	local u="$1" d="$2"
	shift 2
	curl -s -m 4 --noproxy '' "$@" -H 'accept: application/dns-json' "$u?name=$d&type=A" 2>/dev/null \
		| grep -o '"data":"[0-9][0-9.]*"' | head -n 1 | sed 's/^"data":"//; s/"$//'
}
dnst_row() { # <yol> <alan adı> <başlangıç ms> <IP>
	local ms tag=""
	ms=$(( $(dnst_ms) - $3 ))
	if [ -z "$4" ]; then printf '%-40s %-24s YOK\n' "$1" "$2"; return 0; fi
	case "$4" in 79.110.8[0-9].*|79.110.9[0-5].*) tag="Gameforge ağı" ;; esac
	printf '%-40s %-24s %-15s %5d ms  %s\n' "$1" "$2" "$4" "$ms" "$tag"
}
cmd_dnstest() { # [--bg|--read] [alan adı...]  Metin2 için hangi DNS yolu çalışıyor / hızlı?
	local doms d w t0 ip sp up=0
	# Arka planda çalışır: ölçüm 20 sn'yi aşabiliyor, web arayüzünün isteği o kadar bekleyemiyor
	case "${1:-}" in
		--read) bg_read dnstest; return 0 ;;
		--bg) shift; bg_start dnstest cmd_dnstest "$@"; return 0 ;;
	esac
	doms="$*"
	[ -n "$doms" ] || doms=$(uci -q get "$CONF.metin2.domain" 2>/dev/null | tr ' ' '\n' | sed -n 's/^domain://p' | head -n 3)
	[ -n "$doms" ] || doms="metin2.gameforge.com gameforge.com"
	sp=$(uget main.socks_port); sp=${sp:-1080}
	running && up=1
	echo "Metin2 DNS testi (tünel: $([ $up = 1 ] && echo AÇIK || echo KAPALI))"
	printf '%-40s %-24s %s\n' "YOL" "ALAN ADI" "SONUÇ"
	for d in $doms; do
		for w in $(wan_dns); do
			t0=$(dnst_ms); ip=$(dnst_ns "$d" "$w"); dnst_row "Operatör DNS $w (Direkt DNS: auto)" "$d" "$t0" "$ip"
		done
		t0=$(dnst_ms); ip=$(dnst_doh "https://1.1.1.1/dns-query" "$d"); dnst_row "Cloudflare DoH (direkt)" "$d" "$t0" "$ip"
		t0=$(dnst_ms); ip=$(dnst_doh "https://8.8.8.8/resolve" "$d"); dnst_row "Google DoH (direkt)" "$d" "$t0" "$ip"
		if [ $up = 1 ]; then
			t0=$(dnst_ms); ip=$(dnst_doh "https://1.1.1.1/dns-query" "$d" -x "socks5h://127.0.0.1:$sp"); dnst_row "Cloudflare DoH (tünelden)" "$d" "$t0" "$ip"
			t0=$(dnst_ms); ip=$(dnst_doh "https://8.8.8.8/resolve" "$d" -x "socks5h://127.0.0.1:$sp"); dnst_row "Google DoH (tünelden)" "$d" "$t0" "$ip"
		fi
	done
	echo "YOK = o yoldan cevap gelmedi. Google TCP (tünelden) ayrıca ölçülmez; Xray içinden gider."
	return 0
}

cmd_ping() { # [sec] [--json]  VPN kapalıyken geçici test çekirdeği kullanır
	local only="" json=0 a tag sec tp addr port proto net insecure sni pin name tmp list tpid="" i=0 pids=""
	for a in "$@"; do case "$a" in --json) json=1 ;; *) only="$a" ;; esac; done
	mkdir -p "$RUN"
	if running && [ -s "$RUN/nodes.tsv" ]; then
		list="$RUN/nodes.tsv"
	else
		# VPN kapalı: sadece ölçüm için ayrı portlarda geçici bir Xray aç (trafiği/DNS'i etkilemez)
		corebin >/dev/null || { echo "Xray çekirdeği yok (kediray update-core)" >&2; [ $json = 1 ] && ucode "$SHARE/cli.uc" nodes; return 1; }
		list="$RUN/nodes.ping.tsv"
		export KR_TEST_BASE=$(( $(uget main.test_base || echo 21000) + 500 ))
		ucode "$SHARE/gen.uc" nodes > "$list" 2>/dev/null
		[ -s "$list" ] || { echo "Ölçülecek geçerli sunucu yok" >&2; [ $json = 1 ] && ucode "$SHARE/cli.uc" nodes; return 1; }
		resolve_all "$list"
		KR_RESOLVE="$(cat "$RUN/resolve" 2>/dev/null)" ucode "$SHARE/gen.uc" test > "$RUN/ping.json" 2>/dev/null || { echo "Test yapılandırması üretilemedi" >&2; return 1; }
		XRAY_LOCATION_ASSET="$(assetdir)" "$(corebin)" run -c "$RUN/ping.json" >/dev/null 2>&1 &
		tpid=$!
		tp=$(awk -F"$T" 'NR==1{print $3}' "$list")
		while ! port_open "$tp"; do
			i=$((i + 1)); [ $i -gt 20 ] && break
			sleep 0.3 2>/dev/null || sleep 1
		done
	fi
	tmp="$RUN/ping.$$"; mkdir -p "$tmp"
	while IFS="$T" read -r tag sec tp addr port proto net insecure sni pin name; do
		[ -n "$only" ] && [ "$only" != all ] && [ "$only" != "$sec" ] && continue
		(
			ms=-1; rt=-1; warm=-1
			# Tünel testi: yeni bağlantı + tam web isteği (v2rayNG "gerçek gecikme" ile aynı) ve
			# aynı bağlantıdaki ikinci istek (açık tünelin gerçek gecikmesi).
			# Birincil adres yanıt vermezse yedek adres denenir (engellenen bir adres yüzünden "düştü" demesin).
			cw=$(probe_socks2 "$tp" 8) && { ms=${cw%% *}; warm=${cw##* }; }
			# Gerçek ağ gecikmesi: sunucuya TCP bağlantı süresi (oyunlardaki ping'e karşılık gelir)
			ipx="$addr"
			case "$addr" in *[!0-9.]*) ipx=$(tr ' ' '\n' < "$RUN/resolve" 2>/dev/null | awk -F= -v d="$addr" '$1 == d { print $2; exit }') ;; esac
			if [ -n "$ipx" ]; then
				rt=$(curl -s -o /dev/null --noproxy '' -m 4 -w '%{time_connect}' "http://$ipx:$port/" 2>/dev/null | awk '{ v = $1 * 1000; if (v > 0) printf "%d", (v < 1 ? 1 : v); else print -1 }')
			fi
			echo "$sec$T$ms$T$(date +%s)$T${rt:--1}$T${warm:--1}" > "$tmp/$sec"
		) &
		pids="$pids $!"
	done < "$list"
	# shellcheck disable=SC2086
	[ -n "$pids" ] && wait $pids
	[ -n "$tpid" ] && { kill "$tpid" 2>/dev/null; wait "$tpid" 2>/dev/null; rm -f "$RUN/ping.json"; }
	touch "$RUN/ping.tsv"
	cat "$tmp"/* 2>/dev/null > "$tmp.new"
	awk -F"$T" 'NR == FNR { n[$1] = 1; print; next } !($1 in n)' "$tmp.new" "$RUN/ping.tsv" > "$tmp.all"
	mv "$tmp.all" "$RUN/ping.tsv"
	rm -rf "$tmp" "$tmp.new"
	if [ $json = 1 ]; then ucode "$SHARE/cli.uc" nodes; else
		awk -F"$T" 'NR == FNR { p[$1] = $2; r[$1] = $4; w[$1] = $5; next } { printf "%-24s ping %-8s tünel (yeni bağlantı) %-10s tünel (açık bağlantı) %s\n", $11, (r[$2] > 0 ? r[$2] " ms" : "?"), (p[$2] == "" ? "?" : (p[$2] < 0 ? "zaman aşımı" : p[$2] " ms")), (w[$2] > 0 ? w[$2] " ms" : "?") }' "$RUN/ping.tsv" "$list"
	fi
}

cmd_auto() { # on|off  otomatik geçiş
	local act sec
	case "$1" in
		on) cmd_use auto keep ;;
		off)
			# şu an kullanılan sunucuda sabit kal
			if running; then act=$(active_tag); sec=$(awk -F"$T" -v t="$act" '$1 == t { print $2 }' "$RUN/nodes.tsv"); fi
			[ -n "$sec" ] || sec=$(awk -F"$T" '$2 >= 0 { if (b == "" || $2 < m) { m = $2; b = $1 } } END { print b }' "$RUN/ping.tsv" 2>/dev/null)
			[ -n "$sec" ] || sec=$(awk -F"$T" 'NR == 1 { print $2 }' "$RUN/nodes.tsv" 2>/dev/null)
			[ -n "$sec" ] || { echo "Sunucu yok" >&2; return 1; }
			cmd_use "$sec" ;;
		*) [ "$(uget main.node)" = auto ] && echo on || echo off ;;
	esac
}

cmd_speedtest() { # [--json]  hız ve gecikme ölçümü: direkt vs VPN
	local url="https://speed.cloudflare.com/__down?bytes=20000000" small="http://www.gstatic.com/generate_204"
	local sp d v dl vl dns r=0
	sp="socks5h://127.0.0.1:$(uget main.socks_port || echo 1080)"
	running && r=1
	d=$(curl -s -o /dev/null --noproxy '' -m 15 -w '%{speed_download}' "$url" 2>/dev/null)
	dl=$(curl -s -o /dev/null --noproxy '' -m 8 -w '%{time_starttransfer}' "$small" 2>/dev/null)
	dns=$(curl -s -o /dev/null --noproxy '' -m 8 -w '%{time_namelookup}' "https://www.wikipedia.org/" 2>/dev/null)
	if [ $r = 1 ]; then
		v=$(curl -s -o /dev/null --noproxy '' -m 15 -x "$sp" -w '%{speed_download}' "$url" 2>/dev/null)
		vl=$(curl -s -o /dev/null --noproxy '' -m 8 -x "$sp" -w '%{time_starttransfer}' "$small" 2>/dev/null)
	fi
	awk -v d="${d:-0}" -v v="${v:-0}" -v dl="${dl:-0}" -v vl="${vl:-0}" -v dns="${dns:-0}" -v r=$r -v j="$1" 'BEGIN {
		dm = d * 8 / 1000000; vm = v * 8 / 1000000
		if (j == "--json") {
			printf "{\"running\":%s,\"direct_mbps\":%.1f,\"vpn_mbps\":%.1f,\"direct_ms\":%d,\"vpn_ms\":%d,\"dns_ms\":%d}\n", (r ? "true" : "false"), dm, vm, dl * 1000, vl * 1000, dns * 1000
		} else {
			printf "Direkt : %.1f Mbps, gecikme %d ms\n", dm, dl * 1000
			if (r) printf "VPN    : %.1f Mbps, gecikme %d ms\n", vm, vl * 1000; else print "VPN    : kapalı"
			printf "DNS    : %d ms\n", dns * 1000
		}
	}'
}

# Hangi yol çalışıyor? Sayfaların "dönüp durması" (ERR_NAME_NOT_RESOLVED) hep buradan çıkıyor.
# busybox'ta "date +%s%N" yok; /proc/uptime 10 ms çözünürlükle ölçer.
now_cs() { cut -d' ' -f1 /proc/uptime 2>/dev/null | tr -d '.' || echo 0; }
el_ms() { echo $(( ($(now_cs) - $1) * 10 )); }

wan_dns() { # modeme WAN'dan verilen DNS sunucuları
	local d="" net
	if [ -f /lib/functions/network.sh ]; then
		. /lib/functions/network.sh
		network_flush_cache 2>/dev/null
		network_find_wan net 2>/dev/null && network_get_dnsserver d "$net" 2>/dev/null
	fi
	[ -n "$d" ] || d=$(awk '/^nameserver/ && $2 !~ /^127\./ { print $2 }' /tmp/resolv.conf.d/resolv.conf.auto /etc/resolv.conf 2>/dev/null | head -2)
	echo $d
}
# Gerçek (var olan) adlar kullanılır: uydurma ad NXDOMAIN döner ve yol çalışsa bile "hata" sanılır.
# Tarayıcıda takılan gerçek adresler: sorun bunlarda görülüyor
DOC_HOSTS="www.gstatic.com accounts.google.com i.ytimg.com yt3.ggpht.com fonts.gstatic.com"
doc_host() { echo "$DOC_HOSTS" | cut -d' ' -f"$1"; }

# --- tek tek yollar ---
p_udp() { # <sunucu> <ad>
	nslookup "$2" "$1" 2>/dev/null | sed -n '/^Name:/,$p' | grep -qE '^Address[^:]*: *[0-9]+\.[0-9]+'
}
p_doh() { # <url> <ad>
	curl -s -m 6 --noproxy '*' -H 'accept: application/dns-json' "$1?name=$2&type=A" 2>/dev/null \
		| grep -qE '"Answer" *:|"Status" *: *0'
}
p_doh_tun() { # <url> <ad>
	curl -s -m 8 --noproxy '*' -x "socks5h://127.0.0.1:$(uget main.socks_port || echo 10808)" \
		-H 'accept: application/dns-json' "$1?name=$2&type=A" 2>/dev/null | grep -qE '"Answer" *:|"Status" *: *0'
}
p_tcp() { # <ip> <port>  düz erişilebilirlik
	curl -s -m 5 --noproxy '*' -o /dev/null "http://$1:$2/" 2>/dev/null || [ $? = 22 ] || [ $? = 52 ] || [ $? = 56 ]
}

doc_row() { # <etiket> <komut...>
	local label=$1 t0 ms; shift
	t0=$(now_cs)
	if "$@" >/dev/null 2>&1; then
		ms=$(el_ms "$t0")
		printf '  %-36s %6s ms   ÇALIŞIYOR\n' "$label" "$ms"
		printf '%06d %s\n' "$ms" "$label" >> "$RUN/doctor.best"
	else
		printf '  %-36s %6s ms   ÇALIŞMIYOR\n' "$label" "$(el_ms "$t0")"
	fi
}

# Takılma avı: tarayıcıda asılı kalan gerçek adresleri defalarca çek, hangi AŞAMADA takıldığını göster.
# Böylece "DNS mi, bağlantı mı" sorusu tarayıcıdaki hata metnine bakmadan cevaplanır.
HUNT_URLS="https://www.gstatic.com/cast/sdk/libs/sender/1.0/cast_sender.js https://accounts.google.com/generate_204 https://www.youtube.com/favicon.ico"

# Uzun süren ölçümler: web arayüzünün isteği 1 dk'yı bekleyemiyor, arkada çalıştırıp okunuyor
bg_start() { # <ad> <komut...>
	local name="$1"; shift
	mkdir -p "$RUN"
	if [ -f "$RUN/$name.pid" ] && kill -0 "$(cat "$RUN/$name.pid")" 2>/dev/null; then echo "zaten çalışıyor"; return 0; fi
	: > "$RUN/$name.out"
	# Alt kabuğun kendi stdout/stderr'i de kapatılır: aksi halde rpcd (file exec) çıktının bitmesini bekler ve web arayüzü isteği zaman aşımına düşer
	( "$@" > "$RUN/$name.out" 2>&1 < /dev/null; rm -f "$RUN/$name.pid" ) > /dev/null 2>&1 < /dev/null &
	echo $! > "$RUN/$name.pid"
	echo "başladı"
}
bg_read() { # <ad>
	local name="$1"
	mkdir -p "$RUN"
	[ -f "$RUN/$name.out" ] || { echo "BASLAMADI"; return 0; }
	if [ -f "$RUN/$name.pid" ] && kill -0 "$(cat "$RUN/$name.pid")" 2>/dev/null; then echo "CALISIYOR"; else echo "BITTI"; fi
	cat "$RUN/$name.out"
}

# Sunucunun el sıkışmayı kaç kez düşürdüğünü ölçer (günlükteki "failed to dial ... EOF" satırlarının kaynağı).
# Alan adı birden çok IP'ye çözülüyorsa her IP ayrı ayrı denenir: hangi IP'nin bozuk olduğu görünür.
cmd_dialtest() { # [tekrar] [--bg|--read]
	local n=10 a tag sec tp addr port proto net insecure sni pin name host ips ip i okc fail line tc ta code tot bad=0 tried=0
	case "${1:-}" in
		--read) bg_read dialtest; return 0 ;;
		--bg) shift; bg_start dialtest cmd_dialtest "$@"; return 0 ;;
	esac
	for a in "$@"; do case "$a" in [0-9]*) n="$a" ;; esac; done
	[ -s "$RUN/nodes.tsv" ] || ucode "$SHARE/gen.uc" nodes > "$RUN/nodes.tsv" 2>/dev/null
	[ -s "$RUN/nodes.tsv" ] || { echo "Sunucu tanımlı değil."; return 1; }
	echo "Sunucu el sıkışma testi: her adrese $n kez sıfırdan bağlantı (TCP + TLS)."
	echo "Günlükteki 'Sunucu el sıkışma sırasında bağlantıyı kapattı (EOF)' satırlarının ne sıklıkta olduğunu ölçer."
	echo
	while IFS="$(printf '\t')" read -r tag sec tp addr port proto net insecure sni pin name; do
		[ -n "$addr" ] || continue
		host="${sni:-$addr}"
		case "$addr" in
			*[!0-9.]*) ips=$(nslookup "$addr" "$(uget main.dns_bootstrap || echo 1.1.1.1)" 2>/dev/null | awk '
				/^Name:/ { f = 1 }
				f && /^Address/ { for (i = 2; i <= NF; i++) if ($i ~ /^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$/) print $i }' | sort -u) ;;
			*) ips="$addr" ;;
		esac
		[ -n "$ips" ] || { echo "$name ($addr): adres çözülemedi"; echo; continue; }
		echo "$name — $addr:$port  (SNI: $host)"
		for ip in $ips; do
			i=0; okc=0; fail=0; tot=0
			while [ $i -lt "$n" ]; do
				i=$((i + 1))
				line=$(curl -sk -m 8 -o /dev/null --noproxy '*' --resolve "$host:$port:$ip" \
					-w '%{time_connect} %{time_appconnect} %{http_code}' "https://$host:$port/" 2>/dev/null)
				set -- ${line:-0 0 000}
				tc="$1"; ta="$2"; code="$3"
				# El sıkışma tamamlandıysa TLS süresi 0'dan büyüktür; sunucu 400/404 dönse de bağlantı kurulmuştur
				if [ "$(awk -v x="$ta" 'BEGIN{print (x > 0) ? 1 : 0}')" = 1 ]; then
					okc=$((okc + 1))
					tot=$(awk -v t="$tot" -v x="$ta" 'BEGIN{printf "%.4f", t + x}')
				else
					fail=$((fail + 1))
					awk -v i="$i" -v c="$tc" -v o="$code" 'BEGIN {
						printf "    %2d. deneme  DÜŞTÜ: %s\n", i, (c > 0 ? "TCP kuruldu ama TLS/el sıkışma tamamlanmadı (EOF/RST)" : "sunucuya hiç bağlanılamadı") }'
				fi
			done
			tried=$((tried + n)); bad=$((bad + fail))
			awk -v ip="$ip" -v o="$okc" -v n="$n" -v f="$fail" -v t="$tot" 'BEGIN {
				printf "  %-15s %d/%d başarılı", ip, o, n
				if (o > 0) printf " · ortalama el sıkışma %d ms", t / o * 1000
				if (f > 0) printf "  <-- %d DÜŞTÜ", f
				printf "\n" }'
		done
		echo
	done < "$RUN/nodes.tsv"
	echo "Yorum:"
	if [ "$bad" = 0 ]; then
		echo "  Sunucu her seferinde el sıkıştı. Günlükteki EOF satırları seyrekse sorun sunucuda değil."
	else
		awk -v b="$bad" -v t="$tried" 'BEGIN { printf "  %d/%d deneme düştü (%%%.0f). Sayfalarda takılan istekler tam olarak bunlar.\n", b, t, b * 100 / t }'
		echo "  Tek bir IP düşüyorsa: Ayarlar → Genel → \"Sunucuya IP ile bağlan\" kapat (her bağlantıda yeni IP denenir)."
		echo "  Bütün IP'ler düşüyorsa: sunucu/port operatör tarafından kısıtlanıyor olabilir — başka port (2053/2083/2087/8443) ya da ikinci sunucu dene."
	fi
	return 0
}

cmd_hunt() { # [tekrar] [url...] [--bg|--read]  varsayılan: 10 tekrar, tarayıcıda takılan adresler
	local n=10 urls="" a sp r=0 u i ok_=0 dns_slow=0 con_slow=0 fail=0 line
	# Arka planda çalıştır: ölçüm 1 dk'yı aşabiliyor, web arayüzünün isteği o kadar bekleyemiyor
	case "${1:-}" in
		--read) bg_read hunt; return 0 ;;
		--bg) shift; bg_start hunt cmd_hunt "$@"; return 0 ;;
	esac
	for a in "$@"; do case "$a" in http*) urls="$urls $a" ;; [0-9]*) n="$a" ;; esac; done
	[ -n "$urls" ] || urls="$HUNT_URLS"
	sp="socks5://127.0.0.1:$(uget main.socks_port || echo 10808)"
	running && r=1
	echo "Takılma avı: her adres $n kez (tünelden). Aşamalar: DNS | bağlantı | TLS | ilk bayt"
	echo
	for u in $urls; do
		echo "$(echo "$u" | sed 's|https*://||; s|/.*||')"
		i=0; ok_=0; fail=0; dns_slow=0; con_slow=0
		while [ $i -lt "$n" ]; do
			i=$((i + 1))
			line=$(curl -s -o /dev/null --noproxy '*' -m 25 $([ $r = 1 ] && echo "-x $sp") \
				-w '%{time_namelookup} %{time_connect} %{time_appconnect} %{time_starttransfer} %{time_total} %{http_code}' "$u" 2>/dev/null)
			set -- ${line:-0 0 0 0 0 0}
			if [ "${6:-0}" -ge 200 ] 2>/dev/null && [ "${6:-0}" -lt 400 ] 2>/dev/null; then
				ok_=$((ok_ + 1))
				awk -v d="$1" -v c="$2" -v t="$3" -v b="$4" -v o="$5" -v i="$i" 'BEGIN {
					if (o > 3) printf "  %2d. deneme  DNS %5d ms | bağlantı %5d ms | TLS %5d ms | ilk bayt %5d ms | TOPLAM %5d ms  <-- YAVAŞ\n", i, d*1000, (c-d)*1000, (t-c)*1000, (b-t)*1000, o*1000
				}'
				[ "$(awk -v d="$1" 'BEGIN{print (d > 1) ? 1 : 0}')" = 1 ] && dns_slow=$((dns_slow + 1))
				[ "$(awk -v c="$2" -v d="$1" 'BEGIN{print (c-d > 1) ? 1 : 0}')" = 1 ] && con_slow=$((con_slow + 1))
			else
				fail=$((fail + 1))
				awk -v d="$1" -v c="$2" -v o="$5" -v i="$i" 'BEGIN {
					printf "  %2d. deneme  BAŞARISIZ: %s aşamasında, %d ms sonra\n", i,
						(d >= 3 ? "DNS" : (c <= d ? "bağlantı kurulamadı" : "yanıt gelmedi")), o*1000
				}'
			fi
		done
		printf "  -> %d/%d başarılı · %d başarısız · %d kez DNS 1 sn üstü · %d kez bağlantı 1 sn üstü\n\n" "$ok_" "$n" "$fail" "$dns_slow" "$con_slow"
	done
	echo "Yorum:"
	echo "  Başarısızlıklar 'DNS aşamasında' diyorsa sorun ad çözümlemede; ayarları DNS tarafında değiştiririz."
	echo "  'bağlantı kurulamadı' diyorsa sorun tünelin sunucuya bağlanmasında; sunucu/port/SNI tarafına bakarız."
	echo "  Hiç başarısızlık yoksa sorun modemde değil, tarayıcı tarafındadır (ör. Chrome'un kendi Güvenli DNS'i)."
	return 0
}

cmd_doctor() { # [--apply]  yolları dener; --apply en iyi çalışan DNS'i ayarlara yazar
	local apply=0 r=0 w h
	[ "${1:-}" = --apply ] && apply=1
	mkdir -p "$RUN"; : > "$RUN/doctor.best"
	running && r=1
	h=$(doc_host 1)
	echo "KediRay $(kr_version) · yakalama: $(cat "$RUN/capture" 2>/dev/null || echo ?) · DNS modu: $(uget main.dns_mode || echo '(ayarsız)')"
	echo "VPN: $([ $r = 1 ] && echo çalışıyor || echo kapalı) · test adı: $h"
	echo
	echo "0) Modemin kendi (VPN'siz) internet erişimi:"
	doc_row "443 portu (1.1.1.1)" p_tcp 1.1.1.1 443
	doc_row "443 portu (8.8.8.8)" p_tcp 8.8.8.8 443
	doc_row "443 portu (9.9.9.9)" p_tcp 9.9.9.9 443
	echo "  -> $(cmd_direct)"
	echo
	echo "1) DNS yolları (her biri ayrı ayrı):"
	for w in $(wan_dns); do doc_row "operatör DNS'i $w (düz UDP)" p_udp "$w" "$h"; done
	doc_row "1.1.1.1 (düz UDP)" p_udp 1.1.1.1 "$h"
	doc_row "8.8.8.8 (düz UDP)" p_udp 8.8.8.8 "$h"
	doc_row "Cloudflare DoH (direkt)" p_doh "https://1.1.1.1/dns-query" "$h"
	doc_row "Google DoH (direkt)" p_doh "https://dns.google/resolve" "$h"
	doc_row "Quad9 DoH (direkt)" p_doh "https://dns.quad9.net:5053/dns-query" "$h"
	[ $r = 1 ] && doc_row "Cloudflare DoH (tünelden)" p_doh_tun "https://1.1.1.1/dns-query" "$h"
	echo
	echo "2) Modemin kendi çözümlemesi (istemcilerin gördüğü yol, her ad 3 kez):"
	local i k fail=0 tot=0 n=0 ms t0 hh worst=0
	for i in 1 2 3 4 5; do
		hh=$(doc_host $i)
		k=0
		while [ $k -lt 3 ]; do
			k=$((k + 1)); n=$((n + 1)); t0=$(now_cs)
			if p_udp 127.0.0.1 "$hh"; then ms=$(el_ms "$t0")
			else ms=$(el_ms "$t0"); fail=$((fail + 1)); printf '  %-36s %6s ms   BAŞARISIZ\n' "$hh" "$ms"; fi
			tot=$((tot + ms)); [ "$ms" -gt "$worst" ] && { worst=$ms; }
		done
		[ $fail = 0 ] && printf '  %-36s %6s ms   tamam\n' "$hh" "$ms"
	done
	printf '  %-36s %6s ms ortalama · en yavaş %s ms · %d/%d başarısız\n' "toplam" "$((tot / n))" "$worst" "$fail" "$n"
	echo
	if [ $r = 1 ]; then
		echo "3) Tünel:"
		# Sayfa açılırken onlarca yeni bağlantı açılır; kaçının kurulamadığı asıl sorun.
		# Tarayıcı, kurulamayan bağlantıyı dakikalarca bekler ("beklemede" kalan istekler).
		local n=20 okc=0 badc=0 i slow=0 ms t0
		i=0
		while [ $i -lt $n ]; do
			i=$((i + 1))
			t0=$(now_cs)
			if curl -s -m 8 -o /dev/null --noproxy '*' -x "socks5h://127.0.0.1:$(uget main.socks_port || echo 10808)" \
				"$(probe_url_list | head -1)" 2>/dev/null; then
				okc=$((okc + 1)); ms=$(el_ms "$t0"); [ "$ms" -gt "$slow" ] && slow=$ms
			else badc=$((badc + 1)); fi
		done
		printf '  %-36s %d/%d başarılı, %d başarısız (en yavaş %s ms)\n' "20 yeni bağlantı" "$okc" "$n" "$badc" "$slow"
		if [ "$badc" -gt 0 ]; then
			echo "  -> Yeni bağlantıların %$(( badc * 100 / n ))'i kurulamıyor. Bir sayfa 70-100 bağlantı açar;"
			echo "     bu oranda her sayfada birkaç istek askıda kalır ve tarayıcı dönmeye devam eder."
			echo "     Çözüm: Ayarlar → Kararlılık → 'TCP mux' değerini 8 yap (bir bağlantı çok isteği taşır,"
			echo "     açılan bağlantı sayısı ~10 kat azalır) ya da ikinci bir sunucu ekle."
		fi
		local cw
		cw=$(probe_socks2 "$(uget main.socks_port || echo 10808)" 8) \
			&& printf '  %-36s %6s ms (yeni bağlantı) · %s ms (açık bağlantı)\n' "tünel testi" "${cw%% *}" "${cw##* }" \
			|| echo "  tünel testi                          ÇALIŞMIYOR"
		echo
	fi
	echo "4) Bağlantı zaman aşımları (mobil hatta önemli):"
	printf '  %-36s %s (3 önerilir; 6 = düşen SYN 50 sn bekletir)\n' "tcp_syn_retries" "$(cat /proc/sys/net/ipv4/tcp_syn_retries 2>/dev/null || echo ?)"
	printf '  %-36s %s (8 önerilir; 15 = ölü bağlantı dakikalarca beklenir)\n' "tcp_retries2" "$(cat /proc/sys/net/ipv4/tcp_retries2 2>/dev/null || echo ?)"
	echo
	echo "5) Son DNS/tünel hataları:"
	logread 2>/dev/null | tail -n 400 | grep -E 'app/dns|failed to dial|connection reset|context deadline' | tail -n 4 | sed 's/^/  /'
	echo
	echo "Öneri:"
	local best bestlabel
	best=$(sort "$RUN/doctor.best" 2>/dev/null | grep -E 'DoH|UDP' | head -1)
	if [ -z "$best" ]; then
		echo "  Hiçbir DNS yolu çalışmadı."
		echo "  Modemin kendi internet erişimi (0. bölüm) da çalışmıyorsa sorun DNS değil, WAN bağlantısındadır."
	else
		bestlabel=${best#* }
		echo "  En hızlı çalışan yol: $bestlabel"
		local newdns=""
		case "$bestlabel" in
			"operatör DNS'i "*) newdns=$(echo "$bestlabel" | awk '{print $3}') ;;
			"1.1.1.1 (düz UDP)") newdns="1.1.1.1" ;;
			"8.8.8.8 (düz UDP)") newdns="8.8.8.8" ;;
			"Cloudflare DoH (direkt)") newdns="https+local://1.1.1.1/dns-query" ;;
			"Google DoH (direkt)") newdns="https+local://dns.google/dns-query" ;;
			"Quad9 DoH (direkt)") newdns="https+local://dns.quad9.net:5053/dns-query" ;;
			"Cloudflare DoH (tünelden)") newdns="tunnel" ;;
		esac
		if [ "$newdns" = tunnel ]; then
			echo "  Direkt yolların hepsi kapalı: DNS tünelden gitmeli."
			[ $apply = 1 ] && { uci set "$CONF.main.dns_mode=private"; uci commit "$CONF"; echo "  -> DNS modu 'tünelden' yapıldı."; apply_changes; }
			[ $apply = 0 ] && echo "  Uygulamak için: kediray doctor --apply"
		elif [ -n "$newdns" ]; then
			echo "  Ayarlanacak değer: dns_direct = $newdns"
			if [ $apply = 1 ]; then
				uci set "$CONF.main.dns_direct=$newdns"
				uci commit "$CONF"
				echo "  -> Uygulandı (direkt alan adları için DNS: $newdns; DNS modu değiştirilmedi)."
				apply_changes
			else
				echo "  Uygulamak için: kediray doctor --apply"
			fi
		fi
	fi
	rm -f "$RUN/doctor.best"
	return 0
}

cmd_webtest() { # [--json] [url...]  sayfa açılma gecikmesi: DNS / bağlantı / TLS / ilk bayt (direkt ve VPN)
	local json=0 urls="" a sp r=0 host d v
	for a in "$@"; do case "$a" in --json) json=1 ;; http*) urls="$urls $a" ;; esac; done
	# Varsayılan: küçük ve hızlı iki adres (biri yurt dışı, biri Türkiye). Panelden çağrıldığında
	# uzun sürerse arayüz zaman aşımına uğruyor; bu yüzden az sayıda adres ve kısa zaman aşımı.
	[ -n "$urls" ] || urls="https://www.gstatic.com/generate_204 https://www.trendyol.com/"
	sp="socks5://127.0.0.1:$(uget main.socks_port || echo 10808)"
	running && r=1
	mkdir -p "$RUN"
	: > "$RUN/webtest.tsv"
	# %{time_namelookup}: modemin kendi DNS yolu (dnsmasq -> KediRay DNS) = istemcilerin beklediği süre
	# socks5:// (socks5h değil) -> ad çözümü yerelde yapılır, yani DNS süresi ayrı ölçülür
	local W='%{time_namelookup} %{time_connect} %{time_appconnect} %{time_starttransfer} %{time_total} %{http_code}'
	for a in $urls; do
		host=$(echo "$a" | sed 's|https*://||; s|/.*||')
		d=$(curl -s -o /dev/null --noproxy '*' -m 8 -w "$W" "$a" 2>/dev/null)
		v=""
		[ $r = 1 ] && v=$(curl -s -o /dev/null --noproxy '*' -m 8 -x "$sp" -w "$W" "$a" 2>/dev/null)
		printf '%s\t%s\t%s\n' "$host" "${d:-0 0 0 0 0 0}" "${v:-0 0 0 0 0 0}" >> "$RUN/webtest.tsv"
	done
	# curl'de SOCKS desteği yoksa VPN sütunu boş kalır; bunu ölçümün içinde bildir
	local socks_ok=1
	[ $r = 1 ] && { curl --help all 2>/dev/null | grep -q -- '--socks5' || socks_ok=0; }
	KR_SOCKS_OK=$socks_ok ucode "$SHARE/cli.uc" webtest "$RUN/webtest.tsv" "$r" > "$RUN/webtest.json" || return 1
	if [ $json = 1 ]; then cat "$RUN/webtest.json"; return 0; fi
	ucode -e '
	let s = json(require("fs").readfile(ARGV[0]));
	let ms = v => sprintf("%d ms", v);
	printf("\n%-24s %9s %10s %8s %10s %10s\n", "adres", "DNS", "bağlantı", "TLS", "ilk bayt", "TOPLAM");
	for (let t in s.tests) {
		printf("%-24s\n", t.host);
		let row = (l, x) => printf("  %-22s %9s %10s %8s %10s %10s  %s\n", l, ms(x.dns), ms(x.connect), ms(x.tls), ms(x.ttfb), ms(x.total), x.code ? "HTTP " + x.code : "yanıt yok");
		row("direkt", t.direct);
		if (s.running) row("VPN", t.vpn);
	}
	printf("\nOrtalama: DNS %d ms · VPN toplam %d ms · direkt toplam %d ms\n", s.avg.dns, s.avg.vpn_total, s.avg.direct_total);
	for (let v in s.verdict) printf("  - %s\n", v);
	' "$RUN/webtest.json"
	return 0
}

cmd_best() { # en hızlıyı ölç ve ona geç (seçim sabitlenir)
	cmd_ping all >/dev/null 2>&1
	local best
	best=$(awk -F"$T" '$2 >= 0 { if (b == "" || $2 < m) { m = $2; b = $1 } } END { print b }' "$RUN/ping.tsv")
	[ -n "$best" ] || { echo "Çalışan sunucu bulunamadı" >&2; return 1; }
	if [ "$(uget main.node)" = auto ] && running; then
		set_override "$(awk -F"$T" -v s="$best" '$2 == s { print $1 }' "$RUN/nodes.tsv")"
		echo "Sunucu: $best (otomatik geçiş açık kaldı)"
	else
		cmd_use "$best"
	fi
}

cmd_use() { # <sec|auto>
	[ -n "$1" ] || { echo "kullanım: kediray use <sunucu|auto>" >&2; return 1; }
	if [ "$1" != auto ] && [ "$1" != none ]; then
		[ "$(uci -q get "$CONF.$1")" = node ] || { echo "böyle bir sunucu yok: $1" >&2; return 1; }
	fi
	local old
	old=$(uci -q get "$CONF.main.node")
	uci set "$CONF.main.node=$1"
	uci commit "$CONF"   # uci commit ile servis yeniden başlamaz -> bağlantılar kopmaz
	[ "$1" = auto ] && [ -n "$2" ] && rm -f "$RUN/sticky"
	if [ "$1" = none ] || [ "$old" = none ]; then
		# "Bağlantıyı kes": VPN açık kalır, hiçbir sunucuya bağlanılmaz, trafik direkt çıkar (yapılandırma değişir)
		[ "$1" = none ] && rm -f "$RUN/sticky" "$RUN/sticky.fail"
		running && { apply_changes; [ "$1" != none ] && apply_node; }
	else
		running && apply_node
	fi
	echo "Sunucu: $1"
}

cmd_add() { # link/JSON ekle (argüman, dosya veya stdin)
	local f="$RUN/add.$$" n
	mkdir -p "$RUN"
	if [ $# -gt 0 ]; then
		if [ -f "$1" ]; then cat "$1" > "$f"; else printf '%s\n' "$@" > "$f"; fi
	else
		cat > "$f"
	fi
	case "$(tr -d ' \t\r\n' < "$f" | cut -c1)" in
		'{'|'[')
			# JSON yapıştırıldıysa önce yazım denetimi: hatanın satır/sütununu söyle
			if ! ucode "$SHARE/node.uc" check-json "$(cat "$f")" > "$f.chk"; then
				ucode -e 'let e = json(require("fs").readfile(ARGV[0])).errors[0]; warn("JSON hatası: satır " + e.line + ", sütun " + e.col + " — " + e.msg + "\n");' "$f.chk"
				rm -f "$f" "$f.chk"; return 1
			fi
			rm -f "$f.chk" ;;
	esac
	n=$(ucode "$SHARE/link.uc" apply "$f")
	rm -f "$f"
	[ -n "$n" ] && [ "$n" -gt 0 ] 2>/dev/null || { echo "Geçerli link veya JSON bulunamadı" >&2; return 1; }
	echo "$n sunucu eklendi"
	apply_changes
	return 0
}

fetch() { # url dosya
	curl -fsSL --noproxy '' -m 30 -A "v2rayNG/1.10" -o "$2" "$1" 2>/dev/null && return 0
	running && curl -fsSL --noproxy '' -m 30 -A "v2rayNG/1.10" -x "socks5h://127.0.0.1:$(uget main.socks_port || echo 1080)" -o "$2" "$1" 2>/dev/null
}

# Güncelleme denetimi için kısa zaman aşımlı indirme: panel (rpcd) ~20 sn içinde yanıt bekler; eski 30+30 sn "panel yanıt vermedi" diyordu.
ufetch() { # url dosya [saniye]
	local t="${3:-7}"
	# VPN çalışıyorsa önce tünelden dene: modemin doğrudan GitHub çıkışı bazı hatlarda 30 sn askıda kalıp zaman aşımına uğruyor
	running && curl -fsSL --noproxy '' -m "$t" -A "v2rayNG/1.10" -x "socks5h://127.0.0.1:$(uget main.socks_port || echo 1080)" -o "$2" "$1" 2>/dev/null && return 0
	curl -fsSL --noproxy '' -m "$t" -A "v2rayNG/1.10" -o "$2" "$1" 2>/dev/null
}

cmd_sub() {
	local url id f n total=0 fail=0
	mkdir -p "$RUN"
	for url in $(uget main.sub_url); do
		id=$(printf '%s' "$url" | md5sum | cut -c1-8)
		f="$RUN/sub.$id"
		if fetch "$url" "$f" && [ -s "$f" ]; then
			n=$(ucode "$SHARE/link.uc" apply "$f" "$id" 2>/dev/null)
			if [ -n "$n" ] && [ "$n" -gt 0 ] 2>/dev/null; then total=$((total + n)); log "abonelik güncellendi: $n sunucu"; else fail=$((fail + 1)); say "abonelik boş/okunamadı: $url"; fi
		else
			fail=$((fail + 1)); sayerr "abonelik indirilemedi: $url"
		fi
		rm -f "$f"
	done
	date +%s > /etc/kediray.sub_last 2>/dev/null
	echo "Toplam $total sunucu güncellendi, $fail hata"
	[ $total -gt 0 ] && apply_changes
	return 0
}

cmd_app() { # <app> <vpn|direct> | <app> add-ip <cidr> | <app> add-port <port|a-b>
	[ "$(uci -q get "$CONF.$1")" = app ] || { echo "böyle bir uygulama yok: $1" >&2; return 1; }
	local nm cur x
	nm=$(uci -q get "$CONF.$1.name")
	case "$2" in
		vpn|direct|warp|frag)
			[ "$2" = warp ] && [ -z "$(uget main.warp_key)" ] && { echo "önce WARP hesabı aç: kediray warp register" >&2; return 1; }
			uci set "$CONF.$1.route=$2" ;;
		on) uci set "$CONF.$1.enabled=1" ;;
		off) uci set "$CONF.$1.enabled=0" ;;
		dns)
			case "$3" in
				on) uci set "$CONF.$1.tunnel_dns=1" ;;
				off) uci -q delete "$CONF.$1.tunnel_dns" ;;
				*) echo "kullanım: kediray app <ad> dns on|off" >&2; return 1 ;;
			esac ;;
		add-domain)
			echo "$3" | grep -qE '^[A-Za-z0-9._:-]+$' || { echo "geçersiz alan adı: $3" >&2; return 1; }
			case "$3" in *:*) x="$3" ;; *) x="domain:$3" ;; esac
			uci -q get "$CONF.$1.domain" | tr ' ' '\n' | grep -qx "$x" && { echo "$nm: $3 zaten listede"; return 0; }
			uci add_list "$CONF.$1.domain=$x" ;;
		add-ip)
			# Tek IP verilirse komşularıyla (aynı /24) eklenir: oyun başka bir kanal sunucusuna geçince de direkt kalır
			echo "$3" | grep -qE '^[0-9]{1,3}(\.[0-9]{1,3}){3}(/[0-9]{1,2})?$' || { echo "geçersiz IP: $3" >&2; return 1; }
			uci -q get "$CONF.$1.ip" | tr ' ' '\n' | grep -qx "$3" && { echo "$nm: $3 zaten listede"; return 0; }
			uci add_list "$CONF.$1.ip=$3" ;;
		add-port)
			echo "$3" | grep -qE '^[0-9]{1,5}(-[0-9]{1,5})?$' || { echo "geçersiz port: $3" >&2; return 1; }
			cur=$(uci -q get "$CONF.$1.ports")
			case " $cur " in *" $3 "*) echo "$nm: $3 zaten listede"; return 0 ;; esac
			uci set "$CONF.$1.ports=$(echo "$cur $3" | sed 's/^ *//')" ;;
		*) echo "kullanım: kediray app <ad> vpn|direct|warp|frag|on|off | dns on|off | add-domain <ad> | add-ip <cidr> | add-port <port>" >&2; return 1 ;;
	esac
	uci commit "$CONF"
	echo "$nm: ${3:-$2}"
	apply_changes
	return 0
}

cmd_domain_find() { # <alan adı> -> "alan adı<TAB>tür" (ana|alt|ilgili|yok); yalnız çözülenler (ana hariç)
	local in host base tld sld lab t t2 n d k
	in=$(printf '%s' "$1" | tr 'A-Z' 'a-z' | sed 's#^[a-z]*://##; s#[/?#:].*$##; s#^\*\.##; s#^\.##')
	echo "$in" | grep -qE '^[a-z0-9-]+(\.[a-z0-9-]+)+$' || { echo "geçerli bir alan adı yaz (ör. discord.com)" >&2; return 1; }
	tld=${in##*.}; t=${in%.*}; sld=${t##*.}
	base="$sld.$tld"
	case "$sld" in co|com|net|org|gov|edu|gen|k12|web|av|tel|bel)
		if [ ${#tld} -eq 2 ] && [ "$t" != "$sld" ]; then t2=${t%.*}; base="${t2##*.}.$sld.$tld"; fi ;; esac
	lab=${base%%.*}
	d=$(mktemp -d /tmp/kr-find.XXXXXX) || return 1
	# aday listesi: ana alan adı, girilen ad, yaygın alt alan adları, bilinen hizmetin ilgili alan adları
	{
		echo "$base ana"
		[ "$in" != "$base" ] && echo "$in alt"
		for k in www api cdn gateway media static images assets app login status dl download updates discovery; do echo "$k.$base alt"; done
		case "$lab" in
			discord) for k in discordapp.com discord.gg discord.media discordapp.net discordcdn.com discord.gift discordstatus.com; do echo "$k ilgili"; done ;;
			youtube|youtu|google) for k in youtube.com youtu.be googlevideo.com ytimg.com ggpht.com youtube-nocookie.com googleusercontent.com; do echo "$k ilgili"; done ;;
			instagram|facebook|fb) for k in instagram.com cdninstagram.com fbcdn.net facebook.com fb.com; do echo "$k ilgili"; done ;;
			telegram|t) for k in telegram.org t.me telegram.me tdesktop.com telesco.pe; do echo "$k ilgili"; done ;;
			spotify) for k in spotify.com scdn.co spotifycdn.com spoti.fi; do echo "$k ilgili"; done ;;
			twitter|x) for k in twitter.com x.com twimg.com t.co; do echo "$k ilgili"; done ;;
			tiktok) for k in tiktok.com tiktokcdn.com tiktokv.com byteoversea.com ibytedtos.com; do echo "$k ilgili"; done ;;
			netflix) for k in netflix.com nflxvideo.net nflximg.net nflxso.net nflxext.com; do echo "$k ilgili"; done ;;
			twitch) for k in twitch.tv ttvnw.net jtvnw.net twitchcdn.net; do echo "$k ilgili"; done ;;
			reddit) for k in reddit.com redd.it redditmedia.com redditstatic.com; do echo "$k ilgili"; done ;;
			steampowered|steamcommunity) for k in steampowered.com steamcommunity.com steamstatic.com steamcontent.com; do echo "$k ilgili"; done ;;
			zoom) for k in zoom.us zoom.com zoomgov.com; do echo "$k ilgili"; done ;;
		esac
	} | awk '!s[$1]++' > "$d/list"
	n=0
	while read -r host k; do
		n=$((n + 1))
		(
			t=""; command -v timeout >/dev/null 2>&1 && t="timeout 5"
			if $t nslookup "$host" 127.0.0.1 2>/dev/null | sed -n '/^Name:/,$p' | grep -qE '^Address[^:]*: *[0-9]+\.[0-9]+'; then
				printf '%s\t%s\n' "$host" "$k" > "$d/r.$n"
			elif [ "$k" = ana ]; then
				printf '%s\tyok\n' "$host" > "$d/r.$n"
			fi
		) &
	done < "$d/list"
	wait
	for n in $(ls "$d" | grep '^r\.' | sed 's/^r\.//' | sort -n); do cat "$d/r.$n"; done
	rm -rf "$d"
	return 0
}

# ---- Otomatik en iyi bant / frekans (isteğe bağlı; qmodem gerekir) ----
# Her bandı tek tek kilitleyip sinyali ölçer (RSRP + SINR + bant genişliği), en iyi N bandı birlikte kilitler.
# Tarama sırasında hat ~25 sn/bant kesilir; bu yüzden varsayılan olarak yalnızca seçilen saatte (gece) çalışır.
band_sec() { uci -q show qmodem 2>/dev/null | awk -F'[.=]' '$3 == "modem-device" { print $2; exit }'; }
band_qm() { ubus call qmodem "$1" "$2" 2>/dev/null; }
band_prog() { echo "$*" > "$RUN/band.progress"; }
band_ifup() { # bant kilidi modemi yeniden kayıt ettirir; wwan arayüzü (ör. wwan0_1) düştüyse tekrar kaldır
	local n up i=0
	for n in $(uci -q show network 2>/dev/null | awk -F'[.=]' '$3 == "interface" && $2 ~ /^wwan/ { print $2 }'); do
		while [ $i -lt 6 ]; do
			up=$(ifstatus "$n" 2>/dev/null | jsonfilter -e '@.up' 2>/dev/null)
			[ "$up" = true ] && break
			[ $i = 0 ] || ifup "$n" >/dev/null 2>&1
			i=$((i + 1)); sleep 5
		done
		up=$(ifstatus "$n" 2>/dev/null | jsonfilter -e '@.up' 2>/dev/null)
		[ "$up" = true ] || { ifup "$n" >/dev/null 2>&1; log "bant: $n arayüzü kapalıydı, yeniden açıldı"; }
		i=0
	done
}
band_cur() { # <sec> -> şu an bağlı olunan ana hücrenin bandı (örn. "LTE_B3" / "B3" / "N78"); bilinmiyorsa boş
	local js
	js=$(band_qm get_current_band "{\"config_section\":\"$1\"}")
	jsonfilter -s "$js" -e '@.current_band.cells[0].band_name' 2>/dev/null | head -n1
}
band_online() { # internet (wwan üzerinden) geldi mi? ~40 sn dener
	local i=0
	while [ $i -lt 8 ]; do
		ping -c1 -W3 1.1.1.1 >/dev/null 2>&1 && return 0
		ping -c1 -W3 8.8.8.8 >/dev/null 2>&1 && return 0
		i=$((i + 1)); sleep 5
	done
	return 1
}
band_avail() { # <sec> <sınıf>
	jsonfilter -s "$(band_qm get_lockband "{\"config_section\":\"$1\"}")" -e "@.lockband.$2.available_band[*].band_id" 2>/dev/null
}
band_locked() { # <sec> <sınıf>  (lock_band dizi de olabilir, "1,3,5" gibi metin de)
	local js out
	js=$(band_qm get_lockband "{\"config_section\":\"$1\"}")
	out=$(jsonfilter -s "$js" -e "@.lockband.$2.lock_band[*]" 2>/dev/null)
	[ -n "$out" ] || out=$(jsonfilter -s "$js" -e "@.lockband.$2.lock_band" 2>/dev/null | tr -d '[]" ' | tr ',' '\n')
	echo "$out" | sed '/^$/d'
}
band_lock() { # <sec> <sınıf> <id,id,...>  — boş liste ASLA yazılmaz (tüm bantları kapatır, hat gider)
	local p
	[ -n "$3" ] || { say "bant kilidi: boş liste reddedildi ($2)"; return 1; }
	p=$(printf '{"band_class":"%s","lock_band":"%s"}' "$2" "$3" | sed 's/"/\\"/g')
	band_qm set_lockband "{\"config_section\":\"$1\",\"params\":\"$p\"}" >/dev/null
}
band_meas() { # <sec> -> "rsrp sinr bw" (3 örneğin ortalaması); ölçülemezse boş
	local js r s n=0 sr=0 ss=0 i bw
	i=0
	while [ $i -lt 3 ]; do
		js=$(band_qm cell_info "{\"config_section\":\"$1\"}")
		r=$(jsonfilter -s "$js" -e '@.modem_info[@.key="RSRP"].value' 2>/dev/null | head -n1)
		s=$(jsonfilter -s "$js" -e '@.modem_info[@.key="SINR"].value' 2>/dev/null | head -n1)
		case "$r" in ''|*[!0-9.-]*) ;; *) case "$s" in ''|*[!0-9.-]*) s=0 ;; esac; sr=$(awk -v a="$sr" -v b="$r" 'BEGIN{print a+b}'); ss=$(awk -v a="$ss" -v b="$s" 'BEGIN{print a+b}'); n=$((n + 1)) ;; esac
		i=$((i + 1)); sleep 3
	done
	[ $n -gt 0 ] || return 1
	bw=$(jsonfilter -s "$(band_qm get_current_band "{\"config_section\":\"$1\"}")" -e '@.current_band.cells[0].dl_bandwidth' 2>/dev/null | head -n1 | tr -cd '0-9.')
	awk -v a="$sr" -v b="$ss" -v n="$n" -v w="${bw:-0}" 'BEGIN{printf "%.1f %.1f %s\n", a/n, b/n, w+0}'
}
band_wait() { # <sec>: modem yeniden kayıt olana kadar bekle (en çok ~45 sn)
	local i=0 js r
	sleep 8
	while [ $i -lt 16 ]; do
		js=$(band_qm cell_info "{\"config_section\":\"$1\"}")
		r=$(jsonfilter -s "$js" -e '@.modem_info[@.key="RSRP"].value' 2>/dev/null | head -n1)
		case "$r" in ''|*[!0-9.-]*) ;; *) sleep 5; return 0 ;; esac
		i=$((i + 1)); sleep 2
	done
	return 1
}

band_scan() {
	local cb sec cls classes cand cands avail keep list best res sc lockf orig="$RUN/band.orig" resf="$RUN/band.result" m rsrp sinr bw tot n k
	mkdir -p "$RUN"
	sec=$(band_sec)
	[ -n "$sec" ] && ubus list qmodem >/dev/null 2>&1 || { band_prog "hata: qmodem/modem bulunamadı"; echo "qmodem/modem bulunamadı" >&2; return 1; }
	classes=$(uget main.band_auto_class); classes=${classes:-LTE}
	[ "$classes" = LTE+NR ] && classes="LTE NR"
	keep=$(uget main.band_auto_keep); keep=${keep:-2}
	list=$(uget main.band_auto_bands | tr ',' ' ')
	: > "$orig"; : > "$resf"
	for cls in $classes; do
		echo "$cls $(band_locked "$sec" "$cls" | paste -sd, -)" >> "$orig"
	done
	cp "$orig" /etc/kediray.band.orig 2>/dev/null   # elle geri dönmek için kalıcı kopya
	band_prog "başlıyor"
	: > /etc/kediray.band.scanning                  # tarama yarıda kalırsa (yeniden kurulum, elektrik) band_recover eski kilidi geri yükler
	log "bant taraması başladı ($classes)"
	for cls in $classes; do
		avail=$(band_avail "$sec" "$cls")
		[ -n "$avail" ] || continue
		cands=""
		if [ -n "$list" ]; then
			for cand in $avail; do echo " $list " | grep -q " $cand " && cands="$cands $cand"; done
		else
			# Liste boşsa: önce Türkiye'de yaygın bantlar (sinyal olmayan bantlarda boşuna beklenmesin)
			if [ "$cls" = LTE ]; then
				for cand in 1 3 7 8 20 28 38 40 41; do echo " $avail " | tr '\n' ' ' | grep -q " $cand " && cands="$cands $cand"; done
			else
				cands=$(echo $avail)
			fi
		fi
		n=0; tot=$(echo $cands | wc -w)
		for cand in $cands; do
			n=$((n + 1)); [ $n -gt 10 ] && break
			band_prog "taranıyor: $cls B$cand ($n/$tot)"
			band_lock "$sec" "$cls" "$cand"
			band_wait "$sec" || { echo "$cls $cand - - 0 -99" >> "$resf"; continue; }
			# Kilitlenen bant gerçekten bağlı mı? (Bu bantta kapsama yoksa modem eski hücrenin değerlerini gösterir; o ölçüm geçersiz)
			cb=$(band_cur "$sec")
			if [ -n "$cb" ] && ! echo "$cb" | grep -Eq "(^|[^0-9])$cand([^0-9]|$)"; then
				echo "$cls $cand - - 0 -99" >> "$resf"
				log "bant taraması: $cls B$cand bağlanamadı (bağlı bant: $cb), atlandı"
				continue
			fi
			m=$(band_meas "$sec") || { echo "$cls $cand - - 0 -99" >> "$resf"; continue; }
			set -- $m; rsrp=$1; sinr=$2; bw=$3
			sc=$(awk -v r="$rsrp" -v s="$sinr" -v b="$bw" 'BEGIN{printf "%.1f", s + (r + 110) / 2 + b / 5}')
			echo "$cls $cand $rsrp $sinr $bw $sc" >> "$resf"
		done
		best=$(awk -v c="$cls" '$1 == c && $6 > -50 { print $6, $2 }' "$resf" | sort -rn | head -n "$keep" | awk '{print $2}' | paste -sd, -)
		if [ -n "$best" ]; then
			band_lock "$sec" "$cls" "$best"
			log "bant taraması: $cls -> $best"
		else
			# ölçüm yok: eski kilide dön
			res=$(awk -v c="$cls" '$1 == c { print $2 }' "$orig")
			[ -n "$res" ] || res=$(echo $avail | tr ' ' ',')
			band_lock "$sec" "$cls" "$res"
			say "bant taraması: $cls için ölçüm alınamadı, bant kilidi geri yüklendi ($res)"
		fi
	done
	band_wait "$sec" >/dev/null 2>&1
	band_ifup
	if ! band_online; then
		# Seçilen bant(lar)la internet gelmedi: eski kilide dön (bu bantta kapsama yok demektir)
		say "bant taraması: seçilen bantla internet gelmedi, eski bant kilidi geri yükleniyor"
		while read -r cls res; do
			[ -n "$cls" ] || continue
			[ -n "$res" ] || res=$(band_avail "$sec" "$cls" | paste -sd, -)
			band_lock "$sec" "$cls" "$res"
		done < "$orig"
		band_wait "$sec" >/dev/null 2>&1; band_ifup
		uci set "$CONF.main.band_last=$(date '+%d.%m.%Y %H:%M') — seçilen bantla internet gelmedi, eski kilide dönüldü"
		uci commit "$CONF"; band_prog "bitti (geri alındı)"; rm -f /etc/kediray.band.scanning
		return 0
	fi
	uci set "$CONF.main.band_last=$(date '+%d.%m.%Y %H:%M') — $(for cls in $classes; do printf '%s: %s  ' "$cls" "$(band_locked "$sec" "$cls" | paste -sd, -)"; done)"
	uci commit "$CONF"
	band_prog "bitti"
	rm -f /etc/kediray.band.scanning
	return 0
}

band_unlock() { # tüm bantlar açık
	local sec cls
	sec=$(band_sec); [ -n "$sec" ] || { echo "qmodem/modem bulunamadı" >&2; return 1; }
	for cls in LTE NR NR_NSA; do
		avail=$(band_avail "$sec" "$cls" | paste -sd, -)
		[ -n "$avail" ] && band_lock "$sec" "$cls" "$avail"
	done
	band_wait "$sec" >/dev/null 2>&1; band_ifup
	uci set "$CONF.main.band_last=$(date '+%d.%m.%Y %H:%M') — kilit kaldırıldı (tüm bantlar açık)"
	uci commit "$CONF"
	log "bant kilidi kaldırıldı"
	echo "Bant kilidi kaldırıldı (tüm bantlar açık)"
}

# ---- Akıllı band seçimi (1.19.32): ZTE panelindeki gibi ----
# Seçilen bantları tek tek kilitler; her birinde gerçek hızı (VPN açıksa tünel üzerinden, değilse direkt) ve sinyali
# (RSRP, SINR) ölçer, skora göre sıralar. İstenirse en iyi bandı kilitler; iptalde, hatada ya da internet gelmezse eski kilit geri yüklenir.
# Çıktı: $RUN/band.smart.state (aşama/ilerleme) ve $RUN/band.smart.result (satır: id ad kullanılan hız sinyal rsrp bw skor durum)
BS_URLS="https://speed.cloudflare.com/__down?bytes=200000000 http://speedtest.tele2.net/100MB.zip"
bs_cancelled() { [ -f "$RUN/band.cancel" ]; }
bs_sleep() { # <sn>: iptal edilirse erken döner (1)
	local i=0
	while [ "$i" -lt "$1" ]; do bs_cancelled && return 1; sleep 1; i=$((i + 1)); done
	return 0
}
bs_put() { # <aşama> [bitti]  — arayüzün okuduğu durum dosyası (band_smart içindeki yerel değişkenleri kullanır)
	printf 'cls=%s\ntotal=%s\ndone=%s\nphase=%s\nfinished=%s\nbest=%s\napplied=%s\nmeasure=%s\nnote=%s\n' \
		"$cls" "$tot" "$dn" "$1" "${2:-0}" "$best" "$applied" "$meas" "$note" > "$RUN/band.smart.state"
	band_prog "${1:-bitti}"
}
bs_cells() { # <sec> -> bağlı hücrelerin bantları (örn. N78+B3)
	jsonfilter -s "$(band_qm get_current_band "{\"config_section\":\"$1\"}")" -e '@.current_band.cells[*].band_name' 2>/dev/null | sed '/^$/d' | paste -sd+ -
}
bs_rsrp() { # <sec> -> RSRP (sayı) ya da hata
	local r
	r=$(jsonfilter -s "$(band_qm cell_info "{\"config_section\":\"$1\"}")" -e '@.modem_info[@.key="RSRP"].value' 2>/dev/null | head -n1)
	case "$r" in ''|*[!0-9.-]*) return 1 ;; esac
	echo "$r"
}
bs_wait() { # <sec> <bant id> <azami sn>: kilitlenen bant gerçekten bağlanana kadar bekle. 0=bağlandı 1=bağlanamadı 2=iptal
	local end used
	bs_sleep 2 || return 2
	end=$(( $(date +%s) + $3 ))
	while [ "$(date +%s)" -lt "$end" ]; do
		bs_cancelled && return 2
		if bs_rsrp "$1" >/dev/null; then
			used=$(bs_cells "$1")
			# bant adı bilinmiyorsa (boş) yalnızca sinyalin gelmesi yeter; biliniyorsa kilitlenen bant listede olmalı
			if [ -z "$used" ] || echo "$used" | grep -Eq "(^|[^0-9])$2([^0-9]|\$)"; then
				bs_sleep 2 || return 2
				return 0
			fi
		fi
		sleep 1
	done
	return 1
}
bs_meas() { # <sec> -> "rsrp sinr bw" (2 örneğin ortalaması, ~2 sn; band_meas'in hızlı hali)
	local js r sv n=0 sr=0 ss=0 i=0 bw
	while [ "$i" -lt 2 ]; do
		js=$(band_qm cell_info "{\"config_section\":\"$1\"}")
		r=$(jsonfilter -s "$js" -e '@.modem_info[@.key="RSRP"].value' 2>/dev/null | head -n1)
		sv=$(jsonfilter -s "$js" -e '@.modem_info[@.key="SINR"].value' 2>/dev/null | head -n1)
		case "$r" in ''|*[!0-9.-]*) ;; *) case "$sv" in ''|*[!0-9.-]*) sv=0 ;; esac; sr=$(awk -v a="$sr" -v b="$r" 'BEGIN{print a+b}'); ss=$(awk -v a="$ss" -v b="$sv" 'BEGIN{print a+b}'); n=$((n + 1)) ;; esac
		i=$((i + 1)); [ "$i" -lt 2 ] && sleep 1
	done
	[ "$n" -gt 0 ] || return 1
	bw=$(jsonfilter -s "$(band_qm get_current_band "{\"config_section\":\"$1\"}")" -e '@.current_band.cells[0].dl_bandwidth' 2>/dev/null | head -n1 | tr -cd '0-9.')
	awk -v a="$sr" -v b="$ss" -v n="$n" -v w="${bw:-0}" 'BEGIN{printf "%.1f %.1f %s\n", a/n, b/n, w+0}'
}
bs_speed() { # <sn> -> Mbps (ölçülemezse 0). 4 paralel indirme; VPN açıksa SOCKS üzerinden (hattın direkt interneti olmayabilir)
	local dur="$1" sp px="" u i pids p f t0 el fin tot
	if running; then sp=$(uget main.socks_port); px="socks5h://127.0.0.1:${sp:-10808}"; fi
	for u in $BS_URLS; do
		rm -f "$RUN"/bs.dl.* 2>/dev/null
		pids=""; i=0; t0=$(date +%s)
		while [ "$i" -lt 4 ]; do
			if [ -n "$px" ]; then
				curl -s -o /dev/null -m "$dur" --noproxy '' -x "$px" -w '%{size_download}\n' "$u" > "$RUN/bs.dl.$i" 2>/dev/null &
			else
				curl -s -o /dev/null -m "$dur" -w '%{size_download}\n' "$u" > "$RUN/bs.dl.$i" 2>/dev/null &
			fi
			pids="$pids $!"; i=$((i + 1))
		done
		# curl işini bitirince boyutu dosyaya yazar; dördü de yazdıysa ya da süre dolduysa dur
		i=0
		while [ "$i" -le $((dur + 3)) ]; do
			if bs_cancelled; then kill $pids 2>/dev/null; rm -f "$RUN"/bs.dl.* 2>/dev/null; echo 0; return 0; fi
			fin=0; for f in "$RUN"/bs.dl.*; do [ -s "$f" ] && fin=$((fin + 1)); done
			[ "$fin" -ge 4 ] && break
			sleep 1; i=$((i + 1))
		done
		el=$(( $(date +%s) - t0 )); [ "$el" -lt 1 ] && el=1; [ "$el" -gt "$dur" ] && el=$dur
		kill $pids 2>/dev/null
		tot=$(cat "$RUN"/bs.dl.* 2>/dev/null | awk '{ s += $1 } END { printf "%d", s }')
		rm -f "$RUN"/bs.dl.* 2>/dev/null
		if [ "${tot:-0}" -gt 100000 ]; then
			awk -v b="$tot" -v d="$el" 'BEGIN { printf "%.1f\n", b * 8 / d / 1000000 }'
			return 0
		fi
	done
	echo 0
}
bs_online() { # seçilen bantla internet geldi mi? (VPN açıksa tünel üzerinden, ~40 sn dener)
	local i=0 sp
	if running; then
		sp=$(uget main.socks_port); sp=${sp:-10808}
		while [ "$i" -lt 8 ]; do
			curl -s -m 6 -o /dev/null --noproxy '' -x "socks5h://127.0.0.1:$sp" "https://www.gstatic.com/generate_204" 2>/dev/null && return 0
			i=$((i + 1)); sleep 5
		done
		return 1
	fi
	band_online
}
bs_restore() { # band_smart içinden: eski kilidi geri yükle
	local r="$orig"
	[ -n "$r" ] || r=$(band_avail "$sec" "$cls" | paste -sd, -)
	band_lock "$sec" "$cls" "$r"
	band_wait "$sec" >/dev/null 2>&1; band_ifup
}

band_smart() { # --class NR_NSA|NR|LTE --bands "78 1 3" --wait 15 --measure speed|signal --apply 1|0
	local cls="" list="" wait=15 meas=speed apply=1 sec avail cands cand name js tot=0 dn=0 best="" applied=0 note="" orig="" rc m rsrp sinr bw mb sc used status resf="$RUN/band.smart.result" nf="$RUN/band.smart.names"
	while [ $# -gt 0 ]; do
		case "$1" in
			--class) cls="$2"; shift ;;
			--bands) list="$2"; shift ;;
			--wait) wait="$2"; shift ;;
			--measure) meas="$2"; shift ;;
			--apply) apply="$2"; shift ;;
		esac
		shift
	done
	case "$cls" in LTE|NR|NR_NSA) ;; *) echo "geçersiz şebeke sınıfı: $cls" >&2; return 1 ;; esac
	case "$meas" in speed|signal) ;; *) meas=speed ;; esac
	case "$wait" in ''|*[!0-9]*) wait=15 ;; esac
	[ "$wait" -lt 10 ] && wait=10
	[ "$wait" -gt 120 ] && wait=120
	mkdir -p "$RUN"
	sec=$(band_sec)
	[ -n "$sec" ] && ubus list qmodem >/dev/null 2>&1 || { echo "qmodem/modem bulunamadı" >&2; return 1; }
	js=$(band_qm get_lockband "{\"config_section\":\"$sec\"}")
	avail=$(band_avail "$sec" "$cls")
	[ -n "$avail" ] || { echo "$cls için bant listesi alınamadı" >&2; return 1; }
	cands=""
	if [ -n "$list" ]; then
		for cand in $avail; do echo " $list " | grep -q " $cand " && cands="$cands $cand"; done
	else
		cands=$(echo $avail)
	fi
	cands=$(echo $cands | cut -d' ' -f1-16)   # en çok 16 bant
	tot=$(echo $cands | wc -w)
	[ "$tot" -gt 0 ] || { echo "seçilen bantlar modemde yok" >&2; return 1; }
	# bant kimliği -> görünen ad (N78, B3 ...)
	jsonfilter -s "$js" -e "@.lockband.$cls.available_band[*].band_id" 2>/dev/null > "$nf.1"
	jsonfilter -s "$js" -e "@.lockband.$cls.available_band[*].band_name" 2>/dev/null > "$nf.2"
	paste "$nf.1" "$nf.2" > "$nf" 2>/dev/null; rm -f "$nf.1" "$nf.2"

	rm -f "$RUN/band.cancel"; : > "$resf"
	orig=$(band_locked "$sec" "$cls" | paste -sd, -)
	echo "$cls $orig" > "$RUN/band.orig"
	cp "$RUN/band.orig" /etc/kediray.band.orig 2>/dev/null   # tarama yarıda kalırsa band_recover buradan geri yükler
	: > /etc/kediray.band.scanning
	log "akıllı bant taraması başladı ($cls, $tot bant, ölçüm: $meas)"
	bs_put "Hazırlanıyor"

	for cand in $cands; do
		bs_cancelled && break
		name=$(awk -F'\t' -v i="$cand" '$1 == i { print $2; exit }' "$nf" 2>/dev/null | tr -d ' ')
		name=${name:-$cand}
		bs_put "Kilitleniyor: $name"
		band_lock "$sec" "$cls" "$cand"
		bs_wait "$sec" "$cand" "$wait"; rc=$?
		[ "$rc" = 2 ] && break
		if [ "$rc" != 0 ]; then
			echo "$cand $name - - - - - -99 nocov" >> "$resf"
			dn=$((dn + 1)); continue
		fi
		used=$(bs_cells "$sec"); used=${used:--}
		bs_put "Sinyal ölçülüyor: $name"
		m=$(bs_meas "$sec") || m=""
		bs_cancelled && break
		if [ -z "$m" ]; then
			echo "$cand $name $used - - - - -99 nomeas" >> "$resf"
			dn=$((dn + 1)); continue
		fi
		set -- $m; rsrp=$1; sinr=$2; bw=$3
		mb="-"; status=ok
		if [ "$meas" = speed ]; then
			bs_put "Hız ölçülüyor: $name"
			mb=$(bs_speed 6)
			bs_cancelled && break
			sc=$(awk -v m="$mb" -v s="$sinr" 'BEGIN { if (m + 0 > 0) printf "%.1f", m * 10 + s; else print "-99" }')
			[ "$(awk -v m="$mb" 'BEGIN { print (m + 0 > 0) ? 1 : 0 }')" = 1 ] || status=nospeed
		else
			# gece taramasıyla aynı sinyal puanı: SINR + (RSRP+110)/2 + bant genişliği/5
			sc=$(awk -v r="$rsrp" -v s="$sinr" -v b="$bw" 'BEGIN { printf "%.1f", s + (r + 110) / 2 + b / 5 }')
		fi
		echo "$cand $name $used $mb $sinr $rsrp $bw $sc $status" >> "$resf"
		dn=$((dn + 1))
	done

	best=$(awk '$9 == "ok" { print $8, $1 }' "$resf" | sort -rn | head -n1 | awk '{ print $2 }')
	if bs_cancelled; then
		bs_put "Eski band kilidi geri yükleniyor"
		bs_restore
		note="İptal edildi; eski band kilidi geri yüklendi."
	elif [ "$apply" = 1 ] && [ -n "$best" ]; then
		bs_put "En iyi bant uygulanıyor"
		band_lock "$sec" "$cls" "$best"; applied=1
		band_wait "$sec" >/dev/null 2>&1; band_ifup
		if bs_online; then
			note="En iyi bant uygulandı."
		else
			applied=0
			bs_put "İnternet gelmedi, eski kilide dönülüyor"
			bs_restore
			note="Seçilen bantla internet gelmedi; eski band kilidi geri yüklendi."
		fi
	else
		bs_put "Eski band kilidi geri yükleniyor"
		bs_restore
		if [ -n "$best" ]; then note="Eski band kilidi geri yüklendi (en iyi bant tabloda işaretli)."
		else note="Hiçbir bantta ölçüm alınamadı; eski band kilidi geri yüklendi."; fi
	fi
	uci set "$CONF.main.band_last=$(date '+%d.%m.%Y %H:%M') — akıllı seçim ($cls): $(band_locked "$sec" "$cls" | paste -sd, -)"
	uci commit "$CONF"
	dn=$tot
	bs_put "" 1
	rm -f /etc/kediray.band.scanning "$RUN/band.cancel"
	log "akıllı bant taraması bitti ($note)"
	return 0
}

band_smart_status() { # arayüz için JSON
	local run=0 st="$RUN/band.smart.state" rs="$RUN/band.smart.result"
	band_recover >/dev/null 2>&1
	[ -f "$RUN/band.pid" ] && kill -0 "$(cat "$RUN/band.pid" 2>/dev/null)" 2>/dev/null && run=1
	printf '{"running":%s' "$run"
	[ -f "$st" ] && awk '{ i = index($0, "="); if (i < 2) next; k = substr($0, 1, i - 1); v = substr($0, i + 1); gsub(/\\/, "\\\\", v); gsub(/"/, "\\\"", v); printf ",\"%s\":\"%s\"", k, v }' "$st"
	printf ',"rows":['
	[ -f "$rs" ] && awk 'function n(x) { return (x == "-" || x == "") ? "null" : x } NF >= 9 { printf "%s{\"id\":\"%s\",\"name\":\"%s\",\"used\":\"%s\",\"mbps\":%s,\"sinr\":%s,\"rsrp\":%s,\"bw\":%s,\"score\":%s,\"status\":\"%s\"}", (c++ ? "," : ""), $1, $2, $3, n($4), n($5), n($6), n($7), n($8), $9 }' "$rs"
	printf ']}\n'
}

band_info() { # modemin bant listesi (qmodem get_lockband çıktısı, JSON)
	local sec
	sec=$(band_sec)
	[ -n "$sec" ] && ubus list qmodem >/dev/null 2>&1 || { echo '{"error":"qmodem/modem bulunamadı"}'; return 1; }
	band_qm get_lockband "{\"config_section\":\"$sec\"}"
}

cmd_band() { # scan [--bg] | unlock | status | auto on|off
	case "$1" in
		scan)
			# --bg: dnstest ile aynı yöntem (stdout/stderr/stdin kapalı) — aksi halde rpcd çıktının bitmesini bekler, web arayüzü "XHR timed out" der
			if [ "$2" = --bg ]; then bg_start band band_scan
			elif [ -f "$RUN/band.pid" ] && kill -0 "$(cat "$RUN/band.pid" 2>/dev/null)" 2>/dev/null; then echo "tarama zaten sürüyor" >&2; return 1
			else band_scan; fi ;;
		unlock) band_unlock ;;
		restore) band_recover --force ;;
		smart) # kediray band smart [--bg] --class NR_NSA --bands "78 1" --wait 15 --measure speed|signal --apply 1|0
			shift
			if [ "$1" = --bg ]; then
				shift
				if [ -f "$RUN/band.pid" ] && kill -0 "$(cat "$RUN/band.pid" 2>/dev/null)" 2>/dev/null; then echo "tarama zaten sürüyor" >&2; return 1; fi
				mkdir -p "$RUN"; rm -f "$RUN/band.smart.state" "$RUN/band.smart.result" "$RUN/band.cancel"
				bg_start band band_smart "$@"
			else
				band_smart "$@"
			fi ;;
		smart-status) band_smart_status ;;
		cancel) mkdir -p "$RUN"; : > "$RUN/band.cancel"; echo "iptal istendi" ;;
		info) band_info ;;
		status)
			band_recover >/dev/null
			local run=0
			[ -f "$RUN/band.pid" ] && kill -0 "$(cat "$RUN/band.pid" 2>/dev/null)" 2>/dev/null && run=1
			echo "calisiyor: $run"
			echo "ilerleme: $(cat "$RUN/band.progress" 2>/dev/null)"
			echo "son: $(uget main.band_last)"
			[ -s "$RUN/band.result" ] && { echo "--- sınıf bant RSRP SINR BW(MHz) puan"; cat "$RUN/band.result"; } ;;
		auto)
			case "$2" in
				on) uci set "$CONF.main.band_auto=1" ;;
				off) uci set "$CONF.main.band_auto=0" ;;
				*) echo "kullanım: kediray band auto on|off" >&2; return 1 ;;
			esac
			uci commit "$CONF"; echo "Otomatik bant seçimi: $2" ;;
		*) echo "kullanım: kediray band scan [--bg] | smart [--bg] --class C --bands \"id id\" | cancel | info | unlock | restore | status | auto on|off" >&2; return 1 ;;
	esac
}

band_recover() { # [--force]  yarım kalan taramadan sonra bantları eski kilide döndür (tüm bantlar kapalı/tek bantta kalmasın)
	local sec cls ids av
	[ -f /etc/kediray.band.scanning ] || [ "$1" = --force ] || return 0
	if [ "$1" != --force ]; then
		# tarama sürüyorsa dokunma: ilerleme dosyası son 4 dakikada güncellendiyse canlı say
		[ -f "$RUN/band.progress" ] && [ -z "$(find "$RUN/band.progress" -mmin +4 2>/dev/null)" ] && return 0
	fi
	sec=$(band_sec); [ -n "$sec" ] || return 0
	if [ -s /etc/kediray.band.orig ]; then
		while read -r cls ids; do
			[ -n "$cls" ] || continue
			[ -n "$ids" ] || ids=$(band_avail "$sec" "$cls" | paste -sd, -)
			band_lock "$sec" "$cls" "$ids"
		done < /etc/kediray.band.orig
	else
		band_unlock >/dev/null
	fi
	rm -f /etc/kediray.band.scanning
	band_wait "$sec" >/dev/null 2>&1; band_ifup
	log "bant: yarım kalan tarama sonrası eski bant kilidi geri yüklendi"
	echo "Eski bant kilidi geri yüklendi"
}

band_tick() { # watchdog içinden: seçilen saatte günde bir kez tara
	band_recover
	[ "$(uget main.band_auto)" = 1 ] || return 0
	local h d want
	h=$(date +%H); h=${h#0}; h=${h:-0}
	want=$(uget main.band_auto_hour); want=${want:-4}
	[ "$h" = "$want" ] || return 0
	d=$(date +%F)
	[ "$(cat "$RUN/band.day" 2>/dev/null)" = "$d" ] && return 0
	mkdir -p "$RUN"; echo "$d" > "$RUN/band.day"
	cmd_band scan --bg >/dev/null 2>&1
}

cmd_warp() { # register | on | off | via vpn|direct | status [--json] | forget
	local x priv pub body resp sp bin ts
	case "$1" in
		register)
			bin=$(corebin 2>/dev/null); [ -x "$bin" ] || { echo "Xray çekirdeği bulunamadı" >&2; return 1; }
			x=$("$bin" x25519 2>/dev/null)
			priv=$(echo "$x" | sed -n 's/^[Pp]rivate[ ]*[Kk]ey *: *//p' | head -1)
			pub=$(echo "$x" | sed -n 's/^[Pp]ublic[ ]*[Kk]ey *: *//p; s/^Password[^:]*: *//p' | head -1)
			[ -n "$priv" ] && [ -n "$pub" ] || { echo "anahtar üretilemedi" >&2; return 1; }
			# Xray anahtarları URL-güvenli, dolgusuz base64 verir; WireGuard/Cloudflare standart (dolgulu) base64 ister
			priv=$(echo "$priv" | tr '_-' '/+'); pub=$(echo "$pub" | tr '_-' '/+')
			while [ $(( ${#priv} % 4 )) -ne 0 ]; do priv="$priv="; done
			while [ $(( ${#pub} % 4 )) -ne 0 ]; do pub="$pub="; done
			ts=$(date -u +%Y-%m-%dT%H:%M:%S.000Z)
			body="{\"key\":\"$pub\",\"install_id\":\"\",\"fcm_token\":\"\",\"tos\":\"$ts\",\"type\":\"Android\",\"model\":\"PC\",\"locale\":\"en_US\"}"
			echo "Cloudflare WARP'a kaydoluyor…"
			sp=$(uget main.socks_port); [ -n "$sp" ] || sp=10808
			resp=$(curl -s -m 20 --noproxy '' -X POST -H 'Content-Type: application/json' -H 'User-Agent: okhttp/3.12.1' -H 'CF-Client-Version: a-6.3-1922' \
				-d "$body" "https://api.cloudflareclient.com/v0a2158/reg" 2>/dev/null)
			echo "$resp" | grep -q '"peers"' || resp=$(curl -s -m 25 --noproxy '' -x "socks5h://127.0.0.1:$sp" -X POST -H 'Content-Type: application/json' -H 'User-Agent: okhttp/3.12.1' -H 'CF-Client-Version: a-6.3-1922' \
				-d "$body" "https://api.cloudflareclient.com/v0a2158/reg" 2>/dev/null)
			echo "$resp" | grep -q '"peers"' || { echo "WARP kaydı alınamadı (Cloudflare'a ulaşılamadı ya da reddetti). VPN açıkken tekrar dene." >&2; return 1; }
			KR_RESP="$resp" ucode -e '
				let r = json(getenv("KR_RESP")), c = r?.config, i = c?.interface?.addresses, p = c?.peers?.[0];
				if (!p?.public_key || !i?.v4) exit(3);
				let res = [];
				let b = b64dec(c.client_id ?? "");
				if (b) for (let k = 0; k < 3; k++) push(res, ord(b, k) ?? 0);
				print(join("\n", [p.public_key, i.v4, i.v6 ?? "", join(",", length(res) == 3 ? res : [0, 0, 0]), p.endpoint?.host ?? ""]), "\n");
			' > "$RUN/warp.reg" 2>/dev/null || { echo "WARP yanıtı çözülemedi" >&2; return 1; }
			uci set "$CONF.main.warp_key=$priv"
			uci set "$CONF.main.warp_pub=$(sed -n 1p "$RUN/warp.reg")"
			uci set "$CONF.main.warp_v4=$(sed -n 2p "$RUN/warp.reg")"
			uci set "$CONF.main.warp_v6=$(sed -n 3p "$RUN/warp.reg")"
			uci set "$CONF.main.warp_reserved=$(sed -n 4p "$RUN/warp.reg")"
			uci set "$CONF.main.warp=1"
			[ -n "$(uget main.warp_via)" ] || uci set "$CONF.main.warp_via=vpn"
			rm -f "$RUN/warp.reg"
			uci commit "$CONF"
			echo "WARP hesabı oluşturuldu ve açıldı. VPN Ayırma'da bir uygulamayı 'WARP' yap."
			apply_changes
			return 0 ;;
		on|off)
			[ -n "$(uget main.warp_key)" ] || { echo "önce: kediray warp register" >&2; return 1; }
			uci set "$CONF.main.warp=$([ "$1" = on ] && echo 1 || echo 0)"; uci commit "$CONF"
			echo "WARP: $1"; apply_changes; return 0 ;;
		via)
			case "$2" in vpn|direct) ;; *) echo "kullanım: kediray warp via vpn|direct" >&2; return 1 ;; esac
			uci set "$CONF.main.warp_via=$2"; uci commit "$CONF"
			echo "WARP yolu: $2"; apply_changes; return 0 ;;
		forget)
			for x in warp warp_key warp_pub warp_v4 warp_v6 warp_reserved warp_via; do uci -q delete "$CONF.main.$x"; done
			uci commit "$CONF"; echo "WARP hesabı silindi"; apply_changes; return 0 ;;
		status|"")
			local reg=0 en=0 via
			[ -n "$(uget main.warp_key)" ] && reg=1
			[ "$(uget main.warp)" = 1 ] && en=1
			via=$(uget main.warp_via); [ -n "$via" ] || via=vpn
			if [ "$2" = --json ] || [ "$1" = "--json" ]; then
				printf '{"registered":%s,"enabled":%s,"via":"%s"}\n' "$([ $reg = 1 ] && echo true || echo false)" "$([ $en = 1 ] && echo true || echo false)" "$via"
			else
				echo "WARP: $([ $reg = 1 ] && echo kayıtlı || echo kayıtsız), $([ $en = 1 ] && echo açık || echo kapalı), yol: $via"
			fi
			return 0 ;;
		*) echo "kullanım: kediray warp register|on|off|via vpn|direct|status|forget" >&2; return 1 ;;
	esac
}

cmd_device() { # <mac> <vpn|direct|default> [ad]
	local mac sec
	mac=$(echo "$1" | tr 'A-F' 'a-f')
	echo "$mac" | grep -qE '^([0-9a-f]{2}:){5}[0-9a-f]{2}$' || { echo "geçersiz MAC: $1" >&2; return 1; }
	sec=$(uci show "$CONF" 2>/dev/null | awk -F'[.=]' -v m="$mac" 'tolower($0) ~ "\\.mac=.?" m { print $2; exit }')
	case "$2" in
		default|remove)
			[ -n "$sec" ] && uci delete "$CONF.$sec" ;;
		vpn|direct|block)
			[ -n "$sec" ] || { sec=$(uci add "$CONF" device); uci set "$CONF.$sec.mac=$mac"; }
			uci set "$CONF.$sec.mode=$2"
			[ -n "$3" ] && uci set "$CONF.$sec.name=$3" ;;
		*) echo "kullanım: kediray device <mac> vpn|direct|block|default [ad]" >&2; return 1 ;;
	esac
	uci commit "$CONF"
	echo "$mac: $2"
	apply_changes
	return 0
}

# ---------- trafik sayaçları ----------
wan_dev() {
	local net="" dev="" f="$RUN/wan_dev"
	[ -s "$f" ] && [ -d "/sys/class/net/$(cat "$f")" ] && { cat "$f"; return 0; }
	if [ -f /lib/functions/network.sh ]; then
		. /lib/functions/network.sh
		network_flush_cache 2>/dev/null
		network_find_wan net 2>/dev/null && network_get_device dev "$net" 2>/dev/null
	fi
	[ -n "$dev" ] || dev=$(ip -4 route show default 2>/dev/null | awk '{ for (i = 1; i < NF; i++) if ($i == "dev") { print $(i + 1); exit } }')
	[ -n "$dev" ] && { mkdir -p "$RUN"; echo "$dev" > "$f"; }
	echo "$dev"
}
nft_counter() { nft list counter inet kediray "$1" 2>/dev/null | awk '/bytes/ { for (i = 1; i < NF; i++) if ($i == "bytes") { print $(i + 1); exit } }'; }
# ---------- cihaz bazlı trafik (1.19.6) ----------
# Ayrı bir nft tablosu (inet kediray_acct): VPN açık/kapalı fark etmez, KediRay yeniden başlasa da sayaçlar sıfırlanmaz.
# up = cihazdan gelen (yükleme, prerouting), dn = cihaza giden (indirme, postrouting). NAT-redirect ile çekirdeğe
# giden TCP de bu iki noktadan geçtiği için VPN ve direkt trafik birlikte sayılır.
dev_ips() { # LAN'daki cihazların IPv4 adresleri (DHCP kiraları + komşu tablosu)
	local d
	{
		awk 'NF >= 4 { print $3 }' /tmp/dhcp.leases 2>/dev/null
		for d in $(lan_ifs); do
			ip -4 neigh show dev "$d" 2>/dev/null | awk '$1 ~ /^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$/ && $0 !~ /FAILED|INCOMPLETE/ { print $1 }'
		done
	} | awk '!s[$0]++ && $0 ~ /^(10\.|192\.168\.|172\.(1[6-9]|2[0-9]|3[01])\.)/' | head -n 128
}
dev_acct_sync() {
	local lanset i ip up dn
	command -v nft >/dev/null 2>&1 || return 0
	lanset=$(for i in $(lan_ifs); do printf '"%s",' "$i"; done | sed 's/,$//')
	nft list table inet kediray_acct >/dev/null 2>&1 || nft -f - <<EOF 2>/dev/null
table inet kediray_acct {
	chain up { type filter hook prerouting priority raw; policy accept; }
	chain dn { type filter hook postrouting priority 100; policy accept; }
}
EOF
	up=$(nft list chain inet kediray_acct up 2>/dev/null)
	dn=$(nft list chain inet kediray_acct dn 2>/dev/null)
	for ip in $(dev_ips); do
		echo "$up" | grep -q "saddr $ip counter" || nft add rule inet kediray_acct up iifname "{ $lanset }" ip saddr "$ip" counter 2>/dev/null
		echo "$dn" | grep -q "daddr $ip counter" || nft add rule inet kediray_acct dn oifname "{ $lanset }" ip daddr "$ip" counter 2>/dev/null
	done
	return 0
}
dev_read() { # "ip<TAB>rx|tx<TAB>bayt" (rx = cihaza gelen/indirme, tx = cihazdan giden/yükleme)
	nft list chain inet kediray_acct up 2>/dev/null | awk '/saddr/ && /bytes/ { ip = ""; b = ""; for (i = 1; i <= NF; i++) { if ($i == "saddr") ip = $(i + 1); if ($i == "bytes") b = $(i + 1) } if (ip != "" && b != "") print ip "\ttx\t" b }'
	nft list chain inet kediray_acct dn 2>/dev/null | awk '/daddr/ && /bytes/ { ip = ""; b = ""; for (i = 1; i <= NF; i++) { if ($i == "daddr") ip = $(i + 1); if ($i == "bytes") b = $(i + 1) } if (ip != "" && b != "") print ip "\trx\t" b }'
}
traffic_env() { # sayaçları ortam değişkeni olarak ver
	local dev
	dev=$(wan_dev)
	mkdir -p "$RUN"; dev_read > "$RUN/dev.cur" 2>/dev/null
	export KR_DEVF="$RUN/dev.cur"
	KR_VR=$(nft_counter vpn_rx); KR_VT=$(nft_counter vpn_tx)
	KR_WR=$(cat "/sys/class/net/$dev/statistics/rx_bytes" 2>/dev/null); KR_WT=$(cat "/sys/class/net/$dev/statistics/tx_bytes" 2>/dev/null)
	export KR_VR="${KR_VR:-0}" KR_VT="${KR_VT:-0}" KR_WR="${KR_WR:-0}" KR_WT="${KR_WT:-0}"
	[ -f /etc/TZ ] && { TZ=$(cat /etc/TZ); export TZ; }
}
traffic_sample() { # [save]
	( dev_acct_sync; traffic_env; ucode "$SHARE/traffic.uc" sample "$@" >/dev/null 2>&1 )
}

cmd_stats() { # panel: canlı sayaçlar + bugün/hafta/ay/30 gün
	( traffic_env; ucode "$SHARE/traffic.uc" report )
}

cmd_traffic() { # sample|save|restore|reset|report
	case "$1" in
		sample) traffic_sample "$2" ;;
		save|restore|reset) ucode "$SHARE/traffic.uc" "$1" ;;
		*) cmd_stats ;;
	esac
}

kr_version() { cat "$SHARE/version" 2>/dev/null || echo "?"; }

cmd_version() { # [--json]
	local ver core
	ver=$(kr_version)
	core=$(xr version 2>/dev/null | awk 'NR==1{print $2}')
	if [ "${1:-}" = --json ]; then
		printf '{"version":"%s","core":"%s"}\n' "$ver" "$core"
	else
		echo "KediRay $ver"
		echo "Xray çekirdeği: ${core:-yok}"
		echo "Geliştirici: Şaban Vurgun · 2026"
	fi
	return 0
}

cmd_watch() { # [ip] [saniye] [--json]  -> bağlantıları kaydet: hangi yoldan gitti, ne zaman koptu
	local ip="" secs=180 json=0 a
	for a in "$@"; do
		case "$a" in
			--json) json=1 ;;
			*[!0-9]*) ip="$a" ;;
			[0-9]*) secs="$a" ;;
		esac
	done
	[ -n "$ip" ] || { echo "Kullanım: kediray watch <cihaz-ip> [saniye]   (ör. kediray watch 192.168.1.20 300)" >&2; return 1; }
	mkdir -p "$RUN"
	[ -r /proc/net/nf_conntrack ] || command -v conntrack >/dev/null 2>&1 || \
		echo "not: conntrack okunamıyor (kmod-nf-conntrack-netlink / conntrack paketi gerekebilir)" >&2
	[ $json = 1 ] || echo "Kayıt başladı: $ip, $secs saniye. Şimdi sorunu yaşa (oyunda ışınlan / bildirimi bekle), sonra burada sonucu gör."
	ucode "$SHARE/watch.uc" "$secs" "$ip" "$((MARK_TUN))" 1000 > "$RUN/watch.json" || return 1
	if [ $json = 1 ]; then cat "$RUN/watch.json"; return 0; fi
	ucode -e '
	let s = json(require("fs").readfile(ARGV[0]));
	let hm = t => { let l = localtime(t); return sprintf("%02d:%02d:%02d", l.hour, l.min, l.sec); };
	let dur = d => d >= 60 ? sprintf("%d dk %02d sn", d / 60, d % 60) : sprintf("%d sn", d);
	printf("\nKayıt: %s - %s (%d sn, %d örnek)\n", hm(s.t0), hm(s.t1), s.secs, s.samples);
	if (s.conntrack)
		printf("Bağlantı tablosu: %d / %d%s\n", s.conntrack.count, s.conntrack.max,
			s.conntrack.pct > 80 ? "  <-- DOLMAK ÜZERE: kayıtlar düşünce bağlantılar sebepsiz kopar" : "");
	printf("\n%-4s %-22s %-7s %-12s %-12s %s\n", "prot", "hedef", "yol", "süre", "en uzun boş", "bitiş");
	let n = 0;
	for (let f in s.flows) {
		if (f.web && (f.dur < 30 || n > 25)) continue;   // kısa web bağlantıları gürültü
		n++;
		printf("%-4s %-22s %-7s %-12s %-12s %s\n", f.proto, f.dst + ":" + f.port, f.vpn ? "VPN" : "Direkt",
			dur(f.dur), dur(f.idle),
			f.end == null ? "açık" : (f.cut_active ? hm(f.end) + "  <-- kullanılırken koptu" : hm(f.end) + " (boştaydı)"));
	}
	if (length(s.flips)) {
		printf("\n!! YOL DEĞİŞİMİ (oyundan atılmanın sebebi bu olur):\n");
		for (let x in s.flips)
			printf("   %s  %s:%d  %s -> %s\n", hm(x.t), x.dst, x.port, x.from, x.to);
	} else printf("\nYol değişimi yok: aynı sunucuya giden bağlantıların hepsi aynı yoldan gitti.\n");
	let iv = s.idle?.vpn, id = s.idle?.direct;
	printf("\nBoşta kalma dayanıklılığı (bildirim gecikmesinin ölçüsü):\n");
	let idl = (l, x) => printf("   %-7s: %s · hayatta kalan en uzun boşluk %d sn\n", l,
		x?.killed_at != null ? sprintf("%d sn boşta kalan bağlantı KOPTU", x.killed_at) : "boştayken kopan yok", x?.survived ?? 0);
	idl("VPN", iv); idl("Direkt", id);
	if (iv?.killed_at != null && (id?.killed_at == null || id.killed_at > iv.killed_at))
		printf("   -> Tünelden geçen boştaki bağlantılar %d saniyede kesiliyor: bildirim gecikmesinin sebebi bu.\n", iv.killed_at);
	let cut = filter(s.flows, f => f.cut_active && !f.web);
	if (length(cut)) {
		printf("\nKullanılırken kopan bağlantılar (oyun/uygulama kopması):\n");
		for (let f in cut) printf("   %s  %s:%d  (%s, %s sonra)\n", hm(f.end), f.dst, f.port, f.vpn ? "VPN" : "Direkt", dur(f.dur));
	}
	' "$RUN/watch.json"
	return 0
}

cmd_conns() { # [ip] [--json]  -> oyun/uygulama portlarını bulmak için
	local ip="" json=0 a
	for a in "$@"; do case "$a" in --json) json=1 ;; *) ip="$a" ;; esac; done
	{ cat /proc/net/nf_conntrack 2>/dev/null || conntrack -L 2>/dev/null; } | ucode "$SHARE/cli.uc" conns "$ip" "$((MARK_TUN))" > "$RUN/conns.json"
	if [ $json = 1 ]; then cat "$RUN/conns.json"; else
		ucode -e 'for (let c in json(require("fs").readfile(ARGV[0]))) print(sprintf("%-4s %-15s %5d  x%-3d %-7s %s\n", c.proto, c.dst, c.port, c.n, c.vpn ? "VPN" : "DIREKT", c.web ? "(web)" : "<- oyun/uygulama olabilir"));' "$RUN/conns.json"
		echo "İpucu: oyunu açıkken çalıştır; çıkan portu Uygulamalar > Metin2 > Portlar'a ekle." >&2
	fi
}

cmd_check() { # bağlantı teşhisi
	local ok_dns=0 ok_vpn=0 ok_direct=0 ip
	running || { echo '{"running":false}'; return 0; }
	nslookup www.google.com 127.0.0.1 >/dev/null 2>&1 && ok_dns=1
	curl -s -o /dev/null --noproxy '' -m 8 -x "socks5h://127.0.0.1:$(uget main.socks_port || echo 1080)" http://www.gstatic.com/generate_204 && ok_vpn=1
	curl -s -o /dev/null --noproxy '' -m 8 http://www.gstatic.com/generate_204 && ok_direct=1
	ip=$(curl -s --noproxy '' -m 8 -x "socks5h://127.0.0.1:$(uget main.socks_port || echo 1080)" https://api.ipify.org 2>/dev/null)
	printf '{"running":true,"dns":%s,"vpn":%s,"direct":%s,"vpn_ip":"%s"}\n' \
		"$([ $ok_dns = 1 ] && echo true || echo false)" "$([ $ok_vpn = 1 ] && echo true || echo false)" \
		"$([ $ok_direct = 1 ] && echo true || echo false)" "$(echo "$ip" | tr -cd '0-9a-fA-F.:')"
}

cmd_watchdog() {
	local last now iv
	traffic_sample
	ucode "$SHARE/cli.uc" devices >/dev/null 2>&1   # cihaz yoklaması: "bağlı süre" güncel kalsın
	[ "$(uget main.enabled)" = 1 ] || return 0
	[ -f /tmp/kediray.waiting ] && return 0   # açılışta WAN bekleniyor: müdahale etme
	# Modem açılırken cron, KediRay'in kendi açılış başlatması gelmeden watchdog'u çalıştırıyordu: "Xray çalışmıyor"
	# deyip erken başlatıyor, sonra açılış betiği de başlatınca iki başlatma çarpışıyor (TUN aygıtı açılmıyor) ve
	# VPN dakikalarca gecikiyordu. Açılış betiği ilk başlatmayı yapana kadar (en çok 10 dk) bekle.
	if [ ! -f /tmp/kediray.started ] && [ "$(cut -d. -f1 /proc/uptime)" -lt 600 ]; then return 0; fi
	if ! running; then
		log "watchdog: Xray çalışmıyor, yeniden başlatılıyor"
		/etc/init.d/kediray restart >/dev/null 2>&1
		sleep 5
		if ! running; then
			if [ "$(uget main.failsafe)" = open ]; then
				fw_down_real; log "watchdog: failsafe=open, internet direkt açıldı"
			else
				dns_down; log "watchdog: killswitch - VPN trafiği kesik, DNS normale döndü"
			fi
		fi
	elif [ -f "$RUN/fw" ] && ! nft list table inet kediray >/dev/null 2>&1; then
		log "watchdog: kurallar silinmiş (güvenlik duvarı yeniden yüklenmiş olabilir), geri yükleniyor"
		with_lock fw_up_real
	elif [ ! -f "$RUN/fw" ]; then
		# Xray çalışıyor ama kurallar hiç uygulanmamış (ör. açılışta UDP tüneli/TUN gecikti). Bir dakika tolerans, sonra yeniden dene.
		if [ -f "$RUN/nofw" ]; then
			rm -f "$RUN/nofw"
			log "watchdog: kurallar uygulanmamış, yeniden deneniyor"
			with_lock fw_up_real || { log "watchdog: kurallar yine uygulanamadı, KediRay yeniden başlatılıyor"; /etc/init.d/kediray restart >/dev/null 2>&1; }
		else
			: > "$RUN/nofw"
		fi
	elif case "$(cat "$RUN/capture" 2>/dev/null)" in mixed|tun) ! ip link show "$TUN_DEV" >/dev/null 2>&1 ;; *) false ;; esac; then
		# Kurallar var ama UDP tüneli (hev) düşmüş: TUN aygıtı kayboldu
		log "watchdog: TUN aygıtı ($TUN_DEV) yok, UDP tüneli yeniden başlatılıyor"
		/etc/init.d/kediray restart >/dev/null 2>&1
	else
		rm -f "$RUN/nofw"
		sticky_check
	fi
	dns_guard
	band_tick
	running && { direct_watch; mvpn_watch; }
	iv=$(uget main.sub_interval); iv=${iv:-0}
	if [ "$iv" -gt 0 ] 2>/dev/null && [ -n "$(uget main.sub_url)" ]; then
		now=$(date +%s); last=$(cat /etc/kediray.sub_last 2>/dev/null || echo 0)
		[ $((now - last)) -ge $((iv * 3600)) ] && cmd_sub >/dev/null 2>&1
	fi
	return 0
}

xray_asset_name() {
	local a
	a=$(. /etc/openwrt_release 2>/dev/null; echo "$DISTRIB_ARCH")
	[ -n "$a" ] || a=$(uname -m)
	case "$a" in
		aarch64*|arm64*) echo arm64-v8a ;;
		arm_cortex-a15*|arm_cortex-a17*|arm_cortex-a7*|arm_cortex-a8*|arm_cortex-a9_vfp*|arm_cortex-a9_neon*|arm_cortex-a5_vfp*|arm_cortex-a53*|armv7*) echo arm32-v7a ;;
		arm_arm1176*|armv6*) echo arm32-v6 ;;
		arm_*|arm*) echo arm32-v5 ;;
		x86_64*) echo 64 ;;
		i386*|i686*|x86*) echo 32 ;;
		mipsel*|mipsle*) echo mips32le ;;
		mips64el*) echo mips64le ;;
		mips64*) echo mips64 ;;
		mips*) echo mips32 ;;
		riscv64*) echo riscv64 ;;
		loongarch64*) echo loong64 ;;
		*) return 1 ;;
	esac
}

# unzip olmadan zip açma (yalnızca stored/deflate): zip_extract <zip> <hedef-dizin> <dosya...>
# Mantık: merkez dizinden boyut/CRC okunur, her deflate verisi gzip başlığı+bitişiyle sarılıp gzip -dc ile açılır.
# gzip, CRC ve boyutu da doğruladığı için bozuk arşiv sessizce geçmez.
_zle() { # <dosya> <ofset> <bayt>  -> küçük-endian tamsayı
	set -- $(od -An -tu1 -j "$2" -N "$3" "$1"); local v=0 m=1 b
	for b in "$@"; do v=$((v + b * m)); m=$((m * 256)); done
	echo "$v"
}
_zle32() { # <değer> -> 4 bayt küçük-endian ham çıktı
	printf "\\$(printf %03o $(($1 & 255)))\\$(printf %03o $(($1 >> 8 & 255)))\\$(printf %03o $(($1 >> 16 & 255)))\\$(printf %03o $(($1 >> 24 & 255)))"
}
zip_extract() {
	local zip="$1" dir="$2" size eocd cdoff cdcnt pos i name n m k method crc csize usize lho nl ml start w want found
	shift 2
	command -v gzip >/dev/null 2>&1 || { echo "gzip yok" >&2; return 1; }
	size=$(wc -c < "$zip")
	eocd=$((size - 22))
	[ "$(_zle "$zip" "$eocd" 4)" = 101010256 ] || { echo "zip sonu okunamadı (yorumlu arşiv?)" >&2; return 1; }
	cdcnt=$(_zle "$zip" $((eocd + 10)) 2)
	cdoff=$(_zle "$zip" $((eocd + 16)) 4)
	pos=$cdoff; i=0
	while [ $i -lt "$cdcnt" ]; do
		[ "$(_zle "$zip" "$pos" 4)" = 33639248 ] || { echo "merkez dizin bozuk" >&2; return 1; }
		method=$(_zle "$zip" $((pos + 10)) 2)
		crc=$(_zle "$zip" $((pos + 16)) 4)
		csize=$(_zle "$zip" $((pos + 20)) 4)
		usize=$(_zle "$zip" $((pos + 24)) 4)
		n=$(_zle "$zip" $((pos + 28)) 2)
		m=$(_zle "$zip" $((pos + 30)) 2)
		k=$(_zle "$zip" $((pos + 32)) 2)
		lho=$(_zle "$zip" $((pos + 42)) 4)
		name=$(dd if="$zip" bs=1 skip=$((pos + 46)) count="$n" 2>/dev/null)
		for want in "$@"; do
			[ "$name" = "$want" ] || continue
			nl=$(_zle "$zip" $((lho + 26)) 2)
			ml=$(_zle "$zip" $((lho + 28)) 2)
			start=$((lho + 30 + nl + ml))
			case "$method" in
				0) tail -c +$((start + 1)) "$zip" | head -c "$csize" > "$dir/$name" ;;
				8) { printf '\037\213\010\000\000\000\000\000\000\003'
				     tail -c +$((start + 1)) "$zip" | head -c "$csize"
				     _zle32 "$crc"; _zle32 "$usize"; } | gzip -dc > "$dir/$name" 2>/dev/null ;;
				*) echo "desteklenmeyen sıkıştırma ($name)" >&2; return 1 ;;
			esac
			[ -s "$dir/$name" ] || { echo "açılamadı: $name" >&2; return 1; }
			found="$found $name"
		done
		pos=$((pos + 46 + n + m + k)); i=$((i + 1))
	done
	for want in "$@"; do case " $found " in *" $want "*) ;; *) echo "arşivde yok: $want" >&2; return 1 ;; esac; done
	return 0
}

cmd_update_core() { # [sürüm]
	local asset ver base zip tmp want got
	asset=$(xray_asset_name) || { echo "Mimari tanınmadı" >&2; return 1; }
	ver=${1:-latest}
	if [ "$ver" = latest ]; then base="https://github.com/XTLS/Xray-core/releases/latest/download"
	else base="https://github.com/XTLS/Xray-core/releases/download/$ver"; fi
	[ -n "$GH_PROXY" ] && base="$GH_PROXY/$base"
	tmp=/tmp/kediray-core; rm -rf "$tmp"; mkdir -p "$tmp"
	zip="Xray-linux-$asset.zip"
	echo "İndiriliyor: $zip ($ver)"
	fetch "$base/$zip" "$tmp/x.zip" || { echo "İndirme başarısız" >&2; rm -rf "$tmp"; return 1; }
	if fetch "$base/$zip.dgst" "$tmp/x.dgst"; then
		want=$(grep -i '256' "$tmp/x.dgst" | grep -oE '[0-9a-f]{64}' | head -n1)
		got=$(sha256sum "$tmp/x.zip" | awk '{print $1}')
		[ -n "$want" ] && [ "$want" != "$got" ] && { echo "SHA256 doğrulaması BAŞARISIZ" >&2; rm -rf "$tmp"; return 1; }
		echo "SHA256 doğrulandı"
	fi
	if command -v unzip >/dev/null 2>&1; then
		unzip -o -q "$tmp/x.zip" xray geoip.dat geosite.dat -d "$tmp" || { echo "Arşiv açılamadı" >&2; rm -rf "$tmp"; return 1; }
	else
		echo "unzip yok: yerleşik çıkarıcı kullanılıyor"
		zip_extract "$tmp/x.zip" "$tmp" xray geoip.dat geosite.dat || { echo "Arşiv açılamadı" >&2; rm -rf "$tmp"; return 1; }
	fi
	chmod 755 "$tmp/xray"
	"$tmp/xray" version >/dev/null 2>&1 || { echo "İndirilen çekirdek bu cihazda çalışmıyor ($asset)" >&2; rm -rf "$tmp"; return 1; }
	mkdir -p "$SHARE/bin"
	mv -f "$tmp/xray" "$SHARE/bin/xray"
	[ -s "$tmp/geoip.dat" ] && mv -f "$tmp/geoip.dat" "$SHARE/geoip.dat"
	[ -s "$tmp/geosite.dat" ] && mv -f "$tmp/geosite.dat" "$SHARE/geosite.dat"
	rm -rf "$tmp" "$RUN/core.ver"
	"$SHARE/bin/xray" version | head -n1
	[ "$(uget main.enabled)" = 1 ] && /etc/init.d/kediray restart >/dev/null 2>&1
	return 0
}

cmd_update_geo() {
	local b="https://github.com/Loyalsoldier/v2ray-rules-dat/releases/latest/download" f
	[ -n "$GH_PROXY" ] && b="$GH_PROXY/$b"
	for f in geoip.dat geosite.dat; do
		fetch "$b/$f" "/tmp/kr.$f" && [ -s "/tmp/kr.$f" ] && mv -f "/tmp/kr.$f" "$SHARE/$f" && echo "$f güncellendi"
	done
	[ "$(uget main.enabled)" = 1 ] && /etc/init.d/kediray restart >/dev/null 2>&1
	return 0
}

cmd_import_xwrt() { # xDivine-Ray (xwrt) sunucularını/aboneliklerini aktar
	local f=/etc/config/xwrt tmp="$RUN/xwrt.links" u n=0
	[ -f "$f" ] || { echo "xDivine-Ray yapılandırması bulunamadı" >&2; return 1; }
	mkdir -p "$RUN"
	grep -oE "(vless|vmess|trojan|ss)://[^' ]+" "$f" > "$tmp" 2>/dev/null
	[ -s "$tmp" ] && n=$(ucode "$SHARE/link.uc" apply "$tmp" 2>/dev/null)
	for u in $(grep -oE "https?://[^' ]+" "$f" | grep -viE 'github|gstatic|google|cloudflare-dns|dns-query'); do
		uci add_list "$CONF.main.sub_url=$u"; echo "abonelik bulundu: $u"
	done
	uci commit "$CONF"
	rm -f "$tmp"
	echo "${n:-0} sunucu aktarıldı"
}

cmd_uninstall() {
	nft delete table inet kediray_acct 2>/dev/null
	/etc/init.d/kediray stop >/dev/null 2>&1
	/etc/init.d/kediray disable >/dev/null 2>&1
	fw_down_real
	ip link del "$TUN_DEV" 2>/dev/null
	if uci -q get firewall.kediray >/dev/null || uci -q get firewall.kediray_fwd >/dev/null; then
		uci -q delete firewall.kediray; uci -q delete firewall.kediray_fwd; uci -q commit firewall
		/etc/init.d/firewall reload >/dev/null 2>&1
	fi
	rm -f /etc/hotplug.d/firewall/99-kediray
	sed -i '/kediray watchdog/d;/kediray update auto/d' /etc/crontabs/root 2>/dev/null
	rm -f /tmp/kediray-upd.json /etc/kediray.upd.json
	/etc/init.d/cron restart >/dev/null 2>&1
	rm -rf "$SHARE" "$RUN" /etc/init.d/kediray /etc/hotplug.d/iface/80-kediray \
		/www/luci-static/resources/view/kediray /usr/share/luci/menu.d/luci-app-kediray.json \
		/usr/share/rpcd/acl.d/luci-app-kediray.json /www/luci-static/kedi-logo.svg /etc/kediray.sub_last /etc/kediray.traffic.json
	[ "$1" = "--purge" ] && rm -f /etc/config/kediray
	rm -f /tmp/luci-indexcache* /tmp/luci-modulecache/* 2>/dev/null
	/etc/init.d/rpcd reload >/dev/null 2>&1
	rm -f /usr/bin/kediray
	echo "KediRay kaldırıldı${1:+ (ayarlar dahil)}"
}

cmd_logs() { # [clear-errors|clear-stream]  panel için sınıflandırılmış günlük (JSON)
	case "$1" in clear-errors|clear-stream) ucode "$SHARE/logs.uc" "$1"; return ;; esac
	mkdir -p "$RUN"
	if ubus call log read '{"lines":1000,"stream":false}' > "$RUN/log.raw" 2>/dev/null && grep -q '"log"' "$RUN/log.raw"; then
		ucode "$SHARE/logs.uc" read "$RUN/log.raw"
	else
		logread 2>/dev/null | tail -n 1000 > "$RUN/log.raw"
		ucode "$SHARE/logs.uc" read "$RUN/log.raw" --text
	fi
}

node_env() { KR_XRAY="$(corebin 2>/dev/null)" KR_ASSET="$(assetdir)" "$@"; }

cmd_node() { # get|save|del|check-json
	local sub="$1" rc
	[ $# -gt 0 ] && shift
	case "$sub" in
		get) ucode "$SHARE/node.uc" get "$1" ;;
		check-json) ucode "$SHARE/node.uc" check-json "$1" ;;
		save|del)
			node_env ucode "$SHARE/node.uc" "$sub" "$@"
			rc=$?
			if [ $rc = 0 ] && [ "$(uget main.enabled)" = 1 ]; then
				apply_changes
			fi
			return $rc ;;
		*) echo "kullanım: kediray node get|save|del|check-json ..." >&2; return 1 ;;
	esac
}

cmd_node_enable() { # <sec> 0|1  — sunucuyu aç/kapat
	[ "$(uci -q get "$CONF.$1")" = node ] || { echo "böyle bir sunucu yok: $1" >&2; return 1; }
	case "$2" in 0|1) ;; *) echo "kullanım: kediray node-enable <sunucu> 0|1" >&2; return 1 ;; esac
	uci set "$CONF.$1.enabled=$2"
	uci commit "$CONF"
	[ "$(uget main.enabled)" = 1 ] && apply_changes
	echo "ok"
	return 0
}

cmd_validate() { # [--json]
	local r
	r=$(node_env ucode "$SHARE/node.uc" validate)
	if [ "$1" = "--json" ]; then echo "$r"; else
		echo "$r" | ucode -e 'let r = json(require("fs").stdin.read("all"));
			if (r.ok) { print("Yapılandırma hatasız.\n"); exit(0); }
			for (let e in r.errors) print("HATA [", e.stage, "] ", e.name ? e.name + ": " : "", e.field ? e.field + " — " : "",
				e.line ? "satır " + e.line + (e.col ? ", sütun " + e.col : "") + " — " : "", e.msg, "\n");
			exit(3);'
	fi
}

usage() {
	cat <<'EOF'
KediRay - OpenWrt Xray VPN yöneticisi

  kediray status            Durum (--json)
  kediray start|stop|restart
  kediray takeover [servis] Çalışan diğer VPN'den (ör. xwrt) KediRay'e güvenli geçiş;
                            internet gelmezse otomatik geri alır
  kediray direct [check]    Direkt (VPN'siz) çıkış var mı? Yoksa direkt giden her şey otomatik VPN'e alınır
  kediray rollback <servis> KediRay'i kapat, eski VPN'i geri aç
  kediray add <link|dosya>  vless/vmess/trojan/ss linki veya Xray JSON ekle (stdin de olur)
  kediray sub               Abonelikleri güncelle
  kediray use <id|auto>     Sunucu değiştir (bağlantıları koparmadan)
  kediray ping [id|all]     Sunucu gecikmesini ölç
  kediray best              En hızlı sunucuyu bul ve ona geç
  kediray auto on|off       Otomatik geçiş (açık: en hızlıya geç / kapalı: seçili sunucuda kal)
  kediray speedtest         Hız testi: direkt ve VPN (Mbps, gecikme, DNS süresi)
  kediray show-config       Üretilen tam Xray yapılandırmasını göster
  kediray app <ad> vpn|direct        Uygulama yönü (whatsapp, metin2, teams...)
  kediray device <mac> vpn|direct|block|default [ad]   (block = ağdan engelle)
  kediray conns [ip]        Aktif bağlantılar (oyun portu bulmak için)
  kediray watch <ip> [sn]   Bağlantı kaydı: hangi yoldan gitti, ne zaman koptu (kopma teşhisi)
  kediray hunt              Takılan adresleri defalarca çek: hangi aşamada takılıyor (DNS mi bağlantı mı)
  kediray dialtest          Sunucu el sıkışmayı kaç kez düşürüyor (IP IP ölçer; günlükteki EOF'un kaynağı)
  kediray doctor            Hangi DNS yolu çalışıyor / tünel sağlıklı mı (tek komutluk teşhis)
  kediray webtest           Sayfa açılma gecikmesi: DNS / bağlantı / TLS / ilk bayt (direkt ve VPN)
  kediray dnstest [ad...]   Metin2/Gameforge adlarını her DNS yolundan çöz (yanıt var mı, kaç ms)
  kediray version           Sürüm ve çekirdek bilgisi
  kediray check             Bağlantı teşhisi
  kediray band <scan|unlock|status|auto on|off>  Otomatik en iyi bant/frekans (isteğe bağlı)
  kediray band smart --bg --class NR_NSA --bands "78 1 3" [--wait 20] [--measure speed|signal] [--apply 1|0]
                            Akıllı band seçimi: bantları tek tek kilitle, hız+sinyal ölç, en iyisini seç (iptal: kediray band cancel)
  kediray validate          Yapılandırmayı denetle (yazım/alan hataları + Xray testi)
  kediray node get <id>     Sunucuyu düzenleme için göster
  kediray node save <id|new> form|json '<veri>' [ad]   Denetleyip kaydet (hatalıysa kaydetmez)
  kediray node del <id>     Sunucuyu sil
  kediray node-enable <id> 0|1       Sunucuyu aç/kapat
  kediray pin [id]          Sunucu sertifikasını şimdi elle sabitle (değiştiyse tüneli yeniden başlatır)
  kediray cert <id>         Sunucunun sunduğu sertifikayı göster (konu, veren, geçerlilik, SHA-256)
  kediray update-core [sürüm] | update-geo
  kediray import-xwrt       xDivine-Ray sunucularını aktar
  kediray log               Son kayıtlar
  kediray autodirect on|off          Direkt çıkış yokken "direkt" seçilenleri otomatik VPN'e çevir (on) ya da seçime hep uy (off)
  kediray engines                    VPN motorları ve durumları (JSON)
  kediray engine <ad> start|stop     Motoru başlat/durdur (aynı anda yalnızca biri çalışır)
  kediray app-add <ad> <vpn|direct> <portlar> <alan adları> <IP'ler>   Uygulama kuralı ekle
  kediray app-del <app>              Uygulama kuralını sil
  kediray selfupdate <dosya>         Kurulum dosyasıyla güncelle (panel: Hakkında > Güncelle)
  kediray update check [--json]      GitHub'da yeni sürüm var mı
  kediray update install             GitHub'dan indir (SHA256 doğrulamalı) ve kur
  kediray backup [dosya]             Sunucu ve ayarları yedekle (UUID içerir, paylaşma)
  kediray restore <dosya>            Yedeği geri yükle (önce denenir, bozuksa dokunmaz)
  kediray fixboot                    QModem açılış yavaşlığı yamasını uygula (otomatik de yapılır)
  kediray uninstall [--purge]
EOF
}

cmd="$1"; [ $# -gt 0 ] && shift
case "$cmd" in
	gen) cmd_gen ;;
	fw-up) with_lock fw_up_real ;;
	fw-down) with_lock fw_down_real ;;
	fw-zone) fw_zone ;;
	status) cmd_status "$@" ;;
	start|enable)
		cf=$(conflicts)
		if [ -n "$cf" ] && [ "$1" != "--force" ]; then
			echo "Şu an başka VPN çalışıyor: $cf" >&2
			echo "İkisi aynı anda trafiği yönetemez. Güvenli geçiş için: kediray takeover" >&2
			echo "(internet gelmezse otomatik geri alır; zorla başlatmak için: kediray start --force)" >&2
			exit 1
		fi
		uci set "$CONF.main.enabled=1"; uci commit "$CONF"
		/etc/init.d/kediray enable >/dev/null 2>&1; svc restart ;;
	stop|disable)
		uci set "$CONF.main.enabled=0"; uci commit "$CONF"
		svc stop ;;
	restart) svc restart ;;
	takeover) cmd_takeover "$@" ;;
	rollback) cmd_rollback "$@" ;;
	conflicts) conflicts ;;
	add) cmd_add "$@" ;;
	sub) cmd_sub ;;
	use) cmd_use "$@" ;;
	ping) cmd_ping "$@" ;;
	best) cmd_best ;;
	auto) cmd_auto "$@" ;;
	speedtest) cmd_speedtest "$@" ;;
	show-config) cat "$RUN/config.json" 2>/dev/null || { echo "Henüz yapılandırma üretilmedi (VPN hiç başlamadı)" >&2; exit 1; } ;;
	app) cmd_app "$@" ;;
	app-add) cmd_app_add "$@" ;;
	domain-find) cmd_domain_find "$@" ;;
	app-del) cmd_app_del "$@" ;;
	engines) cmd_engines ;;
	engine) cmd_engine "$@" ;;
	engine-bg) cmd_engine_bg "$@" ;;
	engine-log) cmd_engine_log ;;
	device) cmd_device "$@" ;;
	nodes) ucode "$SHARE/cli.uc" nodes ;;
	apps) ucode "$SHARE/cli.uc" apps ;;
	devices) ucode "$SHARE/cli.uc" devices ;;
	stats) cmd_stats ;;
	traffic) cmd_traffic "$@" ;;
	conns) cmd_conns "$@" ;;
	watch) cmd_watch "$@" ;;
	webtest) cmd_webtest "$@" ;;
	doctor) cmd_doctor "$@" ;;
	dnstest) cmd_dnstest "$@" ;;
	direct) cmd_direct "$@" ;;
	autodirect) cmd_autodirect "$@" ;;
	warp) cmd_warp "$@" ;;
	band) cmd_band "$@" ;;
	wan-ready) cmd_wan_ready ;;
	fixboot) cmd_fixboot "$@" ;;
	selfupdate) cmd_selfupdate "$@" ;;
	update) cmd_update "$@" ;;
	backup) cmd_backup "$@" ;;
	restore) cmd_restore "$@" ;;
	hunt) cmd_hunt "$@" ;;
	dialtest) cmd_dialtest "$@" ;;
	version|-V|--version) cmd_version "$@" ;;
	check) cmd_check ;;
	validate) cmd_validate "$@" ;;
	logs) cmd_logs "$@" ;;
	node) cmd_node "$@" ;;
	node-enable) cmd_node_enable "$@" ;;
	pin) mkdir -p "$RUN"; ucode "$SHARE/gen.uc" nodes > "$RUN/nodes.tsv" 2>/dev/null; cmd_pin "${1:-force}" ;;
	cert) cmd_cert "$@" ;;
	watchdog) cmd_watchdog ;;
	dns-guard) dns_guard ;;
	update-core) cmd_update_core "$@" ;;
	update-geo) cmd_update_geo ;;
	import-xwrt) cmd_import_xwrt ;;
	corebin) corebin ;;
	hevbin) hevbin ;;
	capture) capture_eff ;;
	assetdir) assetdir ;;
	log) logread -e kediray 2>/dev/null | tail -n "${1:-80}"; logread -e xray 2>/dev/null | tail -n 20 ;;
	uninstall) cmd_uninstall "$@" ;;
	""|help|-h|--help) usage ;;
	*) echo "Bilinmeyen komut: $cmd" >&2; usage; exit 1 ;;
esac
KEDIRAY_EOF_5
cat > '/usr/share/kediray/gen.uc' <<'KEDIRAY_EOF_6'
'use strict';
// KediRay yapılandırma üreticisi
// Kullanım: ucode gen.uc <xray|nft|dnsmasq|nodes|test|check> [config.json]
//           ucode gen.uc outbound <bölüm>          -> o sunucunun Xray outbound'u (+ test için mini config)
//           ucode gen.uc outbound-json '<json>'    -> kaydedilmemiş aday sunucunun outbound'u
// config.json verilmezse UCI 'kediray' okunur (test için KR_CFG ile JSON fikstürü de verilebilir).

const fs = require('fs');
const WHAT = ARGV[0] || 'xray';
const DATA_MODES = { 'outbound': 1, 'outbound-json': 1 };

function load() {
	let f = DATA_MODES[WHAT] ? getenv('KR_CFG') : (ARGV[1] || getenv('KR_CFG'));
	if (f)
		return json(fs.readfile(f));
	return require('uci').cursor().get_all('kediray');
}

let raw = load() || {};
if (raw.values) raw = raw.values;
const SECS = sort(values(raw), (a, b) => (a['.index'] ?? 0) - (b['.index'] ?? 0));
const M = raw.main || {};

function of(t) { return filter(SECS, s => s['.type'] == t); }
function opt(k, d) { let v = M[k]; return (v == null || v === '') ? d : v; }
function on(v, d) { if (v == null || v === '') return d; return (v == '1' || v == 'true' || v == 'on' || v == 'yes'); }
function num(v, d) { let n = int(v); return (v == null || v === '' || n != n) ? d : n; }
function die(msg, code) { warn('kediray: ' + msg + '\n'); exit(code ?? 1); }

// Liste değerlerini diziye çevir (UCI list veya boşlukla ayrılmış option)
function L(v, sep) {
	if (v == null) return [];
	if (type(v) != 'array') v = [v];
	let out = [];
	for (let x in v)
		for (let y in split(trim('' + x), sep ?? /\s+/))
			if (length(y)) push(out, y);
	return out;
}

function dom(d) {
	d = trim(d);
	if (!length(d)) return null;
	if (index(d, ':') >= 0) return d;
	d = replace(d, /^\*?\./, '');
	return 'domain:' + d;
}

function is_v4(x) { return !!match(x, /^[0-9]{1,3}(\.[0-9]{1,3}){3}(\/[0-9]{1,2})?$/); }

// Tek IP'yi (ya da /25-/32'yi) komşularıyla birlikte /24'e genişletir.
// Oyun sunucuları aynı /24'te sıralanır: ışınlanırken başka bir kanal sunucusuna bağlanınca da direkt kalır.
function ip24(x) {
	let p = split(x, '/');
	if (length(p) > 1 && int(p[1]) <= 24) return x;
	let o = split(p[0], '.');
	if (length(o) != 4) return x;
	return o[0] + '.' + o[1] + '.' + o[2] + '.0/24';
}
// Uygulamanın IP listesi; expand='24' ise tek IP'ler /24'e genişletilir
function app_ips(a) {
	let l = L(a.ip);
	return int(a.expand ?? 0) == 24 ? uniq(map(l, ip24)) : l;
}
function is_v6(x) { return !!match(x, /^[0-9a-fA-F:]+:[0-9a-fA-F:.]*(\/[0-9]{1,3})?$/); }
function ipn(x) {
	x = trim(x);
	if (!length(x)) return null;
	if (match(x, /^(geoip|ext):/)) return x;
	if (is_v4(x) || is_v6(x)) return x;
	return null;
}

// Port aralıklarını ayrıştır, sırala ve birleştir -> [[a,b],...]
function ranges(v) {
	let r = [];
	for (let p in L(v, /[ \t\r\n,]+/)) {
		let m = match(p, /^([0-9]+)(-([0-9]+))?$/);
		if (!m) continue;
		let a = int(m[1]), b = m[3] ? int(m[3]) : a;
		if (a > b) { let t = a; a = b; b = t; }
		if (a < 1 || b > 65535) continue;
		push(r, [a, b]);
	}
	r = sort(r, (x, y) => x[0] - y[0]);
	let out = [];
	for (let x in r) {
		let last = out[length(out) - 1];
		if (last && x[0] <= last[1] + 1) { if (x[1] > last[1]) last[1] = x[1]; }
		else push(out, [x[0], x[1]]);
	}
	return out;
}
function rstr(r, sep) { return join(sep ?? ',', map(r, x => x[0] == x[1] ? '' + x[0] : x[0] + '-' + x[1])); }

// ---------- Sunucular ----------
function split_hostport(o) {
	// JSON outbound içinden adres/port çıkar (görüntüleme ve DNS için)
	let s = o?.settings || {};
	let t = s.vnext?.[0] || s.servers?.[0] || s;
	return { address: t.address, port: t.port };
}

const UUID_RE = /^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$/;
const PROTOS = { vless: 1, vmess: 1, trojan: 1, shadowsocks: 1 };
const NETS = { tcp: 1, raw: 1, ws: 1, grpc: 1, xhttp: 1, httpupgrade: 1 };

// Bir sunucu bölümünü hazırla; sorunları 'errs' dizisine yaz. Kullanılamazsa null döner.
function prep_node(n, errs) {
	let name = n.remarks || n['.name'] || 'yeni sunucu';
	let e = (field, msg) => push(errs, { node: n['.name'], name: name, field: field, msg: msg });
	if (n.raw) {
		let o = null;
		try { o = json(n.raw); } catch (x) { o = null; }
		if (type(o) != 'object') { e('raw', 'JSON okunamadı (yazım hatası)'); return null; }
		if (!o.protocol) { e('raw', 'JSON içinde "protocol" alanı yok'); return null; }
		if (!PROTOS[o.protocol]) { e('raw', '"' + o.protocol + '" protokolü desteklenmiyor (vless, vmess, trojan, shadowsocks)'); return null; }
		let hp = split_hostport(o);
		if (!hp.address) { e('raw', 'JSON içinde sunucu adresi (settings…address) yok'); return null; }
		if (!hp.port) { e('raw', 'JSON içinde port (settings…port) yok'); return null; }
		n.address = hp.address;
		n.port = '' + hp.port;
		n.protocol = o.protocol;
		n._json = o;
		return n;
	}
	let ok = true;
	if (!PROTOS[n.protocol]) { e('protocol', 'protokol seçilmemiş ya da desteklenmiyor'); ok = false; }
	if (!n.address) { e('address', 'adres boş'); ok = false; }
	let p = int(n.port);
	if (!n.port || p != p || p < 1 || p > 65535) { e('port', 'port 1-65535 arasında olmalı'); ok = false; }
	if (n.protocol == 'vless' || n.protocol == 'vmess') {
		if (!n.uuid) { e('uuid', 'UUID boş'); ok = false; }
		else if (!match(n.uuid, UUID_RE) && length(n.uuid) > 30) { e('uuid', 'UUID biçimi hatalı (ör. b831381d-6324-4d53-ad4f-8cda48b30811)'); ok = false; }
	}
	if ((n.protocol == 'trojan' || n.protocol == 'shadowsocks') && !n.password) { e('password', 'parola boş'); ok = false; }
	if (n.protocol == 'shadowsocks' && !n.method) { e('method', 'şifreleme yöntemi seçilmemiş'); ok = false; }
	if (n.network && !NETS[n.network]) { e('network', '"' + n.network + '" aktarımı desteklenmiyor'); ok = false; }
	if (n.path && substr(n.path, 0, 1) != '/') { e('path', 'yol (path) "/" ile başlamalı'); ok = false; }
	if (n.tls == 'reality') {
		if (!n.pbk) { e('pbk', 'REALITY public key boş'); ok = false; }
		if (!n.sni) { e('sni', 'REALITY için SNI gerekli'); ok = false; }
	}
	if (n.flow && n.protocol != 'vless') { e('flow', 'flow sadece VLESS ile kullanılır'); ok = false; }
	if (n.flow && n.network && n.network != 'tcp' && n.network != 'raw') { e('flow', 'xtls-rprx-vision sadece TCP aktarımıyla çalışır'); ok = false; }
	return ok ? n : null;
}

let ERRS = [];
let NODES = [];
for (let n in of('node')) {
	if (n.enabled == '0') continue;
	let r = prep_node(n, ERRS);
	if (r) push(NODES, r);
	else warn('kediray: hatalı sunucu atlandı: ' + (n.remarks || n['.name']) + '\n');
}
for (let i = 0; i < length(NODES); i++) {
	NODES[i]._tag = sprintf('node-%03d', i + 1);
	NODES[i]._tport = num(getenv('KR_TEST_BASE') || opt('test_base', null), 21000) + i + 1;
}

const SEL_NAME = opt('node', 'auto');
const DISC = SEL_NAME == 'none';   // "Bağlantıyı kes": sunucu yok, trafik direkt
let SEL = null;
for (let n in NODES) if (n['.name'] == SEL_NAME) SEL = n;

// 1.19.4: WS heartbeat ve TCP keepalive varsayılan 30 sn. Boşta kalan WebSocket tüneli sunucu önündeki proxy/CDN (60-100 sn) ve
// mobil operatör NAT'ı tarafından sessizce kesilince sunucudan gelen bildirimler (WhatsApp vb.) telefona ulaşmıyordu.
const HB = num(opt('ws_heartbeat'), 30);
const KA = num(opt('tcp_keepalive'), 30);

// Yakalama modu (xDivine ile aynı adlar):
//   mixed   TCP çekirdekte NAT redirect ile (hızlı yol), UDP hev-socks5-tunnel TUN ile   [varsayılan]
//   tproxy  TCP+UDP TPROXY ile
//   redirect sadece TCP (UDP tünellenmez, QUIC reddedilir)
const CAPTURE = getenv('KR_CAPTURE') || opt('capture', 'mixed');
// Soket işaretleri: çekirdeğin kendi bağlantıları / TPROXY / TUN'a gidecek UDP
const MARK_CORE = hex(replace(getenv('KR_MARK_CORE') || '0x2e0', /^0x/, ''));
const MARK_TP = getenv('KR_MARK_TP') || '0x2e1';
const MARK_TUN = getenv('KR_MARK_TUN') || '0x2e2';
// Çekirdek allowInsecure destekliyor mu (kediray betiği test edip KR_CAP_INSECURE=1 verir; 26.x'te kaldırıldı)
const CAP_INSECURE = getenv('KR_CAP_INSECURE') == '1';

// Sunucuya IP ile bağlan: alan adı bir kez IP'ye çevrilir (KR_RESOLVE="alan=ip ..."),
// alan adı SNI/Host olarak kalır; böylece bağlantı DNS'e bağımlı olmaz.
const CONNECT_IP = on(opt('connect_ip'), true);
// Modeme operatörden gelen DNS sunucuları (CLI, KR_WAN_DNS ile geçirir)
const WAN_DNS = filter(L(getenv('KR_WAN_DNS')), is_v4);
// Direkt sorguların gideceği DNS: 'auto' -> operatör DNS'i (xDivine-Ray de böyle yapıyor).
// Ölçüldü: bazı hatlarda DoH adreslerine hiç ulaşılamıyor, her sorgu saniyelerce bekliyor.
function dns_direct_addr(o, i) {
	let v = opt(o, 'auto');
	if (v != 'auto' && v != '') return v;
	if (length(WAN_DNS) > i) return WAN_DNS[i];
	// Operatör DNS'i bilinmiyorsa DoH'a düş; yedek yuva her zaman farklı bir sağlayıcı olsun
	if (i == 0) return 'https+local://1.1.1.1/dns-query';
	return length(WAN_DNS) ? 'https+local://1.1.1.1/dns-query' : 'https+local://8.8.8.8/dns-query';
}
let RES = {};
for (let kv in L(getenv('KR_RESOLVE'))) {
	let i = index(kv, '=');
	if (i > 0) RES[substr(kv, 0, i)] = substr(kv, i + 1);
}
function by_ip(a) { return CONNECT_IP && a && RES[a] ? RES[a] : null; }

// Bağlantı varsayılanları xDivine-Ray'in (MIT, github.com/ozgunokan/xDivine-Ray) gerçek hatta ölçtüğü
// değerlere göre seçildi: TCP mux kapalı, UDP her zaman XUDP ile, QUIC tünelden, hedef IP korunur (routeOnly).

// WebSocket erken veri: varsayılan kapalı (bazı sunucu/CDN kurulumlarında sorun çıkarabiliyor).
const WS_EARLY = on(opt('ws_early'), false);
function ws_path(p) {
	p = p || '/';
	if (!WS_EARLY || match(p, /[?&]ed=/)) return p;
	return p + (index(p, '?') >= 0 ? '&' : '?') + 'ed=2048';
}
// Mux nesnesi iki ayrı şeyi taşır: TCP çoklama ve UDP'yi taşıyan XUDP.
//  - XUDP her zaman açık: onsuz bazı hedeflere UDP (oyun, arama, QUIC) tek yönlü kalıyor.
//  - xudpProxyUDP443 'allow': Xray'in varsayılanı QUIC'i sessizce atar, videolar takılır.
//  - TCP çoklama (concurrency > 0) varsayılan KAPALI (-1): hız düşürür; Vision ile hiç kullanılmaz.
const MUX = on(opt('mux'), false);
function mux_for(proto, flow, net) {
	return { enabled: true, concurrency: (MUX && !flow) ? 8 : -1, xudpConcurrency: 16, xudpProxyUDP443: 'allow' };
}

function sockopt(so) {
	so ??= {};
	so.mark ??= MARK_CORE;
	if (KA > 0) {
		so.tcpKeepAliveIdle ??= KA;
		so.tcpKeepAliveInterval ??= 15;
	}
	return so;
}

function stream(n) {
	let net = n.network || 'tcp';
	if (net == 'raw') net = 'tcp';
	let s = { network: net };
	let sec = n.tls || 'none';
	let host = n.host || '';
	// IP ile bağlanırken Host başlığı boş kalmasın: CDN/WS sunucusu alan adını görmeli
	if (!host && by_ip(n.address) && net != 'grpc') host = n.address;
	if (sec == 'tls') {
		s.security = 'tls';
		// fp boşsa telefondaki v2rayNG gibi Go varsayılan TLS kullanılır
		let t = { serverName: n.sni || host || n.address };
		if (n.fp && n.fp != 'none') t.fingerprint = n.fp;
		if (n.alpn) t.alpn = L(n.alpn, /[ \t\r\n,]+/);
		// xDivine gibi: sabitlenmiş sertifika varsa o; yoksa çekirdek destekliyorsa allowInsecure
		if (n.pin) t.pinnedPeerCertSha256 = n.pin;
		else if (n.insecure == '1' && CAP_INSECURE) t.allowInsecure = true;
		s.tlsSettings = t;
	}
	else if (sec == 'reality') {
		s.security = 'reality';
		s.realitySettings = {
			serverName: n.sni || n.host || '', fingerprint: n.fp || 'chrome',
			publicKey: n.pbk || '', shortId: n.sid || '', spiderX: n.spx || ''
		};
	}
	if (net == 'ws') {
		s.wsSettings = { path: ws_path(n.path) };
		if (host) { s.wsSettings.host = host; s.wsSettings.headers = { Host: host }; }
		if (HB > 0) s.wsSettings.heartbeatPeriod = HB;
	}
	else if (net == 'httpupgrade')
		s.httpupgradeSettings = { path: n.path || '/', host: host };
	else if (net == 'grpc') {
		s.grpcSettings = { serviceName: n.service_name || '', multiMode: (n.grpc_mode == 'multi') };
		if (by_ip(n.address)) s.grpcSettings.authority = n.host || n.address;
	}
	else if (net == 'xhttp') {
		s.xhttpSettings = { path: n.path || '/', host: host, mode: n.xhttp_mode || 'auto' };
	}
	else if (net == 'tcp' && n.header_type == 'http')
		s.tcpSettings = { header: { type: 'http', request: { path: [n.path || '/'], headers: { Host: L(host, /[ \t\r\n,]+/) } } } };
	s.sockopt = sockopt();
	return s;
}

function outbound(n) {
	let o;
	if (n._json) {
		o = n._json;
		o.tag = n._tag;
		o.streamSettings ??= {};
		let ss = o.streamSettings;
		ss.sockopt = sockopt(ss.sockopt);
		if (type(ss.tlsSettings) == 'object' && ss.tlsSettings.allowInsecure != null) {
			if (n.pin) { delete ss.tlsSettings.allowInsecure; ss.tlsSettings.pinnedPeerCertSha256 ??= n.pin; }
			else if (!CAP_INSECURE) delete ss.tlsSettings.allowInsecure;
		}
		if (ss.network == 'ws' || ss.network == 'websocket') {
			ss.wsSettings ??= {};
			if (HB > 0) ss.wsSettings.heartbeatPeriod ??= HB;
			ss.wsSettings.path = ws_path(ss.wsSettings.path);
		}
		// JSON'da TCP mux açıkça açılmamışsa XUDP'yi (UDP taşıma) ekle; açıksa kullanıcınınki kalır
		let uflow = o.settings?.vnext?.[0]?.users?.[0]?.flow;
		if (o.protocol == 'shadowsocks' && o.settings?.servers?.[0]) o.settings.servers[0].uot ??= true;
		if (!(o.mux?.enabled && (o.mux?.concurrency ?? 0) > 0)) {
			let m = mux_for(o.protocol, uflow, ss.network);
			if (m) o.mux = m;
		}
		// IP ile bağlan: adresi IP yap, alan adını SNI/Host olarak koru
		let st = o.settings || {}, tgt = st.vnext?.[0] || st.servers?.[0] || st;
		let ip = by_ip(tgt.address);
		if (ip) {
			let dom = tgt.address;
			tgt.address = ip;
			if (ss.security == 'tls') { ss.tlsSettings ??= {}; ss.tlsSettings.serverName ??= dom; }
			for (let k in ['wsSettings', 'httpupgradeSettings', 'xhttpSettings']) {
				let w = ss[k];
				if (type(w) == 'object' && !w.host) w.host = dom;
			}
			if (ss.network == 'ws' && !ss.wsSettings) ss.wsSettings = { host: dom };
			if (ss.network == 'grpc') { ss.grpcSettings ??= {}; ss.grpcSettings.authority ??= dom; }
		}
		return o;
	}
	let p = n.protocol, port = int(n.port);
	o = { tag: n._tag, protocol: p };
	if (p == 'vless') {
		let u = { id: n.uuid, encryption: n.encryption || 'none' };
		if (n.flow) u.flow = n.flow;
		o.settings = { vnext: [{ address: by_ip(n.address) || n.address, port: port, users: [u] }] };
	}
	else if (p == 'vmess')
		o.settings = { vnext: [{ address: by_ip(n.address) || n.address, port: port, users: [{ id: n.uuid, security: n.cipher || 'auto' }] }] };
	else if (p == 'trojan')
		o.settings = { servers: [{ address: by_ip(n.address) || n.address, port: port, password: n.password }] };
	else if (p == 'shadowsocks')
		o.settings = { servers: [{ address: by_ip(n.address) || n.address, port: port, method: n.method, password: n.password }] };
	else
		return null;
	o.streamSettings = stream(n);
	let m = mux_for(p, n.flow, n.network);
	if (m) o.mux = m;
	if (p == 'shadowsocks') o.settings.servers[0].uot = true;
	return o;
}

// ---------- Uygulamalar / kurallar ----------
// Direkt çıkış yoksa (KR_DIRECT_DEAD=1, kediray direct) "direkt" olan her şey VPN'e çevrilir
// Ham ölçüm: hat gerçekten direkt çıkamıyorsa. Otomatik çevirme kapalı olsa da bildirim düzeltmesi bu ölçüme bakar
// (direkt çıkış yokken FCM'i direkt göndermek bildirimleri tamamen keser).
const DIRECT_RAW_DEAD = getenv('KR_DIRECT_DEAD') == '1';
const DIRECT_DEAD = DIRECT_RAW_DEAD && opt('auto_direct', '1') != '0';
const APPS = map(filter(of('app'), a => a.enabled != '0'), a => (DIRECT_DEAD && a.route != 'warp') ? { ...a, route: 'vpn' } : a);
// Cloudflare WARP (WireGuard) çıkışı: 'warp' yönlü uygulamalar buradan çıkar. Anahtarlar `kediray warp register` ile alınır.
// warp_via=vpn: WARP, VPN sunucusunun içinden kurulur (operatör UDP'yi/WARP'ı görmez); direct: doğrudan hattan.
// TLS parçalama (SNI engeli aşma): 'frag' yönlü uygulamalar direkt çıkar ama TLS el sıkışması küçük parçalara bölünür.
const FRAG_ON = length(filter(APPS, a => a.route == 'frag')) > 0;
const WARP_ON = on(opt('warp'), false) && opt('warp_key', '') != '' && opt('warp_pub', '') != '' && opt('warp_v4', '') != '';
const RULES = map(filter(of('rule'), r => r.enabled != '0'), r => (DIRECT_DEAD && r.target == 'direct') ? { ...r, target: 'proxy' } : r);
// Bildirim (FCM/APNs) direkt istisnası: direkt çıkış yokken kapalı (yoksa bildirimler hiç gelmez)
const PUSH_FIX = on(opt('push_fix'), false) && !DIRECT_RAW_DEAD;
const PUSH_DOMAINS = [
	'domain:mtalk.google.com', 'regexp:^alt[0-9]*-mtalk\\.google\\.com$', 'domain:mtalk4.google.com',
	'domain:push.apple.com', 'domain:push-apple.com.akadns.net', 'domain:push.hicloud.com'
];
const PUSH_PORTS = '5223,5228-5230';
// Tarayıcıların kendi "Güvenli DNS"i (DoH): Chrome/Firefox sistem DNS'ini atlayıp doğrudan bu adreslere sorar.
// Bu hatta DoH adreslerine ulaşılamadığı ölçüldü -> tarayıcı her yeni ad için ~50 sn bekliyor, sayfa yarım kalıyor.
// Kapatınca (RST ile reddedince) tarayıcı anında sistem DNS'ine döner: KediRay'in DNS'i devreye girer.
const DOH_DOMAINS = [
	'domain:dns.google', 'domain:dns64.dns.google', 'domain:cloudflare-dns.com', 'domain:mozilla.cloudflare-dns.com',
	'domain:chrome.cloudflare-dns.com', 'domain:one.one.one.one', 'domain:security.cloudflare-dns.com',
	'domain:family.cloudflare-dns.com', 'domain:dns.quad9.net', 'domain:dns9.quad9.net', 'domain:dns11.quad9.net',
	'domain:doh.opendns.com', 'domain:doh.familyshield.opendns.com', 'domain:dns.nextdns.io', 'domain:doh.dns.sb',
	'domain:dns.adguard.com', 'domain:dns.adguard-dns.com', 'domain:doh.cleanbrowsing.org', 'domain:dns.alidns.com',
	'domain:doh.pub', 'domain:dns.controld.com', 'domain:freedns.controld.com', 'domain:dns.mullvad.net'
];
// Adresi elle yazan istemciler için IP listesi (yalnız 443/853: bu IP'lerin 53'ü DNS yönlendirmesiyle zaten ele alınır)
const DOH_IPS = ['1.1.1.1', '1.0.0.1', '8.8.8.8', '8.8.4.4', '9.9.9.9', '149.112.112.112',
	'208.67.222.222', '208.67.220.220', '94.140.14.14', '94.140.15.15', '45.90.28.0/24', '45.90.30.0/24'];
// 1.17.1: "Akıllı (Türkiye direkt)" modu kaldırıldı; 'rule' ayarı artık 'global' gibi çalışır (her şey VPN, yalnız seçilen uygulamalar direkt)
const MODE = (opt('mode', 'global') == 'list' && !DIRECT_DEAD) ? 'list' : 'global';
// Kullanıcının kendi seçtiği DNS IP'si DoH engelinin içine düşmesin (ör. dns_direct=1.1.1.1 düz DNS)
function rem_ip4() {
	let m = match(opt('dns_remote', 'https://1.1.1.1/dns-query'), /([0-9]{1,3}(\.[0-9]{1,3}){3})/);
	return m ? m[1] : '';
}
// DNS: varsayılan 'private' = dnsmasq -> çekirdeğin DNS portu -> tünel (xDivine-Ray'de seçili olan mod).
// Sorgu tünelin veri yoluna (TUN/TPROXY) girmez, çekirdek kendisi çözer -> hızlı ve sızıntısız.
// 'off' (DNS'e dokunma) TUN yakalamasında hiçbir adı çözemez (cihazın 53 portu TUN'a girer, yanıt dönmez):
// bu birleşimde sessizce 'private'a düşüyoruz.
const DNS_MODE = (opt('dns_mode', 'private') == 'off' && CAPTURE == 'tun') ? 'private' : opt('dns_mode', 'private');
// Uygulama bazlı "DNS'i tünelden çöz" (tunnel_dns=1): global DNS modu 'off' olsa bile yalnız bu uygulamaların
// alan adları dnsmasq -> çekirdek -> tünel yolundan çözülür; diğer her şey modemin kendi DNS'inde kalır.
let TDOMS = [];
for (let a in APPS) if (a.tunnel_dns == '1') for (let d in L(a.domain)) push(TDOMS, dom(d));
TDOMS = uniq(TDOMS);
const DNS_PART = (DNS_MODE == 'off' && length(TDOMS) > 0);
const DNS_ON = (DNS_MODE != 'off' || DNS_PART);

function tgt(t) {
	if (t == 'warp' && WARP_ON) return { outboundTag: 'warp' };
	if (t == 'frag') return { outboundTag: 'direct-frag' };
	if (t == 'proxy' || t == 'vpn' || t == 'warp') return { balancerTag: 'proxy' };
	if (t == 'block') return { outboundTag: 'block' };
	return { outboundTag: 'direct' };
}

function add_match(R, m, t) {
	let base = { ruleTag: m.tag };
	if (m.inbound) base.inboundTag = m.inbound;
	let d = filter(map(L(m.domain), dom), x => x);
	let ip = filter(map(L(m.ip), ipn), x => x);
	let pr = ranges(m.port ?? m.ports);
	// Yeni Xray sürümleri aynı ruleTag'in tekrarını reddeder ("duplicate ruleTag"): her kural benzersiz etiket alır.
	if (length(d)) push(R, { ...base, domain: d, ...tgt(t) });
	if (length(ip)) push(R, { ...base, ruleTag: m.tag + '-ip', ip: ip, ...tgt(t) });
	if (length(pr)) push(R, { ...base, ruleTag: m.tag + '-port', port: rstr(pr), network: 'tcp,udp', ...tgt(t) });
}

function xray() {
	if (!length(NODES))
		die('hiç sunucu yok; önce link, JSON veya abonelik ekleyin', 2);

	let tp_port = num(opt('tproxy_port'), 12345), dns_port = num(opt('dns_port'), 15353);
	let socks_port = num(opt('socks_port'), 10808), api_port = num(opt('api_port'), 10085);
	// xDivine'ın ölçümü: hedefi alan adıyla değiştirmek (sunucuya tekrar çözdürmek) her yeni bağlantıya
	// bir tur ekliyor (47 ms yerine 100 ms, ara ara 700 ms). routeOnly: alan adı sadece kurallar için okunur,
	// hedef IP korunur; adres zaten tünelden çözüldüğü için doğru bölgeden gelir.
	let sniff = {
		enabled: on(opt('sniff'), true), destOverride: ['http', 'tls', 'quic'],
		// sniff_mode=off: hiçbir durumda hedefi alan adıyla değiştirme (her bağlantıda sunucuya alan adı çözdürmez; hız testi/indirme daha çabuk açılır)
		routeOnly: opt('sniff_mode', 'auto') == 'off' || !(on(opt('sniff_override'), false) || length(filter(APPS, x => x.route == 'warp' || x.route == 'frag' || x.tunnel_dns == '1')) > 0)
	};

	// ÖLÇÜLDÜ (Xray 26.3.27): UDP girişinde içerik tanıma (sniffing) her UDP oturumuna SABİT ~200 ms ekliyor.
	// Çıplak Xray, ağ gecikmesi sıfır: sniffing kapalı 0 ms, açık 201 ms. TCP'de böyle bir bekleme yok
	// (TLS ClientHello ilk pakette gelir). DNS ve oyun/arama UDP'si bu yüzden geç açılıyordu.
	// TCP'de sniffing açık kalır (kural eşleştirme için gerekli), UDP girişlerinde kapatılır.
	// tun modunda TCP de socks-in'den geldiği için orada içerik tanıma gerekir (alan adı kuralları).
	// mixed/redirect/tproxy'de socks-in yalnız UDP taşır: kapalı kalır.
	const sniff_udp = (CAPTURE == 'tun');

	// Yakalama moduna göre LAN girişi
	let lan_in = { tag: 'lan-in', listen: '0.0.0.0', port: tp_port, protocol: 'dokodemo-door',
		settings: { network: 'tcp', followRedirect: true }, sniffing: sniff };
	// tproxy: TCP ve UDP ayrı girişlere ayrılır; UDP girişinde sniffing yok (200 ms bekleme yok)
	let lan_in_udp = null;
	if (CAPTURE == 'tproxy') {
		lan_in.streamSettings = { sockopt: { tproxy: 'tproxy' } };
		lan_in_udp = { tag: 'lan-in-udp', listen: '0.0.0.0', port: tp_port + 1, protocol: 'dokodemo-door',
			settings: { network: 'udp', followRedirect: true },
			streamSettings: { sockopt: { tproxy: 'tproxy' } } };
	}

	let inb = [
		lan_in,
		...(lan_in_udp ? [lan_in_udp] : []),
		// LAN'dan gelen DNS de buraya yönlendirilir (çekirdekte, tünele hiç girmeden): sniffing yok, hızlı.
		// WAN tarafı fw4'ün varsayılan kuralıyla kapalıdır. DNS modu 'off' iken bu giriş hiç açılmaz.
		...(!DNS_ON ? [] : [{ tag: 'dns-in', listen: '0.0.0.0', port: dns_port, protocol: 'dokodemo-door',
		  settings: { address: '1.1.1.1', port: 53, network: 'tcp,udp' } }]),
		// mixed modda hev-socks5-tunnel UDP'yi buraya getirir
		// mixed modda UDP'nin tamamı buradan geçer: sniffing KAPALI (yukarıdaki ölçüme bakın)
		{ tag: 'socks-in', listen: '127.0.0.1', port: socks_port, protocol: 'socks',
		  settings: { auth: 'noauth', udp: true, ip: '127.0.0.1' },
		  ...(sniff_udp ? { sniffing: sniff } : {}) },
		{ tag: 'api', listen: '127.0.0.1', port: api_port, protocol: 'dokodemo-door',
		  settings: { address: '127.0.0.1' } }
	];
	for (let n in NODES)
		push(inb, { tag: 't-' + n._tag, listen: '127.0.0.1', port: n._tport, protocol: 'socks', settings: { udp: false } });

	let outb = [
		{ tag: 'direct', protocol: 'freedom', settings: { domainStrategy: on(opt('ipv6'), false) ? 'UseIP' : 'UseIPv4' },
		  streamSettings: { sockopt: { mark: MARK_CORE } } },
		{ tag: 'block', protocol: 'blackhole' },
		{ tag: 'dns-out', protocol: 'dns', settings: { network: 'tcp', address: '1.1.1.1', port: 53 },
		  streamSettings: { sockopt: { mark: MARK_CORE } } }
	];
	for (let n in NODES) {
		let o = outbound(n);
		if (o) push(outb, o);
	}
	if (FRAG_ON) push(outb, { tag: 'direct-frag', protocol: 'freedom',
		settings: { domainStrategy: on(opt('ipv6'), false) ? 'UseIP' : 'UseIPv4',
			fragment: { packets: opt('frag_packets', 'tlshello'), length: opt('frag_length', '100-200'), interval: opt('frag_interval', '10-20') } },
		streamSettings: { sockopt: { mark: MARK_CORE } } });
	if (WARP_ON) {
		let res = map(split(opt('warp_reserved', '0,0,0'), ','), x => int(x));
		let via = (opt('warp_via', 'vpn') == 'vpn');
		let vtag = (SEL ? SEL._tag : NODES[0]._tag);
		push(outb, { tag: 'warp', protocol: 'wireguard',
			settings: {
				secretKey: opt('warp_key'),
				address: filter([opt('warp_v4') + '/32', opt('warp_v6', '') != '' ? opt('warp_v6') + '/128' : null], x => x),
				peers: [{ publicKey: opt('warp_pub'), allowedIPs: ['0.0.0.0/0', '::/0'], endpoint: opt('warp_endpoint', 'engage.cloudflareclient.com:2408') }],
				mtu: num(opt('warp_mtu'), 1280),
				reserved: length(res) == 3 ? res : [0, 0, 0],
				domainStrategy: 'ForceIPv4'
			},
			streamSettings: { sockopt: via ? { dialerProxy: vtag } : { mark: MARK_CORE } } });
	}

	// --- Yönlendirme kuralları (ilk eşleşen kazanır) ---
	let R = [];
	push(R, { inboundTag: ['api'], outboundTag: 'api' });
	if (DNS_ON) push(R, { inboundTag: ['dns-in'], outboundTag: 'dns-out' });
	// İstemcinin kendi seçtiği DNS (8.8.8.8 vb.) de KediRay DNS'inden yanıtlanır (sızıntı yok)
	// off modunda 53 numaralı port normal trafik gibi yönlendirilir (modemin kendi DNS'i devrede kalır)
	if (DNS_MODE != 'off') push(R, { inboundTag: ['lan-in', 'lan-in-udp', 'socks-in'], port: '53', outboundTag: 'dns-out' });
	for (let n in NODES)
		push(R, { inboundTag: ['t-' + n._tag], outboundTag: n._tag });
	// Operatör DNS'ine (ve genel olarak düz IP yazılmış direkt DNS'e) giden sorgular tünelden GEÇMEZ:
	// aksi halde tünel takıldığında alan adı çözülemez ve tarayıcı 50 sn döner.
	// Uzak DNS ile aynı IP varsa dışarıda bırakılır: yoksa tünelden gitmesi gereken sorgu direkt çıkar (sızıntı).
	let rem = opt('dns_remote', 'https://1.1.1.1/dns-query');
	let rem_ip = match(rem, /([0-9]{1,3}(\.[0-9]{1,3}){3})/);
	rem_ip = rem_ip ? rem_ip[1] : '';
	let dns_direct_ips = filter([...WAN_DNS, dns_direct_addr('dns_direct', 0), dns_direct_addr('dns_direct2', 1)],
		x => is_v4(x) && x != rem_ip);
	if (DNS_ON) {
		if (length(dns_direct_ips))
			push(R, { ruleTag: 'dns-local', inboundTag: ['dns-internal'], ip: uniq(dns_direct_ips), outboundTag: 'direct' });
		push(R, { inboundTag: ['dns-internal'], balancerTag: 'proxy' });
	}

	// Tarayıcının kendi DoH'u: engelle -> tarayıcı anında sistem DNS'ine düşer (50 sn'lik askıda kalma biter).
	// Kural DNS kurallarından SONRA: KediRay'in kendi DoH sorguları (dns-internal) yukarıda çözülmüş olur.
	if (on(opt('block_doh'), true))
		push(R, { ruleTag: 'doh-block', inboundTag: ['lan-in', 'lan-in-udp', 'socks-in'],
			domain: DOH_DOMAINS, port: '443,853', outboundTag: 'block' });

	// Uygulamalar (VPN / Direkt kullanıcı seçimi) - en yüksek öncelik
	for (let a in APPS)
		add_match(R, { domain: a.domain, ip: app_ips(a), port: a.ports, tag: 'app-' + a['.name'] }, a.route == 'vpn' ? 'proxy' : a.route == 'warp' ? 'warp' : a.route == 'frag' ? 'frag' : 'direct');

	// Bildirim (FCM / APNs) direkt
	if (PUSH_FIX)
		add_match(R, { domain: PUSH_DOMAINS, port: PUSH_PORTS, tag: 'push' }, 'direct');

	if (on(opt('ad_block'), false))
		push(R, { ruleTag: 'ads', domain: ['geosite:category-ads-all'], outboundTag: 'block' });

	for (let r in RULES)
		add_match(R, { domain: r.domain, ip: r.ip, port: r.port, tag: 'rule-' + r['.name'] }, r.target || 'proxy');

	push(R, { ruleTag: 'private', ip: ['geoip:private'], outboundTag: 'direct' });
	push(R, { ruleTag: 'final', network: 'tcp,udp', ...tgt(MODE == 'list' ? 'direct' : 'proxy') });

	// --- DNS ---
	// Gerçek hatta ölçüldü: tünelden DNS-over-TCP kullanılırken sunucu bir bağlantıyı düşürünce
	// ("failed to read response length -> read/write on closed pipe") sorgu ölüyor ve sayfa askıda kalıyor.
	// DoH (HTTP/2) aynı durumda kendi içinde yeniden deniyor. Kurulumla gelen varsayılan Google TCP'dir (uyumluluk); bu belirti görülürse DoH seçilir.
	let remote = opt('dns_remote', 'https://1.1.1.1/dns-query');
	if (match(remote, /^[0-9.]+$/)) remote = 'tcp://' + remote;
	let direct = dns_direct_addr('dns_direct', 0);
	// Direkt sorgular için yedek: ilk DoH takılırsa (5G hatlarında sık) sorgu saniyelerce beklemez
	let direct2 = dns_direct_addr('dns_direct2', 1);
	if (direct2 == direct) direct2 = '';
	let ddom = [], pdom = [];
	for (let a in APPS) for (let d in L(a.domain)) push((a.route == 'direct' || a.route == 'frag') ? ddom : pdom, dom(d));
	if (PUSH_FIX) for (let d in PUSH_DOMAINS) push(ddom, d);
	for (let r in RULES) {
		if (r.target == 'block') continue;
		for (let d in L(r.domain)) push(r.target == 'direct' ? ddom : pdom, dom(d));
	}
	let servers = [];
	if (length(TDOMS)) push(servers, { address: remote, domains: TDOMS, skipFallback: true });
	pdom = filter(uniq(pdom), x => index(TDOMS, x) < 0);
	if (length(pdom) && DNS_MODE != 'fast') push(servers, { address: remote, domains: pdom, skipFallback: true });
	if (length(ddom)) {
		push(servers, { address: direct, domains: uniq(ddom), skipFallback: true });
		if (length(direct2)) push(servers, { address: direct2, domains: uniq(ddom), skipFallback: true });
	}
	// dns_mode=private (varsayılan, xDivine-Ray'de seçili olan): listede olmayan adlar tünelden çözülür
	//   (hiçbir sorgu operatöre sızmaz; çekirdek kendi çözdüğü için sorgu TUN/TPROXY yoluna girmez).
	// dns_mode=fast: varsayılan sorgular direkt çıkar (tünel koparsa da ad çözülür, karşılığında gizlilik azalır).
	if (MODE == 'list' || DNS_MODE == 'fast') { push(servers, direct); if (length(direct2)) push(servers, direct2); push(servers, remote); }
	else { push(servers, remote); push(servers, direct); if (length(direct2)) push(servers, direct2); }

	let fb = SEL ? SEL._tag : NODES[0]._tag;
	// connIdle 4 saat (xDivine): telefonun bildirim bağlantısı saatlerce veri taşımadan açık durur
	let pol = { connIdle: num(opt('conn_idle'), 14400) };
	// Hız ayarı: bağlantı başına tampon (KB). Küçük tampon yüksek hızda akışı boğar ve hız testinin yükselmesini geciktirir.
	if (on(opt('speed_tune'), true)) pol.bufferSize = num(opt('buffer_size'), 1024);
	let cfg = {
		log: { loglevel: opt('log_level', 'warning'), access: (opt('log_level', 'warning') == 'info' || opt('log_level') == 'debug') ? '' : 'none' },
		api: { tag: 'api', services: ['RoutingService', 'StatsService'] },
		stats: {},
		policy: {
			// v2rayNG JSON'ları kullanıcı seviyesi 8 kullanır: ikisine de aynı uzun bağlantı süresi
			levels: { '0': pol, '8': pol },
			system: { statsOutboundUplink: true, statsOutboundDownlink: true }
		},
		// DNS modu 'off': yönlendiricinin kendi DNS'ine hiç dokunulmaz (xDivine-Ray'in "DNS'e dokunma" seçeneği).
		// Alan adı kuralları yine çalışır: bağlantıdaki SNI okunur (sniffing/routeOnly).
		...(!DNS_ON ? {} : { dns: {
			tag: 'dns-internal',
			queryStrategy: on(opt('ipv6'), false) ? 'UseIP' : 'UseIPv4',
			// Tünel anlık takılırsa (mobil hatta bağlantı sıfırlanması vb.) bilinen adresi beklemeden ver, arkada yenile:
			// uygulama/oyun "DNS zaman aşımı" yüzünden bağlantı kuramama yaşamaz.
			// Süre kısa tutulur: CDN adresleri sık değişir, bir gün önceki adres ölü olabilir ve
			// tarayıcı o adrese bağlanmaya çalışırken sayfa "yükleniyor" kalır (yuvarlak döner).
			serveStale: on(opt('dns_stale'), true),
			serveExpiredTTL: num(opt('dns_stale_ttl'), 600),
			servers: servers
		} }),
		inbounds: inb,
		outbounds: outb,
		observatory: {
			subjectSelector: ['node-'],
			probeUrl: opt('probe_url', 'https://www.gstatic.com/generate_204'),
			probeInterval: opt('probe_interval', '2m'),
			enableConcurrency: true
		},
		routing: {
			domainStrategy: 'AsIs',
			balancers: [{ tag: 'proxy', selector: DISC ? ['__yok__'] : ['node-'], strategy: { type: 'leastPing' }, fallbackTag: DISC ? 'direct' : fb }],
			rules: R
		}
	};
	print(sprintf('%.J\n', cfg));
}

// ---------- nftables ----------
const BYPASS4 = [
	'0.0.0.0/8', '10.0.0.0/8', '100.64.0.0/10', '127.0.0.0/8', '169.254.0.0/16',
	'172.16.0.0/12', '192.0.0.0/24', '192.168.0.0/16', '224.0.0.0/4', '240.0.0.0/4'
];

function nft() {
	let ifs = L(getenv('KR_LAN_IFS') || 'br-lan');
	let tp_port = num(opt('tproxy_port'), 12345);
	let bypass = [...BYPASS4, ...filter(L(getenv('KR_SERVER_IPS')), is_v4)];
	let dips = [], dports = [];
	for (let a in APPS) {
		if (a.route == 'vpn' || a.route == 'warp' || a.route == 'frag') continue;
		for (let x in app_ips(a)) if (is_v4(x)) push(dips, x);
		for (let r in ranges(a.ports)) push(dports, r);
	}
	for (let r in RULES) {
		if (r.target != 'direct') continue;
		for (let x in L(r.ip)) if (is_v4(x)) push(dips, x);
		for (let p in ranges(r.port)) push(dports, p);
	}
	dports = ranges(rstr(dports));

	let dev = { vpn: { mac: [], ip: [] }, direct: { mac: [], ip: [] }, block: { mac: [], ip: [] } };
	for (let d in of('device')) {
		let m = d.mode;
		if (m != 'vpn' && m != 'direct' && m != 'block') continue;
		if (DIRECT_DEAD && m == 'direct') m = 'vpn';
		if (d.mac && match(d.mac, /^([0-9A-Fa-f]{2}:){5}[0-9A-Fa-f]{2}$/)) push(dev[m].mac, lc(d.mac));
		for (let x in L(d.ip)) if (is_v4(x)) push(dev[m].ip, x);
	}
	let defdev = DIRECT_DEAD ? 'vpn' : opt('default_device', 'vpn');
	let q = x => '"' + x + '"';
	let lanset = '{ ' + join(', ', map(ifs, q)) + ' }';

	let o = [];
	let set = (name, typ, els, iv) => {
		push(o, '\tset ' + name + ' {');
		push(o, '\t\ttype ' + typ + ';' + (iv ? ' flags interval; auto-merge;' : ''));
		if (length(els)) push(o, '\t\telements = { ' + join(', ', uniq(els)) + ' }');
		push(o, '\t}');
	};
	// Ortak eleme: LAN dışı, yerel/özel hedefler, sunucu IP'leri, Direkt uygulamalar (Metin2/Teams IP ve portları),
	// bildirim portları; ardından cihaz kuralı ve eylem zinciri.
	let guards = (act, protos) => {
		push(o, '\t\tmeta nfproto != ipv4 return');
		push(o, '\t\tiifname != ' + lanset + ' return');
		push(o, '\t\tmeta l4proto != ' + protos + ' return');
		push(o, '\t\tfib daddr type { local, broadcast, multicast } return');
		// Ağdan engellenen cihaz: yakalanmaz (yakalansa yönlendirme forward zincirini atlar ve engel işlemez)
		if (length(dev.block.mac)) push(o, '\t\tether saddr @dev_block return');
		if (length(dev.block.ip)) push(o, '\t\tip saddr @devip_block return');
		push(o, '\t\tip daddr @bypass4 return');
		push(o, '\t\tip daddr @direct4 return');
		if (length(dports))
			push(o, '\t\tmeta l4proto { tcp, udp } th dport { ' + rstr(dports, ', ') + ' } return');
		if (PUSH_FIX)
			push(o, '\t\ttcp dport { 5223, 5228-5230 } return');
		if (defdev == 'direct') {
			push(o, '\t\tether saddr @dev_vpn jump ' + act);
			push(o, '\t\tip saddr @devip_vpn jump ' + act);
		} else {
			push(o, '\t\tether saddr @dev_direct return');
			push(o, '\t\tip saddr @devip_direct return');
			push(o, '\t\tjump ' + act);
		}
	};

	push(o, 'table inet kediray');
	push(o, 'delete table inet kediray');
	push(o, 'table inet kediray {');
	set('bypass4', 'ipv4_addr', bypass, true);
	set('direct4', 'ipv4_addr', dips, true);
	set('dev_vpn', 'ether_addr', dev.vpn.mac, false);
	set('dev_direct', 'ether_addr', dev.direct.mac, false);
	set('devip_vpn', 'ipv4_addr', dev.vpn.ip, true);
	set('devip_direct', 'ipv4_addr', dev.direct.ip, true);
	// Tarayıcıların kendi DoH sunucuları (443/853 reddedilir; 53 zaten DNS yönlendirmesine takılır)
	set('doh4', 'ipv4_addr', on(opt('block_doh'), true) ? filter(DOH_IPS, x => x != rem_ip4()) : [], true);
	set('dev_block', 'ether_addr', dev.block.mac, false);
	set('devip_block', 'ipv4_addr', dev.block.ip, true);
	// Trafik sayacı: tünelin dış baytları (modemin kendi bağlantısı; donanım hızlandırmaya girmez, kesin sayılır)
	set('srv4', 'ipv4_addr', filter(L(getenv('KR_SERVER_IPS')), is_v4), true);
	push(o, '\tcounter vpn_rx { }');
	push(o, '\tcounter vpn_tx { }');
	push(o, '\tchain acct_in {');
	push(o, '\t\ttype filter hook input priority filter - 5; policy accept;');
	push(o, '\t\tip saddr @srv4 counter name "vpn_rx"');
	push(o, '\t}');
	push(o, '\tchain acct_out {');
	push(o, '\t\ttype filter hook output priority filter - 5; policy accept;');
	push(o, '\t\tip daddr @srv4 counter name "vpn_tx"');
	push(o, '\t}');

	if (CAPTURE == 'tun') {
		// Her şey (TCP+UDP) işaretlenir; ip rule işaretli paketi TUN'a (hev-socks5-tunnel) yollar.
		// xDivine-Ray'in "tun" modunun karşılığı: çekirdekte NAT yok, tüm oturum hev'in kendi TCP yığınında.
		push(o, '\tchain tun_pre {');
		push(o, '\t\ttype filter hook prerouting priority mangle; policy accept;');
		guards('tun_act', '{ tcp, udp }');
		push(o, '\t}');
		push(o, '\tchain tun_act {');
		if (on(opt('dns_hijack'), true) && DNS_MODE != 'off') push(o, '\t\tmeta l4proto { tcp, udp } th dport 53 return');
		if (on(opt('block_quic'), true)) push(o, '\t\tudp dport 443 return');
		push(o, '\t\tmeta mark set ' + MARK_TUN + ' ct mark set ' + MARK_TUN);
		push(o, '\t}');
	} else if (CAPTURE == 'tproxy') {
		push(o, '\tchain prerouting {');
		push(o, '\t\ttype filter hook prerouting priority mangle; policy accept;');
		guards('tp', '{ tcp, udp }');
		push(o, '\t}');
		push(o, '\tchain tp {');
		if (on(opt('dns_hijack'), true)) push(o, '\t\tmeta l4proto { tcp, udp } th dport 53 return');
		if (on(opt('block_quic'), true)) push(o, '\t\tudp dport 443 return');
		push(o, '\t\tmeta l4proto { tcp, udp } socket transparent 1 meta mark set ' + MARK_TP + ' accept');
		// TCP ve UDP ayrı portlara: UDP girişinde sniffing kapalı (her UDP oturumuna ~200 ms ekliyordu)
		push(o, '\t\tmeta l4proto tcp meta mark set ' + MARK_TP + ' tproxy ip to :' + tp_port + ' accept');
		push(o, '\t\tmeta l4proto udp meta mark set ' + MARK_TP + ' tproxy ip to :' + (tp_port + 1) + ' accept');
		push(o, '\t}');
	} else {
		// TCP: çekirdekte NAT redirect (xDivine'ın hızlı yolu). fw4'ün dstnat'ından (-100) önce.
		push(o, '\tchain nat_pre {');
		push(o, '\t\ttype nat hook prerouting priority dstnat - 5; policy accept;');
		guards('nat_act', 'tcp');
		push(o, '\t}');
		push(o, '\tchain nat_act {');
		push(o, '\t\tmeta l4proto tcp redirect to :' + tp_port);
		push(o, '\t}');
		if (CAPTURE == 'mixed') {
			// UDP: sadece işaretlenir; ip rule işaretli paketi TUN (hev-socks5-tunnel) tablosuna gönderir
			push(o, '\tchain udp_pre {');
			push(o, '\t\ttype filter hook prerouting priority mangle; policy accept;');
			guards('udp_act', 'udp');
			push(o, '\t}');
			push(o, '\tchain udp_act {');
			if (on(opt('dns_hijack'), true) && DNS_MODE != 'off') push(o, '\t\tudp dport 53 return');
			if (on(opt('block_quic'), true)) push(o, '\t\tudp dport 443 return');
			push(o, '\t\tmeta mark set ' + MARK_TUN + ' ct mark set ' + MARK_TUN);
			push(o, '\t}');
		}
	}

	// DNS (53): cihaz hangi DNS'i yazarsa yazsın çekirdekte KediRay DNS'ine gider.
	// Böylece sorgu TUN/hev yoluna hiç girmez (ölçüm: o yol UDP başına ~200 ms ekliyor) ve
	// Xray'in DNS önbelleği devreye girer. Kural tünelden geçen cihazlar için geçerli (Direkt cihaz kendi DNS'ini kullanır).
	if (on(opt('dns_hijack'), true) && DNS_MODE != 'off') {
		push(o, '\tchain dns_nat {');
		push(o, '\t\ttype nat hook prerouting priority dstnat - 6; policy accept;');
		guards('dns_act', '{ tcp, udp }');
		push(o, '\t}');
		push(o, '\tchain dns_act {');
		push(o, '\t\tmeta l4proto { tcp, udp } th dport 53 redirect to :' + num(opt('dns_port'), 15353));
		push(o, '\t}');
	}

	// QUIC (UDP 443): tünelde (UDP-over-TCP) tarayıcıyı takılı bırakabiliyor — ör. Google giriş sayfası dönüp duruyor.
	// v2rayNG ve Xray'in kendi varsayılanı gibi reddedilir; ICMP yanıtı anında gider, tarayıcı beklemeden TCP'ye (tünele) geçer.
	if (on(opt('block_quic'), true)) {
		push(o, '\tchain quic_fwd {');
		push(o, '\t\ttype filter hook forward priority filter - 5; policy accept;');
		guards('quic_act', 'udp');
		push(o, '\t}');
		push(o, '\tchain quic_act {');
		push(o, '\t\tudp dport 443 reject with icmpx type port-unreachable');
		push(o, '\t}');
	}

	// Tarayıcının kendi DoH'u, adresi elle yazılmışsa (IP ile): 443/853 anında reddedilir.
	// Alan adıyla gidenler Xray tarafında engellenir; ikisi birlikte tarayıcıyı sistem DNS'ine döndürür.
	if (on(opt('block_doh'), true)) {
		push(o, '\tchain doh_fwd {');
		push(o, '\t\ttype filter hook forward priority filter - 6; policy accept;');
		push(o, '\t\tmeta nfproto != ipv4 return');
		push(o, '\t\tiifname != ' + lanset + ' return');
		push(o, '\t\tip daddr @doh4 meta l4proto { tcp, udp } th dport { 443, 853 } reject with icmpx type port-unreachable');
		push(o, '\t}');
	}

	// Ağdan engellenen cihazlar: internet yok (yerel ağ ve DHCP çalışmaya devam eder)
	if (length(dev.block.mac) || length(dev.block.ip)) {
		push(o, '\tchain block_fwd {');
		push(o, '\t\ttype filter hook forward priority filter - 10; policy accept;');
		push(o, '\t\tiifname != ' + lanset + ' return');
		if (length(dev.block.mac)) push(o, '\t\tether saddr @dev_block reject with icmpx type admin-prohibited');
		if (length(dev.block.ip)) push(o, '\t\tip saddr @devip_block reject with icmpx type admin-prohibited');
		push(o, '\t}');
		// modemin kendi DNS'i de cevap vermesin: sayfa beklemeden "bağlanılamadı" desin
		push(o, '\tchain block_in {');
		push(o, '\t\ttype filter hook input priority filter - 10; policy accept;');
		push(o, '\t\tiifname != ' + lanset + ' return');
		push(o, '\t\tmeta l4proto { tcp, udp } th dport != 53 return');
		if (length(dev.block.mac)) push(o, '\t\tether saddr @dev_block reject');
		if (length(dev.block.ip)) push(o, '\t\tip saddr @devip_block reject');
		push(o, '\t}');
	}

	// IPv6 sızıntı koruması: VPN cihazlarının IPv6 ile tüneli atlamasını engelle
	if (!on(opt('ipv6'), false) && on(opt('v6_block'), true)) {
		push(o, '\tchain forward6 {');
		push(o, '\t\ttype filter hook forward priority filter - 1; policy accept;');
		push(o, '\t\tmeta nfproto != ipv6 return');
		push(o, '\t\tiifname != ' + lanset + ' return');
		push(o, '\t\tip6 daddr { fc00::/7, fe80::/10, ff00::/8 } return');
		if (length(dev.block.mac)) push(o, '\t\tether saddr @dev_block reject with icmpv6 type admin-prohibited');
		if (defdev == 'direct')
			push(o, '\t\tether saddr @dev_vpn reject with icmpv6 type admin-prohibited');
		else {
			push(o, '\t\tether saddr @dev_direct return');
			push(o, '\t\treject with icmpv6 type admin-prohibited');
		}
		push(o, '\t}');
	}
	push(o, '}');
	print(join('\n', o), '\n');
}

// ---------- hev-socks5-tunnel (mixed modda UDP) ----------
// Geliştiricinin bulduğu bildirim hatasının düzeltmesi: hev'in kendi zaman aşımları TCP 5 dk / UDP 1 dk.
// Ayarlanmazsa telefonun bildirim bağlantısı 5 dakikada kapanır, bildirimler toplu ve geç gelir.
// Burada boşta kalma süresi (conn_idle) hev'e de yazılır; UDP en fazla 10 dk (bellek için).
function hev() {
	let idle = num(opt('conn_idle'), 14400);
	if (idle > 86400) idle = 86400;
	let udp = idle > 600 ? 600 : idle;
	let o = [
		'tunnel:',
		'  name: ' + (getenv('KR_TUN') || 'kediray0'),
		'  mtu: ' + (num(opt('tun_mtu'), 8500) < 576 ? 576 : (num(opt('tun_mtu'), 8500) > 9000 ? 9000 : num(opt('tun_mtu'), 8500))),
		'  multi-queue: false',
		'  ipv4: ' + (getenv('KR_TUN_ADDR') || '198.19.0.1'),
		'',
		'socks5:',
		'  port: ' + num(opt('socks_port'), 10808),
		'  address: 127.0.0.1',
		"  udp: 'udp'",
		'  pipeline: false',
		'',
		'misc:',
		'  task-stack-size: 86016'
	];
	if (idle > 0) {
		if (getenv('KR_HEV_KEYS') == 'single')
			push(o, '  read-write-timeout: ' + idle * 1000);
		else {
			push(o, '  tcp-read-write-timeout: ' + idle * 1000);
			push(o, '  udp-read-write-timeout: ' + udp * 1000);
		}
	}
	push(o, '  log-file: stderr');
	push(o, '  log-level: ' + ({ debug: 'debug', info: 'info', error: 'error', none: 'error' }[opt('log_level', 'warning')] ?? 'warn'));
	push(o, '  limit-nofile: 65535');
	print(join('\n', o), '\n');
}

// ---------- dnsmasq ----------
function dnsmasq() {
	// 'off': yönlendiricinin DNS'ine dokunma (xDivine-Ray'deki gibi)
	if (DNS_MODE == 'off' && !DNS_PART) { print(''); return; }
	if (DNS_PART) {
		// Kısmi mod: modemin kendi DNS'i aynen kalır (no-resolv YOK); yalnız listedeki alan adları çekirdeğe gider
		let q = ['# KediRay - otomatik üretildi (yalnız uygulama bazlı DNS)'];
		for (let d in TDOMS) {
			let b = replace(replace(d, /^(domain|full):/, ''), /^[a-z]+:.*$/, '');
			if (b != '' && match(b, /^[A-Za-z0-9._-]+$/)) push(q, 'server=/' + b + '/127.0.0.1#' + num(opt('dns_port'), 15353));
		}
		print(join('\n', q), '\n');
		return;
	}
	// Önyükleme adresleri (sunucu alan adı, saat sunucusu, güncelleme adresleri) tünel kurulmadan çözülmeli.
	// Ölçüldü: bu hatta 1.1.1.1:53'e ulaşılamıyor -> sabit 1.1.1.1 yazarsak bu adlar HİÇ çözülmüyor
	// (ör. gstatic.com). Operatörün kendi DNS'i her zaman ayakta, o yüzden önce o kullanılır.
	let doms = [];
	for (let n in NODES) if (!is_v4(n.address) && !is_v6(n.address)) push(doms, n.address);
	for (let u in L(M.sub_url)) {
		let m = match(u, /^https?:\/\/([^\/:?#]+)/);
		if (m && !is_v4(m[1])) push(doms, m[1]);
	}
	for (let d in ['pool.ntp.org', 'time.google.com', 'time.cloudflare.com', 'openwrt.org', 'github.com', 'githubusercontent.com', 'gstatic.com'])
		push(doms, d);
	for (let d in L(getenv('KR_EXTRA_DIRECT'))) push(doms, d);
	let boots = length(WAN_DNS) ? WAN_DNS : [opt('dns_bootstrap', '1.1.1.1')];
	let o = ['# KediRay - otomatik üretildi', 'no-resolv', 'server=127.0.0.1#' + num(opt('dns_port'), 15353)];
	for (let d in uniq(doms)) for (let b in boots) push(o, 'server=/' + d + '/' + b);
	if (!on(opt('ipv6'), false)) push(o, 'filter-AAAA');
	print(join('\n', o), '\n');
}

// ---------- düğüm listesi (CLI/panel için) ----------
function nodes() {
	for (let n in NODES) {
		let j = n._json, ts = j?.streamSettings?.tlsSettings;
		let insecure = (n.insecure == '1' || ts?.allowInsecure === true) ? 1 : 0;
		let sni = n.sni || n.host || ts?.serverName || n.address;
		let net = n.network || (j?.streamSettings?.network ?? 'tcp');
		print(join('\t', [n._tag, n['.name'], n._tport, n.address, n.port, n.protocol, net, insecure, sni,
			n.pin || '-', replace(n.remarks || (n.address + ':' + n.port), /[\t\n]/g, ' ')]), '\n');
	}
}

// ---------- VPN kapalıyken ping için geçici test çekirdeği ----------
function testcfg() {
	if (!length(NODES)) die('hiç geçerli sunucu yok', 2);
	let inb = [], outb = [{ tag: 'direct', protocol: 'freedom' }], R = [];
	for (let n in NODES) {
		let o = outbound(n);
		if (!o) continue;
		push(outb, o);
		push(inb, { tag: 't-' + n._tag, listen: '127.0.0.1', port: n._tport, protocol: 'socks', settings: { udp: false } });
		push(R, { inboundTag: ['t-' + n._tag], outboundTag: n._tag });
	}
	print(sprintf('%.J\n', { log: { loglevel: 'none' }, inbounds: inb, outbounds: outb, routing: { rules: R } }));
}

// ---------- tek sunucunun outbound'u (düzenleme ekranı ve kayıt öncesi doğrulama) ----------
function one_outbound(n) {
	let errs = [];
	n = prep_node(n, errs);
	let res = { errors: errs, outbound: null, test: null };
	if (n) {
		n._tag = 'node-001';
		let o = outbound(n);
		if (o) {
			res.outbound = o;
			res.test = { log: { loglevel: 'warning' }, outbounds: [o, { tag: 'direct', protocol: 'freedom' }] };
		}
	}
	print(sprintf('%.J\n', res));
	exit(length(errs) ? 3 : 0);
}

if (WHAT == 'xray') xray();
else if (WHAT == 'nft') nft();
else if (WHAT == 'dnsmasq') dnsmasq();
else if (WHAT == 'hev') hev();
else if (WHAT == 'nodes') nodes();
else if (WHAT == 'test') testcfg();
else if (WHAT == 'check') print(sprintf('%.J\n', { errors: ERRS, nodes: length(NODES) }));
else if (WHAT == 'outbound') {
	let n = raw[ARGV[1]];
	if (!n || n['.type'] != 'node') die('böyle bir sunucu yok: ' + ARGV[1]);
	one_outbound({ ...n });
}
else if (WHAT == 'outbound-json') {
	let n = null, arg = ARGV[1] ?? '';
	if (substr(arg, 0, 1) == '@') arg = fs.readfile(substr(arg, 1)) ?? '';
	try { n = json(arg); } catch (e) { n = null; }
	if (type(n) != 'object') die('aday sunucu JSON olarak okunamadı');
	one_outbound(n);
}
else die('bilinmeyen komut: ' + WHAT);
KEDIRAY_EOF_6
cat > '/usr/share/kediray/link.uc' <<'KEDIRAY_EOF_7'
'use strict';
// KediRay link / JSON / abonelik ayrıştırıcı
// ucode link.uc parse <dosya>            -> JSON dizi olarak sunucular
// ucode link.uc apply <dosya> [sub_id]   -> UCI'ye ekler (sub_id verilirse o aboneliğin eskilerini siler)

const fs = require('fs');

function urldec(s) {
	if (s == null) return null;
	return replace(s, /%([0-9A-Fa-f]{2})/g, (m, h) => chr(hex(h)));
}

function b64(s) {
	s = replace(trim('' + s), /[\r\n\t ]/g, '');
	s = replace(s, /-/g, '+');
	s = replace(s, /_/g, '/');
	s = replace(s, /=+$/, '');
	while (length(s) % 4) s += '=';
	return b64dec(s);
}

function qs(q) {
	let o = {};
	if (!q) return o;
	for (let kv in split(q, '&')) {
		if (!length(kv)) continue;
		let i = index(kv, '=');
		if (i < 0) o[urldec(kv)] = '';
		else o[urldec(substr(kv, 0, i))] = urldec(substr(kv, i + 1));
	}
	return o;
}

function purl(link) {
	let m = match(link, /^([a-zA-Z0-9]+):\/\/(.*)$/);
	if (!m) return null;
	let rest = m[2], frag = '', q = '', user = null, i;
	i = index(rest, '#');
	if (i >= 0) { frag = urldec(substr(rest, i + 1)); rest = substr(rest, 0, i); }
	i = index(rest, '?');
	if (i >= 0) { q = substr(rest, i + 1); rest = substr(rest, 0, i); }
	rest = replace(rest, /\/+$/, '');
	i = rindex(rest, '@');
	if (i >= 0) { user = substr(rest, 0, i); rest = substr(rest, i + 1); }
	let host = rest, port = null;
	let hm = match(rest, /^\[([^\]]+)\]:([0-9]+)$/) || match(rest, /^([^:]+):([0-9]+)$/);
	if (hm) { host = hm[1]; port = hm[2]; }
	return { scheme: lc(m[1]), user: user, host: host, port: port, q: qs(q), name: frag };
}

function clean(n) {
	let o = {};
	for (let k, v in n) {
		if (v == null || v === '') continue;
		o[k] = '' + v;
	}
	return o;
}

function transport(n, q) {
	let net = lc(q.type || q.net || 'tcp');
	if (net == 'raw') net = 'tcp';
	if (net == 'websocket') net = 'ws';
	if (net == 'splithttp') net = 'xhttp';
	n.network = net;
	let sec = lc(q.security || '');
	n.tls = (sec == 'tls' || sec == 'xtls') ? 'tls' : (sec == 'reality' ? 'reality' : 'none');
	n.sni = q.sni || q.peer || q.serverName;
	n.host = q.host;
	n.path = q.path;
	if (net == 'grpc') {
		n.service_name = q.serviceName || q.path;
		n.path = null;
		if (q.mode == 'multi') n.grpc_mode = 'multi';
	}
	if (net == 'xhttp') n.xhttp_mode = q.mode;
	if (net == 'tcp' && q.headerType == 'http') n.header_type = 'http';
	n.alpn = q.alpn;
	n.fp = q.fp;
	n.pbk = q.pbk;
	n.sid = q.sid;
	n.spx = q.spx;
	n.flow = q.flow;
	if (q.allowInsecure == '1' || q.allowInsecure == 'true' || q.insecure == '1') n.insecure = '1';
	return n;
}

function p_vless(u) {
	let n = { protocol: 'vless', address: u.host, port: u.port, uuid: urldec(u.user), encryption: u.q.encryption };
	transport(n, u.q);
	n.remarks = u.name;
	return n;
}

function p_trojan(u) {
	let n = { protocol: 'trojan', address: u.host, port: u.port, password: urldec(u.user) };
	transport(n, u.q);
	if (!u.q.security) n.tls = 'tls';
	n.remarks = u.name;
	return n;
}

function p_vmess_obj(j) {
	let n = {
		protocol: 'vmess', address: j.add, port: j.port, uuid: j.id, cipher: j.scy,
		remarks: j.ps
	};
	transport(n, {
		type: j.net, security: j.tls, sni: j.sni, host: j.host, path: j.path,
		alpn: j.alpn, fp: j.fp, headerType: j.type, serviceName: (j.net == 'grpc' ? j.path : null),
		mode: (j.net == 'grpc' && j.type == 'multi') ? 'multi' : j.mode, allowInsecure: j.allowInsecure
	});
	return n;
}

function p_vmess(link) {
	let body = substr(link, 8);
	let i = index(body, '#');
	if (i >= 0) body = substr(body, 0, i);
	let j = null;
	try { j = json(b64(body)); } catch (e) { j = null; }
	if (type(j) == 'object') return p_vmess_obj(j);
	// vmess://uuid@host:port?... biçimi
	let u = purl(link);
	if (!u) return null;
	let n = { protocol: 'vmess', address: u.host, port: u.port, uuid: urldec(u.user), cipher: u.q.encryption };
	transport(n, u.q);
	n.remarks = u.name;
	return n;
}

function p_ss(link) {
	let u = purl(link);
	if (!u) return null;
	let method, password, host = u.host, port = u.port;
	if (u.user != null) {
		let ui = urldec(u.user);
		if (index(ui, ':') < 0) ui = b64(ui);
		let i = index(ui, ':');
		method = substr(ui, 0, i); password = substr(ui, i + 1);
	} else {
		// eski biçim: ss://BASE64(method:pass@host:port)
		let d = b64(host);
		let m = match(d, /^([^:]+):(.*)@([^@]+):([0-9]+)$/);
		if (!m) return null;
		method = m[1]; password = m[2]; host = m[3]; port = m[4];
	}
	if (u.q.plugin) return null; // eklenti gerektiren SS desteklenmiyor
	return { protocol: 'shadowsocks', address: host, port: port, method: method, password: password, network: 'tcp', tls: 'none', remarks: u.name };
}

// ---- JSON (Xray outbound / tam config / vmess json) ----
const PROXY = { vless: 1, vmess: 1, trojan: 1, shadowsocks: 1 };

function from_outbound(o, idx) {
	if (type(o) != 'object' || !PROXY[o.protocol]) return null;
	let s = o.settings || {};
	let t = s.vnext?.[0] || s.servers?.[0] || s;
	if (!t.address || !t.port) return null;
	let copy = { ...o };
	delete copy.tag;
	return {
		protocol: o.protocol, address: t.address, port: t.port,
		network: o.streamSettings?.network,
		tls: o.streamSettings?.security,
		remarks: (o.tag && !match(o.tag, /^(proxy|outbound|out|node)$/)) ? o.tag : (o.protocol + ' ' + t.address + (idx ? ' #' + idx : '')),
		raw: sprintf('%J', copy)
	};
}

function from_json(j) {
	let out = [];
	if (type(j) == 'array') {
		for (let i = 0; i < length(j); i++) {
			let x = j[i];
			if (type(x) == 'object' && x.outbounds) push(out, ...from_json(x));
			else { let n = from_outbound(x, i + 1); if (n) push(out, n); }
		}
	}
	else if (type(j) == 'object') {
		if (type(j.outbounds) == 'array') {
			let k = 0;
			for (let o in j.outbounds) { let n = from_outbound(o, ++k); if (n) push(out, n); }
			// v2rayNG tam config: tag genelde 'proxy' -> config 'remarks' alanını kullan
			if (length(out) == 1 && j.remarks) out[0].remarks = j.remarks;
		}
		else if (j.protocol) { let n = from_outbound(j); if (n) push(out, n); }
		else if (j.add && j.id) push(out, p_vmess_obj(j));
	}
	return out;
}

function parse_text(txt) {
	txt = trim(txt || '');
	if (!length(txt)) return [];
	// JSON mu?
	if (substr(txt, 0, 1) == '{' || substr(txt, 0, 1) == '[') {
		let j = null;
		try { j = json(txt); } catch (e) { j = null; }
		if (j != null) return from_json(j);
	}
	// base64 abonelik mi?
	if (index(txt, '://') < 0) {
		let d = b64(txt);
		if (d && index(d, '://') >= 0) txt = d;
		else if (d && (substr(trim(d), 0, 1) == '{' || substr(trim(d), 0, 1) == '[')) return parse_text(d);
	}
	let out = [];
	for (let line in split(txt, /[\r\n]+/)) {
		line = trim(line);
		let n = null;
		if (match(line, /^vless:\/\//i)) n = p_vless(purl(line));
		else if (match(line, /^vmess:\/\//i)) n = p_vmess(line);
		else if (match(line, /^trojan:\/\//i)) n = p_trojan(purl(line));
		else if (match(line, /^ss:\/\//i)) n = p_ss(line);
		if (n && n.address && n.port) push(out, n);
	}
	return out;
}

const CMD = ARGV[0] || 'parse';
const FILE = ARGV[1];
const text = FILE && FILE != '-' ? fs.readfile(FILE) : fs.stdin.read('all');
let nodes = map(parse_text(text), clean);

if (CMD == 'parse') {
	print(sprintf('%.J\n', nodes));
	exit(0);
}

if (CMD == 'apply') {
	const SUB = ARGV[2];
	const uci = require('uci').cursor();
	let selname = uci.get('kediray', 'main', 'node');
	let selrem = null;
	if (SUB) {
		// Bu aboneliğin eski sunucularını sil (seçili olanın adını hatırla)
		let del = [];
		uci.foreach('kediray', 'node', s => {
			if (s.sub == SUB) {
				if (s['.name'] == selname) selrem = s.remarks;
				push(del, s['.name']);
			}
		});
		if (!length(nodes)) { warn('kediray: abonelik boş geldi, eski sunucular korunuyor\n'); exit(3); }
		for (let d in del) uci.delete('kediray', d);
	}
	let added = 0, newsel = null;
	for (let n in nodes) {
		let s = uci.add('kediray', 'node');
		for (let k, v in n) uci.set('kediray', s, k, v);
		if (SUB) uci.set('kediray', s, 'sub', SUB);
		if (selrem && n.remarks == selrem && !newsel) newsel = s;
		added++;
	}
	if (selrem) uci.set('kediray', 'main', 'node', newsel || 'auto');
	uci.save('kediray');
	uci.commit('kediray');
	print(added, '\n');
	exit(added ? 0 : 3);
}
KEDIRAY_EOF_7
cat > '/usr/share/kediray/cli.uc' <<'KEDIRAY_EOF_8'
'use strict';
// KediRay CLI yardımcıları (JSON çıktılar panel için)
const fs = require('fs');
const CMD = ARGV[0];
const RUN = getenv('KR_RUN') || '/var/etc/kediray';

function cursor() {
	const f = getenv('KR_CFG');   // test için JSON fikstürü
	if (!f) return require('uci').cursor();
	let d = json(fs.readfile(f));
	if (d.values) d = d.values;
	const secs = sort(values(d), (a, b) => (a['.index'] ?? 0) - (b['.index'] ?? 0));
	return {
		get_all: (c, s) => s ? d[s] : d,
		foreach: (c, t, cb) => { for (let s in secs) if (s['.type'] == t) cb(s); }
	};
}
function readlines(p) {
	let t = fs.readfile(p);
	return t ? filter(split(t, '\n'), l => length(l)) : [];
}
function nodes_tsv() {
	let out = [];
	for (let l in readlines(RUN + '/nodes.tsv')) {
		let f = split(l, '\t');
		push(out, { tag: f[0], sec: f[1], tport: int(f[2]), address: f[3], port: int(f[4]), protocol: f[5],
			network: f[6], insecure: f[7] == '1', sni: f[8], pinned: f[9] != '-', name: f[10] });
	}
	return out;
}
// address -> IP eşlemesi ($RUN/resolve: "alan.adi=1.2.3.4 alan2=5.6.7.8")
function resolved(addr) {
	if (!addr || match(addr, /^[0-9.]+$/)) return null;
	for (let kv in split(trim(fs.readfile(RUN + '/resolve') ?? ''), /[ \n]+/)) {
		let i = index(kv, '=');
		if (i > 0 && substr(kv, 0, i) == addr) return substr(kv, i + 1);
	}
	return null;
}
function pings() {
	let p = {};
	for (let l in readlines(RUN + '/ping.tsv')) {
		let f = split(l, '\t');
		p[f[0]] = { ms: int(f[1]), at: int(f[2]), rtt: (f[3] != null && int(f[3]) > 0) ? int(f[3]) : null,
			// açık bağlantıda ölçülen tünel gecikmesi (sayfaların/oyunun hissettiği)
			warm: (f[4] != null && int(f[4]) > 0) ? int(f[4]) : null };
	}
	return p;
}
function out(x) { print(sprintf('%J\n', x)); }

if (CMD == 'status') {
	let c = cursor();
	let m = c.get_all('kediray', 'main') || {};
	let ns = nodes_tsv(), active = getenv('KR_ACTIVE') || '', an = null;
	for (let n in ns) if (n.tag == active) an = n;
	let sel = m.node || 'auto', sn = null;
	for (let n in ns) if (n.sec == sel) sn = n;
	let p = pings();
	out({
		enabled: m.enabled == '1',
		running: getenv('KR_RUNNING') == '1',
		fw: getenv('KR_FW') == 'up',
		core: getenv('KR_CORE') || '',
		uptime: int(getenv('KR_UPTIME') || 0),
		mode: (m.mode == 'list') ? 'list' : 'global',
		auto: !sn && sel != 'none',
		disconnected: sel == 'none',
		selected: sn ? { sec: sn.sec, name: sn.name } : null,
		active: (an && sel != 'none') ? { sec: an.sec, name: an.name, tag: an.tag, address: an.address, port: an.port, sni: an.sni,
			// alan adı ile bağlanılıyorsa bir kez çözülen IP (Ayarlar > "IP ile bağlan")
			ip: resolved(an.address), protocol: an.protocol, network: an.network,
			ping: p[an.sec]?.ms, rtt: p[an.sec]?.rtt, warm: p[an.sec]?.warm } : null,
		nodes: length(ns),
		failsafe: m.failsafe || 'killswitch',
		// tünel DNS'i yanıt vermediği için geçici olarak operatör DNS'ine düşüldü mü
		dns_rescue: fs.stat(RUN + '/dns_rescue') != null,
		conflict: filter(split(getenv('KR_CONFLICT') || '', ' '), x => length(x)),
		direct_dead: m.auto_direct != '0' && trim(fs.readfile(RUN + '/direct') ?? '') == 'dead',
		capture: trim(fs.readfile(RUN + '/capture') ?? '') || (m.capture || 'mixed'),
		last_error: m.enabled == '1' && getenv('KR_RUNNING') != '1' ? trim(fs.readfile(RUN + '/last_error') ?? '') || null : null
	});
}
else if (CMD == 'nodes') {
	let c = cursor(), p = pings(), res = [];
	let tsv = {};
	for (let n in nodes_tsv()) tsv[n.sec] = n;
	c.foreach('kediray', 'node', s => {
		let t = tsv[s['.name']];
		push(res, {
			sec: s['.name'], name: s.remarks || ((s.address ?? '?') + ':' + (s.port ?? '')),
			protocol: s.protocol ?? t?.protocol, network: s.network ?? t?.network ?? 'tcp',
			address: s.address ?? t?.address, port: s.port ?? t?.port, tls: s.tls ?? '',
			json: !!s.raw, sub: s.sub ?? null, enabled: s.enabled != '0',
			tag: t?.tag, insecure: t?.insecure ?? false, pinned: t?.pinned ?? false,
			ping: p[s['.name']]?.ms, ping_at: p[s['.name']]?.at, rtt: p[s['.name']]?.rtt, warm: p[s['.name']]?.warm
		});
	});
	out(res);
}
else if (CMD == 'apps') {
	let c = cursor(), res = [];
	c.foreach('kediray', 'app', s => push(res, {
		sec: s['.name'], name: s.name || s['.name'], route: s.route || 'vpn', enabled: s.enabled != '0',
		ports: s.ports || '', ips: length(s.ip ?? []), domains: length(s.domain ?? []), domain_list: s.domain ?? [], tunnel_dns: s.tunnel_dns == '1'
	}));
	out(res);
}
else if (CMD == 'devices') {
	let c = cursor(), res = {}, order = [];
	let add = (mac, o) => {
		mac = lc(mac || '');
		if (!length(mac)) return;
		if (!res[mac]) { res[mac] = { mac: mac, ip: '', name: '', mode: 'default', sec: null, online: false }; push(order, mac); }
		for (let k, v in o) if (v != null && v !== '') res[mac][k] = v;
	};
	// Gerçekten bağlı mı? DHCP kirası ve ARP kayıtları cihaz ayrıldıktan sonra uzun süre kalır; bu yüzden
	// Wi-Fi'da asıl ölçüt "iw station dump" (bağlı istasyonlar), kablolu cihazda komşu tablosunun canlılığıdır.
	let rd = (cmd) => { let p = fs.popen(cmd + ' 2>/dev/null'); if (!p) return ''; let o = p.read('all') ?? ''; p.close(); return o; };
	// Bağlı kalma süresi: cihaz her görüldüğünde damgalanır; 10 dk hiç görünmezse yeniden bağlanmış sayılır
	const PF = RUN + '/presence.json';
	let pres = {};
	try { let t = fs.readfile(PF); if (t) pres = json(t); } catch (e) { pres = {}; }
	let assoc = {}, haveAssoc = false, neigh = {}, ndev = {}, nip = {}, probes = {}, fb = {};
	for (let l in split(rd('for i in $(iw dev | awk \'$1=="Interface"{print $2}\'); do echo "IF $i"; iw dev "$i" station dump | awk \'/^Station/{m=$2} /inactive time:/{print m, $3}\'; done'), '\n')) {
		if (match(l, /^IF /)) { haveAssoc = true; continue; }
		let m = match(l, /^([0-9a-fA-F]{2}(:[0-9a-fA-F]{2}){5}) ([0-9]+)/);
		if (m) assoc[lc(m[1])] = int(m[3]);   // son hareketten bu yana ms
	}
	for (let l in split(rd('ip -4 neigh show'), '\n')) {
		let m = match(l, /^([0-9.]+) dev ([^ ]+) lladdr ([0-9a-fA-F:]{17}).* (REACHABLE|DELAY|PROBE|STALE|FAILED|INCOMPLETE|PERMANENT|NOARP)/);
		if (m) { let k = lc(m[3]); neigh[k] = m[4]; ndev[k] = m[2]; nip[k] = m[1]; }
	}
	// Gerçekten bağlı mı? DHCP kirası, ARP kaydı ve Wi-Fi "bağlı" listesi cihaz ayrıldıktan sonra uzun süre kalır.
	// Asıl ölçüt: cihaz ARP'a şu an cevap veriyor mu. Cevabı belirsiz (bayat) olanlara komşu sınaması (ARP) gönderilir,
	// sonuç bir sonraki yoklamada okunur. Sınama yapılamıyorsa Wi-Fi hareketsizlik süresine bakılır.
	// Dönüş: 1 bağlı, 0 değil, -1 belirsiz (sınama sürüyor)
	let alive = (mac, ip) => {
		mac = lc(mac || '');
		if (assoc[mac] != null) return true;                 // Wi-Fi'a bağlı: uyku modunda olsa da (trafik göndermese de) bağlıdır
		if (pres[mac]?.wifi) return false;                   // daha önce Wi-Fi'daydı, şimdi bağlı listesinde yok: ayrıldı
		// Wi-Fi'da hiç görülmemiş (kablolu) cihaz: ARP cevabına bak
		let ns = neigh[mac];
		if (ns == 'REACHABLE' || ns == 'PERMANENT') return true;
		if (ns == 'FAILED' || ns == 'INCOMPLETE') return false;
		if (!haveAssoc && ns == null) return true;           // iw yok: eski davranış
		let a = nip[mac] || ip;
		if (a) {
			if (ns != 'PROBE') probes[mac] = { ip: a, dev: ndev[mac] || 'br-lan' };
			fb[mac] = ns != null;
			return -1;
		}
		return false;
	};
	for (let l in readlines('/tmp/dhcp.leases')) {
		let f = split(l, ' ');
		if (length(f) >= 4) add(f[1], { ip: f[2], name: f[3] != '*' ? f[3] : '', online: alive(f[1], f[2]) });
	}
	// ARP tablosundaki (statik IP) cihazlar
	for (let l in readlines('/proc/net/arp')) {
		let f = filter(split(l, ' '), x => length(x));
		if (length(f) >= 6 && f[3] != '00:00:00:00:00:00' && match(f[0], /^[0-9.]+$/) && f[2] != '0x0') add(f[3], { ip: res[lc(f[3])]?.ip || f[0], online: alive(f[3], f[0]) });
	}
	// Belirsiz cihazlara ARP sınaması gönder (asenkron; cevap sonraki yoklamada görünür)
	let probeOK = true;
	for (let mac, pr in probes) {
		let o = rd('ip neigh replace ' + pr.ip + ' lladdr ' + mac + ' dev ' + pr.dev + ' nud probe && echo ok');
		if (!match(o, /ok/)) { probeOK = false; break; }
	}
	c.foreach('kediray', 'device', s => {
		if (s.mac) add(s.mac, { name: s.name, mode: s.mode || 'default', sec: s['.name'], ip: res[lc(s.mac)]?.ip || s.ip });
	});
	let now = time(), keep = {};
	for (let mac, d in res) {
		let p = pres[mac];
		let sure = d.online === true;   // kesin doğrulanmış mı (ARP cevabı / Wi-Fi'da yeni hareket)
		if (d.online === -1) {
			// belirsiz: sınama çalışıyorsa son doğrulamadan 25 sn tolerans (süre dolunca çevrimdışı), çalışmıyorsa Wi-Fi hareketsizlik süresi
			d.online = probeOK ? (p ? (now - int(p.last ?? 0) < 25) : true) : !!fb[mac];
			sure = !probeOK;
		}
		if (d.online) {
			if (!p || now - int(p.last ?? 0) > 600) p = { first: now, last: now };
			if (sure) p.last = now;
			if (assoc[mac] != null) p.wifi = true;   // bu cihaz Wi-Fi'dan bağlanıyor: ayrılınca bağlı listesinden düşmesi yeterli kanıt
			pres[mac] = p;
			d.since = p.first;
			d.uptime = now - int(p.first);
		} else {
			// çevrimdışı: ilk görüldüğü andan (ya da son bağlı olduğu andan) itibaren say; 5 dk sonra listeden gizle
			if (!p) { p = { first: now, last: now }; pres[mac] = p; }
			d.since = p.first;
			d.uptime = 0;
			d.off_for = now - int(p.last ?? now);
			if (d.off_for >= 300) d.hidden = true;   // kuralı silinmez; cihaz tekrar bağlanınca kendi yönüyle geri gelir
		}
	}
	// 7 günden eski kayıtları at
	for (let mac, p in pres) if (now - int(p.last ?? 0) < 604800) keep[mac] = p;
	try { fs.mkdir(RUN); fs.writefile(PF + '.tmp', sprintf('%J', keep)); fs.rename(PF + '.tmp', PF); } catch (e) {}
	out(filter(map(order, k => res[k]), d => !d.hidden));
}
else if (CMD == 'stats') {
	// stdin: xray api statsquery çıktısı
	let j = null;
	try { j = json(fs.stdin.read('all')); } catch (e) { j = null; }
	let r = { vpn_up: 0, vpn_down: 0, direct_up: 0, direct_down: 0, t: time() };
	for (let s in (j?.stat ?? [])) {
		let m = match(s.name, /^outbound>>>([^>]+)>>>traffic>>>(uplink|downlink)$/);
		if (!m) continue;
		let v = int(s.value ?? 0), up = m[2] == 'uplink';
		if (substr(m[1], 0, 5) == 'node-') r[up ? 'vpn_up' : 'vpn_down'] += v;
		else if (m[1] == 'direct') r[up ? 'direct_up' : 'direct_down'] += v;
	}
	out(r);
}
else if (CMD == 'webtest') {
	// ARGV[1]: satır başına "host<TAB>dns con tls ttfb tot code<TAB>(vpn aynısı)" (curl -w saniye cinsinden)
	const running = ARGV[2] == '1';
	let tests = [], sd = 0, st = 0, sv = 0, n = 0;
	let part = (f, off) => {
		// curl kümülatif verir: connect DNS'i, appconnect connect'i içerir
		let dns = +f[0], con = +f[1], tls = +f[2], ttfb = +f[3], tot = +f[4];
		let m = x => int(x * 1000 + 0.5);
		return {
			dns: m(dns), connect: m(con > dns ? con - dns : 0), tls: m(tls > con ? tls - con : 0),
			ttfb: m(ttfb > tls ? ttfb - tls : (ttfb > con ? ttfb - con : 0)), total: m(tot), code: int(f[5])
		};
	};
	for (let l in readlines(ARGV[1])) {
		let c = split(l, '\t');
		if (length(c) < 3) continue;
		let d = part(split(trim(c[1]), /[ ]+/)), v = part(split(trim(c[2]), /[ ]+/));
		push(tests, { host: c[0], direct: d, vpn: v });
		n++; sd += d.dns; st += d.total; sv += v.total;
	}
	// Ortalamaya yalnız TAMAMLANAN ölçümler girer: başarısız denemede curl 0 yazar, 0 ms "iyi" demek değildir
	let okD = filter(tests, t => t.direct.code > 0), okV = filter(tests, t => t.vpn.code > 0);
	let dnsOk = filter(tests, t => t.direct.dns > 0 || t.direct.code > 0);
	let sdo = 0; for (let t in dnsOk) sdo += t.direct.dns;
	let sto = 0; for (let t in okD) sto += t.direct.total;
	let svo = 0; for (let t in okV) svo += t.vpn.total;
	let avg = { dns: length(dnsOk) ? int(sdo / length(dnsOk)) : null,
		direct_total: length(okD) ? int(sto / length(okD)) : null,
		vpn_total: length(okV) ? int(svo / length(okV)) : null };
	// Ad çözümlenemediyse curl DNS aşamasında 0 yazıp zaman aşımına düşer: bu "DNS 0 ms, iyi" DEĞİL, "DNS ölü"dür
	let deadDns = filter(tests, t => t.direct.code == 0 && t.direct.dns == 0);
	let deadV = filter(tests, t => t.vpn.code == 0);
	let verdict = [];
	if (length(deadDns) == n && n > 0) {
		push(verdict, 'Modem hiçbir adresi çözemedi: ' + n + ' adresin hepsi ad çözümleme aşamasında zaman aşımına düştü (curl "DNS 0 ms" yazar, bu iyi demek değil).');
		push(verdict, 'En olası sebep: DNS modu "Tünelden" ve tünel şu an bağlantıyı düşürüyor — çözümleme de tünelden gittiği için modem hiçbir adı çözemez. Günlükte "Sunucu el sıkışma sırasında bağlantıyı kapattı (EOF)" varsa sebep budur.');
		push(verdict, 'Hemen çözüm: Ayarlar → DNS → "Direkt" moduna al (sorgular tünelden bağımsız çözülür). Kalıcı çözüm: sunucunun el sıkışmayı neden düşürdüğünü bul — "kediray dialtest".');
	}
	else if (length(deadDns)) push(verdict, length(deadDns) + ' adres çözümlenemedi (DNS aşamasında zaman aşımı).');
	else if (avg.dns == null) push(verdict, 'DNS süresi ölçülemedi.');
	else if (avg.dns >= 1000) push(verdict, 'DNS çok yavaş (' + avg.dns + ' ms): sayfa daha açılmadan bekleniyor. Ayarlar → DNS → "Direkt" modunu ve direkt DNS yedeğini dene.');
	else if (avg.dns >= 300) push(verdict, 'DNS yavaş (' + avg.dns + ' ms): ilk açılışta hissedilir.');
	else push(verdict, 'DNS iyi (' + avg.dns + ' ms).');
	if (running) {
		if (length(deadV) && length(deadV) != length(deadDns))
			push(verdict, length(deadV) + ' adres VPN üzerinden hiç açılmadı: sunucu bağlantısı kopuyor (Günlük\'e bak, "kediray dialtest" ile ölç).');
		let ov = (avg.vpn_total != null && avg.direct_total != null) ? avg.vpn_total - avg.direct_total : null;
		if (ov == null) push(verdict, 'VPN ek gecikmesi hesaplanamadı: ölçümlerin bir kısmı tamamlanmadı.');
		else if (ov > 1500) push(verdict, 'VPN sayfayı ' + ov + ' ms geciktiriyor: sunucu uzak ya da yükte; başka sunucu dene.');
		else if (ov > 400) push(verdict, 'VPN ' + ov + ' ms ekliyor (normal aralık: 100-400 ms).');
		else push(verdict, 'VPN ek gecikmesi normal (' + ov + ' ms).');
	} else push(verdict, 'VPN kapalı: yalnızca direkt ölçüldü.');
	if (getenv('KR_SOCKS_OK') == '0')
		push(verdict, 'curl bu modemde SOCKS desteklemiyor: VPN sütunu ölçülemedi (apk add curl).');
	out({ running: running, tests: tests, avg: avg, verdict: verdict });
}
else if (CMD == 'conns') {
	// stdin: /proc/net/nf_conntrack ; ARGV[1] = istemci IP (boş = hepsi), ARGV[2] = TUN işareti (UDP tüneli)
	const ip = ARGV[1] || '';
	const tunmark = int(ARGV[2] ?? 0) || 738;
	let agg = {};
	for (let l in split(fs.stdin.read('all') ?? '', '\n')) {
		let srcs = match(l, /src=([0-9.]+)/g), dst = match(l, /dst=([0-9.]+) /), dp = match(l, /dport=([0-9]+)/);
		let pr = match(l, / (tcp|udp) /);
		if (!srcs || !dst || !dp || !pr) continue;
		let src = srcs[0][1];
		if (length(ip) && src != ip) continue;
		if (match(dst[1], /^(10\.|192\.168\.|127\.|172\.(1[6-9]|2[0-9]|3[01])\.|22[4-9]\.|23[0-9]\.|255\.)/)) continue;
		let port = int(dp[1]);
		if (port == 53 || port == 123) continue;
		// Tünelden mi geçiyor? TCP: çekirdek 127.0.0.1'e yönlendirir (yanıt tarafının kaynağı 127.0.0.1)
		//                       UDP: paket TUN işaretini taşır (mark=)
		let mk = match(l, /mark=([0-9]+)/);
		// Tünelden mi? NAT yönlendirmesi yanıt tarafının kaynağını değiştirir (127.0.0.1 ya da yönlendirici IP'si): yanıt kaynağı != asıl hedef
		let vpn = (length(srcs) > 1 && srcs[1][1] != dst[1]) || (mk && int(mk[1]) == tunmark);
		let k = pr[1] + ' ' + dst[1] + ':' + port;
		agg[k] ??= { proto: pr[1], dst: dst[1], port: port, client: src, n: 0, web: (port == 80 || port == 443), vpn: false };
		agg[k].n++;
		if (vpn) agg[k].vpn = true;
	}
	out(sort(values(agg), (a, b) => (a.web - b.web) || (b.n - a.n)));
}
else {
	warn('kullanım: cli.uc status|nodes|apps|devices|stats|conns\n');
	exit(1);
}
KEDIRAY_EOF_8
cat > '/usr/share/kediray/node.uc' <<'KEDIRAY_EOF_9'
'use strict';
// KediRay sunucu düzenleme ve yapılandırma denetimi
//   ucode node.uc check-json '<metin>'                 -> JSON yazım denetimi (satır/sütun, Türkçe)
//   ucode node.uc get <bölüm>                           -> düzenleme ekranı için alanlar
//   ucode node.uc save <bölüm|new> form '<alanlar>'     -> denetle + Xray testi + kaydet
//   ucode node.uc save <bölüm|new> json '<outbound>' [ad]
//   ucode node.uc del <bölüm>
//   ucode node.uc validate                              -> tüm yapılandırmayı denetle
// Ortam: KR_SHARE, KR_XRAY, KR_ASSET, KR_RUN (kediray betiği verir); KR_DRYRUN=1 -> kaydetmeden denetle

const fs = require('fs');
const CMD = ARGV[0];
const SHARE = getenv('KR_SHARE') || '/usr/share/kediray';
const RUN = getenv('KR_RUN') || '/var/etc/kediray';
const PROTOS = { vless: 1, vmess: 1, trojan: 1, shadowsocks: 1 };

function out(x) { print(sprintf('%J\n', x)); }
function q(s) { return "'" + replace('' + s, /'/g, "'\\''") + "'"; }
function sh(cmd) { let p = fs.popen(cmd); let o = p.read('all') ?? ''; let rc = p.close(); return { out: o, rc: rc }; }
function cur() { return require('uci').cursor(); }

// ---------- katı JSON denetleyici: ilk hatanın satır/sütunu ve Türkçe açıklaması ----------
function json_check(s) {
	let i = 0, n = length(s), err = null;
	let ch = () => (i < n ? substr(s, i, 1) : '');
	let fail = (msg) => { if (!err) err = { pos: i, msg: msg }; return false; };
	let ws = () => { while (i < n && index(' \t\r\n', ch()) >= 0) i++; };
	let value, str, num, obj, arr;
	str = () => {
		i++;
		while (i < n) {
			let c = ch();
			if (c == '"') { i++; return true; }
			if (c == '\\') { i += 2; continue; }
			if (c == '\n') return fail('Metin bitmeden satır sonu geldi (kapanış tırnağı " eksik)');
			i++;
		}
		return fail('Kapanış tırnağı " eksik');
	};
	num = () => {
		let m = match(substr(s, i, 64), /^-?(0|[1-9][0-9]*)(\.[0-9]+)?([eE][+-]?[0-9]+)?/);
		if (!m) return fail('Geçersiz sayı');
		i += length(m[0]);
		return true;
	};
	obj = () => {
		i++; ws();
		if (ch() == '}') { i++; return true; }
		while (true) {
			ws();
			let c = ch();
			if (c == '}') return fail("Son öğeden sonra fazladan virgül var (',' sil)");
			if (c == "'") return fail('Anahtarlar tek tırnakla değil çift tırnakla (") yazılmalı');
			if (c != '"') return fail(i >= n ? "'}' kapanmamış (metin erken bitti)" : 'Anahtar çift tırnak (") içinde olmalı');
			if (!str()) return false;
			ws();
			if (ch() != ':') return fail("Anahtardan sonra ':' bekleniyordu");
			i++;
			if (!value()) return false;
			ws();
			c = ch();
			if (c == ',') { i++; continue; }
			if (c == '}') { i++; return true; }
			if (i >= n) return fail("'}' kapanmamış (metin erken bitti)");
			return fail("',' veya '}' bekleniyordu (önceki satırın sonunda virgül eksik olabilir)");
		}
	};
	arr = () => {
		i++; ws();
		if (ch() == ']') { i++; return true; }
		while (true) {
			ws();
			if (ch() == ']') return fail("Son öğeden sonra fazladan virgül var (',' sil)");
			if (!value()) return false;
			ws();
			let c = ch();
			if (c == ',') { i++; continue; }
			if (c == ']') { i++; return true; }
			if (i >= n) return fail("']' kapanmamış (metin erken bitti)");
			return fail("',' veya ']' bekleniyordu");
		}
	};
	value = () => {
		ws();
		let c = ch();
		if (c == '{') return obj();
		if (c == '[') return arr();
		if (c == '"') return str();
		if (c == '-' || (c >= '0' && c <= '9')) return num();
		if (substr(s, i, 4) == 'true' || substr(s, i, 4) == 'null') { i += 4; return true; }
		if (substr(s, i, 5) == 'false') { i += 5; return true; }
		if (c == "'") return fail('Metinler tek tırnakla değil çift tırnakla (") yazılmalı');
		if (i >= n) return fail('Beklenmedik son: değer bekleniyordu');
		return fail("Geçersiz değer '" + c + "' (metinler çift tırnak içinde olmalı)");
	};
	if (value()) { ws(); if (i < n) fail('JSON bittikten sonra fazladan içerik var'); }
	if (!err) return null;
	let line = 1, col = 1;
	for (let k = 0; k < err.pos && k < n; k++) {
		if (substr(s, k, 1) == '\n') { line++; col = 1; } else col++;
	}
	return { line: line, col: col, msg: err.msg };
}

// Xray'in İngilizce hata zincirinden en anlamlı kısmı çıkar
function xray_errors(log) {
	let res = [];
	for (let l in split(log, '\n')) {
		if (!match(l, /(Failed|failed|invalid|error|Error|unknown|not supported|removed)/)) continue;
		if (match(l, /\[Warning\]/)) continue;
		let parts = split(l, ' > ');
		push(res, { msg: trim(parts[length(parts) - 1]), detail: trim(l) });
	}
	return length(res) ? res : [{ msg: 'Xray yapılandırmayı kabul etmedi', detail: trim(log) }];
}

function xray_test(cfg) {
	let xb = getenv('KR_XRAY') || SHARE + '/bin/xray';
	if (!fs.access(xb, 'x')) return null;   // çekirdek yoksa bu aşama atlanır
	let f = RUN + '/cand.' + time() + '.json';
	fs.mkdir(RUN);
	fs.writefile(f, sprintf('%J', cfg));
	let r = sh('XRAY_LOCATION_ASSET=' + q(getenv('KR_ASSET') || SHARE) + ' ' + q(xb) + ' run -test -c ' + q(f) + ' 2>&1');
	fs.unlink(f);
	return r.rc == 0 ? [] : xray_errors(r.out);
}

const FORM_FIELDS = ['remarks', 'protocol', 'address', 'port', 'uuid', 'password', 'method', 'flow', 'encryption', 'cipher',
	'network', 'path', 'host', 'service_name', 'grpc_mode', 'xhttp_mode', 'header_type',
	'tls', 'sni', 'fp', 'alpn', 'insecure', 'pin', 'pbk', 'sid', 'spx', 'enabled'];

function write_node(sec, kind, payload) {
	let u = cur();
	if (sec == 'new' || !sec) sec = u.add('kediray', 'node');
	else if (u.get('kediray', sec) != 'node') return null;
	let keep = { remarks: u.get('kediray', sec, 'remarks'), sub: u.get('kediray', sec, 'sub'), enabled: u.get('kediray', sec, 'enabled') };
	for (let k in [...FORM_FIELDS, 'raw']) u.delete('kediray', sec, k);
	if (kind == 'json') {
		let ob = payload.outbound, st = ob.settings || {}, t = st.vnext?.[0] || st.servers?.[0] || st;
		u.set('kediray', sec, 'raw', sprintf('%J', ob));
		u.set('kediray', sec, 'protocol', '' + ob.protocol);
		u.set('kediray', sec, 'address', '' + t.address);
		u.set('kediray', sec, 'port', '' + t.port);
		if (ob.streamSettings?.network) u.set('kediray', sec, 'network', '' + ob.streamSettings.network);
		if (ob.streamSettings?.security) u.set('kediray', sec, 'tls', '' + ob.streamSettings.security);
		let rm = payload.remarks || keep.remarks;
		if (rm) u.set('kediray', sec, 'remarks', '' + rm);
	} else {
		for (let k, v in payload) {
			if (index(FORM_FIELDS, k) < 0 || v == null || v === '') continue;
			u.set('kediray', sec, k, '' + v);
		}
	}
	if (keep.sub) u.set('kediray', sec, 'sub', keep.sub);
	if (keep.enabled != null && payload.enabled == null) u.set('kediray', sec, 'enabled', keep.enabled);
	u.save('kediray');
	u.commit('kediray');
	return sec;
}

// ================= komutlar =================
if (CMD == 'check-json') {
	let e = json_check(ARGV[1] ?? '');
	out(e ? { ok: false, errors: [e] } : { ok: true });
	exit(e ? 3 : 0);
}

if (CMD == 'get') {
	let s = cur().get_all('kediray', ARGV[1]);
	if (!s || s['.type'] != 'node') { out({ ok: false, errors: [{ msg: 'böyle bir sunucu yok' }] }); exit(1); }
	let f = {};
	for (let k in FORM_FIELDS) if (s[k] != null) f[k] = s[k];
	let pretty = null, gen = null;
	if (s.raw) { try { pretty = sprintf('%.J', json(s.raw)); } catch (e) { pretty = s.raw; } }
	// Form sunucusu için Xray'in kullanacağı outbound'u da göster (JSON sekmesinde düzenlenebilsin)
	let g = sh('ucode ' + q(SHARE + '/gen.uc') + ' outbound ' + q(s['.name']) + ' 2>/dev/null');
	try { gen = json(g.out); } catch (e) { gen = null; }
	if (!pretty && gen?.outbound) {
		let o = { ...gen.outbound };
		delete o.tag;
		pretty = sprintf('%.J', o);
	}
	out({ ok: true, sec: s['.name'], mode: s.raw ? 'json' : 'form', fields: f, json: pretty, sub: s.sub ?? null, errors: gen?.errors ?? [] });
	exit(0);
}

if (CMD == 'save') {
	let sec = ARGV[1], kind = ARGV[2], text = ARGV[3] ?? '', rname = ARGV[4] ?? '';
	let res = { ok: false, stage: null, errors: [] };
	let fail = (stage, errs) => { res.stage = stage; res.errors = errs; out(res); exit(3); };
	let cand, payload;

	// 1) yazım denetimi
	let e = json_check(text);
	if (e) fail('syntax', [e]);
	let data = json(text);

	if (kind == 'json') {
		let ob = data;
		if (type(data) == 'object' && type(data.outbounds) == 'array') {
			ob = null;
			for (let o in data.outbounds) if (type(o) == 'object' && PROTOS[o.protocol]) { ob = o; break; }
			if (!rname && data.remarks) rname = data.remarks;
		}
		if (type(ob) != 'object') fail('fields', [{ msg: 'JSON bir Xray outbound nesnesi olmalı ({ "protocol": ..., "settings": ... })' }]);
		if (!ob.protocol) fail('fields', [{ msg: '"protocol" alanı yok' }]);
		if (!PROTOS[ob.protocol]) fail('fields', [{ msg: '"' + ob.protocol + '" desteklenmiyor (vless, vmess, trojan, shadowsocks)' }]);
		ob = { ...ob };
		delete ob.tag;
		cand = { raw: sprintf('%J', ob), remarks: rname };
		payload = { outbound: ob, remarks: rname };
	} else {
		if (type(data) != 'object') fail('fields', [{ msg: 'form verisi okunamadı' }]);
		cand = {};
		for (let k, v in data) if (index(FORM_FIELDS, k) >= 0 && v != null && v !== '') cand[k] = '' + v;
		payload = cand;
	}

	// 2) alan denetimi + outbound üretimi
	let tf = RUN + '/cand.in.' + time() + '.json';
	fs.mkdir(RUN);
	fs.writefile(tf, sprintf('%J', cand));
	let g = sh('ucode ' + q(SHARE + '/gen.uc') + ' outbound-json ' + q('@' + tf) + ' 2>/dev/null');
	fs.unlink(tf);
	let gen = null;
	try { gen = json(g.out); } catch (x) { gen = null; }
	if (!gen) fail('fields', [{ msg: 'sunucu işlenemedi' }]);
	if (length(gen.errors)) fail('fields', gen.errors);

	// 3) gerçek Xray testi
	let xe = xray_test(gen.test);
	if (xe && length(xe)) fail('xray', xe);

	// 4) kaydet
	if (getenv('KR_DRYRUN') == '1') { res.ok = true; res.stage = 'dry'; res.outbound = gen.outbound; out(res); exit(0); }
	let saved = write_node(sec, kind, payload);
	if (!saved) fail('save', [{ msg: 'böyle bir sunucu yok' }]);
	res.ok = true; res.sec = saved;
	out(res);
	exit(0);
}

if (CMD == 'del') {
	let u = cur(), sec = ARGV[1];
	if (u.get('kediray', sec) != 'node') { out({ ok: false, errors: [{ msg: 'böyle bir sunucu yok' }] }); exit(1); }
	u.delete('kediray', sec);
	if (u.get('kediray', 'main', 'node') == sec) u.set('kediray', 'main', 'node', 'auto');
	u.save('kediray');
	u.commit('kediray');
	out({ ok: true });
	exit(0);
}

if (CMD == 'validate') {
	let res = { ok: true, errors: [] };
	let add = (stage, e) => { res.ok = false; push(res.errors, { stage: stage, ...e }); };
	// a) UCI dosyası okunabiliyor mu (tırnak/yazım hatası)
	if (!getenv('KR_CFG')) {
		let u = sh('uci -q show kediray 2>&1 >/dev/null');
		if (u.rc != 0) {
			let m = match(u.out, /line ([0-9]+)/);
			add('uci', { line: m ? int(m[1]) : null, msg: '/etc/config/kediray okunamadı: ' + trim(u.out) });
			out(res); exit(3);
		}
	}
	// b) sunucu alanları
	let c = sh('ucode ' + q(SHARE + '/gen.uc') + ' check 2>/dev/null'), chk = null;
	try { chk = json(c.out); } catch (x) { chk = null; }
	for (let e in (chk?.errors ?? [])) {
		// Bozuk JSON sunucusunda hatanın yerini de göster
		if (e.field == 'raw' && e.node) {
			let rawtxt = null;
			if (getenv('KR_CFG')) { let d = json(fs.readfile(getenv('KR_CFG'))); rawtxt = d?.[e.node]?.raw; }
			else rawtxt = cur().get('kediray', e.node, 'raw');
			let je = rawtxt ? json_check(rawtxt) : null;
			if (je) { e.line = je.line; e.col = je.col; e.msg = e.msg + ' — ' + je.msg; }
		}
		add('node', e);
	}
	if (chk && chk.nodes == 0) add('node', { msg: 'hiç geçerli sunucu yok' });
	// c) tam yapılandırma + Xray testi
	fs.mkdir(RUN);
	let x = sh('ucode ' + q(SHARE + '/gen.uc') + ' xray 2>' + q(RUN + '/gen.err')), cfg = null;
	try { cfg = json(x.out); } catch (e2) { cfg = null; }
	if (!cfg) { if (chk?.nodes) add('gen', { msg: trim(fs.readfile(RUN + '/gen.err') ?? '') || 'yapılandırma üretilemedi' }); }
	else {
		let xe = xray_test(cfg);
		for (let e in (xe ?? [])) add('xray', e);
	}
	out(res);
	exit(res.ok ? 0 : 3);
}

warn('kullanım: node.uc check-json|get|save|del|validate\n');
exit(1);
KEDIRAY_EOF_9
cat > '/usr/share/kediray/logs.uc' <<'KEDIRAY_EOF_10'
'use strict';
// KediRay günlük okuyucu: sistem günlüğünden KediRay / Xray / hev satırlarını seviye ve bileşene ayırır,
// bilinen hatalara Türkçe açıklama + "ne yapmalı" ekler, hataları ayrıca (bellekte) daha uzun süre saklar.
//   ucode logs.uc read <ubus-json|logread-metni> [--text]  -> { entries, errors }
//   ucode logs.uc clear-errors | clear-stream
const fs = require('fs');
const RUN = getenv('KR_RUN') || '/var/etc/kediray';
const ERRF = RUN + '/errors.json';
const SINCEF = RUN + '/log.since';
const CMD = ARGV[0];
const now_ms = () => time() * 1000;

function out(x) { print(sprintf('%J\n', x)); }
function readj(p, d) { try { let t = fs.readfile(p); return t ? json(t) : d; } catch (e) { return d; } }
function writej(p, v) { fs.mkdir(RUN); fs.writefile(p + '.tmp', sprintf('%J', v)); fs.rename(p + '.tmp', p); }

if (CMD == 'clear-errors') { writej(ERRF, { cleared: now_ms(), last_id: readj(ERRF, {}).last_id ?? 0, items: [] }); out({ ok: true }); exit(0); }
if (CMD == 'clear-stream') { fs.writefile(SINCEF, '' + now_ms()); out({ ok: true }); exit(0); }

// ---------- bilinen hatalar: başlık + ne yapmalı ----------
const HINTS = [
	[/connection reset by peer/, 'Bağlantı karşı taraftan sıfırlandı',
	 'Operatör ya da ağ, VPN sunucusuna açılan bağlantıyı kesti. Ara sıra olursa normaldir (mobil hatlarda sık görülür). Sık tekrarlanıyorsa sunucunun IP/SNI\'si engelleniyor olabilir: farklı port, SNI ya da sunucu dene. Oyun/arama bu anlarda koparsa o uygulamayı "Direkt" yap.'],
	[/(i\/o timeout|dial tcp [^ ]+: .*timeout|connect: connection timed out)/, 'Sunucuya ulaşılamadı (zaman aşımı)',
	 'Sunucu kapalı, IP\'si değişmiş ya da hat bu adresi engelliyor olabilir. Kontrol Paneli\'nden "Ping" ile ölç; çalışmıyorsa aboneliği güncelle ya da başka sunucu seç.'],
	[/connection refused/, 'Sunucu bağlantıyı reddetti',
	 'Sunucu açık ama o portta dinleyen yok. x-ui\'de inbound\'un açık ve portun doğru olduğunu kontrol et.'],
	[/app\/dns.*Post "https:.*(context deadline exceeded|timeout)/, 'Direkt DNS (DoH) yanıt vermedi',
	 'Türkiye\'ye direkt çıkan adresler için kullanılan DoH sunucusuna ulaşılamadı; 5G/mobil hatlarda sık olur. Adres yedek DNS ile çözülür ama sorgu birkaç saniye gecikir. Sürekli oluyorsa Ayarlar → DNS → "Direkt DNS (yedek)" zaten devrede; ilk sırayı değiştirmek için "Direkt DNS" alanına https+local://8.8.8.8/dns-query yaz.'],
	[/(failed to dial to|failed to dial).*> *EOF/, 'Sunucu el sıkışma sırasında bağlantıyı kapattı (EOF)',
	 'VPN sunucusu ya da önündeki ters vekil/CDN, bağlantıyı daha el sıkışma bitmeden kapattı. Sık oluyorsa: sunucunun WebSocket path/host değerlerini x-ui ile karşılaştır, sunucu yükünü kontrol et, ya da ikinci bir sunucu ekle (biri takılınca otomatik diğerine geçer). Bu anlarda açılan yeni bağlantılar başarısız olur; telefonun bildirim bağlantısı da o an kopabilir.'],
	[/app\/dns.*(context deadline exceeded|timeout|i\/o timeout)/, 'DNS sorgusu zamanında yanıtlanmadı',
	 'Tünel o an yavaş ya da takılı. "Tünel takılırsa önbellekten yanıt ver" açıkken daha önce çözülmüş adresler etkilenmez. Sık görülüyorsa Ayarlar → DNS\'te "Cloudflare DoH" seçmeyi dene.'],
	[/failed to read response length/, 'DNS-over-TCP bağlantısı kapandı',
	 'Karşı taraf boştaki DNS bağlantısını kapattı. Bu satır görünüyorsa "Uzak DNS" TCP\'dedir: Ayarlar → DNS → Uzak DNS → "Cloudflare DoH" seç. Gerçek hatta doğrulandı: TCP\'de bağlantı düşünce sorgu ölüyor ve sayfa askıda kalıyor, DoH kendi içinde yeniden deniyor.'],
	[/(pinnedPeerCertSha256|peer cert is unrecognized)/, 'Sunucunun sertifikası değişmiş',
	 'Sabitlenen sertifika artık sunucuda değil (panel/sertifika yenilenmiş). KediRay bir sonraki başlatmada otomatik yeniden sabitler; hemen düzeltmek için panelde Bağlı sunucu → \"🔒 Sertifikayı sabitle\" (ya da: kediray pin)'],
	[/(x509|certificate (is not valid|signed by unknown)|failed to verify certificate)/, 'Sunucunun sertifikası doğrulanamadı',
	 'Sunucu kendinden imzalı ya da başka ada ait sertifika kullanıyor. Sunucuyu düzenle → "Sertifikayı doğrulama" işaretle; KediRay sertifikayı sabitler.'],
	[/(REALITY|reality).*(invalid|failed|verif)/, 'REALITY el sıkışması başarısız',
	 'Public key / short id / SNI sunucuyla uyuşmuyor. Linki x-ui\'den yeniden kopyalayıp sunucuyu düzenle.'],
	[/(bad handshake|unexpected (HTTP )?status|websocket: .*40[0-9])/, 'WebSocket el sıkışması reddedildi',
	 'Path ya da Host yanlış, veya sunucunun önündeki CDN/ters vekil isteği geri çevirdi. Linkteki path ve host değerlerini x-ui ile karşılaştır.'],
	[/(tls: handshake failure|remote error: tls|tls: .*EOF|first record does not look like a TLS)/, 'TLS el sıkışması başarısız',
	 'SNI/ALPN sunucuyla uyuşmuyor, sunucu TLS kullanmıyor ya da operatör bu el sıkışmasını engelliyor. Linkteki security/SNI ayarını kontrol et.'],
	[/(invalid user|invalid request user id|not a valid user)/, 'Kullanıcı (UUID/parola) geçersiz',
	 'Hesap sunucudan silinmiş ya da süresi dolmuş olabilir. x-ui\'de kullanıcının açık olduğunu kontrol et, aboneliği güncelle.'],
	[/failed to find an available destination/, 'Hiçbir bağlanma denemesi başarılı olmadı',
	 'Asıl sebep yukarıdaki ayrıntıda (en sağdaki kısım). Sunucuya erişim yoksa internet VPN\'den gidemez.'],
	[/too many open files/, 'Açık dosya sınırı aşıldı', 'Modemi yeniden başlat; sürekli oluyorsa bağlantı sayısı çok yüksek demektir.'],
	[/yapılandırma testi başarısız/, 'Xray bir ayarı kabul etmedi',
	 'Kontrol Paneli → "✓ Ayarları denetle" hatalı alanı ve satırı gösterir. Son değiştirdiğin sunucu/kuralı düzelt.'],
	[/Yapılandırma üretilemedi/, 'Yapılandırma üretilemedi', 'Kontrol Paneli → "✓ Ayarları denetle" ile hatalı sunucuyu bul.'],
	[/TUN aygıtını/, 'UDP tüneli (hev) başlamadı',
	 'hev-socks5-tunnel kurulu mu? SSH: apk add hev-socks5-tunnel kmod-tun (opkg ile de olur). Olmazsa Ayarlar → Trafik yakalama → TPROXY seç.'],
	[/kural yüklemedi|kuralları yüklenemedi/, 'Güvenlik duvarı kuralı yüklenemedi',
	 'SSH\'ta "fw4 check" çalıştır: /etc/nftables.d içindeki bozuk bir dosya tüm güvenlik duvarını durdurur.'],
	[/sertifika alınamadı/, 'Sunucunun sertifikası alınamadı',
	 'openssl-util kurulu mu (apk add openssl-util)? Sunucu açık ve adres doğru mu?'],
	[/abonelik (indirilemedi|boş)/, 'Abonelik güncellenemedi', 'Abonelik linkini tarayıcıda açıp çalıştığını kontrol et; VPN kapalıyken de erişilebilmeli.'],
	[/socks5 client (connect|socket)/, 'UDP tüneli Xray\'e bağlanamadı',
	 'Xray çalışmıyor ya da SOCKS portu değişmiş. VPN\'i yeniden başlat; sürmezse Günlük\'teki Xray hatalarına bak.'],
	[/çekirdeği bulunamadı/, 'Xray çekirdeği yok', 'SSH: kediray update-core'],
	[/API yanıt vermedi/, 'Sunucu seçimi uygulanamadı', 'Xray yanıt vermiyor; VPN\'i yeniden başlat.']
];
function hint(text) {
	for (let hnt in HINTS) if (match(text, hnt[0])) return { title: hnt[1], fix: hnt[2] };
	return null;
}

// ---------- satır ayrıştırma ----------
const LV = { Error: 'error', Warning: 'warn', Info: 'info', Debug: 'debug', E: 'error', W: 'warn', I: 'info', D: 'debug' };

function comp_of(tag, text) {
	if (tag == 'kediray') return 'KediRay';
	if (tag == 'hev') return 'UDP tüneli';
	if (match(text, /^app\/dns/)) return 'DNS';
	if (match(text, /^(transport\/internet|proxy\/(vless|vmess|trojan|shadowsocks|freedom)|app\/proxyman\/outbound|common\/retry)/)) return 'Sunucu bağlantısı';
	if (match(text, /^app\/observatory/)) return 'Sağlık ölçümü';
	if (match(text, /^(app\/proxyman\/inbound|proxy\/(dokodemo|socks)|from [0-9])/)) return 'Giriş';
	if (match(text, /^app\/router/)) return 'Yönlendirme';
	return 'Xray';
}

function summarize(text) {
	// "a/b: x > c/d: y > z" -> "x → z" (ilk ve son halka)
	let segs = map(split(text, ' > '), s => trim(replace(s, /^[a-z0-9_]+(\/[a-z0-9_.-]+)+: /, '')));
	segs = filter(segs, s => length(s));
	if (length(segs) <= 1) return segs[0] ?? text;
	let last = replace(segs[length(segs) - 1], /^(read|write|dial) (tcp|udp) [^ ]+: /, '');
	return segs[0] + ' → ' + last;
}

function parse(msg, prio, t, id, ts) {
	let m = match(msg, /^([A-Za-z0-9_.-]+)(\[[0-9]+\])?: ?(.*)$/s);
	if (!m) return null;
	let tag = m[1], rest = m[3], level = 'info', text = rest;
	if (tag == 'hev-socks5-tunnel') tag = 'hev';
	if (tag != 'kediray' && tag != 'xray' && tag != 'hev') return null;
	if (tag == 'xray') {
		let x = match(rest, /^[0-9]{4}\/[0-9]{2}\/[0-9]{2} [0-9:.]+ (\[(Error|Warning|Info|Debug)\] )?(.*)$/s);
		if (x) { text = x[3]; level = x[2] ? LV[x[2]] : 'info'; }
		else if (match(rest, /^(Failed to start|panic|fatal)/i)) level = 'error';
		// her başlangıçta çıkan kullanım dışı uyarıları bilgi seviyesine indir
		if (level == 'warn' && match(text, /deprecated|will be removed|Please (migrate|update)/)) level = 'info';
		if (match(text, /^Xray [0-9.]+ started$/)) level = 'info';
	} else if (tag == 'hev') {
		let x = match(rest, /^\[[^\]]+\] \[([EWID])\] (0x[0-9a-f]+ )?(.*)$/s);
		if (x) { level = LV[x[1]]; text = x[3]; }
	} else {
		let sev = prio != null ? (prio & 7) : 6;
		level = sev <= 3 ? 'error' : (sev == 4 ? 'warn' : (sev == 7 ? 'debug' : 'info'));
	}
	let h = (level == 'error' || level == 'warn') ? hint(text) : null;
	return { id: id, t: t, ts: ts, level: level, comp: comp_of(tag, text), text: tag == 'xray' ? summarize(text) : text,
		raw: text, title: h?.title, fix: h?.fix };
}

// ---------- oku ----------
if (CMD != 'read') { warn('kullanım: logs.uc read <dosya> [--text] | clear-errors | clear-stream\n'); exit(1); }
const src = fs.readfile(ARGV[1]) ?? '';
let ents = [];
if (ARGV[2] != '--text') {
	let j = null;
	try { j = json(src); } catch (e) { j = null; }
	for (let e in (j?.log ?? []))
		push(ents, parse(e.msg ?? '', e.priority, e.time, e.id, null));
} else {
	// logread metni: "Wed Sep 30 08:44:46 2026 daemon.info xray[12040]: ..."
	let n = 0;
	for (let l in split(src, '\n')) {
		let m = match(l, /^([A-Z][a-z]{2} [A-Z][a-z]{2} +[0-9]+ [0-9:]+ [0-9]{4}) [a-z]+\.([a-z]+) (.*)$/);
		if (!m) continue;
		let sev = { emerg: 0, alert: 1, crit: 2, err: 3, warn: 4, warning: 4, notice: 5, info: 6, debug: 7 }[m[2]] ?? 6;
		push(ents, parse(m[3], sev, null, ++n, m[1]));
	}
}
ents = filter(ents, e => e);

// Hatalar: bellekte kalıcı, aynı hata gruplanır (sayaç + ilk/son zaman)
let st = readj(ERRF, { cleared: 0, last_id: 0, items: [] });
let byKey = {};
for (let it in st.items) byKey[it.key] = it;
let maxid = st.last_id ?? 0;
let restarted = length(ents) && ents[length(ents) - 1].id != null && ents[length(ents) - 1].id < maxid;
for (let e in ents) {
	if (e.level != 'error') continue;
	if (e.t != null && e.t <= (st.cleared ?? 0)) continue;
	if (e.id != null && !restarted && e.id <= maxid) continue;
	let key = e.comp + '|' + replace(replace(e.title ?? e.text, /[0-9]+(\.[0-9]+){3}(:[0-9]+)?/g, '#'), /[0-9]+/g, '#');
	let it = byKey[key];
	if (!it) {
		it = byKey[key] = { key: key, first: e.t, count: 0, comp: e.comp, title: e.title, fix: e.fix };
		push(st.items, it);
	}
	it.count++;
	it.last = e.t;
	it.ts = e.ts;
	it.text = e.text;
	it.raw = e.raw;
}
for (let e in ents) if (e.id != null && e.id > maxid) maxid = e.id;
st.last_id = maxid;
st.items = slice(sort(st.items, (a, b) => (b.last ?? 0) - (a.last ?? 0)), 0, 100);
writej(ERRF, st);

const since = int(fs.readfile(SINCEF) ?? '0') || 0;
let stream = filter(ents, e => e.t == null || e.t > since);
if (length(stream) > 500) stream = slice(stream, length(stream) - 500);
out({ now: now_ms(), since: since, entries: stream, errors: st.items });
KEDIRAY_EOF_10
cat > '/usr/share/kediray/watch.uc' <<'KEDIRAY_EOF_11'
'use strict';
// KediRay bağlantı kaydedicisi: bir cihazın bağlantılarını conntrack'ten izler.
// Hangi bağlantı hangi yoldan (VPN/Direkt) gitti, ne kadar yaşadı, kopunca boşta mıydı?
// Kullanım: ucode watch.uc <saniye> [istemci-ip] [tun-mark] [örnekleme-ms]
const fs = require('fs');
const SECS = int(ARGV[0]) || 180;
const IP = ARGV[1] ?? '';
const TUNMARK = int(ARGV[2]) || 738;
const IV = int(ARGV[3]) || 1000;
const CT = getenv('KR_CT') || '/proc/net/nf_conntrack';
// Test kancası: KR_CT bir dizinse her örnekte <dizin>/<sıra>.txt okunur, beklemeden sanal saat ilerler
const FAKE = fs.stat(CT)?.type == 'directory';
let clock = 0;

function snapshot(i) {
	if (FAKE) return fs.readfile(CT + '/' + i + '.txt') ?? fs.readfile(CT + '/last.txt') ?? '';
	let t = fs.readfile(CT);
	if (t === null) {
		let p = fs.popen('conntrack -L 2>/dev/null');
		if (p) { t = p.read('all'); p.close(); }
	}
	return t ?? '';
}
function now_s() { return FAKE ? clock : time(); }
function tick() { if (FAKE) clock += IV / 1000; else sleep(IV); }
const PRIV = /^(10\.|192\.168\.|127\.|169\.254\.|172\.(1[6-9]|2[0-9]|3[01])\.|22[4-9]\.|23[0-9]\.|255\.)/;

// Bir conntrack satırını çözümle (hem /proc/net/nf_conntrack hem conntrack -L biçimi)
function parse(l) {
	let pr = match(l, /(^| )(tcp|udp) /);
	if (!pr) return null;
	let srcs = match(l, /src=([0-9.]+)/g), dsts = match(l, /dst=([0-9.]+)/g);
	let sp = match(l, /sport=([0-9]+)/), dp = match(l, /dport=([0-9]+)/);
	if (!srcs || !dsts || !sp || !dp) return null;
	let to = match(l, /([0-9]+) +[A-Z_]* *src=/);
	let mk = match(l, /mark=([0-9]+)/);
	let st = match(l, / ([A-Z][A-Z_]+) +src=/);
	return {
		proto: pr[2], src: srcs[0][1], dst: dsts[0][1], sport: int(sp[1]), dport: int(dp[1]),
		// Tünelden mi? TCP: çekirdek 127.0.0.1'e yönlendirir (yanıt tarafının kaynağı 127.0.0.1)
		//              UDP: paket TUN işaretini taşır
		vpn: (length(srcs) > 1 && srcs[1][1] != dsts[0][1]) || (mk && int(mk[1]) == TUNMARK),
		timeout: to ? int(to[1]) : 0,
		state: st ? st[1] : ''
	};
}

let flows = {}, t0 = now_s(), n = 0;
while (now_s() - t0 < SECS) {
	let now = now_s(), seen = {};
	for (let l in split(snapshot(n), '\n')) {
		let c = parse(l);
		if (!c) continue;
		if (length(IP) && c.src != IP) continue;
		if (match(c.dst, PRIV)) continue;
		let k = c.proto + '|' + c.src + ':' + c.sport + '>' + c.dst + ':' + c.dport;
		seen[k] = true;
		let f = flows[k];
		if (!f) {
			flows[k] = f = { proto: c.proto, client: c.src, dst: c.dst, port: c.dport,
				vpn: c.vpn, flip: false, t0: now, t1: now, base: c.timeout, lastTo: c.timeout, idle: 0, state: c.state, open: true };
		}
		// Yol ortada değiştiyse (aynı bağlantı) işaretle
		if (c.vpn != f.vpn) { f.flip = true; f.vpn = c.vpn; }
		if (c.timeout > f.base) f.base = c.timeout;        // sayaç her pakette tazelenir -> tepe = taban
		f.idle = f.base - c.timeout > f.idle ? f.base - c.timeout : f.idle;
		f.lastTo = c.timeout; f.state = c.state; f.t1 = now; f.open = true;
	}
	for (let k, f in flows)
		if (f.open && !seen[k]) { f.open = false; f.end = now_s(); f.endIdle = f.base - f.lastTo; }
	n++;
	tick();
}
let tend = now_s();
for (let k, f in flows) if (f.open) { f.end = null; f.endIdle = f.base - f.lastTo; }

// Aynı sunucu ağına (cihaz + hedef /24) art arda açılan bağlantılarda yol değişmiş mi?
// Oyun ışınlanırken başka bir kanal sunucusuna/portuna bağlanır: biri Direkt biri VPN ise sunucu IP değişti sanıp atar.
let byTarget = {};
for (let k, f in flows) {
	let net = join('.', slice(split(f.dst, '.'), 0, 3)) + '.0/24';
	let key = f.client + ' -> ' + net;
	byTarget[key] ??= [];
	push(byTarget[key], f);
}
let flips = [];
for (let key, l in byTarget) {
	let sl = sort(l, (a, b) => a.t0 - b.t0), prev = null;
	for (let f in sl) {
		if (prev != null && prev.vpn != f.vpn)
			push(flips, { target: key, t: f.t0, from: prev.vpn ? 'VPN' : 'Direkt', to: f.vpn ? 'VPN' : 'Direkt',
				prev_dst: prev.dst, prev_port: prev.port, dst: f.dst, port: f.port });
		prev = f;
	}
	for (let f in sl) if (f.flip)
		push(flips, { target: key, t: f.t0, from: 'aynı bağlantı içinde', to: f.vpn ? 'VPN' : 'Direkt',
			prev_dst: f.dst, prev_port: f.port, dst: f.dst, port: f.port });
}

let out = [];
for (let k, f in flows) push(out, {
	proto: f.proto, client: f.client, dst: f.dst, port: f.port, vpn: f.vpn,
	t0: f.t0, end: f.end, dur: (f.end ?? tend) - f.t0, idle: f.idle, end_idle: f.endIdle,
	// kopma anında boşta değilse: bağlantı kullanılırken kesilmiş (oyundan atılma / zorla kapatma)
	cut_active: f.end != null && f.endIdle < 15 && ((f.end ?? tend) - f.t0) >= 20,
	web: f.port == 80 || f.port == 443, state: f.state, flip: f.flip
});
// Boşta kalma dayanıklılığı: bildirim bağlantısını kim öldürüyor?
// Uzun süre boşta kaldıktan sonra ölen bağlantılar -> araya giren bir şey boştaki bağlantıyı kapatıyor.
function idle_kill(vpn) {
	let min = null, alive = 0;
	for (let f in out) {
		if (f.vpn != vpn || f.web) continue;
		if (f.end != null && f.end_idle >= 30 && f.dur >= 30) { if (min == null || f.end_idle < min) min = f.end_idle; }
		if (f.end == null && f.idle > alive) alive = f.idle;
	}
	return { killed_at: min, survived: alive };
}
// conntrack dolmuşsa kayıtlar düşer -> hem oyun hem bildirim bağlantısı sebepsiz kopar
function ctinfo() {
	let rd = f => { let v = fs.readfile(f); return v ? int(trim(v)) : null; };
	let c = rd('/proc/sys/net/netfilter/nf_conntrack_count'), m = rd('/proc/sys/net/netfilter/nf_conntrack_max');
	return (c == null || !m) ? null : { count: c, max: m, pct: c * 100 / m };
}
print(sprintf('%J\n', {
	t0: t0, t1: tend, secs: tend - t0, samples: n, client: IP, conntrack: ctinfo(),
	idle: { vpn: idle_kill(true), direct: idle_kill(false) },
	flows: sort(out, (a, b) => (a.web - b.web) || (b.dur - a.dur)),
	flips: sort(flips, (a, b) => a.t - b.t)
}));
KEDIRAY_EOF_11
cat > '/usr/share/kediray/traffic.uc' <<'KEDIRAY_EOF_12'
'use strict';
// KediRay trafik sayacı: VPN (tünelin dış baytları, nft sayacı) ve Direkt (WAN toplamı − VPN) günlük kovalarda.
// 1.19.6: ek olarak cihaz bazlı (LAN IP'si başına) indirme/yükleme günlük kovaları.
//   ucode traffic.uc sample    (KR_VR KR_VT KR_WR KR_WT KR_DEVF ortamdan)   -> farkı bugünün kovasına ekler
//   ucode traffic.uc report    (aynı ortam)                          -> şu anki sayaçlar + bugün/hafta/ay/30 gün + cihazlar
//   ucode traffic.uc save | restore | reset
const fs = require('fs');
const RUN = getenv('KR_RUN') || '/var/etc/kediray';
const RAMF = RUN + '/traffic.json';
const FLASHF = getenv('KR_TRAFFIC_FLASH') || '/etc/kediray.traffic.json';
const CMD = ARGV[0];

function readj(p) { try { let t = fs.readfile(p); return t ? json(t) : null; } catch (e) { return null; } }
function writej(p, v) { fs.writefile(p + '.tmp', sprintf('%J', v)); fs.rename(p + '.tmp', p); }
function n(v) { let x = int(v ?? 0); return x != x ? 0 : x; }
function dkey(ts) { let t = localtime(ts); return sprintf('%04d-%02d-%02d', t.year, t.mon, t.mday); }
function cur() { return { vr: n(getenv('KR_VR')), vt: n(getenv('KR_VT')), wr: n(getenv('KR_WR')), wt: n(getenv('KR_WT')), t: time() }; }
function load() {
	let s = readj(RAMF) ?? readj(FLASHF) ?? {};
	s.days ??= {};
	s.dev ??= {};
	return s;
}
// sayaç sıfırlanmışsa (tablo yeniden kuruldu / modem yeniden başladı) fark = şimdiki değer
function d(c, l) { return c >= l ? c - l : c; }

function delta(s, c) {
	let l = s.last;
	if (!l) return null;
	let vr = d(c.vr, l.vr), vt = d(c.vt, l.vt), wr = d(c.wr, l.wr), wt = d(c.wt, l.wt);
	// WAN sayacı VPN'den küçük kalamaz; kalırsa (farklı anlarda okuma) direkt 0 sayılır
	return { vr: vr, vt: vt, dr: wr > vr ? wr - vr : 0, dt: wt > vt ? wt - vt : 0 };
}
function add(b, x) { b.vr = n(b.vr) + x.vr; b.vt = n(b.vt) + x.vt; b.dr = n(b.dr) + x.dr; b.dt = n(b.dt) + x.dt; }

// ---------- cihaz bazlı sayaçlar ----------
// KR_DEVF satırları: "ip<TAB>rx|tx<TAB>bayt"  (rx = cihaza gelen, tx = cihazdan giden)
function readdev() {
	let r = {}, f = getenv('KR_DEVF');
	if (!f) return r;
	for (let l in split(fs.readfile(f) ?? '', '\n')) {
		let p = split(l, '\t');
		if (length(p) < 3 || !match(p[0], /^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$/)) continue;
		if (p[1] != 'rx' && p[1] != 'tx') continue;
		r[p[0]] ??= { rx: 0, tx: 0 };
		r[p[0]][p[1]] = n(p[2]);
	}
	return r;
}
function leases() { // ip -> { mac, name }
	let r = {};
	for (let l in split(fs.readfile('/tmp/dhcp.leases') ?? '', '\n')) {
		let f = split(l, ' ');
		if (length(f) >= 4) r[f[2]] = { mac: lc(f[1]), name: f[3] != '*' ? f[3] : '' };
	}
	return r;
}
function devlive(e, c) { // son örneklemeden bu yana (henüz kovaya yazılmamış) fark
	if (!c) return { rx: 0, tx: 0 };
	let l = e.last ?? { rx: 0, tx: 0 };
	return { rx: d(n(c.rx), n(l.rx)), tx: d(n(c.tx), n(l.tx)) };
}
function devsample(s, c) {
	let cd = readdev(), ls = leases(), day = dkey(c.t);
	for (let ip, v in cd) {
		s.dev[ip] ??= { days: {} };
		let e = s.dev[ip];
		let x = devlive(e, v);
		e.days ??= {};
		e.days[day] ??= { rx: 0, tx: 0 };
		e.days[day].rx = n(e.days[day].rx) + x.rx;
		e.days[day].tx = n(e.days[day].tx) + x.tx;
		e.last = { rx: n(v.rx), tx: n(v.tx) };
		if (ls[ip]) { e.mac = ls[ip].mac; if (ls[ip].name) e.name = ls[ip].name; }
		e.seen = c.t;
	}
	// 100 günden eski günleri ve boş kalan cihazları at
	let cut = dkey(c.t - 100 * 86400);
	for (let ip in keys(s.dev)) {
		let e = s.dev[ip];
		for (let k in keys(e.days ?? {})) if (k < cut) delete e.days[k];
		if (!length(keys(e.days ?? {})) && !cd[ip]) delete s.dev[ip];
	}
}

if (CMD == 'sample') {
	let s = load(), c = cur(), x = delta(s, c);
	if (x) { s.days[dkey(c.t)] ??= {}; add(s.days[dkey(c.t)], x); }
	s.last = c;
	devsample(s, c);
	// 100 günden eskiyi at
	let ks = sort(keys(s.days));
	while (length(ks) > 100) delete s.days[shift(ks)];
	fs.mkdir(RUN);
	writej(RAMF, s);
	if (ARGV[1] == 'save' || time() - n(s.saved) >= 3600) { s.saved = time(); writej(RAMF, s); writej(FLASHF, s); }
	print('ok\n');
	exit(0);
}
if (CMD == 'save') { let s = load(); s.saved = time(); fs.mkdir(RUN); writej(RAMF, s); writej(FLASHF, s); print('ok\n'); exit(0); }
if (CMD == 'restore') {
	if (!readj(RAMF) && readj(FLASHF)) {
		fs.mkdir(RUN);
		let s = readj(FLASHF);
		delete s.last;
		for (let ip, e in (s.dev ?? {})) delete e.last;   // modem açıldı: nft sayaçları sıfırdan başlar
		writej(RAMF, s);
	}
	print('ok\n');
	exit(0);
}
if (CMD == 'reset') { fs.unlink(RAMF); fs.unlink(FLASHF); print('ok\n'); exit(0); }

if (CMD == 'report') {
	let s = load(), c = cur(), live = delta(s, c) ?? { vr: 0, vt: 0, dr: 0, dt: 0 };
	let today = dkey(c.t);
	let day = k => ({ vr: n(s.days[k]?.vr), vt: n(s.days[k]?.vt), dr: n(s.days[k]?.dr), dt: n(s.days[k]?.dt) });
	let sum = (from) => {
		let t = { vr: 0, vt: 0, dr: 0, dt: 0 };
		for (let k, v in s.days) if (k >= from && k <= today) add(t, day(k));
		add(t, live);   // son örneklemeden bu yana (henüz kovaya yazılmamış) kısım
		return t;
	};
	let lt = localtime(c.t);
	// haftanın başı Pazartesi
	let wd = lt.wday == 0 ? 6 : lt.wday - 1;
	let week = dkey(c.t - wd * 86400);
	let month = sprintf('%04d-%02d-01', lt.year, lt.mon);
	let yest = dkey(c.t - 86400);
	let t_today = day(today); add(t_today, live);
	let hist = [];
	for (let i = 29; i >= 0; i--) {
		let k = dkey(c.t - i * 86400), v = day(k);
		if (k == today) add(v, live);
		push(hist, { day: k, ...v });
	}
	let first = sort(keys(s.days))[0];

	// cihazlar: bugün / hafta / ay / toplam (rx = indirme, tx = yükleme) + canlı hız için ham sayaç
	let cd = readdev(), devs = [];
	for (let ip, e in s.dev) {
		let lv = devlive(e, cd[ip]);
		let dsum = (from) => {
			let t = { rx: 0, tx: 0 };
			for (let k, v in (e.days ?? {})) if (k >= from && k <= today) { t.rx += n(v.rx); t.tx += n(v.tx); }
			t.rx += lv.rx; t.tx += lv.tx;
			return t;
		};
		let tot = dsum('0000-00-00');
		if (tot.rx + tot.tx <= 0) continue;
		push(devs, { ip: ip, name: e.name ?? '', mac: e.mac ?? '', counter: cd[ip] ?? null,
			today: dsum(today), week: dsum(week), month: dsum(month), total: tot });
	}
	devs = sort(devs, (a, b) => ((b.today.rx + b.today.tx) - (a.today.rx + a.today.tx)) || ((b.total.rx + b.total.tx) - (a.total.rx + a.total.tx)));
	if (length(devs) > 40) devs = slice(devs, 0, 40);

	print(sprintf('%J\n', {
		t: c.t, counters: c, today: t_today, yesterday: day(yest), week: sum(week), month: sum(month),
		total: sum('0000-00-00'), since: first, days: hist, devices: devs
	}));
	exit(0);
}
warn('kullanım: traffic.uc sample [save] | report | save | restore | reset\n');
exit(1);
KEDIRAY_EOF_12
cat > '/www/luci-static/resources/view/kediray/status.js' <<'KEDIRAY_EOF_13'
'use strict';
'require view';
'require fs';
'require ui';
'require poll';
'require dom';

/* KediRay - Kontrol paneli */

/* Güvenli öğe oluşturucu: LuCI'nin E()'si iç içe dizileri "[object HTMLButtonElement]," diye metne çevirir ve
 * tek bir metni innerHTML olarak basar (abonelikten gelen bir sunucu adı HTML çalıştırabilir). h() dizileri
 * düzleştirir, boşları atar ve her metni düz metin düğümü olarak ekler. */
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

function run(args) {
	return fs.exec(CLI, args).catch(e => ({ code: 1, stdout: '', stderr: String(e) }));
}
function runJson(args) {
	return run(args).then(r => { try { return JSON.parse(r.stdout || 'null'); } catch (e) { return null; } });
}
function fmtBytes(b) {
	b = +b || 0;
	const u = ['B', 'KB', 'MB', 'GB', 'TB']; let i = 0;
	while (b >= 1024 && i < u.length - 1) { b /= 1024; i++; }
	return (i ? b.toFixed(1) : b) + ' ' + u[i];
}
function fmtRate(b) { return fmtBytes(b) + '/s'; }
// süre: 3 gün 5 sa 22 dk · 5 sa 22 dk 10 sn · 14 dk 49 sn · 49 sn
function fmtDur(s) {
	s = Math.max(0, Math.floor(+s || 0));
	const g = Math.floor(s / 86400), h2 = Math.floor(s % 86400 / 3600), m = Math.floor(s % 3600 / 60), sn = s % 60;
	const p = v => String(v).padStart(2, '0');
	if (g) return g + ' gün ' + h2 + ' sa ' + p(m) + ' dk';
	if (h2) return h2 + ' sa ' + p(m) + ' dk ' + p(sn) + ' sn';
	if (m) return m + ' dk ' + p(sn) + ' sn';
	return sn + ' sn';
}
/* Canlı sayaç: değer render anında damgalanır, her saniye tarayıcıda ilerler
   (modem saatiyle tarayıcı saati farklı olabilir; fark değil, geçen süre sayılır) */
function live(seconds, cls) {
	const v = Math.max(0, Math.floor(+seconds || 0));
	return h('span', {
		'class': 'kr-live' + (cls ? ' ' + cls : ''),
		'data-base': String(v),
		'data-at': String(Date.now())
	}, fmtDur(v));
}
function tickLive(root) {
	const now = Date.now();
	(root || document).querySelectorAll('.kr-live').forEach(e => {
		const base = +e.getAttribute('data-base'), at = +e.getAttribute('data-at');
		if (!isFinite(base) || !isFinite(at)) return;
		e.textContent = fmtDur(base + (now - at) / 1000);
	});
}
// üst köşeleri r kadar yuvarlak, tabanı düz çubuk yolu (SVG path)
function roundTop(x, y, w, hgt, r) {
	r = Math.max(0, Math.min(r, hgt, w / 2));
	const f = v => v.toFixed(1);
	return 'M' + f(x) + ',' + f(y + hgt) + ' V' + f(y + r) + ' Q' + f(x) + ',' + f(y) + ' ' + f(x + r) + ',' + f(y) +
		' H' + f(x + w - r) + ' Q' + f(x + w) + ',' + f(y) + ' ' + f(x + w) + ',' + f(y + r) + ' V' + f(y + hgt) + ' Z';
}
// rtt = gerçek ağ gecikmesi (sunucuya TCP), ms = tünel testi (yeni bağlantı + tam web isteği)
function pingBadge(ms, rtt, warm) {
	if (ms == null && rtt == null) return h('span', { 'class': 'kr-ping kr-na' }, '—');
	if (ms != null && ms < 0) return h('span', { 'class': 'kr-ping kr-bad', 'title': 'Tünel kurulamadı' }, 'yok');
	const tip = 'Ping: modemden sunucuya gerçek ağ gecikmesi.\n' +
		'Tünel (yeni): sıfırdan bağlantı açıp tam bir web isteği yapma süresi — TCP + TLS + WebSocket el sıkışmaları dahil (v2rayNG "gerçek gecikme").\n' +
		'Tünel (açık): aynı bağlantıdan giden ikinci isteğin süresi — sayfaların ve oyunun gerçekte hissettiği gecikme budur.';
	const parts = [];
	if (rtt != null && rtt > 0)
		parts.push(h('span', { 'class': 'kr-ping ' + (rtt < 60 ? 'kr-good' : rtt < 150 ? 'kr-mid' : 'kr-bad') }, rtt + ' ms'));
	if (warm != null && warm > 0)
		parts.push(h('span', { 'class': 'kr-sub', 'style': 'font-size:.8em;margin-left:4px' }, 'tünel ' + warm));
	else if (ms != null && ms > 0 && rtt != null && rtt > 0)
		parts.push(h('span', { 'class': 'kr-sub', 'style': 'font-size:.8em;margin-left:4px' }, 'tünel ' + ms));
	if (ms != null && ms > 0 && warm != null && warm > 0 && ms > warm)
		parts.push(h('span', { 'class': 'kr-sub', 'style': 'font-size:.8em;margin-left:4px;opacity:.55' }, '(ilk ' + ms + ')'));
	if (!parts.length)
		return h('span', { 'class': 'kr-ping ' + (ms < 150 ? 'kr-good' : ms < 400 ? 'kr-mid' : 'kr-bad'), 'title': tip }, ms + ' ms');
	return h('span', { 'style': 'white-space:nowrap', 'title': tip }, parts);
}
function btn(label, cls, fn, title) {
	return h('button', { 'class': 'btn cbi-button ' + (cls || ''), 'title': title || '', 'click': ui.createHandlerFn(this, fn) }, label);
}

/* Katı JSON denetleyici: ilk hatanın satır/sütununu ve Türkçe açıklamasını verir (null = hatasız) */
function jsonCheck(s) {
	let i = 0, err = null;
	const n = s.length;
	const ch = () => (i < n ? s[i] : '');
	const fail = m => { if (!err) err = { pos: i, msg: m }; return false; };
	const ws = () => { while (i < n && ' \t\r\n'.indexOf(s[i]) >= 0) i++; };
	const str = () => {
		i++;
		while (i < n) {
			const c = s[i];
			if (c === '"') { i++; return true; }
			if (c === '\\') { i += 2; continue; }
			if (c === '\n') return fail('Metin bitmeden satır sonu geldi (kapanış tırnağı " eksik)');
			i++;
		}
		return fail('Kapanış tırnağı " eksik');
	};
	const num = () => {
		const m = /^-?(0|[1-9]\d*)(\.\d+)?([eE][+-]?\d+)?/.exec(s.slice(i, i + 64));
		if (!m) return fail('Geçersiz sayı');
		i += m[0].length; return true;
	};
	let value;
	const obj = () => {
		i++; ws();
		if (ch() === '}') { i++; return true; }
		for (;;) {
			ws();
			const c = ch();
			if (c === '}') return fail("Son öğeden sonra fazladan virgül var (',' sil)");
			if (c === "'") return fail('Anahtarlar tek tırnakla değil çift tırnakla (") yazılmalı');
			if (c !== '"') return fail(i >= n ? "'}' kapanmamış (metin erken bitti)" : 'Anahtar çift tırnak (") içinde olmalı');
			if (!str()) return false;
			ws();
			if (ch() !== ':') return fail("Anahtardan sonra ':' bekleniyordu");
			i++;
			if (!value()) return false;
			ws();
			const d = ch();
			if (d === ',') { i++; continue; }
			if (d === '}') { i++; return true; }
			if (i >= n) return fail("'}' kapanmamış (metin erken bitti)");
			return fail("',' veya '}' bekleniyordu (önceki satırın sonunda virgül eksik olabilir)");
		}
	};
	const arr = () => {
		i++; ws();
		if (ch() === ']') { i++; return true; }
		for (;;) {
			ws();
			if (ch() === ']') return fail("Son öğeden sonra fazladan virgül var (',' sil)");
			if (!value()) return false;
			ws();
			const d = ch();
			if (d === ',') { i++; continue; }
			if (d === ']') { i++; return true; }
			if (i >= n) return fail("']' kapanmamış (metin erken bitti)");
			return fail("',' veya ']' bekleniyordu");
		}
	};
	value = () => {
		ws();
		const c = ch();
		if (c === '{') return obj();
		if (c === '[') return arr();
		if (c === '"') return str();
		if (c === '-' || (c >= '0' && c <= '9')) return num();
		if (s.startsWith('true', i) || s.startsWith('null', i)) { i += 4; return true; }
		if (s.startsWith('false', i)) { i += 5; return true; }
		if (c === "'") return fail('Metinler tek tırnakla değil çift tırnakla (") yazılmalı');
		if (i >= n) return fail('Beklenmedik son: değer bekleniyordu');
		return fail("Geçersiz değer '" + c + "' (metinler çift tırnak içinde olmalı)");
	};
	if (value()) { ws(); if (i < n) fail('JSON bittikten sonra fazladan içerik var'); }
	if (!err) return null;
	let line = 1, col = 1;
	for (let k = 0; k < err.pos && k < n; k++) { if (s[k] === '\n') { line++; col = 1; } else col++; }
	return { line, col, msg: err.msg, pos: err.pos };
}

/* Form alanları: [ad, etiket, tür, seçenekler, görünür mü?] */
const isV = f => f.protocol === 'vless' || f.protocol === 'vmess';
const notSS = f => f.protocol !== 'shadowsocks';
const hasPath = f => notSS(f) && (['ws', 'xhttp', 'httpupgrade'].includes(f.network) || (f.network === 'tcp' && f.header_type === 'http'));
const isTLS = f => notSS(f) && (f.tls === 'tls' || f.tls === 'reality');
const FIELDS = [
	['protocol', 'Protokol', 'select', [['vless', 'VLESS'], ['vmess', 'VMess'], ['trojan', 'Trojan'], ['shadowsocks', 'Shadowsocks']]],
	['address', 'Adres (IP ya da alan adı)', 'text'],
	['port', 'Port', 'text'],
	['uuid', 'UUID', 'text', null, isV],
	['password', 'Parola', 'text', null, f => f.protocol === 'trojan' || f.protocol === 'shadowsocks'],
	['method', 'Şifreleme', 'select', ['aes-128-gcm', 'aes-256-gcm', 'chacha20-poly1305', 'chacha20-ietf-poly1305', 'xchacha20-poly1305',
		'2022-blake3-aes-128-gcm', '2022-blake3-aes-256-gcm', '2022-blake3-chacha20-poly1305'], f => f.protocol === 'shadowsocks'],
	['flow', 'Flow', 'select', [['', 'Yok'], ['xtls-rprx-vision', 'xtls-rprx-vision']], f => f.protocol === 'vless'],
	['network', 'Aktarım', 'select', [['ws', 'WebSocket (ws)'], ['tcp', 'TCP / raw'], ['grpc', 'gRPC'], ['xhttp', 'XHTTP'], ['httpupgrade', 'HTTPUpgrade']], notSS],
	['header_type', 'TCP başlık', 'select', [['', 'Yok'], ['http', 'HTTP gizleme']], f => notSS(f) && f.network === 'tcp'],
	['path', 'Yol (path)', 'text', null, hasPath],
	['host', 'Host', 'text', null, hasPath],
	['service_name', 'gRPC servis adı', 'text', null, f => notSS(f) && f.network === 'grpc'],
	['xhttp_mode', 'XHTTP modu', 'select', ['auto', 'packet-up', 'stream-up', 'stream-one'], f => notSS(f) && f.network === 'xhttp'],
	['tls', 'Güvenlik', 'select', [['none', 'Yok'], ['tls', 'TLS'], ['reality', 'REALITY']], notSS],
	['sni', 'SNI', 'text', null, isTLS],
	['fp', 'Parmak izi (uTLS)', 'select', [['', 'Yok (v2rayNG varsayılanı)'], 'chrome', 'firefox', 'safari', 'ios', 'android', 'edge', 'random', 'randomized'], isTLS],
	['alpn', 'ALPN', 'text', null, f => notSS(f) && f.tls === 'tls'],
	['insecure', 'Sertifikayı doğrulama (otomatik sabitlenir)', 'checkbox', null, f => notSS(f) && f.tls === 'tls'],
	['pbk', 'REALITY public key', 'text', null, f => notSS(f) && f.tls === 'reality'],
	['sid', 'REALITY short id', 'text', null, f => notSS(f) && f.tls === 'reality'],
	['spx', 'REALITY spiderX', 'text', null, f => notSS(f) && f.tls === 'reality']
];
const JSON_TEMPLATE = JSON.stringify({
	protocol: 'vless',
	settings: { vnext: [{ address: '1.2.3.4', port: 443, users: [{ id: 'UUID-BURAYA', encryption: 'none' }] }] },
	streamSettings: { network: 'ws', security: 'tls', tlsSettings: { serverName: 'alan.adi' }, wsSettings: { path: '/', host: 'alan.adi' } }
}, null, 2);
const STAGE = { syntax: 'Yazım hatası', fields: 'Eksik ya da hatalı alan', xray: 'Xray bu ayarı kabul etmedi', save: 'Kaydedilemedi', uci: 'Ayar dosyası okunamadı', node: 'Sunucu hatası', gen: 'Yapılandırma üretilemedi' };

const CSS = `
.kr-grid{display:grid;grid-template-columns:repeat(auto-fit,minmax(300px,1fr));gap:14px;margin-bottom:14px}
.kr-card{border:1px solid rgba(128,128,128,.25);border-radius:10px;padding:14px 16px;background:rgba(128,128,128,.04)}
.kr-card h3{margin:0 0 10px;font-size:1.05em;opacity:.85}
.kr-ch{cursor:pointer;user-select:none;display:flex;align-items:center;gap:7px}
.kr-ch:hover{opacity:1}
.kr-caret{font-size:.85em;opacity:.7;width:12px}
.kr-ct{flex:1}
.kr-cbody.kr-fold{display:none}
.kr-blocked td{opacity:.75}
.kr-big{font-size:1.35em;font-weight:600;margin:2px 0 6px;word-break:break-all}
.kr-sub{opacity:.7;font-size:.9em}
.kr-addr{margin-top:6px;font-size:.92em;word-break:break-all}
.kr-mono{font-family:ui-monospace,Menlo,Consolas,monospace;background:rgba(128,128,128,.14);border-radius:5px;padding:1px 6px;user-select:all}
.kr-live{font-variant-numeric:tabular-nums}
.kr-row{display:flex;gap:8px;flex-wrap:wrap;align-items:center;margin-top:10px}
.kr-dot{display:inline-block;width:10px;height:10px;border-radius:50%;margin-right:6px;vertical-align:middle}
.kr-on{background:#22a355}.kr-off{background:#999}.kr-err{background:#d23f3f}
.kr-ping{display:inline-block;min-width:54px;text-align:center;padding:1px 8px;border-radius:10px;font-size:.85em;font-weight:600}
.kr-good{background:rgba(34,163,85,.18);color:#1b8a47}.kr-mid{background:rgba(230,160,20,.2);color:#a86d00}
.kr-bad{background:rgba(210,63,63,.18);color:#b52f2f}.kr-na{background:rgba(128,128,128,.15)}
.kr-seg{display:inline-flex;border:1px solid rgba(128,128,128,.4);border-radius:8px;overflow:hidden}
.kr-seg button{border:0;border-radius:0;margin:0;padding:4px 14px;background:transparent;cursor:pointer;color:inherit;white-space:nowrap;word-break:keep-all}
.kr-seg button.kr-act{background:#2a7de1;color:#fff}
.kr-seg button.kr-act.kr-direct{background:#22a355}
.kr-seg button.kr-act.kr-block{background:#d23f3f;color:#fff}
.kr-seg button.kr-blockbtn{color:#d23f3f}
.kr-seg button.kr-blockbtn:hover{background:rgba(210,63,63,.15)}
.kr-seg-sm button{padding:4px 10px;font-size:.92em}
@media (max-width:700px){.kr-seg-sm{display:grid;grid-template-columns:1fr 1fr}.kr-seg-sm button{padding:6px 8px;border-top:1px solid rgba(128,128,128,.25)}.kr-seg-sm button:nth-child(-n+2){border-top:0}.kr-seg-sm button:nth-child(odd){border-right:1px solid rgba(128,128,128,.25)}}
.kr-warn{border:1px solid #e0a100;background:rgba(224,161,0,.12);border-radius:8px;padding:8px 10px;margin:0 0 10px;font-size:.92em}
.kr-seg.kr-dim{opacity:.4}
.kr-seg.kr-dim button.kr-act{background:transparent;color:inherit}
.kr-app{display:flex;justify-content:space-between;align-items:center;padding:7px 0;border-bottom:1px dashed rgba(128,128,128,.25)}
.kr-app:last-child{border-bottom:0}
.kr-stat{display:grid;grid-template-columns:auto 1fr 1fr;gap:4px 14px;font-variant-numeric:tabular-nums}
.kr-tag{display:inline-block;padding:0 6px;border-radius:6px;background:rgba(42,125,225,.15);font-size:.8em;margin-left:6px}
.kr-tag.kr-tag-red{background:rgba(210,63,63,.2);color:#e05252}
.kr-table td,.kr-table th{padding:6px 8px!important;vertical-align:middle}
.kr-active{background:rgba(42,125,225,.08)}
.kr-tabs{display:flex;gap:4px;margin:8px 0}
.kr-tabs button{border:1px solid rgba(128,128,128,.4);background:transparent;color:inherit;padding:5px 16px;border-radius:8px 8px 0 0;cursor:pointer}
.kr-tabs button.kr-act{background:#2a7de1;color:#fff;border-color:#2a7de1}
.kr-form{display:grid;grid-template-columns:minmax(120px,190px) 1fr;gap:6px 12px;align-items:center}
.kr-form label{opacity:.85}
.kr-form input[type=text],.kr-form select{width:100%;box-sizing:border-box}
.kr-bad-input{outline:2px solid #d23f3f!important}
.modal.kr-wide{max-width:min(1150px,97vw)!important;width:97vw!important}
.kr-ed{display:flex;border:1px solid rgba(128,128,128,.45);border-radius:6px;overflow:hidden}
.kr-gut{margin:0;padding:6px 6px 6px 4px;min-width:34px;text-align:right;opacity:.5;user-select:none;overflow:hidden;background:rgba(128,128,128,.08);font-family:ui-monospace,Menlo,Consolas,monospace;font-size:12.5px;line-height:1.45}
.kr-json{flex:1;min-width:0;box-sizing:border-box;border:0!important;margin:0;padding:6px 8px;resize:vertical;height:420px;font-family:ui-monospace,Menlo,Consolas,monospace;font-size:12.5px;line-height:1.45;tab-size:2;white-space:pre;overflow:auto}
.kr-json.kr-wrap{white-space:pre-wrap;word-break:break-all}
.kr-view{max-height:72vh;overflow:auto;white-space:pre;font-size:12px;background:rgba(128,128,128,.08);padding:10px;border-radius:6px}
.kr-switch{display:flex;align-items:flex-start;gap:9px;cursor:pointer;user-select:none}
.kr-switch input{display:none}
/* flex:0 0 40px -> yazı uzayınca anahtarın rayı ezilmez (top raydan taşmaz) */
.kr-switch span.kr-knob{flex:0 0 40px;width:40px;height:22px;border-radius:11px;background:#999;position:relative;transition:.2s;margin-top:1px}
.kr-switch > span:last-child{flex:1;min-width:0}
.kr-switch span.kr-knob:after{content:'';position:absolute;top:3px;left:3px;width:16px;height:16px;border-radius:50%;background:#fff;transition:.2s}
.kr-switch input:checked + span.kr-knob{background:#22a355}
.kr-switch input:checked + span.kr-knob:after{left:21px}
.kr-srv{display:flex;gap:8px;align-items:center;flex-wrap:wrap;margin-top:8px}
.kr-srv select{min-width:220px;max-width:100%}
.kr-jstat{margin:6px 0;font-size:.9em}
.kr-ok{color:#1b8a47}.kr-no{color:#b52f2f}
.kr-errs{margin:8px 0;padding:8px 12px;border-radius:8px;background:rgba(210,63,63,.1);border:1px solid rgba(210,63,63,.4)}
.kr-errs li{margin:3px 0}
.kr-hint{font-size:.85em;opacity:.8;margin-top:6px}
.kr-traffic{--krc-vpn:#2a78d6;--krc-dir:#eb6834;--krc-surface:#fcfcfb}
@media (prefers-color-scheme: dark){:root:not([data-theme="light"]) .kr-traffic{--krc-vpn:#3987e5;--krc-dir:#d95926;--krc-surface:#1a1a19}}
:root[data-theme="dark"] .kr-traffic{--krc-vpn:#3987e5;--krc-dir:#d95926;--krc-surface:#1a1a19}
.krc-sw{display:inline-block;width:10px;height:10px;border-radius:2px;margin-right:6px;vertical-align:baseline}
.krc-vpn{fill:var(--krc-vpn);background:var(--krc-vpn)}
.krc-dir{fill:var(--krc-dir);background:var(--krc-dir)}
.krc-title{margin:14px 0 4px;font-weight:600;opacity:.85}
.krc-legend{display:flex;gap:16px;flex-wrap:wrap;font-size:.9em;margin:2px 0 6px}
.krc-wrap{position:relative;width:100%}
.krc-svg{display:block;max-width:100%}
.krc-grid{stroke:rgba(128,128,128,.25);stroke-width:1}
.krc-ax{fill:currentColor;opacity:.65;font-size:11px}
.krc-hit{fill:transparent;cursor:crosshair}
.krc-hit:hover{fill:rgba(128,128,128,.12)}
.krc-tip{position:absolute;z-index:5;pointer-events:none;padding:6px 10px;border-radius:8px;font-size:.88em;line-height:1.45;background:var(--krc-surface);color:inherit;border:1px solid rgba(128,128,128,.4);box-shadow:0 2px 8px rgba(0,0,0,.25);white-space:nowrap}
.krt-now{font-weight:600;opacity:.85;margin:0 0 6px}
.krt-lives{display:grid;grid-template-columns:repeat(auto-fit,minmax(200px,1fr));gap:10px}
.krt-live{border:1px solid rgba(128,128,128,.25);border-radius:8px;padding:8px 12px}
.krt-lh{font-weight:600;margin-bottom:4px}
.krt-lv{display:flex;gap:18px;flex-wrap:wrap;font-variant-numeric:tabular-nums;font-size:1.1em}
.krt-totals{display:grid;grid-template-columns:repeat(auto-fit,minmax(200px,1fr));gap:10px;margin:10px 0 4px}
.krt-tot{padding:2px 2px}
.krt-big{font-size:1.5em;font-weight:600;font-variant-numeric:tabular-nums}
.krt-table{margin-top:10px}
.krt-n{text-align:right;font-variant-numeric:tabular-nums;white-space:nowrap}
.krt-table th.krt-n{text-align:right}
.kr-warn{margin-top:10px;padding:8px 10px;border-radius:8px;background:rgba(230,160,20,.15);border:1px solid rgba(230,160,20,.45);font-size:.9em}
@media(max-width:600px){.kr-hide-sm{display:none}}
`;

// Tarayıcıda saklanan eski menüyü (Hizmetler altındaki kayıt) bir kez temizle
try {
	if (!sessionStorage.getItem('kediray-menu-v2')) {
		sessionStorage.setItem('kediray-menu-v2', '1');
		if (ui.menu && ui.menu.flushCache) ui.menu.flushCache();
	}
} catch (e) {}

function collapsed(key) {
	try { return localStorage.getItem('kediray-fold-' + key) === '1'; } catch (e) { return false; }
}

/* KR-PANEL-BASLA */
/* IP/MAC gizleme (Cihazlar tablosu) */
(function () {
	var KEY = 'kr_hide_ids', busy = false;
	var on = function () { try { return localStorage.getItem(KEY) === '1'; } catch (e) { return false; } };
	var isIp = /^\d+\.\d+\.\d+\.\d+$/, isMac = /^([0-9a-f]{2}:){5}[0-9a-f]{2}$/i;
	function mask(t, n) {
		if (n === 0 && isIp.test(t)) return '•••.•••.•••.' + t.split('.')[3];
		if (n === 1 && isMac.test(t)) return '••:••:••:••:' + t.split(':').slice(4).join(':');
		return t;
	}
	function apply() {
		if (busy) return; busy = true;
		try {
			document.querySelectorAll('table.kr-table').forEach(function (tb) {
				var hdr = tb.querySelector('tr.table-titles'); if (!hdr) return;
				var ths = [].map.call(hdr.children, function (c) { return c.textContent.trim(); });
				var ii = ths.indexOf('IP'), mi = ths.indexOf('MAC'); if (ii < 0 || mi < 0) return;
				var host = tb.parentNode;
				if (host && !host.querySelector('.kr-hide-box')) {
					var cb = document.createElement('input'); cb.type = 'checkbox'; cb.checked = on();
					cb.addEventListener('change', function () { try { localStorage.setItem(KEY, cb.checked ? '1' : '0'); } catch (e) {} apply(); });
					var lb = document.createElement('label'); lb.className = 'kr-hide-box'; lb.style.cssText = 'display:inline-flex;gap:6px;align-items:center;margin:0 0 8px;cursor:pointer';
					lb.appendChild(cb); lb.appendChild(document.createTextNode('IP ve MAC adreslerini gizle'));
					host.insertBefore(lb, tb);
				}
				var box = host && host.querySelector('.kr-hide-box input'); if (box) box.checked = on();
				[].forEach.call(tb.querySelectorAll('tr'), function (tr) {
					if (tr === hdr) return;
					[ii, mi].forEach(function (ix, n) {
						var td = tr.children[ix]; if (!td) return;
						var orig = td.getAttribute('data-orig'), cur = td.textContent;
						if (orig === null || (cur !== orig && cur !== td.getAttribute('data-masked'))) {
							if (!(n === 0 ? isIp : isMac).test(cur)) return;
							orig = cur; td.setAttribute('data-orig', cur);
						}
						var want = on() ? mask(orig, n) : orig;
						if (td.textContent !== want) { td.setAttribute('data-masked', want); td.textContent = want; }
					});
				});
			});
		} finally { busy = false; }
	}
	new MutationObserver(function () { apply(); }).observe(document.documentElement, { childList: true, subtree: true });
})();
/* Sunucu bilgilerini / bağlı sunucu IP'sini gizleme */
(function () {
	var KS = 'kr_hide_srv', KI = 'kr_hide_srvip', secrets = [], orig = new WeakMap(), pend = false;
	var get = function (k) { try { return localStorage.getItem(k) === '1'; } catch (e) { return false; } };
	var set = function (k, v) { try { localStorage.setItem(k, v ? '1' : '0'); } catch (e) {} };
	var IPRE = /\b(\d{1,3})\.(\d{1,3})\.(\d{1,3})\.(\d{1,3})\b/g;
	function priv(a, b) { return a === 10 || a === 127 || a === 0 || (a === 192 && b === 168) || (a === 172 && b >= 16 && b <= 31) || (a === 169 && b === 254); }
	function loadSecrets() {
		try {
			var env = (window.L && L.env) || {};
			fetch(env.ubuspath || '/ubus/', { method: 'POST', body: JSON.stringify({ jsonrpc: '2.0', id: 1, method: 'call',
				params: [env.sessionid, 'uci', 'get', { config: 'kediray' }] }) })
			.then(function (r) { return r.json(); }).then(function (j) {
				var v = (j.result && j.result[1] && j.result[1].values) || {}, out = {};
				Object.keys(v).forEach(function (k) {
					if (v[k]['.type'] !== 'node') return;
					['address', 'sni', 'host', 'uuid', 'server'].forEach(function (f) {
						var x = v[k][f]; if (typeof x === 'string' && x.length >= 4) out[x] = 1;
					});
				});
				secrets = Object.keys(out).sort(function (a, b) { return b.length - a.length; });
				schedule();
			}).catch(function () {});
		} catch (e) {}
	}
	function conv(s, srv, ip) {
		if (srv) secrets.forEach(function (x) { if (s.indexOf(x) >= 0) s = s.split(x).join('••••••'); });
		if (ip) s = s.replace(IPRE, function (m, a, b, c, d) { return priv(+a, +b) ? m : '•••.•••.•••.' + d; });
		return s;
	}
	function ui() {
		if (document.querySelector('.kr-srv-box')) return;
		var h2 = [].filter.call(document.querySelectorAll('h2'), function (x) { return /KediRay VPN/.test(x.textContent); })[0];
		if (!h2 || !h2.parentNode) return;
		var bar = document.createElement('div'); bar.className = 'kr-srv-box';
		bar.style.cssText = 'display:flex;gap:18px;flex-wrap:wrap;margin:4px 0 10px';
		[['Sunucu bilgilerini gizle', KS]].forEach(function (p) {
			var lb = document.createElement('label'), cb = document.createElement('input');
			lb.style.cssText = 'display:inline-flex;gap:6px;align-items:center;cursor:pointer';
			cb.type = 'checkbox'; cb.checked = get(p[1]);
			cb.addEventListener('change', function () { set(p[1], cb.checked); apply(); });
			lb.appendChild(cb); lb.appendChild(document.createTextNode(p[0])); bar.appendChild(lb);
		});
		h2.parentNode.insertBefore(bar, h2.nextSibling);
	}
	function apply() {
		ui();
		var srv = get(KS), ip = srv;
		var w = document.createTreeWalker(document.body, NodeFilter.SHOW_TEXT, null), n, list = [];
		while ((n = w.nextNode())) list.push(n);
		list.forEach(function (n) {
			var p = n.parentNode; if (!p || /^(SCRIPT|STYLE|TEXTAREA)$/.test(p.nodeName) || (p.closest && p.closest('.kr-srv-box'))) return;
			var rec = orig.get(n), base = (rec && n.data === rec.m) ? rec.o : n.data;
			var m = conv(base, srv, ip);
			if (m !== n.data) { orig.set(n, { o: base, m: m }); n.data = m; }
			else if (m === base) orig.delete(n);
		});
	}
	function schedule() { if (pend) return; pend = true; setTimeout(function () { pend = false; apply(); }, 50); }
	loadSecrets();
	new MutationObserver(schedule).observe(document.documentElement, { childList: true, subtree: true, characterData: true });
})();
/* KR-PANEL-SON */

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

return view.extend({
	/* Kart: başlığa tıklayınca içerik katlanır (tercih tarayıcıda saklanır) */
	card(el, key, title, children, right) {
		const open = !collapsed(key);
		const body = h('div', { 'class': 'kr-cbody' + (open ? '' : ' kr-fold') }, children);
		const cap = h('span', { 'class': 'kr-caret' }, open ? '▾' : '▸');
		const head = h('h3', { 'class': 'kr-ch', 'title': 'Küçült / aç' }, [cap, h('span', { 'class': 'kr-ct' }, title), right || '']);
		head.addEventListener('click', ev => {
			if (ev.target.closest('button, select, input, a')) return;
			const now = body.classList.toggle('kr-fold');
			cap.textContent = now ? '▸' : '▾';
			try { localStorage.setItem('kediray-fold-' + key, now ? '1' : '0'); } catch (e) {}
		});
		dom.content(el, [head, body]);
	},

	/* Kart içindeki bölüm: başlığa tıklayınca katlanır (tercih tarayıcıda saklanır) */
	fold(key, title, content) {
		const open = !collapsed(key);
		const body = h('div', { 'class': 'kr-cbody' + (open ? '' : ' kr-fold') }, content);
		const cap = h('span', { 'class': 'kr-caret' }, open ? '▾' : '▸');
		const head = h('div', { 'class': 'krc-title kr-ch', 'title': 'Küçült / aç' }, [cap, h('span', { 'class': 'kr-ct' }, title)]);
		head.addEventListener('click', () => {
			const now = body.classList.toggle('kr-fold');
			cap.textContent = now ? '▸' : '▾';
			try { localStorage.setItem('kediray-fold-' + key, now ? '1' : '0'); } catch (e) {}
		});
		return h('div', {}, [head, body]);
	},

	lastStats: null,
	liveRate: null,
	trafficBuilt: false,
	chartSig: '',
	days: null,

	load() {
		return Promise.all([
			runJson(['status', '--json']),
			runJson(['nodes']),
			runJson(['apps']),
			runJson(['devices'])
		]);
	},

	/* ---------- işlemler ---------- */
	busy(msg, p) {
		ui.showModal(null, [h('p', { 'class': 'spinning' }, msg)]);
		return p.then(r => { ui.hideModal(); return r; }, e => { ui.hideModal(); throw e; });
	},
	note(msg, type) { ui.addNotification(null, h('p', msg), type || 'info'); },

	fetchDirect() {
		return run(['direct']).then(r => {
			const dead = /Direkt çıkış: YOK/.test(r.stdout || '');
			const off = /Otomatik direkt denetimi: KAPALI/.test(r.stdout || '');
			const ch = dead !== this.directDead || off !== this.autoOff;
			this.directDead = dead;
			this.autoOff = off;
			return ch;
		});
	},
	async doAutoDirect(off) {
		await this.busy('Uygulanıyor…', run(['autodirect', off ? 'off' : 'on']));
		return this.refreshAll();
	},
	async doDirectCheck() {
		await this.busy('Direkt çıkış ölçülüyor…', run(['direct', 'check']));
		return this.refreshAll();
	},

	async refreshAll() {
		const [st, nodes, apps, devs] = await this.load();
		await this.fetchDirect();
		this.nodes = nodes || [];
		this.apps = apps || [];
		this.renderStatus(st);
		this.renderNodes(nodes || [], st);
		this.renderApps(apps || []);
		this.devSig = JSON.stringify((devs || []).map(x => [x.mac, x.ip, x.name, x.mode, x.online])) + '|' + this.directDead + this.autoOff;
		this.renderDevices(devs || []);
	},

	async doToggle(st) {
		const on = st && st.enabled;
		if (!on && st && st.conflict && st.conflict.length)
			return this.doTakeover(st);
		await this.busy(on ? 'VPN durduruluyor…' : 'VPN başlatılıyor…', run([on ? 'stop' : 'start']));
		return this.refreshAll();
	},
	async doTakeover(st) {
		const names = (st && st.conflict || []).join(', ');
		if (!confirm(names + ' durdurulup KediRay başlatılacak.\nİnternet gelmezse otomatik olarak ' + names + ' geri açılır.\n\nDevam edilsin mi?'))
			return;
		const r = await this.busy('Geçiş yapılıyor (en fazla ~40 sn)…', run(['takeover']));
		this.note((r.stdout || '') + (r.stderr ? '\n' + r.stderr : ''), r.code === 0 ? 'info' : 'warning');
		return this.refreshAll();
	},
	async doRestart() {
		await this.busy('Yeniden başlatılıyor…', run(['restart']));
		return this.refreshAll();
	},
	async doPing(sec) {
		await this.busy(sec ? 'Ölçülüyor…' : 'Tüm sunucular ölçülüyor…', runJson(['ping', sec || 'all', '--json']));
		return this.refreshAll();
	},
	async doBest() {
		const r = await this.busy('En hızlı sunucu aranıyor…', run(['best']));
		this.note(r.code === 0 ? (r.stdout || 'En hızlı sunucuya geçildi') : ('Bulunamadı: ' + (r.stderr || '')), r.code === 0 ? 'info' : 'warning');
		return this.refreshAll();
	},
	async doUse(sec) {
		await this.busy('Sunucu değiştiriliyor (bağlantılar kopmadan)…', run(['use', sec]));
		return this.refreshAll();
	},
	async doApp(sec, route) {
		await this.busy('Uygulanıyor…', run(['app', sec, route]));
		return this.refreshAll();
	},
	async doDevice(d, mode) {
		await this.busy('Uygulanıyor…', run(['device', d.mac, mode, d.name || '']));
		return this.refreshAll();
	},
	async doSub() {
		const r = await this.busy('Abonelikler güncelleniyor…', run(['sub']));
		this.note((r.stdout || '') + (r.stderr ? ' ' + r.stderr : ''));
		return this.refreshAll();
	},
	async doCheck() {
		const r = await this.busy('Bağlantı test ediliyor…', runJson(['check']));
		if (!r || !r.running) return this.note('VPN çalışmıyor.', 'warning');
		const ok = v => v ? '✅' : '❌';
		ui.showModal('Bağlantı teşhisi', [
			h('ul', {}, [
				h('li', {}, ok(r.dns) + ' DNS (Xray üzerinden)'),
				h('li', {}, ok(r.vpn) + ' VPN tüneli' + (r.vpn_ip ? ' — çıkış IP: ' + r.vpn_ip : '')),
				h('li', {}, ok(r.direct) + ' Direkt internet')
			]),
			h('div', { 'class': 'right' }, h('button', { 'class': 'btn', 'click': ui.hideModal }, 'Kapat'))
		]);
	},
	errList(res) {
		const errs = (res && res.errors) || [];
		if (!errs.length) return h('div', { 'class': 'kr-errs' }, 'Bilinmeyen hata: ' + ((res && res.raw) || 'yanıt alınamadı'));
		return h('div', { 'class': 'kr-errs' }, [
			h('b', {}, STAGE[res.stage] || 'Hata'),
			h('ul', {}, errs.map(e => h('li', {}, [
				e.name && e.stage ? h('b', {}, e.name + ': ') : '',
				e.line ? 'Satır ' + e.line + (e.col ? ', sütun ' + e.col : '') + ' — ' : '',
				e.field && !e.line ? '[' + e.field + '] ' : '',
				e.msg || '',
				e.detail && e.detail !== e.msg ? h('div', { 'class': 'kr-sub', 'style': 'font-size:.8em;word-break:break-all' }, e.detail) : ''
			])))
		]);
	},

	async doValidate() {
		const r = await this.busy('Yapılandırma denetleniyor…', runJson(['validate', '--json']));
		ui.showModal('Yapılandırma denetimi', [
			r && r.ok ? h('p', { 'class': 'kr-ok' }, '✅ Yazım, alan ve Xray denetimi: hata yok.') : this.errList(r),
			h('div', { 'class': 'right' }, h('button', { 'class': 'btn', 'click': ui.hideModal }, 'Kapat'))
		]);
	},

	async doDelete(n) {
		if (!confirm('"' + n.name + '" silinsin mi?')) return;
		const r = await this.busy('Siliniyor…', runJson(['node', 'del', n.sec]));
		if (!r || !r.ok) this.note('Silinemedi', 'error');
		return this.refreshAll();
	},

	/* ---------- sunucu düzenleyici: Form + JSON ---------- */
	async openEditor(sec) {
		let d;
		if (sec) {
			d = await runJson(['node', 'get', sec]);
			if (!d || !d.ok) return this.note('Sunucu okunamadı', 'error');
		} else {
			d = { mode: 'form', fields: { protocol: 'vless', network: 'ws', tls: 'tls', port: '443' }, json: JSON_TEMPLATE };
		}
		const f = Object.assign({}, d.fields || {});
		const inputs = {}, rows = {};
		let tab = d.mode === 'json' ? 'json' : 'form';

		const name = h('input', { 'type': 'text', 'class': 'cbi-input-text', 'style': 'width:100%', 'value': f.remarks || '', 'placeholder': 'ör. Almanya WS' });
		const errBox = h('div', {});
		const hint = h('div', { 'class': 'kr-hint' });

		const readForm = () => {
			const o = {};
			FIELDS.forEach(([k, , t]) => {
				const el = inputs[k];
				o[k] = t === 'checkbox' ? (el.checked ? '1' : '') : el.value.trim();
			});
			return o;
		};
		const refreshVis = () => {
			const cur = readForm();
			FIELDS.forEach(([k, , , , vis]) => { rows[k].forEach(el => el.style.display = (!vis || vis(cur)) ? '' : 'none'); });
			const ipTLS = /^\d+\.\d+\.\d+\.\d+$/.test(cur.address) && cur.tls === 'tls' && !cur.sni && !cur.insecure;
			hint.textContent = ipTLS ? 'IP adresiyle TLS kullanıyorsan SNI alanına alan adını yaz ya da "Sertifikayı doğrulama"yı işaretle.' : '';
		};
		const formGrid = h('div', { 'class': 'kr-form' });
		FIELDS.forEach(([k, label, t, opts]) => {
			let el;
			if (t === 'select') {
				el = h('select', { 'class': 'cbi-input-select' }, (opts || []).map(o => {
					const [v, l] = Array.isArray(o) ? o : [o, o];
					return h('option', { 'value': v, 'selected': (f[k] || '') === v ? '' : null }, l);
				}));
			} else if (t === 'checkbox') {
				el = h('input', { 'type': 'checkbox', 'checked': f[k] === '1' ? '' : null });
			} else {
				el = h('input', { 'type': 'text', 'class': 'cbi-input-text', 'value': f[k] || '', 'spellcheck': 'false', 'autocomplete': 'off' });
			}
			el.addEventListener('change', refreshVis);
			el.addEventListener('input', () => { el.classList.remove('kr-bad-input'); if (k === 'address' || k === 'sni') refreshVis(); });
			inputs[k] = el;
			const lab = h('label', {}, label);
			rows[k] = [lab, el];
			formGrid.appendChild(lab);
			formGrid.appendChild(el);
		});

		const ta = h('textarea', { 'class': 'kr-json', 'spellcheck': 'false', 'wrap': 'off' });
		ta.value = d.json || JSON_TEMPLATE;
		const gut = h('pre', { 'class': 'kr-gut' });
		const syncGut = () => {
			const nl = ta.value.split('\n').length;
			if (gut._n !== nl) { gut._n = nl; gut.textContent = Array.from({ length: nl }, (_, k) => k + 1).join('\n'); }
			gut.scrollTop = ta.scrollTop;
		};
		const fitHeight = () => {
			const nl = ta.value.split('\n').length;
			ta.style.height = Math.min(Math.max(nl + 2, 16), 44) * 18.2 + 14 + 'px';
		};
		ta.addEventListener('scroll', syncGut);
		ta.addEventListener('input', syncGut);
		const editor = h('div', { 'class': 'kr-ed' }, [gut, ta]);
		const wrapBtn = h('button', { 'class': 'btn cbi-button', 'click': ev => {
			ev.preventDefault();
			ta.classList.toggle('kr-wrap');
			ta.setAttribute('wrap', ta.classList.contains('kr-wrap') ? 'soft' : 'off');
			gut.style.display = ta.classList.contains('kr-wrap') ? 'none' : '';
			wrapBtn.textContent = ta.classList.contains('kr-wrap') ? '↔ Satırları kaydırma' : '↵ Uzun satırları kaydır';
		} }, '↵ Uzun satırları kaydır');
		const fullBtn = h('button', { 'class': 'btn cbi-button', 'click': ev => {
			ev.preventDefault();
			ta.style.height = ta.style.height === '78vh' ? '' : '78vh';
			if (!ta.style.height) fitHeight();
			syncGut();
		} }, '⤢ Büyüt / küçült');
		const jstat = h('div', { 'class': 'kr-jstat' });
		let lastErr = null;
		const checkJson = () => {
			lastErr = jsonCheck(ta.value);
			jstat.className = 'kr-jstat ' + (lastErr ? 'kr-no' : 'kr-ok');
			jstat.textContent = lastErr ? '❌ Satır ' + lastErr.line + ', sütun ' + lastErr.col + ': ' + lastErr.msg : '✅ Geçerli JSON';
		};
		let tmr = null;
		ta.addEventListener('input', () => { clearTimeout(tmr); tmr = setTimeout(checkJson, 250); });
		ta.addEventListener('keydown', ev => {   // Tab tuşu girinti eklesin
			if (ev.key === 'Tab') {
				ev.preventDefault();
				const a = ta.selectionStart, b = ta.selectionEnd;
				ta.value = ta.value.slice(0, a) + '  ' + ta.value.slice(b);
				ta.selectionStart = ta.selectionEnd = a + 2;
			}
		});
		const gotoErr = e => {
			if (!e) return;
			ta.focus();
			const pos = e.pos != null ? e.pos : ta.value.split('\n').slice(0, e.line - 1).join('\n').length + (e.line > 1 ? 1 : 0) + (e.col - 1);
			ta.setSelectionRange(pos, Math.min(pos + 1, ta.value.length));
			const lh = parseFloat(getComputedStyle(ta).lineHeight) || 18;
			ta.scrollTop = Math.max(0, (e.line - 4) * lh);
		};
		const fmtBtn = h('button', { 'class': 'btn cbi-button', 'click': ev => {
			ev.preventDefault();
			checkJson();
			if (lastErr) return gotoErr(lastErr);
			ta.value = JSON.stringify(JSON.parse(ta.value), null, 2);
			checkJson(); fitHeight(); syncGut();
		} }, '⇆ Biçimlendir (girintiyi düzelt)');
		const goBtn = h('button', { 'class': 'btn cbi-button', 'click': ev => { ev.preventDefault(); checkJson(); gotoErr(lastErr); } }, 'Hataya git');

		const formPane = h('div', {}, [
			d.mode === 'json' ? h('p', { 'class': 'kr-hint' }, 'Bu sunucu JSON ile eklenmiş. Form ile kaydedersen JSON\'a özel ince ayarlar kaybolabilir; o ayarlar için JSON sekmesini kullan.') : '',
			formGrid, hint
		]);
		const jsonPane = h('div', {}, [
			h('p', { 'class': 'kr-hint' }, 'Xray outbound JSON\'u. v2rayNG\'nin tam yapılandırmasını da yapıştırabilirsin, içinden sunucu kısmı alınır. Girinti hata değildir, "Biçimlendir" ile düzeltilir; virgül/tırnak hataları anında satır ve sütunuyla gösterilir.'),
			editor, jstat, h('div', { 'class': 'kr-row', 'style': 'margin-top:4px' }, [fmtBtn, goBtn, wrapBtn, fullBtn])
		]);
		const tFormBtn = h('button', {}, 'Form');
		const tJsonBtn = h('button', {}, '{ } JSON');
		const setTab = t => {
			tab = t;
			formPane.style.display = t === 'form' ? '' : 'none';
			jsonPane.style.display = t === 'json' ? '' : 'none';
			tFormBtn.className = t === 'form' ? 'kr-act' : '';
			tJsonBtn.className = t === 'json' ? 'kr-act' : '';
			if (t === 'json') { checkJson(); fitHeight(); syncGut(); }
		};
		tFormBtn.addEventListener('click', ev => { ev.preventDefault(); setTab('form'); });
		tJsonBtn.addEventListener('click', ev => { ev.preventDefault(); setTab('json'); });

		const save = async () => {
			dom.content(errBox, '');
			let args;
			if (tab === 'json') {
				checkJson();
				if (lastErr) { dom.content(errBox, this.errList({ stage: 'syntax', errors: [lastErr] })); gotoErr(lastErr); return; }
				args = ['node', 'save', sec || 'new', 'json', ta.value, name.value.trim()];
			} else {
				const o = readForm();
				o.remarks = name.value.trim();
				const vis = {};
				FIELDS.forEach(([k, , , , v]) => { if (!v || v(o)) vis[k] = o[k]; });
				vis.remarks = o.remarks;
				args = ['node', 'save', sec || 'new', 'form', JSON.stringify(vis)];
			}
			const r = await run(args);
			let res = null;
			try { res = JSON.parse(r.stdout); } catch (e) { res = { ok: false, raw: (r.stdout || '') + (r.stderr || '') }; }
			if (res && res.ok) {
				ui.hideModal();
				this.note('Kaydedildi' + (sec ? '' : ' (yeni sunucu eklendi)') + '. Ayar denetimden ve Xray testinden geçti.');
				return this.refreshAll();
			}
			dom.content(errBox, this.errList(res));
			(res.errors || []).forEach(e => { if (e.field && inputs[e.field]) inputs[e.field].classList.add('kr-bad-input'); });
			if (tab === 'json' && res.stage === 'syntax' && res.errors && res.errors[0]) gotoErr(res.errors[0]);
		};

		ui.showModal(sec ? 'Sunucuyu düzenle' : 'Yeni sunucu', [
			h('div', { 'class': 'kr-form', 'style': 'margin-bottom:6px' }, [h('label', {}, 'Ad'), name]),
			d.sub ? h('p', { 'class': 'kr-hint' }, 'Not: Bu sunucu abonelikten geliyor; abonelik güncellenince değişikliğin üzerine yazılabilir.') : '',
			(d.errors && d.errors.length) ? this.errList({ stage: 'node', errors: d.errors }) : '',
			h('div', { 'class': 'kr-tabs' }, [tFormBtn, tJsonBtn]),
			formPane, jsonPane, errBox,
			h('div', { 'class': 'right', 'style': 'margin-top:10px' }, [
				h('button', { 'class': 'btn', 'click': ui.hideModal }, 'İptal'), ' ',
				h('button', { 'class': 'btn cbi-button-positive', 'click': ui.createHandlerFn(this, save) }, 'Denetle ve kaydet')
			])
		], 'kr-wide');
		refreshVis();
		setTab(tab);
	},

	showAdd() {
		const ta = h('textarea', { 'style': 'width:100%;height:190px;font-family:monospace', 'placeholder':
			'vless://...  vmess://...  trojan://...  ss://...\n(birden fazla satır olabilir)\n\nveya Xray JSON: tek outbound, outbound dizisi\nya da v2rayNG "tam yapılandırma" JSON\'u' });
		ui.showModal('Sunucu ekle — link veya JSON', [
			ta,
			h('p', { 'class': 'kr-sub' }, 'İpucu: v2rayNG\'de sunucuya uzun bas → "Tam yapılandırmayı panoya aktar" ile JSON\'u birebir alabilirsin.'),
			h('div', { 'class': 'right' }, [
				h('button', { 'class': 'btn', 'click': ui.hideModal }, 'İptal'), ' ',
				h('button', { 'class': 'btn cbi-button-positive', 'click': ui.createHandlerFn(this, async () => {
					const v = ta.value.trim();
					if (!v) return;
					const r = await this.busy('Ekleniyor…', run(['add', v]));
					this.note(r.code === 0 ? r.stdout : ('Eklenemedi: ' + (r.stderr || 'geçerli link/JSON yok')), r.code === 0 ? 'info' : 'error');
					return this.refreshAll();
				}) }, 'Ekle')
			])
		]);
	},
	async showConns(ip) {
		const list = await this.busy('Bağlantılar okunuyor…', runJson(['conns', ip, '--json']));
		const apps = (this.apps || []).filter(a => a.route === 'direct');
		const sel = h('select', { 'class': 'cbi-input-select' }, apps.map(a => h('option', { 'value': a.sec }, a.name)));
		const rows = (list || []).slice(0, 60).map(c => h('tr', { 'class': 'tr' }, [
			h('td', { 'class': 'td' }, c.proto),
			h('td', { 'class': 'td' }, c.dst), h('td', { 'class': 'td' }, String(c.port)),
			h('td', { 'class': 'td' }, String(c.n)),
			h('td', { 'class': 'td' }, h('span', { 'class': 'kr-ping ' + (c.vpn ? 'kr-mid' : 'kr-good') }, c.vpn ? 'VPN' : 'Direkt')),
			h('td', { 'class': 'td' }, c.web ? h('span', { 'class': 'kr-sub' }, 'web') : h('b', {}, 'oyun/uygulama?')),
			h('td', { 'class': 'td' }, c.vpn && apps.length
				? btn.call(this, 'Direkt yap', 'cbi-button-action', () => this.doDirect(sel.value, c), 'Bu sunucuyu (ve komşularını) seçili uygulamaya ekler')
				: '')
		]));
		ui.showModal('Aktif bağlantılar — ' + (ip || 'tüm cihazlar'), [
			h('p', { 'class': 'kr-sub' }, 'Oyun açıkken bak. Oyunun satırlarında "VPN" yazıyorsa oyun tünelden geçiyor: ışınlanırken sunucu IP değişti sanıp atabilir. "Direkt yap" o sunucuyu (aynı /24 komşuları) ve portunu seçili uygulamaya ekler.'),
			apps.length ? h('div', { 'class': 'kr-row', 'style': 'margin:0 0 8px' }, [h('label', {}, 'Eklenecek uygulama:'), sel]) : '',
			h('table', { 'class': 'table kr-table' }, [
				h('tr', { 'class': 'tr table-titles' }, ['Proto', 'Hedef', 'Port', 'Adet', 'Yol', '', ''].map(x => h('th', { 'class': 'th' }, x))),
				...rows
			]),
			h('div', { 'class': 'right' }, h('button', { 'class': 'btn', 'click': ui.hideModal }, 'Kapat'))
		], 'kr-wide');
	},

	async doDirect(sec, c) {
		if (!sec) return;
		const net = c.dst.split('.').slice(0, 3).join('.') + '.0/24';
		const r1 = await run(['app', sec, 'add-ip', net]);
		const r2 = c.web ? { code: 0 } : await run(['app', sec, 'add-port', String(c.port)]);
		ui.hideModal();
		if (r1.code === 0 && r2.code === 0)
			ui.addNotification(null, h('p', {}, net + (c.web ? '' : ' ve port ' + c.port) + ' direkt listeye eklendi. Oyunu yeniden başlatmadan denemek için önce oyundan çık.'), 'info');
		else
			ui.addNotification(null, h('p', {}, 'Eklenemedi: ' + ((r1.stderr || r2.stderr || '').trim() || 'bilinmeyen hata')), 'error');
	},

	/* ---------- çizim ---------- */
	renderStatus(st) {
		st = st || {};
		const dot = st.running ? 'kr-on' : (st.enabled ? 'kr-err' : 'kr-off');
		const txt = st.running ? 'Çalışıyor' : (st.enabled ? 'Durdu — Günlük sekmesine bak' : 'Kapalı');
		const modes = { rule: 'Tümü VPN', global: 'Tümü VPN', list: 'Sadece liste VPN' };
		const cf = st.conflict || [];
		this.card(this.elStatus, 'status', 'Durum', [
			h('div', { 'class': 'kr-big' }, [h('span', { 'class': 'kr-dot ' + dot }), txt]),
			h('div', { 'class': 'kr-sub' }, [
				'Xray ', st.core || '?', ' · Mod: ', modes[st.mode] || st.mode || '-',
				' · Yakalama: ', ({ mixed: 'Mixed (TCP çekirdek + UDP hev)', tun: 'TUN (hepsi hev-socks5-tunnel)', tproxy: 'TPROXY', redirect: 'Redirect (sadece TCP)' })[st.capture] || st.capture || '-',
				st.running ? [' · Açık: ', live(st.uptime)] : '',
				st.direct_dead ? ' · Direkt çıkış yok: "direkt" uygulamalar da VPN\'den çıkıyor' : ''
			]),
			cf.length ? h('div', { 'class': 'kr-warn' }, [
				h('b', {}, 'Şu an ' + cf.join(', ') + ' çalışıyor. '),
				'İkisi aynı anda trafiği yönetemez; KediRay kapalı bekliyor. "Güvenli geçiş" ' + cf.join(', ') +
				'\'i durdurur, artıklarını temizler ve KediRay\'i başlatır. İnternet gelmezse otomatik geri alır.'
			]) : '',
			st.dns_rescue ? h('div', { 'class': 'kr-warn' }, [
				h('b', {}, 'DNS acil yedeği devrede. '),
				'Tünelden giden DNS yanıt vermedi, adresler geçici olarak operatörün DNS\'iyle çözülüyor — internet çalışmaya devam ediyor ama bu sorgular tünelden geçmiyor. Tünel düzelince kendiliğinden geri döner. Sebebini görmek için "🤝 Sunucu el sıkışması"na bas.'
			]) : '',
			st.last_error ? h('div', { 'class': 'kr-errs' }, [
				h('b', {}, 'Yapılandırma hatası — VPN başlatılamadı'),
				h('pre', { 'style': 'white-space:pre-wrap;margin:6px 0 0;font-size:.85em' }, st.last_error)
			]) : '',
			h('div', { 'class': 'kr-row' }, [
				cf.length && !st.enabled
					? btn.call(this, '⇄ Güvenli geçiş', 'cbi-button-positive', () => this.doTakeover(st))
					: btn.call(this, st.enabled ? 'Durdur' : 'Başlat', st.enabled ? 'cbi-button-negative' : 'cbi-button-positive', () => this.doToggle(st)),
				btn.call(this, 'Yeniden başlat', 'cbi-button-action', () => this.doRestart()),
				btn.call(this, 'Teşhis', '', () => this.doCheck()),
				btn.call(this, '✓ Ayarları denetle', '', () => this.doValidate(), 'Yazım/alan hatası ve Xray testi'),
				btn.call(this, '⏱ Hız testi', '', () => this.doSpeed(), 'Direkt ve VPN hızını karşılaştır'),
				btn.call(this, '🐢 Sayfa gecikmesi', '', () => this.doWebtest(), 'Sayfa neden geç açılıyor: DNS mi, tünel mi?'),
				btn.call(this, '🔎 Takılma avı', '', () => this.doHunt(), 'Tarayıcıda takılan adresleri arka arkaya dener: takılma DNS\'te mi bağlantıda mı?'),
				btn.call(this, '🤝 Sunucu el sıkışması', '', () => this.doDial(), 'Sunucu bağlantıyı kaç kez düşürüyor (günlükteki EOF hatası)'),
				btn.call(this, '{ } Xray yapılandırması', '', () => this.showConfig(), 'Üretilen tam config.json')
			])
		]);
		const a = st.active;
		// Kullanıcı açılır listeyi kullanırken periyodik yenileme listeyi bozmasın
		if (this.elNode.contains(document.activeElement) && document.activeElement.tagName === 'SELECT') return;
		const nodes = (this.nodes || []).filter(n => n.enabled !== false);
		const curSec = st.auto ? (a ? a.sec : '') : (st.selected ? st.selected.sec : '');
		const sel = h('select', { 'class': 'cbi-input-select' }, nodes.map(n =>
			h('option', { 'value': n.sec, 'selected': n.sec === curSec ? '' : null },
				n.name + (n.ping != null && n.ping < 0 ? '  (yok)' : n.rtt ? '  (' + n.rtt + ' ms)' : n.ping != null ? '  (tünel ' + n.ping + ' ms)' : ''))));
		const sw = h('input', { 'type': 'checkbox', 'checked': st.auto ? '' : null });
		sw.addEventListener('change', ui.createHandlerFn(this, () => this.doAuto(sw.checked)));
		this.card(this.elNode, 'node', 'Bağlı sunucu', [
			h('div', { 'class': 'kr-big' }, a ? a.name : (st.running ? '…' : (st.selected ? st.selected.name : '—'))),
			h('div', { 'class': 'kr-sub' }, [
				a ? [a.protocol, a.network].filter(Boolean).join(' · ') + ' · ' : '',
				st.auto ? h('span', { 'class': 'kr-tag' }, 'OTOMATİK') : h('span', { 'class': 'kr-tag' }, 'ELLE SEÇİLDİ'),
				' ', a ? pingBadge(a.ping, a.rtt, a.warm) : ''
			]),
			// Bağlanılan adres: alan adı ya da IP (alan adıyla bağlanıldıysa çözülen IP de yazar)
			a && a.address ? h('div', { 'class': 'kr-addr' }, [
				h('span', { 'class': 'kr-sub' }, a.ip ? 'Sunucu (alan adı): ' : 'Sunucu IP\'si: '),
				h('code', { 'class': 'kr-mono' }, a.address + (a.port ? ':' + a.port : '')),
				a.ip ? [h('span', { 'class': 'kr-sub' }, ' → IP: '), h('code', { 'class': 'kr-mono' }, a.ip)] : ''
			]) : '',
			h('label', { 'class': 'kr-switch', 'style': 'margin-top:10px' }, [
				sw, h('span', { 'class': 'kr-knob' }),
				h('span', {}, [h('b', {}, 'Otomatik geçiş'), h('span', { 'class': 'kr-sub' },
					st.auto ? ' — seçili sunucuda kalır, sadece o düşerse diğerine geçer (oyunda IP değişmez)' : ' — kapalı: seçtiğin sunucuda kalır, hiç geçiş yapılmaz')])
			]),
			h('div', { 'class': 'kr-srv' }, nodes.length ? [
				sel,
				btn.call(this, 'Bu sunucuya bağlan', 'cbi-button-action', () => this.doUse(sel.value), 'Elle seç (otomatik geçiş kapanır)')
			] : h('span', { 'class': 'kr-sub' }, 'Sunucu yok')),
			h('div', { 'class': 'kr-row' }, [
				btn.call(this, '⚡ Ping ölç', '', () => this.doPing(null)),
				btn.call(this, '🚀 En hızlıyı bul ve bağlan', 'cbi-button-positive', () => this.doBest()),
				(this.nodes || []).some(n => n.insecure) ? btn.call(this, '🔒 Sertifikayı sabitle', '', () => this.doPin(null), 'Sunucunun şu anki sertifikasını sabitler; değiştiyse tüneli yeniden başlatır (internet gittiyse bas)') : ''
			])
		]);
	},

	async doPin(sec) {
		const r = await this.busy('Sertifika sabitleniyor…', run(sec ? ['pin', sec] : ['pin']));
		const out = ((r.stdout || '') + ' ' + (r.stderr || '')).trim().split('\n').join(' · ');
		this.note(out || 'Bitti', r.code === 0 ? 'info' : 'warning');
		return this.refreshAll();
	},

	async doAuto(on) {
		await this.busy(on ? 'Otomatik geçiş açılıyor…' : 'Şu anki sunucuda sabitleniyor…', run(['auto', on ? 'on' : 'off']));
		return this.refreshAll();
	},

	async doWebtest() {
		const raw = await this.busy('Sayfa açılma süresi ölçülüyor (≈10 sn)…', run(['webtest', '--json']));
		let r = null;
		try { r = JSON.parse(raw.stdout || 'null'); } catch (e) { r = null; }
		if (!r || !r.tests)
			return ui.showModal('Sayfa gecikmesi — ölçüm yapılamadı', [
				h('p', {}, 'Komut beklenen çıktıyı vermedi. Terminalde şunu çalıştırıp çıktıyı paylaşabilirsin:'),
				h('pre', { 'class': 'kr-view' }, 'kediray webtest'),
				h('p', { 'class': 'kr-sub' }, 'Çıkış kodu: ' + raw.code),
				(raw.stderr || raw.stdout) ? h('details', {}, [h('summary', {}, 'Çıktı'), h('pre', { 'class': 'kr-view' }, ((raw.stderr || '') + '\n' + (raw.stdout || '')).trim())]) : '',
				h('div', { 'class': 'right' }, h('button', { 'class': 'btn', 'click': ui.hideModal }, 'Kapat'))
			], 'kr-wide');
		const ms = v => (v == null ? '—' : v + ' ms');
		const rows = [];
		r.tests.forEach(t => {
			const line = (label, x, cls) => h('tr', { 'class': 'tr' + (cls || '') }, [
				h('td', { 'class': 'td' }, label),
				h('td', { 'class': 'td krt-n' }, ms(x.dns)), h('td', { 'class': 'td krt-n' }, ms(x.connect)),
				h('td', { 'class': 'td krt-n' }, ms(x.tls)), h('td', { 'class': 'td krt-n' }, ms(x.ttfb)),
				h('td', { 'class': 'td krt-n' }, h('b', {}, ms(x.total))),
				h('td', { 'class': 'td' }, x.code ? String(x.code) : h('span', { 'style': 'color:#e05252' }, 'yanıt yok'))
			]);
			rows.push(h('tr', { 'class': 'tr' }, h('td', { 'class': 'td', 'colspan': 7 }, h('b', {}, t.host))));
			rows.push(line('  direkt', t.direct));
			if (r.running) rows.push(line('  VPN', t.vpn, ' kr-active'));
		});
		ui.showModal('Sayfa açılma gecikmesi', [
			h('p', { 'class': 'kr-sub' }, 'Bir sayfanın açılması: DNS (adres çözme) → bağlantı → TLS → ilk bayt. Hangi aşamada beklendiği aşağıda. DNS süresi ikisinde de aynıdır: o modemin kendi DNS yolu.'),
			h('table', { 'class': 'table kr-table' }, [
				h('tr', { 'class': 'tr table-titles' }, ['', 'DNS', 'Bağlantı', 'TLS', 'İlk bayt', 'Toplam', 'HTTP'].map((x, i) =>
					h('th', { 'class': 'th' + (i ? ' krt-n' : '') }, x))),
				...rows
			]),
			r.verdict && r.verdict.length ? h('ul', {}, r.verdict.map(v => h('li', {}, v))) : '',
			h('div', { 'class': 'right' }, h('button', { 'class': 'btn', 'click': ui.hideModal }, 'Kapat'))
		], 'kr-wide');
	},

	// Arka planda çalışan uzun ölçümü aç, bitene kadar canlı oku (arayüz isteği zaman aşımına düşmesin)
	async bgWatch(title, args, hint, verdict) {
		const kick = await run([args[0], '--bg', ...args.slice(1)]);
		if (kick.code !== 0)
			return ui.showModal(title + ' — başlatılamadı', [
				h('p', {}, 'Komut çalışmadı. SSH ile deneyebilirsin:'),
				h('pre', { 'class': 'kr-view' }, 'kediray ' + args.join(' ')),
				h('pre', { 'class': 'kr-view' }, ((kick.stderr || '') + '\n' + (kick.stdout || '')).trim() || 'çıkış kodu: ' + kick.code),
				h('div', { 'class': 'right' }, h('button', { 'class': 'btn', 'click': ui.hideModal }, 'Kapat'))
			], 'kr-wide');
		const pre = h('pre', { 'class': 'kr-view', 'style': 'max-height:50vh' }, 'Ölçüm başladı, ilk sonuçlar birkaç saniye içinde…');
		const head = h('p', {}, h('b', {}, 'Ölçüm sürüyor…'));
		const closed = { v: false };
		ui.showModal(title, [
			head, pre,
			h('p', { 'class': 'kr-sub' }, hint),
			h('div', { 'class': 'right' }, h('button', { 'class': 'btn', 'click': () => { closed.v = true; ui.hideModal(); } }, 'Kapat'))
		], 'kr-wide');
		for (let i = 0; i < 120 && !closed.v; i++) {
			const r = await run([args[0], '--read']);
			const nl = (r.stdout || '').indexOf('\n');
			const state = nl < 0 ? (r.stdout || '').trim() : r.stdout.slice(0, nl).trim();
			const body = nl < 0 ? '' : r.stdout.slice(nl + 1);
			if (closed.v) return;
			if (body.trim()) pre.textContent = body.trimEnd();
			if (state === 'BITTI') { head.textContent = ''; head.appendChild(h('b', {}, verdict(body))); return; }
			if (state === 'BASLAMADI' && i > 3) { head.textContent = 'Ölçüm çıktısı bulunamadı. SSH: kediray ' + args.join(' '); return; }
			await new Promise(res => setTimeout(res, 2000));
		}
		if (!closed.v) head.textContent = 'Ölçüm hâlâ sürüyor. Düğmeye tekrar basarak kaldığı yerden okuyabilirsin.';
	},

	doDial() {
		return this.bgWatch('Sunucu el sıkışması', ['dialtest', '10'],
			'Her sunucu adresine 10 kez sıfırdan bağlanılır. Alan adı birden çok IP\'ye çözülüyorsa her IP ayrı ölçülür.',
			out => this.dialVerdict(out));
	},

	dialVerdict(out) {
		const lines = (out || '').split('\n');
		if (!lines.some(l => /başarılı/.test(l))) return 'Ölçüm sonucu okunamadı: aşağıdaki çıktıyı paylaş ya da SSH ile "kediray dialtest" çalıştır.';
		const bad = lines.filter(l => /DÜŞTÜ/.test(l) && /\d+\/\d+ başarılı/.test(l));
		const good = lines.filter(l => /\d+\/\d+ başarılı/.test(l) && !/DÜŞTÜ/.test(l));
		if (!bad.length) return 'Sunucu her denemede el sıkıştı: bağlantı kurulumu sağlam. Sayfa takılmaları başka yerde.';
		if (good.length) return 'Bazı IP\'ler bağlantıyı düşürüyor, bazıları sağlam. Ayarlar → Genel → "Sunucuya IP ile bağlan" seçeneğini kapat: her bağlantıda çalışan IP denenir.';
		return 'Sunucu bağlantıları düşürüyor (günlükteki EOF hatası bu). Sayfalarda takılan istekler bunlar: sunucu yükü/port kısıtı olabilir — başka port ya da ikinci sunucu dene.';
	},

	async doHunt() {
		// Ölçüm 1 dk'yı aşabiliyor; arayüzün isteği o kadar bekleyemediği için arka planda çalıştırıp okuyoruz
		const kick = await run(['hunt', '--bg', '5']);
		if (kick.code !== 0)
			return ui.showModal('Takılma avı başlatılamadı', [
				h('p', {}, 'Komut çalışmadı. SSH ile şunu deneyip çıktıyı paylaşabilirsin:'),
				h('pre', { 'class': 'kr-view' }, 'kediray hunt 10'),
				h('pre', { 'class': 'kr-view' }, ((kick.stderr || '') + '\n' + (kick.stdout || '')).trim() || 'çıkış kodu: ' + kick.code),
				h('div', { 'class': 'right' }, h('button', { 'class': 'btn', 'click': ui.hideModal }, 'Kapat'))
			], 'kr-wide');

		const pre = h('pre', { 'class': 'kr-view', 'style': 'max-height:50vh' }, 'Ölçüm başladı, ilk sonuçlar birkaç saniye içinde…');
		const head = h('p', {}, h('b', {}, 'Ölçüm sürüyor…'));
		const closed = { v: false };
		const close = () => { closed.v = true; ui.hideModal(); };
		ui.showModal('Takılma avı', [
			head, pre,
			h('p', { 'class': 'kr-sub' }, 'Her adres 5 kez denenir. Pencereyi kapatsan da ölçüm arkada biter; tekrar bakmak için düğmeye bas.'),
			h('div', { 'class': 'right' }, h('button', { 'class': 'btn', 'click': close }, 'Kapat'))
		], 'kr-wide');

		for (let i = 0; i < 90 && !closed.v; i++) {
			const r = await run(['hunt', '--read']);
			const nl = (r.stdout || '').indexOf('\n');
			const state = nl < 0 ? (r.stdout || '').trim() : r.stdout.slice(0, nl).trim();
			const body = nl < 0 ? '' : r.stdout.slice(nl + 1);
			if (closed.v) return;
			if (body.trim()) pre.textContent = body.trimEnd();
			if (state === 'BITTI') {
				head.textContent = '';
				head.appendChild(h('b', {}, this.huntVerdict(body)));
				return;
			}
			if (state === 'BASLAMADI' && i > 3) {
				head.textContent = 'Ölçüm çıktısı bulunamadı. SSH: kediray hunt 10';
				return;
			}
			await new Promise(res => setTimeout(res, 2000));
		}
		if (!closed.v) head.textContent = 'Ölçüm hâlâ sürüyor. Düğmeye tekrar basarak kaldığı yerden okuyabilirsin.';
	},

	// Çıktıdan tek cümlelik sonuç. Çıktı yoksa ASLA "takılma yok" demeyiz: bilmiyoruz demektir.
	huntVerdict(out) {
		const lines = (out || '').split('\n');
		const tried = lines.filter(l => /deneme/.test(l) || /başarılı/.test(l));
		if (!tried.length) return 'Ölçüm sonucu okunamadı: aşağıdaki çıktıyı paylaş ya da SSH ile "kediray hunt 10" çalıştır.';
		const fails = lines.filter(l => /BAŞARISIZ/.test(l));
		const slow = lines.filter(l => /YAVAŞ/.test(l));
		if (fails.length)
			return /DNS aşamasında/.test(fails.join(' '))
				? 'Takılmalar ad çözümlemede (DNS): ' + fails.length + ' deneme DNS aşamasında düştü. Ayarlar → DNS bölümünden mod değiştirip tekrar ölçelim.'
				: 'Takılmalar bağlantı aşamasında: tünelin sunucuya bağlanması takılıyor. Sunucu/port/SNI ya da başka bir sunucu denenmeli.';
		if (slow.length)
			return 'Hiçbir deneme düşmedi ama ' + slow.length + ' deneme 3 sn üstünde kaldı: aşağıda hangi aşamanın beklediği yazıyor.';
		return 'Modem tarafında takılma yok: bu adresler her denemede hızlı açıldı. Takılma tarayıcı tarafındadır (Chrome → Gizlilik → "Güvenli DNS" kapalı olmalı; ayrıca IPv6/QUIC).';
	},

	async doSpeed() {
		const r = await this.busy('Hız testi yapılıyor (≈30 sn)…', runJson(['speedtest', '--json']));
		if (!r) return this.note('Hız testi yapılamadı', 'error');
		const tip = [];
		if (r.running && r.direct_mbps > 0) {
			const ratio = r.vpn_mbps / r.direct_mbps;
			if (ratio < 0.3) tip.push('VPN hızı direktin çok altında: sunucunun hattı/uzaklığı ya da sunucu tarafı sınırı olabilir. "En hızlıyı bul" ile başka sunucu dene.');
			else if (ratio < 0.7) tip.push('VPN hızı direktin bir miktar altında; WS+TLS tünelde bu normal sayılır.');
			else tip.push('VPN hızı direkte yakın, tünel sorunsuz.');
		}
		if (r.dns_ms > 300) tip.push('DNS yavaş (' + r.dns_ms + ' ms): Ayarlar → DNS → "Hızlı" modunu kullan.');
		ui.showModal('Hız testi (modem üzerinden)', [
			h('table', { 'class': 'table kr-table' }, [
				h('tr', { 'class': 'tr table-titles' }, ['', 'İndirme', 'Gecikme'].map(x => h('th', { 'class': 'th' }, x))),
				h('tr', { 'class': 'tr' }, [h('td', { 'class': 'td' }, 'Direkt'), h('td', { 'class': 'td' }, r.direct_mbps + ' Mbps'), h('td', { 'class': 'td' }, r.direct_ms + ' ms')]),
				h('tr', { 'class': 'tr' }, [h('td', { 'class': 'td' }, 'VPN'), h('td', { 'class': 'td' }, r.running ? r.vpn_mbps + ' Mbps' : 'kapalı'), h('td', { 'class': 'td' }, r.running ? r.vpn_ms + ' ms' : '—')]),
				h('tr', { 'class': 'tr' }, [h('td', { 'class': 'td' }, 'DNS çözümleme'), h('td', { 'class': 'td' }, ''), h('td', { 'class': 'td' }, r.dns_ms + ' ms')])
			]),
			tip.length ? h('ul', {}, tip.map(t => h('li', {}, t))) : '',
			h('p', { 'class': 'kr-sub' }, 'Ölçüm modemin kendi bağlantısıyla yapılır (Cloudflare, 20 MB). Wi-Fi hızın bundan düşükse darboğaz Wi-Fi\'dır.'),
			h('div', { 'class': 'right' }, h('button', { 'class': 'btn', 'click': ui.hideModal }, 'Kapat'))
		]);
	},

	async showConfig() {
		const r = await run(['show-config']);
		ui.showModal('Üretilen Xray yapılandırması (salt okunur)', [
			r.code === 0 ? h('pre', { 'class': 'kr-view' }, r.stdout) : h('p', {}, (r.stderr || 'Yapılandırma yok').trim()),
			h('div', { 'class': 'right' }, h('button', { 'class': 'btn', 'click': ui.hideModal }, 'Kapat'))
		], 'kr-wide');
	},

	/* Trafik: canlı hız + dönem tablosu (VPN ve Direkt ayrı) + 30 günlük yığılmış çubuk grafik.
	   Kaynak: `kediray stats` = { t, counters:{vr,vt,wr,wt}, today, yesterday, week, month, total, since, days:[{day,vr,vt,dr,dt}] }
	   vr/vt = VPN indirme/yükleme (tünelin dış baytları), dr/dt = Direkt = WAN toplamı − VPN. */
	trafficLive(s) {
		let r = { vd: 0, vu: 0, dd: 0, du: 0 };
		const p = this.lastStats, c = s.counters;
		if (p && s.t > p.t) {
			const dt = s.t - p.t, pc = p.counters;
			// sayaç sıfırlandıysa (tablo yeniden kuruldu) fark = şimdiki değer
			const d = (a, b) => (a >= b ? a - b : a) / dt;
			const vd = d(c.vr, pc.vr), vu = d(c.vt, pc.vt);
			r = { vd, vu, dd: Math.max(0, d(c.wr, pc.wr) - vd), du: Math.max(0, d(c.wt, pc.wt) - vu) };
		} else if (this.liveRate) r = this.liveRate;
		this.liveRate = r;
		this.lastStats = s;
		return r;
	},

	trafficChart(days) {
		const W = Math.max(280, Math.min(1100, this.elChart.clientWidth || 700)), H = 170;
		const L = 46, R = 8, T = 10, B = 24, pw = W - L - R, ph = H - T - B;
		const n = days.length, slot = pw / n, bw = Math.min(24, Math.max(4, slot - 4));
		const tot = days.map(x => x.vr + x.vt + x.dr + x.dt);
		const max = Math.max(1, ...tot);
		// "güzel" üst sınır: 1/2/5 × 10^k
		const pow = Math.pow(10, Math.floor(Math.log10(max))), top = [1, 2, 5, 10].map(m => m * pow).find(v => v >= max);
		const y = v => T + ph - (v / top) * ph;
		let g = '';
		for (let i = 0; i <= 4; i++) {
			const v = top * i / 4, yy = y(v).toFixed(1);
			g += '<line x1="' + L + '" x2="' + (W - R) + '" y1="' + yy + '" y2="' + yy + '" class="krc-grid"/>' +
				'<text x="' + (L - 6) + '" y="' + (+yy + 4) + '" text-anchor="end" class="krc-ax">' + (v ? fmtBytes(v) : '0') + '</text>';
		}
		let bars = '';
		days.forEach((x, i) => {
			const cx = L + slot * i + slot / 2, x0 = (cx - bw / 2).toFixed(1);
			const vpn = x.vr + x.vt, dir = x.dr + x.dt;
			const hv = vpn > 0 ? Math.max(1, (vpn / top) * ph) : 0, hd = dir > 0 ? Math.max(1, (dir / top) * ph) : 0;
			const base = T + ph;
			// alt: VPN, üst: Direkt; en üstteki parçanın ucu 4px yuvarlak, taban düz; ikisi arasında 2px yüzey boşluğu
			const gap = hv > 0 && hd > 2 ? 2 : 0;
			if (hv > 0) bars += hd > 0 ? '<rect x="' + x0 + '" y="' + (base - hv).toFixed(1) + '" width="' + bw.toFixed(1) + '" height="' + hv.toFixed(1) + '" class="krc-vpn"/>'
				: '<path d="' + roundTop(+x0, base - hv, bw, hv, 4) + '" class="krc-vpn"/>';
			if (hd > 0) bars += '<path d="' + roundTop(+x0, base - hv - hd, bw, hd - gap, 4) + '" class="krc-dir"/>';
			// gezinme hedefi: sütunun tamamı
			bars += '<rect x="' + (L + slot * i).toFixed(1) + '" y="' + T + '" width="' + slot.toFixed(1) + '" height="' + ph + '" class="krc-hit" data-i="' + i + '"/>';
			if (i % Math.ceil(n / (W < 500 ? 5 : 10)) === 0 || i === n - 1)
				bars += '<text x="' + cx.toFixed(1) + '" y="' + (H - 6) + '" text-anchor="middle" class="krc-ax">' + x.day.slice(8) + '.' + x.day.slice(5, 7) + '</text>';
		});
		return '<svg viewBox="0 0 ' + W + ' ' + H + '" width="' + W + '" height="' + H + '" class="krc-svg" role="img" aria-label="Son 30 gün trafik (VPN ve Direkt)">' + g + bars + '</svg>';
	},

	renderTraffic(s) {
		if (!s || !s.counters || !s.today) { this.card(this.elTraffic, 'traffic', 'Trafik', h('div', { 'class': 'kr-sub' }, 'Henüz veri yok')); this.trafficBuilt = false; return; }
		const r = this.trafficLive(s);
		if (!this.trafficBuilt) {
			this.elLive = h('div', {});
			this.elPeriods = h('div', {});
			this.elDevTr = h('div', {});
			this.elChart = h('div', { 'class': 'krc-wrap' });
			this.elTip = h('div', { 'class': 'krc-tip', 'style': 'display:none' });
			this.elChart.appendChild(this.elTip);
			this.elSvg = h('div', {});
			this.elChart.insertBefore(this.elSvg, this.elTip);
			this.elChart.addEventListener('mousemove', ev => this.trafficHover(ev));
			this.elChart.addEventListener('mouseleave', () => { this.elTip.style.display = 'none'; });
			this.elChart.addEventListener('click', ev => this.trafficHover(ev));
			this.card(this.elTraffic, 'traffic', 'Trafik', [
				this.elLive,
				this.fold('t-periods', 'Bugün / Dün / Bu hafta / Bu ay / Toplam', this.elPeriods),
				this.fold('t-devs', 'Cihaz bazında trafik', this.elDevTr),
				this.fold('t-chart', 'Son 30 gün (günlük)', h('div', {}, [
					h('div', { 'class': 'krc-legend' }, [
						h('span', {}, [h('i', { 'class': 'krc-sw krc-vpn' }), 'VPN']),
						h('span', {}, [h('i', { 'class': 'krc-sw krc-dir' }), 'Direkt'])
					]),
					this.elChart
				])),
				h('div', { 'class': 'kr-sub', 'style': 'margin-top:8px' }, 'VPN = sunucuya giden/gelen gerçek tünel baytları. Direkt = modemin İnternet (WAN) toplamı − VPN; yani VPN\'siz çıkan her şey (seçtiğin direkt uygulamalar, oyun, Teams, yerel indirmeler) burada. Sayaçlar modem yeniden başlasa da saklanır.')
			]);
			this.trafficBuilt = true;
		}

		const pill = (cls, label, d, u) => h('div', { 'class': 'krt-live ' + cls }, [
			h('div', { 'class': 'krt-lh' }, [h('i', { 'class': 'krc-sw ' + (cls === 'v' ? 'krc-vpn' : 'krc-dir') }), label]),
			h('div', { 'class': 'krt-lv' }, [h('span', {}, '↓ ' + fmtRate(d)), h('span', {}, '↑ ' + fmtRate(u))])
		]);
		dom.content(this.elLive, [
			h('div', { 'class': 'krt-now' }, 'Şu an'),
			h('div', { 'class': 'krt-lives' }, [pill('v', 'VPN', r.vd, r.vu), pill('d', 'Direkt', r.dd, r.du)]),
			h('div', { 'class': 'krt-totals' }, [
				h('div', { 'class': 'krt-tot' }, [h('div', { 'class': 'kr-sub' }, 'VPN toplam'), h('div', { 'class': 'krt-big' }, fmtBytes(s.total.vr + s.total.vt)),
					h('div', { 'class': 'kr-sub' }, '↓ ' + fmtBytes(s.total.vr) + ' · ↑ ' + fmtBytes(s.total.vt))]),
				h('div', { 'class': 'krt-tot' }, [h('div', { 'class': 'kr-sub' }, 'Direkt toplam'), h('div', { 'class': 'krt-big' }, fmtBytes(s.total.dr + s.total.dt)),
					h('div', { 'class': 'kr-sub' }, '↓ ' + fmtBytes(s.total.dr) + ' · ↑ ' + fmtBytes(s.total.dt))])
			])
		]);

		const rows = [['Bugün', s.today], ['Dün', s.yesterday], ['Bu hafta', s.week], ['Bu ay', s.month], ['Toplam' + (s.since ? ' (' + s.since.split('-').reverse().join('.') + '\'den beri)' : ''), s.total]];
		const cell = b => [h('td', { 'class': 'td krt-n' }, fmtBytes(b.vr + b.vt)), h('td', { 'class': 'td krt-n kr-hide-sm kr-sub' }, '↓' + fmtBytes(b.vr) + ' ↑' + fmtBytes(b.vt))];
		dom.content(this.elPeriods, h('table', { 'class': 'table kr-table krt-table' }, [
			h('tr', { 'class': 'tr table-titles' }, [
				h('th', { 'class': 'th' }, 'Dönem'),
				h('th', { 'class': 'th krt-n', 'colspan': 2 }, [h('i', { 'class': 'krc-sw krc-vpn' }), 'VPN']),
				h('th', { 'class': 'th krt-n', 'colspan': 2 }, [h('i', { 'class': 'krc-sw krc-dir' }), 'Direkt']),
				h('th', { 'class': 'th krt-n' }, 'Hepsi')
			]),
			...rows.map(([l, b]) => h('tr', { 'class': 'tr' }, [
				h('td', { 'class': 'td' }, h('b', {}, l)), ...cell({ vr: b.vr, vt: b.vt }), ...cell({ vr: b.dr, vt: b.dt }),
				h('td', { 'class': 'td krt-n' }, fmtBytes(b.vr + b.vt + b.dr + b.dt))
			]))
		]));

		this.renderDevTraffic(s.devices || [], s.t);

		// grafik yalnızca veri ya da genişlik değişince yeniden çizilir (gezinme/ipucu titremesin)
		const sig = JSON.stringify(s.days) + '|' + (this.elChart.clientWidth || 0);
		if (sig !== this.chartSig) {
			this.chartSig = sig;
			this.days = s.days;
			this.elSvg.innerHTML = this.trafficChart(s.days);   // yalnızca sayılardan üretilen SVG
		}
	},

	/* Cihaz bazında trafik: indirme = cihaza gelen, yükleme = cihazdan giden (nft sayaçları, LAN IP'si başına).
	   Canlı hız, iki yoklama arasındaki sayaç farkından hesaplanır. */
	renderDevTraffic(devs, t) {
		const prev = this.devPrev || {}, next = {};
		if (!devs.length) {
			dom.content(this.elDevTr, h('div', { 'class': 'kr-sub' }, 'Henüz cihaz verisi yok; sayaçlar başladıktan 1-2 dakika sonra dolar.'));
			this.devPrev = next;
			return;
		}
		let sdd = 0, sdu = 0, srx = 0, stx = 0, mrx = 0, mtx = 0, trx = 0, ttx = 0;
		const rows = devs.map(dv => {
			let dd = 0, du = 0;
			const c = dv.counter, p = prev[dv.ip];
			if (c) {
				if (p && t > p.t) {
					const dt = t - p.t, f = (a, b) => (a >= b ? a - b : a) / dt;
					dd = f(c.rx, p.rx); du = f(c.tx, p.tx);
				}
				next[dv.ip] = { t: t, rx: c.rx, tx: c.tx };
			}
			sdd += dd; sdu += du;
			srx += dv.today.rx; stx += dv.today.tx; mrx += dv.month.rx; mtx += dv.month.tx; trx += dv.total.rx; ttx += dv.total.tx;
			return h('tr', { 'class': 'tr' }, [
				h('td', { 'class': 'td' }, [h('b', {}, dv.name || dv.ip), dv.name ? h('div', { 'class': 'kr-sub' }, dv.ip) : '']),
				h('td', { 'class': 'td krt-n' }, '↓ ' + fmtRate(dd) + '  ↑ ' + fmtRate(du)),
				h('td', { 'class': 'td krt-n', 'title': 'Toplam (kurulumdan beri): ' + fmtBytes(dv.total.rx + dv.total.tx) + ' · Bu ay: ' + fmtBytes(dv.month.rx + dv.month.tx) }, '↓ ' + fmtBytes(dv.today.rx) + '  ↑ ' + fmtBytes(dv.today.tx))
			]);
		});
		this.devPrev = next;
		dom.content(this.elDevTr, [
			h('table', { 'class': 'table kr-table krt-table' }, [
				h('tr', { 'class': 'tr table-titles' }, [
					h('th', { 'class': 'th' }, 'Cihaz'),
					h('th', { 'class': 'th krt-n' }, 'Şu an'),
					h('th', { 'class': 'th krt-n' }, 'Bugün')
				]),
				...rows,
				h('tr', { 'class': 'tr kr-active' }, [
					h('td', { 'class': 'td' }, [h('b', {}, 'Tüm cihazlar (' + devs.length + ')'),
						h('div', { 'class': 'kr-sub' }, 'Bu ay ↓ ' + fmtBytes(mrx) + ' ↑ ' + fmtBytes(mtx) + ' · Toplam ↓ ' + fmtBytes(trx) + ' ↑ ' + fmtBytes(ttx))]),
					h('td', { 'class': 'td krt-n' }, h('b', {}, '↓ ' + fmtRate(sdd) + '  ↑ ' + fmtRate(sdu))),
					h('td', { 'class': 'td krt-n' }, h('b', {}, '↓ ' + fmtBytes(srx) + '  ↑ ' + fmtBytes(stx)))
				])
			]),
			h('div', { 'class': 'kr-sub', 'style': 'margin-top:6px' }, '↓ cihaza gelen (indirme), ↑ cihazdan giden (yükleme). VPN ve direkt trafik birlikte sayılır. Sayaçlar modem yeniden başlasa da saklanır; donanım hızlandırma (NSS) açıksa direkt giden büyük akışlar eksik görünebilir.')
		]);
	},

	trafficHover(ev) {
		const t = ev.target && ev.target.closest ? ev.target.closest('[data-i]') : null;
		if (!t || !this.days) { this.elTip.style.display = 'none'; return; }
		const x = this.days[+t.getAttribute('data-i')];
		if (!x) return;
		const dm = x.day.split('-').reverse().join('.');
		dom.content(this.elTip, [
			h('b', {}, dm),
			h('div', {}, [h('i', { 'class': 'krc-sw krc-vpn' }), 'VPN: ' + fmtBytes(x.vr + x.vt)]),
			h('div', {}, [h('i', { 'class': 'krc-sw krc-dir' }), 'Direkt: ' + fmtBytes(x.dr + x.dt)]),
			h('div', { 'class': 'kr-sub' }, 'Toplam: ' + fmtBytes(x.vr + x.vt + x.dr + x.dt))
		]);
		const box = this.elChart.getBoundingClientRect();
		let px = ev.clientX - box.left + 12;
		this.elTip.style.display = 'block';
		if (px + this.elTip.offsetWidth > box.width) px = ev.clientX - box.left - this.elTip.offsetWidth - 12;
		this.elTip.style.left = Math.max(0, px) + 'px';
		this.elTip.style.top = '4px';
	},

	renderApps(apps) {
		const rows = apps.filter(a => a.enabled).map(a => h('div', { 'class': 'kr-app' }, [
			h('div', {}, [h('b', {}, a.name), h('div', { 'class': 'kr-sub' }, [a.ports ? 'port ' + a.ports : '', a.ips ? ' · ' + a.ips + ' IP bloğu' : '', a.domains ? ' · ' + a.domains + ' alan adı' : ''])]),
			h('div', { 'class': 'kr-seg' }, [
				h('button', { 'title': 'VPN: Bu uygulamanın trafiği VPN tünelinden çıkar. Operatör ne yaptığını görmez, siteler seni VPN sunucusunun IP\'siyle görür. Tünel koparsa bağlantı da kopar.', 'class': a.route === 'vpn' ? 'kr-act' : '', 'click': ui.createHandlerFn(this, () => a.route !== 'vpn' && this.doApp(a.sec, 'vpn')) }, 'VPN'),
				h('button', { 'title': 'Direkt: Tünele girmez, doğrudan hattan çıkar. En düşük ping; VPN yeniden başlasa bile bağlantı kopmaz. Siteler seni operatörün IP\'siyle görür (oyun ve görüntülü görüşme için uygun).', 'class': a.route === 'direct' ? 'kr-act kr-direct' : '', 'click': ui.createHandlerFn(this, () => a.route !== 'direct' && this.doApp(a.sec, 'direct')) }, 'Direkt')
			])
		]));
		this.card(this.elApps, 'apps', 'Uygulamalar — VPN mi, Direkt mi?', [
			...rows,
			h('div', { 'class': 'kr-sub', 'style': 'margin-top:8px' }, 'Direkt: çekirdekte bypass, VPN yeniden başlasa bile bağlantı kopmaz. Yeni uygulama/oyun: Ayarlar → Uygulamalar.')
		]);
	},

	renderNodes(nodes, st) {
		const act = st && st.active ? st.active.sec : null;
		const rows = nodes.map(n => h('tr', { 'class': 'tr' + (n.sec === act ? ' kr-active' : '') }, [
			h('td', { 'class': 'td' }, [h('b', {}, n.name), n.sec === act && st && st.enabled && !st.disconnected ? h('span', { 'class': 'kr-tag' }, 'BAĞLI') : '', n.json ? h('span', { 'class': 'kr-tag' }, 'JSON') : '', n.sub ? h('span', { 'class': 'kr-tag' }, 'abonelik') : '']),
			h('td', { 'class': 'td' }, [n.protocol, n.network, n.tls].filter(x => x && x !== 'none').join(' · ')),
			h('td', { 'class': 'td kr-hide-sm' }, (n.address || '') + ':' + (n.port || '')),
			h('td', { 'class': 'td' }, pingBadge(n.ping, n.rtt, n.warm)),
			h('td', { 'class': 'td', 'style': 'white-space:nowrap' }, [
				btn.call(this, 'Ping', '', () => this.doPing(n.sec)), ' ',
				btn.call(this, 'Düzenle', '', () => this.openEditor(n.sec)), ' ',
				n.sec === act && st && st.enabled && !st.disconnected ? [btn.call(this, 'Bağlantıyı kes', 'cbi-button-negative', () => this.doUse('none'), 'Sunucudan kopar; VPN açık kalır, trafik doğrudan çıkar'), ' '] : '',
				n.sec === act && st && st.enabled && !st.auto && !st.disconnected ? '' : [btn.call(this, 'Bağlan', 'cbi-button-action', () => this.doUse(n.sec)), ' '],
				btn.call(this, '✕', 'cbi-button-negative', () => this.doDelete(n), 'Sil')
			])
		]));
		this.card(this.elNodes, 'nodes', 'Sunucular (' + nodes.length + ')', [
			h('div', { 'class': 'kr-row', 'style': 'margin:0 0 10px' }, [
				btn.call(this, '⚡ Tümünü ölç', 'cbi-button-action', () => this.doPing(null)),
				btn.call(this, '+ Link / JSON ekle', 'cbi-button-positive', () => this.showAdd()),
				btn.call(this, '+ Elle ekle', '', () => this.openEditor(null)),
				btn.call(this, '↻ Aboneliği güncelle', '', () => this.doSub()),
				nodes.some(n => n.insecure) ? btn.call(this, '🔒 Sertifikayı sabitle', '', () => this.doPin(null), 'Sunucunun şu anki sertifikasını sabitler; değiştiyse tüneli yeniden başlatır') : ''
			]),
			nodes.length ? h('table', { 'class': 'table kr-table' }, [
				h('tr', { 'class': 'tr table-titles' }, [
					h('th', { 'class': 'th' }, 'Ad'), h('th', { 'class': 'th' }, 'Tür'), h('th', { 'class': 'th kr-hide-sm' }, 'Adres'),
					h('th', { 'class': 'th', 'title': 'Ping = sunucuya ağ gecikmesi · tünel = açık bağlantıdaki istek (parantez içi: sıfırdan bağlanma)' }, 'Ping'), h('th', { 'class': 'th' }, '')
				]),
				...rows
			]) : h('p', {}, 'Henüz sunucu yok. "Link / JSON ekle" ile ekle ya da Ayarlar\'dan abonelik gir.')
		]);
	},

	renderDevices(devs) {
		const on = devs.filter(d => d.online).length;
		// Yön: dört buton — Varsayılan / VPN / Direkt / Engelle (engelli kırmızı)
		const MODES = [
			['default', 'Varsayılan', '', 'Varsayılan: Bu cihaza özel kural yok, genel ayara uyar.'],
			['vpn', 'VPN', '', 'VPN: Bu cihazın tüm trafiği VPN tünelinden çıkar; siteler VPN sunucusunun IP\'sini görür.'],
			['direct', 'Direkt', 'kr-direct', 'Direkt: Bu cihaz tüneli hiç kullanmaz, doğrudan hattan çıkar (en düşük ping; IP\'si operatörün IP\'si olur).'],
			['block', 'Engelle', 'kr-block', 'Engelle: Bu cihaz internete hiç çıkamaz (ne VPN ne direkt).']
		];
		const mkRow = (d, off) => {
			const cur = d.mode || 'default';
			const seg = h('div', { 'class': 'kr-seg kr-seg-sm' }, MODES.map(([v, label, cls, tip]) =>
				h('button', {
					'class': (cur === v ? 'kr-act ' + cls : (cls === 'kr-block' ? 'kr-blockbtn' : '')),
					'title': tip,
					'click': ui.createHandlerFn(this, () => cur !== v && this.doDevice(d, v))
				}, label)));
			return h('tr', { 'class': 'tr' + (cur === 'block' ? ' kr-blocked' : '') }, [
				h('td', { 'class': 'td' }, [
					h('span', { 'class': 'kr-dot ' + (cur === 'block' ? 'kr-err' : d.online ? 'kr-on' : 'kr-off') }),
					d.name || '(adsız)',
					cur === 'block' ? h('span', { 'class': 'kr-tag kr-tag-red' }, 'ENGELLİ') : ''
				]),
				h('td', { 'class': 'td' }, d.ip || '-'),
				h('td', { 'class': 'td kr-hide-sm' }, d.mac),
				h('td', { 'class': 'td kr-hide-sm krt-n' }, d.online && d.uptime != null ? live(d.uptime) : (d.off_for != null ? 'çevrimdışı ' + Math.max(1, Math.round(d.off_for / 60)) + ' dk' : '—')),
				h('td', { 'class': 'td' }, seg),
				h('td', { 'class': 'td' }, off ? (d.sec ? btn.call(this, 'Kaydı sil', '', () => this.doDevice(d, 'default'), 'Bu çevrimdışı cihazın kayıtlı yönünü sil') : '') : (d.ip ? btn.call(this, 'Bağlantılar', '', () => this.showConns(d.ip), 'Bu cihazın şu an açık olan bağlantılarını listeler: hangi adrese ve porta, VPN\'den mi direkt mi gittiği. Bir uygulamanın hangi adresi/portu kullandığını görüp yön kuralına eklemek için.') : ''))
			]);
		};
		// Çevrimdışı cihazlar (yalnızca kayıtlı yönü olanlar) varsayılan olarak gizli; istenirse açılır
		const offl = devs.filter(d => !d.online);
		const rows = devs.filter(d => d.online).map(d => mkRow(d, false));
		const offRows = this.showOff ? offl.map(d => mkRow(d, true)) : [];
		const offBar = offl.length ? h('div', { 'style': 'margin-top:8px' }, [
			btn.call(this, (this.showOff ? '▾ ' : '▸ ') + 'Çevrimdışı cihazlar (' + offl.length + ')', '',
				() => { this.showOff = !this.showOff; this.renderDevices(devs); },
				'Şu an bağlı olmayan cihazlar (rastgele MAC kullanan telefonlar kayıtlı yönüyle burada birikebilir)')
		]) : '';
		const warn = (this.directDead && !this.autoOff) ? h('div', { 'class': 'kr-warn' }, [
			'Direkt çıkış şu an YOK görünüyor (hat VPN olmadan internete çıkamıyor ya da denetim henüz tamamlanmadı). Bu yüzden "Direkt" seçili cihazlar ve uygulamalar da VPN üzerinden çıkıyor. ',
			btn.call(this, 'Yeniden denetle', '', () => this.doDirectCheck(), 'Direkt çıkışı şimdi ölç')
		]) : '';
		const chk = h('input', { 'type': 'checkbox', 'checked': this.autoOff ? '' : null, 'change': ui.createHandlerFn(this, ev => this.doAutoDirect(ev.target.checked)) });
		const autoRow = h('label', { 'style': 'display:flex;gap:8px;align-items:center;margin:0 0 10px;cursor:pointer' }, [chk, 'Direkt seçilenler her durumda direkt çıksın (hat VPN\'siz çıkamıyorsa o cihaz internetsiz kalabilir)']);
		this.card(this.elDevs, 'devs', 'Cihazlar (' + on + ' bağlı)', h('div', {}, [warn, autoRow, h('table', { 'class': 'table kr-table' }, [
			h('tr', { 'class': 'tr table-titles' }, ['Cihaz', 'IP', 'MAC', 'Bağlı süre', 'Yön', ''].map((x, i) =>
				h('th', { 'class': 'th' + (i === 2 || i === 3 ? ' kr-hide-sm' : '') }, x))),
			...rows, ...offRows
		]), offBar]));
	},

	render(data) {
		const [st, nodes, apps, devs] = data;
		this.nodes = nodes || [];
		this.elStatus = h('div', { 'class': 'kr-card' });
		this.elNode = h('div', { 'class': 'kr-card' });
		this.elApps = h('div', { 'class': 'kr-card' });
		this.elNodes = h('div', { 'class': 'kr-card', 'style': 'margin-bottom:14px' });
		this.elDevs = h('div', { 'class': 'kr-card' });

		this.renderStatus(st);
		this.renderApps(apps || []);
		this.renderNodes(nodes || [], st);
		this.renderDevices(devs || []);
		this.fetchDirect().then(ch => { if (ch) this.renderDevices(devs || []); });

		// canlı süre sayaçları (Açık / Bağlı süre) her saniye ilerler
		// poll ile: sayfadan çıkınca LuCI durdurur, sekme arkadayken boşa çalışmaz
		poll.add(() => tickLive(), 1);
		poll.add(() => runJson(['status', '--json']).then(s => { if (s) this.renderStatus(s); }), 5);
		// cihaz listesi: yeni bağlanan/ayrılan görünsün (değişmediyse tabloya dokunulmaz)
		poll.add(() => Promise.all([runJson(['devices']), this.fetchDirect()]).then(([d]) => {
			if (!d) return;
			const sig = JSON.stringify(d.map(x => [x.mac, x.ip, x.name, x.mode, x.online])) + '|' + this.directDead + this.autoOff;
			if (sig === this.devSig) return;
			this.devSig = sig;
			this.renderDevices(d);
		}), 30);

		return h('div', {}, [
			h('style', {}, CSS),
			h('h2', {}, [h('img', { 'src': '/luci-static/kedi-logo.svg', 'style': 'height:1.3em;vertical-align:-0.25em;margin-right:8px;border-radius:6px' }), 'KediRay VPN']),
			h('div', { 'class': 'kr-grid' }, [this.elStatus, this.elNode, this.elApps]),
			this.elNodes,
			this.elDevs
		]);
	},

	handleSaveApply: null,
	handleSave: null,
	handleReset: null
});
KEDIRAY_EOF_13
cat > '/www/luci-static/resources/view/kediray/trafik.js' <<'KEDIRAY_EOF_24'
'use strict';
'require view';
'require fs';
'require ui';
'require poll';
'require dom';

/* KediRay - Trafik (Kontrol Paneli'nden ayrıldı; aynı kodu paylaşır) */

/* Güvenli öğe oluşturucu: LuCI'nin E()'si iç içe dizileri "[object HTMLButtonElement]," diye metne çevirir ve
 * tek bir metni innerHTML olarak basar (abonelikten gelen bir sunucu adı HTML çalıştırabilir). h() dizileri
 * düzleştirir, boşları atar ve her metni düz metin düğümü olarak ekler. */
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

function run(args) {
	return fs.exec(CLI, args).catch(e => ({ code: 1, stdout: '', stderr: String(e) }));
}
function runJson(args) {
	return run(args).then(r => { try { return JSON.parse(r.stdout || 'null'); } catch (e) { return null; } });
}
function fmtBytes(b) {
	b = +b || 0;
	const u = ['B', 'KB', 'MB', 'GB', 'TB']; let i = 0;
	while (b >= 1024 && i < u.length - 1) { b /= 1024; i++; }
	return (i ? b.toFixed(1) : b) + ' ' + u[i];
}
function fmtRate(b) { return fmtBytes(b) + '/s'; }
// süre: 3 gün 5 sa 22 dk · 5 sa 22 dk 10 sn · 14 dk 49 sn · 49 sn
function fmtDur(s) {
	s = Math.max(0, Math.floor(+s || 0));
	const g = Math.floor(s / 86400), h2 = Math.floor(s % 86400 / 3600), m = Math.floor(s % 3600 / 60), sn = s % 60;
	const p = v => String(v).padStart(2, '0');
	if (g) return g + ' gün ' + h2 + ' sa ' + p(m) + ' dk';
	if (h2) return h2 + ' sa ' + p(m) + ' dk ' + p(sn) + ' sn';
	if (m) return m + ' dk ' + p(sn) + ' sn';
	return sn + ' sn';
}
/* Canlı sayaç: değer render anında damgalanır, her saniye tarayıcıda ilerler
   (modem saatiyle tarayıcı saati farklı olabilir; fark değil, geçen süre sayılır) */
function live(seconds, cls) {
	const v = Math.max(0, Math.floor(+seconds || 0));
	return h('span', {
		'class': 'kr-live' + (cls ? ' ' + cls : ''),
		'data-base': String(v),
		'data-at': String(Date.now())
	}, fmtDur(v));
}
function tickLive(root) {
	const now = Date.now();
	(root || document).querySelectorAll('.kr-live').forEach(e => {
		const base = +e.getAttribute('data-base'), at = +e.getAttribute('data-at');
		if (!isFinite(base) || !isFinite(at)) return;
		e.textContent = fmtDur(base + (now - at) / 1000);
	});
}
// üst köşeleri r kadar yuvarlak, tabanı düz çubuk yolu (SVG path)
function roundTop(x, y, w, hgt, r) {
	r = Math.max(0, Math.min(r, hgt, w / 2));
	const f = v => v.toFixed(1);
	return 'M' + f(x) + ',' + f(y + hgt) + ' V' + f(y + r) + ' Q' + f(x) + ',' + f(y) + ' ' + f(x + r) + ',' + f(y) +
		' H' + f(x + w - r) + ' Q' + f(x + w) + ',' + f(y) + ' ' + f(x + w) + ',' + f(y + r) + ' V' + f(y + hgt) + ' Z';
}
// rtt = gerçek ağ gecikmesi (sunucuya TCP), ms = tünel testi (yeni bağlantı + tam web isteği)
function pingBadge(ms, rtt, warm) {
	if (ms == null && rtt == null) return h('span', { 'class': 'kr-ping kr-na' }, '—');
	if (ms != null && ms < 0) return h('span', { 'class': 'kr-ping kr-bad', 'title': 'Tünel kurulamadı' }, 'yok');
	const tip = 'Ping: modemden sunucuya gerçek ağ gecikmesi.\n' +
		'Tünel (yeni): sıfırdan bağlantı açıp tam bir web isteği yapma süresi — TCP + TLS + WebSocket el sıkışmaları dahil (v2rayNG "gerçek gecikme").\n' +
		'Tünel (açık): aynı bağlantıdan giden ikinci isteğin süresi — sayfaların ve oyunun gerçekte hissettiği gecikme budur.';
	const parts = [];
	if (rtt != null && rtt > 0)
		parts.push(h('span', { 'class': 'kr-ping ' + (rtt < 60 ? 'kr-good' : rtt < 150 ? 'kr-mid' : 'kr-bad') }, rtt + ' ms'));
	if (warm != null && warm > 0)
		parts.push(h('span', { 'class': 'kr-sub', 'style': 'font-size:.8em;margin-left:4px' }, 'tünel ' + warm));
	else if (ms != null && ms > 0 && rtt != null && rtt > 0)
		parts.push(h('span', { 'class': 'kr-sub', 'style': 'font-size:.8em;margin-left:4px' }, 'tünel ' + ms));
	if (ms != null && ms > 0 && warm != null && warm > 0 && ms > warm)
		parts.push(h('span', { 'class': 'kr-sub', 'style': 'font-size:.8em;margin-left:4px;opacity:.55' }, '(ilk ' + ms + ')'));
	if (!parts.length)
		return h('span', { 'class': 'kr-ping ' + (ms < 150 ? 'kr-good' : ms < 400 ? 'kr-mid' : 'kr-bad'), 'title': tip }, ms + ' ms');
	return h('span', { 'style': 'white-space:nowrap', 'title': tip }, parts);
}
function btn(label, cls, fn, title) {
	return h('button', { 'class': 'btn cbi-button ' + (cls || ''), 'title': title || '', 'click': ui.createHandlerFn(this, fn) }, label);
}

/* Katı JSON denetleyici: ilk hatanın satır/sütununu ve Türkçe açıklamasını verir (null = hatasız) */
function jsonCheck(s) {
	let i = 0, err = null;
	const n = s.length;
	const ch = () => (i < n ? s[i] : '');
	const fail = m => { if (!err) err = { pos: i, msg: m }; return false; };
	const ws = () => { while (i < n && ' \t\r\n'.indexOf(s[i]) >= 0) i++; };
	const str = () => {
		i++;
		while (i < n) {
			const c = s[i];
			if (c === '"') { i++; return true; }
			if (c === '\\') { i += 2; continue; }
			if (c === '\n') return fail('Metin bitmeden satır sonu geldi (kapanış tırnağı " eksik)');
			i++;
		}
		return fail('Kapanış tırnağı " eksik');
	};
	const num = () => {
		const m = /^-?(0|[1-9]\d*)(\.\d+)?([eE][+-]?\d+)?/.exec(s.slice(i, i + 64));
		if (!m) return fail('Geçersiz sayı');
		i += m[0].length; return true;
	};
	let value;
	const obj = () => {
		i++; ws();
		if (ch() === '}') { i++; return true; }
		for (;;) {
			ws();
			const c = ch();
			if (c === '}') return fail("Son öğeden sonra fazladan virgül var (',' sil)");
			if (c === "'") return fail('Anahtarlar tek tırnakla değil çift tırnakla (") yazılmalı');
			if (c !== '"') return fail(i >= n ? "'}' kapanmamış (metin erken bitti)" : 'Anahtar çift tırnak (") içinde olmalı');
			if (!str()) return false;
			ws();
			if (ch() !== ':') return fail("Anahtardan sonra ':' bekleniyordu");
			i++;
			if (!value()) return false;
			ws();
			const d = ch();
			if (d === ',') { i++; continue; }
			if (d === '}') { i++; return true; }
			if (i >= n) return fail("'}' kapanmamış (metin erken bitti)");
			return fail("',' veya '}' bekleniyordu (önceki satırın sonunda virgül eksik olabilir)");
		}
	};
	const arr = () => {
		i++; ws();
		if (ch() === ']') { i++; return true; }
		for (;;) {
			ws();
			if (ch() === ']') return fail("Son öğeden sonra fazladan virgül var (',' sil)");
			if (!value()) return false;
			ws();
			const d = ch();
			if (d === ',') { i++; continue; }
			if (d === ']') { i++; return true; }
			if (i >= n) return fail("']' kapanmamış (metin erken bitti)");
			return fail("',' veya ']' bekleniyordu");
		}
	};
	value = () => {
		ws();
		const c = ch();
		if (c === '{') return obj();
		if (c === '[') return arr();
		if (c === '"') return str();
		if (c === '-' || (c >= '0' && c <= '9')) return num();
		if (s.startsWith('true', i) || s.startsWith('null', i)) { i += 4; return true; }
		if (s.startsWith('false', i)) { i += 5; return true; }
		if (c === "'") return fail('Metinler tek tırnakla değil çift tırnakla (") yazılmalı');
		if (i >= n) return fail('Beklenmedik son: değer bekleniyordu');
		return fail("Geçersiz değer '" + c + "' (metinler çift tırnak içinde olmalı)");
	};
	if (value()) { ws(); if (i < n) fail('JSON bittikten sonra fazladan içerik var'); }
	if (!err) return null;
	let line = 1, col = 1;
	for (let k = 0; k < err.pos && k < n; k++) { if (s[k] === '\n') { line++; col = 1; } else col++; }
	return { line, col, msg: err.msg, pos: err.pos };
}

/* Form alanları: [ad, etiket, tür, seçenekler, görünür mü?] */
const isV = f => f.protocol === 'vless' || f.protocol === 'vmess';
const notSS = f => f.protocol !== 'shadowsocks';
const hasPath = f => notSS(f) && (['ws', 'xhttp', 'httpupgrade'].includes(f.network) || (f.network === 'tcp' && f.header_type === 'http'));
const isTLS = f => notSS(f) && (f.tls === 'tls' || f.tls === 'reality');
const FIELDS = [
	['protocol', 'Protokol', 'select', [['vless', 'VLESS'], ['vmess', 'VMess'], ['trojan', 'Trojan'], ['shadowsocks', 'Shadowsocks']]],
	['address', 'Adres (IP ya da alan adı)', 'text'],
	['port', 'Port', 'text'],
	['uuid', 'UUID', 'text', null, isV],
	['password', 'Parola', 'text', null, f => f.protocol === 'trojan' || f.protocol === 'shadowsocks'],
	['method', 'Şifreleme', 'select', ['aes-128-gcm', 'aes-256-gcm', 'chacha20-poly1305', 'chacha20-ietf-poly1305', 'xchacha20-poly1305',
		'2022-blake3-aes-128-gcm', '2022-blake3-aes-256-gcm', '2022-blake3-chacha20-poly1305'], f => f.protocol === 'shadowsocks'],
	['flow', 'Flow', 'select', [['', 'Yok'], ['xtls-rprx-vision', 'xtls-rprx-vision']], f => f.protocol === 'vless'],
	['network', 'Aktarım', 'select', [['ws', 'WebSocket (ws)'], ['tcp', 'TCP / raw'], ['grpc', 'gRPC'], ['xhttp', 'XHTTP'], ['httpupgrade', 'HTTPUpgrade']], notSS],
	['header_type', 'TCP başlık', 'select', [['', 'Yok'], ['http', 'HTTP gizleme']], f => notSS(f) && f.network === 'tcp'],
	['path', 'Yol (path)', 'text', null, hasPath],
	['host', 'Host', 'text', null, hasPath],
	['service_name', 'gRPC servis adı', 'text', null, f => notSS(f) && f.network === 'grpc'],
	['xhttp_mode', 'XHTTP modu', 'select', ['auto', 'packet-up', 'stream-up', 'stream-one'], f => notSS(f) && f.network === 'xhttp'],
	['tls', 'Güvenlik', 'select', [['none', 'Yok'], ['tls', 'TLS'], ['reality', 'REALITY']], notSS],
	['sni', 'SNI', 'text', null, isTLS],
	['fp', 'Parmak izi (uTLS)', 'select', [['', 'Yok (v2rayNG varsayılanı)'], 'chrome', 'firefox', 'safari', 'ios', 'android', 'edge', 'random', 'randomized'], isTLS],
	['alpn', 'ALPN', 'text', null, f => notSS(f) && f.tls === 'tls'],
	['insecure', 'Sertifikayı doğrulama (otomatik sabitlenir)', 'checkbox', null, f => notSS(f) && f.tls === 'tls'],
	['pbk', 'REALITY public key', 'text', null, f => notSS(f) && f.tls === 'reality'],
	['sid', 'REALITY short id', 'text', null, f => notSS(f) && f.tls === 'reality'],
	['spx', 'REALITY spiderX', 'text', null, f => notSS(f) && f.tls === 'reality']
];
const JSON_TEMPLATE = JSON.stringify({
	protocol: 'vless',
	settings: { vnext: [{ address: '1.2.3.4', port: 443, users: [{ id: 'UUID-BURAYA', encryption: 'none' }] }] },
	streamSettings: { network: 'ws', security: 'tls', tlsSettings: { serverName: 'alan.adi' }, wsSettings: { path: '/', host: 'alan.adi' } }
}, null, 2);
const STAGE = { syntax: 'Yazım hatası', fields: 'Eksik ya da hatalı alan', xray: 'Xray bu ayarı kabul etmedi', save: 'Kaydedilemedi', uci: 'Ayar dosyası okunamadı', node: 'Sunucu hatası', gen: 'Yapılandırma üretilemedi' };

const CSS = `
.kr-grid{display:grid;grid-template-columns:repeat(auto-fit,minmax(300px,1fr));gap:14px;margin-bottom:14px}
.kr-card{border:1px solid rgba(128,128,128,.25);border-radius:10px;padding:14px 16px;background:rgba(128,128,128,.04)}
.kr-card h3{margin:0 0 10px;font-size:1.05em;opacity:.85}
.kr-ch{cursor:pointer;user-select:none;display:flex;align-items:center;gap:7px}
.kr-ch:hover{opacity:1}
.kr-caret{font-size:.85em;opacity:.7;width:12px}
.kr-ct{flex:1}
.kr-cbody.kr-fold{display:none}
.kr-blocked td{opacity:.75}
.kr-big{font-size:1.35em;font-weight:600;margin:2px 0 6px;word-break:break-all}
.kr-sub{opacity:.7;font-size:.9em}
.kr-addr{margin-top:6px;font-size:.92em;word-break:break-all}
.kr-mono{font-family:ui-monospace,Menlo,Consolas,monospace;background:rgba(128,128,128,.14);border-radius:5px;padding:1px 6px;user-select:all}
.kr-live{font-variant-numeric:tabular-nums}
.kr-row{display:flex;gap:8px;flex-wrap:wrap;align-items:center;margin-top:10px}
.kr-dot{display:inline-block;width:10px;height:10px;border-radius:50%;margin-right:6px;vertical-align:middle}
.kr-on{background:#22a355}.kr-off{background:#999}.kr-err{background:#d23f3f}
.kr-ping{display:inline-block;min-width:54px;text-align:center;padding:1px 8px;border-radius:10px;font-size:.85em;font-weight:600}
.kr-good{background:rgba(34,163,85,.18);color:#1b8a47}.kr-mid{background:rgba(230,160,20,.2);color:#a86d00}
.kr-bad{background:rgba(210,63,63,.18);color:#b52f2f}.kr-na{background:rgba(128,128,128,.15)}
.kr-seg{display:inline-flex;border:1px solid rgba(128,128,128,.4);border-radius:8px;overflow:hidden}
.kr-seg button{border:0;border-radius:0;margin:0;padding:4px 14px;background:transparent;cursor:pointer;color:inherit;white-space:nowrap;word-break:keep-all}
.kr-seg button.kr-act{background:#2a7de1;color:#fff}
.kr-seg button.kr-act.kr-direct{background:#22a355}
.kr-seg button.kr-act.kr-block{background:#d23f3f;color:#fff}
.kr-seg button.kr-blockbtn{color:#d23f3f}
.kr-seg button.kr-blockbtn:hover{background:rgba(210,63,63,.15)}
.kr-seg-sm button{padding:4px 10px;font-size:.92em}
@media (max-width:700px){.kr-seg-sm{display:grid;grid-template-columns:1fr 1fr}.kr-seg-sm button{padding:6px 8px;border-top:1px solid rgba(128,128,128,.25)}.kr-seg-sm button:nth-child(-n+2){border-top:0}.kr-seg-sm button:nth-child(odd){border-right:1px solid rgba(128,128,128,.25)}}
.kr-warn{border:1px solid #e0a100;background:rgba(224,161,0,.12);border-radius:8px;padding:8px 10px;margin:0 0 10px;font-size:.92em}
.kr-seg.kr-dim{opacity:.4}
.kr-seg.kr-dim button.kr-act{background:transparent;color:inherit}
.kr-app{display:flex;justify-content:space-between;align-items:center;padding:7px 0;border-bottom:1px dashed rgba(128,128,128,.25)}
.kr-app:last-child{border-bottom:0}
.kr-stat{display:grid;grid-template-columns:auto 1fr 1fr;gap:4px 14px;font-variant-numeric:tabular-nums}
.kr-tag{display:inline-block;padding:0 6px;border-radius:6px;background:rgba(42,125,225,.15);font-size:.8em;margin-left:6px}
.kr-tag.kr-tag-red{background:rgba(210,63,63,.2);color:#e05252}
.kr-table td,.kr-table th{padding:6px 8px!important;vertical-align:middle}
.kr-active{background:rgba(42,125,225,.08)}
.kr-tabs{display:flex;gap:4px;margin:8px 0}
.kr-tabs button{border:1px solid rgba(128,128,128,.4);background:transparent;color:inherit;padding:5px 16px;border-radius:8px 8px 0 0;cursor:pointer}
.kr-tabs button.kr-act{background:#2a7de1;color:#fff;border-color:#2a7de1}
.kr-form{display:grid;grid-template-columns:minmax(120px,190px) 1fr;gap:6px 12px;align-items:center}
.kr-form label{opacity:.85}
.kr-form input[type=text],.kr-form select{width:100%;box-sizing:border-box}
.kr-bad-input{outline:2px solid #d23f3f!important}
.modal.kr-wide{max-width:min(1150px,97vw)!important;width:97vw!important}
.kr-ed{display:flex;border:1px solid rgba(128,128,128,.45);border-radius:6px;overflow:hidden}
.kr-gut{margin:0;padding:6px 6px 6px 4px;min-width:34px;text-align:right;opacity:.5;user-select:none;overflow:hidden;background:rgba(128,128,128,.08);font-family:ui-monospace,Menlo,Consolas,monospace;font-size:12.5px;line-height:1.45}
.kr-json{flex:1;min-width:0;box-sizing:border-box;border:0!important;margin:0;padding:6px 8px;resize:vertical;height:420px;font-family:ui-monospace,Menlo,Consolas,monospace;font-size:12.5px;line-height:1.45;tab-size:2;white-space:pre;overflow:auto}
.kr-json.kr-wrap{white-space:pre-wrap;word-break:break-all}
.kr-view{max-height:72vh;overflow:auto;white-space:pre;font-size:12px;background:rgba(128,128,128,.08);padding:10px;border-radius:6px}
.kr-switch{display:flex;align-items:flex-start;gap:9px;cursor:pointer;user-select:none}
.kr-switch input{display:none}
/* flex:0 0 40px -> yazı uzayınca anahtarın rayı ezilmez (top raydan taşmaz) */
.kr-switch span.kr-knob{flex:0 0 40px;width:40px;height:22px;border-radius:11px;background:#999;position:relative;transition:.2s;margin-top:1px}
.kr-switch > span:last-child{flex:1;min-width:0}
.kr-switch span.kr-knob:after{content:'';position:absolute;top:3px;left:3px;width:16px;height:16px;border-radius:50%;background:#fff;transition:.2s}
.kr-switch input:checked + span.kr-knob{background:#22a355}
.kr-switch input:checked + span.kr-knob:after{left:21px}
.kr-srv{display:flex;gap:8px;align-items:center;flex-wrap:wrap;margin-top:8px}
.kr-srv select{min-width:220px;max-width:100%}
.kr-jstat{margin:6px 0;font-size:.9em}
.kr-ok{color:#1b8a47}.kr-no{color:#b52f2f}
.kr-errs{margin:8px 0;padding:8px 12px;border-radius:8px;background:rgba(210,63,63,.1);border:1px solid rgba(210,63,63,.4)}
.kr-errs li{margin:3px 0}
.kr-hint{font-size:.85em;opacity:.8;margin-top:6px}
.kr-traffic{--krc-vpn:#2a78d6;--krc-dir:#eb6834;--krc-surface:#fcfcfb}
@media (prefers-color-scheme: dark){:root:not([data-theme="light"]) .kr-traffic{--krc-vpn:#3987e5;--krc-dir:#d95926;--krc-surface:#1a1a19}}
:root[data-theme="dark"] .kr-traffic{--krc-vpn:#3987e5;--krc-dir:#d95926;--krc-surface:#1a1a19}
.krc-sw{display:inline-block;width:10px;height:10px;border-radius:2px;margin-right:6px;vertical-align:baseline}
.krc-vpn{fill:var(--krc-vpn);background:var(--krc-vpn)}
.krc-dir{fill:var(--krc-dir);background:var(--krc-dir)}
.krc-title{margin:14px 0 4px;font-weight:600;opacity:.85}
.krc-legend{display:flex;gap:16px;flex-wrap:wrap;font-size:.9em;margin:2px 0 6px}
.krc-wrap{position:relative;width:100%}
.krc-svg{display:block;max-width:100%}
.krc-grid{stroke:rgba(128,128,128,.25);stroke-width:1}
.krc-ax{fill:currentColor;opacity:.65;font-size:11px}
.krc-hit{fill:transparent;cursor:crosshair}
.krc-hit:hover{fill:rgba(128,128,128,.12)}
.krc-tip{position:absolute;z-index:5;pointer-events:none;padding:6px 10px;border-radius:8px;font-size:.88em;line-height:1.45;background:var(--krc-surface);color:inherit;border:1px solid rgba(128,128,128,.4);box-shadow:0 2px 8px rgba(0,0,0,.25);white-space:nowrap}
.krt-now{font-weight:600;opacity:.85;margin:0 0 6px}
.krt-lives{display:grid;grid-template-columns:repeat(auto-fit,minmax(200px,1fr));gap:10px}
.krt-live{border:1px solid rgba(128,128,128,.25);border-radius:8px;padding:8px 12px}
.krt-lh{font-weight:600;margin-bottom:4px}
.krt-lv{display:flex;gap:18px;flex-wrap:wrap;font-variant-numeric:tabular-nums;font-size:1.1em}
.krt-totals{display:grid;grid-template-columns:repeat(auto-fit,minmax(200px,1fr));gap:10px;margin:10px 0 4px}
.krt-tot{padding:2px 2px}
.krt-big{font-size:1.5em;font-weight:600;font-variant-numeric:tabular-nums}
.krt-table{margin-top:10px}
.krt-n{text-align:right;font-variant-numeric:tabular-nums;white-space:nowrap}
.krt-table th.krt-n{text-align:right}
.kr-warn{margin-top:10px;padding:8px 10px;border-radius:8px;background:rgba(230,160,20,.15);border:1px solid rgba(230,160,20,.45);font-size:.9em}
@media(max-width:600px){.kr-hide-sm{display:none}}
`;

// Tarayıcıda saklanan eski menüyü (Hizmetler altındaki kayıt) bir kez temizle
try {
	if (!sessionStorage.getItem('kediray-menu-v2')) {
		sessionStorage.setItem('kediray-menu-v2', '1');
		if (ui.menu && ui.menu.flushCache) ui.menu.flushCache();
	}
} catch (e) {}

function collapsed(key) {
	try { return localStorage.getItem('kediray-fold-' + key) === '1'; } catch (e) { return false; }
}

/* KR-PANEL-BASLA */
/* IP/MAC gizleme (Cihazlar tablosu) */
(function () {
	var KEY = 'kr_hide_ids', busy = false;
	var on = function () { try { return localStorage.getItem(KEY) === '1'; } catch (e) { return false; } };
	var isIp = /^\d+\.\d+\.\d+\.\d+$/, isMac = /^([0-9a-f]{2}:){5}[0-9a-f]{2}$/i;
	function mask(t, n) {
		if (n === 0 && isIp.test(t)) return '•••.•••.•••.' + t.split('.')[3];
		if (n === 1 && isMac.test(t)) return '••:••:••:••:' + t.split(':').slice(4).join(':');
		return t;
	}
	function apply() {
		if (busy) return; busy = true;
		try {
			document.querySelectorAll('table.kr-table').forEach(function (tb) {
				var hdr = tb.querySelector('tr.table-titles'); if (!hdr) return;
				var ths = [].map.call(hdr.children, function (c) { return c.textContent.trim(); });
				var ii = ths.indexOf('IP'), mi = ths.indexOf('MAC'); if (ii < 0 || mi < 0) return;
				var host = tb.parentNode;
				if (host && !host.querySelector('.kr-hide-box')) {
					var cb = document.createElement('input'); cb.type = 'checkbox'; cb.checked = on();
					cb.addEventListener('change', function () { try { localStorage.setItem(KEY, cb.checked ? '1' : '0'); } catch (e) {} apply(); });
					var lb = document.createElement('label'); lb.className = 'kr-hide-box'; lb.style.cssText = 'display:inline-flex;gap:6px;align-items:center;margin:0 0 8px;cursor:pointer';
					lb.appendChild(cb); lb.appendChild(document.createTextNode('IP ve MAC adreslerini gizle'));
					host.insertBefore(lb, tb);
				}
				var box = host && host.querySelector('.kr-hide-box input'); if (box) box.checked = on();
				[].forEach.call(tb.querySelectorAll('tr'), function (tr) {
					if (tr === hdr) return;
					[ii, mi].forEach(function (ix, n) {
						var td = tr.children[ix]; if (!td) return;
						var orig = td.getAttribute('data-orig'), cur = td.textContent;
						if (orig === null || (cur !== orig && cur !== td.getAttribute('data-masked'))) {
							if (!(n === 0 ? isIp : isMac).test(cur)) return;
							orig = cur; td.setAttribute('data-orig', cur);
						}
						var want = on() ? mask(orig, n) : orig;
						if (td.textContent !== want) { td.setAttribute('data-masked', want); td.textContent = want; }
					});
				});
			});
		} finally { busy = false; }
	}
	new MutationObserver(function () { apply(); }).observe(document.documentElement, { childList: true, subtree: true });
})();
/* Sunucu bilgilerini / bağlı sunucu IP'sini gizleme */
(function () {
	var KS = 'kr_hide_srv', KI = 'kr_hide_srvip', secrets = [], orig = new WeakMap(), pend = false;
	var get = function (k) { try { return localStorage.getItem(k) === '1'; } catch (e) { return false; } };
	var set = function (k, v) { try { localStorage.setItem(k, v ? '1' : '0'); } catch (e) {} };
	var IPRE = /\b(\d{1,3})\.(\d{1,3})\.(\d{1,3})\.(\d{1,3})\b/g;
	function priv(a, b) { return a === 10 || a === 127 || a === 0 || (a === 192 && b === 168) || (a === 172 && b >= 16 && b <= 31) || (a === 169 && b === 254); }
	function loadSecrets() {
		try {
			var env = (window.L && L.env) || {};
			fetch(env.ubuspath || '/ubus/', { method: 'POST', body: JSON.stringify({ jsonrpc: '2.0', id: 1, method: 'call',
				params: [env.sessionid, 'uci', 'get', { config: 'kediray' }] }) })
			.then(function (r) { return r.json(); }).then(function (j) {
				var v = (j.result && j.result[1] && j.result[1].values) || {}, out = {};
				Object.keys(v).forEach(function (k) {
					if (v[k]['.type'] !== 'node') return;
					['address', 'sni', 'host', 'uuid', 'server'].forEach(function (f) {
						var x = v[k][f]; if (typeof x === 'string' && x.length >= 4) out[x] = 1;
					});
				});
				secrets = Object.keys(out).sort(function (a, b) { return b.length - a.length; });
				schedule();
			}).catch(function () {});
		} catch (e) {}
	}
	function conv(s, srv, ip) {
		if (srv) secrets.forEach(function (x) { if (s.indexOf(x) >= 0) s = s.split(x).join('••••••'); });
		if (ip) s = s.replace(IPRE, function (m, a, b, c, d) { return priv(+a, +b) ? m : '•••.•••.•••.' + d; });
		return s;
	}
	function ui() {
		if (document.querySelector('.kr-srv-box')) return;
		var h2 = [].filter.call(document.querySelectorAll('h2'), function (x) { return /KediRay VPN/.test(x.textContent); })[0];
		if (!h2 || !h2.parentNode) return;
		var bar = document.createElement('div'); bar.className = 'kr-srv-box';
		bar.style.cssText = 'display:flex;gap:18px;flex-wrap:wrap;margin:4px 0 10px';
		[['Sunucu bilgilerini gizle', KS]].forEach(function (p) {
			var lb = document.createElement('label'), cb = document.createElement('input');
			lb.style.cssText = 'display:inline-flex;gap:6px;align-items:center;cursor:pointer';
			cb.type = 'checkbox'; cb.checked = get(p[1]);
			cb.addEventListener('change', function () { set(p[1], cb.checked); apply(); });
			lb.appendChild(cb); lb.appendChild(document.createTextNode(p[0])); bar.appendChild(lb);
		});
		h2.parentNode.insertBefore(bar, h2.nextSibling);
	}
	function apply() {
		ui();
		var srv = get(KS), ip = srv;
		var w = document.createTreeWalker(document.body, NodeFilter.SHOW_TEXT, null), n, list = [];
		while ((n = w.nextNode())) list.push(n);
		list.forEach(function (n) {
			var p = n.parentNode; if (!p || /^(SCRIPT|STYLE|TEXTAREA)$/.test(p.nodeName) || (p.closest && p.closest('.kr-srv-box'))) return;
			var rec = orig.get(n), base = (rec && n.data === rec.m) ? rec.o : n.data;
			var m = conv(base, srv, ip);
			if (m !== n.data) { orig.set(n, { o: base, m: m }); n.data = m; }
			else if (m === base) orig.delete(n);
		});
	}
	function schedule() { if (pend) return; pend = true; setTimeout(function () { pend = false; apply(); }, 50); }
	loadSecrets();
	new MutationObserver(schedule).observe(document.documentElement, { childList: true, subtree: true, characterData: true });
})();
/* KR-PANEL-SON */

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

return view.extend({
	/* Kart: başlığa tıklayınca içerik katlanır (tercih tarayıcıda saklanır) */
	card(el, key, title, children, right) {
		const open = !collapsed(key);
		const body = h('div', { 'class': 'kr-cbody' + (open ? '' : ' kr-fold') }, children);
		const cap = h('span', { 'class': 'kr-caret' }, open ? '▾' : '▸');
		const head = h('h3', { 'class': 'kr-ch', 'title': 'Küçült / aç' }, [cap, h('span', { 'class': 'kr-ct' }, title), right || '']);
		head.addEventListener('click', ev => {
			if (ev.target.closest('button, select, input, a')) return;
			const now = body.classList.toggle('kr-fold');
			cap.textContent = now ? '▸' : '▾';
			try { localStorage.setItem('kediray-fold-' + key, now ? '1' : '0'); } catch (e) {}
		});
		dom.content(el, [head, body]);
	},

	/* Kart içindeki bölüm: başlığa tıklayınca katlanır (tercih tarayıcıda saklanır) */
	fold(key, title, content) {
		const open = !collapsed(key);
		const body = h('div', { 'class': 'kr-cbody' + (open ? '' : ' kr-fold') }, content);
		const cap = h('span', { 'class': 'kr-caret' }, open ? '▾' : '▸');
		const head = h('div', { 'class': 'krc-title kr-ch', 'title': 'Küçült / aç' }, [cap, h('span', { 'class': 'kr-ct' }, title)]);
		head.addEventListener('click', () => {
			const now = body.classList.toggle('kr-fold');
			cap.textContent = now ? '▸' : '▾';
			try { localStorage.setItem('kediray-fold-' + key, now ? '1' : '0'); } catch (e) {}
		});
		return h('div', {}, [head, body]);
	},

	lastStats: null,
	liveRate: null,
	trafficBuilt: false,
	chartSig: '',
	days: null,

	load() {
		return Promise.resolve(null);
	},

	/* ---------- işlemler ---------- */
	busy(msg, p) {
		ui.showModal(null, [h('p', { 'class': 'spinning' }, msg)]);
		return p.then(r => { ui.hideModal(); return r; }, e => { ui.hideModal(); throw e; });
	},
	note(msg, type) { ui.addNotification(null, h('p', msg), type || 'info'); },

	fetchDirect() {
		return run(['direct']).then(r => {
			const dead = /Direkt çıkış: YOK/.test(r.stdout || '');
			const off = /Otomatik direkt denetimi: KAPALI/.test(r.stdout || '');
			const ch = dead !== this.directDead || off !== this.autoOff;
			this.directDead = dead;
			this.autoOff = off;
			return ch;
		});
	},
	async doAutoDirect(off) {
		await this.busy('Uygulanıyor…', run(['autodirect', off ? 'off' : 'on']));
		return this.refreshAll();
	},
	async doDirectCheck() {
		await this.busy('Direkt çıkış ölçülüyor…', run(['direct', 'check']));
		return this.refreshAll();
	},

	async refreshAll() {
		const [st, nodes, apps, devs] = await this.load();
		await this.fetchDirect();
		this.nodes = nodes || [];
		this.apps = apps || [];
		this.renderStatus(st);
		this.renderNodes(nodes || [], st);
		this.renderApps(apps || []);
		this.devSig = JSON.stringify((devs || []).map(x => [x.mac, x.ip, x.name, x.mode, x.online])) + '|' + this.directDead + this.autoOff;
		this.renderDevices(devs || []);
	},

	async doToggle(st) {
		const on = st && st.enabled;
		if (!on && st && st.conflict && st.conflict.length)
			return this.doTakeover(st);
		await this.busy(on ? 'VPN durduruluyor…' : 'VPN başlatılıyor…', run([on ? 'stop' : 'start']));
		return this.refreshAll();
	},
	async doTakeover(st) {
		const names = (st && st.conflict || []).join(', ');
		if (!confirm(names + ' durdurulup KediRay başlatılacak.\nİnternet gelmezse otomatik olarak ' + names + ' geri açılır.\n\nDevam edilsin mi?'))
			return;
		const r = await this.busy('Geçiş yapılıyor (en fazla ~40 sn)…', run(['takeover']));
		this.note((r.stdout || '') + (r.stderr ? '\n' + r.stderr : ''), r.code === 0 ? 'info' : 'warning');
		return this.refreshAll();
	},
	async doRestart() {
		await this.busy('Yeniden başlatılıyor…', run(['restart']));
		return this.refreshAll();
	},
	async doPing(sec) {
		await this.busy(sec ? 'Ölçülüyor…' : 'Tüm sunucular ölçülüyor…', runJson(['ping', sec || 'all', '--json']));
		return this.refreshAll();
	},
	async doBest() {
		const r = await this.busy('En hızlı sunucu aranıyor…', run(['best']));
		this.note(r.code === 0 ? (r.stdout || 'En hızlı sunucuya geçildi') : ('Bulunamadı: ' + (r.stderr || '')), r.code === 0 ? 'info' : 'warning');
		return this.refreshAll();
	},
	async doUse(sec) {
		await this.busy('Sunucu değiştiriliyor (bağlantılar kopmadan)…', run(['use', sec]));
		return this.refreshAll();
	},
	async doApp(sec, route) {
		await this.busy('Uygulanıyor…', run(['app', sec, route]));
		return this.refreshAll();
	},
	async doDevice(d, mode) {
		await this.busy('Uygulanıyor…', run(['device', d.mac, mode, d.name || '']));
		return this.refreshAll();
	},
	async doSub() {
		const r = await this.busy('Abonelikler güncelleniyor…', run(['sub']));
		this.note((r.stdout || '') + (r.stderr ? ' ' + r.stderr : ''));
		return this.refreshAll();
	},
	async doCheck() {
		const r = await this.busy('Bağlantı test ediliyor…', runJson(['check']));
		if (!r || !r.running) return this.note('VPN çalışmıyor.', 'warning');
		const ok = v => v ? '✅' : '❌';
		ui.showModal('Bağlantı teşhisi', [
			h('ul', {}, [
				h('li', {}, ok(r.dns) + ' DNS (Xray üzerinden)'),
				h('li', {}, ok(r.vpn) + ' VPN tüneli' + (r.vpn_ip ? ' — çıkış IP: ' + r.vpn_ip : '')),
				h('li', {}, ok(r.direct) + ' Direkt internet')
			]),
			h('div', { 'class': 'right' }, h('button', { 'class': 'btn', 'click': ui.hideModal }, 'Kapat'))
		]);
	},
	errList(res) {
		const errs = (res && res.errors) || [];
		if (!errs.length) return h('div', { 'class': 'kr-errs' }, 'Bilinmeyen hata: ' + ((res && res.raw) || 'yanıt alınamadı'));
		return h('div', { 'class': 'kr-errs' }, [
			h('b', {}, STAGE[res.stage] || 'Hata'),
			h('ul', {}, errs.map(e => h('li', {}, [
				e.name && e.stage ? h('b', {}, e.name + ': ') : '',
				e.line ? 'Satır ' + e.line + (e.col ? ', sütun ' + e.col : '') + ' — ' : '',
				e.field && !e.line ? '[' + e.field + '] ' : '',
				e.msg || '',
				e.detail && e.detail !== e.msg ? h('div', { 'class': 'kr-sub', 'style': 'font-size:.8em;word-break:break-all' }, e.detail) : ''
			])))
		]);
	},

	async doValidate() {
		const r = await this.busy('Yapılandırma denetleniyor…', runJson(['validate', '--json']));
		ui.showModal('Yapılandırma denetimi', [
			r && r.ok ? h('p', { 'class': 'kr-ok' }, '✅ Yazım, alan ve Xray denetimi: hata yok.') : this.errList(r),
			h('div', { 'class': 'right' }, h('button', { 'class': 'btn', 'click': ui.hideModal }, 'Kapat'))
		]);
	},

	async doDelete(n) {
		if (!confirm('"' + n.name + '" silinsin mi?')) return;
		const r = await this.busy('Siliniyor…', runJson(['node', 'del', n.sec]));
		if (!r || !r.ok) this.note('Silinemedi', 'error');
		return this.refreshAll();
	},

	/* ---------- sunucu düzenleyici: Form + JSON ---------- */
	async openEditor(sec) {
		let d;
		if (sec) {
			d = await runJson(['node', 'get', sec]);
			if (!d || !d.ok) return this.note('Sunucu okunamadı', 'error');
		} else {
			d = { mode: 'form', fields: { protocol: 'vless', network: 'ws', tls: 'tls', port: '443' }, json: JSON_TEMPLATE };
		}
		const f = Object.assign({}, d.fields || {});
		const inputs = {}, rows = {};
		let tab = d.mode === 'json' ? 'json' : 'form';

		const name = h('input', { 'type': 'text', 'class': 'cbi-input-text', 'style': 'width:100%', 'value': f.remarks || '', 'placeholder': 'ör. Almanya WS' });
		const errBox = h('div', {});
		const hint = h('div', { 'class': 'kr-hint' });

		const readForm = () => {
			const o = {};
			FIELDS.forEach(([k, , t]) => {
				const el = inputs[k];
				o[k] = t === 'checkbox' ? (el.checked ? '1' : '') : el.value.trim();
			});
			return o;
		};
		const refreshVis = () => {
			const cur = readForm();
			FIELDS.forEach(([k, , , , vis]) => { rows[k].forEach(el => el.style.display = (!vis || vis(cur)) ? '' : 'none'); });
			const ipTLS = /^\d+\.\d+\.\d+\.\d+$/.test(cur.address) && cur.tls === 'tls' && !cur.sni && !cur.insecure;
			hint.textContent = ipTLS ? 'IP adresiyle TLS kullanıyorsan SNI alanına alan adını yaz ya da "Sertifikayı doğrulama"yı işaretle.' : '';
		};
		const formGrid = h('div', { 'class': 'kr-form' });
		FIELDS.forEach(([k, label, t, opts]) => {
			let el;
			if (t === 'select') {
				el = h('select', { 'class': 'cbi-input-select' }, (opts || []).map(o => {
					const [v, l] = Array.isArray(o) ? o : [o, o];
					return h('option', { 'value': v, 'selected': (f[k] || '') === v ? '' : null }, l);
				}));
			} else if (t === 'checkbox') {
				el = h('input', { 'type': 'checkbox', 'checked': f[k] === '1' ? '' : null });
			} else {
				el = h('input', { 'type': 'text', 'class': 'cbi-input-text', 'value': f[k] || '', 'spellcheck': 'false', 'autocomplete': 'off' });
			}
			el.addEventListener('change', refreshVis);
			el.addEventListener('input', () => { el.classList.remove('kr-bad-input'); if (k === 'address' || k === 'sni') refreshVis(); });
			inputs[k] = el;
			const lab = h('label', {}, label);
			rows[k] = [lab, el];
			formGrid.appendChild(lab);
			formGrid.appendChild(el);
		});

		const ta = h('textarea', { 'class': 'kr-json', 'spellcheck': 'false', 'wrap': 'off' });
		ta.value = d.json || JSON_TEMPLATE;
		const gut = h('pre', { 'class': 'kr-gut' });
		const syncGut = () => {
			const nl = ta.value.split('\n').length;
			if (gut._n !== nl) { gut._n = nl; gut.textContent = Array.from({ length: nl }, (_, k) => k + 1).join('\n'); }
			gut.scrollTop = ta.scrollTop;
		};
		const fitHeight = () => {
			const nl = ta.value.split('\n').length;
			ta.style.height = Math.min(Math.max(nl + 2, 16), 44) * 18.2 + 14 + 'px';
		};
		ta.addEventListener('scroll', syncGut);
		ta.addEventListener('input', syncGut);
		const editor = h('div', { 'class': 'kr-ed' }, [gut, ta]);
		const wrapBtn = h('button', { 'class': 'btn cbi-button', 'click': ev => {
			ev.preventDefault();
			ta.classList.toggle('kr-wrap');
			ta.setAttribute('wrap', ta.classList.contains('kr-wrap') ? 'soft' : 'off');
			gut.style.display = ta.classList.contains('kr-wrap') ? 'none' : '';
			wrapBtn.textContent = ta.classList.contains('kr-wrap') ? '↔ Satırları kaydırma' : '↵ Uzun satırları kaydır';
		} }, '↵ Uzun satırları kaydır');
		const fullBtn = h('button', { 'class': 'btn cbi-button', 'click': ev => {
			ev.preventDefault();
			ta.style.height = ta.style.height === '78vh' ? '' : '78vh';
			if (!ta.style.height) fitHeight();
			syncGut();
		} }, '⤢ Büyüt / küçült');
		const jstat = h('div', { 'class': 'kr-jstat' });
		let lastErr = null;
		const checkJson = () => {
			lastErr = jsonCheck(ta.value);
			jstat.className = 'kr-jstat ' + (lastErr ? 'kr-no' : 'kr-ok');
			jstat.textContent = lastErr ? '❌ Satır ' + lastErr.line + ', sütun ' + lastErr.col + ': ' + lastErr.msg : '✅ Geçerli JSON';
		};
		let tmr = null;
		ta.addEventListener('input', () => { clearTimeout(tmr); tmr = setTimeout(checkJson, 250); });
		ta.addEventListener('keydown', ev => {   // Tab tuşu girinti eklesin
			if (ev.key === 'Tab') {
				ev.preventDefault();
				const a = ta.selectionStart, b = ta.selectionEnd;
				ta.value = ta.value.slice(0, a) + '  ' + ta.value.slice(b);
				ta.selectionStart = ta.selectionEnd = a + 2;
			}
		});
		const gotoErr = e => {
			if (!e) return;
			ta.focus();
			const pos = e.pos != null ? e.pos : ta.value.split('\n').slice(0, e.line - 1).join('\n').length + (e.line > 1 ? 1 : 0) + (e.col - 1);
			ta.setSelectionRange(pos, Math.min(pos + 1, ta.value.length));
			const lh = parseFloat(getComputedStyle(ta).lineHeight) || 18;
			ta.scrollTop = Math.max(0, (e.line - 4) * lh);
		};
		const fmtBtn = h('button', { 'class': 'btn cbi-button', 'click': ev => {
			ev.preventDefault();
			checkJson();
			if (lastErr) return gotoErr(lastErr);
			ta.value = JSON.stringify(JSON.parse(ta.value), null, 2);
			checkJson(); fitHeight(); syncGut();
		} }, '⇆ Biçimlendir (girintiyi düzelt)');
		const goBtn = h('button', { 'class': 'btn cbi-button', 'click': ev => { ev.preventDefault(); checkJson(); gotoErr(lastErr); } }, 'Hataya git');

		const formPane = h('div', {}, [
			d.mode === 'json' ? h('p', { 'class': 'kr-hint' }, 'Bu sunucu JSON ile eklenmiş. Form ile kaydedersen JSON\'a özel ince ayarlar kaybolabilir; o ayarlar için JSON sekmesini kullan.') : '',
			formGrid, hint
		]);
		const jsonPane = h('div', {}, [
			h('p', { 'class': 'kr-hint' }, 'Xray outbound JSON\'u. v2rayNG\'nin tam yapılandırmasını da yapıştırabilirsin, içinden sunucu kısmı alınır. Girinti hata değildir, "Biçimlendir" ile düzeltilir; virgül/tırnak hataları anında satır ve sütunuyla gösterilir.'),
			editor, jstat, h('div', { 'class': 'kr-row', 'style': 'margin-top:4px' }, [fmtBtn, goBtn, wrapBtn, fullBtn])
		]);
		const tFormBtn = h('button', {}, 'Form');
		const tJsonBtn = h('button', {}, '{ } JSON');
		const setTab = t => {
			tab = t;
			formPane.style.display = t === 'form' ? '' : 'none';
			jsonPane.style.display = t === 'json' ? '' : 'none';
			tFormBtn.className = t === 'form' ? 'kr-act' : '';
			tJsonBtn.className = t === 'json' ? 'kr-act' : '';
			if (t === 'json') { checkJson(); fitHeight(); syncGut(); }
		};
		tFormBtn.addEventListener('click', ev => { ev.preventDefault(); setTab('form'); });
		tJsonBtn.addEventListener('click', ev => { ev.preventDefault(); setTab('json'); });

		const save = async () => {
			dom.content(errBox, '');
			let args;
			if (tab === 'json') {
				checkJson();
				if (lastErr) { dom.content(errBox, this.errList({ stage: 'syntax', errors: [lastErr] })); gotoErr(lastErr); return; }
				args = ['node', 'save', sec || 'new', 'json', ta.value, name.value.trim()];
			} else {
				const o = readForm();
				o.remarks = name.value.trim();
				const vis = {};
				FIELDS.forEach(([k, , , , v]) => { if (!v || v(o)) vis[k] = o[k]; });
				vis.remarks = o.remarks;
				args = ['node', 'save', sec || 'new', 'form', JSON.stringify(vis)];
			}
			const r = await run(args);
			let res = null;
			try { res = JSON.parse(r.stdout); } catch (e) { res = { ok: false, raw: (r.stdout || '') + (r.stderr || '') }; }
			if (res && res.ok) {
				ui.hideModal();
				this.note('Kaydedildi' + (sec ? '' : ' (yeni sunucu eklendi)') + '. Ayar denetimden ve Xray testinden geçti.');
				return this.refreshAll();
			}
			dom.content(errBox, this.errList(res));
			(res.errors || []).forEach(e => { if (e.field && inputs[e.field]) inputs[e.field].classList.add('kr-bad-input'); });
			if (tab === 'json' && res.stage === 'syntax' && res.errors && res.errors[0]) gotoErr(res.errors[0]);
		};

		ui.showModal(sec ? 'Sunucuyu düzenle' : 'Yeni sunucu', [
			h('div', { 'class': 'kr-form', 'style': 'margin-bottom:6px' }, [h('label', {}, 'Ad'), name]),
			d.sub ? h('p', { 'class': 'kr-hint' }, 'Not: Bu sunucu abonelikten geliyor; abonelik güncellenince değişikliğin üzerine yazılabilir.') : '',
			(d.errors && d.errors.length) ? this.errList({ stage: 'node', errors: d.errors }) : '',
			h('div', { 'class': 'kr-tabs' }, [tFormBtn, tJsonBtn]),
			formPane, jsonPane, errBox,
			h('div', { 'class': 'right', 'style': 'margin-top:10px' }, [
				h('button', { 'class': 'btn', 'click': ui.hideModal }, 'İptal'), ' ',
				h('button', { 'class': 'btn cbi-button-positive', 'click': ui.createHandlerFn(this, save) }, 'Denetle ve kaydet')
			])
		], 'kr-wide');
		refreshVis();
		setTab(tab);
	},

	showAdd() {
		const ta = h('textarea', { 'style': 'width:100%;height:190px;font-family:monospace', 'placeholder':
			'vless://...  vmess://...  trojan://...  ss://...\n(birden fazla satır olabilir)\n\nveya Xray JSON: tek outbound, outbound dizisi\nya da v2rayNG "tam yapılandırma" JSON\'u' });
		ui.showModal('Sunucu ekle — link veya JSON', [
			ta,
			h('p', { 'class': 'kr-sub' }, 'İpucu: v2rayNG\'de sunucuya uzun bas → "Tam yapılandırmayı panoya aktar" ile JSON\'u birebir alabilirsin.'),
			h('div', { 'class': 'right' }, [
				h('button', { 'class': 'btn', 'click': ui.hideModal }, 'İptal'), ' ',
				h('button', { 'class': 'btn cbi-button-positive', 'click': ui.createHandlerFn(this, async () => {
					const v = ta.value.trim();
					if (!v) return;
					const r = await this.busy('Ekleniyor…', run(['add', v]));
					this.note(r.code === 0 ? r.stdout : ('Eklenemedi: ' + (r.stderr || 'geçerli link/JSON yok')), r.code === 0 ? 'info' : 'error');
					return this.refreshAll();
				}) }, 'Ekle')
			])
		]);
	},
	async showConns(ip) {
		const list = await this.busy('Bağlantılar okunuyor…', runJson(['conns', ip, '--json']));
		const apps = (this.apps || []).filter(a => a.route === 'direct');
		const sel = h('select', { 'class': 'cbi-input-select' }, apps.map(a => h('option', { 'value': a.sec }, a.name)));
		const rows = (list || []).slice(0, 60).map(c => h('tr', { 'class': 'tr' }, [
			h('td', { 'class': 'td' }, c.proto),
			h('td', { 'class': 'td' }, c.dst), h('td', { 'class': 'td' }, String(c.port)),
			h('td', { 'class': 'td' }, String(c.n)),
			h('td', { 'class': 'td' }, h('span', { 'class': 'kr-ping ' + (c.vpn ? 'kr-mid' : 'kr-good') }, c.vpn ? 'VPN' : 'Direkt')),
			h('td', { 'class': 'td' }, c.web ? h('span', { 'class': 'kr-sub' }, 'web') : h('b', {}, 'oyun/uygulama?')),
			h('td', { 'class': 'td' }, c.vpn && apps.length
				? btn.call(this, 'Direkt yap', 'cbi-button-action', () => this.doDirect(sel.value, c), 'Bu sunucuyu (ve komşularını) seçili uygulamaya ekler')
				: '')
		]));
		ui.showModal('Aktif bağlantılar — ' + (ip || 'tüm cihazlar'), [
			h('p', { 'class': 'kr-sub' }, 'Oyun açıkken bak. Oyunun satırlarında "VPN" yazıyorsa oyun tünelden geçiyor: ışınlanırken sunucu IP değişti sanıp atabilir. "Direkt yap" o sunucuyu (aynı /24 komşuları) ve portunu seçili uygulamaya ekler.'),
			apps.length ? h('div', { 'class': 'kr-row', 'style': 'margin:0 0 8px' }, [h('label', {}, 'Eklenecek uygulama:'), sel]) : '',
			h('table', { 'class': 'table kr-table' }, [
				h('tr', { 'class': 'tr table-titles' }, ['Proto', 'Hedef', 'Port', 'Adet', 'Yol', '', ''].map(x => h('th', { 'class': 'th' }, x))),
				...rows
			]),
			h('div', { 'class': 'right' }, h('button', { 'class': 'btn', 'click': ui.hideModal }, 'Kapat'))
		], 'kr-wide');
	},

	async doDirect(sec, c) {
		if (!sec) return;
		const net = c.dst.split('.').slice(0, 3).join('.') + '.0/24';
		const r1 = await run(['app', sec, 'add-ip', net]);
		const r2 = c.web ? { code: 0 } : await run(['app', sec, 'add-port', String(c.port)]);
		ui.hideModal();
		if (r1.code === 0 && r2.code === 0)
			ui.addNotification(null, h('p', {}, net + (c.web ? '' : ' ve port ' + c.port) + ' direkt listeye eklendi. Oyunu yeniden başlatmadan denemek için önce oyundan çık.'), 'info');
		else
			ui.addNotification(null, h('p', {}, 'Eklenemedi: ' + ((r1.stderr || r2.stderr || '').trim() || 'bilinmeyen hata')), 'error');
	},

	/* ---------- çizim ---------- */
	renderStatus(st) {
		st = st || {};
		const dot = st.running ? 'kr-on' : (st.enabled ? 'kr-err' : 'kr-off');
		const txt = st.running ? 'Çalışıyor' : (st.enabled ? 'Durdu — Günlük sekmesine bak' : 'Kapalı');
		const modes = { rule: 'Tümü VPN', global: 'Tümü VPN', list: 'Sadece liste VPN' };
		const cf = st.conflict || [];
		this.card(this.elStatus, 'status', 'Durum', [
			h('div', { 'class': 'kr-big' }, [h('span', { 'class': 'kr-dot ' + dot }), txt]),
			h('div', { 'class': 'kr-sub' }, [
				'Xray ', st.core || '?', ' · Mod: ', modes[st.mode] || st.mode || '-',
				' · Yakalama: ', ({ mixed: 'Mixed (TCP çekirdek + UDP hev)', tun: 'TUN (hepsi hev-socks5-tunnel)', tproxy: 'TPROXY', redirect: 'Redirect (sadece TCP)' })[st.capture] || st.capture || '-',
				st.running ? [' · Açık: ', live(st.uptime)] : '',
				st.direct_dead ? ' · Direkt çıkış yok: "direkt" uygulamalar da VPN\'den çıkıyor' : ''
			]),
			cf.length ? h('div', { 'class': 'kr-warn' }, [
				h('b', {}, 'Şu an ' + cf.join(', ') + ' çalışıyor. '),
				'İkisi aynı anda trafiği yönetemez; KediRay kapalı bekliyor. "Güvenli geçiş" ' + cf.join(', ') +
				'\'i durdurur, artıklarını temizler ve KediRay\'i başlatır. İnternet gelmezse otomatik geri alır.'
			]) : '',
			st.dns_rescue ? h('div', { 'class': 'kr-warn' }, [
				h('b', {}, 'DNS acil yedeği devrede. '),
				'Tünelden giden DNS yanıt vermedi, adresler geçici olarak operatörün DNS\'iyle çözülüyor — internet çalışmaya devam ediyor ama bu sorgular tünelden geçmiyor. Tünel düzelince kendiliğinden geri döner. Sebebini görmek için "🤝 Sunucu el sıkışması"na bas.'
			]) : '',
			st.last_error ? h('div', { 'class': 'kr-errs' }, [
				h('b', {}, 'Yapılandırma hatası — VPN başlatılamadı'),
				h('pre', { 'style': 'white-space:pre-wrap;margin:6px 0 0;font-size:.85em' }, st.last_error)
			]) : '',
			h('div', { 'class': 'kr-row' }, [
				cf.length && !st.enabled
					? btn.call(this, '⇄ Güvenli geçiş', 'cbi-button-positive', () => this.doTakeover(st))
					: btn.call(this, st.enabled ? 'Durdur' : 'Başlat', st.enabled ? 'cbi-button-negative' : 'cbi-button-positive', () => this.doToggle(st)),
				btn.call(this, 'Yeniden başlat', 'cbi-button-action', () => this.doRestart()),
				btn.call(this, 'Teşhis', '', () => this.doCheck()),
				btn.call(this, '✓ Ayarları denetle', '', () => this.doValidate(), 'Yazım/alan hatası ve Xray testi'),
				btn.call(this, '⏱ Hız testi', '', () => this.doSpeed(), 'Direkt ve VPN hızını karşılaştır'),
				btn.call(this, '🐢 Sayfa gecikmesi', '', () => this.doWebtest(), 'Sayfa neden geç açılıyor: DNS mi, tünel mi?'),
				btn.call(this, '🔎 Takılma avı', '', () => this.doHunt(), 'Tarayıcıda takılan adresleri arka arkaya dener: takılma DNS\'te mi bağlantıda mı?'),
				btn.call(this, '🤝 Sunucu el sıkışması', '', () => this.doDial(), 'Sunucu bağlantıyı kaç kez düşürüyor (günlükteki EOF hatası)'),
				btn.call(this, '{ } Xray yapılandırması', '', () => this.showConfig(), 'Üretilen tam config.json')
			])
		]);
		const a = st.active;
		// Kullanıcı açılır listeyi kullanırken periyodik yenileme listeyi bozmasın
		if (this.elNode.contains(document.activeElement) && document.activeElement.tagName === 'SELECT') return;
		const nodes = (this.nodes || []).filter(n => n.enabled !== false);
		const curSec = st.auto ? (a ? a.sec : '') : (st.selected ? st.selected.sec : '');
		const sel = h('select', { 'class': 'cbi-input-select' }, nodes.map(n =>
			h('option', { 'value': n.sec, 'selected': n.sec === curSec ? '' : null },
				n.name + (n.ping != null && n.ping < 0 ? '  (yok)' : n.rtt ? '  (' + n.rtt + ' ms)' : n.ping != null ? '  (tünel ' + n.ping + ' ms)' : ''))));
		const sw = h('input', { 'type': 'checkbox', 'checked': st.auto ? '' : null });
		sw.addEventListener('change', ui.createHandlerFn(this, () => this.doAuto(sw.checked)));
		this.card(this.elNode, 'node', 'Bağlı sunucu', [
			h('div', { 'class': 'kr-big' }, a ? a.name : (st.running ? '…' : (st.selected ? st.selected.name : '—'))),
			h('div', { 'class': 'kr-sub' }, [
				a ? [a.protocol, a.network].filter(Boolean).join(' · ') + ' · ' : '',
				st.auto ? h('span', { 'class': 'kr-tag' }, 'OTOMATİK') : h('span', { 'class': 'kr-tag' }, 'ELLE SEÇİLDİ'),
				' ', a ? pingBadge(a.ping, a.rtt, a.warm) : ''
			]),
			// Bağlanılan adres: alan adı ya da IP (alan adıyla bağlanıldıysa çözülen IP de yazar)
			a && a.address ? h('div', { 'class': 'kr-addr' }, [
				h('span', { 'class': 'kr-sub' }, a.ip ? 'Sunucu (alan adı): ' : 'Sunucu IP\'si: '),
				h('code', { 'class': 'kr-mono' }, a.address + (a.port ? ':' + a.port : '')),
				a.ip ? [h('span', { 'class': 'kr-sub' }, ' → IP: '), h('code', { 'class': 'kr-mono' }, a.ip)] : ''
			]) : '',
			h('label', { 'class': 'kr-switch', 'style': 'margin-top:10px' }, [
				sw, h('span', { 'class': 'kr-knob' }),
				h('span', {}, [h('b', {}, 'Otomatik geçiş'), h('span', { 'class': 'kr-sub' },
					st.auto ? ' — seçili sunucuda kalır, sadece o düşerse diğerine geçer (oyunda IP değişmez)' : ' — kapalı: seçtiğin sunucuda kalır, hiç geçiş yapılmaz')])
			]),
			h('div', { 'class': 'kr-srv' }, nodes.length ? [
				sel,
				btn.call(this, 'Bu sunucuya bağlan', 'cbi-button-action', () => this.doUse(sel.value), 'Elle seç (otomatik geçiş kapanır)')
			] : h('span', { 'class': 'kr-sub' }, 'Sunucu yok')),
			h('div', { 'class': 'kr-row' }, [
				btn.call(this, '⚡ Ping ölç', '', () => this.doPing(null)),
				btn.call(this, '🚀 En hızlıyı bul ve bağlan', 'cbi-button-positive', () => this.doBest()),
				(this.nodes || []).some(n => n.insecure) ? btn.call(this, '🔒 Sertifikayı sabitle', '', () => this.doPin(null), 'Sunucunun şu anki sertifikasını sabitler; değiştiyse tüneli yeniden başlatır (internet gittiyse bas)') : ''
			])
		]);
	},

	async doPin(sec) {
		const r = await this.busy('Sertifika sabitleniyor…', run(sec ? ['pin', sec] : ['pin']));
		const out = ((r.stdout || '') + ' ' + (r.stderr || '')).trim().split('\n').join(' · ');
		this.note(out || 'Bitti', r.code === 0 ? 'info' : 'warning');
		return this.refreshAll();
	},

	async doAuto(on) {
		await this.busy(on ? 'Otomatik geçiş açılıyor…' : 'Şu anki sunucuda sabitleniyor…', run(['auto', on ? 'on' : 'off']));
		return this.refreshAll();
	},

	async doWebtest() {
		const raw = await this.busy('Sayfa açılma süresi ölçülüyor (≈10 sn)…', run(['webtest', '--json']));
		let r = null;
		try { r = JSON.parse(raw.stdout || 'null'); } catch (e) { r = null; }
		if (!r || !r.tests)
			return ui.showModal('Sayfa gecikmesi — ölçüm yapılamadı', [
				h('p', {}, 'Komut beklenen çıktıyı vermedi. Terminalde şunu çalıştırıp çıktıyı paylaşabilirsin:'),
				h('pre', { 'class': 'kr-view' }, 'kediray webtest'),
				h('p', { 'class': 'kr-sub' }, 'Çıkış kodu: ' + raw.code),
				(raw.stderr || raw.stdout) ? h('details', {}, [h('summary', {}, 'Çıktı'), h('pre', { 'class': 'kr-view' }, ((raw.stderr || '') + '\n' + (raw.stdout || '')).trim())]) : '',
				h('div', { 'class': 'right' }, h('button', { 'class': 'btn', 'click': ui.hideModal }, 'Kapat'))
			], 'kr-wide');
		const ms = v => (v == null ? '—' : v + ' ms');
		const rows = [];
		r.tests.forEach(t => {
			const line = (label, x, cls) => h('tr', { 'class': 'tr' + (cls || '') }, [
				h('td', { 'class': 'td' }, label),
				h('td', { 'class': 'td krt-n' }, ms(x.dns)), h('td', { 'class': 'td krt-n' }, ms(x.connect)),
				h('td', { 'class': 'td krt-n' }, ms(x.tls)), h('td', { 'class': 'td krt-n' }, ms(x.ttfb)),
				h('td', { 'class': 'td krt-n' }, h('b', {}, ms(x.total))),
				h('td', { 'class': 'td' }, x.code ? String(x.code) : h('span', { 'style': 'color:#e05252' }, 'yanıt yok'))
			]);
			rows.push(h('tr', { 'class': 'tr' }, h('td', { 'class': 'td', 'colspan': 7 }, h('b', {}, t.host))));
			rows.push(line('  direkt', t.direct));
			if (r.running) rows.push(line('  VPN', t.vpn, ' kr-active'));
		});
		ui.showModal('Sayfa açılma gecikmesi', [
			h('p', { 'class': 'kr-sub' }, 'Bir sayfanın açılması: DNS (adres çözme) → bağlantı → TLS → ilk bayt. Hangi aşamada beklendiği aşağıda. DNS süresi ikisinde de aynıdır: o modemin kendi DNS yolu.'),
			h('table', { 'class': 'table kr-table' }, [
				h('tr', { 'class': 'tr table-titles' }, ['', 'DNS', 'Bağlantı', 'TLS', 'İlk bayt', 'Toplam', 'HTTP'].map((x, i) =>
					h('th', { 'class': 'th' + (i ? ' krt-n' : '') }, x))),
				...rows
			]),
			r.verdict && r.verdict.length ? h('ul', {}, r.verdict.map(v => h('li', {}, v))) : '',
			h('div', { 'class': 'right' }, h('button', { 'class': 'btn', 'click': ui.hideModal }, 'Kapat'))
		], 'kr-wide');
	},

	// Arka planda çalışan uzun ölçümü aç, bitene kadar canlı oku (arayüz isteği zaman aşımına düşmesin)
	async bgWatch(title, args, hint, verdict) {
		const kick = await run([args[0], '--bg', ...args.slice(1)]);
		if (kick.code !== 0)
			return ui.showModal(title + ' — başlatılamadı', [
				h('p', {}, 'Komut çalışmadı. SSH ile deneyebilirsin:'),
				h('pre', { 'class': 'kr-view' }, 'kediray ' + args.join(' ')),
				h('pre', { 'class': 'kr-view' }, ((kick.stderr || '') + '\n' + (kick.stdout || '')).trim() || 'çıkış kodu: ' + kick.code),
				h('div', { 'class': 'right' }, h('button', { 'class': 'btn', 'click': ui.hideModal }, 'Kapat'))
			], 'kr-wide');
		const pre = h('pre', { 'class': 'kr-view', 'style': 'max-height:50vh' }, 'Ölçüm başladı, ilk sonuçlar birkaç saniye içinde…');
		const head = h('p', {}, h('b', {}, 'Ölçüm sürüyor…'));
		const closed = { v: false };
		ui.showModal(title, [
			head, pre,
			h('p', { 'class': 'kr-sub' }, hint),
			h('div', { 'class': 'right' }, h('button', { 'class': 'btn', 'click': () => { closed.v = true; ui.hideModal(); } }, 'Kapat'))
		], 'kr-wide');
		for (let i = 0; i < 120 && !closed.v; i++) {
			const r = await run([args[0], '--read']);
			const nl = (r.stdout || '').indexOf('\n');
			const state = nl < 0 ? (r.stdout || '').trim() : r.stdout.slice(0, nl).trim();
			const body = nl < 0 ? '' : r.stdout.slice(nl + 1);
			if (closed.v) return;
			if (body.trim()) pre.textContent = body.trimEnd();
			if (state === 'BITTI') { head.textContent = ''; head.appendChild(h('b', {}, verdict(body))); return; }
			if (state === 'BASLAMADI' && i > 3) { head.textContent = 'Ölçüm çıktısı bulunamadı. SSH: kediray ' + args.join(' '); return; }
			await new Promise(res => setTimeout(res, 2000));
		}
		if (!closed.v) head.textContent = 'Ölçüm hâlâ sürüyor. Düğmeye tekrar basarak kaldığı yerden okuyabilirsin.';
	},

	doDial() {
		return this.bgWatch('Sunucu el sıkışması', ['dialtest', '10'],
			'Her sunucu adresine 10 kez sıfırdan bağlanılır. Alan adı birden çok IP\'ye çözülüyorsa her IP ayrı ölçülür.',
			out => this.dialVerdict(out));
	},

	dialVerdict(out) {
		const lines = (out || '').split('\n');
		if (!lines.some(l => /başarılı/.test(l))) return 'Ölçüm sonucu okunamadı: aşağıdaki çıktıyı paylaş ya da SSH ile "kediray dialtest" çalıştır.';
		const bad = lines.filter(l => /DÜŞTÜ/.test(l) && /\d+\/\d+ başarılı/.test(l));
		const good = lines.filter(l => /\d+\/\d+ başarılı/.test(l) && !/DÜŞTÜ/.test(l));
		if (!bad.length) return 'Sunucu her denemede el sıkıştı: bağlantı kurulumu sağlam. Sayfa takılmaları başka yerde.';
		if (good.length) return 'Bazı IP\'ler bağlantıyı düşürüyor, bazıları sağlam. Ayarlar → Genel → "Sunucuya IP ile bağlan" seçeneğini kapat: her bağlantıda çalışan IP denenir.';
		return 'Sunucu bağlantıları düşürüyor (günlükteki EOF hatası bu). Sayfalarda takılan istekler bunlar: sunucu yükü/port kısıtı olabilir — başka port ya da ikinci sunucu dene.';
	},

	async doHunt() {
		// Ölçüm 1 dk'yı aşabiliyor; arayüzün isteği o kadar bekleyemediği için arka planda çalıştırıp okuyoruz
		const kick = await run(['hunt', '--bg', '5']);
		if (kick.code !== 0)
			return ui.showModal('Takılma avı başlatılamadı', [
				h('p', {}, 'Komut çalışmadı. SSH ile şunu deneyip çıktıyı paylaşabilirsin:'),
				h('pre', { 'class': 'kr-view' }, 'kediray hunt 10'),
				h('pre', { 'class': 'kr-view' }, ((kick.stderr || '') + '\n' + (kick.stdout || '')).trim() || 'çıkış kodu: ' + kick.code),
				h('div', { 'class': 'right' }, h('button', { 'class': 'btn', 'click': ui.hideModal }, 'Kapat'))
			], 'kr-wide');

		const pre = h('pre', { 'class': 'kr-view', 'style': 'max-height:50vh' }, 'Ölçüm başladı, ilk sonuçlar birkaç saniye içinde…');
		const head = h('p', {}, h('b', {}, 'Ölçüm sürüyor…'));
		const closed = { v: false };
		const close = () => { closed.v = true; ui.hideModal(); };
		ui.showModal('Takılma avı', [
			head, pre,
			h('p', { 'class': 'kr-sub' }, 'Her adres 5 kez denenir. Pencereyi kapatsan da ölçüm arkada biter; tekrar bakmak için düğmeye bas.'),
			h('div', { 'class': 'right' }, h('button', { 'class': 'btn', 'click': close }, 'Kapat'))
		], 'kr-wide');

		for (let i = 0; i < 90 && !closed.v; i++) {
			const r = await run(['hunt', '--read']);
			const nl = (r.stdout || '').indexOf('\n');
			const state = nl < 0 ? (r.stdout || '').trim() : r.stdout.slice(0, nl).trim();
			const body = nl < 0 ? '' : r.stdout.slice(nl + 1);
			if (closed.v) return;
			if (body.trim()) pre.textContent = body.trimEnd();
			if (state === 'BITTI') {
				head.textContent = '';
				head.appendChild(h('b', {}, this.huntVerdict(body)));
				return;
			}
			if (state === 'BASLAMADI' && i > 3) {
				head.textContent = 'Ölçüm çıktısı bulunamadı. SSH: kediray hunt 10';
				return;
			}
			await new Promise(res => setTimeout(res, 2000));
		}
		if (!closed.v) head.textContent = 'Ölçüm hâlâ sürüyor. Düğmeye tekrar basarak kaldığı yerden okuyabilirsin.';
	},

	// Çıktıdan tek cümlelik sonuç. Çıktı yoksa ASLA "takılma yok" demeyiz: bilmiyoruz demektir.
	huntVerdict(out) {
		const lines = (out || '').split('\n');
		const tried = lines.filter(l => /deneme/.test(l) || /başarılı/.test(l));
		if (!tried.length) return 'Ölçüm sonucu okunamadı: aşağıdaki çıktıyı paylaş ya da SSH ile "kediray hunt 10" çalıştır.';
		const fails = lines.filter(l => /BAŞARISIZ/.test(l));
		const slow = lines.filter(l => /YAVAŞ/.test(l));
		if (fails.length)
			return /DNS aşamasında/.test(fails.join(' '))
				? 'Takılmalar ad çözümlemede (DNS): ' + fails.length + ' deneme DNS aşamasında düştü. Ayarlar → DNS bölümünden mod değiştirip tekrar ölçelim.'
				: 'Takılmalar bağlantı aşamasında: tünelin sunucuya bağlanması takılıyor. Sunucu/port/SNI ya da başka bir sunucu denenmeli.';
		if (slow.length)
			return 'Hiçbir deneme düşmedi ama ' + slow.length + ' deneme 3 sn üstünde kaldı: aşağıda hangi aşamanın beklediği yazıyor.';
		return 'Modem tarafında takılma yok: bu adresler her denemede hızlı açıldı. Takılma tarayıcı tarafındadır (Chrome → Gizlilik → "Güvenli DNS" kapalı olmalı; ayrıca IPv6/QUIC).';
	},

	async doSpeed() {
		const r = await this.busy('Hız testi yapılıyor (≈30 sn)…', runJson(['speedtest', '--json']));
		if (!r) return this.note('Hız testi yapılamadı', 'error');
		const tip = [];
		if (r.running && r.direct_mbps > 0) {
			const ratio = r.vpn_mbps / r.direct_mbps;
			if (ratio < 0.3) tip.push('VPN hızı direktin çok altında: sunucunun hattı/uzaklığı ya da sunucu tarafı sınırı olabilir. "En hızlıyı bul" ile başka sunucu dene.');
			else if (ratio < 0.7) tip.push('VPN hızı direktin bir miktar altında; WS+TLS tünelde bu normal sayılır.');
			else tip.push('VPN hızı direkte yakın, tünel sorunsuz.');
		}
		if (r.dns_ms > 300) tip.push('DNS yavaş (' + r.dns_ms + ' ms): Ayarlar → DNS → "Hızlı" modunu kullan.');
		ui.showModal('Hız testi (modem üzerinden)', [
			h('table', { 'class': 'table kr-table' }, [
				h('tr', { 'class': 'tr table-titles' }, ['', 'İndirme', 'Gecikme'].map(x => h('th', { 'class': 'th' }, x))),
				h('tr', { 'class': 'tr' }, [h('td', { 'class': 'td' }, 'Direkt'), h('td', { 'class': 'td' }, r.direct_mbps + ' Mbps'), h('td', { 'class': 'td' }, r.direct_ms + ' ms')]),
				h('tr', { 'class': 'tr' }, [h('td', { 'class': 'td' }, 'VPN'), h('td', { 'class': 'td' }, r.running ? r.vpn_mbps + ' Mbps' : 'kapalı'), h('td', { 'class': 'td' }, r.running ? r.vpn_ms + ' ms' : '—')]),
				h('tr', { 'class': 'tr' }, [h('td', { 'class': 'td' }, 'DNS çözümleme'), h('td', { 'class': 'td' }, ''), h('td', { 'class': 'td' }, r.dns_ms + ' ms')])
			]),
			tip.length ? h('ul', {}, tip.map(t => h('li', {}, t))) : '',
			h('p', { 'class': 'kr-sub' }, 'Ölçüm modemin kendi bağlantısıyla yapılır (Cloudflare, 20 MB). Wi-Fi hızın bundan düşükse darboğaz Wi-Fi\'dır.'),
			h('div', { 'class': 'right' }, h('button', { 'class': 'btn', 'click': ui.hideModal }, 'Kapat'))
		]);
	},

	async showConfig() {
		const r = await run(['show-config']);
		ui.showModal('Üretilen Xray yapılandırması (salt okunur)', [
			r.code === 0 ? h('pre', { 'class': 'kr-view' }, r.stdout) : h('p', {}, (r.stderr || 'Yapılandırma yok').trim()),
			h('div', { 'class': 'right' }, h('button', { 'class': 'btn', 'click': ui.hideModal }, 'Kapat'))
		], 'kr-wide');
	},

	/* Trafik: canlı hız + dönem tablosu (VPN ve Direkt ayrı) + 30 günlük yığılmış çubuk grafik.
	   Kaynak: `kediray stats` = { t, counters:{vr,vt,wr,wt}, today, yesterday, week, month, total, since, days:[{day,vr,vt,dr,dt}] }
	   vr/vt = VPN indirme/yükleme (tünelin dış baytları), dr/dt = Direkt = WAN toplamı − VPN. */
	/* Düzen: hangi bölüm görünsün, hangi sırada, hangi dönem satırları. Tarayıcıda saklanır. */
	secTitles: { live: 'Şu an + toplamlar', periods: 'Dönemler (Bugün / Dün / Hafta / Ay)', devs: 'Cihaz bazında trafik', chart: 'Son 30 gün grafiği' },
	rowTitles: { today: 'Bugün', yesterday: 'Dün', week: 'Bu hafta', month: 'Bu ay', total: 'Toplam' },
	loadLayout() {
		const def = { order: ['live', 'periods', 'devs', 'chart'], hide: {}, hideRows: {} };
		try {
			const c = JSON.parse(localStorage.getItem('kediray-trafik-layout') || 'null');
			if (c && Array.isArray(c.order)) {
				const o = c.order.filter(k => def.order.indexOf(k) >= 0);
				def.order.forEach(k => { if (o.indexOf(k) < 0) o.push(k); });
				return { order: o, hide: c.hide || {}, hideRows: c.hideRows || {} };
			}
		} catch (e) {}
		return def;
	},
	saveLayout() {
		try { localStorage.setItem('kediray-trafik-layout', JSON.stringify(this.layoutCfg)); } catch (e) {}
	},
	relayout() {
		this.saveLayout(); this.layout();
		if (this.lastStats) this.renderTraffic(this.lastStats);
	},
	layout() {
		const c = this.layoutCfg, ed = this.editing, out = [];
		dom.content(this.elTools, [
			h('button', { 'class': 'btn cbi-button' + (ed ? ' cbi-button-positive' : ''), 'click': ui.createHandlerFn(this, () => { this.editing = !this.editing; this.layout(); }) }, ed ? '✓ Bitti' : '⚙ Düzenle'),
			ed ? h('button', { 'class': 'btn cbi-button', 'click': ui.createHandlerFn(this, () => { this.layoutCfg = { order: ['live', 'periods', 'devs', 'chart'], hide: {}, hideRows: {} }; this.relayout(); }) }, 'Varsayılana dön') : ''
		]);
		c.order.forEach((k, i) => {
			if (c.hide[k] && !ed) return;
			const box = [];
			if (ed) {
				const mv = d => { const j = i + d; if (j < 0 || j >= c.order.length) return; const t = c.order[i]; c.order[i] = c.order[j]; c.order[j] = t; this.relayout(); };
				const cb = h('input', { 'type': 'checkbox' });
				cb.checked = !c.hide[k];
				cb.addEventListener('change', () => { c.hide[k] = !cb.checked; this.relayout(); });
				box.push(h('div', { 'class': 'kr-row', 'style': 'margin:0 0 6px;padding:6px 8px;border:1px dashed rgba(128,128,128,.5);border-radius:8px;align-items:center' }, [
					h('b', { 'style': 'flex:1' }, this.secTitles[k]),
					h('button', { 'class': 'btn cbi-button', 'click': ui.createHandlerFn(this, () => mv(-1)) }, '▲'),
					h('button', { 'class': 'btn cbi-button', 'click': ui.createHandlerFn(this, () => mv(1)) }, '▼'),
					h('label', { 'style': 'margin-left:8px;white-space:nowrap' }, [cb, ' Göster'])
				]));
				if (k === 'periods') {
					box.push(h('div', { 'class': 'kr-row', 'style': 'margin:0 0 6px;gap:12px;flex-wrap:wrap' }, Object.keys(this.rowTitles).map(rk => {
						const rc = h('input', { 'type': 'checkbox' });
						rc.checked = !c.hideRows[rk];
						rc.addEventListener('change', () => { c.hideRows[rk] = !rc.checked; this.relayout(); });
						return h('label', { 'style': 'white-space:nowrap' }, [rc, ' ' + this.rowTitles[rk]]);
					})));
				}
			}
			box.push(h('div', { 'style': (ed && c.hide[k]) ? 'opacity:.35' : '' }, this.secs[k]));
			out.push(h('div', {}, box));
		});
		dom.content(this.elSecs, out);
	},

	trafficLive(s) {
		let r = { vd: 0, vu: 0, dd: 0, du: 0 };
		const p = this.lastStats, c = s.counters;
		if (p && s.t > p.t) {
			const dt = s.t - p.t, pc = p.counters;
			// sayaç sıfırlandıysa (tablo yeniden kuruldu) fark = şimdiki değer
			const d = (a, b) => (a >= b ? a - b : a) / dt;
			const vd = d(c.vr, pc.vr), vu = d(c.vt, pc.vt);
			r = { vd, vu, dd: Math.max(0, d(c.wr, pc.wr) - vd), du: Math.max(0, d(c.wt, pc.wt) - vu) };
		} else if (this.liveRate) r = this.liveRate;
		this.liveRate = r;
		this.lastStats = s;
		return r;
	},

	trafficChart(days) {
		const W = Math.max(280, Math.min(1100, this.elChart.clientWidth || 700)), H = 170;
		const L = 46, R = 8, T = 10, B = 24, pw = W - L - R, ph = H - T - B;
		const n = days.length, slot = pw / n, bw = Math.min(24, Math.max(4, slot - 4));
		const tot = days.map(x => x.vr + x.vt + x.dr + x.dt);
		const max = Math.max(1, ...tot);
		// "güzel" üst sınır: 1/2/5 × 10^k
		const pow = Math.pow(10, Math.floor(Math.log10(max))), top = [1, 2, 5, 10].map(m => m * pow).find(v => v >= max);
		const y = v => T + ph - (v / top) * ph;
		let g = '';
		for (let i = 0; i <= 4; i++) {
			const v = top * i / 4, yy = y(v).toFixed(1);
			g += '<line x1="' + L + '" x2="' + (W - R) + '" y1="' + yy + '" y2="' + yy + '" class="krc-grid"/>' +
				'<text x="' + (L - 6) + '" y="' + (+yy + 4) + '" text-anchor="end" class="krc-ax">' + (v ? fmtBytes(v) : '0') + '</text>';
		}
		let bars = '';
		days.forEach((x, i) => {
			const cx = L + slot * i + slot / 2, x0 = (cx - bw / 2).toFixed(1);
			const vpn = x.vr + x.vt, dir = x.dr + x.dt;
			const hv = vpn > 0 ? Math.max(1, (vpn / top) * ph) : 0, hd = dir > 0 ? Math.max(1, (dir / top) * ph) : 0;
			const base = T + ph;
			// alt: VPN, üst: Direkt; en üstteki parçanın ucu 4px yuvarlak, taban düz; ikisi arasında 2px yüzey boşluğu
			const gap = hv > 0 && hd > 2 ? 2 : 0;
			if (hv > 0) bars += hd > 0 ? '<rect x="' + x0 + '" y="' + (base - hv).toFixed(1) + '" width="' + bw.toFixed(1) + '" height="' + hv.toFixed(1) + '" class="krc-vpn"/>'
				: '<path d="' + roundTop(+x0, base - hv, bw, hv, 4) + '" class="krc-vpn"/>';
			if (hd > 0) bars += '<path d="' + roundTop(+x0, base - hv - hd, bw, hd - gap, 4) + '" class="krc-dir"/>';
			// gezinme hedefi: sütunun tamamı
			bars += '<rect x="' + (L + slot * i).toFixed(1) + '" y="' + T + '" width="' + slot.toFixed(1) + '" height="' + ph + '" class="krc-hit" data-i="' + i + '"/>';
			if (i % Math.ceil(n / (W < 500 ? 5 : 10)) === 0 || i === n - 1)
				bars += '<text x="' + cx.toFixed(1) + '" y="' + (H - 6) + '" text-anchor="middle" class="krc-ax">' + x.day.slice(8) + '.' + x.day.slice(5, 7) + '</text>';
		});
		return '<svg viewBox="0 0 ' + W + ' ' + H + '" width="' + W + '" height="' + H + '" class="krc-svg" role="img" aria-label="Son 30 gün trafik (VPN ve Direkt)">' + g + bars + '</svg>';
	},

	renderTraffic(s) {
		if (!s || !s.counters || !s.today) { this.card(this.elTraffic, 'traffic', 'Trafik', h('div', { 'class': 'kr-sub' }, 'Henüz veri yok')); this.trafficBuilt = false; return; }
		const r = this.trafficLive(s);
		if (!this.trafficBuilt) {
			this.elLive = h('div', {});
			this.elPeriods = h('div', {});
			this.elDevTr = h('div', {});
			this.elChart = h('div', { 'class': 'krc-wrap' });
			this.elTip = h('div', { 'class': 'krc-tip', 'style': 'display:none' });
			this.elChart.appendChild(this.elTip);
			this.elSvg = h('div', {});
			this.elChart.insertBefore(this.elSvg, this.elTip);
			this.elChart.addEventListener('mousemove', ev => this.trafficHover(ev));
			this.elChart.addEventListener('mouseleave', () => { this.elTip.style.display = 'none'; });
			this.elChart.addEventListener('click', ev => this.trafficHover(ev));
			this.secs = {
				live: this.elLive,
				periods: this.fold('t-periods', 'Bugün / Dün / Bu hafta / Bu ay / Toplam', this.elPeriods),
				devs: this.fold('t-devs', 'Cihaz bazında trafik', this.elDevTr),
				chart: this.fold('t-chart', 'Son 30 gün (günlük)', h('div', {}, [
					h('div', { 'class': 'krc-legend' }, [
						h('span', {}, [h('i', { 'class': 'krc-sw krc-vpn' }), 'VPN']),
						h('span', {}, [h('i', { 'class': 'krc-sw krc-dir' }), 'Direkt'])
					]),
					this.elChart
				]))
			};
			this.elSecs = h('div', {});
			this.elTools = h('div', { 'class': 'kr-row', 'style': 'margin:0 0 10px' });
			this.layoutCfg = this.loadLayout();
			this.editing = false;
			this.layout();
			this.card(this.elTraffic, 'traffic', 'Trafik', [
				this.elTools,
				this.elSecs,
				h('div', { 'class': 'kr-sub', 'style': 'margin-top:8px' }, 'VPN = sunucuya giden/gelen gerçek tünel baytları. Direkt = modemin İnternet (WAN) toplamı − VPN; yani VPN\'siz çıkan her şey (seçtiğin direkt uygulamalar, oyun, Teams, yerel indirmeler) burada. Sayaçlar modem yeniden başlasa da saklanır.')
			]);
			this.trafficBuilt = true;
		}

		const pill = (cls, label, d, u) => h('div', { 'class': 'krt-live ' + cls }, [
			h('div', { 'class': 'krt-lh' }, [h('i', { 'class': 'krc-sw ' + (cls === 'v' ? 'krc-vpn' : 'krc-dir') }), label]),
			h('div', { 'class': 'krt-lv' }, [h('span', {}, '↓ ' + fmtRate(d)), h('span', {}, '↑ ' + fmtRate(u))])
		]);
		dom.content(this.elLive, [
			h('div', { 'class': 'krt-now' }, 'Şu an'),
			h('div', { 'class': 'krt-lives' }, [pill('v', 'VPN', r.vd, r.vu), pill('d', 'Direkt', r.dd, r.du)]),
			h('div', { 'class': 'krt-totals' }, [
				h('div', { 'class': 'krt-tot' }, [h('div', { 'class': 'kr-sub' }, 'VPN toplam'), h('div', { 'class': 'krt-big' }, fmtBytes(s.total.vr + s.total.vt)),
					h('div', { 'class': 'kr-sub' }, '↓ ' + fmtBytes(s.total.vr) + ' · ↑ ' + fmtBytes(s.total.vt))]),
				h('div', { 'class': 'krt-tot' }, [h('div', { 'class': 'kr-sub' }, 'Direkt toplam'), h('div', { 'class': 'krt-big' }, fmtBytes(s.total.dr + s.total.dt)),
					h('div', { 'class': 'kr-sub' }, '↓ ' + fmtBytes(s.total.dr) + ' · ↑ ' + fmtBytes(s.total.dt))])
			])
		]);

		const allRows = [['today', 'Bugün', s.today], ['yesterday', 'Dün', s.yesterday], ['week', 'Bu hafta', s.week], ['month', 'Bu ay', s.month], ['total', 'Toplam' + (s.since ? ' (' + s.since.split('-').reverse().join('.') + '\'den beri)' : ''), s.total]];
		const rows = allRows.filter(x => !this.layoutCfg.hideRows[x[0]]).map(x => [x[1], x[2]]);
		const cell = b => [h('td', { 'class': 'td krt-n' }, fmtBytes(b.vr + b.vt)), h('td', { 'class': 'td krt-n kr-hide-sm kr-sub' }, '↓' + fmtBytes(b.vr) + ' ↑' + fmtBytes(b.vt))];
		dom.content(this.elPeriods, h('table', { 'class': 'table kr-table krt-table' }, [
			h('tr', { 'class': 'tr table-titles' }, [
				h('th', { 'class': 'th' }, 'Dönem'),
				h('th', { 'class': 'th krt-n', 'colspan': 2 }, [h('i', { 'class': 'krc-sw krc-vpn' }), 'VPN']),
				h('th', { 'class': 'th krt-n', 'colspan': 2 }, [h('i', { 'class': 'krc-sw krc-dir' }), 'Direkt']),
				h('th', { 'class': 'th krt-n' }, 'Hepsi')
			]),
			...rows.map(([l, b]) => h('tr', { 'class': 'tr' }, [
				h('td', { 'class': 'td' }, h('b', {}, l)), ...cell({ vr: b.vr, vt: b.vt }), ...cell({ vr: b.dr, vt: b.dt }),
				h('td', { 'class': 'td krt-n' }, fmtBytes(b.vr + b.vt + b.dr + b.dt))
			]))
		]));

		this.renderDevTraffic(s.devices || [], s.t);

		// grafik yalnızca veri ya da genişlik değişince yeniden çizilir (gezinme/ipucu titremesin)
		const sig = JSON.stringify(s.days) + '|' + (this.elChart.clientWidth || 0);
		if (sig !== this.chartSig) {
			this.chartSig = sig;
			this.days = s.days;
			this.elSvg.innerHTML = this.trafficChart(s.days);   // yalnızca sayılardan üretilen SVG
		}
	},

	/* Cihaz bazında trafik: indirme = cihaza gelen, yükleme = cihazdan giden (nft sayaçları, LAN IP'si başına).
	   Canlı hız, iki yoklama arasındaki sayaç farkından hesaplanır. */
	renderDevTraffic(devs, t) {
		const prev = this.devPrev || {}, next = {};
		if (!devs.length) {
			dom.content(this.elDevTr, h('div', { 'class': 'kr-sub' }, 'Henüz cihaz verisi yok; sayaçlar başladıktan 1-2 dakika sonra dolar.'));
			this.devPrev = next;
			return;
		}
		let sdd = 0, sdu = 0, srx = 0, stx = 0, mrx = 0, mtx = 0, trx = 0, ttx = 0;
		const rows = devs.map(dv => {
			let dd = 0, du = 0;
			const c = dv.counter, p = prev[dv.ip];
			if (c) {
				if (p && t > p.t) {
					const dt = t - p.t, f = (a, b) => (a >= b ? a - b : a) / dt;
					dd = f(c.rx, p.rx); du = f(c.tx, p.tx);
				}
				next[dv.ip] = { t: t, rx: c.rx, tx: c.tx };
			}
			sdd += dd; sdu += du;
			srx += dv.today.rx; stx += dv.today.tx; mrx += dv.month.rx; mtx += dv.month.tx; trx += dv.total.rx; ttx += dv.total.tx;
			return h('tr', { 'class': 'tr' }, [
				h('td', { 'class': 'td' }, [h('b', {}, dv.name || dv.ip), dv.name ? h('div', { 'class': 'kr-sub' }, dv.ip) : '']),
				h('td', { 'class': 'td krt-n' }, '↓ ' + fmtRate(dd) + '  ↑ ' + fmtRate(du)),
				h('td', { 'class': 'td krt-n', 'title': 'Toplam (kurulumdan beri): ' + fmtBytes(dv.total.rx + dv.total.tx) + ' · Bu ay: ' + fmtBytes(dv.month.rx + dv.month.tx) }, '↓ ' + fmtBytes(dv.today.rx) + '  ↑ ' + fmtBytes(dv.today.tx))
			]);
		});
		this.devPrev = next;
		dom.content(this.elDevTr, [
			h('table', { 'class': 'table kr-table krt-table' }, [
				h('tr', { 'class': 'tr table-titles' }, [
					h('th', { 'class': 'th' }, 'Cihaz'),
					h('th', { 'class': 'th krt-n' }, 'Şu an'),
					h('th', { 'class': 'th krt-n' }, 'Bugün')
				]),
				...rows,
				h('tr', { 'class': 'tr kr-active' }, [
					h('td', { 'class': 'td' }, [h('b', {}, 'Tüm cihazlar (' + devs.length + ')'),
						h('div', { 'class': 'kr-sub' }, 'Bu ay ↓ ' + fmtBytes(mrx) + ' ↑ ' + fmtBytes(mtx) + ' · Toplam ↓ ' + fmtBytes(trx) + ' ↑ ' + fmtBytes(ttx))]),
					h('td', { 'class': 'td krt-n' }, h('b', {}, '↓ ' + fmtRate(sdd) + '  ↑ ' + fmtRate(sdu))),
					h('td', { 'class': 'td krt-n' }, h('b', {}, '↓ ' + fmtBytes(srx) + '  ↑ ' + fmtBytes(stx)))
				])
			]),
			h('div', { 'class': 'kr-sub', 'style': 'margin-top:6px' }, '↓ cihaza gelen (indirme), ↑ cihazdan giden (yükleme). VPN ve direkt trafik birlikte sayılır. Sayaçlar modem yeniden başlasa da saklanır; donanım hızlandırma (NSS) açıksa direkt giden büyük akışlar eksik görünebilir.')
		]);
	},

	trafficHover(ev) {
		const t = ev.target && ev.target.closest ? ev.target.closest('[data-i]') : null;
		if (!t || !this.days) { this.elTip.style.display = 'none'; return; }
		const x = this.days[+t.getAttribute('data-i')];
		if (!x) return;
		const dm = x.day.split('-').reverse().join('.');
		dom.content(this.elTip, [
			h('b', {}, dm),
			h('div', {}, [h('i', { 'class': 'krc-sw krc-vpn' }), 'VPN: ' + fmtBytes(x.vr + x.vt)]),
			h('div', {}, [h('i', { 'class': 'krc-sw krc-dir' }), 'Direkt: ' + fmtBytes(x.dr + x.dt)]),
			h('div', { 'class': 'kr-sub' }, 'Toplam: ' + fmtBytes(x.vr + x.vt + x.dr + x.dt))
		]);
		const box = this.elChart.getBoundingClientRect();
		let px = ev.clientX - box.left + 12;
		this.elTip.style.display = 'block';
		if (px + this.elTip.offsetWidth > box.width) px = ev.clientX - box.left - this.elTip.offsetWidth - 12;
		this.elTip.style.left = Math.max(0, px) + 'px';
		this.elTip.style.top = '4px';
	},

	renderApps(apps) {
		const rows = apps.filter(a => a.enabled).map(a => h('div', { 'class': 'kr-app' }, [
			h('div', {}, [h('b', {}, a.name), h('div', { 'class': 'kr-sub' }, [a.ports ? 'port ' + a.ports : '', a.ips ? ' · ' + a.ips + ' IP bloğu' : '', a.domains ? ' · ' + a.domains + ' alan adı' : ''])]),
			h('div', { 'class': 'kr-seg' }, [
				h('button', { 'title': 'VPN: Bu uygulamanın trafiği VPN tünelinden çıkar. Operatör ne yaptığını görmez, siteler seni VPN sunucusunun IP\'siyle görür. Tünel koparsa bağlantı da kopar.', 'class': a.route === 'vpn' ? 'kr-act' : '', 'click': ui.createHandlerFn(this, () => a.route !== 'vpn' && this.doApp(a.sec, 'vpn')) }, 'VPN'),
				h('button', { 'title': 'Direkt: Tünele girmez, doğrudan hattan çıkar. En düşük ping; VPN yeniden başlasa bile bağlantı kopmaz. Siteler seni operatörün IP\'siyle görür (oyun ve görüntülü görüşme için uygun).', 'class': a.route === 'direct' ? 'kr-act kr-direct' : '', 'click': ui.createHandlerFn(this, () => a.route !== 'direct' && this.doApp(a.sec, 'direct')) }, 'Direkt')
			])
		]));
		this.card(this.elApps, 'apps', 'Uygulamalar — VPN mi, Direkt mi?', [
			...rows,
			h('div', { 'class': 'kr-sub', 'style': 'margin-top:8px' }, 'Direkt: çekirdekte bypass, VPN yeniden başlasa bile bağlantı kopmaz. Yeni uygulama/oyun: Ayarlar → Uygulamalar.')
		]);
	},

	renderNodes(nodes, st) {
		const act = st && st.active ? st.active.sec : null;
		const rows = nodes.map(n => h('tr', { 'class': 'tr' + (n.sec === act ? ' kr-active' : '') }, [
			h('td', { 'class': 'td' }, [h('b', {}, n.name), n.sec === act && st && st.enabled && !st.disconnected ? h('span', { 'class': 'kr-tag' }, 'BAĞLI') : '', n.json ? h('span', { 'class': 'kr-tag' }, 'JSON') : '', n.sub ? h('span', { 'class': 'kr-tag' }, 'abonelik') : '']),
			h('td', { 'class': 'td' }, [n.protocol, n.network, n.tls].filter(x => x && x !== 'none').join(' · ')),
			h('td', { 'class': 'td kr-hide-sm' }, (n.address || '') + ':' + (n.port || '')),
			h('td', { 'class': 'td' }, pingBadge(n.ping, n.rtt, n.warm)),
			h('td', { 'class': 'td', 'style': 'white-space:nowrap' }, [
				btn.call(this, 'Ping', '', () => this.doPing(n.sec)), ' ',
				btn.call(this, 'Düzenle', '', () => this.openEditor(n.sec)), ' ',
				n.sec === act && st && st.enabled && !st.disconnected ? [btn.call(this, 'Bağlantıyı kes', 'cbi-button-negative', () => this.doUse('none'), 'Sunucudan kopar; VPN açık kalır, trafik doğrudan çıkar'), ' '] : '',
				n.sec === act && st && st.enabled && !st.auto && !st.disconnected ? '' : [btn.call(this, 'Bağlan', 'cbi-button-action', () => this.doUse(n.sec)), ' '],
				btn.call(this, '✕', 'cbi-button-negative', () => this.doDelete(n), 'Sil')
			])
		]));
		this.card(this.elNodes, 'nodes', 'Sunucular (' + nodes.length + ')', [
			h('div', { 'class': 'kr-row', 'style': 'margin:0 0 10px' }, [
				btn.call(this, '⚡ Tümünü ölç', 'cbi-button-action', () => this.doPing(null)),
				btn.call(this, '+ Link / JSON ekle', 'cbi-button-positive', () => this.showAdd()),
				btn.call(this, '+ Elle ekle', '', () => this.openEditor(null)),
				btn.call(this, '↻ Aboneliği güncelle', '', () => this.doSub()),
				nodes.some(n => n.insecure) ? btn.call(this, '🔒 Sertifikayı sabitle', '', () => this.doPin(null), 'Sunucunun şu anki sertifikasını sabitler; değiştiyse tüneli yeniden başlatır') : ''
			]),
			nodes.length ? h('table', { 'class': 'table kr-table' }, [
				h('tr', { 'class': 'tr table-titles' }, [
					h('th', { 'class': 'th' }, 'Ad'), h('th', { 'class': 'th' }, 'Tür'), h('th', { 'class': 'th kr-hide-sm' }, 'Adres'),
					h('th', { 'class': 'th', 'title': 'Ping = sunucuya ağ gecikmesi · tünel = açık bağlantıdaki istek (parantez içi: sıfırdan bağlanma)' }, 'Ping'), h('th', { 'class': 'th' }, '')
				]),
				...rows
			]) : h('p', {}, 'Henüz sunucu yok. "Link / JSON ekle" ile ekle ya da Ayarlar\'dan abonelik gir.')
		]);
	},

	renderDevices(devs) {
		const on = devs.filter(d => d.online).length;
		// Yön: dört buton — Varsayılan / VPN / Direkt / Engelle (engelli kırmızı)
		const MODES = [
			['default', 'Varsayılan', '', 'Varsayılan: Bu cihaza özel kural yok, genel ayara uyar.'],
			['vpn', 'VPN', '', 'VPN: Bu cihazın tüm trafiği VPN tünelinden çıkar; siteler VPN sunucusunun IP\'sini görür.'],
			['direct', 'Direkt', 'kr-direct', 'Direkt: Bu cihaz tüneli hiç kullanmaz, doğrudan hattan çıkar (en düşük ping; IP\'si operatörün IP\'si olur).'],
			['block', 'Engelle', 'kr-block', 'Engelle: Bu cihaz internete hiç çıkamaz (ne VPN ne direkt).']
		];
		const mkRow = (d, off) => {
			const cur = d.mode || 'default';
			const seg = h('div', { 'class': 'kr-seg kr-seg-sm' }, MODES.map(([v, label, cls, tip]) =>
				h('button', {
					'class': (cur === v ? 'kr-act ' + cls : (cls === 'kr-block' ? 'kr-blockbtn' : '')),
					'title': tip,
					'click': ui.createHandlerFn(this, () => cur !== v && this.doDevice(d, v))
				}, label)));
			return h('tr', { 'class': 'tr' + (cur === 'block' ? ' kr-blocked' : '') }, [
				h('td', { 'class': 'td' }, [
					h('span', { 'class': 'kr-dot ' + (cur === 'block' ? 'kr-err' : d.online ? 'kr-on' : 'kr-off') }),
					d.name || '(adsız)',
					cur === 'block' ? h('span', { 'class': 'kr-tag kr-tag-red' }, 'ENGELLİ') : ''
				]),
				h('td', { 'class': 'td' }, d.ip || '-'),
				h('td', { 'class': 'td kr-hide-sm' }, d.mac),
				h('td', { 'class': 'td kr-hide-sm krt-n' }, d.online && d.uptime != null ? live(d.uptime) : (d.off_for != null ? 'çevrimdışı ' + Math.max(1, Math.round(d.off_for / 60)) + ' dk' : '—')),
				h('td', { 'class': 'td' }, seg),
				h('td', { 'class': 'td' }, off ? (d.sec ? btn.call(this, 'Kaydı sil', '', () => this.doDevice(d, 'default'), 'Bu çevrimdışı cihazın kayıtlı yönünü sil') : '') : (d.ip ? btn.call(this, 'Bağlantılar', '', () => this.showConns(d.ip), 'Bu cihazın şu an açık olan bağlantılarını listeler: hangi adrese ve porta, VPN\'den mi direkt mi gittiği. Bir uygulamanın hangi adresi/portu kullandığını görüp yön kuralına eklemek için.') : ''))
			]);
		};
		// Çevrimdışı cihazlar (yalnızca kayıtlı yönü olanlar) varsayılan olarak gizli; istenirse açılır
		const offl = devs.filter(d => !d.online);
		const rows = devs.filter(d => d.online).map(d => mkRow(d, false));
		const offRows = this.showOff ? offl.map(d => mkRow(d, true)) : [];
		const offBar = offl.length ? h('div', { 'style': 'margin-top:8px' }, [
			btn.call(this, (this.showOff ? '▾ ' : '▸ ') + 'Çevrimdışı cihazlar (' + offl.length + ')', '',
				() => { this.showOff = !this.showOff; this.renderDevices(devs); },
				'Şu an bağlı olmayan cihazlar (rastgele MAC kullanan telefonlar kayıtlı yönüyle burada birikebilir)')
		]) : '';
		const warn = (this.directDead && !this.autoOff) ? h('div', { 'class': 'kr-warn' }, [
			'Direkt çıkış şu an YOK görünüyor (hat VPN olmadan internete çıkamıyor ya da denetim henüz tamamlanmadı). Bu yüzden "Direkt" seçili cihazlar ve uygulamalar da VPN üzerinden çıkıyor. ',
			btn.call(this, 'Yeniden denetle', '', () => this.doDirectCheck(), 'Direkt çıkışı şimdi ölç')
		]) : '';
		const chk = h('input', { 'type': 'checkbox', 'checked': this.autoOff ? '' : null, 'change': ui.createHandlerFn(this, ev => this.doAutoDirect(ev.target.checked)) });
		const autoRow = h('label', { 'style': 'display:flex;gap:8px;align-items:center;margin:0 0 10px;cursor:pointer' }, [chk, 'Direkt seçilenler her durumda direkt çıksın (hat VPN\'siz çıkamıyorsa o cihaz internetsiz kalabilir)']);
		this.card(this.elDevs, 'devs', 'Cihazlar (' + on + ' bağlı)', h('div', {}, [warn, autoRow, h('table', { 'class': 'table kr-table' }, [
			h('tr', { 'class': 'tr table-titles' }, ['Cihaz', 'IP', 'MAC', 'Bağlı süre', 'Yön', ''].map((x, i) =>
				h('th', { 'class': 'th' + (i === 2 || i === 3 ? ' kr-hide-sm' : '') }, x))),
			...rows, ...offRows
		]), offBar]));
	},

	render() {
		this.nodes = [];
		this.elTraffic = h('div', { 'class': 'kr-card kr-traffic', 'style': 'margin-bottom:14px' });
		this.trafficBuilt = false; this.chartSig = ''; this.lastStats = null;
		this.renderTraffic(null);
		// poll ile: sayfadan çıkınca LuCI durdurur, sekme arkadayken boşa çalışmaz
		poll.add(() => runJson(['stats']).then(s => this.renderTraffic(s)), 2);
		return h('div', {}, [
			h('style', {}, CSS),
			h('h2', {}, [h('img', { 'src': '/luci-static/kedi-logo.svg', 'style': 'height:1.3em;vertical-align:-0.25em;margin-right:8px;border-radius:6px' }), 'KediRay VPN — Trafik']),
			this.elTraffic
		]);
	},

	handleSaveApply: null,
	handleSave: null,
	handleReset: null
});
KEDIRAY_EOF_24
cat > '/www/luci-static/resources/view/kediray/settings.js' <<'KEDIRAY_EOF_14'
'use strict';
'require view';
'require ui';
'require form';
'require uci';
'require rpc';
'require fs';
'require dom';

/* KediRay - Ayarlar */

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
		o.description = 'Mixed: TCP en kısa yoldan (çekirdek NAT), UDP TUN\'dan. TUN: her şey tek bir TUN aygıtından geçer — bazı hatlarda sayfalar daha hızlı açılır, denemeye değer; karşılığında UDP oturumları biraz gecikir. TPROXY: ikisi de çekirdekte. Redirect: yalnız TCP. Gerekli paketler yoksa KediRay otomatik TPROXY\'ye düşer (apk add hev-socks5-tunnel kmod-tun). Değiştirdikten sonra bir sayfa açıp Kontrol Paneli → "🐢 Sayfa gecikmesi" ile karşılaştır.';

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
		o.description = '"Tünelden": dnsmasq sorguları çekirdeğin DNS portuna (varsayılan 15353), çekirdek de "Uzak DNS" sunucusuna tünel içinden verir — hiçbir sorgu operatöre sızmaz. Sorgu tünelin veri yoluna (TUN/TPROXY) hiç girmediği için hızlıdır; TUN yakalama modunda tek çalışan seçenek budur. "Direkt": sorgular tünele girmez, tünel kopsa da ad çözümlenir; karşılığında hangi siteye girdiğin operatörün DNS\'ine ya da DoH sunucusuna görünür. "DNS\'e dokunma": KediRay ad çözümlemeye hiç karışmaz; alan adı kuralları (WhatsApp VPN\'den, oyun direkt) yine bağlantıdaki alan adından (SNI) okunduğu için çalışır, ama TUN yakalamasında hiçbir ad çözülemez (o birleşimde KediRay kendiliğinden "Tünelden"e döner) — yalnız DNS kaynaklı bir sorunu denemek için kullan.';

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
			'Chrome ve Firefox "Güvenli DNS" ile sistem DNS\'ini atlayıp doğrudan dns.google / cloudflare-dns.com gibi adreslere sorar. Bu hatta o adreslere ulaşılamadığı için sayfa başına 1-3 istek ~50 saniye askıda kalıyor ve tarayıcıda çark dönmeye devam ediyor. Açıkken bu istekler anında reddedilir (RST/ICMP), tarayıcı hemen KediRay\'in DNS\'ine döner. Alan adı kuralların ve gizliliğin etkilenmez.');
		o.default = '1';
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
			'Önerilen: KAPALI. Kapalıyken Google (FCM) / Apple (APNs) bildirim bağlantıları tünelden gider (xDivine-Ray gibi); tünel heartbeat ile canlı kaldığı için bağlantı kesilmez. Açıkken bu bağlantılar operatörden direkt gider ve operatör boştaki bağlantıyı sessizce kesebilir: bildirimler gecikir ya da gelmez.');
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
		o = s.taboption('stable', form.Flag, 'mux', 'TCP Mux',
			'Kapalıyken her istek sunucuya yeni bir bağlantı açar: bir sayfa 70-100 bağlantı demektir. Hattın ara sıra bağlantı düşürüyorsa (Günlük\'te "failed to dial / EOF / connection reset") her sayfada birkaç istek askıda kalır ve tarayıcı dönmeye devam eder. Açıldığında tek bağlantı çok isteği taşır, açılan bağlantı sayısı ~10 kat azalır. Hız biraz düşebilir; takılma yaşıyorsan aç, "kediray doctor" ile önce/sonra ölç. UDP (oyun, arama) için XUDP bu ayardan bağımsız olarak hep açıktır.');
		o.default = '0';
		o.rmempty = false;
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

		return m.render();
	}
});
KEDIRAY_EOF_14
cat > '/www/luci-static/resources/view/kediray/log.js' <<'KEDIRAY_EOF_15'
'use strict';
'require view';
'require ui';
'require fs';
'require poll';
'require dom';

/* KediRay - Günlük (hatalar ayrı ve kalıcı, akış seviye/bileşene göre süzülür) */

// Tarayıcıda saklanan eski menüyü (Hizmetler altındaki kayıt) bir kez temizle
try {
	if (!sessionStorage.getItem('kediray-menu-v2')) {
		sessionStorage.setItem('kediray-menu-v2', '1');
		if (ui.menu && ui.menu.flushCache) ui.menu.flushCache();
	}
} catch (e) {}

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
const LEVELS = { error: 'Hata', warn: 'Uyarı', info: 'Bilgi', debug: 'Ayıklama' };
const RANK = { error: 0, warn: 1, info: 2, debug: 3 };
const FILTERS = [['error', 'sadece hatalar'], ['warn', 'uyarı ve üstü'], ['info', 'bilgi ve üstü'], ['debug', 'hepsi (ayıklama dahil)']];

const CSS = `
.kl-desc{opacity:.8;margin:4px 0 14px}
.kl-sec{margin:18px 0 8px;font-size:1.25em}
.kl-row{display:flex;gap:10px;flex-wrap:wrap;align-items:center;margin:8px 0}
.kl-row label{opacity:.85}
.kl-err{border:1px solid rgba(210,63,63,.45);border-left:4px solid #d23f3f;border-radius:8px;padding:9px 12px;margin:8px 0;background:rgba(210,63,63,.06)}
.kl-err-h{display:flex;gap:8px;flex-wrap:wrap;align-items:baseline}
.kl-err-t{color:#e05252;font-weight:700}
.kl-fix{margin:6px 0 2px}
.kl-fix b{opacity:.85}
.kl-err details{margin-top:4px}
.kl-err pre,.kl-raw{white-space:pre-wrap;word-break:break-all;font-size:12px;margin:4px 0 0;opacity:.85}
.kl-badge{display:inline-block;padding:0 7px;border-radius:9px;font-size:.78em;font-weight:600;background:rgba(128,128,128,.18)}
.kl-cnt{font-size:.8em;opacity:.8}
.kl-time{font-variant-numeric:tabular-nums;opacity:.7;font-size:.85em}
.kl-stream{max-height:62vh;overflow:auto;border-radius:8px;background:rgba(128,128,128,.07);padding:6px 4px;font-family:ui-monospace,Menlo,Consolas,monospace;font-size:12.5px}
.kl-line{display:grid;grid-template-columns:84px 70px 130px 1fr;gap:8px;padding:3px 8px;border-bottom:1px solid rgba(128,128,128,.12);align-items:start}
.kl-line:last-child{border-bottom:0}
.kl-line.kl-lv-error{color:#e05252}
.kl-line.kl-lv-warn{color:#d9962b}
.kl-line.kl-lv-debug{opacity:.6}
.kl-lvb{display:inline-block;min-width:58px;text-align:center;border-radius:6px;font-size:.85em;font-weight:700;padding:0 4px}
.kl-lvb.error{background:rgba(210,63,63,.2);color:#e05252}
.kl-lvb.warn{background:rgba(230,160,20,.2);color:#d9962b}
.kl-lvb.info{background:rgba(42,125,225,.15);color:#5b9be8}
.kl-lvb.debug{background:rgba(128,128,128,.18)}
.kl-comp{opacity:.8;overflow:hidden;text-overflow:ellipsis;white-space:nowrap}
.kl-msg{word-break:break-word}
.kl-empty{font-style:italic;opacity:.75;padding:8px}
.kl-sum{display:flex;gap:6px;flex-wrap:wrap}
@media(max-width:700px){.kl-line{grid-template-columns:70px 1fr}.kl-line .kl-comp,.kl-line .kl-lvw{display:none}}
`;

function fmtTime(t, ts) {
	if (t == null) return ts || '';
	const d = new Date(t), n = new Date();
	const hm = d.toLocaleTimeString('tr-TR', { hour: '2-digit', minute: '2-digit', second: '2-digit' });
	return d.toDateString() === n.toDateString() ? hm : d.toLocaleDateString('tr-TR', { day: '2-digit', month: '2-digit' }) + ' ' + hm;
}

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

return view.extend({
	level: 'info',
	comp: '',
	data: null,

	load() {
		try { this.hideEof = localStorage.getItem('kediray-log-hideeof') === '1'; this.level = localStorage.getItem('kediray-log-level') || 'info'; this.comp = localStorage.getItem('kediray-log-comp') || ''; } catch (e) {}
		return fs.exec(CLI, ['logs']).then(r => { try { return JSON.parse(r.stdout); } catch (e) { return null; } }).catch(() => null);
	},

	async act(args) {
		await fs.exec(CLI, args).catch(() => null);
		this.update(await this.load());
	},

	skipEof(e) {
		return !!this.hideEof && /EOF/.test(String(e.title || '') + ' ' + String(e.text || '') + ' ' + String(e.raw || ''));
	},

	renderErrors(errs) {
		errs = (errs || []).filter(e => !this.skipEof(e));
		if (!errs.length)
			return h('p', { 'class': 'kl-empty' }, 'Kayıtlı hata yok.');
		return errs.map(e => h('div', { 'class': 'kl-err' }, [
			h('div', { 'class': 'kl-err-h' }, [
				h('span', { 'class': 'kl-err-t' }, e.title || e.text),
				h('span', { 'class': 'kl-badge' }, e.comp),
				e.count > 1 ? h('span', { 'class': 'kl-cnt' }, '×' + e.count) : '',
				h('span', { 'class': 'kl-time' }, e.count > 1 && e.first ? fmtTime(e.first) + ' – ' + fmtTime(e.last, e.ts) : fmtTime(e.last, e.ts))
			]),
			e.fix ? h('div', { 'class': 'kl-fix' }, [h('b', {}, 'Ne yapmalı: '), e.fix]) : '',
			h('details', {}, [h('summary', {}, 'Çıktı'), h('pre', {}, e.raw || e.text)])
		]));
	},

	renderStream(ents) {
		const lim = RANK[this.level] ?? 2;
		const rows = (ents || []).filter(e => (RANK[e.level] ?? 2) <= lim && (!this.comp || e.comp === this.comp) && !this.skipEof(e));
		if (!rows.length) return h('div', { 'class': 'kl-empty' }, 'Bu filtrelere uyan kayıt yok.');
		return rows.map(e => h('div', { 'class': 'kl-line kl-lv-' + e.level, 'title': e.fix ? 'Ne yapmalı: ' + e.fix : null }, [
			h('span', { 'class': 'kl-time' }, fmtTime(e.t, e.ts)),
			h('span', { 'class': 'kl-lvw' }, h('span', { 'class': 'kl-lvb ' + e.level }, LEVELS[e.level] || e.level)),
			h('span', { 'class': 'kl-comp' }, e.comp),
			h('span', { 'class': 'kl-msg' }, [e.title ? h('b', {}, e.title + ': ') : '', e.text])
		]));
	},

	update(d) {
		if (!d) return;
		this.data = d;
		// bileşen listesini güncel tut
		const comps = Array.from(new Set((d.entries || []).map(e => e.comp))).sort();
		const cur = this.comp;
		dom.content(this.selComp, [h('option', { 'value': '' }, 'tüm bileşenler'),
			...comps.map(c => h('option', { 'value': c, 'selected': c === cur ? '' : null }, c))]);
		if (cur && !comps.includes(cur)) this.selComp.appendChild(h('option', { 'value': cur, 'selected': '' }, cur));

		const cnt = { error: 0, warn: 0, info: 0 };
		(d.entries || []).forEach(e => { if (cnt[e.level] != null) cnt[e.level]++; });
		dom.content(this.elSum, [
			h('span', { 'class': 'kl-lvb error' }, cnt.error + ' hata'),
			h('span', { 'class': 'kl-lvb warn' }, cnt.warn + ' uyarı'),
			h('span', { 'class': 'kl-lvb info' }, cnt.info + ' bilgi')
		]);

		dom.content(this.elErrs, this.renderErrors(d.errors));
		const box = this.elStream;
		const atBottom = box.scrollHeight - box.scrollTop - box.clientHeight < 40;
		dom.content(box, this.renderStream(d.entries));
		if (atBottom || !this.scrolled) { box.scrollTop = box.scrollHeight; this.scrolled = true; }
	},

	render(d) {
		this.selLevel = h('select', { 'class': 'cbi-input-select', 'change': ev => {
			this.level = ev.target.value;
			try { localStorage.setItem('kediray-log-level', this.level); } catch (e) {}
			dom.content(this.elStream, this.renderStream(this.data && this.data.entries));
		} }, FILTERS.map(([v, l]) => h('option', { 'value': v, 'selected': v === this.level ? '' : null }, l)));
		this.selComp = h('select', { 'class': 'cbi-input-select', 'change': ev => {
			this.comp = ev.target.value;
			try { localStorage.setItem('kediray-log-comp', this.comp); } catch (e) {}
			dom.content(this.elStream, this.renderStream(this.data && this.data.entries));
		} });
		this.elErrs = h('div', {});
		this.elStream = h('div', { 'class': 'kl-stream' });
		this.elSum = h('div', { 'class': 'kl-sum' });

		const view = h('div', {}, [
			h('style', {}, CSS),
			h('h2', {}, [h('img', { 'src': '/luci-static/kedi-logo.svg', 'style': 'height:1.3em;vertical-align:-0.25em;margin-right:8px;border-radius:6px' }), 'Günlük']),
			h('label', { 'class': 'kl-row' }, [h('input', { 'type': 'checkbox', 'checked': this.hideEof ? '' : null, 'change': ev => { this.hideEof = ev.target.checked; try { localStorage.setItem('kediray-log-hideeof', this.hideEof ? '1' : '0'); } catch (e) {} this.update(this.data); } }), ' EOF hatalarını gizle']),
			h('p', { 'class': 'kl-desc' }, 'Yalnızca bellekte tutulur, flash belleğe hiçbir şey yazılmaz. Kaynak: sistem günlüğü (logread) — KediRay, Xray çekirdeği ve UDP tüneli (hev). Xray\'in bağlantı ayrıntıları için Ayarlar → Gelişmiş → Günlük seviyesi: info.'),

			h('h3', { 'class': 'kl-sec' }, 'Hatalar'),
			h('p', { 'class': 'kl-desc' }, 'Aşağıdaki akıştan daha uzun süre saklanır; aynı hata tekrarlanırsa tek kartta sayılır. Her kartta çıktı ve ne yapılması gerektiği vardır.'),
			h('div', { 'class': 'kl-row' }, h('button', { 'class': 'btn cbi-button cbi-button-negative', 'click': ui.createHandlerFn(this, () => this.act(['logs', 'clear-errors'])) }, 'Temizle')),
			this.elErrs,

			h('h3', { 'class': 'kl-sec' }, 'Akış'),
			h('div', { 'class': 'kl-row' }, [
				h('label', {}, 'Düzey'), this.selLevel,
				h('label', {}, 'Bileşen'), this.selComp,
				h('button', { 'class': 'btn cbi-button', 'click': () => { this.elStream.scrollTop = this.elStream.scrollHeight; } }, 'En alta git'),
				h('button', { 'class': 'btn cbi-button cbi-button-negative', 'click': ui.createHandlerFn(this, () => this.act(['logs', 'clear-stream'])) }, 'Akışı temizle'),
				this.elSum
			]),
			this.elStream
		]);

		this.update(d || { entries: [], errors: [] });
		poll.add(() => this.load().then(x => this.update(x)), 5);
		return view;
	},

	handleSaveApply: null,
	handleSave: null,
	handleReset: null
});
KEDIRAY_EOF_15
cat > '/www/luci-static/resources/view/kediray/about.js' <<'KEDIRAY_EOF_16'
'use strict';
'require view';
'require fs';
'require ui';

/* KediRay - Hakkında */

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

const ICONS = {
	coffee: [ '0 0 24 24', 'M2 21h18v-2H2v2zM20 8h-2V5h2v3zm0-5H4v10c0 2.21 1.79 4 4 4h6c2.21 0 4-1.79 4-4v-3h2c1.11 0 2-.89 2-2V5c0-1.11-.89-2-2-2z', '#ffdd00' ],
	update: [ '0 0 24 24', 'M17.65 6.35A7.958 7.958 0 0012 4c-4.42 0-7.99 3.58-7.99 8s3.57 8 7.99 8c3.73 0 6.84-2.55 7.73-6h-2.08A5.99 5.99 0 0112 18c-3.31 0-6-2.69-6-6s2.69-6 6-6c1.66 0 3.14.69 4.22 1.78L13 11h7V4l-2.35 2.35z', '' ],
	github: [ '0 0 16 16', 'M8 0C3.58 0 0 3.58 0 8c0 3.54 2.29 6.53 5.47 7.59.4.07.55-.17.55-.38 0-.19-.01-.82-.01-1.49-2.01.37-2.53-.49-2.69-.94-.09-.23-.48-.94-.82-1.13-.28-.15-.68-.52-.01-.53.63-.01 1.08.58 1.23.82.72 1.21 1.87.87 2.33.66.07-.52.28-.87.51-1.07-1.78-.2-3.64-.89-3.64-3.95 0-.87.31-1.59.82-2.15-.08-.2-.36-1.02.08-2.12 0 0 .67-.21 2.2.82.64-.18 1.32-.27 2-.27.68 0 1.36.09 2 .27 1.53-1.04 2.2-.82 2.2-.82.44 1.1.16 1.92.08 2.12.51.56.82 1.27.82 2.15 0 3.07-1.87 3.75-3.65 3.95.29.25.54.73.54 1.48 0 1.07-.01 1.93-.01 2.2 0 .21.15.46.55.38A8.013 8.013 0 0016 8c0-4.42-3.58-8-8-8z', '' ],
	backup: [ '0 0 24 24', 'M17 3H5a2 2 0 00-2 2v14a2 2 0 002 2h14a2 2 0 002-2V7l-4-4zm-5 16a3 3 0 110-6 3 3 0 010 6zm3-10H5V5h10v4z', '' ]
};

function title(name, text) {
	const i = ICONS[name], ico = document.createElement('span');
	ico.setAttribute('style', 'display:inline-flex;vertical-align:-3px;margin-right:8px' + (i[2] ? ';color:' + i[2] : ''));
	ico.innerHTML = '<svg xmlns="http://www.w3.org/2000/svg" width="22" height="22" viewBox="' + i[0] + '" fill="currentColor"><path d="' + i[1] + '"/></svg>';
	return h('h3', { 'style': 'margin:0 0 6px' }, [ ico, text ]);
}

const CLI = '/usr/bin/kediray';

const CSS = `
.ka-card{border:1px solid rgba(128,128,128,.25);border-radius:12px;padding:20px 22px;background:rgba(128,128,128,.04);max-width:620px}
.ka-name{font-size:1.9em;font-weight:700;letter-spacing:-.02em;margin:0}
.ka-tag{opacity:.75;margin:2px 0 18px}
.ka-rows{display:grid;grid-template-columns:auto 1fr;gap:10px 18px;align-items:baseline}
.ka-k{opacity:.75}
.ka-v{font-weight:600;font-variant-numeric:tabular-nums;word-break:break-all}
.ka-sep{grid-column:1/-1;height:1px;background:rgba(128,128,128,.22);margin:6px 0}
.ka-dev{grid-column:1/-1;margin-top:4px}
.ka-dev b{font-size:1.05em}
.ka-note{opacity:.7;font-size:.9em;margin-top:16px;max-width:620px;line-height:1.5}
`;

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

return view.extend({
	load() {
		return fs.exec(CLI, ['version', '--json'])
			.then(r => { try { return JSON.parse(r.stdout); } catch (e) { return null; } })
			.catch(() => null);
	},

	showCachedUpdate() {
		return fs.exec(CLI, ['update', 'cached']).then(r => {
			let j = null; try { j = JSON.parse((r.stdout || '').trim()); } catch (e) { }
			const msg = document.getElementById('ka-upd-msg'), go = document.getElementById('ka-upd-go');
			if (j && j.ok && j.newer && msg && !msg.textContent) { msg.textContent = 'Yeni sürüm var: ' + j.current + ' → ' + j.latest; if (go) go.style.display = ''; }
		}).catch(() => null);
	},

	render(d) {
		d = d || {};
		setTimeout(() => this.showCachedUpdate(), 400);
		const row = (k, v) => [h('div', { 'class': 'ka-k' }, k), h('div', { 'class': 'ka-v' }, v || '—')];
		return h('div', {}, [
			h('style', {}, CSS),
			h('h2', {}, [h('img', { 'src': '/luci-static/kedi-logo.svg', 'style': 'height:1.3em;vertical-align:-0.25em;margin-right:8px;border-radius:6px' }), 'Hakkında']),
			h('div', { 'class': 'ka-card' }, [
				h('h3', { 'class': 'ka-name' }, [h('img', { 'src': '/luci-static/kedi-logo.svg', 'style': 'height:1.1em;vertical-align:-0.15em;margin-right:8px;border-radius:6px' }), 'KediRay VPN']),
				h('div', { 'class': 'ka-tag' }, 'OpenWrt için Xray tabanlı akıllı VPN'),
				h('div', { 'class': 'ka-rows' }, [
					row('Sürüm', d.version),
					row('Proxy çekirdeği', d.core ? 'Xray ' + d.core : 'Xray —'),
					h('div', { 'class': 'ka-sep' }),
					h('div', { 'class': 'ka-dev' }, [h('span', { 'class': 'ka-k' }, 'Geliştirici: '), h('b', {}, 'Şaban Vurgun'), ' · 2026'])
				])
			]),
			h('div', { 'class': 'ka-card', 'style': 'margin-top:14px' }, [
				title('coffee', 'Beni destekle'),
				h('div', { 'style': 'margin-bottom:10px' }, h('a', { 'href': 'https://buymeacoffee.com/sabanvurgun', 'target': '_blank', 'rel': 'noopener noreferrer' }, 'https://buymeacoffee.com/sabanvurgun')),
				h('a', { 'class': 'btn cbi-button cbi-button-action', 'href': 'https://buymeacoffee.com/sabanvurgun', 'target': '_blank', 'rel': 'noopener noreferrer' }, 'Bana bir kahve ısmarla'),
				h('div', { 'class': 'ka-k', 'style': 'margin-top:10px' }, 'Bağışlarınız için teşekkürler, bu iş için harcanan emek için ufak bir hediye.')
			]),
			h('div', { 'class': 'ka-card', 'style': 'margin-top:14px' }, [
				title('update', 'Elle güncelle'),
				h('div', { 'class': 'ka-k', 'style': 'margin-bottom:10px' }, 'Yeni kediray-…-install.sh dosyasını seç; yüklenir ve otomatik kurulur.'),
				h('button', { 'class': 'btn cbi-button cbi-button-action', 'click': ui.createHandlerFn(this, 'doUpdate') }, 'Dosya seç ve güncelle')
			]),
			h('div', { 'class': 'ka-card', 'style': 'margin-top:14px' }, [
				title('github', 'GitHub\'dan güncelle'),
				h('div', { 'class': 'ka-k', 'style': 'margin-bottom:10px' }, 'En son sürüm GitHub\'dan indirilir, SHA256 ile doğrulanır ve kurulur.'),
				h('div', { 'id': 'ka-upd-msg', 'style': 'margin-bottom:10px;font-weight:600' }, ''),
				h('button', { 'class': 'btn cbi-button', 'click': ui.createHandlerFn(this, 'doCheck') }, 'Güncellemeyi denetle'),
				' ',
				h('button', { 'id': 'ka-upd-go', 'class': 'btn cbi-button cbi-button-action', 'style': 'display:none', 'click': ui.createHandlerFn(this, 'doOnline') }, 'Şimdi güncelle')
			]),
			h('div', { 'class': 'ka-card', 'style': 'margin-top:14px' }, [
				title('backup', 'Yedekle / geri yükle'),
				h('div', { 'class': 'ka-k', 'style': 'margin-bottom:10px' }, 'Sunucuların, uygulama kuralların ve ayarların tek dosyada. Modemi sıfırlarsan bu dosyayla geri getirirsin. Dosya sunucu kimliklerini (UUID) içerir: kimseyle paylaşma, GitHub\'a yükleme.'),
				h('div', { 'id': 'ka-bk-msg', 'style': 'margin-bottom:10px;font-weight:600' }, ''),
				h('button', { 'class': 'btn cbi-button cbi-button-action', 'click': ui.createHandlerFn(this, 'doBackup') }, 'Yedek al'),
				' ',
				h('button', { 'class': 'btn cbi-button', 'click': ui.createHandlerFn(this, 'doRestore') }, 'Yedekten geri yükle')
			]),
			h('div', { 'class': 'ka-note' }, 'Çekirdeği güncellemek için SSH: kediray update-core · Coğrafi veriler: kediray update-geo')
		]);
	},

	doCheck() {
		const msg = document.getElementById('ka-upd-msg'), go = document.getElementById('ka-upd-go');
		if (msg) msg.textContent = 'Denetleniyor…';
		if (go) go.style.display = 'none';
		return fs.exec(CLI, ['update', 'check', '--json']).then(r => {
			let j = null; try { j = JSON.parse((r.stdout || '').trim()); } catch (e) { }
			if (!msg) return;
			if (!j || !j.ok) msg.textContent = 'Denetlenemedi: ' + ((j && j.error) || 'GitHub\'a ulaşılamadı') + '.';
			else if (j.newer) { msg.textContent = 'Yeni sürüm var: ' + j.current + ' → ' + j.latest; if (go) go.style.display = ''; }
			else msg.textContent = 'Güncelsin (' + j.current + ').';
		}).catch(() => { if (msg) msg.textContent = 'Denetlenemedi: panel yanıt vermedi.'; });
	},

	doBackup() {
		const msg = document.getElementById('ka-bk-msg');
		return fs.exec(CLI, ['backup']).then(r => {
			const txt = r.stdout || '';
			if (r.code !== 0 || !/^package kediray/.test(txt)) { if (msg) msg.textContent = 'Yedek alınamadı: ' + ((r.stderr || '').trim() || 'ayar boş'); return; }
			const d = new Date(), p = n => String(n).padStart(2, '0');
			const name = 'kediray-yedek-' + d.getFullYear() + p(d.getMonth() + 1) + p(d.getDate()) + '-' + p(d.getHours()) + p(d.getMinutes()) + '.conf';
			const a = document.createElement('a');
			a.href = URL.createObjectURL(new Blob([txt], { type: 'text/plain' }));
			a.download = name;
			document.body.appendChild(a); a.click(); a.remove();
			setTimeout(() => URL.revokeObjectURL(a.href), 4000);
			const n = (txt.match(/^config node\b/mg) || []).length;
			if (msg) msg.textContent = 'Yedek indirildi: ' + name + ' (' + n + ' sunucu)';
		}).catch(() => { if (msg) msg.textContent = 'Yedek alınamadı: panel yanıt vermedi.'; });
	},

	doRestore(ev) {
		const UP = '/tmp/kediray-restore.conf', msg = document.getElementById('ka-bk-msg');
		return ui.uploadFile(UP, ev.target).then(() => {
			return new Promise(resolve => {
				ui.showModal('Yedekten geri yükle', [
					h('p', {}, 'Mevcut sunucuların ve ayarların yedekteki ile DEĞİŞTİRİLECEK. Önceki ayar modemde /etc/kediray.pre-restore olarak saklanır. Devam edilsin mi?'),
					h('div', { 'class': 'right' }, [
						h('button', { 'class': 'btn cbi-button', 'click': () => { ui.hideModal(); resolve(false); } }, 'Vazgeç'),
						' ',
						h('button', { 'class': 'btn cbi-button cbi-button-negative', 'click': () => { ui.hideModal(); resolve(true); } }, 'Geri yükle')
					])
				]);
			});
		}, e => {
			const m = (e && e.message) || String(e || '');
			if (!/cancel|iptal/i.test(m) && msg) msg.textContent = 'Dosya yüklenemedi: ' + m;
			return null;
		}).then(go => {
			if (go === null) return;
			if (!go) { if (msg) msg.textContent = 'Vazgeçildi.'; return; }
			return fs.exec(CLI, ['restore', UP]).then(r => {
				const out = ((r.stdout || '') + (r.stderr || '')).trim();
				if (msg) msg.textContent = out || (r.code === 0 ? 'Geri yüklendi.' : 'Geri yüklenemedi.');
				if (r.code === 0) setTimeout(() => location.reload(), 2500);
			}).catch(() => { if (msg) msg.textContent = 'Panel yanıt vermedi; birkaç saniye sonra sayfayı yenile.'; });
		});
	},

	doOnline() {
		return fs.exec(CLI, ['update', 'install']).catch(() => ({ code: 0, stdout: '' })).then(r => this.runUpdate(r));
	},

	doUpdate(ev) {
		const UP = '/tmp/kediray-update.sh';
		return ui.uploadFile(UP, ev.target).then(() => {
			// Başlatma isteği geç yanıtlanırsa (panel meşgulken) hata gösterme: kurulum günlüğünden ilerlemeyi izleriz
			return fs.exec(CLI, ['selfupdate', UP]).catch(() => ({ code: 0, stdout: '' }));
		}, e => {
			const msg = (e && e.message) || String(e || '');
			if (!/cancel|iptal/i.test(msg)) ui.addNotification(null, h('p', {}, 'Dosya yüklenemedi: ' + msg), 'error');
			return null;
		}).then(r => this.runUpdate(r));
	},

	runUpdate(r) {
		const TOTAL = 7;   // kurulumun ana adımları (==> satırları)
		return Promise.resolve(r).then(r => {
			if (!r) return;
			if (r.code !== 0) {
				ui.addNotification(null, h('p', {}, ((r.stdout || '') + (r.stderr || '')).trim() || 'Güncelleme başlatılamadı.'), 'error');
				return;
			}
			const out = h('pre', { 'style': 'max-height:260px;overflow:auto;white-space:pre-wrap;margin:8px 0;font-size:.85em' }, (r.stdout || '').trim());
			const fill = h('div', { 'style': 'height:100%;width:3%;background:#3b82f6;border-radius:6px;transition:width .6s' });
			const label = h('div', { 'style': 'margin:6px 0 10px;font-weight:600' }, 'Güncelleme başlatılıyor…');
			const done = h('button', { 'class': 'btn cbi-button cbi-button-action', 'disabled': true, 'click': () => location.reload() }, 'Sayfayı yenile');
			ui.showModal('KediRay güncelleniyor', [
				h('p', {}, 'Kurulum arka planda çalışıyor. Panel birkaç saniye yanıt vermeyebilir, bu normal.'),
				h('div', { 'style': 'height:12px;border-radius:6px;background:rgba(128,128,128,.25);overflow:hidden' }, fill),
				label,
				h('details', {}, [h('summary', { 'style': 'cursor:pointer;opacity:.75' }, 'Ayrıntılı çıktı'), out]),
				h('div', { 'class': 'right' }, done)
			]);
			let fails = 0, seen = 0, polls = 0, finished = false;
			const bar = (pct, text) => { fill.style.width = Math.max(3, Math.min(100, pct)) + '%'; label.textContent = text; };
			const restarting = () => {
				bar(100, 'Güncelleme tamamlandı ✔ — LuCI yenileniyor, sayfa birazdan yeniden yüklenecek…');
				done.disabled = false;
				if (!finished) { finished = true; setTimeout(() => location.reload(), 5000); }
			};
			const poll = () => { polls++; return fs.exec(CLI, ['selfupdate', 'log']).then(x => {
				fails = 0;
				const lines = (x.stdout || '').split('\n'), st = lines.shift() || '', sl = lines.shift() || '';
				const m = /^STEPS (\d+)\|(.*)$/.exec(sl);
				if (m) { seen = +m[1]; if (seen) bar(Math.round(seen / TOTAL * 92), 'Güncelleme: ' + seen + '/' + TOTAL + ' — ' + (m[2] || 'çalışıyor')); }
				out.textContent = lines.join('\n').trim();
				out.scrollTop = out.scrollHeight;
				if (/^DONE/.test(st)) {
					if (st === 'DONE 0') restarting();
					else if (!seen && polls < 6) setTimeout(poll, 2000);   // henüz başlamadı: birkaç saniye bekle
					else { bar(Math.round(seen / TOTAL * 92), seen ? 'Kurulum hata ile bitti (kod ' + st.slice(5) + '). Ayrıntılı çıktıya bak.' : 'Güncelleme başlatılamadı. Ayrıntılı çıktıya bak.'); done.disabled = false; }
				} else setTimeout(poll, 2000);
			}).catch(() => {
				// kurulumun sonunda LuCI'nin arka plan servisi (rpcd) yeniden başlar; bu sırada yanıt gelmez
				fails++;
				if (seen >= TOTAL - 1 || fails >= 8) restarting();
				else label.textContent = 'Panel yanıt vermiyor, bekleniyor… (güncelleme arka planda sürüyor)';
				if (!finished) setTimeout(poll, 2500);
			}); };
			setTimeout(poll, 2000);
		});
	},

	handleSaveApply: null,
	handleSave: null,
	handleReset: null
});
KEDIRAY_EOF_16
cat > '/www/luci-static/resources/view/kediray/ayir.js' <<'KEDIRAY_EOF_23'
'use strict';
'require view';
'require fs';
'require ui';
'require poll';
'require dom';

/* KediRay - VPN Ayırma: hangi motor çalışsın, hangi uygulama VPN'den / direkt gitsin */

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

function run(args) {
	return fs.exec(CLI, args).catch(e => ({ code: 1, stdout: '', stderr: String(e) }));
}
function runJson(args) {
	return run(args).then(r => { try { return JSON.parse(r.stdout || 'null'); } catch (e) { return null; } });
}
function outOf(r) { return ((r.stdout || '') + (r.stderr || '')).trim(); }

const PRESETS = [
	{ name: 'WhatsApp', route: 'vpn', ports: '5222', domains: ['geosite:whatsapp', 'domain:whatsapp.com', 'domain:whatsapp.net', 'domain:wa.me'], ips: ['geoip:facebook'] },
	{ name: 'Metin2', route: 'direct', ports: '11000-13999', expand: '24',
	  domains: ['domain:gameforge.com', 'domain:metin2.gameforge.com', 'domain:gameforge.io', 'domain:gameforge.net'],
	  ips: ['79.110.80.0/20', '79.110.87.192/32', '79.110.92.148/32', '79.110.90.244/32', '79.110.90.99/32', '79.110.91.96/32', '79.110.91.98/32', '79.110.92.117/32', '79.110.92.96/32', '79.110.92.97/32', '79.110.92.98/32'] },
	{ name: 'Microsoft Teams', route: 'direct', domains: ['domain:teams.microsoft.com', 'domain:teams.live.com', 'domain:teams.cloud.microsoft', 'domain:skype.com', 'domain:lync.com'], ips: ['13.107.64.0/18', '52.112.0.0/14', '52.122.0.0/15'] },
	{ name: 'YouTube', domains: ['geosite:youtube', 'domain:googlevideo.com', 'domain:ytimg.com'] },
	{ name: 'Netflix', domains: ['geosite:netflix', 'domain:nflxvideo.net', 'domain:nflximg.net'] },
	{ name: 'Telegram', domains: ['geosite:telegram'], ips: ['geoip:telegram'] },
	{ name: 'Instagram', domains: ['domain:instagram.com', 'domain:cdninstagram.com'] },
	{ name: 'Discord', dns: true, domains: ['domain:discord.com', 'domain:discord.gg', 'domain:discordapp.com', 'domain:discord.media', 'domain:discordapp.net', 'domain:discordcdn.com'] },
	{ name: 'Steam', domains: ['domain:steampowered.com', 'domain:steamcommunity.com', 'domain:steamstatic.com'] },
	{ name: 'Spotify', domains: ['domain:spotify.com', 'domain:scdn.co'] },
	{ name: 'Zoom', domains: ['domain:zoom.us', 'domain:zoom.com'] }
];

const CSS = `
.ka-card{border:1px solid rgba(128,128,128,.3);border-radius:10px;padding:14px;margin:0 0 14px}
.ka-card h3{margin:0 0 10px}
.ka-row{display:flex;align-items:center;justify-content:space-between;gap:10px;padding:8px 0;border-top:1px solid rgba(128,128,128,.18);flex-wrap:wrap}
.ka-row:first-of-type{border-top:0}
.ka-sub{opacity:.65;font-size:.85em}
.ka-tag{display:inline-block;padding:1px 8px;border-radius:10px;font-size:.78em;margin-left:8px;background:rgba(128,128,128,.25)}
.ka-on{background:#22a04b;color:#fff}
.ka-seg{display:inline-flex;border:1px solid rgba(128,128,128,.45);border-radius:6px;overflow:hidden}
.ka-seg button{border:0;background:transparent;padding:4px 14px;cursor:pointer;color:inherit}
.ka-seg button.a-vpn{background:#3b82f6;color:#fff}
.ka-seg button.a-dir{background:#e08a1e;color:#fff}
.ka-seg button.a-warp{background:#f6821f;color:#fff}
.ka-seg button.a-frag{background:#8b5cf6;color:#fff}
.ka-form{display:grid;gap:8px;max-width:520px}
.ka-form textarea,.ka-form input,.ka-form select{width:100%}
.ka-chips{display:flex;flex-wrap:wrap;gap:6px;margin-top:6px}
`;

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

return view.extend({
	load() {
		return Promise.all([runJson(['engines']), runJson(['apps']), runJson(['warp', 'status', '--json'])]);
	},

	render(data) {
		this.elEng = h('div', { 'class': 'ka-card' });
		this.elApps = h('div', { 'class': 'ka-card' });
		this.elWarp = h('div', { 'class': 'ka-card' });
		const root = h('div', {}, [
			h('style', {}, CSS),
			h('h2', {}, 'VPN Ayırma'),
			h('p', { 'class': 'ka-sub' }, 'Hangi VPN motorunun çalışacağını seç ve hangi uygulamaların VPN\'den, hangilerinin direkt gideceğini belirle.'),
			this.elEng, this.elWarp, this.elApps, this.buildAdd()
		]);
		this.fill(data[0], data[1], data[2]);
		poll.add(() => this.refresh(), 6);
		return root;
	},

	refresh() {
		if (this.busyNow) return Promise.resolve();
		return Promise.all([runJson(['engines']), runJson(['apps']), runJson(['warp', 'status', '--json'])]).then(d => this.fill(d[0], d[1], d[2]));
	},

	fill(engines, apps, warp) {
		this.warp = warp || {};
		this.renderEngines(engines || []);
		this.renderWarp(this.warp);
		this.renderApps(apps || []);
	},

	renderEngines(list) {
		const rows = list.map(e => h('div', { 'class': 'ka-row' }, [
			h('div', {}, [h('b', {}, e.name), h('span', { 'class': 'ka-tag' + (e.running ? ' ka-on' : '') }, e.running ? 'Çalışıyor' : 'Durdu'),
				e.id !== 'kediray' ? h('div', { 'class': 'ka-sub' }, 'servis: ' + e.id) : '']),
			h('div', {}, e.running
				? h('button', { 'class': 'btn cbi-button cbi-button-negative', 'click': ui.createHandlerFn(this, () => this.engine(e, 'stop')) }, 'Durdur')
				: h('button', { 'class': 'btn cbi-button cbi-button-action', 'click': ui.createHandlerFn(this, () => this.engine(e, 'start')) }, 'Başlat'))
		]));
		dom.content(this.elEng, [
			h('h3', {}, 'VPN motoru'),
			...rows,
			h('div', { 'class': 'ka-sub', 'style': 'margin-top:8px' }, 'Aynı anda yalnızca biri çalışır: birini başlatınca çalışan diğeri durdurulur ve açılışta da seçtiğin motor çalışır. KediRay\'de internet gelmezse otomatik geri alınır.')
		]);
	},

	engine(e, act) {
		const label = e.name;
		return new Promise(resolve => {
			ui.showModal(label + (act === 'start' ? ' başlatılsın mı?' : ' durdurulsun mu?'), [
				h('p', {}, act === 'start'
					? 'Çalışan diğer VPN motorları durdurulur ve ' + label + ' başlatılır. İnternet birkaç saniye kesilebilir.'
					: label + ' durdurulur. Başka bir motor çalışmıyorsa internet VPN\'siz (kendi hattınla) devam eder.'),
				h('div', { 'class': 'right' }, [
					h('button', { 'class': 'btn', 'click': () => { ui.hideModal(); resolve(); } }, 'Vazgeç'), ' ',
					h('button', { 'class': 'btn cbi-button cbi-button-action', 'click': () => { resolve(this.runEngine(e, act)); } }, 'Evet')
				])
			]);
		});
	},

	runEngine(e, act) {
		this.busyNow = true;
		const out = h('pre', { 'style': 'max-height:260px;overflow:auto;white-space:pre-wrap;font-size:.85em' }, 'Başlatılıyor…');
		const close = h('button', { 'class': 'btn', 'disabled': true, 'click': () => { ui.hideModal(); this.busyNow = false; this.refresh(); } }, 'Kapat');
		ui.showModal(e.name + (act === 'start' ? ' başlatılıyor…' : ' durduruluyor…'), [
			h('p', {}, 'İşlem arka planda sürüyor; bu sayfa donarsa birkaç saniye bekle.'), out, h('div', { 'class': 'right' }, close)
		]);
		let fails = 0;
		const poll1 = () => run(['engine-log']).then(r => {
			fails = 0;
			const lines = (r.stdout || '').split('\n'), st = lines.shift() || '';
			out.textContent = lines.join('\n').trim();
			out.scrollTop = out.scrollHeight;
			if (/^DONE/.test(st)) {
				out.textContent += '\n\n' + (st === 'DONE 0' ? 'Tamamlandı ✔' : 'Hata ile bitti (' + st.slice(5) + ')');
				close.disabled = false;
			} else setTimeout(poll1, 2000);
		}).catch(() => { if (++fails < 10) setTimeout(poll1, 2500); else { close.disabled = false; } });
		return run(['engine-bg', e.id, act]).then(r => {
			if (r.code !== 0) { out.textContent = outOf(r) || 'Başlatılamadı'; close.disabled = false; return; }
			setTimeout(poll1, 1500);
		});
	},

	renderWarp(w) {
		const reg = !!w.registered;
		const via = h('select', { 'change': ui.createHandlerFn(this, ev => this.app(['warp', 'via', ev.target.value])) }, [
			h('option', { 'value': 'vpn' }, 'VPN sunucusunun içinden (önerilen)'), h('option', { 'value': 'direct' }, 'Doğrudan hattan')]);
		via.value = w.via || 'vpn';
		dom.content(this.elWarp, [
			h('h3', {}, 'Cloudflare WARP'),
			h('div', { 'class': 'ka-sub' }, 'Seçtiğin uygulamaların çıkışı Cloudflare WARP olur: site seni VPN sunucusunun değil Cloudflare\'in IP\'si olarak görür. Her uygulamanın yanındaki "WARP" düğmesiyle seçilir.'),
			h('div', { 'class': 'ka-row' }, [
				h('div', {}, [h('b', {}, 'Durum'), h('span', { 'class': 'ka-tag' + (reg && w.enabled ? ' ka-on' : '') }, !reg ? 'Hesap yok' : (w.enabled ? 'Açık' : 'Kapalı'))]),
				h('div', { 'style': 'display:flex;gap:8px;flex-wrap:wrap' }, !reg
					? [h('button', { 'class': 'btn cbi-button cbi-button-action', 'click': ui.createHandlerFn(this, () => this.warpRegister()) }, 'WARP hesabı oluştur')]
					: [h('button', { 'class': 'btn cbi-button', 'click': ui.createHandlerFn(this, () => this.app(['warp', w.enabled ? 'off' : 'on'])) }, w.enabled ? 'Kapat' : 'Aç'),
						h('button', { 'class': 'btn cbi-button cbi-button-negative', 'click': ui.createHandlerFn(this, () => this.app(['warp', 'forget'])) }, 'Hesabı sil')])
			]),
			reg ? h('div', { 'class': 'ka-row' }, [h('div', {}, 'WARP bağlantı yolu'), via]) : ''
		]);
	},

	warpRegister() {
		ui.showModal('WARP hesabı oluşturuluyor…', [h('p', { 'class': 'spinning' }, 'Cloudflare\'e kaydolunuyor, 30 sn kadar sürebilir')]);
		return run(['warp', 'register']).then(r => {
			ui.hideModal();
			if (r.code !== 0) ui.addNotification(null, h('p', {}, outOf(r) || 'Kayıt başarısız'), 'error');
			return this.refresh();
		});
	},

	renderApps(apps) {
		const rows = apps.map(a => h('div', { 'class': 'ka-row', 'style': a.enabled ? '' : 'opacity:.55' }, [
			h('div', {}, [h('b', {}, a.name),
				h('div', { 'class': 'ka-sub' }, [a.ports ? 'port ' + a.ports : '', a.ips ? ' · ' + a.ips + ' IP bloğu' : '', a.domains ? ' · ' + a.domains + ' alan adı' : ''].join('').replace(/^ · /, ''))]),
			h('div', { 'style': 'display:flex;gap:8px;align-items:center;flex-wrap:wrap' }, [
				h('div', { 'class': 'ka-seg' }, [
					h('button', { 'title': 'VPN: Bu uygulamanın trafiği VPN tünelinden çıkar. Operatör ne yaptığını görmez, siteler seni VPN sunucusunun IP\'siyle görür. Tünel koparsa bağlantı da kopar.', 'class': a.route === 'vpn' ? 'a-vpn' : '', 'click': ui.createHandlerFn(this, () => a.route !== 'vpn' && this.app(['app', a.sec, 'vpn'])) }, 'VPN'),
					h('button', { 'title': 'Direkt: Tünele girmez, doğrudan hattan çıkar. En düşük ping; VPN yeniden başlasa bile bağlantı kopmaz. Siteler seni operatörün IP\'siyle görür (oyun ve görüntülü görüşme için uygun).', 'class': a.route === 'direct' ? 'a-dir' : '', 'click': ui.createHandlerFn(this, () => a.route !== 'direct' && this.app(['app', a.sec, 'direct'])) }, 'Direkt'),
					h('button', { 'title': 'Parçala: Direkt çıkar (VPN yok, ping düşük) ama TLS el sıkışması parçalanır; operatörün site adı (SNI) engelini aşabilir. IP\'n operatörün IP\'si kalır.', 'class': a.route === 'frag' ? 'a-frag' : '', 'click': ui.createHandlerFn(this, () => a.route !== 'frag' && this.app(['app', a.sec, 'frag'])) }, 'Parçala'),
					(this.warp && this.warp.registered) || a.route === 'warp' ? h('button', { 'title': 'WARP: Çıkış Cloudflare WARP ağından olur; siteler seni VPN sunucusunun değil Cloudflare\'in IP\'siyle görür. VPN sunucusunun IP\'sini engelleyen siteler için.', 'class': a.route === 'warp' ? 'a-warp' : '', 'click': ui.createHandlerFn(this, () => a.route !== 'warp' && this.app(['app', a.sec, 'warp'])) }, 'WARP') : ''
				]),
				h('button', { 'class': 'btn cbi-button' + (a.tunnel_dns ? ' cbi-button-action' : ''), 'title': a.tunnel_dns ? 'DNS: tünel: Bu uygulamanın alan adları tünel içinden çözülür; yanlış ya da engelli adres geliyorsa işe yarar. Tıkla: normale döndür.' : 'DNS: normal: Bu uygulamanın alan adları normal DNS ayarınla çözülür. Tıkla: tünel DNS\'ine al (Discord gibi DNS\'i bozulan uygulamalar için).',
					'click': ui.createHandlerFn(this, () => this.app(['app', a.sec, 'dns', a.tunnel_dns ? 'off' : 'on'])) }, a.tunnel_dns ? 'DNS: tünel ✔' : 'DNS: normal'),
				h('button', { 'class': 'btn cbi-button', 'title': 'Bir ad yaz (örn. discord.com): yönlendirici çözer, ilgili ve alt alan adlarını listeler, seçtiklerin bu uygulamaya eklenir. Uygulamanın bazı adresleri kurala girmiyorsa kullan.', 'click': ui.createHandlerFn(this, () => this.finder(a)) }, 'Alan adı bul'),
				h('button', { 'class': 'btn cbi-button', 'title': a.enabled ? 'Kapat: Bu uygulama kuralını geçici kapatır (silinmez); trafik genel kurala göre gider.' : 'Aç: Bu uygulama kuralını yeniden etkinleştirir.', 'click': ui.createHandlerFn(this, () => this.app(['app', a.sec, a.enabled ? 'off' : 'on'])) }, a.enabled ? 'Kapat' : 'Aç'),
				h('button', { 'class': 'btn cbi-button cbi-button-negative', 'title': 'Sil: Bu uygulama kuralını kalıcı olarak siler.', 'click': ui.createHandlerFn(this, () => this.delApp(a)) }, 'Sil')
			])
		]));
		const have = new Set(apps.map(a => (a.name || '').toLowerCase()));
		const chips = PRESETS.filter(p => !have.has(p.name.toLowerCase())).map(p =>
			h('button', { 'class': 'btn cbi-button', 'click': ui.createHandlerFn(this, () => this.preset(p)) }, '+ ' + p.name));
		dom.content(this.elApps, [
			h('h3', {}, 'Uygulamalar (' + apps.length + ')'),
			...rows,
			chips.length ? h('div', { 'class': 'ka-sub', 'style': 'margin-top:10px' }, 'Hazır uygulamalar (Metin2 ve Teams direkt, diğerleri VPN gelir):') : '',
			chips.length ? h('div', { 'class': 'ka-chips' }, chips) : '',
			h('div', { 'class': 'ka-sub', 'style': 'margin-top:8px' }, 'Direkt: çekirdekte bypass, VPN yeniden başlasa bile bağlantı kopmaz.')
		]);
	},

	async app(args) {
		const r = await run(args);
		if (r.code !== 0) ui.addNotification(null, h('p', {}, outOf(r) || 'İşlem başarısız'), 'error');
		return this.refresh();
	},

	delApp(a) {
		return new Promise(resolve => {
			ui.showModal(a.name + ' silinsin mi?', [
				h('p', {}, 'Bu uygulama kuralı kalıcı olarak silinir.'),
				h('div', { 'class': 'right' }, [
					h('button', { 'class': 'btn', 'click': () => { ui.hideModal(); resolve(); } }, 'Vazgeç'), ' ',
					h('button', { 'class': 'btn cbi-button cbi-button-negative', 'click': () => { ui.hideModal(); resolve(this.app(['app-del', a.sec])); } }, 'Sil')
				])
			]);
		});
	},

	// Alan adı bulucu: adı yaz -> yönlendirici çözer, ilgili/alt alan adlarını listeler -> seçilenler eklenir.
	// onAdd(seçilen alan adları dizisi) -> Promise
	finder(a, onAdd) {
		const inp = h('input', { 'type': 'text', 'placeholder': 'ör. discord.com', 'style': 'width:100%' });
		const res = h('div', { 'style': 'margin:10px 0;max-height:300px;overflow:auto' });
		const have = new Set(a ? (a.domain_list || []).map(x => x.replace(/^domain:/, '')) : []);
		let found = [];
		const add = h('button', { 'class': 'btn cbi-button cbi-button-positive', 'disabled': true });
		const search = () => {
			const v = inp.value.trim();
			if (!v) return;
			res.textContent = 'Aranıyor…'; add.disabled = true;
			return run(['domain-find', v]).then(r => {
				if (r.code !== 0) { res.textContent = outOf(r) || 'Hata'; return; }
				found = (r.stdout || '').split('\n').map(l => l.split('\t')).filter(x => x[0]);
				const rows = found.map((f, i) => {
					const ok = f[1] !== 'yok';
					const cb = h('input', { 'type': 'checkbox', 'data-d': f[0] });
					cb.disabled = !ok || have.has(f[0]);
					cb.checked = ok && !have.has(f[0]) && (f[1] === 'ana' || f[1] === 'ilgili');
					return h('label', { 'style': 'display:flex;gap:8px;align-items:center;padding:3px 0' }, [cb, h('span', {}, f[0]),
						h('span', { 'class': 'ka-tag' }, have.has(f[0]) ? 'listede' : f[1] === 'ana' ? 'ana alan adı' : f[1] === 'ilgili' ? 'ilgili hizmet' : f[1] === 'yok' ? 'çözülemedi' : 'alt alan adı')]);
				});
				dom.content(res, rows.length ? rows : 'Sonuç yok');
				add.disabled = !found.some(f => f[1] !== 'yok');
			});
		};
		add.textContent = 'Seçilenleri listeye ekle';
		add.addEventListener('click', ui.createHandlerFn(this, () => {
			const sel = Array.from(res.querySelectorAll('input[type=checkbox]')).filter(c => c.checked && !c.disabled).map(c => c.getAttribute('data-d'));
			ui.hideModal();
			// ana alan adı "domain:" ile eklenir: alt alan adlarının hepsini kapsar
			const base = sel.filter(d => !sel.some(o => o !== d && d.endsWith('.' + o)));
			return a ? this.addDomains(a, base) : onAdd(base);
		}));
		inp.addEventListener('keydown', ev => { if (ev.key === 'Enter') { ev.preventDefault(); search(); } });
		ui.showModal('Alan adı bul' + (a ? ' — ' + a.name : ''), [
			h('p', { 'class': 'ka-sub' }, 'Uygulamanın bilinen bir adresini yaz; ana alan adı, yaygın alt alan adları ve (biliniyorsa) ilgili hizmetlerin adları aranır. "domain:" kaydı alt alan adlarını da kapsar.'),
			h('div', { 'style': 'display:flex;gap:8px' }, [inp, h('button', { 'class': 'btn cbi-button cbi-button-action', 'click': ui.createHandlerFn(this, search) }, 'Bul')]),
			res,
			h('div', { 'class': 'right' }, [h('button', { 'class': 'btn', 'click': ui.hideModal }, 'Vazgeç'), ' ', add])
		]);
		inp.focus();
	},

	async addDomains(a, list) {
		for (const d of list) {
			const r = await run(['app', a.sec, 'add-domain', d]);
			if (r.code !== 0) ui.addNotification(null, h('p', {}, outOf(r) || 'Eklenemedi: ' + d), 'error');
		}
		return this.refresh();
	},

	preset(p) {
		return this.app(['app-add', p.name, p.route || 'vpn', p.ports || '', (p.domains || []).join(','), (p.ips || []).join(','), p.dns ? 'dns' : '', p.expand || '']);
	},

	buildAdd() {
		const name = h('input', { 'type': 'text', 'placeholder': 'Uygulama / oyun adı' });
		const route = h('select', {}, [h('option', { 'value': 'vpn' }, 'VPN'), h('option', { 'value': 'direct' }, 'Direkt'), h('option', { 'value': 'warp' }, 'WARP (Cloudflare)'), h('option', { 'value': 'frag' }, 'Direkt + TLS parçala (SNI engeli)')]);
		const ports = h('input', { 'type': 'text', 'placeholder': 'Portlar (boşlukla): 5222 11000-13999' });
		const doms = h('textarea', { 'rows': 3, 'placeholder': 'Alan adları (satır ya da virgülle): example.com, domain:foo.net, geosite:youtube' });
		const ips = h('textarea', { 'rows': 2, 'placeholder': 'IP / CIDR (satır ya da virgülle): 79.110.80.0/20' });
		const clean = s => s.value.split(/[\n,]+/).map(x => x.trim()).filter(x => x).join(',');
		const dns = h('input', { 'type': 'checkbox' });
		const find = h('button', { 'class': 'btn cbi-button', 'click': ui.createHandlerFn(this, () => this.finder(null, list => {
			const cur = clean(doms);
			doms.value = (cur ? cur + ',' : '') + list.map(d => 'domain:' + d).join(',');
		})) }, 'Alan adı bul…');
		const btn = h('button', { 'class': 'btn cbi-button cbi-button-positive', 'click': ui.createHandlerFn(this, () => {
			if (!name.value.trim()) { ui.addNotification(null, h('p', {}, 'Bir ad yaz.'), 'error'); return; }
			return this.app(['app-add', name.value.trim(), route.value, ports.value.trim(), clean(doms), clean(ips), dns.checked ? 'dns' : '']).then(() => {
				name.value = ports.value = doms.value = ips.value = ''; dns.checked = false;
			});
		}) }, 'Ekle');
		return h('div', { 'class': 'ka-card' }, [
			h('h3', {}, 'Yeni uygulama ekle'),
			h('div', { 'class': 'ka-form' }, [name, route, ports, doms, h('div', {}, find), ips,
				h('label', { 'style': 'display:flex;gap:8px;align-items:center' }, [dns, 'Alan adlarını tünel DNS\'iyle çöz (DNS\'i bozulan uygulamalar için)']),
				h('div', {}, btn)])
		]);
	},

	handleSaveApply: null,
	handleSave: null,
	handleReset: null
});
KEDIRAY_EOF_23
cat > '/usr/share/luci/menu.d/luci-app-kediray.json' <<'KEDIRAY_EOF_17'
{
	"admin/vpn": {
		"title": "VPN",
		"order": 60,
		"action": {
			"type": "firstchild"
		}
	},

	"admin/vpn/kediray": {
		"title": "KediRay VPN",
		"order": 5,
		"action": { "type": "firstchild" },
		"depends": { "acl": [ "luci-app-kediray" ], "uci": { "kediray": true } }
	},
	"admin/vpn/kediray/status": {
		"title": "Kontrol Paneli",
		"order": 1,
		"action": { "type": "view", "path": "kediray/status" }
	},
	"admin/vpn/kediray/trafik": {
		"title": "Trafik",
		"order": 2,
		"action": { "type": "view", "path": "kediray/trafik" }
	},
	"admin/vpn/kediray/ayir": {
		"title": "VPN Ayırma",
		"order": 3,
		"action": { "type": "view", "path": "kediray/ayir" }
	},
	"admin/vpn/kediray/settings": {
		"title": "Ayarlar",
		"order": 4,
		"action": { "type": "view", "path": "kediray/settings" }
	},
	"admin/vpn/kediray/log": {
		"title": "Günlük",
		"order": 5,
		"action": { "type": "view", "path": "kediray/log" }
	},
	"admin/vpn/kediray/about": {
		"title": "Hakkında",
		"order": 6,
		"action": { "type": "view", "path": "kediray/about" }
	}
}
KEDIRAY_EOF_17
cat > '/usr/share/rpcd/acl.d/luci-app-kediray.json' <<'KEDIRAY_EOF_18'
{
	"luci-app-kediray": {
		"description": "KediRay VPN yönetimi",
		"read": {
			"file": {
				"/usr/bin/kediray": [ "exec" ],
				"/usr/bin/kediray *": [ "exec" ]
			},
			"ubus": {
				"luci-rpc": [ "getHostHints" ],
				"file": [ "exec" ]
			},
			"uci": [ "kediray" ]
		},
		"write": {
			"cgi-io": [ "upload" ],
			"file": {
				"/tmp/kediray-update.sh": [ "write" ],
				"/tmp/kediray-restore.conf": [ "write" ]
			},
			"uci": [ "kediray" ]
		}
	}
}
KEDIRAY_EOF_18
cat > '/www/luci-static/kedi-logo.svg' <<'KEDIRAY_EOF_19'
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 108 108" width="256" height="256">
  <defs>
    <linearGradient id="bg" x1="0" y1="0" x2="1" y2="1">
      <stop offset="0" stop-color="#4C1D95"/>
      <stop offset="1" stop-color="#7C3AED"/>
    </linearGradient>
  </defs>
  <rect width="108" height="108" rx="26" fill="url(#bg)"/>
  <path fill="#F3E8FF" d="M30,32 L43,43 Q54,40 65,43 L78,32 L78,62 Q78,80 54,80 Q30,80 30,62 Z"/>
  <path fill="#C4B5FD" d="M34,38 L41,44 L34,50 Z M74,38 L67,44 L74,50 Z"/>
  <path fill="#FBBF24" d="M57,40 L47,56 L53,56 L50,67 L61,50 L55,50 Z"/>
  <path fill="#4C1D95" d="M37,62 Q41,57 45,62 Q41,66 37,62 Z M63,62 Q67,57 71,62 Q67,66 63,62 Z"/>
  <path fill="#A78BFA" d="M51,69 L57,69 L54,73 Z"/>
</svg>
KEDIRAY_EOF_19
mkdir -p /usr/libexec/rpcd
cat > '/usr/bin/aw1k-usage' <<'KEDIRAY_EOF_20'
#!/bin/sh
# Günlük mobil veri kaydı. Satır biçimi: YYYY-MM-DD rx_bayt tx_bayt
DEV="wwan0_1"
PERSIST="/etc/aw1k-usage.db"   # kalıcı kopya (flash), saatte bir yazılır
RUN="/tmp/aw1k-usage.db"       # çalışma kopyası (RAM)
LAST="/tmp/aw1k-usage.last"    # önceki sayaç değerleri

st=$(ubus call network.device status "{\"name\":\"$DEV\"}" 2>/dev/null) || exit 0
rx=$(echo "$st" | jsonfilter -e '@.statistics.rx_bytes')
tx=$(echo "$st" | jsonfilter -e '@.statistics.tx_bytes')
[ -n "$rx" ] && [ -n "$tx" ] || exit 0

if [ ! -f "$RUN" ]; then
    if [ -f "$PERSIST" ]; then cp "$PERSIST" "$RUN"; else : > "$RUN"; fi
fi

if [ -f "$LAST" ]; then
    read prx ptx < "$LAST"
elif [ -f "$PERSIST" ]; then
    prx=0; ptx=0            # modem yeniden başlamış: sayaçlar sıfırdan başladı
else
    prx=$rx; ptx=$tx        # ilk kurulum: geçmiş sayaçlar yok sayılır
fi

# Sayaç geriye gittiyse (yeniden başlatma) mevcut değer yeni farktır
if [ "$rx" -lt "$prx" ]; then drx=$rx; else drx=$((rx - prx)); fi
if [ "$tx" -lt "$ptx" ]; then dtx=$tx; else dtx=$((tx - ptx)); fi
echo "$rx $tx" > "$LAST"

today=$(date +%F)
awk -v d="$today" -v rx="$drx" -v tx="$dtx" '
    $1 == d { $2 += rx; $3 += tx; found = 1 }
    { printf "%s %.0f %.0f\n", $1, $2, $3 }
    END { if (!found) printf "%s %.0f %.0f\n", d, rx, tx }
' "$RUN" | tail -n 400 > "$RUN.new" && mv "$RUN.new" "$RUN"

if [ ! -f "$PERSIST" ] || [ "$(date +%M)" -lt 2 ]; then
    cp "$RUN" "$PERSIST"
fi
KEDIRAY_EOF_20
cat > '/usr/libexec/rpcd/aw1k' <<'KEDIRAY_EOF_21'
#!/bin/sh
# rpcd eklentisi: ubus call aw1k usage | kediray | kediray_ctl | kediray_devices | wifi_clients
case "$1" in
list)
    echo '{ "usage": {}, "kediray": {}, "kediray_ctl": { "action": "str" }, "kediray_devices": {}, "wifi_clients": {}, "guest_get": {}, "guest_set": { "enabled": true, "ssid": "str", "key": "str" }, "wan_info": {}, "bandpw_write": { "pw": "str" }, "kediray_device": { "mac": "str", "mode": "str", "name": "str" } }'
    ;;
call)
    case "$2" in
    kediray)
        running=false; /etc/init.d/kediray status 2>/dev/null | grep -q running && running=true
        enabled=false; /etc/init.d/kediray enabled 2>/dev/null && enabled=true
        st=$(ubus call network.device status '{"name":"kediray0"}' 2>/dev/null)
        rx=$(echo "$st" | jsonfilter -e '@.statistics.rx_bytes'); [ -n "$rx" ] || rx=0
        tx=$(echo "$st" | jsonfilter -e '@.statistics.tx_bytes'); [ -n "$tx" ] || tx=0
        since=0
        [ -f /var/etc/kediray/config.json ] && since=$(stat -c %Y /var/etc/kediray/config.json 2>/dev/null || echo 0)
        printf '{"running":%s,"enabled":%s,"since":%s,"now":%s,"rx":%s,"tx":%s}' \
            "$running" "$enabled" "$since" "$(date +%s)" "$rx" "$tx"
        ;;
    kediray_devices)
        def=$(uci -q get kediray.main.default_device); [ -n "$def" ] || def=vpn
        printf '{"default":"%s","devices":[' "$def"
        n=0; i=0
        while mac=$(uci -q get kediray.@device[$i].mac); do
            mode=$(uci -q get kediray.@device[$i].mode)
            [ $n -gt 0 ] && printf ','
            printf '{"mac":"%s","mode":"%s"}' "$mac" "$mode"
            n=$((n+1)); i=$((i+1))
        done
        printf '],"assoc":['
        n=0
        for obj in $(ubus list 'hostapd.*' 2>/dev/null); do
            dev=${obj#hostapd.}
            out=$(ubus call iwinfo assoc "{\"device\":\"$dev\"}" 2>/dev/null) || continue
            macs=$(echo "$out" | jsonfilter -e '@.results[*].mac')
            times=$(echo "$out" | jsonfilter -e '@.results[*].connected_time')
            j=0
            for m in $macs; do
                t=$(echo "$times" | sed -n "$((j+1))p"); [ -n "$t" ] || t=-1
                [ $n -gt 0 ] && printf ','
                printf '{"mac":"%s","secs":%s}' "$m" "$t"
                n=$((n+1)); j=$((j+1))
            done
        done
        printf ']}'
        ;;
    wifi_clients)
        now=$(date +%s)
        tmp=/tmp/aw1k-wc.$$
        : > $tmp
        printf '{"now":%s,"status":' "$now"
        ubus call network.wireless status 2>/dev/null || printf 'null'
        printf ',"ifaces":['
        n=0
        for obj in $(ubus list 'hostapd.*' 2>/dev/null); do
            dev=${obj#hostapd.}
            data=$(ubus call "$obj" get_clients 2>/dev/null) || continue
            echo "$data" >> $tmp
            as=$(ubus call iwinfo assoc "{\"device\":\"$dev\"}" 2>/dev/null); [ -n "$as" ] || as=null
            [ $n -gt 0 ] && printf ','
            printf '{"name":"%s","data":%s,"assoc":%s}' "$dev" "$data" "$as"
            n=$((n+1))
        done
        printf '],"seen":{'
        f=/tmp/aw1k-seen; : > $f.new
        for m in $(grep -oE '([0-9a-fA-F]{2}:){5}[0-9a-fA-F]{2}' $tmp | tr 'A-F' 'a-f' | sort -u); do
            ts=$(grep "^$m " $f 2>/dev/null | head -n1 | cut -d' ' -f2); [ -n "$ts" ] || ts=$now
            echo "$m $ts" >> $f.new
        done
        mv $f.new $f
        awk '{ if (NR>1) printf ","; printf "\"%s\":%s", $1, $2 }' $f
        printf '}}'
        rm -f $tmp
        ;;
    guest_get)
        esc() { printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g'; }
        if ! uci -q get wireless.guest_wifi >/dev/null; then
            printf '{"exists":false}'
        else
            dis=$(uci -q get wireless.guest_wifi.disabled); en=true; [ "$dis" = 1 ] && en=false
            printf '{"exists":true,"enabled":%s,"ssid":"%s","key":"%s","radio":"%s"}' "$en" \
                "$(esc "$(uci -q get wireless.guest_wifi.ssid)")" "$(esc "$(uci -q get wireless.guest_wifi.key)")" \
                "$(uci -q get wireless.guest_wifi.device)"
        fi
        ;;
    guest_set)
        read -r input
        enabled=$(echo "$input" | jsonfilter -e '@.enabled')
        ssid=$(echo "$input" | jsonfilter -e '@.ssid')
        key=$(echo "$input" | jsonfilter -e '@.key')
        if [ -z "$ssid" ] || [ ${#ssid} -gt 32 ]; then printf '{"ok":false,"error":"Ağ adı 1-32 karakter olmalı"}'; exit 0; fi
        if [ ${#key} -lt 8 ] || [ ${#key} -gt 63 ]; then printf '{"ok":false,"error":"Şifre 8-63 karakter olmalı"}'; exit 0; fi
        # ağ arayüzü
        if ! uci -q get network.guest >/dev/null; then
            lanip=$(uci -q get network.lan.ipaddr | cut -d/ -f1)
            gip=192.168.50.1; case "$lanip" in 192.168.50.*) gip=192.168.51.1 ;; esac
            uci set network.guest=interface
            uci set network.guest.proto=static
            uci set network.guest.ipaddr="$gip"
            uci set network.guest.netmask=255.255.255.0
        fi
        # DHCP
        if ! uci -q get dhcp.guest >/dev/null; then
            uci set dhcp.guest=dhcp
            uci set dhcp.guest.interface=guest
            uci set dhcp.guest.start=100
            uci set dhcp.guest.limit=100
            uci set dhcp.guest.leasetime=1h
        fi
        # güvenlik duvarı: misafir ağı yalnızca internete çıkar, LAN'a erişemez
        if ! uci -q get firewall.guest_zone >/dev/null; then
            wz=wan
            uci -q show firewall | grep -q "^firewall\.@zone\[[0-9]*\]\.name='wan'$" || {
                wz=$(uci -q show firewall | sed -n "s/^firewall\.@zone\[\([0-9]*\)\]\.masq='1'$/\1/p" | head -n1)
                [ -n "$wz" ] && wz=$(uci -q get firewall.@zone[$wz].name) || wz=wan
            }
            uci set firewall.guest_zone=zone
            uci set firewall.guest_zone.name=guest
            uci set firewall.guest_zone.network=guest
            uci set firewall.guest_zone.input=REJECT
            uci set firewall.guest_zone.output=ACCEPT
            uci set firewall.guest_zone.forward=REJECT
            uci set firewall.guest_fwd=forwarding
            uci set firewall.guest_fwd.src=guest
            uci set firewall.guest_fwd.dest="$wz"
            uci set firewall.guest_dns=rule
            uci set firewall.guest_dns.name='Guest-DNS'
            uci set firewall.guest_dns.src=guest
            uci set firewall.guest_dns.dest_port=53
            uci set firewall.guest_dns.proto='tcp udp'
            uci set firewall.guest_dns.target=ACCEPT
            uci set firewall.guest_dhcp=rule
            uci set firewall.guest_dhcp.name='Guest-DHCP'
            uci set firewall.guest_dhcp.src=guest
            uci set firewall.guest_dhcp.dest_port=67
            uci set firewall.guest_dhcp.proto=udp
            uci set firewall.guest_dhcp.family=ipv4
            uci set firewall.guest_dhcp.target=ACCEPT
        fi
        # Wi-Fi: tercihen 2.4 GHz radyo
        if ! uci -q get wireless.guest_wifi >/dev/null; then
            radio=""
            for r in $(uci -q show wireless | sed -n 's/^wireless\.\([^.=]*\)=wifi-device$/\1/p'); do
                [ -n "$radio" ] || radio=$r
                [ "$(uci -q get wireless.$r.band)" = 2g ] && { radio=$r; break; }
            done
            [ -n "$radio" ] || { printf '{"ok":false,"error":"Wi-Fi radyosu bulunamadı"}'; exit 0; }
            uci set wireless.guest_wifi=wifi-iface
            uci set wireless.guest_wifi.device="$radio"
            uci set wireless.guest_wifi.mode=ap
            uci set wireless.guest_wifi.network=guest
            uci set wireless.guest_wifi.isolate=1
        fi
        uci set wireless.guest_wifi.ssid="$ssid"
        uci set wireless.guest_wifi.encryption=psk2
        uci set wireless.guest_wifi.key="$key"
        if [ "$enabled" = true ]; then uci -q delete wireless.guest_wifi.disabled; else uci set wireless.guest_wifi.disabled=1; fi
        uci commit network; uci commit dhcp; uci commit firewall; uci commit wireless
        ( sleep 1; /etc/init.d/network reload; /etc/init.d/firewall reload; /etc/init.d/dnsmasq restart ) </dev/null >/dev/null 2>&1 &
        printf '{"ok":true}'
        ;;
    wan_info)
        dev=wwan0_1
        up=$(ubus call network.interface dump 2>/dev/null | jsonfilter -e "@.interface[@.l3_device='$dev'].uptime" | head -n1)
        [ -n "$up" ] || up=$(ubus call network.interface dump 2>/dev/null | jsonfilter -e "@.interface[@.device='$dev'].uptime" | head -n1)
        [ -n "$up" ] || up=-1
        st=$(ubus call network.device status "{\"name\":\"$dev\"}" 2>/dev/null)
        rx=$(echo "$st" | jsonfilter -e '@.statistics.rx_bytes'); [ -n "$rx" ] || rx=-1
        tx=$(echo "$st" | jsonfilter -e '@.statistics.tx_bytes'); [ -n "$tx" ] || tx=-1
        printf '{"uptime":%s,"rx":%s,"tx":%s}' "$up" "$rx" "$tx"
        ;;
    bandpw_write)
        read -r input
        pw=$(echo "$input" | jsonfilter -e '@.pw')
        [ -n "$pw" ] || { printf '{"ok":false}'; exit 0; }
        ( umask 077; printf '%s\n' "$pw" > /root/band-kilidi-sifre.txt )
        chmod 600 /root/band-kilidi-sifre.txt
        printf '{"ok":true}'
        ;;
    kediray_device)
        read -r input
        mac=$(echo "$input" | jsonfilter -e '@.mac')
        mode=$(echo "$input" | jsonfilter -e '@.mode')
        name=$(echo "$input" | jsonfilter -e '@.name' | tr -cd 'A-Za-z0-9 ._-')
        echo "$mac" | grep -qiE '^([0-9a-f]{2}:){5}[0-9a-f]{2}$' || { printf '{"ok":false}'; exit 0; }
        case "$mode" in vpn|direct|block|default) ;; *) printf '{"ok":false}'; exit 0 ;; esac
        /usr/bin/kediray device "$mac" "$mode" "$name" >/dev/null 2>&1
        printf '{"ok":true}'
        ;;
    kediray_ctl)
        read -r input
        action=$(echo "$input" | jsonfilter -e '@.action')
        case "$action" in
        start|stop|restart)
            ( /etc/init.d/kediray "$action" >/dev/null 2>&1 & )
            printf '{"ok":true}'
            ;;
        *) printf '{"ok":false}' ;;
        esac
        ;;
    usage)
        f=/tmp/aw1k-usage.db
        [ -f "$f" ] || f=/etc/aw1k-usage.db
        printf '{"today":"%s","days":[' "$(date +%F)"
        [ -f "$f" ] && awk 'NF == 3 { if (n++) printf ","; printf "{\"d\":\"%s\",\"rx\":%.0f,\"tx\":%.0f}", $1, $2, $3 }' "$f"
        printf ']}'
        ;;
    esac
    ;;
esac
KEDIRAY_EOF_21
cat > '/usr/share/rpcd/acl.d/aw1k-panel.json' <<'KEDIRAY_EOF_22'
{
    "aw1k-panel": {
        "description": "AW1K Panel veri kullanımı ve KediRay",
        "read": {
            "ubus": {
                "aw1k": [ "usage", "kediray", "kediray_ctl", "kediray_devices", "kediray_device", "wifi_clients", "guest_get", "guest_set", "wan_info", "bandpw_write" ]
            }
        },
        "write": {
            "ubus": {
                "aw1k": [ "kediray_ctl", "kediray_device", "guest_set", "bandpw_write" ]
            }
        }
    }
}
KEDIRAY_EOF_22
}
AW_OLD=$(md5sum /usr/libexec/rpcd/aw1k 2>/dev/null)
write_files
chmod 755 /usr/bin/aw1k-usage /usr/libexec/rpcd/aw1k 2>/dev/null
[ "$AW_OLD" != "$(md5sum /usr/libexec/rpcd/aw1k 2>/dev/null)" ] && AW_RESTART=1
chmod 755 /usr/bin/kediray /etc/init.d/kediray /etc/hotplug.d/iface/80-kediray /etc/hotplug.d/firewall/99-kediray
# Güncelleme rpcd/arka plan üzerinden çalışırsa umask 077 olabilir: web'in sunduğu dosyalar 403 verir. Okunur yap.
chmod 755 /www/luci-static/resources/view/kediray 2>/dev/null
chmod 644 /www/luci-static/resources/view/kediray/*.js /www/luci-static/kedi-logo.svg /usr/share/luci/menu.d/luci-app-kediray.json /usr/share/rpcd/acl.d/luci-app-kediray.json /usr/share/rpcd/acl.d/aw1k-panel.json 2>/dev/null
# Tarayıcı önbelleği: LuCI görünüm dosyalarını sürüm etiketli adla da yayınla ve menüyü ona yönlendir.
# (Aynı adlı .js dosyasını tarayıcı bir saat saklar; güncellemeden sonra eski sayfa görünüyordu. Yeni ad = yeni adres.)
KR_TAG=$(echo "$KR_VERSION" | tr . _)
KR_VD=/www/luci-static/resources/view/kediray
rm -f "$KR_VD"/*-r[0-9]*.js 2>/dev/null
for v in status trafik ayir settings log about; do
	[ -f "$KR_VD/$v.js" ] || continue
	cp "$KR_VD/$v.js" "$KR_VD/$v-r$KR_TAG.js" && \
		sed -i "s#\"path\": \"kediray/$v[^\"]*\"#\"path\": \"kediray/$v-r$KR_TAG\"#" /usr/share/luci/menu.d/luci-app-kediray.json
done
chmod 644 "$KR_VD"/*.js 2>/dev/null
chmod 755 /usr/share/kediray 2>/dev/null; chmod 644 /usr/share/kediray/*.uc 2>/dev/null
printf '%s\n' "$KR_VERSION" > /usr/share/kediray/version
if [ -f /etc/config/kediray ]; then
	ok "Mevcut ayarlar korundu (/etc/config/kediray)"
	rm -f /tmp/kediray.default
	# 1.4: bağlantı ayarları xDivine-Ray'in ölçülmüş varsayılanlarına döner (bir kez)
	cv=$(uci -q get kediray.main.cfgver); cv=${cv:-0}
	if [ "$cv" -lt 4 ] 2>/dev/null; then
		# 1.4: xDivine-Ray ile aynı bağlantı yolu (mixed) ve bildirim ayarları
		uci set kediray.main.capture="$CAPTURE"
		uci set kediray.main.ws_heartbeat=0
		uci set kediray.main.tcp_keepalive=0
		uci set kediray.main.block_quic=1
		[ "$(uci -q get kediray.main.dns_remote)" = "https://1.1.1.1/dns-query" ] && uci set kediray.main.dns_remote=tcp://1.1.1.1
		[ "$(uci -q get kediray.main.dns_port)" = 5353 ] && uci set kediray.main.dns_port=15353
		[ "$(uci -q get kediray.main.socks_port)" = 1080 ] && uci set kediray.main.socks_port=10808
	fi
	if [ "$cv" -lt 3 ] 2>/dev/null; then
		uci set kediray.main.mux=0
		uci set kediray.main.ws_early=0
		uci set kediray.main.dns_mode=private
		uci set kediray.main.sniff_override=0
		ci=$(uci -q get kediray.main.conn_idle)
		[ -z "$ci" ] || [ "$ci" -lt 14400 ] 2>/dev/null && uci set kediray.main.conn_idle=14400
		uci commit kediray
		ok "Bağlantı ayarları güncellendi (TCP mux kapalı, UDP/QUIC XUDP ile, DNS tünelden, hedef IP korunur)"
	fi
	if [ "$cv" -lt 4 ] 2>/dev/null; then
		uci set kediray.main.cfgver=4; uci commit kediray
		ok "Bağlantı yolu ayarlandı: $CAPTURE"
	fi
	# 1.5: Metin2 ışınlanma kopması - kanal portları tek aralık, Gameforge ağı ve komşu /24'ler direkt
	if [ "$cv" -lt 5 ] 2>/dev/null; then
		if [ "$(uci -q get kediray.metin2)" = app ]; then
			case "$(uci -q get kediray.metin2.ports)" in
				'11000-11999 13000-13999'|'') uci set kediray.metin2.ports='11000-13999' ;;
			esac
			[ -n "$(uci -q get kediray.metin2.expand)" ] || uci set kediray.metin2.expand=24
			for d in domain:gameforge.io domain:gameforge.net; do
				uci -q get kediray.metin2.domain | tr ' ' '\n' | grep -qx "$d" || uci add_list kediray.metin2.domain="$d"
			done
		fi
		uci set kediray.main.cfgver=5; uci commit kediray
		ok "Metin2: kanal portları 11000-13999, Gameforge ağı ve komşu sunucular direkt (ışınlanma kopması düzeltmesi)"
	fi
	# 1.6.2: direkt DNS için yedek (ilk DoH takılınca sorgu beklemesin)
	if [ "$cv" -lt 6 ] 2>/dev/null; then
		[ -n "$(uci -q get kediray.main.dns_direct2)" ] || uci set kediray.main.dns_direct2='https+local://8.8.8.8/dns-query'
		uci set kediray.main.cfgver=6; uci commit kediray
		ok "Direkt DNS için yedek sunucu eklendi (DoH takılınca sorgu 10 sn beklemiyor)"
	fi
	# 1.7: ping/sağlık ölçümü için yedek adres (biri engellenirse sunucu boşuna "düştü" sayılmasın)
	if [ "$cv" -lt 7 ] 2>/dev/null; then
		[ -n "$(uci -q get kediray.main.probe_url2)" ] || uci set kediray.main.probe_url2='https://cp.cloudflare.com/generate_204'
		uci set kediray.main.cfgver=7; uci commit kediray
		ok "Ölçüm adresine yedek eklendi (Cloudflare)"
	fi
	# 1.8: sayfa açılma gecikmesi düzeltmesi (ölçüldü: UDP girişinde sniffing oturum başına ~200 ms ekliyordu)
	if [ "$cv" -lt 8 ] 2>/dev/null; then
		[ -n "$(uci -q get kediray.main.dns_hijack)" ] || uci set kediray.main.dns_hijack=1
		uci set kediray.main.cfgver=8; uci commit kediray
		ok "DNS artık çekirdekte yönlendiriliyor; UDP girişinde içerik tanıma kapatıldı (sayfalar hızlanır)"
	fi
	# 1.9.1: DNS artık tünele bağımlı değil (tünel koparsa sayfa 50 sn dönüyordu)
	if [ "$cv" -lt 9 ] 2>/dev/null; then
		case "$(uci -q get kediray.main.dns_mode)" in private|"") uci set kediray.main.dns_mode=fast ;; esac
		uci set kediray.main.cfgver=9; uci commit kediray
		ok "DNS modu 'Direkt DoH' yapıldı: tünel bir an koparsa alan adları yine çözülür"
	fi
	# 1.10: direkt DNS artık operatörün kendi sunucusu (xDivine-Ray ile aynı).
	# Ölçüldü: bazı hatlarda DoH adreslerine hiç ulaşılamıyor ve her sorgu saniyelerce bekliyor.
	if [ "$cv" -lt 10 ] 2>/dev/null; then
		case "$(uci -q get kediray.main.dns_direct)" in
			https*|"") uci set kediray.main.dns_direct=auto ;;
		esac
		case "$(uci -q get kediray.main.dns_direct2)" in
			https*|"") uci set kediray.main.dns_direct2=auto ;;
		esac
		uci set kediray.main.cfgver=10; uci commit kediray
		ok "Direkt DNS: operatörün kendi sunucusu (DoH erişilemeyen hatlarda sayfa takılmaz)"
	fi
	# 1.12: DNS xDivine-Ray ile birebir aynı: dnsmasq -> çekirdek (15353) -> tünel, üst sunucu tcp://1.1.1.1.
	# 1.9.1'de 'fast'a (direkt DoH) geçmiştik; xDivine-Ray'de seçili olan mod bu değil, 'tünelden' olan.
	if [ "$cv" -lt 12 ] 2>/dev/null; then
		case "$(uci -q get kediray.main.dns_mode)" in fast|"") uci set kediray.main.dns_mode=private ;; esac
		case "$(uci -q get kediray.main.dns_remote)" in ""|https*) uci set kediray.main.dns_remote='tcp://1.1.1.1' ;; esac
		[ -n "$(uci -q get kediray.main.dns_hijack)" ] || uci set kediray.main.dns_hijack=1
		uci set kediray.main.cfgver=12; uci commit kediray
		ok "DNS modu: 'Tünelden' (dnsmasq -> çekirdek -> tünel)"
	fi
	# 1.13: tarayıcının kendi "Güvenli DNS"i (DoH) sistem DNS'ini atlıyor; bu hatta o adreslere
	# ulaşılamadığı için sayfa başına 1-3 istek ~50 sn askıda kalıyordu. Reddedilince tarayıcı anında geri döner.
	if [ "$cv" -lt 13 ] 2>/dev/null; then
		[ -n "$(uci -q get kediray.main.block_doh)" ] || uci set kediray.main.block_doh=1
		uci set kediray.main.cfgver=13; uci commit kediray
		ok "Tarayıcıların kendi DoH'u engellendi (askıda kalan istekler biter)"
	fi
	# 1.14: uzak DNS artık DoH. Gerçek hatta doğrulandı: DNS-over-TCP kullanılırken tünelde tek bir
	# bağlantı düşünce sorgu ölüyor ve sayfalar askıda kalıyordu; DoH'a geçince sorun bitti.
	if [ "$cv" -lt 14 ] 2>/dev/null; then
		case "$(uci -q get kediray.main.dns_remote)" in
			tcp://*|""|1.1.1.1|8.8.8.8) uci set kediray.main.dns_remote='https://1.1.1.1/dns-query' ;;
		esac
		uci set kediray.main.cfgver=14; uci commit kediray
		ok "Uzak DNS: Cloudflare DoH (tünelde bağlantı düşse de sorgu ölmez)"
	fi
	# 1.11: mobil hatta düşen SYN yüzünden istekler 50 sn askıda kalıyordu
	if [ "$cv" -lt 11 ] 2>/dev/null; then
		[ -n "$(uci -q get kediray.main.mobile_tune)" ] || uci set kediray.main.mobile_tune=1
		uci set kediray.main.cfgver=11; uci commit kediray
		ok "Mobil hat ayarı açıldı: takılan bağlantı 50 sn yerine ~15 sn'de bırakılır"
	fi
	# 1.19.3: "Direkt" seçilen cihaz/uygulama her durumda direkt çıksın (otomatik VPN'e çevirme bir kez kapatılır; panelden açılabilir)
	if [ ! -f /etc/kediray.autodirect-off ]; then
		uci set kediray.main.auto_direct=0; uci commit kediray
		touch /etc/kediray.autodirect-off
		ok "Direkt seçilenler artık hiçbir zaman VPN'e çevrilmez (panel: Cihazlar > kutucuk)"
	fi
	# 1.19.19: bildirimler (FCM/APNs) tünelden gitsin: direkt giden bağlantıyı operatör NAT'ı sessizce kesiyordu (bir kez; panelden açılabilir)
	if [ ! -f /etc/kediray.pushfix0 ]; then
		uci set kediray.main.push_fix=0; uci commit kediray
		touch /etc/kediray.pushfix0
		ok "Bildirimler artık tünelden gidiyor (xDivine-Ray gibi): operatör NAT'ı direkt bağlantıyı sessizce kesip bildirimleri geciktiriyordu"
	fi
	# 1.19.4: boşta kalan WebSocket tünelinin kesilip bildirimlerin gelmemesi: heartbeat + keepalive 30 sn (bir kez)
	if [ ! -f /etc/kediray.keepalive30 ]; then
		[ "$(uci -q get kediray.main.ws_heartbeat)" = 0 ] && uci set kediray.main.ws_heartbeat=30
		[ "$(uci -q get kediray.main.tcp_keepalive)" = 0 ] && uci set kediray.main.tcp_keepalive=30
		uci commit kediray
		touch /etc/kediray.keepalive30
		ok "WebSocket heartbeat ve TCP keepalive 30 sn (boştaki tünel kesilmesin, bildirimler gelsin)"
	fi
	# Seçili mod bu cihazda yoksa desteklenene geç
	case "$(uci -q get kediray.main.capture)" in
		mixed|tun) [ "$MIXED_OK" = 1 ] || { uci set kediray.main.capture="$CAPTURE"; uci commit kediray; } ;;
		tproxy) [ "$TPROXY_OK" = 1 ] || { uci set kediray.main.capture="$CAPTURE"; uci commit kediray; } ;;
	esac
	# Yeni sürümde eklenen Metin2 sunucu IP'lerini mevcut ayara da ekle
	if [ "$(uci -q get kediray.metin2)" = app ]; then
		added=0
		for ip in 79.110.80.0/20 79.110.87.192/32 79.110.92.148/32 79.110.90.244/32 79.110.90.99/32 79.110.91.96/32 79.110.91.98/32 79.110.92.117/32 79.110.92.96/32 79.110.92.97/32 79.110.92.98/32; do
			uci -q get kediray.metin2.ip | tr ' ' '\n' | grep -qx "$ip" && continue
			uci add_list kediray.metin2.ip="$ip"; added=$((added + 1))
		done
		[ $added -gt 0 ] && { uci commit kediray; ok "Metin2 listesine $added IP eklendi"; }
	fi
else
	mv /tmp/kediray.default /etc/config/kediray
	FRESH_CONF=1
	uci set kediray.main.capture="$CAPTURE"; uci commit kediray
	ok "Varsayılan ayarlar yazıldı (yakalama: $CAPTURE)"
fi
rm -rf /var/etc/kediray/core.ver
ok "Dosyalar hazır"

# Çalışan başka servislerle port çakışması olmasın: dolu portları atla
port_used() {
	local hex f
	hex=$(printf ':%04X' "$1")
	for f in /proc/net/tcp /proc/net/tcp6 /proc/net/udp /proc/net/udp6; do
		[ -r "$f" ] || continue
		awk -v p="$hex" 'FNR > 1 && substr($2, length($2) - 4) == p { f = 1 } END { exit !f }' "$f" && return 0
	done
	return 1
}
range_used() { # başlangıç adet
	local i=0
	while [ $i -lt "$2" ]; do port_used $(($1 + i)) && return 0; i=$((i + 1)); done
	return 1
}
TAKEN=""
for pair in tproxy_port:12345 dns_port:5353 socks_port:1080 api_port:10085; do
	opt=${pair%%:*}; def=${pair#*:}
	cur=$(uci -q get "kediray.main.$opt"); cur=${cur:-$def}
	p=$cur
	while port_used "$p" || echo " $TAKEN " | grep -q " $p "; do p=$((p + 1)); done
	TAKEN="$TAKEN $p"
	if [ "$p" != "$cur" ]; then uci set "kediray.main.$opt=$p"; ok "$opt: $cur dolu, $p seçildi"; fi
done
tb=$(uci -q get kediray.main.test_base); tb=${tb:-21000}
while range_used $((tb + 1)) 64; do tb=$((tb + 100)); done
[ "$tb" != 21000 ] && uci set kediray.main.test_base="$tb"
[ "$KEEP_OTHER" = 1 ] && uci set kediray.main.enabled=0
uci commit kediray
ok "Portlar: TPROXY $(uci -q get kediray.main.tproxy_port) · DNS $(uci -q get kediray.main.dns_port) · SOCKS $(uci -q get kediray.main.socks_port) · API $(uci -q get kediray.main.api_port)"

# ---------------------------------------------------------------- 5. Xray çekirdeği
step "Xray çekirdeği"
CORE_BIN=$(/usr/bin/kediray corebin 2>/dev/null)
CORE_CUR=""
[ -n "$CORE_BIN" ] && [ -x "$CORE_BIN" ] && CORE_CUR=$("$CORE_BIN" version 2>/dev/null | head -n1)
CORE_ASSET=$(/usr/bin/kediray assetdir 2>/dev/null)
core_ok=0
if [ "$FORCE_CORE" != 1 ] && [ -n "$CORE_CUR" ] && [ -n "$CORE_ASSET" ]; then
	# istenen sürüm zaten kuruluysa (ya da "latest" istendiyse) indirme yapma
	if [ "$CORE_VER" = latest ]; then core_ok=1
	else case "$CORE_CUR" in *"${CORE_VER#v}"*) core_ok=1 ;; esac; fi
fi
if [ "$core_ok" = 1 ]; then
	ok "zaten kurulu, indirme atlandı: $CORE_CUR"
	ok "coğrafi veriler: $CORE_ASSET  (güncellemek için: kediray update-geo)"
elif /usr/bin/kediray update-core "$CORE_VER"; then
	ok "Xray kuruldu"
else
	warn "GitHub'dan indirilemedi, paket deposu deneniyor"
	if [ -n "$CORE_CUR" ]; then
		ok "mevcut çekirdek korundu: $CORE_CUR"
	else
		pkg_add xray-core && ok "xray-core (paket)" || die "Xray kurulamadı. İnternet/GitHub erişimini kontrol et ya da --gh-proxy kullan."
	fi
	[ -n "$CORE_ASSET" ] || pkg_add v2ray-geoip v2ray-geosite >/dev/null 2>&1 || warn "geoip/geosite paketi kurulamadı: kediray update-geo"
fi

# Coğrafi veri (geoip/geosite): kurallar geosite:whatsapp gibi kayıtları kullanır, dosya yoksa Xray hiç başlamaz.
# Sırayla: GitHub'dan indir -> paket deposu -> sistemde zaten olan (xDivine-Ray vb.) dosyaları bağla.
geo_have() { local d; d=$(/usr/bin/kediray assetdir 2>/dev/null); [ -s "$d/geoip.dat" ] && [ -s "$d/geosite.dat" ]; }
if ! geo_have; then
	warn "geoip/geosite eksik, tamamlanıyor"
	mkdir -p /usr/share/kediray
	/usr/bin/kediray update-geo >/dev/null 2>&1 || true
	geo_have || { pkg_add v2ray-geoip v2ray-geosite >/dev/null 2>&1 || true; }
	if ! geo_have; then
		GSRC=$(find /usr /opt /etc -type f -name geosite.dat -size +1k 2>/dev/null | head -n1)
		if [ -n "$GSRC" ] && [ -s "$(dirname "$GSRC")/geoip.dat" ]; then
			ln -sf "$GSRC" /usr/share/kediray/geosite.dat
			ln -sf "$(dirname "$GSRC")/geoip.dat" /usr/share/kediray/geoip.dat
			ok "mevcut coğrafi veri bağlandı: $(dirname "$GSRC")"
		fi
	fi
	geo_have && ok "geoip/geosite hazır" || warn "geoip/geosite bulunamadı: Xray başlamayabilir. Elle: kediray update-geo"
fi

# ---------------------------------------------------------------- 6. tercihler
step "Tercihler"
# 1.19.11: Güncellemede (mevcut ayar dosyası varsa) uygulamaların VPN/Direkt seçimine DOKUNULMAZ.
# Eskiden -y ile (panelden güncelleme) Metin2 ve Teams her seferinde varsayılan "Direkt"e dönüyordu.
choose_route() { # uygulama soru varsayılan argüman
	local v="$4" cur
	[ "$(uci -q get "kediray.$1")" = app ] || return 0
	cur=$(uci -q get "kediray.$1.route")
	if [ -z "$v" ] && [ "${FRESH_CONF:-0}" != 1 ] && [ -n "$cur" ]; then
		ok "$(uci -q get "kediray.$1.name"): mevcut seçim korundu ($([ "$cur" = vpn ] && echo VPN || echo Direkt))"
		return 0
	fi
	if [ -z "$v" ]; then
		echo
		echo "  $2"
		echo "    1) Direkt (bypass) — en düşük ping, VPN yeniden başlasa bile kopmaz"
		echo "    2) VPN üzerinden"
		ask "Seçimin (1/2)" "$3"
		case "$REPLY" in 2|v|V|vpn|VPN) v=vpn ;; *) v=direct ;; esac
	fi
	uci set "kediray.$1.route=$v"
	ok "$(uci -q get "kediray.$1.name"): $([ "$v" = vpn ] && echo VPN || echo Direkt)"
}
choose_route metin2 "Metin2 nasıl bağlansın?" 1 "$ARG_METIN2"
choose_route teams "Microsoft Teams (sesli/görüntülü görüşme) nasıl bağlansın?" 1 "$ARG_TEAMS"
if [ "$(uci -q get kediray.whatsapp)" = app ] && { [ "${FRESH_CONF:-0}" = 1 ] || [ -z "$(uci -q get kediray.whatsapp.route)" ]; }; then
	uci set kediray.whatsapp.route=vpn
	ok "WhatsApp: VPN"
fi
uci commit kediray

[ "$IMPORT_XWRT" = 1 ] && /usr/bin/kediray import-xwrt

if [ -n "$ARG_SUB" ]; then
	uci add_list kediray.main.sub_url="$ARG_SUB"; uci commit kediray
elif [ "$AUTO" != 1 ] && [ -z "$(uci -q get kediray.main.sub_url)" ]; then
	echo
	ask "Abonelik adresi (x-ui/3x-ui; yoksa boş bırak)" ""
	[ -n "$REPLY" ] && { uci add_list kediray.main.sub_url="$REPLY"; uci commit kediray; }
fi
[ -n "$(uci -q get kediray.main.sub_url)" ] && /usr/bin/kediray sub

if [ -n "$ARG_LINK" ]; then
	/usr/bin/kediray add "$ARG_LINK"
elif [ "$AUTO" != 1 ] && [ -z "$(uci show kediray 2>/dev/null | grep '=node$')" ]; then
	echo
	echo "  Sunucu linki yapıştır (vless://, vmess://, trojan://, ss://). Boş bırakırsan panelden eklersin."
	echo "  (JSON eklemek için panelde 'Link / JSON ekle' butonunu kullan.)"
	ask "Link" ""
	[ -n "$REPLY" ] && /usr/bin/kediray add "$REPLY"
fi

# ---------------------------------------------------------------- 7. servis
step "Servis ve arayüz etkinleştiriliyor"
touch /etc/crontabs/root
sed -i '/kediray watchdog/d' /etc/crontabs/root
echo '* * * * * /usr/bin/kediray watchdog >/dev/null 2>&1' >> /etc/crontabs/root
sed -i '/kediray update auto/d' /etc/crontabs/root
echo '0 1 * * * /usr/bin/kediray update auto >/dev/null 2>&1' >> /etc/crontabs/root
grep -q '/usr/bin/aw1k-usage' /etc/crontabs/root || echo '*/2 * * * * /usr/bin/aw1k-usage >/dev/null 2>&1' >> /etc/crontabs/root
/etc/init.d/cron enable >/dev/null 2>&1
# crond crontab değişikliğini kendisi okur; çalışıyorsa YENİDEN BAŞLATMA: gece otomatik güncelleme cron'dan başladığında
# restart, kurulumu yarıda öldürüyordu (menü yolu/servis adımları atlanıyor, VPN bir dakika kapalı kalıyordu)
/etc/init.d/cron running >/dev/null 2>&1 || /etc/init.d/cron start >/dev/null 2>&1
/usr/bin/aw1k-usage >/dev/null 2>&1
ok "Watchdog (dakikalık kontrol + abonelik güncelleme)"
case "$(uci -q get kediray.main.capture)" in
	mixed|tun) /usr/bin/kediray fw-zone && ok "Güvenlik duvarı bölgesi (kediray0 TUN) hazır" ;;
esac

# Eski menü kayıtlarını temizle (KediRay artık VPN menüsünde) ve LuCI önbelleğini sıfırla
for f in /usr/share/luci/menu.d/*.json; do
	[ "$f" = /usr/share/luci/menu.d/luci-app-kediray.json ] && continue
	grep -q '"admin/services/kediray' "$f" 2>/dev/null && rm -f "$f"
done
sed -i 's#admin/services/kediray#admin/vpn/kediray#g' /usr/share/luci/menu.d/luci-app-kediray.json
rm -f /tmp/luci-indexcache* 2>/dev/null; rm -rf /tmp/luci-modulecache 2>/dev/null
if [ "$AW_RESTART" = 1 ]; then /etc/init.d/rpcd restart >/dev/null 2>&1; else /etc/init.d/rpcd reload >/dev/null 2>&1; fi   # eklenti ilk kez/değişerek geldiyse restart gerekir; aksi halde reload (restart oturumları düşürür)
ok "LuCI menüsü: VPN → KediRay VPN (görmezsen LuCI’den çıkış yapıp tekrar gir)"

rm -f /etc/rc.d/S??kediray /etc/rc.d/K??kediray 2>/dev/null   # eski sıra numarası (S99) kalmasın
/etc/init.d/kediray enable >/dev/null 2>&1
/usr/bin/kediray fixboot -v 2>/dev/null
STILL=$(/usr/bin/kediray conflicts)
if [ -n "$STILL" ] && [ "$WAS_ON" != 1 ]; then
	uci set kediray.main.enabled=0; uci commit kediray
	ok "KediRay kuruldu ve kapalı bekliyor ($STILL çalışmaya devam ediyor, internetin kesilmedi)"
	if uci show kediray 2>/dev/null | grep -q '=node$'; then
		echo "  Geçmeye hazır olunca:  kediray takeover   (ya da panelde 'Güvenli geçiş')"
		echo "  İnternet gelmezse otomatik olarak $STILL'e geri döner."
	else
		echo "  Önce panelden sunucu ekle, sonra 'Güvenli geçiş' butonuna bas."
	fi
elif [ "$PREV_CONF" = 1 ] && [ "$PREV_ENABLED" != 1 ]; then
	ok "KediRay güncellendi; VPN daha önce kapalıydı, kapalı bırakıldı (açmak için Ayarlar → VPN açık)"
elif uci show kediray 2>/dev/null | grep -q '=node$'; then
	uci set kediray.main.enabled=1; uci commit kediray
	# procd servis kayıtlı değilken zararsız bir "Command failed: Not found" yazar; süz
	/etc/init.d/kediray restart 2>&1 | grep -v '^Command failed: Not found$'
	sleep 4
	if /usr/bin/kediray status --json | grep -q '"running": *true'; then
		ok "VPN çalışıyor"
		/usr/bin/kediray ping all >/dev/null 2>&1
		/usr/bin/kediray check
	else
		warn "VPN başlamadı. Ayrıntı: kediray log"
	fi
else
	warn "Henüz sunucu yok; panelden ekleyince 'Başlat'a bas."
fi

LANIP=$(uci -q get network.lan.ipaddr | cut -d/ -f1)
printf "\n${C_G}KediRay %s kuruldu.${C_0}\n" "$KR_VERSION"
echo "  Panel : http://${LANIP:-192.168.1.1}/cgi-bin/luci/admin/vpn/kediray"
echo "  Komut : kediray help"
echo
