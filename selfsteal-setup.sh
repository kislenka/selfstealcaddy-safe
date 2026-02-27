#!/bin/bash

# ============================================
#  SelfSteal Caddy 404 Stub Installer
#  For Remnawave + Xray Reality nodes
#
#  Usage: bash selfsteal-setup.sh
#  Requirements: Debian/Ubuntu, root access
# ============================================

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

echo -e "${CYAN}"
cat << 'BANNER'
 ╔═══════════════════════════════════════════════╗
 ║      SelfSteal Caddy 404 Stub Installer       ║
 ║      For Remnawave + Xray Reality nodes        ║
 ╚═══════════════════════════════════════════════╝
BANNER
echo -e "${NC}"

# ---- Check root ----
if [[ $EUID -ne 0 ]]; then
    echo -e "${RED}[✗] This script must be run as root${NC}"
    echo -e "    Run: ${CYAN}sudo bash $0${NC}"
    exit 1
fi

# ---- Domain input ----
read -rp "$(echo -e "${YELLOW}[?] Enter your domain: ${NC}")" DOMAIN

if [[ -z "$DOMAIN" ]]; then
    echo -e "${RED}[✗] Domain cannot be empty${NC}"
    exit 1
fi

DOMAIN=$(echo "$DOMAIN" | xargs)

# ---- Check DNS ----
echo -e "${CYAN}[*] Checking DNS for ${DOMAIN}...${NC}"

SERVER_IP=$(curl -s4 --max-time 5 ifconfig.me 2>/dev/null || curl -s4 --max-time 5 icanhazip.com 2>/dev/null || echo "unknown")
DOMAIN_IP=$(dig +short "$DOMAIN" A 2>/dev/null | head -1)

if [[ -z "$DOMAIN_IP" ]]; then
    echo -e "${RED}[✗] Domain ${DOMAIN} does not resolve to any IP${NC}"
    echo -e "    Make sure DNS A record points to this server: ${CYAN}${SERVER_IP}${NC}"
    read -rp "$(echo -e "${YELLOW}[?] Continue anyway? (y/n): ${NC}")" CONT
    [[ "$CONT" != "y" ]] && exit 1
elif [[ "$SERVER_IP" == "$DOMAIN_IP" ]]; then
    echo -e "${GREEN}[✓] DNS OK: ${DOMAIN} → ${DOMAIN_IP}${NC}"
else
    echo -e "${YELLOW}[!] Warning: ${DOMAIN} → ${DOMAIN_IP}, but server IP is ${SERVER_IP}${NC}"
    read -rp "$(echo -e "${YELLOW}[?] Continue anyway? (y/n): ${NC}")" CONT
    [[ "$CONT" != "y" ]] && exit 1
fi

# ---- Install dependencies ----
echo -e "${CYAN}[*] Checking dependencies...${NC}"

for pkg in curl dnsutils; do
    if ! dpkg -s "$pkg" &>/dev/null; then
        apt install -y "$pkg" > /dev/null 2>&1
    fi
done

# ---- Install Caddy ----
echo -e "${CYAN}[*] Installing Caddy...${NC}"

if command -v caddy &>/dev/null; then
    CADDY_VER=$(caddy version 2>/dev/null | awk '{print $1}')
    echo -e "${GREEN}[✓] Caddy already installed (${CADDY_VER})${NC}"
else
    apt install -y debian-keyring debian-archive-keyring apt-transport-https > /dev/null 2>&1

    curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/gpg.key' \
        | gpg --dearmor -o /usr/share/keyrings/caddy-stable-archive-keyring.gpg 2>/dev/null

    curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/debian.deb.txt' \
        | tee /etc/apt/sources.list.d/caddy-stable.list > /dev/null

    apt update -qq > /dev/null 2>&1
    apt install -y caddy > /dev/null 2>&1

    if command -v caddy &>/dev/null; then
        echo -e "${GREEN}[✓] Caddy installed successfully${NC}"
    else
        echo -e "${RED}[✗] Failed to install Caddy${NC}"
        exit 1
    fi
fi

# ---- Create 404 page ----
echo -e "${CYAN}[*] Creating 404 stub page...${NC}"

mkdir -p /var/www/html

