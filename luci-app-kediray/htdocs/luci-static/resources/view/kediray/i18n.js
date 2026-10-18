'use strict';
'require baseclass';

/* KediRay - dil desteği (Türkçe · English · Français)
 *
 * Panelin kaynak metinleri Türkçedir. Bu modül seçilen dile göre sayfadaki metinleri (düz metin, title/placeholder/aria-label,
 * düğme değerleri, confirm/alert penceresi) sözlükten çevirir; sayfa sonradan değişirse (canlı güncelleme, açılan pencere) yeniden çevirir.
 * Seçim tarayıcıda saklanır ('kediray-lang'); değiştirince sayfa yenilenir. Sözlükte olmayan metin Türkçe kalır.
 * Sağ üstteki TR | EN | FR seçici sayfa başlığının sağına konur.
 *
 * Yeni metin eklerken: kaynağı Türkçe yaz, çevirisini aşağıdaki DICT'e [İngilizce, Fransızca] olarak ekle.
 */

const LS = 'kediray-lang';
const LANGS = [ [ 'tr', 'TR', 'Türkçe' ], [ 'en', 'EN', 'English' ], [ 'fr', 'FR', 'Français' ] ];

function curLang() {
	try { const l = localStorage.getItem(LS); if (l === 'en' || l === 'fr' || l === 'tr') return l; } catch (e) { }
	return 'tr';
}
const LANG = curLang();
const LI = LANG === 'fr' ? 1 : 0;

