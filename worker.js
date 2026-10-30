/**
 * Cloudflare Worker: принимает заявку с лендинга и кладёт её в Telegram.
 *
 * Зачем воркер, а не запрос в Telegram прямо со страницы:
 * токен бота в коде страницы видит любой желающий, и бота угоняют за час.
 * Здесь токен лежит в секретах Cloudflare и наружу не попадает.
 *
 * Развернуть:
 *   npm i -g wrangler
 *   wrangler login
 *   wrangler deploy
 *   wrangler secret put TG_TOKEN      # токен бота от @BotFather
 *   wrangler secret put TG_CHAT       # твой chat_id
 *   wrangler secret put WHATSAPP      # номер для кнопки, только цифры: 375291234567
 *   wrangler secret put ALLOWED_ORIGIN # https://твойдомен.com
 *
 * Потом URL воркера вписывается в index.html → CONFIG.endpoint.
 */

const esc = s => String(s || "")
  .replace(/&/g, "&amp;")
  .replace(/</g, "&lt;")
  .replace(/>/g, "&gt;");

function cors(origin) {
  return {
    "Access-Control-Allow-Origin": origin,
    "Access-Control-Allow-Methods": "POST, OPTIONS",
    "Access-Control-Allow-Headers": "Content-Type",
    "Access-Control-Max-Age": "86400"
  };
}

export default {
  async fetch(request, env) {
    const origin = env.ALLOWED_ORIGIN || "*";

    if (request.method === "OPTIONS") {
      return new Response(null, { status: 204, headers: cors(origin) });
    }
    if (request.method !== "POST") {
      return new Response("Method not allowed", { status: 405, headers: cors(origin) });
    }

    let d;
    try {
      d = await request.json();
    } catch {
      return new Response("Bad JSON", { status: 400, headers: cors(origin) });
    }

    // минимальная валидация — без неё бот превращается в спам-канал
    if (!d.name || !d.phone || String(d.phone).replace(/\D/g, "").length < 7) {
      return new Response("Missing fields", { status: 422, headers: cors(origin) });
    }
    if (d.company_website) {               // honeypot, если добавишь скрытое поле
      return new Response("ok", { status: 200, headers: cors(origin) });
    }

    const digits = String(d.phone).replace(/\D/g, "");
    const calc = d.calc || {};

    const text = [
      "🔧 <b>Новая заявка — Auto Shop Teardown</b>",
      "",
      `<b>Имя:</b> ${esc(d.name)}`,
      `<b>WhatsApp:</b> <code>${esc(d.phone)}</code>`,
      d.spend ? `<b>Бюджет:</b> ${esc(d.spend)}` : null,
      d.videoName ? `<b>Пришёл с ролика:</b> ${esc(d.videoName)}` : null,
      "",
      "<b>Что накрутил в калькуляторе:</b>",
      `клик ${esc(calc.cpc)} · конверсия сайта ${esc(calc.cr)} · записывается ${esc(calc.close)}`,
      `клиент обходится ему в <b>${esc(calc.estimate)}</b>`,
      "",
      `<b>Источник:</b> ${esc(d.utm_source || d.referrer || "—")}`,
      d.utm_campaign ? `<b>Кампания:</b> ${esc(d.utm_campaign)}` : null,
      d.video ? `<b>Видео:</b> ${esc(d.video)}` : null
    ].filter(Boolean).join("\n");

    const tg = await fetch(`https://api.telegram.org/bot${env.TG_TOKEN}/sendMessage`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({
        chat_id: env.TG_CHAT,
        text,
        parse_mode: "HTML",
        disable_web_page_preview: true,
        reply_markup: {
          inline_keyboard: [[
            { text: "💬 Написать в WhatsApp", url: `https://wa.me/${digits}` },
            { text: "📞 Позвонить", url: `tel:+${digits}` }
          ]]
        }
      })
    });

    if (!tg.ok) {
      console.error("telegram failed", tg.status, await tg.text());
      return new Response("Upstream error", { status: 502, headers: cors(origin) });
    }

    return new Response(JSON.stringify({ ok: true }), {
      status: 200,
      headers: { ...cors(origin), "Content-Type": "application/json" }
    });
  }
};