cat > /var/www/html/404.html << 'HTMLEOF'
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>404 - Page Not Found</title>
    <style>
        *{margin:0;padding:0;box-sizing:border-box}
        body{font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',Roboto,sans-serif;background:#0a0a0a;color:#e0e0e0;display:flex;justify-content:center;align-items:center;min-height:100vh}
        .container{text-align:center;padding:2rem}
        .error-code{font-size:clamp(6rem,20vw,12rem);font-weight:800;background:linear-gradient(135deg,#667eea 0%,#764ba2 100%);-webkit-background-clip:text;-webkit-text-fill-color:transparent;background-clip:text;line-height:1;margin-bottom:1rem;animation:pulse 3s ease-in-out infinite}
        .message{font-size:1.3rem;color:#888;margin-bottom:.5rem}
        .sub{font-size:.95rem;color:#555}
        @keyframes pulse{0%,100%{opacity:1}50%{opacity:.7}}
    </style>
</head>
<body>
    <div class="container">
        <div class="error-code">404</div>
        <p class="message">Page Not Found</p>
        <p class="sub">The requested resource could not be located on this server.</p>
    </div>
</body>
</html>
HTMLEOF

echo -e "${GREEN}[✓] 404 page created${NC}"

# ---- Configure Caddy ----
echo -e "${CYAN}[*] Configuring Caddy...${NC}"

if [[ -f /etc/caddy/Caddyfile ]]; then
    cp /etc/caddy/Caddyfile "/etc/caddy/Caddyfile.bak.$(date +%s)"
fi

cat > /etc/caddy/Caddyfile << CADDYEOF
{
    http_port 80
    https_port 8443
}

${DOMAIN}:80 {
    redir https://${DOMAIN}:8443{uri} permanent
}

${DOMAIN}:8443 {
    header {
        Strict-Transport-Security "max-age=31536000; includeSubDomains; preload"
        X-Content-Type-Options "nosniff"
        X-Frame-Options "SAMEORIGIN"
    }
    handle {
        root * /var/www/html
        rewrite * /404.html
        file_server
    }
    handle_errors {
        root * /var/www/html
        rewrite * /404.html
        file_server
    }
}
CADDYEOF

caddy fmt --overwrite /etc/caddy/Caddyfile > /dev/null 2>&1 || true
echo -e "${GREEN}[✓] Caddyfile configured${NC}"

# ---- Firewall ----
echo -e "${CYAN}[*] Configuring firewall...${NC}"

if command -v ufw &>/dev/null; then
    ufw allow 80/tcp  > /dev/null 2>&1 || true
    ufw allow 443/tcp > /dev/null 2>&1 || true
    ufw delete allow 8443/tcp > /dev/null 2>&1 || true
    echo -e "${GREEN}[✓] UFW: 80/tcp, 443/tcp open | 8443 closed (internal only)${NC}"
else
    echo -e "${YELLOW}[!] UFW not found — make sure ports 80 and 443 are open${NC}"
fi

# ---- Start Caddy ----
echo -e "${CYAN}[*] Starting Caddy...${NC}"

systemctl enable caddy > /dev/null 2>&1
systemctl restart caddy

echo -e "${CYAN}[*] Waiting for TLS certificate...${NC}"
sleep 5

if systemctl is-active --quiet caddy; then
    echo -e "${GREEN}[✓] Caddy is running${NC}"
else
    echo -e "${RED}[✗] Caddy failed to start${NC}"
    echo -e "    Check: ${CYAN}journalctl -u caddy --no-pager -n 20${NC}"
    exit 1
fi

# ---- Verify ----
HTTP_CODE=$(curl -sk -o /dev/null -w "%{http_code}" "https://${DOMAIN}:8443" 2>/dev/null || echo "000")

if [[ "$HTTP_CODE" == "404" ]]; then
    echo -e "${GREEN}[✓] HTTPS works, 404 stub served correctly${NC}"
elif [[ "$HTTP_CODE" == "000" ]]; then
    echo -e "${YELLOW}[!] Could not verify HTTPS yet (cert may still be issuing)${NC}"
else
    echo -e "${YELLOW}[!] Got HTTP ${HTTP_CODE} instead of 404${NC}"
fi

# ---- Summary ----
echo ""
echo -e "${GREEN}╔═══════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║           ✓ Installation Complete              ║${NC}"
echo -e "${GREEN}╚═══════════════════════════════════════════════╝${NC}"
echo ""
echo -e "  ${BOLD}Domain:${NC}     ${CYAN}${DOMAIN}${NC}"
echo -e "  ${BOLD}Stub URL:${NC}   ${CYAN}https://${DOMAIN}:8443${NC}"
echo -e "  ${BOLD}HTTP:${NC}       ${CYAN}http://${DOMAIN}${NC} → redirect to HTTPS"
echo ""
echo -e "  ${YELLOW}━━━ Update your Xray / Remnawave node config ━━━${NC}"
echo ""
echo -e "    \"target\":      ${GREEN}\"127.0.0.1:8443\"${NC}"
echo -e "    \"serverNames\": ${GREEN}[\"${DOMAIN}\"]${NC}"
echo ""
echo -e "  ${BOLD}Open ports:${NC}  80 (cert + redirect), 443 (Xray)"
echo -e "  ${BOLD}Internal:${NC}    8443 (Caddy, localhost only)"
echo ""
