# KediRay sayaç sunucusu (Cloudflare Workers)

Yalnızca **izin veren** kullanıcıların günde bir kez gönderdiği anonim kullanım bilgisini sayar: rastgele kurulum kimliği, sürüm, uygulama adı.
IP adresi saklanmaz. 35 gün ping gelmeyen kayıt kendiliğinden silinir.

## Yayınlama (Cloudflare panelinden, komut gerekmez)

1. Cloudflare → **Workers & Pages → Create → Worker**, adı `kediray-stats`. **Deploy** de, sonra **Edit code**'a gir, `worker.js` içeriğini yapıştır, kaydet.
2. **Storage & Databases → KV → Create** ile `STATS` adlı bir namespace aç.
3. Worker → **Settings → Bindings → Add → KV namespace**: değişken adı `STATS`, az önceki namespace.
4. Worker → **Settings → Variables and Secrets → Add**: tür *Secret*, ad `ADMIN_TOKEN`, değer = kendi yönetici şifren (uzun ve rastgele).
5. Worker adresi `https://kediray-stats.<hesabın>.workers.dev` olur. Yönetici sayfası: `<adres>/admin`.

Komut satırı sevenler için: `wrangler.toml` hazır; `npx wrangler deploy`.

## Uç noktalar

- `POST /ping` — `{"app":"kediray","id":"<hex>","v":"1.19.65"}`
- `GET /admin` — şifreli sayfa (şifreyi tarayıcı yalnızca oturum boyunca tutar)
- `GET /api/stats` — `Authorization: Bearer <ADMIN_TOKEN>` ile JSON

Not: Cloudflare, her web sunucusu gibi, bağlantının IP'sini kendi altyapısında görür; bu Worker onu okumaz ve saklamaz.
