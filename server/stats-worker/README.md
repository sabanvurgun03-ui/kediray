# KediRay sayaç sunucusu (Cloudflare Workers)

Yalnızca **izin veren** kullanıcıların günde bir kez gönderdiği anonim kullanım bilgisini sayar: rastgele kurulum kimliği, sürüm, uygulama adı.
IP adresi saklanmaz. 35 gün ping gelmeyen kayıt kendiliğinden silinir.

## Yayınlama (Cloudflare panelinden, komut gerekmez)

1. Cloudflare → **Workers & Pages → Create → Worker**, adı `kediray-stats`. **Deploy** de, sonra **Edit code**'a gir, `worker.js` içeriğini yapıştır, kaydet.
2. **Storage & Databases → KV → Create** ile `STATS` adlı bir namespace aç.
3. Worker → **Settings → Bindings → Add → KV namespace**: değişken adı `STATS`, az önceki namespace.
4. Worker → **Settings → Variables and Secrets → Add**, tür *Secret*:
   - `ADMIN_USER`: ana yöneticinin kullanıcı adı
   - `ADMIN_TOKEN`: ana yöneticinin şifresi (uzun ve rastgele). Aynı değer oturum çerezlerini imzalamak için de kullanılır; değiştirirsen açık oturumlar kapanır.
5. İsteğe bağlı, "Şifremi unuttum" için: `RESEND_API_KEY` (Secret, [Resend](https://resend.com) API anahtarı) ve `RESET_EMAIL` (sıfırlama maillerinin gideceği adres). Bağlantının başka bir alan adıyla üretilmesini istersen `SITE_URL` ekle (yoksa Worker'ın kendi adresi kullanılır).
6. Worker adresi `https://kediray-stats.kediray.workers.dev` olur. Yönetici sayfası: `<adres>/admin`.

Komut satırı sevenler için: `wrangler.toml` hazır; `npx wrangler deploy`.

## Yönetici girişi

- `/admin` sayfasında kullanıcı adı ve şifreyle girilir. Oturum 7 gün açık kalır (`HttpOnly`, `Secure`, `SameSite=Strict` çerez).
- 10 dakika içinde 10 hatalı girişten sonra giriş 10 dakika kilitlenir. Kilit herkes için ortaktır (IP'ye göre değil).
- Ana yönetici başka yöneticiler ekleyip silebilir. Eklenenlerin şifresi KV'de PBKDF2 ile özetlenmiş saklanır, düz metin yoktur.
- "Şifremi unuttum": `RESET_EMAIL` adresine yönetici kullanıcı adlarını ve 15 dakika geçerli, tek kullanımlık bir sıfırlama bağlantısını gönderir. Yeni mail için 5 dakika beklemek gerekir.

## Uç noktalar

- `POST /ping` — `{"app":"kediray","id":"<hex>","v":"1.19.65"}`
- `GET /admin` — giriş ve sayaç sayfası
- `POST /admin/login`, `POST /admin/logout` — oturum aç / kapat
- `POST /admin/forgot`, `GET /admin/reset`, `GET /admin/reset-users`, `POST /admin/reset-confirm` — şifre sıfırlama
- `GET /api/me` — oturumdaki yönetici
- `GET /api/admins`, `POST /api/admins`, `POST /api/admins/delete` — yönetici listesi / ekleme / silme (yalnızca ana yönetici)
- `GET /api/stats` — sayaç JSON'u; oturum çerezi ya da (betikler için) `Authorization: Bearer <ADMIN_TOKEN>` ile

Not: Cloudflare, her web sunucusu gibi, bağlantının IP'sini kendi altyapısında görür; bu Worker onu okumaz ve saklamaz.
