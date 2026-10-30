<?php
/* Приём заявки с лендинга и отправка её в Telegram.
   Токен сюда не вписан: он читается из файла tg.env рядом, в котором две
   строки — TG_TOKEN= и TG_CHAT=. Этот файл можно хранить в репозитории,
   tg.env — нельзя. */

header("Content-Type: application/json; charset=utf-8");
header("Access-Control-Allow-Origin: *");
header("Access-Control-Allow-Headers: Content-Type");
if ($_SERVER["REQUEST_METHOD"] === "OPTIONS") { http_response_code(204); exit; }
if ($_SERVER["REQUEST_METHOD"] !== "POST") {
    http_response_code(405); echo '{"ok":false}'; exit;
}

/* tg.env лежит рядом; на сервере его надо закрыть от чтения извне —
   как это сделать, написано в README рядом. */
$cfg = [];
foreach (@file(__DIR__ . "/tg.env", FILE_IGNORE_NEW_LINES | FILE_SKIP_EMPTY_LINES) ?: [] as $line) {
    if ($line === "" || $line[0] === "#" || strpos($line, "=") === false) { continue; }
    [$k, $v] = explode("=", $line, 2);
    $cfg[trim($k)] = trim($v, " \"'");
}
if (empty($cfg["TG_TOKEN"]) || empty($cfg["TG_CHAT"])) {
    http_response_code(500); echo '{"ok":false,"error":"no config"}'; exit;
}

$d = json_decode(file_get_contents("php://input"), true) ?: [];
$get = function ($k, $max = 120) use ($d) {
    return mb_substr(trim(strip_tags((string)($d[$k] ?? ""))), 0, $max);
};

$name  = $get("name");
$phone = $get("phone", 40);
if ($name === "" || $phone === "") {
    http_response_code(400); echo '{"ok":false,"error":"empty"}'; exit;
}

/* номер в ссылку для WhatsApp — только цифры */
$wa = preg_replace('/\D+/', '', $phone);

$lines = ["<b>Новая заявка с сайта</b>", "",
          "Имя: " . htmlspecialchars($name),
          "Телефон: " . htmlspecialchars($phone)];
if ($get("spend") !== "")     { $lines[] = "Бюджет: " . htmlspecialchars($get("spend")); }
if ($get("videoName") !== "") { $lines[] = "Пришёл с ролика: " . htmlspecialchars($get("videoName")); }
elseif ($get("video") !== "") { $lines[] = "Пришёл с ролика: " . htmlspecialchars($get("video")); }

$calc = $d["calc"] ?? null;
if (is_array($calc) && !empty($calc["estimate"])) {
    $lines[] = "Насчитал себе цену клиента: " . htmlspecialchars((string)$calc["estimate"]);
}
if ($get("utm_source") !== "") { $lines[] = "utm_source: " . htmlspecialchars($get("utm_source")); }
$lines[] = "";
$lines[] = "Откуда пришёл: " . htmlspecialchars($get("referrer", 200));

$body = [
    "chat_id"      => $cfg["TG_CHAT"],
    "parse_mode"   => "HTML",
    "text"         => implode("\n", $lines),
    "reply_markup" => json_encode(["inline_keyboard" => [[
        ["text" => "Написать в WhatsApp", "url" => "https://wa.me/" . $wa],
        ["text" => "Позвонить",           "url" => "tel:" . $phone],
    ]]]),
];

$ch = curl_init("https://api.telegram.org/bot" . $cfg["TG_TOKEN"] . "/sendMessage");
curl_setopt_array($ch, [
    CURLOPT_POST           => true,
    CURLOPT_POSTFIELDS     => http_build_query($body),
    CURLOPT_RETURNTRANSFER => true,
    CURLOPT_TIMEOUT        => 12,
]);
curl_exec($ch);
$code = curl_getinfo($ch, CURLINFO_HTTP_CODE);
curl_close($ch);

if ($code === 200) { echo '{"ok":true}'; }
else { http_response_code(502); echo '{"ok":false,"error":"telegram"}'; }