const DICT = {
	"(zaman aşımı: ölçüm hâlâ sürüyor olabilir; `kediray dnstest --read` ile bak)": ["(timed out: the measurement may still be running; check with `kediray dnstest --read`)", "(délai dépassé : la mesure est peut-être encore en cours ; vérifiez avec `kediray dnstest --read`)"],
	"  (tünel ": ["  (tunnel ", "  (tunnel "],
	" (GitHub'a ulaşılamadı, son kayıtlı değer)": [" (could not reach GitHub, last saved value)", " (GitHub injoignable, dernière valeur enregistrée)"],
	" (değiştirmek için tıkla)": [" (click to change)", " (cliquer pour changer)"],
	" (lisans anahtarı bu IMEI numarasına göre üretilir; tek hanesi değişirse geçersiz olur)": [" (the license key is generated for this IMEI; if even one digit changes, it becomes invalid)", " (la clé de licence est générée pour cet IMEI ; si un seul chiffre change, elle devient invalide)"],
	" DNS (Xray üzerinden)": [" DNS (via Xray)", " DNS (via Xray)"],
	" EOF hatalarını gizle": [" Hide EOF errors", " Masquer les erreurs EOF"],
	" Göster": [" Show", " Afficher"],
	" IP bloğu": [" IP block", " bloc d'IP"],
	" VPN tüneli": [" VPN tunnel", " tunnel VPN"],
	" alan adı": [" domain", " domaine"],
	" bant sırayla denenecek (yaklaşık ": [" bands will be tried in turn (about ", " bandes seront testées l'une après l'autre (environ "],
	" bağlı)": [" connected)", " connecté(s))"],
	" başlatılsın mı?": [" — start it?", " — le démarrer ?"],
	" başlatılır. İnternet birkaç saniye kesilebilir.": [" started. The internet may drop for a few seconds.", " démarré. Internet peut être coupé quelques secondes."],
	" başlatılıyor…": [" starting…", " démarrage…"],
	" deneme 3 sn üstünde kaldı: aşağıda hangi aşamanın beklediği yazıyor.": [" attempts took over 3 s: the stage that waited is shown below.", " essais ont dépassé 3 s : l'étape qui a attendu est indiquée ci-dessous."],
	" deneme DNS aşamasında düştü. Ayarlar → DNS bölümünden mod değiştirip tekrar ölçelim.": [" attempts failed at the DNS stage. Change the mode under Settings → DNS and measure again.", " essais ont échoué à l'étape DNS. Changez de mode dans Paramètres → DNS et mesurons à nouveau."],
	" direkt listeye eklendi. Oyunu yeniden başlatmadan denemek için önce oyundan çık.": [" was added to the direct list. To try it without restarting the game, quit the game first.", " a été ajouté à la liste directe. Pour essayer sans redémarrer le jeu, quittez d'abord le jeu."],
	" dk). Her denemede internet kısa süre kesilir. ": [" min). The internet drops briefly on each attempt. ", " min). Internet est brièvement coupé à chaque essai. "],
	" durdurulup KediRay başlatılacak.": [" will be stopped and KediRay will be started.", " sera arrêté et KediRay sera démarré."],
	"İnternet gelmezse otomatik olarak ": ["If there is no internet, ", "Si Internet ne revient pas, "],
	" durdurulur. Başka bir motor çalışmıyorsa internet VPN'siz (kendi hattınla) devam eder.": [" is stopped. If no other engine is running, the internet continues without VPN (on your own line).", " est arrêté. Si aucun autre moteur ne tourne, Internet continue sans VPN (sur votre propre ligne)."],
	" geri açılır.": [" is turned back on automatically.", " est réactivé automatiquement."],
	"Devam edilsin mi?": ["Continue?", "Continuer ?"],
	" ms): Ayarlar → DNS → \"Hızlı\" modunu kullan.": [" ms): Settings → DNS → use \"Fast\" mode.", " ms) : Paramètres → DNS → utilisez le mode « Rapide »."],
	" sn kaldı": [" s left", " s restantes"],
	" uyarı": [" warnings", " avertissements"],
	" · Açık: ": [" · Up: ", " · Actif : "],
	" · Direkt çıkış yok: \"direkt\" uygulamalar da VPN'den çıkıyor": [" · No direct exit: \"direct\" apps also go out through the VPN", " · Pas de sortie directe : les applis « directes » passent aussi par le VPN"],
	" · Yükleme %": [" · Upload %", " · Envoi %"],
	" çalışıyor. ": [" is running. ", " est en cours d'exécution. "],
	" — başlatılamadı": [" — could not start", " — impossible de démarrer"],
	" — kapalı: seçtiğin sunucuda kalır, hiç geçiş yapılmaz": [" — off: stays on the chosen server, never switches", " — désactivé : reste sur le serveur choisi, ne change jamais"],
	" — seçili sunucuda kalır, sadece o düşerse diğerine geçer (oyunda IP değişmez)": [" — stays on the chosen server, switches to another only if it goes down (IP does not change in games)", " — reste sur le serveur choisi, ne bascule que s'il tombe (l'IP ne change pas en jeu)"],
	" — çıkış IP: ": [" — exit IP: ", " — IP de sortie : "],
	"\"Tünelden\": sorgular tünel içinden gider, operatöre sızmaz; hızlıdır, TUN modunda tek çalışan seçenektir. \"Direkt\": tünele girmez, tünel kopsa da çalışır; ziyaret ettiğin siteler operatörün DNS'ine görünür. \"DNS'e dokunma\": KediRay ad çözümlemeye karışmaz; TUN modunda ad çözülemediği için otomatik \"Tünelden\"e döner. Yalnız sorun gidermek için.": ["\"Via tunnel\": queries go through the tunnel and don't leak to the operator; fast, and the only working option in TUN mode. \"Direct\": doesn't enter the tunnel and works even if the tunnel drops; the sites you visit are visible to the operator's DNS. \"Don't touch DNS\": KediRay stays out of name resolution; in TUN mode it automatically falls back to \"Via tunnel\" because names can't be resolved. For troubleshooting only.", "« Via le tunnel » : les requêtes passent par le tunnel et ne fuient pas vers l'opérateur ; rapide, et seule option fonctionnelle en mode TUN. « Direct » : n'entre pas dans le tunnel et fonctionne même si le tunnel tombe ; les sites visités sont visibles du DNS de l'opérateur. « Ne pas toucher au DNS » : KediRay n'intervient pas dans la résolution de noms ; en mode TUN il revient automatiquement à « Via le tunnel » car les noms ne peuvent pas être résolus. Uniquement pour le dépannage."],
	"' (metinler çift tırnak içinde olmalı)": ["(strings must be in double quotes)", "(les textes doivent être entre guillemets doubles)"],
	"',' veya '}' bekleniyordu (önceki satırın sonunda virgül eksik olabilir)": ["',' or '}' expected (a comma may be missing at the end of the previous line)", "',' ou '}' attendu (il manque peut-être une virgule à la fin de la ligne précédente)"],
	"']' kapanmamış (metin erken bitti)": ["']' not closed (text ended early)", "']' non fermé (texte terminé trop tôt)"],
	"'i durdurur, artıklarını temizler ve KediRay'i başlatır. İnternet gelmezse otomatik geri alır.": ["stops it, cleans up leftovers and starts KediRay. If the internet doesn't come back, it is reverted automatically.", "l'arrête, nettoie les restes et démarre KediRay. Si Internet ne revient pas, il revient automatiquement en arrière."],
	"'}' kapanmamış (metin erken bitti)": ["'}' not closed (text ended early)", "'}' non fermé (texte terminé trop tôt)"],
	"(adsız)": ["(unnamed)", "(sans nom)"],
	"). Ayrıntılı çıktıya bak.": ["). See the detailed output.", "). Voir la sortie détaillée."],
	", sütun ": [", column ", ", colonne "],
	". Denetlenmedi; kontrol etmek için \"✓ Ayarları denetle\"ye bas.": [". Not checked; press \"✓ Check settings\" to verify.", ". Non vérifié ; appuyez sur « ✓ Vérifier les réglages » pour contrôler."],
	"30 gün": ["30 days", "30 jours"],
	"7 gün": ["7 days", "7 jours"],
	"Abonelikler güncelleniyor…": ["Updating subscriptions…", "Mise à jour des abonnements…"],
	"Abonelikte ech yoksa boş kalır": ["Stays empty if the subscription has no ech", "Reste vide si l'abonnement n'a pas d'ech"],
	"Adres (IP ya da alan adı)": ["Address (IP or domain)", "Adresse (IP ou domaine)"],
	"Adreste alan adı olsa bile bir kez IP'ye çevrilir ve doğrudan IP'ye bağlanılır; alan adı SNI/Host olarak kalır. DNS sorunlarından etkilenmez.": ["Even if the address is a domain, it is resolved to an IP once and connected to directly by IP; the domain stays as SNI/Host. Unaffected by DNS problems.", "Même si l'adresse est un domaine, il est résolu une fois en IP et la connexion se fait directement par IP ; le domaine reste en SNI/Host. Insensible aux problèmes de DNS."],
	"Aktarım": ["Transport", "Transport"],
	"Aktif bağlantılar — ": ["Active connections — ", "Connexions actives — "],
	"Akıllı band seçimi": ["Smart band selection", "Sélection intelligente de bande"],
	"Akış": ["Stream", "Flux"],
	"Akışı temizle": ["Clear stream", "Vider le flux"],
	"Alan adları (satır ya da virgülle): example.com, domain:foo.net, geosite:youtube": ["Domains (one per line or comma-separated): example.com, domain:foo.net, geosite:youtube", "Domaines (un par ligne ou séparés par des virgules) : example.com, domain:foo.net, geosite:youtube"],
	"Alan adlarını tünel DNS'iyle çöz (DNS'i bozulan uygulamalar için)": ["Resolve domains via the tunnel DNS (for apps whose DNS breaks)", "Résoudre les domaines via le DNS du tunnel (pour les applis dont le DNS pose problème)"],
	"Alan adı bul": ["Find domains", "Trouver des domaines"],
	"Alan adı bul…": ["Find domains…", "Trouver des domaines…"],
	"Alan adı yönlendirme (hız / uyumluluk)": ["Domain routing (speed / compatibility)", "Routage des domaines (vitesse / compatibilité)"],
	"Alan adını VPN sunucusu çözsün": ["Let the VPN server resolve the domain", "Laisser le serveur VPN résoudre le domaine"],
	"Anahtar çift tırnak (\") içinde olmalı": ["The key must be in double quotes (\")", "La clé doit être entre guillemets doubles (\")"],
	"Anahtarlar tek tırnakla değil çift tırnakla (\") yazılmalı": ["Keys must be written with double quotes, not single quotes (\")", "Les clés doivent être écrites avec des guillemets doubles, pas simples (\")"],
	"Aranıyor…": ["Searching…", "Recherche…"],
	"Ayar dosyası okunamadı": ["Could not read the config file", "Impossible de lire le fichier de configuration"],
	"Aylık": ["Monthly", "Mensuel"],
	"Aylık ortalama (": ["Monthly average (", "Moyenne mensuelle ("],
	"Aynı anda yalnızca biri çalışır: birini başlatınca çalışan diğeri durdurulur ve açılışta da seçtiğin motor çalışır. KediRay'de internet gelmezse otomatik geri alınır.": ["Only one runs at a time: starting one stops the other, and the engine you choose also runs at boot. With KediRay, it reverts automatically if the internet doesn't come back.", "Un seul fonctionne à la fois : en démarrer un arrête l'autre, et le moteur choisi démarre aussi au boot. Avec KediRay, retour arrière automatique si Internet ne revient pas."],
	"Aynı sürümde (": ["There are new changes in the repository for the same version (", "Il y a de nouvelles modifications dans le dépôt pour la même version ("],
	"Ayrıntılı çıktı": ["Detailed output", "Sortie détaillée"],
	"Ayıklama": ["Debug", "Débogage"],
	"Aç": ["Enable", "Activer"],
	"Aç: Bu uygulama kuralını yeniden etkinleştirir.": ["Enable: Re-enables this app rule.", "Activer : réactive cette règle d'application."],
	"Açık": ["On", "Activé"],
	"Açıkken büyük indirmeler (WhatsApp foto/video) yol MTU'suna uydurulur. Hücresel hatta indirmeler takılıyorsa açık kalsın. Değiştirince kurallar yenilenir.": ["When on, large downloads (WhatsApp photos/videos) are fitted to the path MTU. Leave it on if downloads stall on a cellular line. Changing it refreshes the rules.", "Activé, les gros téléchargements (photos/vidéos WhatsApp) sont adaptés au MTU du chemin. Laissez-le activé si les téléchargements se bloquent sur une ligne cellulaire. Le modifier actualise les règles."],
	"Aşağı taşı": ["Move down", "Descendre"],
	"Aşağıdaki akıştan daha uzun süre saklanır; aynı hata tekrarlanırsa tek kartta sayılır. Her kartta çıktı ve ne yapılması gerektiği vardır.": ["Kept longer than the stream below; the same error repeated is counted on a single card. Each card has the output and what to do.", "Conservé plus longtemps que le flux ci-dessous ; une même erreur répétée est comptée sur une seule carte. Chaque carte contient la sortie et la marche à suivre."],
	"BAĞLI": ["CONNECTED", "CONNECTÉ"],
	"Bana bir kahve ısmarla": ["Buy me a coffee", "Offrez-moi un café"],
	"Bant bilgisi alınamadı: ": ["Could not get band info: ", "Impossible d'obtenir les infos de bande : "],
	"Bant kilidini kaldır": ["Remove band lock", "Retirer le verrouillage de bande"],
	"Bazı IP'ler bağlantıyı düşürüyor, bazıları sağlam. Ayarlar → Genel → \"Sunucuya IP ile bağlan\" seçeneğini kapat: her bağlantıda çalışan IP denenir.": ["Some IPs drop the connection, others are solid. Turn off Settings → General → \"Connect to the server by IP\": a working IP is tried on every connection.", "Certaines IP coupent la connexion, d'autres sont fiables. Désactivez Paramètres → Général → « Se connecter au serveur par IP » : une IP fonctionnelle est testée à chaque connexion."],
	"Bağlan": ["Connect", "Connecter"],
	"Bağlantı": ["Connection", "Connexion"],
	"Bağlantı test ediliyor…": ["Testing connection…", "Test de la connexion…"],
	"Bağlantı teşhisi": ["Connection diagnosis", "Diagnostic de connexion"],
	"Bağlantılar": ["Connections", "Connexions"],
	"Bağlantılar okunuyor…": ["Reading connections…", "Lecture des connexions…"],
	"Bağlantıyı kes": ["Disconnect", "Déconnecter"],
	"Bağlı sunucu": ["Connected server", "Serveur connecté"],
	"Bağlı süre": ["Uptime", "Durée de connexion"],
	"Bağışlarınız için teşekkürler, bu iş için harcanan emek için ufak bir hediye.": ["Thank you for your donations — a small gift for the effort put into this work.", "Merci pour vos dons — un petit cadeau pour le travail investi dans ce projet."],
	"Başlat": ["Start", "Démarrer"],
	"Başlatılamadı": ["Could not start", "Démarrage impossible"],
	"Başlatılıyor…": ["Starting…", "Démarrage…"],
	"Beklenmedik son: değer bekleniyordu": ["Unexpected end: a value was expected", "Fin inattendue : une valeur était attendue"],
	"Bildirimleri direkt gönder": ["Send notifications directly", "Envoyer les notifications en direct"],
	"Bileşen": ["Component", "Composant"],
	"Bir ad yaz (örn. discord.com): yönlendirici çözer, ilgili ve alt alan adlarını listeler, seçtiklerin bu uygulamaya eklenir. Uygulamanın bazı adresleri kurala girmiyorsa kullan.": ["Type a name (e.g. discord.com): the router resolves it, lists related and subdomains, and what you tick is added to this app. Use it if some of the app's addresses don't match the rule.", "Saisissez un nom (ex. discord.com) : le routeur le résout, liste les domaines liés et sous-domaines, et ce que vous cochez est ajouté à cette appli. À utiliser si certaines adresses de l'appli ne correspondent pas à la règle."],
	"Bir band taraması zaten sürüyor.": ["A band scan is already running.", "Un balayage de bandes est déjà en cours."],
	"Bir sayfanın açılması: DNS (adres çözme) → bağlantı → TLS → ilk bayt. Hangi aşamada beklendiği aşağıda. DNS süresi ikisinde de aynıdır: o modemin kendi DNS yolu.": ["Opening a page: DNS (name resolution) → connection → TLS → first byte. The stage where it waited is shown below. DNS time is the same in both: it is the modem's own DNS path.", "Ouverture d'une page : DNS (résolution de nom) → connexion → TLS → premier octet. L'étape où l'attente a eu lieu est indiquée ci-dessous. Le temps DNS est identique dans les deux : c'est le chemin DNS propre du modem."],
	"Birincisi yanıt vermezse bu denenir; ikisi de yanıt vermezse sunucu düşmüş sayılır. Boş = yedek yok.": ["This one is tried if the first doesn't respond; if neither responds, the server is considered down. Empty = no backup.", "Celui-ci est essayé si le premier ne répond pas ; si aucun ne répond, le serveur est considéré comme en panne. Vide = pas de secours."],
	"Bitince eski band kilidi geri yüklenir. ": ["When it finishes, the previous band lock is restored. ", "À la fin, l'ancien verrouillage de bande est rétabli. "],
	"Boş = /usr/share/kediray/bin/xray": ["Empty = /usr/share/kediray/bin/xray", "Vide = /usr/share/kediray/bin/xray"],
	"Boş = sistemdeki hev-socks5-tunnel": ["Empty = the system's hev-socks5-tunnel", "Vide = le hev-socks5-tunnel du système"],
	"Boşta bağlantı süresi (sn)": ["Idle connection time (s)", "Durée de connexion inactive (s)"],
	"Boştaki WebSocket tünelini canlı tutar (varsayılan 30). Sunucu önündeki proxy/CDN ya da operatör boş bağlantıyı keserse bildirimler (WhatsApp vb.) telefona ulaşmaz; bu ayar onu önler. 0 = kapalı.": ["Keeps the idle WebSocket tunnel alive (default 30). If a proxy/CDN in front of the server or the operator cuts idle connections, notifications (WhatsApp etc.) don't reach the phone; this setting prevents that. 0 = off.", "Maintient en vie le tunnel WebSocket inactif (30 par défaut). Si un proxy/CDN devant le serveur ou l'opérateur coupe les connexions inactives, les notifications (WhatsApp, etc.) n'arrivent pas sur le téléphone ; ce réglage l'évite. 0 = désactivé."],
	"Bu cihazın şu an açık olan bağlantılarını listeler: hangi adrese ve porta, VPN'den mi direkt mi gittiği. Bir uygulamanın hangi adresi/portu kullandığını görüp yön kuralına eklemek için.": ["Lists this device's currently open connections: which address and port, and whether they go through the VPN or direct. Use it to see which address/port an app uses and add it to a routing rule.", "Liste les connexions actuellement ouvertes de cet appareil : quelle adresse et quel port, et si elles passent par le VPN ou en direct. Permet de voir quelle adresse/port une appli utilise et de l'ajouter à une règle de routage."],
	"Bu filtrelere uyan kayıt yok.": ["No entries match these filters.", "Aucune entrée ne correspond à ces filtres."],
	"Bu sunucu JSON ile eklenmiş. Form ile kaydedersen JSON'a özel ince ayarlar kaybolabilir; o ayarlar için JSON sekmesini kullan.": ["This server was added via JSON. If you save with the form, JSON-specific fine settings may be lost; use the JSON tab for those.", "Ce serveur a été ajouté via JSON. Si vous enregistrez avec le formulaire, les réglages fins propres au JSON peuvent être perdus ; utilisez l'onglet JSON pour ceux-ci."],
	"Bu sunucuya bağlan": ["Connect to this server", "Se connecter à ce serveur"],
	"Bu sunucuyu (ve komşularını) seçili uygulamaya ekler": ["Adds this server (and its neighbors) to the selected app", "Ajoute ce serveur (et ses voisins) à l'appli sélectionnée"],
	"Bu uygulama kuralı kalıcı olarak silinir.": ["This app rule will be deleted permanently.", "Cette règle d'application sera supprimée définitivement."],
	"Bu çevrimdışı cihazın kayıtlı yönünü sil": ["Delete this offline device's saved direction", "Supprimer le sens enregistré de cet appareil hors ligne"],
	"Bugün": ["Today", "Aujourd'hui"],
	"Bugün ↓ ": ["Today ↓ ", "Aujourd'hui ↓ "],
	"Bugünkü veri kullanımının cihazlara dağılımı": ["Distribution of today's data usage across devices", "Répartition de la consommation de données du jour entre les appareils"],
	"Bulunamadı: ": ["Not found: ", "Introuvable : "],
	"Canlı trafik": ["Live traffic", "Trafic en direct"],
	"Chrome ve Firefox \"Güvenli DNS\" ile sistem DNS'ini atlayıp doğrudan dns.google / cloudflare-dns.com gibi adreslere sorar. Bu hatta o adreslere ulaşılamadığı için sayfa başına 1-3 istek ~50 saniye askıda kalıyor ve tarayıcıda çark dönmeye devam ediyor. Açıkken bu istekler anında reddedilir (RST/ICMP), tarayıcı hemen KediRay'in DNS'ine döner. Alan adı kuralların ve gizliliğin etkilenmez. Varsayılan KAPALI: açıkken telefonun \"Özel DNS\" ayarı da reddedildiği için Speedtest gibi uygulamalar \"Check your connection\" uyarısı verebilir. Sayfalar askıda kalıyorsa açın.": ["Chrome and Firefox bypass the system DNS with \"Secure DNS\" and query addresses like dns.google / cloudflare-dns.com directly. Since those addresses can't be reached on this line, 1–3 requests per page hang for ~50 seconds and the browser spinner keeps turning. When on, those requests are rejected instantly (RST/ICMP) and the browser falls back to KediRay's DNS right away. Your domain rules and privacy are not affected. Default OFF: when on, the phone's \"Private DNS\" setting is also rejected, so apps like Speedtest may show a \"Check your connection\" warning. Turn it on if pages hang.", "Chrome et Firefox contournent le DNS du système avec « DNS sécurisé » et interrogent directement des adresses comme dns.google / cloudflare-dns.com. Comme ces adresses sont inaccessibles sur cette ligne, 1 à 3 requêtes par page restent bloquées ~50 secondes et le cercle du navigateur tourne sans fin. Activé, ces requêtes sont rejetées instantanément (RST/ICMP) et le navigateur revient aussitôt au DNS de KediRay. Vos règles de domaine et votre confidentialité ne sont pas affectées. Désactivé par défaut : activé, le réglage « DNS privé » du téléphone est aussi rejeté, donc des applis comme Speedtest peuvent afficher l'avertissement « Check your connection ». Activez-le si les pages se bloquent."],
	"Cihaz bazında trafik": ["Traffic by device", "Trafic par appareil"],
	"Cihaz kendi DNS'ini (8.8.8.8 gibi) yazsa bile sorgu modemin DNS'ine yönlendirilir. Kapatmayın: açıkken sorgu tünel/TUN yoluna hiç girmez ve sayfalar belirgin şekilde hızlı açılır (ölçüm: 205 ms yerine 1 ms).": ["Even if a device uses its own DNS (like 8.8.8.8), the query is redirected to the modem's DNS. Don't turn it off: when on, queries never enter the tunnel/TUN path and pages open noticeably faster (measured: 1 ms instead of 205 ms).", "Même si un appareil utilise son propre DNS (comme 8.8.8.8), la requête est redirigée vers le DNS du modem. Ne le désactivez pas : activé, les requêtes n'entrent jamais dans le chemin tunnel/TUN et les pages s'ouvrent nettement plus vite (mesuré : 1 ms au lieu de 205 ms)."],
	"Cihazların DNS'ini çekirdekte yakala": ["Capture devices' DNS in the kernel", "Intercepter le DNS des appareils dans le noyau"],
	"Cloudflare DoH (sansürsüz, direkt)": ["Cloudflare DoH (uncensored, direct)", "Cloudflare DoH (non censuré, direct)"],
	"Cloudflare'e kaydolunuyor, 30 sn kadar sürebilir": ["Registering with Cloudflare, may take up to 30 s", "Inscription auprès de Cloudflare, peut prendre jusqu'à 30 s"],
	"DNS acil yedeği devrede. ": ["DNS emergency fallback is active. ", "Le DNS de secours est actif. "],
	"DNS yavaş (": ["DNS is slow (", "DNS lent ("],
	"DNS çözümleme": ["DNS resolution", "Résolution DNS"],
	"DNS'e dokunma — modemin kendi DNS'i aynen kalır (sorun giderme için)": ["Don't touch DNS — the modem's own DNS stays as is (for troubleshooting)", "Ne pas toucher au DNS — le DNS propre du modem reste inchangé (pour le dépannage)"],
	"DNS: normal: Bu uygulamanın alan adları normal DNS ayarınla çözülür. Tıkla: tünel DNS'ine al (Discord gibi DNS'i bozulan uygulamalar için).": ["DNS: normal: This app's domains are resolved with your normal DNS settings. Click: switch to tunnel DNS (for apps like Discord whose DNS breaks).", "DNS : normal : les domaines de cette appli sont résolus avec vos réglages DNS normaux. Cliquer : passer au DNS du tunnel (pour les applis comme Discord dont le DNS pose problème)."],
	"DNS: tünel ✔": ["DNS: tunnel ✔", "DNS : tunnel ✔"],
	"DNS: tünel: Bu uygulamanın alan adları tünel içinden çözülür; yanlış ya da engelli adres geliyorsa işe yarar. Tıkla: normale döndür.": ["DNS: tunnel: This app's domains are resolved through the tunnel; useful if wrong or blocked addresses come back. Click: switch back to normal.", "DNS : tunnel : les domaines de cette appli sont résolus via le tunnel ; utile si des adresses erronées ou bloquées sont renvoyées. Cliquer : revenir à normal."],
	"Denetlenemedi: panel yanıt vermedi.": ["Could not check: the panel did not respond.", "Vérification impossible : le panneau n'a pas répondu."],
	"Direkt + TLS parçala (SNI engeli)": ["Direct + split TLS (SNI block)", "Direct + TLS fragmenté (blocage SNI)"],
	"Direkt DNS (Türkiye/direkt alan adları)": ["Direct DNS (Turkey / direct domains)", "DNS direct (Turquie / domaines directs)"],
	"Direkt seçilenler her durumda direkt çıksın (hat VPN'siz çıkamıyorsa o cihaz internetsiz kalabilir)": ["Whatever is set to direct always goes direct (if the line can't get out without the VPN, that device may be left without internet)", "Ce qui est réglé en direct sort toujours en direct (si la ligne ne sort pas sans VPN, cet appareil peut rester sans Internet)"],
	"Direkt ve VPN hızını karşılaştır": ["Compare direct and VPN speed", "Comparer la vitesse directe et VPN"],
	"Direkt çıksın (sadece listedekiler VPN)": ["Go direct (only the listed ones use the VPN)", "Sortir en direct (seuls ceux de la liste utilisent le VPN)"],
	"Direkt çıkış ölçülüyor…": ["Measuring direct exit…", "Mesure de la sortie directe…"],
	"Direkt çıkış şu an YOK görünüyor (hat VPN olmadan internete çıkamıyor ya da denetim henüz tamamlanmadı). Bu yüzden \"Direkt\" seçili cihazlar ve uygulamalar da VPN üzerinden çıkıyor. ": ["Direct exit currently seems MISSING (the line can't reach the internet without the VPN, or the check hasn't finished yet). So devices and apps set to \"Direct\" also go out through the VPN. ", "La sortie directe semble ABSENTE pour le moment (la ligne ne peut pas accéder à Internet sans VPN, ou la vérification n'est pas terminée). Les appareils et applis réglés sur « Direct » sortent donc aussi par le VPN. "],
	"Direkt çıkışı şimdi ölç": ["Measure direct exit now", "Mesurer la sortie directe maintenant"],
	"Direkt — sorgular çekirdekten ama tünele girmeden çıkar": ["Direct — queries go out from the kernel but without entering the tunnel", "Direct — les requêtes sortent du noyau sans entrer dans le tunnel"],
	"Direkt: Bu cihaz tüneli hiç kullanmaz, doğrudan hattan çıkar (en düşük ping; IP'si operatörün IP'si olur).": ["Direct: This device never uses the tunnel and goes straight out the line (lowest ping; its IP is the operator's IP).", "Direct : cet appareil n'utilise jamais le tunnel et sort directement par la ligne (ping le plus bas ; son IP est celle de l'opérateur)."],
	"Direkt: Tünele girmez, doğrudan hattan çıkar. En düşük ping; VPN yeniden başlasa bile bağlantı kopmaz. Siteler seni operatörün IP'siyle görür (oyun ve görüntülü görüşme için uygun).": ["Direct: Doesn't enter the tunnel, goes straight out the line. Lowest ping; the connection doesn't drop even if the VPN restarts. Sites see you with the operator's IP (good for games and video calls).", "Direct : n'entre pas dans le tunnel, sort directement par la ligne. Ping le plus bas ; la connexion ne coupe pas même si le VPN redémarre. Les sites vous voient avec l'IP de l'opérateur (idéal pour les jeux et les appels vidéo)."],
	"Direkt: çekirdekte bypass, VPN yeniden başlasa bile bağlantı kopmaz.": ["Direct: bypass in the kernel; the connection doesn't drop even if the VPN restarts.", "Direct : contournement dans le noyau ; la connexion ne coupe pas même si le VPN redémarre."],
	"Direkt: çekirdekte bypass, VPN yeniden başlasa bile bağlantı kopmaz. Yeni uygulama/oyun: Ayarlar → Uygulamalar.": ["Direct: bypass in the kernel; the connection doesn't drop even if the VPN restarts. New app/game: Settings → Apps.", "Direct : contournement dans le noyau ; la connexion ne coupe pas même si le VPN redémarre. Nouvelle appli/jeu : Paramètres → Applications."],
	"Diğer": ["Other", "Autre"],
	"Dosya seç ve güncelle": ["Choose file and update", "Choisir le fichier et mettre à jour"],
	"Dosya yüklenemedi: ": ["Could not upload file: ", "Échec du téléversement du fichier : "],
	"Doğrudan hattan": ["Directly from the line", "Directement par la ligne"],
	"Durdu — Günlük sekmesine bak": ["Stopped — see the Log tab", "Arrêté — voir l'onglet Journal"],
	"Dönem": ["Period", "Période"],
	"Dün": ["Yesterday", "Hier"],
	"Dünün %": ["Yesterday's %", "% d'hier"],
	"Düzenle": ["Edit", "Modifier"],
	"Düzey": ["Level", "Niveau"],
	"ECH anahtarı (abonelikten otomatik)": ["ECH key (automatic from subscription)", "Clé ECH (automatique depuis l'abonnement)"],
	"ELLE SEÇİLDİ": ["MANUALLY SELECTED", "SÉLECTION MANUELLE"],
	"EN İYİ": ["BEST", "MEILLEUR"],
	"ENGELLİ": ["BLOCKED", "BLOQUÉ"],
	"Eksik ya da hatalı alan": ["Missing or invalid field", "Champ manquant ou invalide"],
	"Elle güncelle": ["Manual update", "Mise à jour manuelle"],
	"Elle seç (otomatik geçiş kapanır)": ["Choose manually (automatic switching turns off)", "Choisir manuellement (le basculement automatique se désactive)"],
	"Emin misin? Ayarların sıfırlanacak ve kurulum sırasında VPN bir süre kesilecek. Hatta VPN dışında internet yoksa bağlantı kurulum bitene kadar gidebilir. Yedek dosyası modemde kalır; geri yüklemek için: kediray restore <dosya>.": ["Are you sure? Your settings will be reset and the VPN will be cut for a while during installation. If the line has no internet outside the VPN, the connection may be lost until the installation finishes. The backup file stays on the modem; to restore: kediray restore <file>.", "Êtes-vous sûr ? Vos réglages seront réinitialisés et le VPN sera coupé un moment pendant l'installation. Si la ligne n'a pas d'Internet hors VPN, la connexion peut être perdue jusqu'à la fin de l'installation. Le fichier de sauvegarde reste sur le modem ; pour restaurer : kediray restore <fichier>."],
	"Emin misin? Hattında VPN dışında internet yoksa kaldırınca internet bağlantın kesilir. Tekrar kurmak için kurulum dosyası ya da modemde elle kurulum gerekir.": ["Are you sure? If your line has no internet outside the VPN, your connection will be lost once it is removed. To install again you need the installer file or a manual install on the modem.", "Êtes-vous sûr ? Si votre ligne n'a pas d'Internet hors VPN, la connexion sera perdue après la désinstallation. Pour réinstaller, il faut le fichier d'installation ou une installation manuelle sur le modem."],
	"En az bir bant seç.": ["Select at least one band.", "Sélectionnez au moins une bande."],
	"En hızlı sunucu aranıyor…": ["Looking for the fastest server…", "Recherche du serveur le plus rapide…"],
	"En hızlı sunucuya geçildi": ["Switched to the fastest server", "Basculé vers le serveur le plus rapide"],
	"En son sürüm GitHub Release'ten indirilir, yayınlanan sha256sums ile doğrulanır ve kurulur. Doğrulama dosyası yoksa ya da uyuşmazsa kurulmaz.": ["The latest version is downloaded from the GitHub Release, verified with the published sha256sums and installed. If the verification file is missing or doesn't match, it is not installed.", "La dernière version est téléchargée depuis la GitHub Release, vérifiée avec les sha256sums publiés puis installée. Si le fichier de vérification est absent ou ne correspond pas, elle n'est pas installée."],
	"En yoğun ay": ["Busiest month", "Mois le plus chargé"],
	"En yoğun gün": ["Busiest day", "Jour le plus chargé"],
	"Engelle: Bu cihaz internete hiç çıkamaz (ne VPN ne direkt).": ["Block: This device can't reach the internet at all (neither VPN nor direct).", "Bloquer : cet appareil ne peut pas accéder à Internet du tout (ni VPN ni direct)."],
	"Etkinleştir": ["Activate", "Activer"],
	"Etkinleştirilemedi.": ["Could not activate.", "Activation impossible."],
	"Evet, kaldır": ["Yes, remove", "Oui, désinstaller"],
	"Evet, sıfırdan kur": ["Yes, install from scratch", "Oui, réinstaller à zéro"],
	"Evet, yardımcı olayım": ["Yes, I'll help", "Oui, je veux aider"],
	"Gece denetiminde yeni sürüm çıkmışsa kendiliğinden indirilir (SHA256 ile doğrulanır) ve kurulur; kurulum sırasında VPN kısa süre yeniden başlar. Ayarların ve sunucuların korunur. Kapalıysa yalnızca haber verilir.": ["At the nightly check, if a new version is out, it is downloaded automatically (verified with SHA256) and installed; the VPN restarts briefly during installation. Your settings and servers are kept. If off, you are only notified.", "Lors du contrôle nocturne, si une nouvelle version est disponible, elle est téléchargée automatiquement (vérifiée par SHA256) et installée ; le VPN redémarre brièvement pendant l'installation. Vos réglages et serveurs sont conservés. Désactivé, vous êtes seulement prévenu."],
	"Gelişmiş": ["Advanced", "Avancé"],
	"Geliştirici: ": ["Developer: ", "Développeur : "],
	"Geliştirmeye yardımcı ol": ["Help improve development", "Aider au développement"],
	"Geri yükle": ["Restore", "Restaurer"],
	"Geri yüklendi.": ["Restored.", "Restauré."],
	"Geri yüklenemedi.": ["Could not restore.", "Restauration impossible."],
	"Geçersiz değer '": ["Invalid value '", "Valeur invalide '"],
	"Geçersiz sayı": ["Invalid number", "Nombre invalide"],
	"Geçiş yapılıyor (en fazla ~40 sn)…": ["Switching (up to ~40 s)…", "Basculement en cours (~40 s max)…"],
	"GitHub Releases'teki kurulum dosyasının (kediray-install.sh) indirme sayısı. ": ["Download count of the installer file (kediray-install.sh) on GitHub Releases. ", "Nombre de téléchargements du fichier d'installation (kediray-install.sh) sur GitHub Releases. "],
	"GitHub deposundaki yıldız ve indirme sayısı": ["Stars and download count on the GitHub repository", "Étoiles et nombre de téléchargements du dépôt GitHub"],
	"GitHub'a ulaşılamadı": ["Could not reach GitHub", "GitHub injoignable"],
	"GitHub'dan güncelle": ["Update from GitHub", "Mettre à jour depuis GitHub"],
	"Google, TCP  [önerilen]": ["Google, TCP  [recommended]", "Google, TCP  [recommandé]"],
	"Görünüm": ["Appearance", "Apparence"],
	"Güncelleme başlatılamadı.": ["Could not start the update.", "Impossible de lancer la mise à jour."],
	"Güncelleme başlatılamadı. Ayrıntılı çıktıya bak.": ["Could not start the update. See the detailed output.", "Impossible de lancer la mise à jour. Voir la sortie détaillée."],
	"Güncelleme başlatılıyor…": ["Starting the update…", "Lancement de la mise à jour…"],
	"Güncelleme kaynağı": ["Update source", "Source des mises à jour"],
	"Güncelleme tamamlandı ✔ — LuCI yenileniyor, sayfa birazdan yeniden yüklenecek…": ["Update complete ✔ — LuCI is refreshing, the page will reload shortly…", "Mise à jour terminée ✔ — LuCI s'actualise, la page va se recharger…"],
	"Güncelleme: ": ["Update: ", "Mise à jour : "],
	"Güncellemeleri kontrol et": ["Check for updates", "Rechercher les mises à jour"],
	"Güncellemeyi denetle": ["Check for updates", "Rechercher une mise à jour"],
	"Güncelsin (": ["You are up to date (", "Vous êtes à jour ("],
	"Günlük": ["Log", "Journal"],
	"Günlük ortalama": ["Daily average", "Moyenne quotidienne"],
	"Günlük ortalama (": ["Daily average (", "Moyenne quotidienne ("],
	"Günlük seviyesi": ["Log level", "Niveau de journalisation"],
	"Güvenlik": ["Security", "Sécurité"],
	"Hakkında": ["About", "À propos"],
	"Hangi VPN motorunun çalışacağını seç ve hangi uygulamaların VPN'den, hangilerinin direkt gideceğini belirle.": ["Choose which VPN engine runs and decide which apps go through the VPN and which go direct.", "Choisissez quel moteur VPN fonctionne et décidez quelles applis passent par le VPN et lesquelles sortent en direct."],
	"Hayır": ["No", "Non"],
	"Hazır uygulamalar:": ["Ready-made apps:", "Applis prêtes :"],
	"Henüz cihaz verisi yok; sayaçlar başladıktan 1-2 dakika sonra dolar.": ["No device data yet; the counters fill up 1–2 minutes after they start.", "Pas encore de données d'appareil ; les compteurs se remplissent 1 à 2 minutes après leur démarrage."],
	"Henüz sunucu yok. \"Link / JSON ekle\" ile ekle ya da Ayarlar'dan abonelik gir.": ["No servers yet. Add one with \"Add link / JSON\" or enter a subscription under Settings.", "Aucun serveur pour l'instant. Ajoutez-en un avec « Ajouter lien / JSON » ou saisissez un abonnement dans Paramètres."],
	"Henüz veri yok": ["No data yet", "Pas encore de données"],
	"Her adres 5 kez denenir. Pencereyi kapatsan da ölçüm arkada biter; tekrar bakmak için düğmeye bas.": ["Each address is tried 5 times. Even if you close the window, the measurement finishes in the background; press the button to look again.", "Chaque adresse est testée 5 fois. Même si vous fermez la fenêtre, la mesure se termine en arrière-plan ; appuyez sur le bouton pour revoir."],
	"Her gece 01:00'de GitHub'da yeni bir sürüm çıkmış mı diye sorar ve Hakkında sayfasında söyler. Sen düğmeye basmadan hiçbir şey kurulmaz; bu yalnızca sorunun sorulup sorulmayacağına karar verir.": ["Every night at 01:00 it asks GitHub whether a new version is out and tells you on the About page. Nothing is installed unless you press the button; this only decides whether the question is asked.", "Chaque nuit à 01h00, il demande à GitHub si une nouvelle version est sortie et l'indique sur la page À propos. Rien n'est installé sans que vous appuyiez sur le bouton ; cela décide seulement si la question est posée."],
	"Her sunucu adresine 10 kez sıfırdan bağlanılır. Alan adı birden çok IP'ye çözülüyorsa her IP ayrı ölçülür.": ["Each server address is connected to from scratch 10 times. If a domain resolves to several IPs, each IP is measured separately.", "Chaque adresse de serveur est connectée 10 fois depuis zéro. Si un domaine se résout en plusieurs IP, chaque IP est mesurée séparément."],
	"Hesabı sil": ["Delete account", "Supprimer le compte"],
	"Hiçbir deneme düşmedi ama ": ["No attempt failed, but ", "Aucun essai n'a échoué, mais "],
	"Hız": ["Speed", "Vitesse"],
	"Hız ayarı (TCP tamponları + Xray tamponu)": ["Speed tuning (TCP buffers + Xray buffer)", "Réglage de la vitesse (tampons TCP + tampon Xray)"],
	"Hız testi (modem üzerinden)": ["Speed test (via the modem)", "Test de vitesse (via le modem)"],
	"Hız testi ya da büyük indirme yavaş hızlanıyorsa: çekirdeğin TCP tamponlarını büyütür ve Xray'in bağlantı başına tamponunu artırır (yaklaşık 1 MB). Bellek yalnızca yük gelince kullanılır. Sorun çıkarsa kapat.": ["If a speed test or large download ramps up slowly: enlarges the kernel's TCP buffers and increases Xray's per-connection buffer (about 1 MB). Memory is only used under load. Turn it off if it causes problems.", "Si un test de vitesse ou un gros téléchargement monte lentement : agrandit les tampons TCP du noyau et augmente le tampon par connexion de Xray (environ 1 Mo). La mémoire n'est utilisée que sous charge. Désactivez-le en cas de problème."],
	"Hız testi yapılamadı": ["Could not run the speed test", "Impossible de lancer le test de vitesse"],
	"Hız testi yapılıyor (≈30 sn)…": ["Running speed test (≈30 s)…", "Test de vitesse en cours (≈30 s)…"],
	"Hız öncelikli — hiçbir zaman sunucuya çözdürme": ["Speed first — never let the server resolve", "Vitesse d'abord — ne jamais faire résoudre par le serveur"],
	"Hız, Bildirim & Kararlılık": ["Speed, Notifications & Stability", "Vitesse, notifications et stabilité"],
	"IP / CIDR (satır ya da virgülle): 79.110.80.0/20": ["IP / CIDR (one per line or comma-separated): 79.110.80.0/20", "IP / CIDR (une par ligne ou séparées par des virgules) : 79.110.80.0/20"],
	"IP adresiyle TLS kullanıyorsan SNI alanına alan adını yaz ya da \"Sertifikayı otomatik sabitle\"yi işaretle.": ["If you use TLS with an IP address, enter the domain in the SNI field or tick \"Pin the certificate automatically\".", "Si vous utilisez TLS avec une adresse IP, saisissez le domaine dans le champ SNI ou cochez « Épingler automatiquement le certificat »."],
	"IPv6 desteği": ["IPv6 support", "Prise en charge d'IPv6"],
	"IPv6 sızıntı koruması": ["IPv6 leak protection", "Protection contre les fuites IPv6"],
	"Kaldır": ["Remove", "Supprimer"],
	"Kaldırılıyor… sayfa birazdan yenilenecek.": ["Removing… the page will refresh shortly.", "Suppression… la page va s'actualiser."],
	"Kapalı": ["Off", "Désactivé"],
	"Kapalıyken IPv6 (AAAA) kayıtları filtrelenir; sızıntı olmaz.": ["When off, IPv6 (AAAA) records are filtered; no leaks.", "Désactivé, les enregistrements IPv6 (AAAA) sont filtrés ; aucune fuite."],
	"Kapanış tırnağı \" eksik": ["Closing quote \" is missing", "Guillemet fermant \" manquant"],
	"Kapat: Bu uygulama kuralını geçici kapatır (silinmez); trafik genel kurala göre gider.": ["Disable: Temporarily turns off this app rule (not deleted); traffic follows the general rule.", "Désactiver : désactive temporairement cette règle d'application (non supprimée) ; le trafic suit la règle générale."],
	"Kaydet & Uygula dediğinde VPN yeniden başlar. Çekirdekte direkt geçen uygulamalar bundan etkilenmez.": ["When you press Save & Apply, the VPN restarts. Apps going direct in the kernel are not affected.", "Quand vous appuyez sur Enregistrer et appliquer, le VPN redémarre. Les applis qui passent en direct dans le noyau ne sont pas affectées."],
	"Kaydı sil": ["Delete entry", "Supprimer l'entrée"],
	"Kayıt başarısız": ["Registration failed", "Échec de l'inscription"],
	"Kayıtlı hata yok.": ["No errors recorded.", "Aucune erreur enregistrée."],
	"Kaç kişinin KediRay kullandığını görmek istiyorum. Onay verirsen günde bir kez şunlar gönderilir:": ["I'd like to see how many people use KediRay. If you agree, the following is sent once a day:", "J'aimerais savoir combien de personnes utilisent KediRay. Si vous acceptez, les éléments suivants sont envoyés une fois par jour :"],
	"KediRay güncelleniyor": ["KediRay is updating", "KediRay se met à jour"],
	"KediRay kaldırılıyor": ["KediRay is being removed", "KediRay est en cours de désinstallation"],
	"KediRay modemden kaldırılır: VPN durur, güvenlik duvarı kuralları ve panel sayfaları silinir. Ayar dosyan (/etc/config/kediray) modemde kalır. Devam edilsin mi?": ["KediRay is removed from the modem: the VPN stops, firewall rules and panel pages are deleted. Your config file (/etc/config/kediray) stays on the modem. Continue?", "KediRay est retiré du modem : le VPN s'arrête, les règles du pare-feu et les pages du panneau sont supprimées. Votre fichier de configuration (/etc/config/kediray) reste sur le modem. Continuer ?"],
	"KediRay sürümü": ["KediRay version", "Version de KediRay"],
	"KediRay'i geliştirmeye yardımcı olur musun?": ["Would you help improve KediRay?", "Voulez-vous aider à améliorer KediRay ?"],
	"KediRay'i kaldır": ["Remove KediRay", "Désinstaller KediRay"],
	"Kill switch — VPN trafiğini kes (WhatsApp asla direkt çıkmaz)": ["Kill switch — cut VPN traffic (WhatsApp never goes direct)", "Kill switch — couper le trafic VPN (WhatsApp ne sort jamais en direct)"],
	"Komut beklenen çıktıyı vermedi. Terminalde şunu çalıştırıp çıktıyı paylaşabilirsin:": ["The command did not give the expected output. Run this in a terminal and share the output:", "La commande n'a pas donné la sortie attendue. Exécutez ceci dans un terminal et partagez la sortie :"],
	"Komut çalışmadı. SSH ile deneyebilirsin:": ["The command did not run. You can try over SSH:", "La commande ne s'est pas exécutée. Vous pouvez essayer en SSH :"],
	"Komut çalışmadı. SSH ile şunu deneyip çıktıyı paylaşabilirsin:": ["The command did not run. Try this over SSH and share the output:", "La commande ne s'est pas exécutée. Essayez ceci en SSH et partagez la sortie :"],
	"Kurulum arka planda çalışıyor. Panel birkaç saniye yanıt vermeyebilir, bu normal.": ["The installation is running in the background. The panel may not respond for a few seconds; this is normal.", "L'installation s'exécute en arrière-plan. Le panneau peut ne pas répondre pendant quelques secondes ; c'est normal."],
	"Küçült / aç": ["Collapse / expand", "Réduire / développer"],
	"Kırmızı": ["Red", "Rouge"],
	"LAN arayüzleri": ["LAN interfaces", "Interfaces LAN"],
	"Lisans durumu okunamadı.": ["Could not read the license status.", "Impossible de lire l'état de la licence."],
	"Lisans etkinleştirildi.": ["License activated.", "Licence activée."],
	"Lisans gerekli: ayarlar lisans girilene kadar kaydedilemez (Hakkında → Lisans). Modem IMEI: ": ["License required: settings can't be saved until a license is entered (About → License). Modem IMEI: ", "Licence requise : les réglages ne peuvent pas être enregistrés tant qu'une licence n'est pas saisie (À propos → Licence). IMEI du modem : "],
	"Lisans geçerli": ["License valid", "Licence valide"],
	"Lisans kaldırıldı.": ["License removed.", "Licence supprimée."],
	"Lisansı gir": ["Enter license", "Saisir la licence"],
	"Lisansı kaldır": ["Remove license", "Supprimer la licence"],
	"Listeden seç ya da kendi adresini yaz. 204 döndüren küçük bir adres olmalı.": ["Pick from the list or type your own address. It should be a small address that returns 204.", "Choisissez dans la liste ou saisissez votre propre adresse. Ce doit être une petite adresse qui renvoie 204."],
	"Metin bitmeden satır sonu geldi (kapanış tırnağı \" eksik)": ["Line ended before the text did (closing quote \" is missing)", "Fin de ligne avant la fin du texte (guillemet fermant \" manquant)"],
	"Metinler tek tırnakla değil çift tırnakla (\") yazılmalı": ["Strings must be written with double quotes, not single quotes (\")", "Les textes doivent être écrits avec des guillemets doubles, pas simples (\")"],
	"Mevcut sunucuların ve ayarların yedekteki ile DEĞİŞTİRİLECEK. Önceki ayar modemde /etc/kediray.pre-restore olarak saklanır. Devam edilsin mi?": ["Your current servers and settings will be REPLACED with those in the backup. The previous settings are kept on the modem as /etc/kediray.pre-restore. Continue?", "Vos serveurs et réglages actuels seront REMPLACÉS par ceux de la sauvegarde. Les réglages précédents sont conservés sur le modem dans /etc/kediray.pre-restore. Continuer ?"],
	"Mixed (TCP çekirdek + UDP hev)": ["Mixed (TCP kernel + UDP hev)", "Mixed (TCP noyau + UDP hev)"],
	"Mixed — TCP çekirdekte (NAT), UDP hev-socks5-tunnel ile  [önerilen]": ["Mixed — TCP in the kernel (NAT), UDP via hev-socks5-tunnel  [recommended]", "Mixed — TCP dans le noyau (NAT), UDP via hev-socks5-tunnel  [recommandé]"],
	"Mixed: TCP çekirdekten, UDP TUN'dan. TUN: her şey TUN'dan geçer; bazı hatlarda sayfalar hızlanır, UDP biraz gecikir. TPROXY: TCP ve UDP çekirdekte. Redirect: yalnız TCP. Paketler yoksa otomatik TPROXY'ye düşer (apk add hev-socks5-tunnel kmod-tun). Karşılaştırmak için Kontrol Paneli → \"🐢 Sayfa gecikmesi\".": ["Mixed: TCP from the kernel, UDP from TUN. TUN: everything goes through TUN; pages speed up on some lines, UDP lags slightly. TPROXY: TCP and UDP in the kernel. Redirect: TCP only. If the packages are missing it automatically falls back to TPROXY (apk add hev-socks5-tunnel kmod-tun). To compare: Dashboard → \"🐢 Page latency\".", "Mixed : TCP depuis le noyau, UDP depuis TUN. TUN : tout passe par TUN ; les pages s'accélèrent sur certaines lignes, l'UDP a un peu de latence. TPROXY : TCP et UDP dans le noyau. Redirect : TCP seulement. Si les paquets manquent, repli automatique sur TPROXY (apk add hev-socks5-tunnel kmod-tun). Pour comparer : Tableau de bord → « 🐢 Latence des pages »."],
	"Mobil hat ayarı (5G/CGNAT)": ["Mobile line tuning (5G/CGNAT)", "Réglage ligne mobile (5G/CGNAT)"],
	"Mobil hatta tünel anlık koparsa bilinen adresler beklemeden verilir, arkada yenilenir (Xray serveStale). Uygulamalar \"DNS zaman aşımı\" yaşamaz.": ["If the tunnel drops momentarily on a mobile line, known addresses are served without waiting and refreshed in the background (Xray serveStale). Apps don't see \"DNS timeout\".", "Si le tunnel coupe un instant sur une ligne mobile, les adresses connues sont servies sans attendre et actualisées en arrière-plan (Xray serveStale). Les applis ne subissent pas de « délai DNS dépassé »."],
	"Modem açık": ["Modem on", "Modem allumé"],
	"Modem tarafında takılma yok: bu adresler her denemede hızlı açıldı. Takılma tarayıcı tarafındadır (Chrome → Gizlilik → \"Güvenli DNS\" kapalı olmalı; ayrıca IPv6/QUIC).": ["No stalls on the modem side: these addresses opened fast on every attempt. The stalling is on the browser side (Chrome → Privacy → \"Secure DNS\" should be off; also IPv6/QUIC).", "Aucun blocage côté modem : ces adresses se sont ouvertes rapidement à chaque essai. Le blocage vient du navigateur (Chrome → Confidentialité → « DNS sécurisé » doit être désactivé ; aussi IPv6/QUIC)."],
	"Modemde taranabilecek bant listesi bulunamadı.": ["No scannable band list found on the modem.", "Aucune liste de bandes à scanner trouvée sur le modem."],
	"Modemin bant bilgisi okunamadı (qmodem kurulu mu?).": ["Could not read the modem's band info (is qmodem installed?).", "Impossible de lire les infos de bande du modem (qmodem est-il installé ?)."],
	"Modemin bant bilgisi okunamadı.": ["Could not read the modem's band info.", "Impossible de lire les infos de bande du modem."],
	"NSA (4G çapa + 5G)": ["NSA (4G anchor + 5G)", "NSA (ancrage 4G + 5G)"],
	"Ne yapmalı: ": ["What to do: ", "Que faire : "],
	"Not: Bu sunucu abonelikten geliyor; abonelik güncellenince değişikliğin üzerine yazılabilir.": ["Note: This server comes from a subscription; your changes may be overwritten when the subscription updates.", "Remarque : ce serveur provient d'un abonnement ; vos modifications peuvent être écrasées lors de la mise à jour de l'abonnement."],
	"OTOMATİK": ["AUTO", "AUTO"],
	"OpenWrt için Xray tabanlı akıllı VPN": ["Smart Xray-based VPN for OpenWrt", "VPN intelligent basé sur Xray pour OpenWrt"],
	"Otomatik geçiş": ["Automatic switching", "Basculement automatique"],
	"Otomatik geçiş açılıyor…": ["Enabling automatic switching…", "Activation du basculement automatique…"],
	"Otomatik güncelleme": ["Automatic update", "Mise à jour automatique"],
	"Otomatik mod ölçüm aralığı": ["Auto mode measurement interval", "Intervalle de mesure du mode auto"],
	"Otomatik modda tüm bağlantılarda hedef alan adı sunucuya çözdürülür; bu her yeni bağlantıya bir miktar gecikme ekler ve hız testi gibi çok bağlantılı yüklemelerde yavaş hızlanmaya yol açabilir. \"Hız öncelikli\" seçersen bu gecikme olmaz, ama operatörün DNS'i bozduğu siteler (ör. Discord) açılmayabilir.": ["In auto mode, the target domain is resolved by the server on all connections; this adds some delay to every new connection and can make multi-connection loads like speed tests ramp up slowly. If you choose \"Speed first\" there is no such delay, but sites whose DNS the operator tampers with (e.g. Discord) may not open.", "En mode auto, le domaine cible est résolu par le serveur pour toutes les connexions ; cela ajoute un délai à chaque nouvelle connexion et peut ralentir la montée en débit des charges multi-connexions comme les tests de vitesse. Avec « Vitesse d'abord », ce délai disparaît, mais les sites dont l'opérateur altère le DNS (ex. Discord) peuvent ne pas s'ouvrir."],
	"Otomatik — DNS'i bozuk uygulama (Discord, WARP) varsa sunucu çözer": ["Automatic — the server resolves if an app's DNS is broken (Discord, WARP)", "Automatique — le serveur résout si le DNS d'une appli est défaillant (Discord, WARP)"],
	"Otomatik — en hızlı, düşerse diğerine geç": ["Automatic — fastest, switch to another if it drops", "Automatique — le plus rapide, bascule sur un autre s'il tombe"],
	"Otomatik — operatörün DNS sunucusu": ["Automatic — the operator's DNS server", "Automatique — le serveur DNS de l'opérateur"],
	"Otomatik — operatörün ikinci DNS sunucusu": ["Automatic — the operator's second DNS server", "Automatique — le second serveur DNS de l'opérateur"],
	"Otomatik: LuCI'nin kendi teması kalır. Açık/Koyu yalnızca KediRay sayfalarının renklerini zorlar. Vurgu rengi butonlara, seçili sekmelere, kart çizgisine ve trafik grafiğindeki VPN rengine uygulanır. Seçim bu tarayıcıda saklanır (telefonda ve bilgisayarda ayrı ayrı seçilir).": ["Auto: LuCI's own theme stays. Light/Dark only force the colors of KediRay pages. The accent color is applied to buttons, selected tabs, the card line and the VPN color in the traffic chart. The choice is saved in this browser (chosen separately on phone and computer).", "Auto : le thème propre de LuCI est conservé. Clair/Sombre ne forcent que les couleurs des pages KediRay. La couleur d'accent s'applique aux boutons, aux onglets sélectionnés, à la ligne des cartes et à la couleur VPN du graphique de trafic. Le choix est enregistré dans ce navigateur (choisi séparément sur téléphone et ordinateur)."],
	"Oturum yüklenen": ["Session uploaded", "Envoyé (session)"],
	"Oyun (Metin2 vb.) oynuyorsan TCP Mux KAPALI kalsın: açıkken oyuna girilemiyor ya da oyundan atılıyorsun. Varsayılan: kapalı.": ["If you play games (Metin2 etc.), keep TCP Mux OFF: when on, you can't enter the game or get kicked out. Default: off.", "Si vous jouez (Metin2, etc.), gardez TCP Mux DÉSACTIVÉ : activé, on ne peut pas entrer dans le jeu ou on en est éjecté. Par défaut : désactivé."],
	"Oyun açıkken bak. Oyunun satırlarında \"VPN\" yazıyorsa oyun tünelden geçiyor: ışınlanırken sunucu IP değişti sanıp atabilir. \"Direkt yap\" o sunucuyu (aynı /24 komşuları) ve portunu seçili uygulamaya ekler.": ["Check while the game is open. If the game's rows say \"VPN\", the game goes through the tunnel: when teleporting, the server may think the IP changed and kick you. \"Make direct\" adds that server (its /24 neighbors) and port to the selected app.", "Regardez pendant que le jeu est ouvert. Si les lignes du jeu indiquent « VPN », le jeu passe par le tunnel : lors d'une téléportation, le serveur peut croire que l'IP a changé et vous éjecter. « Passer en direct » ajoute ce serveur (ses voisins /24) et son port à l'appli sélectionnée."],
	"Oyun oynuyorsan (Metin2 vb.) KAPALI tut: açıkken oyuna girilemiyor ya da oyundan atılıyorsun. Açıkken bağlantılar tek tünelde birleşir; sadece sayfalar sürekli askıda kalıyorsa dene. Varsayılan: kapalı.": ["Keep OFF if you play games (Metin2 etc.): when on, you can't enter the game or get kicked out. When on, connections are merged into a single tunnel; try it only if pages hang constantly. Default: off.", "Gardez DÉSACTIVÉ si vous jouez (Metin2, etc.) : activé, on ne peut pas entrer dans le jeu ou on en est éjecté. Activé, les connexions sont fusionnées dans un seul tunnel ; essayez-le seulement si les pages se bloquent en permanence. Par défaut : désactivé."],
	"Panel yanıt vermedi": ["The panel did not respond", "Le panneau n'a pas répondu"],
	"Panel yanıt vermedi.": ["The panel did not respond.", "Le panneau n'a pas répondu."],
	"Panel yanıt vermedi; birkaç saniye sonra sayfayı yenile.": ["The panel did not respond; refresh the page in a few seconds.", "Le panneau n'a pas répondu ; actualisez la page dans quelques secondes."],
	"Panel yanıt vermedi; birkaç saniye sonra tekrar dene.": ["The panel did not respond; try again in a few seconds.", "Le panneau n'a pas répondu ; réessayez dans quelques secondes."],
	"Panel yanıt vermiyor, bekleniyor… (güncelleme arka planda sürüyor)": ["The panel isn't responding, waiting… (the update continues in the background)", "Le panneau ne répond pas, en attente… (la mise à jour se poursuit en arrière-plan)"],
	"Parçala": ["Fragment", "Fragmenter"],
	"Parçala: Direkt çıkar (VPN yok, ping düşük) ama TLS el sıkışması parçalanır; operatörün site adı (SNI) engelini aşabilir. IP'n operatörün IP'si kalır.": ["Fragment: Goes direct (no VPN, low ping) but the TLS handshake is fragmented; can get around the operator's site-name (SNI) block. Your IP stays the operator's IP.", "Fragmenter : sort en direct (pas de VPN, ping bas) mais la poignée de main TLS est fragmentée ; peut contourner le blocage du nom de site (SNI) par l'opérateur. Votre IP reste celle de l'opérateur."],
	"Path'e \"?ed=2048\" ekler. Bazı sunucu/CDN kurulumlarında sorun çıkarabildiği için varsayılan kapalı.": ["Adds \"?ed=2048\" to the path. Off by default because it can cause problems with some server/CDN setups.", "Ajoute « ?ed=2048 » au chemin. Désactivé par défaut car cela peut poser problème avec certaines configurations serveur/CDN."],
	"Ping = sunucuya ağ gecikmesi · tünel = açık bağlantıdaki istek (parantez içi: sıfırdan bağlanma)": ["Ping = network latency to the server · tunnel = request on an open connection (in brackets: connecting from scratch)", "Ping = latence réseau vers le serveur · tunnel = requête sur une connexion ouverte (entre parenthèses : connexion depuis zéro)"],
	"Ping: modemden sunucuya gerçek ağ gecikmesi.": ["Ping: real network latency from the modem to the server.", "Ping : latence réseau réelle du modem vers le serveur."],
	"Portlar (boşlukla): 5222 11000-13999": ["Ports (space-separated): 5222 11000-13999", "Ports (séparés par des espaces) : 5222 11000-13999"],
	"Proxy çekirdeği": ["Proxy core", "Cœur proxy"],
	"QUIC'i (UDP 443) reddet — önerilen": ["Reject QUIC (UDP 443) — recommended", "Rejeter QUIC (UDP 443) — recommandé"],
	"Redirect — sadece TCP (UDP/oyun/arama direkt çıkar)": ["Redirect — TCP only (UDP/game/calls go direct)", "Redirect — TCP seulement (UDP/jeux/appels en direct)"],
	"Rengi sıfırla": ["Reset color", "Réinitialiser la couleur"],
	"SA (yalnız 5G)": ["SA (5G only)", "SA (5G uniquement)"],
	"Sadece seçilenler VPN — Kurallar ve VPN'e ayarlı uygulamalar": ["Only the selected go via VPN — Rules and apps set to VPN", "Seuls les éléments sélectionnés passent par le VPN — Règles et applis réglées sur VPN"],
	"Sadece sinyal (hızlı, veri harcamaz)": ["Signal only (fast, uses no data)", "Signal seulement (rapide, ne consomme pas de données)"],
	"Satır ": ["Line ", "Ligne "],
	"Sayfa açılma gecikmesi": ["Page load latency", "Latence d'ouverture des pages"],
	"Sayfa açılma süresi ölçülüyor (≈10 sn)…": ["Measuring page load time (≈10 s)…", "Mesure du temps d'ouverture des pages (≈10 s)…"],
	"Sayfa gecikmesi — ölçüm yapılamadı": ["Page latency — could not measure", "Latence des pages — mesure impossible"],
	"Sayfa neden geç açılıyor: DNS mi, tünel mi?": ["Why do pages open slowly: DNS or tunnel?", "Pourquoi les pages s'ouvrent lentement : DNS ou tunnel ?"],
	"Sayfayı yenile": ["Refresh page", "Actualiser la page"],
	"Sertifikayı otomatik sabitle": ["Pin the certificate automatically", "Épingler automatiquement le certificat"],
	"Seçilenleri listeye ekle": ["Add selected to the list", "Ajouter la sélection à la liste"],
	"Seçtiğin bantları tek tek kilitler, her birinde gerçek hız (speedtest) ve sinyali ölçer, en hızlısını seçer. 5G kilidi internetini düşürmez: NSA seçiliyken 4G çapa açık kalır.": ["Locks the bands you choose one by one, measures real speed (speedtest) and signal on each, and picks the fastest. A 5G lock doesn't drop your internet: with NSA selected the 4G anchor stays on.", "Verrouille une à une les bandes choisies, mesure la vitesse réelle (speedtest) et le signal sur chacune, puis choisit la plus rapide. Un verrouillage 5G ne coupe pas votre Internet : avec NSA sélectionné, l'ancrage 4G reste actif."],
	"Seçtiğin uygulamaların çıkışı Cloudflare WARP olur: site seni VPN sunucusunun değil Cloudflare'in IP'si olarak görür. Her uygulamanın yanındaki \"WARP\" düğmesiyle seçilir.": ["The selected apps exit through Cloudflare WARP: sites see you as Cloudflare's IP, not the VPN server's. Selected with the \"WARP\" button next to each app.", "Les applis sélectionnées sortent par Cloudflare WARP : les sites vous voient avec l'IP de Cloudflare, et non celle du serveur VPN. Sélection avec le bouton « WARP » à côté de chaque appli."],
	"Sil: Bu uygulama kuralını kalıcı olarak siler.": ["Delete: Permanently deletes this app rule.", "Supprimer : supprime définitivement cette règle d'application."],
	"Son 30 gün (günlük)": ["Last 30 days (daily)", "30 derniers jours (quotidien)"],
	"Son güncelleme: ": ["Last updated: ", "Dernière mise à jour : "],
	"Sonuç yok": ["No results", "Aucun résultat"],
	"Speedtest (önerilen)": ["Speedtest (recommended)", "Speedtest (recommandé)"],
	"Sunucu (alan adı): ": ["Server (domain): ", "Serveur (domaine) : "],
	"Sunucu adreslerini çözmek için düz DNS IP'si.": ["Plain DNS IP for resolving server addresses.", "IP DNS classique pour résoudre les adresses des serveurs."],
	"Sunucu bağlantıları düşürüyor (günlükteki EOF hatası bu). Sayfalarda takılan istekler bunlar: sunucu yükü/port kısıtı olabilir — başka port ya da ikinci sunucu dene.": ["The server drops connections (that's the EOF error in the log). These are the requests that hang on pages: could be server load/port restrictions — try another port or a second server.", "Le serveur coupe les connexions (c'est l'erreur EOF du journal). Ce sont les requêtes qui restent bloquées sur les pages : cela peut venir de la charge du serveur ou d'une restriction de port — essayez un autre port ou un second serveur."],
	"Sunucu bağlantıyı kaç kez düşürüyor (günlükteki EOF hatası)": ["How many times the server drops connections (the EOF error in the log)", "Combien de fois le serveur coupe les connexions (l'erreur EOF du journal)"],
	"Sunucu bilgilerin, trafiğin, adın ya da IP adresin kaydedilmez. Ayarlar → \"Geliştirmeye yardımcı ol\" bölümünden istediğin an kapatabilirsin.": ["Your server details, traffic, name or IP address are not recorded. You can turn it off any time under Settings → \"Help improve development\".", "Vos informations de serveur, votre trafic, votre nom ou votre adresse IP ne sont pas enregistrés. Vous pouvez le désactiver à tout moment dans Paramètres → « Aider au développement »."],
	"Sunucu değiştiriliyor (bağlantılar kopmadan)…": ["Changing server (without dropping connections)…", "Changement de serveur (sans couper les connexions)…"],
	"Sunucu değiştirmek için Kontrol Paneli'ndeki \"Bağlan\" butonu bağlantıları koparmadan geçer.": ["To change servers, the \"Connect\" button on the Dashboard switches without dropping connections.", "Pour changer de serveur, le bouton « Connecter » du tableau de bord bascule sans couper les connexions."],
	"Sunucu el sıkışması": ["Server handshake", "Poignée de main serveur"],
	"Sunucu hatası": ["Server error", "Erreur serveur"],
	"Sunucu her denemede el sıkıştı: bağlantı kurulumu sağlam. Sayfa takılmaları başka yerde.": ["The server handshook on every attempt: connection setup is solid. The page stalls are elsewhere.", "Le serveur a répondu à chaque essai : l'établissement de la connexion est fiable. Les blocages de pages sont ailleurs."],
	"Sunucu okunamadı": ["Could not read the server", "Impossible de lire le serveur"],
	"Sunucudan kopar; VPN açık kalır, trafik doğrudan çıkar": ["Disconnects from the server; the VPN stays on, traffic goes out directly", "Se déconnecte du serveur ; le VPN reste actif, le trafic sort en direct"],
	"Sunucuların, uygulama kuralların ve ayarların SİLİNİR; GitHub deposundaki son kod baştan kurulur. Silmeden önce modemin /root klasörüne yedek alınır (kediray-backup-….uci). Devam edilsin mi?": ["Your servers, app rules and settings will be DELETED; the latest code from the GitHub repository is installed from scratch. Before deleting, a backup is made in the modem's /root folder (kediray-backup-….uci). Continue?", "Vos serveurs, règles d'application et réglages seront SUPPRIMÉS ; le dernier code du dépôt GitHub est installé à zéro. Avant la suppression, une sauvegarde est faite dans le dossier /root du modem (kediray-backup-….uci). Continuer ?"],
	"Sunucuların, uygulama kuralların ve ayarların tek dosyada. Modemi sıfırlarsan bu dosyayla geri getirirsin. Dosya sunucu kimliklerini (UUID) içerir: kimseyle paylaşma, GitHub'a yükleme.": ["Your servers, app rules and settings in one file. If you reset the modem, you restore them with this file. The file contains server IDs (UUIDs): don't share it with anyone or upload it to GitHub.", "Vos serveurs, règles d'application et réglages dans un seul fichier. Si vous réinitialisez le modem, vous les restaurez avec ce fichier. Le fichier contient les identifiants des serveurs (UUID) : ne le partagez avec personne et ne le mettez pas sur GitHub."],
	"Sunucunun şu anki sertifikasını sabitler; değiştiyse tüneli yeniden başlatır": ["Pins the server's current certificate; restarts the tunnel if it changed", "Épingle le certificat actuel du serveur ; redémarre le tunnel s'il a changé"],
	"Sunucunun şu anki sertifikasını sabitler; değiştiyse tüneli yeniden başlatır (internet gittiyse bas)": ["Pins the server's current certificate; restarts the tunnel if it changed (press if the internet is gone)", "Épingle le certificat actuel du serveur ; redémarre le tunnel s'il a changé (à utiliser si Internet a disparu)"],
	"Sunucuya IP ile bağlan": ["Connect to the server by IP", "Se connecter au serveur par IP"],
	"Sunucuya giden TCP bağlantısında keepalive (varsayılan 30). Operatör NAT kaydı boş bağlantıyı unutmasın. 0 = kapalı.": ["Keepalive on the TCP connection to the server (default 30). Keeps the operator's NAT from forgetting idle connections. 0 = off.", "Keepalive sur la connexion TCP vers le serveur (30 par défaut). Évite que le NAT de l'opérateur oublie les connexions inactives. 0 = désactivé."],
	"Sunucuya giden bağlantı isteği (SYN) düşerse çekirdek varsayılan olarak ~50 saniye yeniden dener; tarayıcı o isteği 50 saniye askıda tutar ve sayfa \"yükleniyor\" kalır. Açıkken 3 denemeye (≈15 sn) iner: bağlantı hızlı başarısız olur, tarayıcı kendisi tekrar dener ve sayfa tamamlanır. (tcp_syn_retries=3, tcp_retries2=8)": ["If the connection request (SYN) to the server is dropped, the kernel retries for ~50 seconds by default; the browser holds that request for 50 seconds and the page stays \"loading\". When on, it drops to 3 attempts (≈15 s): the connection fails quickly, the browser retries itself and the page completes. (tcp_syn_retries=3, tcp_retries2=8)", "Si la demande de connexion (SYN) vers le serveur est perdue, le noyau réessaie ~50 secondes par défaut ; le navigateur garde cette requête 50 secondes et la page reste « en chargement ». Activé, on passe à 3 essais (≈15 s) : la connexion échoue vite, le navigateur réessaie de lui-même et la page se termine. (tcp_syn_retries=3, tcp_retries2=8)"],
	"Sunucuyu düzenle": ["Edit server", "Modifier le serveur"],
	"Sürüm": ["Version", "Version"],
	"Sürümlerin alınacağı GitHub deposu, sahip/depo biçiminde. Yalnızca bir fork'tan kuruyorsan değiştir; boş bırakırsan varsayılan kullanılır.": ["The GitHub repository the releases are fetched from, as owner/repo. Change it only if you install from a fork; if left empty, the default is used.", "Le dépôt GitHub d'où sont récupérées les versions, au format propriétaire/dépôt. Ne le modifiez que si vous installez depuis un fork ; laissé vide, la valeur par défaut est utilisée."],
	"Sıfırdan kur": ["Reinstall from scratch", "Réinstaller à zéro"],
	"Sıfırdan kur / Kaldır": ["Reinstall from scratch / Remove", "Réinstaller à zéro / Désinstaller"],
	"Sıfırdan kur: ayarların yedeklenip silinir, GitHub deposundaki son kod baştan kurulur. Kaldır: KediRay modemden kaldırılır. İkisi de iki kez onay ister.": ["Reinstall from scratch: your settings are backed up and deleted, and the latest code from the GitHub repository is installed from scratch. Remove: KediRay is removed from the modem. Both ask for confirmation twice.", "Réinstaller à zéro : vos réglages sont sauvegardés puis supprimés, et le dernier code du dépôt GitHub est installé à zéro. Désinstaller : KediRay est retiré du modem. Les deux demandent une double confirmation."],
	"Sıfırla (%100)": ["Reset (100%)", "Réinitialiser (100 %)"],
	"TCP MSS ayarı": ["TCP MSS setting", "Réglage TCP MSS"],
	"TCP başlık": ["TCP header", "En-tête TCP"],
	"TPROXY — TCP ve UDP çekirdekte TPROXY ile": ["TPROXY — TCP and UDP in the kernel via TPROXY", "TPROXY — TCP et UDP dans le noyau via TPROXY"],
	"TUN — her şey (TCP+UDP) hev-socks5-tunnel üzerinden": ["TUN — everything (TCP+UDP) via hev-socks5-tunnel", "TUN — tout (TCP+UDP) via hev-socks5-tunnel"],
	"Takılma avı": ["Stall hunt", "Chasse aux blocages"],
	"Takılma avı başlatılamadı": ["Could not start the stall hunt", "Impossible de lancer la chasse aux blocages"],
	"Takılmalar ad çözümlemede (DNS): ": ["Stalls are in name resolution (DNS): ", "Les blocages viennent de la résolution de noms (DNS) : "],
	"Takılmalar bağlantı aşamasında: tünelin sunucuya bağlanması takılıyor. Sunucu/port/SNI ya da başka bir sunucu denenmeli.": ["Stalls are at the connection stage: the tunnel's connection to the server stalls. Try the server/port/SNI or another server.", "Les blocages sont à l'étape de connexion : la connexion du tunnel au serveur se bloque. Essayez le serveur/port/SNI ou un autre serveur."],
	"Tamam, hiçbir şey gönderilmeyecek.": ["OK, nothing will be sent.", "D'accord, rien ne sera envoyé."],
	"Tamamlandı ✔": ["Done ✔", "Terminé ✔"],
	"Tarama başlatılamadı: ": ["Could not start the scan: ", "Impossible de lancer le balayage : "],
	"Tarama başlatılsın mı?": ["Start the scan?", "Lancer le balayage ?"],
	"Tarama sırasında internet her bant için kısa süre kesilir. Hız ölçümü VPN açıksa tünel üzerinden yapılır (bu hatta direkt internet olmayabilir), aynı koşulda bantlar kıyaslanır. İptalde ya da internet gelmezse eski band kilidi geri yüklenir.": ["During the scan the internet is cut briefly for each band. If the VPN is on, the speed measurement is done through the tunnel (this line may have no direct internet); bands are compared under the same conditions. On cancel, or if the internet doesn't come back, the old band lock is restored.", "Pendant le balayage, Internet est brièvement coupé pour chaque bande. Si le VPN est actif, la mesure de vitesse se fait via le tunnel (cette ligne n'a peut-être pas d'Internet direct) ; les bandes sont comparées dans les mêmes conditions. En cas d'annulation, ou si Internet ne revient pas, l'ancien verrouillage de bande est rétabli."],
	"Taramayı başlat": ["Start scan", "Lancer le balayage"],
	"Tarayıcıda takılan adresleri arka arkaya dener: takılma DNS'te mi bağlantıda mı?": ["Tries the addresses that stall in the browser back to back: is the stall in DNS or in the connection?", "Teste à la suite les adresses qui se bloquent dans le navigateur : le blocage est-il dans le DNS ou dans la connexion ?"],
	"Tarayıcıların QUIC bağlantısı tünelde takılabiliyor (ör. Google giriş sayfası dönüp duruyor). Reddedilince tarayıcı beklemeden TCP'ye (tünele) geçer; v2rayNG ve Xray'in varsayılanı da budur. Oyun, arama ve DNS gibi diğer UDP trafiği etkilenmez.": ["Browsers' QUIC connections can stall in the tunnel (e.g. the Google sign-in page keeps spinning). When rejected, the browser switches to TCP (the tunnel) without waiting; this is also the default of v2rayNG and Xray. Other UDP traffic such as games, calls and DNS is not affected.", "Les connexions QUIC des navigateurs peuvent se bloquer dans le tunnel (ex. la page de connexion Google tourne sans fin). Une fois rejeté, le navigateur passe à TCP (le tunnel) sans attendre ; c'est aussi le comportement par défaut de v2rayNG et Xray. Les autres trafics UDP (jeux, appels, DNS) ne sont pas affectés."],
	"Tarayıcıların kendi DNS'ini (DoH) engelle": ["Block browsers' own DNS (DoH)", "Bloquer le DNS propre des navigateurs (DoH)"],
	"Taşınamadı": ["Could not move", "Déplacement impossible"],
	"Testi çalıştır": ["Run the test", "Lancer le test"],
	"Teşekkürler! Anonim kullanım sayısı açıldı.": ["Thank you! Anonymous usage counting is enabled.", "Merci ! Le comptage anonyme d'utilisation est activé."],
	"Teşhis": ["Diagnosis", "Diagnostic"],
	"Trafiği yakalanacak ağlar (misafir ağı eklemek için guest yaz).": ["Networks whose traffic is captured (type guest to add the guest network).", "Réseaux dont le trafic est capturé (saisissez guest pour ajouter le réseau invité)."],
	"Tüm bantları aç": ["Enable all bands", "Activer toutes les bandes"],
	"Tüm cihazlar (": ["All devices (", "Tous les appareils ("],
	"Tüm sunucular ölçülüyor…": ["Measuring all servers…", "Mesure de tous les serveurs…"],
	"Tümü": ["All", "Tous"],
	"Tümü VPN": ["All via VPN", "Tout via VPN"],
	"Tümü VPN (yerel ağ hariç)": ["All via VPN (except local network)", "Tout via VPN (hors réseau local)"],
	"Tünel (açık): aynı bağlantıdan giden ikinci isteğin süresi — sayfaların ve oyunun gerçekte hissettiği gecikme budur.": ["Tunnel (open): time of the second request over the same connection — this is the latency pages and games actually feel.", "Tunnel (ouvert) : durée de la deuxième requête sur la même connexion — c'est la latence réellement ressentie par les pages et les jeux."],
	"Tünel (yeni): sıfırdan bağlantı açıp tam bir web isteği yapma süresi — TCP + TLS + WebSocket el sıkışmaları dahil (v2rayNG \"gerçek gecikme\").": ["Tunnel (new): time to open a connection from scratch and make a full web request — including TCP + TLS + WebSocket handshakes (v2rayNG \"real delay\").", "Tunnel (nouveau) : durée d'ouverture d'une connexion depuis zéro et d'une requête web complète — poignées de main TCP + TLS + WebSocket comprises (« délai réel » de v2rayNG)."],
	"Tünel kurulamadı": ["Could not establish the tunnel", "Impossible d'établir le tunnel"],
	"Tünel takılırsa önbellekten yanıt ver": ["Answer from cache if the tunnel stalls", "Répondre depuis le cache si le tunnel se bloque"],
	"Tünelden giden DNS yanıt vermedi, adresler geçici olarak operatörün DNS'iyle çözülüyor — internet çalışmaya devam ediyor ama bu sorgular tünelden geçmiyor. Tünel düzelince kendiliğinden geri döner. Sebebini görmek için \"🤝 Sunucu el sıkışması\"na bas.": ["DNS through the tunnel did not respond; addresses are temporarily resolved with the operator's DNS — the internet keeps working but these queries are not going through the tunnel. It returns by itself once the tunnel recovers. Press \"🤝 Server handshake\" to see the cause.", "Le DNS via le tunnel n'a pas répondu ; les adresses sont temporairement résolues avec le DNS de l'opérateur — Internet continue de fonctionner mais ces requêtes ne passent pas par le tunnel. Il revient tout seul dès que le tunnel est rétabli. Appuyez sur « 🤝 Poignée de main serveur » pour voir la cause."],
	"Tünelden çözülen sorguların gittiği sunucu (VPN üzerinden). Varsayılan Google TCP: en uyumlusu. Bu hatta ölçüldü: DNS-over-TCP kullanılırken tünelde tek bir bağlantı düşünce sorgu ölebiliyor (günlükte \"failed to read response length → read/write on closed pipe\") ve sayfalar askıda kalıyor. Bu belirtiyi görürsen Cloudflare ya da Google DoH'a geç: HTTP/2 üzerinden kendi içinde yeniden dener. VPN sunucun DoH'a çıkamıyorsa TCP'ye dön. Adres IP olmalı.": ["The server that tunnel-resolved queries go to (via the VPN). Default Google TCP: the most compatible. Measured on this line: with DNS-over-TCP, when a single connection in the tunnel drops the query can die (in the log: \"failed to read response length → read/write on closed pipe\") and pages hang. If you see this symptom, switch to Cloudflare or Google DoH: it retries on its own over HTTP/2. If your VPN server can't reach DoH, go back to TCP. The address must be an IP.", "Le serveur vers lequel vont les requêtes résolues via le tunnel (via le VPN). Google TCP par défaut : le plus compatible. Mesuré sur cette ligne : avec DNS-over-TCP, quand une seule connexion du tunnel tombe, la requête peut mourir (dans le journal : « failed to read response length → read/write on closed pipe ») et les pages se bloquent. Si vous voyez ce symptôme, passez à Cloudflare ou Google DoH : il réessaie de lui-même via HTTP/2. Si votre serveur VPN ne peut pas joindre DoH, revenez à TCP. L'adresse doit être une IP."],
	"Tünelden — dnsmasq sorguları çekirdeğe, çekirdek tünele verir  [önerilen]": ["Via tunnel — dnsmasq hands queries to the kernel, the kernel hands them to the tunnel  [recommended]", "Via le tunnel — dnsmasq transmet les requêtes au noyau, le noyau au tunnel  [recommandé]"],
	"Tür": ["Type", "Type"],
	"Uyarı": ["Warning", "Avertissement"],
	"Uygulama / oyun adı": ["App / game name", "Nom de l'appli / du jeu"],
	"Uygulamanın bilinen bir adresini yaz; ana alan adı, yaygın alt alan adları ve (biliniyorsa) ilgili hizmetlerin adları aranır. \"domain:\" kaydı alt alan adlarını da kapsar.": ["Type a known address of the app; the main domain, common subdomains and (if known) names of related services are searched. A \"domain:\" entry also covers subdomains.", "Saisissez une adresse connue de l'appli ; le domaine principal, les sous-domaines courants et (si connus) les noms des services associés sont recherchés. Une entrée « domain: » couvre aussi les sous-domaines."],
	"Uygulanıyor…": ["Applying…", "Application…"],
	"Uzak DNS (VPN üzerinden)": ["Remote DNS (via VPN)", "DNS distant (via VPN)"],
	"Uzaklaştır": ["Zoom out", "Dézoomer"],
	"VPN = tünel trafiği. Direkt = modem toplamı − VPN (VPN'siz çıkan her şey). Sayaçlar yeniden başlatmada saklanır.": ["VPN = tunnel traffic. Direct = modem total − VPN (everything that goes out without the VPN). Counters are kept across restarts.", "VPN = trafic du tunnel. Direct = total du modem − VPN (tout ce qui sort sans VPN). Les compteurs sont conservés après redémarrage."],
	"VPN Ayırma": ["VPN Split", "Séparation VPN"],
	"VPN açık · açılışta otomatik bağlan": ["VPN on · connect automatically at boot", "VPN activé · connexion automatique au démarrage"],
	"VPN başlatılıyor…": ["Starting VPN…", "Démarrage du VPN…"],
	"VPN cihazlarının IPv6 ile tüneli atlamasını engeller.": ["Prevents VPN devices from bypassing the tunnel over IPv6.", "Empêche les appareils VPN de contourner le tunnel via IPv6."],
	"VPN hızı direkte yakın, tünel sorunsuz.": ["VPN speed is close to direct; the tunnel is fine.", "La vitesse VPN est proche du direct ; le tunnel est en bon état."],
	"VPN hızı direktin bir miktar altında; WS+TLS tünelde bu normal sayılır.": ["VPN speed is somewhat below direct; this is considered normal for a WS+TLS tunnel.", "La vitesse VPN est un peu inférieure au direct ; c'est considéré comme normal pour un tunnel WS+TLS."],
	"VPN hızı direktin çok altında: sunucunun hattı/uzaklığı ya da sunucu tarafı sınırı olabilir. \"En hızlıyı bul\" ile başka sunucu dene.": ["VPN speed is far below direct: it may be the server's line/distance or a server-side limit. Try another server with \"Find the fastest\".", "La vitesse VPN est bien inférieure au direct : cela peut venir de la ligne/distance du serveur ou d'une limite côté serveur. Essayez un autre serveur avec « Trouver le plus rapide »."],
	"VPN kurallarını kullansın": ["Use VPN rules", "Utiliser les règles VPN"],
	"VPN sunucusunun içinden (önerilen)": ["From inside the VPN server (recommended)", "Depuis le serveur VPN (recommandé)"],
	"VPN çalışmaya devam eder; sunucu, uygulama ve cihaz ayarları lisans girilene kadar değiştirilemez.": ["The VPN keeps running; server, app and device settings can't be changed until a license is entered.", "Le VPN continue de fonctionner ; les réglages des serveurs, applis et appareils ne peuvent pas être modifiés tant qu'une licence n'est pas saisie."],
	"VPN çalışmaya devam ediyor; ancak sunucu, uygulama ve cihaz ayarları lisans girilene kadar değiştirilemez. Modem IMEI: ": ["The VPN keeps running; however, server, app and device settings can't be changed until a license is entered. Modem IMEI: ", "Le VPN continue de fonctionner ; cependant les réglages des serveurs, applis et appareils ne peuvent pas être modifiés tant qu'une licence n'est pas saisie. IMEI du modem : "],
	"VPN çalışmıyor.": ["The VPN is not running.", "Le VPN ne fonctionne pas."],
	"VPN çekirdeği çökerse": ["If the VPN core crashes", "Si le cœur VPN plante"],
	"VPN: Bu cihazın tüm trafiği VPN tünelinden çıkar; siteler VPN sunucusunun IP'sini görür.": ["VPN: All of this device's traffic goes out through the VPN tunnel; sites see the VPN server's IP.", "VPN : tout le trafic de cet appareil sort par le tunnel VPN ; les sites voient l'IP du serveur VPN."],
	"VPN: Bu uygulamanın trafiği VPN tünelinden çıkar. Operatör ne yaptığını görmez, siteler seni VPN sunucusunun IP'siyle görür. Tünel koparsa bağlantı da kopar.": ["VPN: This app's traffic goes out through the VPN tunnel. The operator can't see what you're doing, and sites see you with the VPN server's IP. If the tunnel drops, the connection drops too.", "VPN : le trafic de cette appli sort par le tunnel VPN. L'opérateur ne voit pas ce que vous faites, et les sites vous voient avec l'IP du serveur VPN. Si le tunnel tombe, la connexion tombe aussi."],
	"Varsayılan": ["Default", "Par défaut"],
	"Varsayılan kapalı: hedef IP korunur, her bağlantıda ikinci DNS sorgusu olmaz (daha düşük gecikme).": ["Off by default: the destination IP is kept, and there is no second DNS query on every connection (lower latency).", "Désactivé par défaut : l'IP de destination est conservée, et il n'y a pas de seconde requête DNS à chaque connexion (latence plus faible)."],
	"Varsayılan: Bu cihaza özel kural yok, genel ayara uyar.": ["Default: No rule specific to this device; follows the general setting.", "Par défaut : aucune règle propre à cet appareil ; suit le réglage général."],
	"Varsayılana dön": ["Reset to default", "Rétablir par défaut"],
	"Vazgeç": ["Cancel", "Annuler"],
	"Vazgeçildi.": ["Cancelled.", "Annulé."],
	"WARP bağlantı yolu": ["WARP connection path", "Chemin de connexion WARP"],
	"WARP hesabı oluştur": ["Create WARP account", "Créer un compte WARP"],
	"WARP hesabı oluşturuluyor…": ["Creating WARP account…", "Création du compte WARP…"],
	"WARP: Çıkış Cloudflare WARP ağından olur; siteler seni VPN sunucusunun değil Cloudflare'in IP'siyle görür. VPN sunucusunun IP'sini engelleyen siteler için.": ["WARP: Exit is through the Cloudflare WARP network; sites see you with Cloudflare's IP, not the VPN server's. For sites that block the VPN server's IP.", "WARP : la sortie se fait par le réseau Cloudflare WARP ; les sites vous voient avec l'IP de Cloudflare et non celle du serveur VPN. Pour les sites qui bloquent l'IP du serveur VPN."],
	"Xray bağlantı tamponu (KB)": ["Xray connection buffer (KB)", "Tampon de connexion Xray (Ko)"],
	"Xray bu ayarı kabul etmedi": ["Xray did not accept this setting", "Xray n'a pas accepté ce réglage"],
	"Xray outbound JSON'u. v2rayNG'nin tam yapılandırmasını da yapıştırabilirsin, içinden sunucu kısmı alınır. Girinti hata değildir, \"Biçimlendir\" ile düzeltilir; virgül/tırnak hataları anında satır ve sütunuyla gösterilir.": ["Xray outbound JSON. You can also paste v2rayNG's full configuration; the server part is taken from it. Indentation is not an error and is fixed with \"Format\"; comma/quote errors are shown instantly with line and column.", "JSON outbound Xray. Vous pouvez aussi coller la configuration complète de v2rayNG ; la partie serveur en est extraite. L'indentation n'est pas une erreur et se corrige avec « Formater » ; les erreurs de virgule/guillemet sont signalées instantanément avec la ligne et la colonne."],
	"Xray varsayılanı 300 sn; telefonun bildirim bağlantısını koparır. Önerilen 14400 (4 saat): bildirim bağlantısı gece boyunca yaşar.": ["Xray's default is 300 s, which cuts the phone's notification connection. Recommended 14400 (4 hours): the notification connection lives through the night.", "La valeur par défaut de Xray est 300 s, ce qui coupe la connexion de notification du téléphone. Recommandé : 14400 (4 heures) : la connexion de notification survit toute la nuit."],
	"Xray çekirdek yolu": ["Xray core path", "Chemin du cœur Xray"],
	"Yakınlaştır": ["Zoom in", "Zoomer"],
	"Yalnızca TUN yakalama modunda ve UDP için kullanılır. Varsayılan 1380 (hücresel hatta WhatsApp foto/video takılmasını önler); sorun yoksa 1400-1500 denenebilir. 576-9000 arası. Değiştirince VPN yeniden başlar.": ["Used only in TUN capture mode and for UDP. Default 1380 (prevents WhatsApp photo/video stalls on a cellular line); if there's no problem, 1400–1500 can be tried. Range 576–9000. The VPN restarts when changed.", "Utilisé uniquement en mode de capture TUN et pour l'UDP. 1380 par défaut (évite les blocages des photos/vidéos WhatsApp sur ligne cellulaire) ; en l'absence de problème, 1400–1500 peut être essayé. Plage 576–9000. Le VPN redémarre à la modification."],
	"Yalnızca bellekte tutulur, flash belleğe hiçbir şey yazılmaz. Kaynak: sistem günlüğü (logread) — KediRay, Xray çekirdeği ve UDP tüneli (hev). Xray'in bağlantı ayrıntıları için Ayarlar → Gelişmiş → Günlük seviyesi: info.": ["Kept in memory only; nothing is written to flash. Source: the system log (logread) — KediRay, the Xray core and the UDP tunnel (hev). For Xray's connection details: Settings → Advanced → Log level: info.", "Conservé uniquement en mémoire ; rien n'est écrit en flash. Source : le journal système (logread) — KediRay, le cœur Xray et le tunnel UDP (hev). Pour les détails de connexion d'Xray : Paramètres → Avancé → Niveau de journalisation : info."],
	"Yapılandırma denetimi": ["Configuration check", "Vérification de la configuration"],
	"Yapılandırma denetleniyor…": ["Checking configuration…", "Vérification de la configuration…"],
	"Yapılandırma hatası — VPN başlatılamadı": ["Configuration error — the VPN could not start", "Erreur de configuration — le VPN n'a pas pu démarrer"],
	"Yapılandırma yok": ["No configuration", "Aucune configuration"],
	"Yapılandırma üretilemedi": ["Could not generate the configuration", "Impossible de générer la configuration"],
	"Yazım hatası": ["Syntax error", "Erreur de syntaxe"],
	"Yazım/alan hatası ve Xray testi": ["Syntax/field errors and Xray test", "Erreurs de syntaxe/champ et test Xray"],
	"Yedek alınamadı: ": ["Could not make a backup: ", "Impossible de créer la sauvegarde : "],
	"Yedek alınamadı: panel yanıt vermedi.": ["Could not make a backup: the panel did not respond.", "Impossible de créer la sauvegarde : le panneau n'a pas répondu."],
	"Yedek ölçüm adresi": ["Backup measurement address", "Adresse de mesure de secours"],
	"Yedekle / geri yükle": ["Backup / restore", "Sauvegarde / restauration"],
	"Yedekten geri yükle": ["Restore from backup", "Restaurer depuis une sauvegarde"],
	"Yeni kediray-…-install.sh dosyasını seç; yüklenir ve otomatik kurulur.": ["Choose the new kediray-…-install.sh file; it is uploaded and installed automatically.", "Choisissez le nouveau fichier kediray-…-install.sh ; il est téléversé et installé automatiquement."],
	"Yeniden başlat": ["Restart", "Redémarrer"],
	"Yeniden başlatılıyor…": ["Restarting…", "Redémarrage…"],
	"Yerel SOCKS5 portu (hev bu porta bağlanır)": ["Local SOCKS5 port (hev connects to this port)", "Port SOCKS5 local (hev se connecte à ce port)"],
	"Yeşil": ["Green", "Vert"],
	"Yukarı taşı": ["Move up", "Monter"],
	"Yön": ["Direction", "Sens"],
	"Yönlendirme modu": ["Routing mode", "Mode de routage"],
	"Yükleme": ["Upload", "Envoi"],
	"alt alan adı": ["subdomain", "sous-domaine"],
	"ana alan adı": ["main domain", "domaine principal"],
	"auto = modeme operatörden gelen DNS (önerilen): her zaman ayakta ve tünele girmez. Bazı hatlarda DoH adreslerine hiç ulaşılamıyor ve o zaman her sorgu saniyelerce bekleyip sayfayı kilitliyor.": ["auto = the DNS the modem gets from the operator (recommended): always up and doesn't enter the tunnel. On some lines DoH addresses can't be reached at all, and then every query waits for seconds and locks up the page.", "auto = le DNS que le modem reçoit de l'opérateur (recommandé) : toujours disponible et n'entre pas dans le tunnel. Sur certaines lignes, les adresses DoH sont totalement inaccessibles et chaque requête attend alors plusieurs secondes et bloque la page."],
	"ayar boş": ["empty config", "config vide"],
	"bağlanamadı (bu bantta kapsama yok)": ["could not connect (no coverage on this band)", "connexion impossible (pas de couverture sur cette bande)"],
	"bilgi ve üstü": ["info and above", "info et plus"],
	"bugün": ["today", "aujourd'hui"],
	"bugün günlük ortalamanın %": ["today is % of the daily average", "aujourd'hui représente % de la moyenne quotidienne"],
	"gRPC servis adı": ["gRPC service name", "Nom du service gRPC"],
	"geçen haftaya göre": ["vs. last week", "par rapport à la semaine dernière"],
	"geçerli link/JSON yok": ["no valid link/JSON", "aucun lien/JSON valide"],
	"günlük ort. ": ["daily avg. ", "moy. quot. "],
	"güzel": ["nice", "bien"],
	"hepsi (ayıklama dahil)": ["all (including debug)", "tout (débogage inclus)"],
	"kapalı": ["off", "désactivé"],
	"rastgele bir kurulum kimliği (seni tanıtmaz)": ["a random install ID (doesn't identify you)", "un identifiant d'installation aléatoire (ne vous identifie pas)"],
	"sahip/depo biçiminde yaz": ["type as owner/repo", "saisir au format propriétaire/dépôt"],
	"sinyal ölçülemedi": ["signal could not be measured", "signal non mesurable"],
	"takılma yok": ["no stalls", "aucun blocage"],
	"tüm bileşenler": ["all components", "tous les composants"],
	"tüm cihazlar": ["all devices", "tous les appareils"],
	"tünel ": ["tunnel ", "tunnel "],
	"uyarı ve üstü": ["warning and above", "avertissement et plus"],
	"uygulama adı": ["app name", "nom de l'appli"],
	"(birden fazla satır olabilir)": ["(there can be several lines)", "(plusieurs lignes possibles)"],
	"veya Xray JSON: tek outbound, outbound dizisi": ["or Xray JSON: a single outbound, an outbound array", "ou JSON Xray : un seul outbound, un tableau d'outbounds"],
	"ya da v2rayNG \"tam yapılandırma\" JSON'u": ["or v2rayNG \"full configuration\" JSON", "ou JSON « configuration complète » de v2rayNG"],
	"x-ui / 3x-ui abonelik linki (base64 veya düz liste).": ["x-ui / 3x-ui subscription link (base64 or plain list).", "Lien d'abonnement x-ui / 3x-ui (base64 ou liste simple)."],
	"yanıt alınamadı": ["no response received", "aucune réponse reçue"],
	"yanıt yok": ["no response", "pas de réponse"],
	"yıldız": ["stars", "étoiles"],
	"{ } Xray yapılandırması": ["{ } Xray configuration", "{ } Configuration Xray"],
	"Çalışan diğer VPN motorları durdurulur ve ": ["Other running VPN engines will be stopped and ", "Les autres moteurs VPN en cours seront arrêtés et "],
	"Çalıştırılamadı: ": ["Could not run: ", "Exécution impossible : "],
	"Çalışıyor": ["Running", "En marche"],
	"Çalışıyor…": ["Running…", "En cours…"],
	"Çekirdeği güncellemek için SSH: kediray update-core · Coğrafi veriler: kediray update-geo": ["To update the core over SSH: kediray update-core · Geo data: kediray update-geo", "Pour mettre à jour le cœur via SSH : kediray update-core · Données géographiques : kediray update-geo"],
	"Çevrimdışı cihazlar (": ["Offline devices (", "Appareils hors ligne ("],
	"Çıktı": ["Output", "Sortie"],
	"Çıkış kodu: ": ["Exit code: ", "Code de sortie : "],
	"Ölçülüyor…": ["Measuring…", "Mesure en cours…"],
	"Ölçüm": ["Measurement", "Mesure"],
	"Ölçüm adresi (ping / sağlık)": ["Measurement address (ping / health)", "Adresse de mesure (ping / santé)"],
	"Ölçüm başladı, ilk sonuçlar birkaç saniye içinde…": ["Measurement started, first results within a few seconds…", "Mesure lancée, premiers résultats dans quelques secondes…"],
	"Ölçüm başlatılıyor…": ["Starting measurement…", "Lancement de la mesure…"],
	"Ölçüm hâlâ sürüyor. Düğmeye tekrar basarak kaldığı yerden okuyabilirsin.": ["The measurement is still running. Press the button again to read from where it left off.", "La mesure est toujours en cours. Appuyez à nouveau sur le bouton pour reprendre la lecture là où elle s'est arrêtée."],
	"Ölçüm modemin kendi bağlantısıyla yapılır (Cloudflare, 20 MB). Wi-Fi hızın bundan düşükse darboğaz Wi-Fi'dır.": ["The measurement is made over the modem's own connection (Cloudflare, 20 MB). If your Wi-Fi speed is lower than this, Wi-Fi is the bottleneck.", "La mesure est faite via la propre connexion du modem (Cloudflare, 20 Mo). Si votre débit Wi-Fi est inférieur, le goulot d'étranglement est le Wi-Fi."],
	"Ölçüm sonucu okunamadı: aşağıdaki çıktıyı paylaş ya da SSH ile \"kediray dialtest\" çalıştır.": ["Could not read the measurement result: share the output below or run \"kediray dialtest\" over SSH.", "Impossible de lire le résultat de la mesure : partagez la sortie ci-dessous ou exécutez « kediray dialtest » en SSH."],
	"Ölçüm sonucu okunamadı: aşağıdaki çıktıyı paylaş ya da SSH ile \"kediray hunt 10\" çalıştır.": ["Could not read the measurement result: share the output below or run \"kediray hunt 10\" over SSH.", "Impossible de lire le résultat de la mesure : partagez la sortie ci-dessous ou exécutez « kediray hunt 10 » en SSH."],
	"Ölçüm sürüyor…": ["Measurement in progress…", "Mesure en cours…"],
	"Ölçüm çıktısı bulunamadı. SSH: kediray ": ["Measurement output not found. SSH: kediray ", "Sortie de mesure introuvable. SSH : kediray "],
	"Ölçüm çıktısı bulunamadı. SSH: kediray hunt 10": ["Measurement output not found. SSH: kediray hunt 10", "Sortie de mesure introuvable. SSH : kediray hunt 10"],
	"Önce lisans anahtarını yapıştır.": ["Paste the license key first.", "Collez d'abord la clé de licence."],
	"Önerilen: KAPALI. Kapalıyken Google (FCM) / Apple (APNs) bildirim bağlantıları tünelden gider; tünel heartbeat ile canlı kaldığı için bağlantı kesilmez. Açıkken bu bağlantılar operatörden direkt gider ve operatör boştaki bağlantıyı sessizce kesebilir: bildirimler gecikir ya da gelmez.": ["Recommended: OFF. When off, Google (FCM) / Apple (APNs) notification connections go through the tunnel; the connection isn't cut because the tunnel stays alive with a heartbeat. When on, these connections go directly through the operator and the operator may silently cut idle connections: notifications are delayed or don't arrive.", "Recommandé : DÉSACTIVÉ. Désactivé, les connexions de notification Google (FCM) / Apple (APNs) passent par le tunnel ; la connexion n'est pas coupée car le tunnel reste vivant grâce à un heartbeat. Activé, ces connexions passent directement par l'opérateur, qui peut couper silencieusement les connexions inactives : les notifications sont retardées ou n'arrivent pas."],
	"Önyükleme DNS": ["Bootstrap DNS", "DNS d'amorçage"],
	"Üretilen Xray yapılandırması (salt okunur)": ["Generated Xray configuration (read-only)", "Configuration Xray générée (lecture seule)"],
	"Üretilen tam config.json": ["Generated full config.json", "config.json complet généré"],
	"çalışıyor": ["running", "en marche"],
	"çevrimdışı ": ["offline ", "hors ligne "],
	"çözülemedi": ["could not resolve", "résolution impossible"],
	"çıkış kodu: ": ["exit code: ", "code de sortie : "],
	"ölçülemedi": ["could not measure", "mesure impossible"],
	"önceki güne göre": ["vs. the previous day", "par rapport à la veille"],
	"ör. Almanya WS": ["e.g. Germany WS", "ex. Allemagne WS"],
	"ör. discord.com": ["e.g. discord.com", "ex. discord.com"],
	"İkisi aynı anda trafiği yönetemez; KediRay kapalı bekliyor. \"Güvenli geçiş\" ": ["The two can't manage traffic at the same time; KediRay is waiting off. \"Safe switch\" ", "Les deux ne peuvent pas gérer le trafic en même temps ; KediRay attend, désactivé. « Basculement sûr » "],
	"İlk bayt": ["First byte", "Premier octet"],
	"İlki yanıt vermezse buraya düşer. auto = operatörün ikinci DNS sunucusu.": ["Falls back here if the first doesn't respond. auto = the operator's second DNS server.", "Repli ici si le premier ne répond pas. auto = le second serveur DNS de l'opérateur."],
	"İndirme": ["Download", "Réception"],
	"İndirme %": ["Download %", "Réception %"],
	"İndirme / Yükleme": ["Download / Upload", "Réception / Envoi"],
	"İnterneti direkt aç": ["Open the internet directly", "Ouvrir Internet en direct"],
	"İptal": ["Cancel", "Annuler"],
	"İptal edersen ya da seçilen bantla internet gelmezse de eski kilit geri yüklenir.": ["If you cancel, or if the internet doesn't come back with the selected band, the old lock is also restored.", "Si vous annulez, ou si Internet ne revient pas avec la bande choisie, l'ancien verrouillage est aussi rétabli."],
	"İptal ediliyor…": ["Cancelling…", "Annulation…"],
	"İpucu: v2rayNG'de sunucuya uzun bas → \"Tam yapılandırmayı panoya aktar\" ile JSON'u birebir alabilirsin.": ["Tip: in v2rayNG, long-press the server → \"Export full configuration to clipboard\" to get the JSON exactly.", "Astuce : dans v2rayNG, appuyez longuement sur le serveur → « Exporter la configuration complète vers le presse-papiers » pour obtenir le JSON à l'identique."],
	"İstatistikler": ["Statistics", "Statistiques"],
	"İşaretliyken VPN şimdi çalışır ve modem her açıldığında internet gelince kendiliğinden bağlanır (seçili sunucuya, \"Sunucu: Auto\" ise en hızlısına). İşareti kaldırırsan VPN durur ve açılışta başlamaz; internet doğrudan çıkar.": ["When ticked, the VPN runs now and connects by itself whenever the modem boots and the internet comes up (to the selected server, or the fastest if \"Server: Auto\"). If you untick it, the VPN stops and doesn't start at boot; the internet goes out directly.", "Cochée, le VPN fonctionne maintenant et se connecte tout seul à chaque démarrage du modem dès qu'Internet est disponible (au serveur sélectionné, ou au plus rapide si « Serveur : Auto »). Décochée, le VPN s'arrête et ne démarre pas au boot ; Internet sort en direct."],
	"İşaretliyse anonim kullanım sayısı gönderilir; işaretsizken hiçbir şey gönderilmez. Açıksa günde bir kez şunlar gönderilir: rastgele bir kurulum kimliği, KediRay sürümü ve uygulama adı. Sunucu bilgilerin, trafiğin, adın ya da IP adresin kaydedilmez. İstediğin an kapatabilirsin; kapatınca kimlik silinir. Ne gönderileceğini görmek için: kediray count show": ["When ticked, an anonymous usage count is sent; when unticked nothing is sent. When on, the following is sent once a day: a random install ID, the KediRay version and the app name. Your server details, traffic, name or IP address are not recorded. You can turn it off any time; when you do, the ID is deleted. To see what will be sent: kediray count show", "Cochée, un comptage anonyme d'utilisation est envoyé ; décochée, rien n'est envoyé. Activé, les éléments suivants sont envoyés une fois par jour : un identifiant d'installation aléatoire, la version de KediRay et le nom de l'appli. Vos informations de serveur, votre trafic, votre nom ou votre adresse IP ne sont pas enregistrés. Vous pouvez le désactiver à tout moment ; l'identifiant est alors supprimé. Pour voir ce qui sera envoyé : kediray count show"],
	"İşlem arka planda sürüyor; bu sayfa donarsa birkaç saniye bekle.": ["The operation continues in the background; if this page freezes, wait a few seconds.", "L'opération se poursuit en arrière-plan ; si cette page se fige, patientez quelques secondes."],
	"İşlem başarısız": ["Operation failed", "Échec de l'opération"],
	"Şebeke / 5G tipi": ["Network / 5G type", "Réseau / type 5G"],
	"Şifreleme": ["Encryption", "Chiffrement"],
	"Şimdi güncelle": ["Update now", "Mettre à jour maintenant"],
	"Şu an": ["Now", "Actuel"],
	"Şu an ": ["Now ", "Actuel "],
	"Şu an + toplamlar": ["Now + totals", "Actuel + totaux"],
	"Şu an bağlı olmayan cihazlar (rastgele MAC kullanan telefonlar kayıtlı yönüyle burada birikebilir)": ["Devices not currently connected (phones using random MACs may pile up here with their saved direction)", "Appareils actuellement non connectés (les téléphones à adresse MAC aléatoire peuvent s'accumuler ici avec leur sens enregistré)"],
	"Şu anki sunucuda sabitleniyor…": ["Pinning to the current server…", "Épinglage sur le serveur actuel…"],
	"↓ cihaza gelen (indirme), ↑ cihazdan giden (yükleme). VPN ve direkt trafik birlikte sayılır. Sayaçlar modem yeniden başlasa da saklanır; donanım hızlandırma (NSS) açıksa direkt giden büyük akışlar eksik görünebilir.": ["↓ incoming to the device (download), ↑ outgoing from the device (upload). VPN and direct traffic are counted together. Counters are kept even if the modem restarts; if hardware acceleration (NSS) is on, large direct outgoing flows may appear incomplete.", "↓ reçu par l'appareil (réception), ↑ envoyé par l'appareil (envoi). Le trafic VPN et direct est compté ensemble. Les compteurs sont conservés même si le modem redémarre ; si l'accélération matérielle (NSS) est activée, les gros flux directs sortants peuvent paraître incomplets."],
	"↓ cihaza gelen (indirme), ↑ cihazdan giden (yükleme). Çubuk, cihazın bugünkü payı. VPN ve direkt trafik birlikte sayılır. Sayaçlar modem yeniden başlasa da saklanır; donanım hızlandırma (NSS) açıksa direkt giden büyük akışlar eksik görünebilir.": ["↓ incoming to the device (download), ↑ outgoing from the device (upload). The bar is the device's share today. VPN and direct traffic are counted together. Counters are kept even if the modem restarts; if hardware acceleration (NSS) is on, large direct outgoing flows may appear incomplete.", "↓ reçu par l'appareil (réception), ↑ envoyé par l'appareil (envoi). La barre représente la part de l'appareil aujourd'hui. Le trafic VPN et direct est compté ensemble. Les compteurs sont conservés même si le modem redémarre ; si l'accélération matérielle (NSS) est activée, les gros flux directs sortants peuvent paraître incomplets."],
	"↔ Satırları kaydırma": ["↔ Don't wrap lines", "↔ Ne pas renvoyer à la ligne"],
	"↵ Uzun satırları kaydır": ["↵ Wrap long lines", "↵ Renvoyer les longues lignes"],
	"↻ Aboneliği güncelle": ["↻ Update subscription", "↻ Mettre à jour l'abonnement"],
	"⇄ Güvenli geçiş": ["⇄ Safe switch", "⇄ Basculement sûr"],
	"⇆ Biçimlendir (girintiyi düzelt)": ["⇆ Format (fix indentation)", "⇆ Formater (corriger l'indentation)"],
	"⏱ Hız testi": ["⏱ Speed test", "⏱ Test de vitesse"],
	"⚙ Düzenle": ["⚙ Edit", "⚙ Modifier"],
	"⚡ Ping ölç": ["⚡ Measure ping", "⚡ Mesurer le ping"],
	"⚡ Tümünü ölç": ["⚡ Measure all", "⚡ Tout mesurer"],
	"✅ Geçerli JSON": ["✅ Valid JSON", "✅ JSON valide"],
	"✅ Yazım, alan ve Xray denetimi: hata yok.": ["✅ Syntax, field and Xray check: no errors.", "✅ Vérification de la syntaxe, des champs et d'Xray : aucune erreur."],
	"✓ Ayarları denetle": ["✓ Check settings", "✓ Vérifier les réglages"],
	"❌ Satır ": ["❌ Line ", "❌ Ligne "],
	"⤢ Büyüt / küçült": ["⤢ Enlarge / shrink", "⤢ Agrandir / réduire"],
	"🔎 Takılma avı": ["🔎 Stall hunt", "🔎 Chasse aux blocages"],
	"🔒 Sertifikayı sabitle": ["🔒 Pin certificate", "🔒 Épingler le certificat"],
	"🚀 En hızlıyı bul ve bağlan": ["🚀 Find the fastest and connect", "🚀 Trouver le plus rapide et se connecter"],
	"🤝 Sunucu el sıkışması": ["🤝 Server handshake", "🤝 Poignée de main serveur"],
	"Direkt yap": ["Make direct", "Passer en direct"],
	"Sil": ["Delete", "Supprimer"],
	"Kapat": ["Close", "Fermer"],
	"Kaydet": ["Save", "Enregistrer"],
	"Ekle": ["Add", "Ajouter"],
	"Bul": ["Find", "Trouver"],
	"Tamam": ["OK", "OK"],
	"Devam": ["Continue", "Continuer"],
	"Durdur": ["Stop", "Arrêter"],
	"Durdu": ["Stopped", "Arrêté"],
	"Engelle": ["Block", "Bloquer"],
	"Temizle": ["Clear", "Effacer"],
	"Evet": ["Yes", "Oui"],
	"Hata": ["Error", "Erreur"],
	"Hatalar": ["Errors", "Erreurs"],
	"Hepsi": ["All", "Tous"],
	"Genel": ["General", "Général"],
	"Durum": ["Status", "État"],
	"Yok": ["None", "Aucun"],
	"Toplam": ["Total", "Total"],
	"Toplam ": ["Total ", "Total "],
	"Toplam: ": ["Total: ", "Total : "],
	"Ortalama": ["Average", "Moyenne"],
	"Saatlik ortalama": ["Hourly average", "Moyenne horaire"],
	"Bu ay": ["This month", "Ce mois"],
	"Bu hafta": ["This week", "Cette semaine"],
	"Bu ay ortalama": ["This month's average", "Moyenne du mois"],
	"Bu ay: ": ["This month: ", "Ce mois : "],
	"Bu ay ↓ ": ["This month ↓ ", "Ce mois ↓ "],
	"Aylar": ["Months", "Mois"],
	"Adet": ["Count", "Nombre"],
	"Ad": ["Name", "Nom"],
	"Adres": ["Address", "Adresse"],
	"Bant": ["Band", "Bande"],
	"Bilgi": ["Info", "Info"],
	"Cihaz": ["Device", "Appareil"],
	"Gecikme": ["Latency", "Latence"],
	"Hedef": ["Target", "Cible"],
	"Mod": ["Mode", "Mode"],
	"Otomatik": ["Auto", "Auto"],
	"Parola": ["Password", "Mot de passe"],
	"Protokol": ["Protocol", "Protocole"],
	"Sinyal": ["Signal", "Signal"],
	"Skor": ["Score", "Score"],
	"Sunucu": ["Server", "Serveur"],
	"Sunucu yok": ["No server", "Aucun serveur"],
	"Tema": ["Theme", "Thème"],
	"Tema: ": ["Theme: ", "Thème : "],
	"Koyu": ["Dark", "Sombre"],
	"Mavi": ["Blue", "Bleu"],
	"Mor": ["Purple", "Violet"],
	"Pembe": ["Pink", "Rose"],
	"Turuncu": ["Orange", "Orange"],
	"Turkuaz": ["Turquoise", "Turquoise"],
	"Trafik": ["Traffic", "Trafic"],
	"Abonelik": ["Subscription", "Abonnement"],
	"Abonelik adresleri": ["Subscription URLs", "URL d'abonnement"],
	"Tepe: ": ["Peak: ", "Pic : "],
	"Kaydedildi": ["Saved", "Enregistré"],
	"Kaydedilemedi": ["Could not save", "Enregistrement impossible"],
	"Silinemedi": ["Could not delete", "Suppression impossible"],
	"Siliniyor…": ["Deleting…", "Suppression…"],
	"Ekleniyor…": ["Adding…", "Ajout…"],
	"Eklenemedi: ": ["Could not add: ", "Ajout impossible : "],
	"Denetleniyor…": ["Checking…", "Vérification…"],
	"Denetlenemedi: ": ["Could not check: ", "Vérification impossible : "],
	"Yedek al": ["Back up", "Sauvegarder"],
	"Yedek yok": ["No backup", "Aucune sauvegarde"],
	"Yedek indirildi: ": ["Backup downloaded: ", "Sauvegarde téléchargée : "],
	"Yeni sunucu": ["New server", "Nouveau serveur"],
	"Yeni uygulama ekle": ["Add new app", "Ajouter une nouvelle appli"],
	"Yeniden denetle": ["Check again", "Revérifier"],
	"Oturum indirilen": ["Session downloaded", "Reçu (session)"],
	"Lisans": ["License", "Licence"],
	"Lisans gerekli": ["License required", "Licence requise"],
	"Lisans gerekli. ": ["License required. ", "Licence requise. "],
	"Otomatik kur": ["Install automatically", "Installer automatiquement"],
	"Beni destekle": ["Support me", "Soutenez-moi"],
	"Bitti": ["Done", "Terminé"],
	"Bitince en iyi bant kilitlenir. ": ["When it finishes, the best band is locked. ", "À la fin, la meilleure bande est verrouillée. "],
	"Bilinmeyen hata: ": ["Unknown error: ", "Erreur inconnue : "],
	"Bir ad yaz.": ["Type a name.", "Saisissez un nom."],
	"Denenecek bantlar": ["Bands to try", "Bandes à tester"],
	"DNS modu": ["DNS mode", "Mode DNS"],
	"En alta git": ["Jump to bottom", "Aller en bas"],
	"En iyisini otomatik uygula": ["Apply the best automatically", "Appliquer automatiquement la meilleure"],
	"HTTP gizleme": ["HTTP obfuscation", "Obfuscation HTTP"],
	"Hataya git": ["Go to error", "Aller à l'erreur"],
	"Hesap yok": ["No account", "Aucun compte"],
	"Listede olmayan cihazlar": ["Devices not in the list", "Appareils absents de la liste"],
	"Metin2 DNS testi": ["Metin2 DNS test", "Test DNS Metin2"],
	"Modem IMEI: ": ["Modem IMEI: ", "IMEI du modem : "],
	"Modemin bant bilgisi okunuyor…": ["Reading the modem's band info…", "Lecture des infos de bande du modem…"],
	"Sadece liste VPN": ["Only the list uses VPN", "Seule la liste utilise le VPN"],
	"Sertifika sabitleniyor…": ["Pinning certificate…", "Épinglage du certificat…"],
	"Son denetleme: ": ["Last check: ", "Dernière vérification : "],
	"Sunucu IP'si: ": ["Server IP: ", "IP du serveur : "],
	"Sunucu bilgilerini gizle": ["Hide server info", "Masquer les infos du serveur"],
	"Sunucu ekle — link veya JSON": ["Add server — link or JSON", "Ajouter un serveur — lien ou JSON"],
	"Trafik yakalama modu": ["Traffic capture mode", "Mode de capture du trafic"],
	"Uygulamalar — VPN mi, Direkt mi?": ["Apps — VPN or Direct?", "Applis — VPN ou Direct ?"],
	"VPN durduruluyor…": ["Stopping VPN…", "Arrêt du VPN…"],
	"VPN motoru": ["VPN engine", "Moteur VPN"],
	"VPN toplam": ["VPN total", "Total VPN"],
	"Direkt toplam": ["Direct total", "Total direct"],
	"Vurgu rengi": ["Accent color", "Couleur d'accent"],
	"WebSocket erken veri": ["WebSocket early data", "Early data WebSocket"],
	"XHTTP modu": ["XHTTP mode", "Mode XHTTP"],
	"Kendi rengin: ": ["Your own color: ", "Votre couleur : "],
	"IP ve MAC adreslerini gizle": ["Hide IP and MAC addresses", "Masquer les adresses IP et MAC"],
	"Reklam engelleme": ["Ad blocking", "Blocage des publicités"],
	"Eklenecek uygulama:": ["App to add to:", "Appli à laquelle ajouter :"],
	"KediRay VPN — Trafik": ["KediRay VPN — Traffic", "KediRay VPN — Trafic"],
	"KediRay — Ayarlar": ["KediRay — Settings", "KediRay — Paramètres"],
	"hata": ["error", "erreur"],
	"bilgi": ["info", "info"],
	"ilgili": ["related", "associé"],
	"ilgili hizmet": ["related service", "service associé"],
	"sadece hatalar": ["errors only", "erreurs seulement"],
	"listede": ["in the list", "dans la liste"],
	"yok": ["none", "aucun"],
	"evet": ["yes", "oui"],
	"Aç: ": ["Enable: ", "Activer : "],
	"\" silinsin mi?": ["\" — delete it?", "\" — la supprimer ?"],
	"· Bu ay: ": ["· This month: ", "· Ce mois : "],
	"· Direkt %": ["· Direct %", "· Direct %"],
	"· Mod: ": ["· Mode: ", "· Mode : "],
	"· Toplam ↓ ": ["· Total ↓ ", "· Total ↓ "],
	"· Yakalama: ": ["· Capture: ", "· Capture : "],
	"' veya ']' bekleniyordu": ["' or ']' expected", "',' ou ']' attendu"],
	"Anahtardan sonra ':' bekleniyordu": ["':' expected after the key", "':' attendu après la clé"],
	"ay ort. ": ["month avg. ", "moy. mensuelle "],
	"bu ay ": ["this month ", "ce mois "],
	"ort. ": ["avg. ", "moy. "],
	"otomatik": ["automatic", "automatique"],
	"verisi olan aylar": ["months with data", "mois avec données"],
	"hev-socks5-tunnel yolu": ["hev-socks5-tunnel path", "Chemin de hev-socks5-tunnel"],
	"🐢 Sayfa gecikmesi": ["🐢 Page latency", "🐢 Latence des pages"],
	"✓ Bitti": ["✓ Done", "✓ Terminé"],
	"Kontrol Paneli": ["Dashboard", "Tableau de bord"],
	"Ayarlar": ["Settings", "Paramètres"],
	"Direkt": ["Direct", "Direct"],
	"Direkt ": ["Direct ", "Direct "],
	"Direkt: ": ["Direct: ", "Direct : "],
	"  direkt": ["  direct", "  direct"],
	"Direkt internet": ["Direct internet", "Internet direct"],
	" Direkt internet": [" Direct internet", " Internet direct"],
	" durdurulsun mu?": [" — stop it?", " — l'arrêter ?"],
	" durduruluyor…": [" stopping…", " arrêt…"],
	" silinsin mi?": [" — delete it?", " — le supprimer ?"],
	"durduruluyor…": ["stopping…", "arrêt…"],
	"durdurulsun mu?": ["— stop it?", "— l'arrêter ?"],
	"silinsin mi?": ["— delete it?", "— le supprimer ?"],
	"ve ": ["and ", "et "],
	"ve port ": [" and port ", " et port "],
	"Son 30 gün trafik (VPN ve Direkt)": ["Last 30 days traffic (VPN and Direct)", "Trafic des 30 derniers jours (VPN et Direct)"],
	"Aylık trafik": ["Monthly traffic", "Trafic mensuel"],
	"Günlük trafik": ["Daily traffic", "Trafic quotidien"],
	"Sistem": ["System", "Système"],
	"Hizmetler": ["Services", "Services"],
	"Ağ": ["Network", "Réseau"],
	"Oturumu Kapat": ["Log out", "Déconnexion"],
	"YENİLENİYOR": ["REFRESHING", "ACTUALISATION"],
	"Tools": ["Tools", "Outils"],
	"Xray DNS portu": ["Xray DNS port", "Port DNS Xray"],
	"Xray API portu": ["Xray API port", "Port API Xray"],
	"Yol": ["Path", "Chemin"],
	"bilinmeyen hata": ["unknown error", "erreur inconnue"],
	"UUID-BURAYA": ["UUID-HERE", "UUID-ICI"],
	" sunucu)": [" servers)", " serveurs)"],
	"Kurulum hata ile bitti (kod ": ["Installation finished with an error (code ", "L'installation s'est terminée avec une erreur (code "],
	"servis: ": ["service: ", "service : "],
	"Hata ile bitti (": ["Finished with an error (", "Terminé avec une erreur ("],
	"Uygulamalar (": ["Apps (", "Applications ("],
	" hata": [" errors", " erreurs"],
	" bilgi": [" info", " infos"],
	"Bekleme / aday (sn)": ["Wait / candidate (s)", "Attente / candidat (s)"],
	"Google DoH (direkt)": ["Google DoH (direct)", "Google DoH (direct)"],
	"Direkt DNS (yedek)": ["Direct DNS (backup)", "DNS direct (secours)"],
	"Cloudflare DoH (direkt)": ["Cloudflare DoH (direct)", "Cloudflare DoH (direct)"],
	"WebSocket heartbeat (sn)": ["WebSocket heartbeat (s)", "WebSocket heartbeat (s)"],
	"TCP keepalive (sn)": ["TCP keepalive (s)", "TCP keepalive (s)"],
	"Yakalama (redirect/TPROXY) portu": ["Capture (redirect/TPROXY) port", "Port de capture (redirect/TPROXY)"],
	"Yol (path)": ["Path", "Chemin (path)"],
	"Parmak izi (uTLS)": ["Fingerprint (uTLS)", "Empreinte (uTLS)"],
	"oyun/uygulama?": ["game/app?", "jeu/appli ?"],
	"TUN (hepsi hev-socks5-tunnel)": ["TUN (everything via hev-socks5-tunnel)", "TUN (tout via hev-socks5-tunnel)"],
	"Redirect (sadece TCP)": ["Redirect (TCP only)", "Redirect (TCP seulement)"],
	"Toplam (kurulumdan beri): ": ["Total (since install): ", "Total (depuis l'installation) : "],
	"Sunucular (": ["Servers (", "Serveurs ("],
	"Cihazlar (": ["Devices (", "Appareils ("],
	"(ilk ": ["(first ", "(premiers "],
	" trafik (": [" traffic (", " trafic ("],
	" ay)": [" mo)", " mois)"],
	"VPN / Direkt": ["VPN / Direct", "VPN / Direct"],
	"Bağlantı karşı taraftan sıfırlandı": ["Connection reset by peer", "Connexion réinitialisée par le correspondant"],
	"Operatör ya da ağ, VPN sunucusuna açılan bağlantıyı kesti. Ara sıra olursa normaldir (mobil hatlarda sık görülür). Sık tekrarlanıyorsa sunucunun IP/SNI'si engelleniyor olabilir: farklı port, SNI ya da sunucu dene. Oyun/arama bu anlarda koparsa o uygulamayı \"Direkt\" yap.": ["The operator or network cut the connection opened to the VPN server. Occasional occurrences are normal (common on mobile lines). If it repeats often, the server's IP/SNI may be blocked: try a different port, SNI or server. If games/calls drop at those moments, set that app to \"Direct\".", "L'opérateur ou le réseau a coupé la connexion ouverte vers le serveur VPN. Des occurrences occasionnelles sont normales (fréquent sur les lignes mobiles). Si cela se répète souvent, l'IP/SNI du serveur est peut-être bloquée : essayez un autre port, SNI ou serveur. Si les jeux/appels coupent à ces moments, réglez cette appli sur « Direct »."],
	"Sunucuya ulaşılamadı (zaman aşımı)": ["Could not reach the server (timeout)", "Serveur injoignable (délai dépassé)"],
	"Sunucu kapalı, IP'si değişmiş ya da hat bu adresi engelliyor olabilir. Kontrol Paneli'nden \"Ping\" ile ölç; çalışmıyorsa aboneliği güncelle ya da başka sunucu seç.": ["The server may be down, its IP may have changed, or the line may be blocking this address. Measure with \"Ping\" from the Dashboard; if it doesn't work, update the subscription or pick another server.", "Le serveur est peut-être éteint, son IP a peut-être changé, ou la ligne bloque cette adresse. Mesurez avec « Ping » depuis le tableau de bord ; si cela ne fonctionne pas, mettez à jour l'abonnement ou choisissez un autre serveur."],
	"Sunucu bağlantıyı reddetti": ["The server refused the connection", "Le serveur a refusé la connexion"],
	"Sunucu açık ama o portta dinleyen yok. x-ui'de inbound'un açık ve portun doğru olduğunu kontrol et.": ["The server is up but nothing is listening on that port. Check in x-ui that the inbound is enabled and the port is correct.", "Le serveur est actif mais rien n'écoute sur ce port. Vérifiez dans x-ui que l'inbound est activé et que le port est correct."],
	"Direkt DNS (DoH) yanıt vermedi": ["Direct DNS (DoH) did not respond", "Le DNS direct (DoH) n'a pas répondu"],
	"Türkiye'ye direkt çıkan adresler için kullanılan DoH sunucusuna ulaşılamadı; 5G/mobil hatlarda sık olur. Adres yedek DNS ile çözülür ama sorgu birkaç saniye gecikir. Sürekli oluyorsa Ayarlar → DNS → \"Direkt DNS (yedek)\" zaten devrede; ilk sırayı değiştirmek için \"Direkt DNS\" alanına https+local://8.8.8.8/dns-query yaz.": ["The DoH server used for addresses that go directly to Turkey could not be reached; this is common on 5G/mobile lines. The address is resolved with the backup DNS but the query is delayed by a few seconds. If it keeps happening, Settings → DNS → \"Direct DNS (backup)\" is already active; to change the first one, enter https+local://8.8.8.8/dns-query in the \"Direct DNS\" field.", "Le serveur DoH utilisé pour les adresses qui sortent directement vers la Turquie est injoignable ; fréquent sur les lignes 5G/mobiles. L'adresse est résolue avec le DNS de secours mais la requête est retardée de quelques secondes. Si cela persiste, Paramètres → DNS → « DNS direct (secours) » est déjà actif ; pour changer le premier, saisissez https+local://8.8.8.8/dns-query dans le champ « DNS direct »."],
	"Sunucu el sıkışma sırasında bağlantıyı kapattı (EOF)": ["The server closed the connection during the handshake (EOF)", "Le serveur a fermé la connexion pendant la poignée de main (EOF)"],
	"VPN sunucusu ya da önündeki ters vekil/CDN, bağlantıyı daha el sıkışma bitmeden kapattı. Sık oluyorsa: sunucunun WebSocket path/host değerlerini x-ui ile karşılaştır, sunucu yükünü kontrol et, ya da ikinci bir sunucu ekle (biri takılınca otomatik diğerine geçer). Bu anlarda açılan yeni bağlantılar başarısız olur; telefonun bildirim bağlantısı da o an kopabilir.": ["The VPN server, or the reverse proxy/CDN in front of it, closed the connection before the handshake finished. If it happens often: compare the server's WebSocket path/host values with x-ui, check the server load, or add a second server (when one stalls it switches to the other automatically). New connections opened at those moments fail; the phone's notification connection may also drop then.", "Le serveur VPN, ou le proxy inverse/CDN devant lui, a fermé la connexion avant la fin de la poignée de main. Si cela arrive souvent : comparez les valeurs WebSocket path/host du serveur avec x-ui, vérifiez la charge du serveur, ou ajoutez un second serveur (quand l'un se bloque, il bascule automatiquement sur l'autre). Les nouvelles connexions ouvertes à ces moments échouent ; la connexion de notification du téléphone peut aussi couper à cet instant."],
	"DNS sorgusu zamanında yanıtlanmadı": ["DNS query was not answered in time", "La requête DNS n'a pas reçu de réponse à temps"],
	"Tünel o an yavaş ya da takılı. \"Tünel takılırsa önbellekten yanıt ver\" açıkken daha önce çözülmüş adresler etkilenmez. Sık görülüyorsa Ayarlar → DNS'te \"Cloudflare DoH\" seçmeyi dene.": ["The tunnel is slow or stuck at that moment. With \"Answer from cache if the tunnel stalls\" on, addresses resolved earlier are not affected. If you see it often, try choosing \"Cloudflare DoH\" under Settings → DNS.", "Le tunnel est lent ou bloqué à cet instant. Avec « Répondre depuis le cache si le tunnel se bloque » activé, les adresses déjà résolues ne sont pas affectées. Si cela arrive souvent, essayez de choisir « Cloudflare DoH » dans Paramètres → DNS."],
	"DNS-over-TCP bağlantısı kapandı": ["DNS-over-TCP connection closed", "Connexion DNS-over-TCP fermée"],
	"Karşı taraf boştaki DNS bağlantısını kapattı. Bu satır görünüyorsa \"Uzak DNS\" TCP'dedir: Ayarlar → DNS → Uzak DNS → \"Cloudflare DoH\" seç. Gerçek hatta doğrulandı: TCP'de bağlantı düşünce sorgu ölüyor ve sayfa askıda kalıyor, DoH kendi içinde yeniden deniyor.": ["The other side closed the idle DNS connection. If you see this line, \"Remote DNS\" is on TCP: choose Settings → DNS → Remote DNS → \"Cloudflare DoH\". Verified on a real line: with TCP, when the connection drops the query dies and the page hangs; DoH retries on its own.", "L'autre partie a fermé la connexion DNS inactive. Si vous voyez cette ligne, « DNS distant » est en TCP : choisissez Paramètres → DNS → DNS distant → « Cloudflare DoH ». Vérifié sur une ligne réelle : avec TCP, quand la connexion tombe, la requête meurt et la page se bloque ; DoH réessaie de lui-même."],
	"Sunucunun sertifikası değişmiş": ["The server's certificate has changed", "Le certificat du serveur a changé"],
	"Sabitlenen sertifika artık sunucuda değil (panel/sertifika yenilenmiş). KediRay bir sonraki başlatmada otomatik yeniden sabitler; hemen düzeltmek için panelde Bağlı sunucu → \"🔒 Sertifikayı sabitle\" (ya da: kediray pin)": ["The pinned certificate is no longer on the server (panel/certificate renewed). KediRay re-pins automatically at the next start; to fix it right away, on the panel use Connected server → \"🔒 Pin certificate\" (or: kediray pin)", "Le certificat épinglé n'est plus sur le serveur (panneau/certificat renouvelé). KediRay le ré-épingle automatiquement au prochain démarrage ; pour corriger immédiatement, dans le panneau utilisez Serveur connecté → « 🔒 Épingler le certificat » (ou : kediray pin)"],
	"Sunucunun sertifikası doğrulanamadı": ["The server's certificate could not be verified", "Le certificat du serveur n'a pas pu être vérifié"],
	"Sunucu kendinden imzalı ya da başka ada ait sertifika kullanıyor. Sunucuyu düzenle → \"Sertifikayı otomatik sabitle\" işaretle; KediRay sertifikayı sabitler.": ["The server uses a self-signed certificate or one belonging to another name. Edit the server → tick \"Pin the certificate automatically\"; KediRay pins the certificate.", "Le serveur utilise un certificat auto-signé ou appartenant à un autre nom. Modifiez le serveur → cochez « Épingler automatiquement le certificat » ; KediRay épingle le certificat."],
	"REALITY el sıkışması başarısız": ["REALITY handshake failed", "Échec de la poignée de main REALITY"],
	"Public key / short id / SNI sunucuyla uyuşmuyor. Linki x-ui'den yeniden kopyalayıp sunucuyu düzenle.": ["Public key / short id / SNI don't match the server. Copy the link again from x-ui and edit the server.", "La clé publique / short id / SNI ne correspond pas au serveur. Recopiez le lien depuis x-ui et modifiez le serveur."],
	"WebSocket el sıkışması reddedildi": ["WebSocket handshake rejected", "Poignée de main WebSocket rejetée"],
	"Path ya da Host yanlış, veya sunucunun önündeki CDN/ters vekil isteği geri çevirdi. Linkteki path ve host değerlerini x-ui ile karşılaştır.": ["The path or Host is wrong, or the CDN/reverse proxy in front of the server rejected the request. Compare the path and host values in the link with x-ui.", "Le path ou le Host est incorrect, ou le CDN/proxy inverse devant le serveur a rejeté la requête. Comparez les valeurs path et host du lien avec x-ui."],
	"TLS el sıkışması başarısız": ["TLS handshake failed", "Échec de la poignée de main TLS"],
	"SNI/ALPN sunucuyla uyuşmuyor, sunucu TLS kullanmıyor ya da operatör bu el sıkışmasını engelliyor. Linkteki security/SNI ayarını kontrol et.": ["SNI/ALPN doesn't match the server, the server doesn't use TLS, or the operator is blocking this handshake. Check the security/SNI setting in the link.", "SNI/ALPN ne correspond pas au serveur, le serveur n'utilise pas TLS, ou l'opérateur bloque cette poignée de main. Vérifiez le paramètre security/SNI dans le lien."],
	"Kullanıcı (UUID/parola) geçersiz": ["User (UUID/password) invalid", "Utilisateur (UUID/mot de passe) invalide"],
	"Hesap sunucudan silinmiş ya da süresi dolmuş olabilir. x-ui'de kullanıcının açık olduğunu kontrol et, aboneliği güncelle.": ["The account may have been deleted from the server or expired. Check in x-ui that the user is enabled, and update the subscription.", "Le compte a peut-être été supprimé du serveur ou a expiré. Vérifiez dans x-ui que l'utilisateur est activé, et mettez à jour l'abonnement."],
	"Hiçbir bağlanma denemesi başarılı olmadı": ["No connection attempt succeeded", "Aucune tentative de connexion n'a réussi"],
	"Asıl sebep yukarıdaki ayrıntıda (en sağdaki kısım). Sunucuya erişim yoksa internet VPN'den gidemez.": ["The real cause is in the detail above (the rightmost part). If there's no access to the server, the internet can't go through the VPN.", "La vraie cause se trouve dans le détail ci-dessus (la partie la plus à droite). Sans accès au serveur, Internet ne peut pas passer par le VPN."],
	"Açık dosya sınırı aşıldı": ["Open file limit exceeded", "Limite de fichiers ouverts dépassée"],
	"Modemi yeniden başlat; sürekli oluyorsa bağlantı sayısı çok yüksek demektir.": ["Restart the modem; if it keeps happening, the number of connections is too high.", "Redémarrez le modem ; si cela persiste, le nombre de connexions est trop élevé."],
	"Xray bir ayarı kabul etmedi": ["Xray did not accept a setting", "Xray n'a pas accepté un réglage"],
	"Kontrol Paneli → \"✓ Ayarları denetle\" hatalı alanı ve satırı gösterir. Son değiştirdiğin sunucu/kuralı düzelt.": ["Dashboard → \"✓ Check settings\" shows the faulty field and line. Fix the server/rule you changed last.", "Tableau de bord → « ✓ Vérifier les réglages » indique le champ et la ligne en cause. Corrigez le dernier serveur/règle modifié."],
	"Kontrol Paneli → \"✓ Ayarları denetle\" ile hatalı sunucuyu bul.": ["Dashboard → \"✓ Check settings\" to find the faulty server.", "Tableau de bord → « ✓ Vérifier les réglages » pour trouver le serveur en cause."],
	"UDP tüneli (hev) başlamadı": ["UDP tunnel (hev) did not start", "Le tunnel UDP (hev) n'a pas démarré"],
	"hev-socks5-tunnel kurulu mu? SSH: apk add hev-socks5-tunnel kmod-tun (opkg ile de olur). Olmazsa Ayarlar → Trafik yakalama → TPROXY seç.": ["Is hev-socks5-tunnel installed? SSH: apk add hev-socks5-tunnel kmod-tun (opkg also works). If it doesn't work, choose Settings → Traffic capture → TPROXY.", "hev-socks5-tunnel est-il installé ? SSH : apk add hev-socks5-tunnel kmod-tun (opkg fonctionne aussi). Sinon, choisissez Paramètres → Capture du trafic → TPROXY."],
	"Güvenlik duvarı kuralı yüklenemedi": ["Firewall rule could not be loaded", "La règle du pare-feu n'a pas pu être chargée"],
	"SSH'ta \"fw4 check\" çalıştır: /etc/nftables.d içindeki bozuk bir dosya tüm güvenlik duvarını durdurur.": ["Run \"fw4 check\" over SSH: a broken file in /etc/nftables.d stops the whole firewall.", "Exécutez « fw4 check » en SSH : un fichier corrompu dans /etc/nftables.d arrête tout le pare-feu."],
	"Sunucunun sertifikası alınamadı": ["The server's certificate could not be fetched", "Le certificat du serveur n'a pas pu être récupéré"],
	"openssl-util kurulu mu (apk add openssl-util)? Sunucu açık ve adres doğru mu?": ["Is openssl-util installed (apk add openssl-util)? Is the server up and the address correct?", "openssl-util est-il installé (apk add openssl-util) ? Le serveur est-il actif et l'adresse correcte ?"],
	"Abonelik güncellenemedi": ["Subscription could not be updated", "L'abonnement n'a pas pu être mis à jour"],
	"Abonelik linkini tarayıcıda açıp çalıştığını kontrol et; VPN kapalıyken de erişilebilmeli.": ["Open the subscription link in a browser and check that it works; it should also be reachable while the VPN is off.", "Ouvrez le lien d'abonnement dans un navigateur et vérifiez qu'il fonctionne ; il doit aussi être accessible quand le VPN est désactivé."],
	"UDP tüneli Xray'e bağlanamadı": ["The UDP tunnel could not connect to Xray", "Le tunnel UDP n'a pas pu se connecter à Xray"],
	"Xray çalışmıyor ya da SOCKS portu değişmiş. VPN'i yeniden başlat; sürmezse Günlük'teki Xray hatalarına bak.": ["Xray isn't running or the SOCKS port changed. Restart the VPN; if it persists, look at the Xray errors in the Log.", "Xray ne fonctionne pas ou le port SOCKS a changé. Redémarrez le VPN ; si cela persiste, consultez les erreurs Xray dans le Journal."],
	"Xray çekirdeği yok": ["Xray core is missing", "Le cœur Xray est absent"],
	"Sunucu seçimi uygulanamadı": ["Server selection could not be applied", "La sélection du serveur n'a pas pu être appliquée"],
	"Xray yanıt vermiyor; VPN'i yeniden başlat.": ["Xray isn't responding; restart the VPN.", "Xray ne répond pas ; redémarrez le VPN."],
	"UDP tüneli": ["UDP tunnel", "Tunnel UDP"],
	"Sunucu bağlantısı": ["Server connection", "Connexion au serveur"],
	"Sağlık ölçümü": ["Health check", "Contrôle de santé"],
	"Giriş": ["Inbound", "Entrée"],
	"Yönlendirme": ["Routing", "Routage"],
	"Modem hiçbir adresi çözemedi: ": ["The modem could not resolve any address: ", "Le modem n'a pu résoudre aucune adresse : "],
	" adresin hepsi ad çözümleme aşamasında zaman aşımına düştü (curl \"DNS 0 ms\" yazar, bu iyi demek değil).": [" addresses all timed out in the name-resolution stage (curl prints \"DNS 0 ms\", which doesn't mean good).", " adresses ont toutes dépassé le délai à l'étape de résolution de noms (curl affiche « DNS 0 ms », ce qui ne veut pas dire que c'est bon)."],
	"En olası sebep: DNS modu \"Tünelden\" ve tünel şu an bağlantıyı düşürüyor — çözümleme de tünelden gittiği için modem hiçbir adı çözemez. Günlükte \"Sunucu el sıkışma sırasında bağlantıyı kapattı (EOF)\" varsa sebep budur.": ["Most likely cause: DNS mode is \"Via tunnel\" and the tunnel is currently dropping the connection — since resolution also goes through the tunnel, the modem can't resolve any name. If the Log shows \"The server closed the connection during the handshake (EOF)\", that's the cause.", "Cause la plus probable : le mode DNS est « Via le tunnel » et le tunnel coupe actuellement la connexion — comme la résolution passe aussi par le tunnel, le modem ne peut résoudre aucun nom. Si le Journal affiche « Le serveur a fermé la connexion pendant la poignée de main (EOF) », c'est la cause."],
	"Hemen çözüm: Ayarlar → DNS → \"Direkt\" moduna al (sorgular tünelden bağımsız çözülür). Kalıcı çözüm: sunucunun el sıkışmayı neden düşürdüğünü bul — \"kediray dialtest\".": ["Quick fix: switch Settings → DNS → to \"Direct\" mode (queries are resolved independently of the tunnel). Permanent fix: find out why the server drops the handshake — \"kediray dialtest\".", "Solution rapide : passez Paramètres → DNS → en mode « Direct » (les requêtes sont résolues indépendamment du tunnel). Solution durable : trouvez pourquoi le serveur coupe la poignée de main — « kediray dialtest »."],
	" adres çözümlenemedi (DNS aşamasında zaman aşımı).": [" addresses could not be resolved (timeout in the DNS stage).", " adresses n'ont pas pu être résolues (délai dépassé à l'étape DNS)."],
	"DNS süresi ölçülemedi.": ["DNS time could not be measured.", "Le temps DNS n'a pas pu être mesuré."],
	"DNS çok yavaş (": ["DNS is very slow (", "DNS très lent ("],
	" ms): sayfa daha açılmadan bekleniyor. Ayarlar → DNS → \"Direkt\" modunu ve direkt DNS yedeğini dene.": [" ms): the page is waited on before it even opens. Try Settings → DNS → \"Direct\" mode and the direct DNS backup.", " ms) : on attend avant même que la page ne s'ouvre. Essayez Paramètres → DNS → mode « Direct » et le DNS direct de secours."],
	" ms): ilk açılışta hissedilir.": [" ms): noticeable on first load.", " ms) : perceptible à la première ouverture."],
	" adres VPN üzerinden hiç açılmadı: sunucu bağlantısı kopuyor (Günlük'e bak, \"kediray dialtest\" ile ölç).": [" addresses never opened through the VPN: the server connection is dropping (see the Log, measure with \"kediray dialtest\").", " adresses ne se sont jamais ouvertes via le VPN : la connexion au serveur coupe (voir le Journal, mesurez avec « kediray dialtest »)."],
	"VPN ek gecikmesi hesaplanamadı: ölçümlerin bir kısmı tamamlanmadı.": ["VPN extra latency could not be calculated: some of the measurements did not complete.", "Le surcoût de latence du VPN n'a pas pu être calculé : certaines mesures ne sont pas terminées."],
	"VPN sayfayı ": ["VPN delays the page by ", "Le VPN retarde la page de "],
	" ms geciktiriyor: sunucu uzak ya da yükte; başka sunucu dene.": [" ms: the server is far away or under load; try another server.", " ms : le serveur est éloigné ou surchargé ; essayez un autre serveur."],
	" ms ekliyor (normal aralık: 100-400 ms).": [" ms added by the VPN (normal range: 100–400 ms).", " ms ajoutées par le VPN (plage normale : 100–400 ms)."],
	"VPN kapalı: yalnızca direkt ölçüldü.": ["VPN is off: only direct was measured.", "Le VPN est désactivé : seul le direct a été mesuré."],
	"curl bu modemde SOCKS desteklemiyor: VPN sütunu ölçülemedi (apk add curl).": ["curl on this modem doesn't support SOCKS: the VPN column could not be measured (apk add curl).", "curl sur ce modem ne prend pas en charge SOCKS : la colonne VPN n'a pas pu être mesurée (apk add curl)."],
	"Son öğeden sonra fazladan virgül var (',' sil)": ["There's an extra comma after the last item (delete the ',')", "Il y a une virgule en trop après le dernier élément (supprimez la ',')"],
	"JSON bittikten sonra fazladan içerik var": ["Extra content after the end of the JSON", "Contenu superflu après la fin du JSON"],
	"Xray yapılandırmayı kabul etmedi": ["Xray did not accept the configuration", "Xray n'a pas accepté la configuration"],
	"böyle bir sunucu yok": ["no such server", "aucun serveur de ce type"],
	"JSON bir Xray outbound nesnesi olmalı ({ \"protocol\": ..., \"settings\": ... })": ["The JSON must be an Xray outbound object ({ \"protocol\": ..., \"settings\": ... })", "Le JSON doit être un objet outbound Xray ({ \"protocol\": ..., \"settings\": ... })"],
	"form verisi okunamadı": ["could not read the form data", "impossible de lire les données du formulaire"],
	"/etc/config/kediray okunamadı: ": ["/etc/config/kediray could not be read: ", "/etc/config/kediray illisible : "],
	"hiç geçerli sunucu yok": ["no valid server at all", "aucun serveur valide"],
	"yapılandırma üretilemedi": ["could not generate the configuration", "impossible de générer la configuration"],
	"aynı bağlantı içinde": ["within the same connection", "au sein de la même connexion"],
	"Açık​": ["Light", "Clair"]
};

