#!/usr/bin/env bash
# Разворачивает приём заявок в Telegram одной командой. Без npm и wrangler — чистый curl.
#
# Что нужно один раз, пять минут:
#   1. завести бесплатный аккаунт на dash.cloudflare.com
#   2. скопировать Account ID — он справа на главной странице дашборда
#   3. My Profile → API Tokens → Create Token → шаблон "Edit Cloudflare Workers"
#
# Потом:
#   export CF_ACCOUNT_ID=...
#   export CF_API_TOKEN=...
#   bash deploy-bot.sh https://твойдомен.com
#
# Токен бота берётся из ~/.claude/bin/tg.env и уезжает прямо в секреты Cloudflare —
# в коде страницы его нет и не будет.

set -euo pipefail
cd "$(dirname "$0")"

SCRIPT_NAME="autoshop-leads"
ENV_FILE="$HOME/.claude/bin/tg.env"
ORIGIN="${1:-*}"
API="https://api.cloudflare.com/client/v4"

: "${CF_ACCOUNT_ID:?Нет CF_ACCOUNT_ID. Возьми его на главной dash.cloudflare.com, справа}"
: "${CF_API_TOKEN:?Нет CF_API_TOKEN. My Profile -> API Tokens -> шаблон Edit Cloudflare Workers}"
[ -f "$ENV_FILE" ] || { echo "Не нашёл $ENV_FILE с токеном бота"; exit 1; }

# shellcheck disable=SC1090
set -a; source "$ENV_FILE"; set +a
: "${TG_TOKEN:?нет TG_TOKEN в tg.env}"
: "${TG_CHAT:?нет TG_CHAT в tg.env}"

ok() { python3 -c "import json,sys; d=json.load(sys.stdin); print('OK' if d.get('success') else 'FAIL: '+json.dumps(d.get('errors'),ensure_ascii=False))"; }

echo "→ Загружаю воркер и секреты…"
META=$(python3 - <<PY
import json,os
print(json.dumps({
  "main_module":"worker.js",
  "compatibility_date":"2026-10-01",
  "bindings":[
    {"type":"secret_text","name":"TG_TOKEN","text":os.environ["TG_TOKEN"]},
    {"type":"secret_text","name":"TG_CHAT","text":os.environ["TG_CHAT"]},
    {"type":"secret_text","name":"ALLOWED_ORIGIN","text":"$ORIGIN"},
  ]
}))
PY
)

RES=$(curl -s -X PUT "$API/accounts/$CF_ACCOUNT_ID/workers/scripts/$SCRIPT_NAME" \
  -H "Authorization: Bearer $CF_API_TOKEN" \
  -F "metadata=$META;type=application/json" \
  -F "worker.js=@worker.js;type=application/javascript+module")
echo "   $(echo "$RES" | ok)"
echo "$RES" | grep -q '"success":true' || { echo "Деплой не прошёл, выше причина."; exit 1; }

echo "→ Включаю публичный адрес…"
curl -s -X POST "$API/accounts/$CF_ACCOUNT_ID/workers/scripts/$SCRIPT_NAME/subdomain" \
  -H "Authorization: Bearer $CF_API_TOKEN" -H "Content-Type: application/json" \
  -d '{"enabled":true}' | ok

SUB=$(curl -s "$API/accounts/$CF_ACCOUNT_ID/workers/subdomain" \
  -H "Authorization: Bearer $CF_API_TOKEN" \
  | python3 -c "import json,sys; print(json.load(sys.stdin)['result']['subdomain'])")
URL="https://$SCRIPT_NAME.$SUB.workers.dev"

echo "→ Прописываю адрес в index.html…"
python3 - "$URL" <<'PY'
import io, re, sys
url = sys.argv[1]
s = io.open("index.html", encoding="utf-8").read()
s = re.sub(r'(endpoint:\s*)"[^"]*"', lambda m: m.group(1) + '"' + url + '"', s, count=1)
io.open("index.html", "w", encoding="utf-8").write(s)
print("   endpoint =", url)
PY

echo "→ Отправляю тестовую заявку…"
sleep 3
curl -s -X POST "$URL" -H "Content-Type: application/json" -d '{
  "name":"Тестовая заявка",
  "phone":"+1 555 014 2290",
  "shop":"Northside Auto, Austin TX",
  "site":"northsideauto.com",
  "spend":"$3,000 - $7,000",
  "pain":"Проверка связки лендинг -> бот",
  "calc":{"spend":"3000","cpc":"6","missed":"9","ticket":"450","estimate":"$6,021"},
  "utm_source":"deploy-script"
}'; echo

echo
echo "Готово. Смотри телегу — должно прийти сообщение с кнопками WhatsApp и Позвонить."
echo "Адрес воркера: $URL"
