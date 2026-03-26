# SelfSteal Caddy Stub

Скрипт для установки локального HTTPS-бэкенда на `Caddy` под `Xray Reality` / `Remnawave`.

Идея простая:
- `Xray Reality` слушает `443`
- fallback для зондирования и невалидного трафика уходит на `127.0.0.1:8443`
- `Caddy` на `127.0.0.1:8443` отдаёт выбранную HTML-страницу с валидным сертификатом для твоего домена

## Как это работает

```text
Client (SNI: your-domain.com)
        |
        v
Xray Reality (:443)
        |
        +--> valid client -> VPN tunnel
        |
        +--> probe / fallback -> 127.0.0.1:8443
                                |
                                v
                       Caddy with valid TLS
                                |
                                v
                           Stub page
```

## Встроенные страницы

Скрипт включает 3 варианта на выбор:

| # | Name | Description |
|---|------|-------------|
| 1 | **Nexus Digital** | Bright corporate landing page with stats, services and CTA sections |
| 2 | **Stratus Works** | Bright cloud and infrastructure engineering landing page |
| 3 | **Your Custom Page** | Embedded user-provided landing page from the provided reference |

После установки можно заменить `/var/www/html/index.html` на любой свой HTML.

## Требования

- Debian / Ubuntu
- root-доступ
- домен с `A`-записью на IP сервера
- установленный `Xray Reality` или `Remnawave`

## Установка

Одной командой:

```bash
bash <(curl -Ls https://raw.githubusercontent.com/kislenka/selfstealcaddy-safe/main/selfsteal-setup.sh)
```

Вручную:

```bash
curl -Lo selfsteal-setup.sh https://raw.githubusercontent.com/kislenka/selfstealcaddy-safe/main/selfsteal-setup.sh
bash selfsteal-setup.sh
```

Неинтерактивно:

```bash
bash selfsteal-setup.sh --domain example.com --stub 1 --yes
```

## Что делает скрипт

1. Запрашивает домен и вариант страницы
2. Проверяет DNS
3. Устанавливает `Caddy`, если он ещё не установлен
4. Создаёт выбранную страницу в `/var/www/html/index.html`
5. Настраивает `Caddy`:
   - `80/tcp` — публичная HTTP-страница + ACME
   - `8443/tcp` — локальный HTTPS-бэкенд на `127.0.0.1`
6. Настраивает `ufw` для `80`, `2222`, `443`, `8443`, если `ufw` установлен
7. Проверяет локальный TLS-бэкенд через `--resolve ... 127.0.0.1`

## Что менять в Xray / Remnawave

В `realitySettings` нужно заменить только эти поля:

```json
"realitySettings": {
  "target": "127.0.0.1:8443",
  "serverNames": ["your-domain.com"]
}
```

Пример:

```json
{
  "streamSettings": {
    "network": "tcp",
    "security": "reality",
    "realitySettings": {
      "show": false,
      "xver": 0,
      "target": "127.0.0.1:8443",
      "shortIds": [
        "ff5ccb60e442b966"
      ],
      "privateKey": "YOUR_PRIVATE_KEY",
      "serverNames": [
        "your-domain.com"
      ]
    }
  }
}
```

Остальные поля (`shortIds`, `privateKey`, routing, clients, outbounds) обычно менять не нужно.

## Порты

| Port | Service | Access |
|------|---------|--------|
| `80` | Caddy | Public: ACME + HTTP stub |
| `2222` | Extra TCP port | Opened by script if `ufw` exists |
| `443` | Xray Reality | Public |
| `8443` | Caddy HTTPS | Opened in firewall if configured, but Caddy binds only to `127.0.0.1` |

## Файлы

| File | Path |
|------|------|
| Stub page | `/var/www/html/index.html` |
| Caddy config | `/etc/caddy/Caddyfile` |
| Caddy backups | `/etc/caddy/Caddyfile.bak.*` |

## Проверка

Проверить публичную HTTP-страницу:

```bash
curl -I http://your-domain.com
```

Проверить локальный HTTPS fallback:

```bash
curl --resolve your-domain.com:8443:127.0.0.1 -kI https://your-domain.com:8443
```

Проверить слушающие порты:

```bash
ss -lntp | grep -E ':80|:443|:8443|:2222'
```

Проверить логи `Caddy`:

```bash
journalctl -u caddy --no-pager -n 50
```

## Кастомизация

Заменить страницу вручную:

```bash
nano /var/www/html/index.html
systemctl restart caddy
```

Переустановить другой встроенный шаблон:

```bash
bash selfsteal-setup.sh --domain your-domain.com --stub 2 --yes
```

## Удаление

```bash
systemctl stop caddy
systemctl disable caddy
apt remove caddy -y
rm -rf /var/www/html
rm -f /etc/apt/sources.list.d/caddy-stable.list
rm -f /usr/share/keyrings/caddy-stable-archive-keyring.gpg
```

## Troubleshooting

`Caddy` не запускается:

```bash
journalctl -u caddy --no-pager -n 30
```

Сертификат не выдаётся:

- проверь, что `80/tcp` доступен снаружи
- проверь, что `A`-запись домена указывает на этот сервер
- проверь `curl -I http://your-domain.com`

## License

MIT