const NAMES = {
	tr: { days: [ 'Paz', 'Pzt', 'Sal', 'Çar', 'Per', 'Cum', 'Cmt' ],
		months: [ 'Ocak', 'Şubat', 'Mart', 'Nisan', 'Mayıs', 'Haziran', 'Temmuz', 'Ağustos', 'Eylül', 'Ekim', 'Kasım', 'Aralık' ],
		short: [ 'Oca', 'Şub', 'Mar', 'Nis', 'May', 'Haz', 'Tem', 'Ağu', 'Eyl', 'Eki', 'Kas', 'Ara' ] },
	en: { days: [ 'Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat' ],
		months: [ 'January', 'February', 'March', 'April', 'May', 'June', 'July', 'August', 'September', 'October', 'November', 'December' ],
		short: [ 'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec' ] },
	fr: { days: [ 'dim', 'lun', 'mar', 'mer', 'jeu', 'ven', 'sam' ],
		months: [ 'janvier', 'février', 'mars', 'avril', 'mai', 'juin', 'juillet', 'août', 'septembre', 'octobre', 'novembre', 'décembre' ],
		short: [ 'janv', 'févr', 'mars', 'avr', 'mai', 'juin', 'juil', 'août', 'sept', 'oct', 'nov', 'déc' ] }
};
const LOCALES = { tr: 'tr-TR', en: 'en-GB', fr: 'fr-FR' };

/* Süre/sayı birimleri: "3 saatte bir", "1 gün 2 sa 5 dk 7 sn" gibi sayıya bitişik Türkçe kısaltmalar */
const UNITS = {
	en: { d: 'd', h: 'h', m: 'min', s: 's', every: n => 'every ' + n + ' h' },
	fr: { d: 'j', h: 'h', m: 'min', s: 's', every: n => 'toutes les ' + n + ' h' }
};

let EXACT = null, RX = null, MAP = null;

function build() {
	EXACT = new Map(); MAP = new Map();
	const keys = Object.keys(DICT).sort((a, b) => b.length - a.length);
	const parts = [];
	keys.forEach(k => {
		const v = DICT[k][LI];
		if (v == null || v === k) return;
		EXACT.set(k, v); MAP.set(k, v);
		const tk = k.trim();
		if (tk !== k && tk && !EXACT.has(tk)) EXACT.set(tk, v.trim());
		if (k.length < 2) return;
		const esc = k.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
		const pre = /^[\p{L}\p{N}]/u.test(k) ? '(?<![\\p{L}\\p{N}])' : '';
		const post = /[\p{L}\p{N}]$/u.test(k) ? '(?![\\p{L}\\p{N}])' : '';
		parts.push(pre + esc + post);
	});
	RX = new RegExp(parts.join('|'), 'gu');
}

const cache = new Map();

function trs(s) {
	if (LANG === 'tr' || typeof s !== 'string' || s.length < 2) return s;
	if (!EXACT) build();
	if (cache.has(s)) return cache.get(s);
	let r = EXACT.get(s);
	if (r == null) {
		const m = /^(\s*)([\s\S]*?)(\s*)$/.exec(s);
		const e = m && m[2] ? EXACT.get(m[2]) : null;
		if (e != null) r = m[1] + e + m[3];
	}
	if (r == null) {
		r = s.replace(RX, x => MAP.get(x));
		const u = UNITS[LANG];
		r = r.replace(/(\d+)\s*saatte bir/g, (x, n) => u.every(n))
			.replace(/(\d)\s*gün(?![\p{L}])/gu, (x, n) => n + ' ' + u.d)
			.replace(/(\d)\s*sa(?![\p{L}])/gu, (x, n) => n + ' ' + u.h)
			.replace(/(\d)\s*dk(?![\p{L}])/gu, (x, n) => n + ' ' + u.m)
			.replace(/(\d)\s*sn(?![\p{L}])/gu, (x, n) => n + ' ' + u.s);
	}
	if (cache.size > 4000) cache.clear();
	cache.set(s, r);
	return r;
}

const SKIP = /^(SCRIPT|STYLE|TEXTAREA|NOSCRIPT|CODE|PRE)$/;
const ATTRS = [ 'title', 'placeholder', 'aria-label', 'alt' ];
const doneTxt = new WeakMap(), doneAttr = new WeakMap();

function skipNode(n) {
	for (let p = n.nodeType === 1 ? n : n.parentNode; p && p.nodeType === 1; p = p.parentNode)
		if (SKIP.test(p.nodeName) || (p.hasAttribute && p.hasAttribute('data-i18n-skip'))) return true;
	return false;
}

function doText(n) {
	const s = n.data;
	if (doneTxt.get(n) === s) return;
	if (skipNode(n)) { doneTxt.set(n, s); return; }
	const r = trs(s);
	if (r !== s) n.data = r;
	doneTxt.set(n, r);
}

function doAttrs(el) {
	if (skipNode(el)) return;
	let rec = doneAttr.get(el);
	const names = ATTRS.slice();
	if (el.nodeName === 'BUTTON' || (el.nodeName === 'INPUT' && /^(button|submit|reset)$/.test(el.type))) names.push('value');
	names.forEach(a => {
		const v = el.getAttribute(a);
		if (v == null || v === '') return;
		if (rec && rec[a] === v) return;
		const r = trs(v);
		if (r !== v) el.setAttribute(a, r);
		if (!rec) { rec = {}; doneAttr.set(el, rec); }
		rec[a] = r;
	});
}

function walk(n) {
	if (!n) return;
	if (n.nodeType === 3) { doText(n); return; }
	if (n.nodeType !== 1 || SKIP.test(n.nodeName) || n.hasAttribute('data-i18n-skip')) return;
	doAttrs(n);
	for (let c = n.firstChild; c; c = c.nextSibling) walk(c);
}

/* Dil seçici: sayfa başlığının (h2) sağına; başlık yoksa içeriğin en üstüne sağa yaslı konur */
function mkSwitch() {
	const w = document.createElement('span');
	w.className = 'kr-lang';
	w.setAttribute('data-i18n-skip', '1');
	w.setAttribute('style', 'display:inline-flex;align-items:center;gap:2px;padding:2px;margin-left:auto;border-radius:999px;border:1px solid rgba(128,128,128,.4);background:rgba(128,128,128,.08);font:600 12px/1 system-ui,sans-serif;white-space:nowrap');
	const g = document.createElement('span');
	g.textContent = '🌐';
	g.setAttribute('style', 'padding:0 4px 0 6px;font-size:13px;line-height:1');
	w.appendChild(g);
	LANGS.forEach(l => {
		const b = document.createElement('button');
		b.type = 'button'; b.textContent = l[1]; b.title = l[2];
		b.setAttribute('aria-pressed', l[0] === LANG ? 'true' : 'false');
		b.setAttribute('style', 'border:0;cursor:pointer;font:inherit;padding:5px 9px;border-radius:999px;color:' + (l[0] === LANG ? '#fff' : 'inherit')
			+ ';background:' + (l[0] === LANG ? 'var(--kr-accent,#2a7de1)' : 'transparent'));
		b.addEventListener('click', ev => { ev.preventDefault(); ev.stopPropagation(); setLang(l[0]); });
		w.appendChild(b);
	});
	return w;
}

function mount() {
	if (document.querySelector('.kr-lang')) return true;
	const root = document.getElementById('maincontent') || document.body;
	const h2 = root.querySelector('h2');
	if (h2 && h2.parentNode) {
		h2.style.display = 'flex'; h2.style.alignItems = 'center'; h2.style.flexWrap = 'wrap'; h2.style.gap = '8px';
		h2.appendChild(mkSwitch());
		return true;
	}
	const v = document.getElementById('view') || root.querySelector('.cbi-map, [data-page], .ka-card');
	if (v && v.parentNode && v.firstChild) {
		const bar = document.createElement('div');
		bar.setAttribute('style', 'display:flex;justify-content:flex-end;margin:0 0 8px');
		bar.appendChild(mkSwitch());
		(v.classList && v.classList.contains('ka-card') ? v.parentNode : v).insertBefore(bar, (v.classList && v.classList.contains('ka-card') ? v : v.firstChild));
		return true;
	}
	return false;
}

function setLang(l) {
	try { localStorage.setItem(LS, l); } catch (e) { }
	location.reload();
}

let started = false;

function start() {
	if (started) return;
	started = true;
	const go = () => {
		if (LANG !== 'tr') {
			['confirm', 'alert', 'prompt'].forEach(fn => {
				const o = window[fn];
				if (typeof o === 'function') window[fn] = function (m, d) { return o.call(window, trs(String(m)), d); };
			});
			document.documentElement.setAttribute('lang', LANG);
			document.title = trs(document.title);
			walk(document.body);
			let q = new Set(), tm = null;
			const flush = () => {
				tm = null;
				const items = Array.from(q); q = new Set();
				items.forEach(n => { if (n.isConnected !== false) walk(n); });
				if (document.title) { const t = trs(document.title); if (t !== document.title) document.title = t; }
			};
			new MutationObserver(ms => {
				ms.forEach(m => {
					if (m.type === 'childList') m.addedNodes.forEach(n => q.add(n));
					else if (m.type === 'characterData') q.add(m.target);
					else if (m.type === 'attributes') q.add(m.target);
				});
				if (!tm) tm = setTimeout(flush, 30);
			}).observe(document.documentElement, { childList: true, subtree: true, characterData: true, attributes: true, attributeFilter: ATTRS.concat([ 'value' ]) });
		}
		let tries = 0;
		const iv = setInterval(() => {
			if (mount() || ++tries > 40) clearInterval(iv);
		}, 250);
	};
	if (document.body) go(); else document.addEventListener('DOMContentLoaded', go);
}

start();

return baseclass.extend({
	lang: LANG,
	t: trs,
	locale: () => LOCALES[LANG],
	days: () => NAMES[LANG].days.slice(),
	months: () => NAMES[LANG].months.slice(),
	monthsShort: () => NAMES[LANG].short.slice(),
	setLang: setLang
});
