#!/bin/bash

# ============================================
#  SelfSteal Caddy Stub Installer
#  For Remnawave + Xray Reality nodes
#
#  Usage: bash selfsteal-setup.sh
#  Requirements: Debian/Ubuntu, root access
# ============================================

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
DIM='\033[2m'
NC='\033[0m'

DOMAIN=""
STUB_CHOICE="1"
ASSUME_YES="0"
MANAGED_PORTS=(80 2222 443 8443)

trim() {
    local value="$1"
    value="${value#"${value%%[![:space:]]*}"}"
    value="${value%"${value##*[![:space:]]}"}"
    printf '%s' "$value"
}

usage() {
    cat <<'EOF'
Usage: bash selfsteal-setup.sh [options]

Options:
  --domain <fqdn>      Domain to use for the Caddy stub
  --stub <1|2|3>       Stub page: 1=Nexus, 2=Stratus, 3=Custom page
  --yes                Continue non-interactively on DNS mismatch
  -h, --help           Show this help
EOF
}

validate_domain() {
    local domain="$1"

    if [[ ${#domain} -gt 253 ]]; then
        return 1
    fi

    if [[ "$domain" =~ [[:space:]/\\:{}] ]]; then
        return 1
    fi

    if [[ ! "$domain" =~ ^[A-Za-z0-9.-]+$ ]]; then
        return 1
    fi

    if [[ "$domain" == .* || "$domain" == *. || "$domain" == *..* ]]; then
        return 1
    fi

    if [[ ! "$domain" =~ [A-Za-z] ]]; then
        return 1
    fi

    return 0
}

confirm_continue() {
    local prompt="$1"

    if [[ "$ASSUME_YES" == "1" ]]; then
        echo -e "${YELLOW}[!] ${prompt} --yes enabled, continuing${NC}"
        return 0
    fi

    local answer
    read -rp "$(echo -e "${YELLOW}[?] ${prompt} (y/n): ${NC}")" answer
    [[ "$answer" == "y" ]]
}

report_port_status() {
    local port="$1"

    if ss -lnt "( sport = :$port )" 2>/dev/null | tail -n +2 | grep -q .; then
        echo -e "${GREEN}[✓] Port ${port} has an active listener${NC}"
    else
        echo -e "${YELLOW}[!] Port ${port} has no active listener right now${NC}"
    fi
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --domain)
            [[ $# -lt 2 ]] && { echo "Missing value for --domain"; exit 1; }
            DOMAIN="$2"
            shift 2
            ;;
        --stub)
            [[ $# -lt 2 ]] && { echo "Missing value for --stub"; exit 1; }
            STUB_CHOICE="$2"
            shift 2
            ;;
        --yes)
            ASSUME_YES="1"
            shift
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            echo -e "${RED}[✗] Unknown argument: $1${NC}"
            usage
            exit 1
            ;;
    esac
done

echo -e "${CYAN}"
cat << 'BANNER'
 ╔═══════════════════════════════════════════════╗
 ║       SelfSteal Caddy Stub Installer          ║
 ║       For Remnawave + Xray Reality nodes       ║
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
if [[ -z "$DOMAIN" ]]; then
    read -rp "$(echo -e "${YELLOW}[?] Enter your domain: ${NC}")" DOMAIN
fi

DOMAIN=$(trim "$DOMAIN")
DOMAIN=${DOMAIN,,}
DOMAIN=${DOMAIN%.}

if [[ -z "$DOMAIN" ]]; then
    echo -e "${RED}[✗] Domain cannot be empty${NC}"
    exit 1
fi

if ! validate_domain "$DOMAIN"; then
    echo -e "${RED}[✗] Invalid domain: ${DOMAIN}${NC}"
    echo -e "    Allowed: letters, digits, dots and hyphens only"
    exit 1
fi

# ---- Stub page selection ----
echo ""
echo -e "${BOLD}  Choose a stub page:${NC}"
echo ""
echo -e "  ${CYAN}1)${NC} ${BOLD}Nexus Digital${NC}      ${DIM}- Clean enterprise software landing page${NC}"
echo -e "  ${CYAN}2)${NC} ${BOLD}Stratus Works${NC}      ${DIM}- Cloud and infrastructure consulting site${NC}"
echo -e "  ${CYAN}3)${NC} ${BOLD}Your Custom Page${NC}    ${DIM}- Your provided corporate landing page${NC}"
echo ""
if [[ -z "${STUB_CHOICE:-}" || ! "$STUB_CHOICE" =~ ^[1-3]$ ]]; then
    read -rp "$(echo -e "${YELLOW}[?] Select (1/2/3) [default: 1]: ${NC}")" STUB_CHOICE
fi

STUB_CHOICE=${STUB_CHOICE:-1}

if [[ ! "$STUB_CHOICE" =~ ^[1-3]$ ]]; then
    echo -e "${YELLOW}[!] Invalid choice, using default (1)${NC}"
    STUB_CHOICE=1
fi

STUB_NAMES=("Nexus Digital" "Stratus Works" "Your Custom Page")
echo -e "${GREEN}[✓] Selected: ${STUB_NAMES[$((STUB_CHOICE-1))]}${NC}"

# ---- Check DNS ----
echo -e "${CYAN}[*] Checking DNS for ${DOMAIN}...${NC}"

SERVER_IP=$(curl -s4 --max-time 5 ifconfig.me 2>/dev/null || curl -s4 --max-time 5 icanhazip.com 2>/dev/null || echo "unknown")
DOMAIN_IP=$(dig +short "$DOMAIN" A 2>/dev/null | head -1)

if [[ -z "$DOMAIN_IP" ]]; then
    echo -e "${RED}[✗] Domain ${DOMAIN} does not resolve to any IP${NC}"
    echo -e "    Make sure DNS A record points to this server: ${CYAN}${SERVER_IP}${NC}"
    confirm_continue "Continue anyway?" || exit 1
elif [[ "$SERVER_IP" == "$DOMAIN_IP" ]]; then
    echo -e "${GREEN}[✓] DNS OK: ${DOMAIN} → ${DOMAIN_IP}${NC}"
else
    echo -e "${YELLOW}[!] Warning: ${DOMAIN} → ${DOMAIN_IP}, but server IP is ${SERVER_IP}${NC}"
    confirm_continue "Continue anyway?" || exit 1
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

# ---- Create stub page ----
echo -e "${CYAN}[*] Creating stub page...${NC}"

mkdir -p /var/www/html

# --- Legacy stub: Minimal 404 (unused) ---
create_stub_minimal() {
cat > /var/www/html/index.html << 'HTMLEOF'
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
}

# --- Legacy stub: Cat Memes 404 (unused) ---
create_stub_cats() {
cat > /var/www/html/index.html << 'HTMLEOF'
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>404 - Oops!</title>
    <style>
        *{margin:0;padding:0;box-sizing:border-box}
        body{font-family:'Trebuchet MS','Segoe UI',Verdana,sans-serif;background:#1a1525;color:#e0e0e0;display:flex;justify-content:center;align-items:center;min-height:100vh;overflow:hidden}
        .container{text-align:center;padding:2rem;position:relative;z-index:1}
        .cat-wrapper{position:relative;display:inline-block;margin-bottom:1.5rem}
        .cat{font-size:8rem;line-height:1;filter:drop-shadow(0 0 30px rgba(255,150,200,0.3));animation:float 3s ease-in-out infinite}
        .sparkles{position:absolute;top:-10px;right:-20px;font-size:2rem;animation:spin 4s linear infinite}
        .error-code{font-size:clamp(4rem,15vw,8rem);font-weight:700;background:linear-gradient(135deg,#ff6b9d,#c44dff,#6e8efb);-webkit-background-clip:text;-webkit-text-fill-color:transparent;background-clip:text;line-height:1;margin-bottom:.5rem}
        .message{font-size:1.4rem;color:#c4a0ff;margin-bottom:.5rem;font-weight:600}
        .sub{font-size:1rem;color:#7a6b8a;max-width:400px;margin:0 auto}
        .paws{margin-top:1.5rem;font-size:1.5rem;opacity:.5;letter-spacing:8px;animation:walk 2s ease-in-out infinite}
        .bg-cats{position:fixed;top:0;left:0;width:100%;height:100%;pointer-events:none;z-index:0;overflow:hidden}
        .bg-cat{position:absolute;font-size:2rem;opacity:.06;animation:drift 20s linear infinite}
        .bg-cat:nth-child(1){left:10%;top:-5%;animation-delay:0s;animation-duration:18s}
        .bg-cat:nth-child(2){left:30%;top:-5%;animation-delay:3s;animation-duration:22s}
        .bg-cat:nth-child(3){left:50%;top:-5%;animation-delay:6s;animation-duration:20s}
        .bg-cat:nth-child(4){left:70%;top:-5%;animation-delay:2s;animation-duration:24s}
        .bg-cat:nth-child(5){left:90%;top:-5%;animation-delay:8s;animation-duration:19s}
        .bg-cat:nth-child(6){left:20%;top:-5%;animation-delay:11s;animation-duration:21s}
        .bg-cat:nth-child(7){left:60%;top:-5%;animation-delay:5s;animation-duration:23s}
        .bg-cat:nth-child(8){left:80%;top:-5%;animation-delay:9s;animation-duration:17s}
        @keyframes float{0%,100%{transform:translateY(0) rotate(0deg)}50%{transform:translateY(-15px) rotate(3deg)}}
        @keyframes spin{0%{transform:rotate(0deg)}100%{transform:rotate(360deg)}}
        @keyframes walk{0%,100%{transform:translateX(0)}50%{transform:translateX(10px)}}
        @keyframes drift{0%{transform:translateY(-50px) rotate(0deg)}100%{transform:translateY(110vh) rotate(360deg)}}
    </style>
</head>
<body>
    <div class="bg-cats">
        <div class="bg-cat">🐱</div><div class="bg-cat">😸</div><div class="bg-cat">🐈</div>
        <div class="bg-cat">😺</div><div class="bg-cat">🐱</div><div class="bg-cat">😻</div>
        <div class="bg-cat">🐈</div><div class="bg-cat">😸</div>
    </div>
    <div class="container">
        <div class="cat-wrapper">
            <div class="cat">😿</div>
            <div class="sparkles">✨</div>
        </div>
        <div class="error-code">404</div>
        <p class="message">The cat knocked this page off the table</p>
        <p class="sub">We looked everywhere — under the couch, behind the curtains, even in the box. This page simply doesn't exist.</p>
        <div class="paws">🐾 🐾 🐾</div>
    </div>
</body>
</html>
HTMLEOF
}

# --- Legacy stub: Business Site (unused) ---
create_stub_business() {
cat > /var/www/html/index.html << 'HTMLEOF'
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>NovaTech Solutions — Digital Innovation</title>
    <style>
        *{margin:0;padding:0;box-sizing:border-box}
        :root{--bg:#0c0f16;--surface:#13161f;--border:#1e2230;--accent:#4f7df5;--accent2:#7c5bf5;--text:#c8cdd8;--text-dim:#5a6072;--white:#eef0f6}
        body{font-family:'Segoe UI',Tahoma,Geneva,Verdana,sans-serif;background:var(--bg);color:var(--text);overflow-x:hidden}
        .noise{position:fixed;top:0;left:0;width:100%;height:100%;opacity:.03;pointer-events:none;background-image:url("data:image/svg+xml,%3Csvg viewBox='0 0 256 256' xmlns='http://www.w3.org/2000/svg'%3E%3Cfilter id='n'%3E%3CfeTurbulence type='fractalNoise' baseFrequency='0.9' numOctaves='4' stitchTiles='stitch'/%3E%3C/filter%3E%3Crect width='100%25' height='100%25' filter='url(%23n)'/%3E%3C/svg%3E");z-index:999}
        nav{position:fixed;top:0;width:100%;padding:1.2rem 3rem;display:flex;justify-content:space-between;align-items:center;z-index:10;backdrop-filter:blur(20px);background:rgba(12,15,22,.7);border-bottom:1px solid var(--border)}
        .logo{font-family:Georgia,'Times New Roman',serif;font-size:1.4rem;color:var(--white);font-weight:700;letter-spacing:-.5px}
        .logo span{color:var(--accent)}
        nav ul{list-style:none;display:flex;gap:2rem}
        nav a{color:var(--text-dim);text-decoration:none;font-size:.9rem;font-weight:500;transition:color .3s}
        nav a:hover{color:var(--white)}
        .hero{min-height:100vh;display:flex;align-items:center;justify-content:center;position:relative;padding:6rem 3rem 4rem}
        .hero-content{max-width:800px;text-align:center;position:relative;z-index:2}
        .badge{display:inline-block;padding:.4rem 1rem;border:1px solid var(--border);border-radius:50px;font-size:.8rem;color:var(--accent);margin-bottom:2rem;letter-spacing:1px;text-transform:uppercase}
        h1{font-family:Georgia,'Times New Roman',serif;font-size:clamp(2.5rem,6vw,4.5rem);color:var(--white);line-height:1.1;margin-bottom:1.5rem;letter-spacing:-.5px}
        h1 em{font-style:normal;background:linear-gradient(135deg,var(--accent),var(--accent2));-webkit-background-clip:text;-webkit-text-fill-color:transparent;background-clip:text}
        .hero p{font-size:1.15rem;color:var(--text-dim);max-width:550px;margin:0 auto 2.5rem;line-height:1.7}
        .cta-row{display:flex;gap:1rem;justify-content:center;flex-wrap:wrap}
        .btn{padding:.85rem 2rem;border-radius:8px;font-size:.95rem;font-weight:600;text-decoration:none;transition:all .3s;cursor:pointer;border:none;font-family:inherit}
        .btn-primary{background:linear-gradient(135deg,var(--accent),var(--accent2));color:#fff;box-shadow:0 4px 20px rgba(79,125,245,.25)}
        .btn-primary:hover{transform:translateY(-2px);box-shadow:0 8px 30px rgba(79,125,245,.35)}
        .btn-outline{background:transparent;color:var(--text);border:1px solid var(--border)}
        .btn-outline:hover{border-color:var(--accent);color:var(--white)}
        .glow{position:absolute;width:500px;height:500px;border-radius:50%;filter:blur(120px);opacity:.12;pointer-events:none}
        .glow-1{background:var(--accent);top:-100px;left:-100px}
        .glow-2{background:var(--accent2);bottom:-100px;right:-100px}
        .stats{display:flex;gap:3rem;justify-content:center;margin-top:4rem;padding-top:3rem;border-top:1px solid var(--border)}
        .stat{text-align:center}
        .stat-num{font-family:Georgia,'Times New Roman',serif;font-size:2.2rem;color:var(--white);font-weight:700}
        .stat-label{font-size:.85rem;color:var(--text-dim);margin-top:.3rem}
        .features{padding:4rem 3rem 5rem;max-width:1000px;margin:0 auto}
        .features-grid{display:grid;grid-template-columns:repeat(auto-fit,minmax(280px,1fr));gap:1.5rem}
        .feature-card{background:var(--surface);border:1px solid var(--border);border-radius:12px;padding:2rem;transition:all .3s}
        .feature-card:hover{border-color:var(--accent);transform:translateY(-3px)}
        .feature-icon{width:42px;height:42px;border-radius:10px;background:linear-gradient(135deg,rgba(79,125,245,.15),rgba(124,91,245,.15));display:flex;align-items:center;justify-content:center;font-size:1.2rem;margin-bottom:1rem}
        .feature-card h3{color:var(--white);font-size:1.05rem;margin-bottom:.5rem}
        .feature-card p{font-size:.9rem;color:var(--text-dim);line-height:1.6}
        footer{text-align:center;padding:2rem;border-top:1px solid var(--border);font-size:.8rem;color:var(--text-dim)}
        @media(max-width:600px){nav{padding:1rem 1.5rem}nav ul{display:none}.hero{padding:6rem 1.5rem 3rem}.stats{flex-direction:column;gap:1.5rem}.features{padding:2rem 1.5rem}}
    </style>
</head>
<body>
    <div class="noise"></div>
    <nav>
        <div class="logo">Nova<span>Tech</span></div>
        <ul>
            <li><a href="#">Solutions</a></li>
            <li><a href="#">About</a></li>
            <li><a href="#">Careers</a></li>
            <li><a href="#">Contact</a></li>
        </ul>
    </nav>
    <section class="hero">
        <div class="glow glow-1"></div>
        <div class="glow glow-2"></div>
        <div class="hero-content">
            <div class="badge">Digital Transformation Partner</div>
            <h1>Building the <em>future</em> of digital infrastructure</h1>
            <p>We help businesses scale their technology stack with modern cloud-native solutions, enterprise security, and seamless integration.</p>
            <div class="cta-row">
                <a class="btn btn-primary" href="#">Get Started</a>
                <a class="btn btn-outline" href="#">Learn More</a>
            </div>
            <div class="stats">
                <div class="stat"><div class="stat-num">500+</div><div class="stat-label">Clients Worldwide</div></div>
                <div class="stat"><div class="stat-num">99.9%</div><div class="stat-label">Uptime SLA</div></div>
                <div class="stat"><div class="stat-num">24/7</div><div class="stat-label">Expert Support</div></div>
            </div>
        </div>
    </section>
    <section class="features">
        <div class="features-grid">
            <div class="feature-card">
                <div class="feature-icon">☁️</div>
                <h3>Cloud Solutions</h3>
                <p>Multi-cloud architecture designed for resilience, performance, and cost optimization at any scale.</p>
            </div>
            <div class="feature-card">
                <div class="feature-icon">🔒</div>
                <h3>Enterprise Security</h3>
                <p>Zero-trust security framework with real-time threat detection and automated incident response.</p>
            </div>
            <div class="feature-card">
                <div class="feature-icon">⚡</div>
                <h3>Edge Computing</h3>
                <p>Low-latency processing at the edge with intelligent data routing and distributed computing.</p>
            </div>
        </div>
    </section>
    <footer>&copy; 2026 NovaTech Solutions. All rights reserved.</footer>
</body>
</html>
HTMLEOF
}


# --- Stub 1: Nexus Digital ---
create_stub_nexus() {
cat > /var/www/html/index.html << 'HTMLEOF'
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Nexus Digital - Global IT Engineering & Consultancy</title>
    <style>
        *{margin:0;padding:0;box-sizing:border-box}
        :root{--bg:#f8fbff;--soft:#eef4ff;--ink:#0f172a;--muted:#5b6b86;--line:#d7e3f6;--accent:#2563eb;--accent2:#4f46e5}
        body{font-family:'Segoe UI',Tahoma,Geneva,Verdana,sans-serif;background:linear-gradient(180deg,#f8fbff 0%,#fff 48%,#f7faff 100%);color:var(--ink)}
        .wrap{max-width:1180px;margin:0 auto;padding:0 24px}.nav{position:sticky;top:0;backdrop-filter:blur(16px);background:rgba(255,255,255,.82);border-bottom:1px solid rgba(215,227,246,.8)}
        .nav-inner{min-height:78px;display:flex;justify-content:space-between;align-items:center;gap:18px}.brand{display:flex;align-items:center;gap:12px;font-weight:800}.mark{width:42px;height:42px;border-radius:14px;background:linear-gradient(135deg,var(--accent),var(--accent2));display:grid;place-items:center;color:#fff}
        .brand-name{font-size:1.45rem}.brand-name span{color:var(--accent)}.links{display:flex;gap:24px;color:var(--muted);font-size:.84rem;font-weight:800;text-transform:uppercase;letter-spacing:.14em}.cta{padding:14px 22px;border-radius:999px;background:linear-gradient(135deg,var(--accent),var(--accent2));color:#fff;font-weight:800;text-decoration:none}
        .hero{padding:92px 0 116px;background:radial-gradient(circle at 85% 12%,rgba(96,165,250,.18),transparent 25%),radial-gradient(circle at 10% 22%,rgba(79,70,229,.11),transparent 28%)}
        .eyebrow{display:inline-block;padding:10px 16px;border-radius:999px;background:#edf4ff;color:var(--accent);font-size:.82rem;font-weight:800;text-transform:uppercase;letter-spacing:.14em}h1{margin-top:24px;font-size:clamp(3rem,7vw,5.7rem);line-height:1.02;letter-spacing:-.05em}h1 span{background:linear-gradient(135deg,var(--accent),var(--accent2));-webkit-background-clip:text;-webkit-text-fill-color:transparent;background-clip:text}
        .lead{max-width:760px;margin-top:22px;color:var(--muted);font-size:1.14rem;line-height:1.8}.actions{display:flex;gap:16px;flex-wrap:wrap;margin-top:32px}.btn{padding:18px 28px;border-radius:22px;text-decoration:none;font-weight:800}.btn-dark{background:#0f172a;color:#fff}.btn-light{background:#fff;border:1px solid var(--line);color:var(--muted)}
        .stats{margin-top:-48px}.stats-grid{display:grid;grid-template-columns:repeat(4,1fr);gap:18px;background:#fff;border:1px solid #edf2fb;border-radius:34px;padding:28px;box-shadow:0 25px 70px rgba(37,99,235,.12)}.stat{text-align:center}.stat strong{display:block;font-size:2.3rem;color:var(--accent)}.stat span{display:block;margin-top:8px;color:var(--muted);font-size:.76rem;font-weight:800;text-transform:uppercase;letter-spacing:.18em}
        .section{padding:100px 0}.cards{display:grid;grid-template-columns:repeat(3,1fr);gap:22px}.card{padding:32px;border:1px solid #edf2fb;border-radius:30px;background:#fff;box-shadow:0 16px 40px rgba(148,163,184,.08)}.icon{width:56px;height:56px;border-radius:18px;display:grid;place-items:center;font-weight:900;margin-bottom:20px}.blue{background:#eaf2ff;color:var(--accent)}.indigo{background:#eef0ff;color:var(--accent2)}.emerald{background:#ecfdf5;color:#059669}.card h3{font-size:1.45rem;margin-bottom:12px}.card p{color:var(--muted);line-height:1.75}
        .dark{background:#0f172a;color:#fff}.dark-grid{display:grid;grid-template-columns:1.1fr .9fr;gap:34px;align-items:center}.dark p{color:#94a3b8;line-height:1.8}.tiles{display:grid;grid-template-columns:repeat(2,1fr);gap:16px}.tile{padding:28px;border-radius:26px;background:rgba(255,255,255,.05);border:1px solid rgba(255,255,255,.09);text-align:center}.tile strong{display:block;color:#60a5fa;font-size:1.9rem}.tile span{display:block;margin-top:8px;color:#94a3b8;font-size:.78rem;font-weight:800;text-transform:uppercase;letter-spacing:.18em}
        .contact{padding:32px;border-radius:40px;background:linear-gradient(135deg,#2563eb,#4f46e5);color:#fff}.contact-grid{display:grid;grid-template-columns:1fr 1fr;gap:28px}.form{background:#fff;border-radius:28px;padding:28px;display:grid;gap:14px}input,textarea{width:100%;padding:16px 18px;border:1px solid #e2e8f0;border-radius:18px;background:#f8fafc;font:inherit}textarea{min-height:120px;resize:vertical}button{border:0;padding:18px;border-radius:18px;background:#2563eb;color:#fff;font:inherit;font-weight:800}footer{padding:64px 0;color:#94a3b8}
        @media(max-width:980px){.links,.cards,.dark-grid,.contact-grid,.stats-grid{grid-template-columns:1fr;display:grid}}
    </style>
</head>
<body>
    <nav class="nav"><div class="wrap nav-inner"><div class="brand"><div class="mark">N</div><div class="brand-name">Nexus<span>Digital</span></div></div><div class="links"><span>Services</span><span>About</span><span>Portfolio</span><span>Contact</span></div><a class="cta" href="#contact">Get a Quote</a></div></nav>
    <section class="hero"><div class="wrap"><div class="eyebrow">Engineering The Future</div><h1>Scale Your Business Through <span>Technology</span></h1><p class="lead">We build digital products, cloud platforms and secure internal systems for teams that need software delivery to feel fast, polished and dependable.</p><div class="actions"><a class="btn btn-dark" href="#contact">Start Partnership</a><a class="btn btn-light" href="#services">View Services</a></div></div></section>
    <section class="stats"><div class="wrap"><div class="stats-grid"><div class="stat"><strong>10+</strong><span>Years Experience</span></div><div class="stat"><strong>250+</strong><span>Projects Delivered</span></div><div class="stat"><strong>98%</strong><span>Client Retention</span></div><div class="stat"><strong>50+</strong><span>Top Engineers</span></div></div></div></section>
    <section id="services" class="section"><div class="wrap"><div class="cards"><div class="card"><div class="icon blue">DEV</div><h3>Custom Software</h3><p>End-to-end development of internal tools, portals and customer-facing applications tailored to your workflows.</p></div><div class="card"><div class="icon indigo">SEC</div><h3>Cloud & Security</h3><p>Modern infrastructure, access boundaries and deployment hardening for production systems that cannot afford chaos.</p></div><div class="card"><div class="icon emerald">AI</div><h3>AI & Data</h3><p>Practical analytics and automation workflows that turn operational data into forecasting and decision support.</p></div></div></div></section>
    <section class="section dark"><div class="wrap dark-grid"><div><h2>Trusted partner for global innovators</h2><p>Nexus Digital helps product teams bridge complex engineering and clear business outcomes with strong delivery discipline and clean user-facing execution.</p></div><div class="tiles"><div class="tile"><strong>USA</strong><span>Headquarters</span></div><div class="tile"><strong>Germany</strong><span>R&amp;D Office</span></div><div class="tile"><strong>UAE</strong><span>Sales Hub</span></div><div class="tile"><strong>Singapore</strong><span>Global Support</span></div></div></div></section>
    <section id="contact" class="section"><div class="wrap"><div class="contact"><div class="contact-grid"><div><h2>Ready to build something extraordinary?</h2><p style="margin-top:18px;color:#dbeafe;line-height:1.8">Share your goals and our engineering team will prepare a practical implementation plan for product delivery, infrastructure or security work.</p></div><form class="form"><input type="text" placeholder="Full Name"><input type="email" placeholder="Work Email"><textarea placeholder="Briefly describe your goals..."></textarea><button type="button">Send Inquiry</button></form></div></div></div></section>
    <footer><div class="wrap">&copy; 2026 Nexus Digital Group. All rights reserved.</div></footer>
</body>
</html>
HTMLEOF
}

# --- Stub 2: Stratus Works ---
create_stub_stratus() {
cat > /var/www/html/index.html << 'HTMLEOF'
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Stratus Works - Cloud Infrastructure and Delivery Engineering</title>
    <style>
        *{margin:0;padding:0;box-sizing:border-box}
        :root{--ink:#0f172a;--muted:#64748b;--line:#dbe7f3;--blue:#0f6cdd;--cyan:#0891b2}
        body{font-family:'Segoe UI',Tahoma,Geneva,Verdana,sans-serif;background:radial-gradient(circle at top left,rgba(8,145,178,.10),transparent 24%),radial-gradient(circle at bottom right,rgba(15,108,221,.08),transparent 24%),linear-gradient(180deg,#fbfdff 0%,#f3f8fc 100%);color:var(--ink)}
        .wrap{max-width:1160px;margin:0 auto;padding:0 24px}.nav{padding:24px 0}.nav-in{display:flex;justify-content:space-between;align-items:center;gap:18px;padding:18px 22px;background:rgba(255,255,255,.82);border:1px solid rgba(219,231,243,.85);backdrop-filter:blur(16px);border-radius:24px}.logo{display:flex;align-items:center;gap:12px;font-weight:900}.logo-mark{width:42px;height:42px;border-radius:14px;background:linear-gradient(135deg,var(--blue),var(--cyan));display:grid;place-items:center;color:#fff}
        .hero{padding:60px 0 90px}.grid{display:grid;grid-template-columns:1.05fr .95fr;gap:26px;align-items:center}h1{font-size:clamp(3rem,6vw,5.2rem);line-height:1.03;letter-spacing:-.06em}h1 span{color:var(--blue)}p{color:var(--muted);line-height:1.82}.lead{margin-top:22px;font-size:1.1rem;max-width:640px}
        .actions{display:flex;gap:16px;flex-wrap:wrap;margin-top:30px}.btn{padding:18px 26px;border-radius:20px;text-decoration:none;font-weight:800}.primary{background:linear-gradient(135deg,var(--blue),var(--cyan));color:#fff}.secondary{background:#fff;border:1px solid var(--line);color:var(--ink)}
        .panel{padding:28px;border-radius:32px;background:linear-gradient(180deg,#fff,#f8fbff);border:1px solid var(--line);box-shadow:0 22px 55px rgba(15,108,221,.12)}.mini-grid{display:grid;grid-template-columns:repeat(2,1fr);gap:16px}.mini{padding:18px;border-radius:20px;background:#fff;border:1px solid #e7eef8}.mini strong{display:block;font-size:1.65rem}.mini span{display:block;margin-top:8px;color:var(--muted);font-size:.84rem;font-weight:700}
        .section{padding:90px 0}.heading{text-align:center;max-width:720px;margin:0 auto 50px}.heading h2{font-size:clamp(2.1rem,4vw,3.6rem);line-height:1.08;letter-spacing:-.05em}.cards{display:grid;grid-template-columns:repeat(3,1fr);gap:22px}.card{padding:30px;border-radius:28px;background:#fff;border:1px solid var(--line);box-shadow:0 16px 40px rgba(148,163,184,.08)}.card h3{font-size:1.4rem;margin-bottom:12px}.metrics{display:grid;grid-template-columns:repeat(4,1fr);gap:18px;margin-top:24px}
        .metric{padding:24px;border-radius:24px;background:#0f172a;color:#fff;text-align:center}.metric strong{display:block;font-size:2rem;color:#67e8f9}.metric span{display:block;margin-top:8px;color:#94a3b8;font-size:.8rem;font-weight:800;text-transform:uppercase;letter-spacing:.16em}
        .contact{padding:34px;border-radius:34px;background:#fff;border:1px solid var(--line);box-shadow:0 22px 55px rgba(15,108,221,.12)}.contact-grid{display:grid;grid-template-columns:1fr 1fr;gap:28px}input,select,textarea{width:100%;padding:16px 18px;border:1px solid var(--line);border-radius:18px;background:#f8fbff;font:inherit;margin-top:12px}textarea{min-height:120px;resize:vertical}button{margin-top:12px;border:0;padding:18px 20px;border-radius:18px;background:linear-gradient(135deg,var(--blue),#0f766e);color:#fff;font:inherit;font-weight:800}footer{padding:56px 0 68px;text-align:center;color:#94a3b8}
        @media(max-width:980px){.grid,.cards,.metrics,.contact-grid{grid-template-columns:1fr}}
    </style>
</head>
<body>
    <div class="wrap"><div class="nav"><div class="nav-in"><div class="logo"><div class="logo-mark">S</div><div>Stratus Works</div></div><div style="font-weight:800;color:var(--muted)">Infrastructure / Security / Delivery</div></div></div><section class="hero"><div class="grid"><div><h1>Cloud delivery for teams that need <span>clarity</span> and speed</h1><p class="lead">Stratus Works helps companies modernize infrastructure, deployment pipelines and internal developer platforms with clear execution and security-first defaults.</p><div class="actions"><a class="btn primary" href="#contact">Talk to Engineering</a><a class="btn secondary" href="#services">See Capabilities</a></div></div><div class="panel"><div class="mini-grid"><div class="mini"><strong>99.98%</strong><span>Service availability</span></div><div class="mini"><strong>14m</strong><span>Mean rollout time</span></div><div class="mini"><strong>42</strong><span>Regions supported</span></div><div class="mini"><strong>7x</strong><span>Faster recovery</span></div></div></div></div></section><section id="services" class="section"><div class="heading"><h2>Infrastructure, delivery and platform services in one operating model</h2><p>We work with teams that need more than ad-hoc DevOps support and want a repeatable operating baseline for modern delivery.</p></div><div class="cards"><div class="card"><h3>Deployment Systems</h3><p>Pipeline design, artifact promotion and release safety controls tailored to your stack and compliance profile.</p></div><div class="card"><h3>Cloud Platforms</h3><p>Kubernetes, observability and policy baselines that support multi-team application delivery without platform sprawl.</p></div><div class="card"><h3>Security Hardening</h3><p>Identity boundaries, workload isolation and incident-ready telemetry tuned for production environments.</p></div></div><div class="metrics"><div class="metric"><strong>180+</strong><span>Clusters Managed</span></div><div class="metric"><strong>24/7</strong><span>Incident Readiness</span></div><div class="metric"><strong>35%</strong><span>Lower Cloud Waste</span></div><div class="metric"><strong>5 Days</strong><span>Typical Migration</span></div></div></section><section id="contact" class="section"><div class="contact"><div class="contact-grid"><div><h2 style="font-size:clamp(2rem,4vw,3.3rem);line-height:1.1;letter-spacing:-.05em">Need a cleaner infrastructure story?</h2><p style="margin-top:18px">Tell us where delivery friction, security gaps or scaling pain are showing up and we will outline a realistic platform improvement path.</p></div><div><input type="text" placeholder="Your Name"><input type="email" placeholder="Work Email"><select><option>Platform Modernization</option><option>Cloud Migration</option><option>Security Hardening</option></select><textarea placeholder="Describe the current challenge..."></textarea><button type="button">Request Consultation</button></div></div></div></section><footer>&copy; 2026 Stratus Works. Platform engineering, infrastructure modernization and cloud security delivery.</footer></div>
</body>
</html>
HTMLEOF
}

# --- Stub 3: User-provided page ---
create_stub_custom() {
cat > /var/www/html/index.html << 'HTMLEOF'
<!DOCTYPE html>
<html lang="en" class="scroll-smooth">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Nexus Digital — Global IT Engineering & Consultancy</title>
    <script src="https://cdn.tailwindcss.com"></script>
    <link href="https://fonts.googleapis.com/css2?family=Inter:wght@300;400;500;600;700&display=swap" rel="stylesheet">
    <style>
        body { font-family: 'Inter', sans-serif; }
        .hero-gradient {
            background: radial-gradient(circle at top right, #f8fafc 0%, #f1f5f9 100%);
        }
        .glass-card {
            background: rgba(255, 255, 255, 0.7);
            backdrop-filter: blur(10px);
            border: 1px solid rgba(255, 255, 255, 0.3);
        }
    </style>
</head>
<body class="bg-white text-slate-900">

    <!-- Navigation -->
    <nav class="sticky top-0 z-50 bg-white/80 backdrop-blur-md border-b border-slate-100">
        <div class="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8">
            <div class="flex justify-between h-20 items-center">
                <div class="flex items-center gap-2">
                    <div class="w-10 h-10 bg-blue-600 rounded-xl flex items-center justify-center text-white font-bold text-xl shadow-lg shadow-blue-200">N</div>
                    <span class="text-2xl font-bold tracking-tight">Nexus<span class="text-blue-600">Digital</span></span>
                </div>
                <div class="hidden md:flex space-x-10 text-sm font-semibold text-slate-600">
                    <a href="#services" class="hover:text-blue-600 transition-colors uppercase tracking-wider">Services</a>
                    <a href="#about" class="hover:text-blue-600 transition-colors uppercase tracking-wider">About Us</a>
                    <a href="#portfolio" class="hover:text-blue-600 transition-colors uppercase tracking-wider">Portfolio</a>
                    <a href="#contact" class="hover:text-blue-600 transition-colors uppercase tracking-wider">Contact</a>
                </div>
                <a href="#contact" class="bg-blue-600 text-white px-6 py-2.5 rounded-full text-sm font-bold hover:bg-blue-700 transition shadow-lg shadow-blue-200">
                    Get a Quote
                </a>
            </div>
        </div>
    </nav>

    <!-- Hero Section -->
    <header class="hero-gradient pt-24 pb-40 overflow-hidden">
        <div class="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 text-center relative">
            <div class="inline-block px-4 py-1.5 mb-6 text-sm font-bold tracking-wide text-blue-600 uppercase bg-blue-50 rounded-full">
                Engineering the Future
            </div>
            <h1 class="text-6xl md:text-7xl font-extrabold text-slate-900 tracking-tight mb-8 leading-[1.1]">
                Scale Your Business <br>
                <span class="text-transparent bg-clip-text bg-gradient-to-r from-blue-600 to-indigo-600">Through Technology</span>
            </h1>
            <p class="text-xl text-slate-600 max-w-3xl mx-auto mb-12 leading-relaxed">
                We are a full-cycle software development company. From startup MVPs to enterprise-level high-load systems, we build digital products that drive growth.
            </p>
            <div class="flex flex-col sm:flex-row justify-center gap-6">
                <a href="#contact" class="bg-slate-900 text-white px-10 py-5 rounded-2xl font-bold hover:bg-slate-800 transition shadow-xl shadow-slate-200">Start Partnership</a>
                <a href="#portfolio" class="bg-white border border-slate-200 text-slate-600 px-10 py-5 rounded-2xl font-bold hover:bg-slate-50 transition">View Case Studies</a>
            </div>
        </div>
    </header>

    <!-- Stats Section -->
    <section class="-mt-20 relative z-10 max-w-7xl mx-auto px-4 sm:px-6 lg:px-8">
        <div class="grid grid-cols-2 md:grid-cols-4 gap-4 md:gap-8 bg-white p-8 md:p-12 rounded-[2.5rem] shadow-2xl shadow-slate-200 border border-slate-50">
            <div class="text-center">
                <div class="text-4xl font-extrabold text-blue-600 mb-2">10+</div>
                <div class="text-slate-500 font-medium uppercase text-xs tracking-widest">Years Experience</div>
            </div>
            <div class="text-center">
                <div class="text-4xl font-extrabold text-blue-600 mb-2">250+</div>
                <div class="text-slate-500 font-medium uppercase text-xs tracking-widest">Projects Delivered</div>
            </div>
            <div class="text-center">
                <div class="text-4xl font-extrabold text-blue-600 mb-2">98%</div>
                <div class="text-slate-500 font-medium uppercase text-xs tracking-widest">Client Retention</div>
            </div>
            <div class="text-center">
                <div class="text-4xl font-extrabold text-blue-600 mb-2">50+</div>
                <div class="text-slate-500 font-medium uppercase text-xs tracking-widest">Top Engineers</div>
            </div>
        </div>
    </section>

    <!-- Services Section -->
    <section id="services" class="py-32">
        <div class="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8">
            <div class="flex flex-col md:flex-row justify-between items-end mb-20 gap-8">
                <div class="max-w-xl text-left">
                    <h2 class="text-4xl font-bold text-slate-900 mb-6 leading-tight">Comprehensive Digital Solutions for Modern Enterprises</h2>
                    <p class="text-slate-500">We don't just write code; we solve business problems with elegant architectural decisions and cutting-edge tech.</p>
                </div>
                <a href="#contact" class="text-blue-600 font-bold hover:underline">Explore all services &rarr;</a>
            </div>
            
            <div class="grid md:grid-cols-3 gap-8">
                <!-- Card 1 -->
                <div class="p-10 border border-slate-100 rounded-[2rem] hover:shadow-2xl transition-all group bg-white">
                    <div class="w-14 h-14 bg-blue-50 text-blue-600 rounded-2xl flex items-center justify-center mb-8 group-hover:bg-blue-600 group-hover:text-white transition-all duration-300">
                        <svg xmlns="http://www.w3.org/2000/svg" class="w-7 h-7" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                            <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M10 20l4-16m4 4l4 4-4 4M6 16l-4-4 4-4" />
                        </svg>
                    </div>
                    <h3 class="text-2xl font-bold mb-4 text-slate-900">Custom Software</h3>
                    <p class="text-slate-500 leading-relaxed mb-6">
                        End-to-end development of bespoke applications tailored to your specific business workflows and user needs.
                    </p>
                    <ul class="space-y-3 text-sm font-medium text-slate-700">
                        <li class="flex items-center gap-2">
                            <span class="w-1.5 h-1.5 bg-blue-600 rounded-full"></span> Enterprise Web Apps
                        </li>
                        <li class="flex items-center gap-2">
                            <span class="w-1.5 h-1.5 bg-blue-600 rounded-full"></span> Mobile Development
                        </li>
                    </ul>
                </div>

                <!-- Card 2 -->
                <div class="p-10 border border-slate-100 rounded-[2rem] hover:shadow-2xl transition-all group bg-white">
                    <div class="w-14 h-14 bg-indigo-50 text-indigo-600 rounded-2xl flex items-center justify-center mb-8 group-hover:bg-indigo-600 group-hover:text-white transition-all duration-300">
                        <svg xmlns="http://www.w3.org/2000/svg" class="w-7 h-7" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                            <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 15v2m-6 4h12a2 2 0 002-2v-6a2 2 0 00-2-2H6a2 2 0 00-2 2v6a2 2 0 00-2 2zm10-10V7a4 4 0 00-8 0v4h8z" />
                        </svg>
                    </div>
                    <h3 class="text-2xl font-bold mb-4 text-slate-900">Cloud & Security</h3>
                    <p class="text-slate-500 leading-relaxed mb-6">
                        We build highly secure infrastructure using AWS/GCP and implement military-grade encryption for your data.
                    </p>
                    <ul class="space-y-3 text-sm font-medium text-slate-700">
                        <li class="flex items-center gap-2">
                            <span class="w-1.5 h-1.5 bg-indigo-600 rounded-full"></span> Penetration Testing
                        </li>
                        <li class="flex items-center gap-2">
                            <span class="w-1.5 h-1.5 bg-indigo-600 rounded-full"></span> Cloud Infrastructure
                        </li>
                    </ul>
                </div>

                <!-- Card 3 -->
                <div class="p-10 border border-slate-100 rounded-[2rem] hover:shadow-2xl transition-all group bg-white">
                    <div class="w-14 h-14 bg-emerald-50 text-emerald-600 rounded-2xl flex items-center justify-center mb-8 group-hover:bg-emerald-600 group-hover:text-white transition-all duration-300">
                        <svg xmlns="http://www.w3.org/2000/svg" class="w-7 h-7" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                            <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M13 10V3L4 14h7v7l9-11h-7z" />
                        </svg>
                    </div>
                    <h3 class="text-2xl font-bold mb-4 text-slate-900">AI & Big Data</h3>
                    <p class="text-slate-500 leading-relaxed mb-6">
                        Unlock insights from your data. We implement machine learning models to automate decision-making.
                    </p>
                    <ul class="space-y-3 text-sm font-medium text-slate-700">
                        <li class="flex items-center gap-2">
                            <span class="w-1.5 h-1.5 bg-emerald-600 rounded-full"></span> Predictive Analytics
                        </li>
                        <li class="flex items-center gap-2">
                            <span class="w-1.5 h-1.5 bg-emerald-600 rounded-full"></span> LLM Integration
                        </li>
                    </ul>
                </div>
            </div>
        </div>
    </section>

    <!-- About Section -->
    <section id="about" class="py-24 bg-slate-900 text-white overflow-hidden">
        <div class="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8">
            <div class="grid lg:grid-cols-2 gap-20 items-center">
                <div class="relative">
                    <div class="absolute -top-20 -left-20 w-64 h-64 bg-blue-600 rounded-full blur-[120px] opacity-20"></div>
                    <h2 class="text-5xl font-bold mb-8 leading-tight">Trusted Partner for <br><span class="text-blue-500">Global Innovators</span></h2>
                    <p class="text-slate-400 text-lg mb-8 leading-relaxed">
                        Founded in 2016, Nexus Digital started with a mission to bridge the gap between complex engineering and intuitive user experience. Today, we operate globally, helping Fortune 500 companies and ambitious startups alike.
                    </p>
                    <div class="space-y-6">
                        <div class="flex gap-4">
                            <div class="flex-shrink-0 w-12 h-12 bg-white/10 rounded-full flex items-center justify-center">
                                <svg xmlns="http://www.w3.org/2000/svg" class="w-6 h-6 text-blue-500" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                                    <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M5 13l4 4L19 7" />
                                </svg>
                            </div>
                            <div>
                                <h4 class="font-bold text-xl">Agile Methodology</h4>
                                <p class="text-slate-500">Fast iterations and transparent communication at every step.</p>
                            </div>
                        </div>
                        <div class="flex gap-4">
                            <div class="flex-shrink-0 w-12 h-12 bg-white/10 rounded-full flex items-center justify-center">
                                <svg xmlns="http://www.w3.org/2000/svg" class="w-6 h-6 text-blue-500" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                                    <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M5 13l4 4L19 7" />
                                </svg>
                            </div>
                            <div>
                                <h4 class="font-bold text-xl">Top 3% Talent</h4>
                                <p class="text-slate-500">We hire only the best engineers from around the globe.</p>
                            </div>
                        </div>
                    </div>
                </div>
                <div class="grid grid-cols-2 gap-4">
                    <div class="bg-white/5 p-8 rounded-3xl border border-white/10 text-center">
                        <div class="text-3xl font-bold text-blue-500 mb-1">USA</div>
                        <p class="text-sm text-slate-500 uppercase tracking-widest">Headquarters</p>
                    </div>
                    <div class="bg-white/5 p-8 rounded-3xl border border-white/10 mt-8 text-center">
                        <div class="text-3xl font-bold text-blue-500 mb-1">Germany</div>
                        <p class="text-sm text-slate-500 uppercase tracking-widest">R&D Office</p>
                    </div>
                    <div class="bg-white/5 p-8 rounded-3xl border border-white/10 text-center">
                        <div class="text-3xl font-bold text-blue-500 mb-1">UAE</div>
                        <p class="text-sm text-slate-500 uppercase tracking-widest">Sales Hub</p>
                    </div>
                    <div class="bg-white/5 p-8 rounded-3xl border border-white/10 mt-8 text-center">
                        <div class="text-3xl font-bold text-blue-500 mb-1">Singapore</div>
                        <p class="text-sm text-slate-500 uppercase tracking-widest">Global Support</p>
                    </div>
                </div>
            </div>
        </div>
    </section>

    <!-- Portfolio Section -->
    <section id="portfolio" class="py-32 bg-slate-50">
        <div class="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 text-center">
            <h2 class="text-4xl font-bold mb-4">Our Featured Case Studies</h2>
            <p class="text-slate-500 mb-16 max-w-2xl mx-auto">Take a look at how we've helped our clients transform their businesses through custom digital solutions.</p>
            
            <div class="grid md:grid-cols-2 gap-12">
                <!-- Case 1 -->
                <div class="group cursor-pointer">
                    <div class="bg-slate-200 aspect-video rounded-[2.5rem] mb-8 overflow-hidden relative">
                        <div class="absolute inset-0 bg-gradient-to-br from-blue-600/20 to-indigo-600/20 flex items-center justify-center font-bold text-slate-400">
                            [FinTech Ecosystem App]
                        </div>
                        <div class="absolute inset-0 bg-slate-900/40 opacity-0 group-hover:opacity-100 transition-opacity flex items-center justify-center">
                            <span class="bg-white text-slate-900 px-8 py-3 rounded-full font-bold">View Case Study</span>
                        </div>
                    </div>
                    <div class="text-left px-4">
                        <span class="text-blue-600 font-bold text-sm tracking-widest uppercase mb-2 block">FinTech</span>
                        <h3 class="text-2xl font-bold mb-3 group-hover:text-blue-600 transition">NextGen Banking Platform</h3>
                        <p class="text-slate-500">We built a scalable microservices architecture for a neo-bank, processing over $500M monthly.</p>
                    </div>
                </div>
                <!-- Case 2 -->
                <div class="group cursor-pointer">
                    <div class="bg-slate-200 aspect-video rounded-[2.5rem] mb-8 overflow-hidden relative">
                        <div class="absolute inset-0 bg-gradient-to-br from-emerald-600/20 to-teal-600/20 flex items-center justify-center font-bold text-slate-400">
                            [AI Analytics Dashboard]
                        </div>
                        <div class="absolute inset-0 bg-slate-900/40 opacity-0 group-hover:opacity-100 transition-opacity flex items-center justify-center">
                            <span class="bg-white text-slate-900 px-8 py-3 rounded-full font-bold">View Case Study</span>
                        </div>
                    </div>
                    <div class="text-left px-4">
                        <span class="text-indigo-600 font-bold text-sm tracking-widest uppercase mb-2 block">E-commerce</span>
                        <h3 class="text-2xl font-bold mb-3 group-hover:text-indigo-600 transition">Retail Predictive Analytics</h3>
                        <p class="text-slate-500">Implementing an AI model that predicts inventory needs with 94% accuracy for a global retail chain.</p>
                    </div>
                </div>
            </div>
        </div>
    </section>

    <!-- Technology Stack -->
    <section class="py-24 border-y border-slate-100">
        <div class="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8">
            <h3 class="text-center text-slate-400 font-bold text-sm uppercase tracking-[0.3em] mb-12">Technologies We Master</h3>
            <div class="flex flex-wrap justify-center gap-12 md:gap-20 opacity-50 grayscale hover:grayscale-0 transition duration-500">
                <span class="text-2xl font-black text-slate-900">REACT</span>
                <span class="text-2xl font-black text-slate-900">NODE.JS</span>
                <span class="text-2xl font-black text-slate-900">AWS</span>
                <span class="text-2xl font-black text-slate-900">PYTHON</span>
                <span class="text-2xl font-black text-slate-900">KUBERNETES</span>
                <span class="text-2xl font-black text-slate-900">POSTGRES</span>
            </div>
        </div>
    </section>

    <!-- Contact Form Section -->
    <section id="contact" class="py-32 bg-white">
        <div class="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8">
            <div class="bg-blue-600 rounded-[3rem] p-8 md:p-20 overflow-hidden relative">
                <div class="absolute top-0 right-0 w-96 h-96 bg-white/10 rounded-full blur-[100px]"></div>
                <div class="absolute -bottom-20 -left-20 w-80 h-80 bg-black/10 rounded-full blur-[80px]"></div>
                
                <div class="grid lg:grid-cols-2 gap-16 relative">
                    <div class="text-white">
                        <h2 class="text-5xl font-bold mb-8 leading-tight">Ready to build something <br>extraordinary?</h2>
                        <p class="text-blue-100 text-lg mb-12">Fill out the form and our CTO will reach out to you within 24 hours to schedule a deep-dive consultation.</p>
                        <div class="space-y-6">
                            <div class="flex items-center gap-4">
                                <div class="w-12 h-12 bg-white/20 rounded-xl flex items-center justify-center">
                                    <svg xmlns="http://www.w3.org/2000/svg" class="w-6 h-6" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                                        <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M3 8l7.89 5.26a2 2 0 002.22 0L21 8M5 19h14a2 2 0 002-2V7a2 2 0 00-2-2H5a2 2 0 00-2 2v10a2 2 0 002 2z" />
                                    </svg>
                                </div>
                                <span class="font-bold text-xl">hello@nexus.digital</span>
                            </div>
                            <div class="flex items-center gap-4">
                                <div class="w-12 h-12 bg-white/20 rounded-xl flex items-center justify-center">
                                    <svg xmlns="http://www.w3.org/2000/svg" class="w-6 h-6" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                                        <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M17.657 16.657L13.414 20.9a1.998 1.998 0 01-2.827 0l-4.244-4.243a8 8 0 1111.314 0z" />
                                        <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M15 11a3 3 0 11-6 0 3 3 0 016 0z" />
                                    </svg>
                                </div>
                                <span class="font-bold text-xl">San Francisco, CA</span>
                            </div>
                        </div>
                    </div>
                    
                    <div class="bg-white p-10 rounded-[2rem] shadow-2xl">
                        <form onsubmit="event.preventDefault(); document.getElementById('success-msg').classList.remove('hidden');" class="space-y-6">
                            <div class="grid md:grid-cols-2 gap-6">
                                <div>
                                    <label class="block text-sm font-bold mb-2 text-slate-700">Full Name</label>
                                    <input type="text" placeholder="John Doe" class="w-full px-5 py-4 rounded-xl border border-slate-100 bg-slate-50 focus:outline-none focus:ring-2 focus:ring-blue-600 focus:bg-white transition" required>
                                </div>
                                <div>
                                    <label class="block text-sm font-bold mb-2 text-slate-700">Work Email</label>
                                    <input type="email" placeholder="john@company.com" class="w-full px-5 py-4 rounded-xl border border-slate-100 bg-slate-50 focus:outline-none focus:ring-2 focus:ring-blue-600 focus:bg-white transition" required>
                                </div>
                            </div>
                            <div>
                                <label class="block text-sm font-bold mb-2 text-slate-700">Project Type</label>
                                <select class="w-full px-5 py-4 rounded-xl border border-slate-100 bg-slate-50 focus:outline-none focus:ring-2 focus:ring-blue-600 focus:bg-white transition appearance-none">
                                    <option>Web Application</option>
                                    <option>Mobile App (iOS/Android)</option>
                                    <option>AI / Machine Learning</option>
                                    <option>Cybersecurity Audit</option>
                                    <option>Other</option>
                                </select>
                            </div>
                            <div>
                                <label class="block text-sm font-bold mb-2 text-slate-700">Message</label>
                                <textarea rows="4" placeholder="Briefly describe your goals..." class="w-full px-5 py-4 rounded-xl border border-slate-100 bg-slate-50 focus:outline-none focus:ring-2 focus:ring-blue-600 focus:bg-white transition"></textarea>
                            </div>
                            <button type="submit" class="w-full bg-blue-600 text-white py-5 rounded-xl font-bold text-lg hover:bg-blue-700 transition-all transform hover:-translate-y-1 shadow-xl shadow-blue-200">
                                Send Inquiry
                            </button>
                            <div id="success-msg" class="hidden text-center p-4 bg-emerald-50 text-emerald-700 rounded-xl font-bold">
                                Done! Our team will contact you shortly.
                            </div>
                        </form>
                    </div>
                </div>
            </div>
        </div>
    </section>

    <!-- Footer -->
    <footer class="py-20 bg-slate-50 border-t border-slate-100">
        <div class="max-w-7xl mx-auto px-4">
            <div class="grid md:grid-cols-4 gap-12 mb-16">
                <div class="col-span-2">
                    <div class="flex items-center gap-2 mb-6">
                        <div class="w-8 h-8 bg-blue-600 rounded-lg flex items-center justify-center text-white font-bold">N</div>
                        <span class="text-xl font-bold tracking-tight text-slate-900">Nexus<span class="text-blue-600">Digital</span></span>
                    </div>
                    <p class="text-slate-500 max-w-sm mb-8 leading-relaxed">
                        Leading provider of complex IT engineering. We help the world's most innovative companies build the next generation of digital products.
                    </p>
                    <div class="flex gap-4">
                        <div class="w-10 h-10 bg-slate-200 rounded-full flex items-center justify-center hover:bg-blue-600 hover:text-white transition cursor-pointer">
                            <span class="font-bold uppercase text-[10px]">In</span>
                        </div>
                        <div class="w-10 h-10 bg-slate-200 rounded-full flex items-center justify-center hover:bg-blue-600 hover:text-white transition cursor-pointer">
                            <span class="font-bold uppercase text-[10px]">Tw</span>
                        </div>
                        <div class="w-10 h-10 bg-slate-200 rounded-full flex items-center justify-center hover:bg-blue-600 hover:text-white transition cursor-pointer">
                            <span class="font-bold uppercase text-[10px]">Gh</span>
                        </div>
                    </div>
                </div>
                <div>
                    <h5 class="font-bold text-slate-900 mb-6 uppercase text-xs tracking-widest">Company</h5>
                    <ul class="space-y-4 text-slate-500 text-sm">
                        <li><a href="#about" class="hover:text-blue-600">Our Story</a></li>
                        <li><a href="#portfolio" class="hover:text-blue-600">Portfolio</a></li>
                        <li><a href="#" class="hover:text-blue-600">Careers</a></li>
                        <li><a href="#contact" class="hover:text-blue-600">Partner Program</a></li>
                    </ul>
                </div>
                <div>
                    <h5 class="font-bold text-slate-900 mb-6 uppercase text-xs tracking-widest">Support</h5>
                    <ul class="space-y-4 text-slate-500 text-sm">
                        <li><a href="#" class="hover:text-blue-600">Knowledge Base</a></li>
                        <li><a href="#" class="hover:text-blue-600">Cookie Policy</a></li>
                        <li><a href="#" class="hover:text-blue-600">Security</a></li>
                        <li><a href="#" class="hover:text-blue-600">Terms of Use</a></li>
                    </ul>
                </div>
            </div>
            <div class="pt-12 border-t border-slate-200 text-center md:text-left flex flex-col md:flex-row justify-between items-center gap-4">
                <p class="text-slate-400 text-xs tracking-wide">© 2026 Nexus Digital Group. All rights reserved. Global License №1029-AS-USA.</p>
                <div class="flex gap-8 text-xs text-slate-400">
                    <a href="#" class="hover:text-slate-900 transition">Privacy</a>
                    <a href="#" class="hover:text-slate-900 transition">Compliance</a>
                    <a href="#" class="hover:text-slate-900 transition">Sitemap</a>
                </div>
            </div>
        </div>
    </footer>

</body>
</html>
HTMLEOF
}

# ---- Generate selected stub ----
case "$STUB_CHOICE" in
    1) create_stub_nexus ;;
    2) create_stub_stratus ;;
    3) create_stub_custom ;;
esac

echo -e "${GREEN}[✓] Stub page created${NC}"

# ---- Configure Caddy ----
echo -e "${CYAN}[*] Configuring Caddy...${NC}"

if [[ -f /etc/caddy/Caddyfile ]]; then
    cp /etc/caddy/Caddyfile "/etc/caddy/Caddyfile.bak.$(date +%s)"
fi

# Determine response code based on stub type
if [[ "$STUB_CHOICE" == "3" ]]; then
    RESPONSE_CODE="200"
else
    RESPONSE_CODE="404"
fi

cat > /etc/caddy/Caddyfile << CADDYEOF
{
    http_port 80
    https_port 8443
}

${DOMAIN}:80 {
    root * /var/www/html
    try_files {path} /index.html
    file_server
}

${DOMAIN}:8443 {
    bind 127.0.0.1
    header {
        Strict-Transport-Security "max-age=31536000; includeSubDomains; preload"
        X-Content-Type-Options "nosniff"
        X-Frame-Options "SAMEORIGIN"
    }
    root * /var/www/html
    try_files {path} /index.html
    file_server
}
CADDYEOF

caddy validate --config /etc/caddy/Caddyfile > /dev/null 2>&1
caddy fmt --overwrite /etc/caddy/Caddyfile > /dev/null 2>&1 || true
echo -e "${GREEN}[✓] Caddyfile configured${NC}"

# ---- Firewall ----
echo -e "${CYAN}[*] Configuring firewall...${NC}"

if command -v ufw &>/dev/null; then
    for port in "${MANAGED_PORTS[@]}"; do
        ufw allow "${port}/tcp" > /dev/null 2>&1 || true
    done
    echo -e "${GREEN}[✓] UFW: opened 80/tcp, 2222/tcp, 443/tcp, 8443/tcp${NC}"
else
    echo -e "${YELLOW}[!] UFW not found — open ports manually if needed${NC}"
fi

for port in "${MANAGED_PORTS[@]}"; do
    report_port_status "$port"
done

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
HTTP_CODE=$(curl --resolve "${DOMAIN}:8443:127.0.0.1" -sk -o /dev/null -w "%{http_code}" "https://${DOMAIN}:8443" 2>/dev/null || true)
HTTP_CODE=${HTTP_CODE:-000}

if [[ "$HTTP_CODE" =~ ^(200|404)$ ]]; then
    echo -e "${GREEN}[✓] HTTPS works, stub page served (HTTP ${HTTP_CODE})${NC}"
elif [[ "$HTTP_CODE" == "000" ]]; then
    echo -e "${YELLOW}[!] Could not verify HTTPS yet (cert may still be issuing)${NC}"
else
    echo -e "${YELLOW}[!] Got HTTP ${HTTP_CODE}${NC}"
fi

# ---- Summary ----
echo ""
echo -e "${GREEN}╔═══════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║           ✓ Installation Complete              ║${NC}"
echo -e "${GREEN}╚═══════════════════════════════════════════════╝${NC}"
echo ""
echo -e "  ${BOLD}Domain:${NC}     ${CYAN}${DOMAIN}${NC}"
echo -e "  ${BOLD}Stub:${NC}       ${CYAN}${STUB_NAMES[$((STUB_CHOICE-1))]}${NC}"
echo -e "  ${BOLD}Local TLS:${NC}  ${CYAN}https://${DOMAIN}:8443${NC}"
echo -e "  ${BOLD}Public HTTP:${NC} ${CYAN}http://${DOMAIN}${NC} serves the stub page"
echo ""
echo -e "  ${YELLOW}━━━ Update your Xray / Remnawave node config ━━━${NC}"
echo ""
echo -e "    \"target\":      ${GREEN}\"127.0.0.1:8443\"${NC}"
echo -e "    \"serverNames\": ${GREEN}[\"${DOMAIN}\"]${NC}"
echo ""
echo -e "  ${BOLD}Managed ports:${NC} 80 (ACME + stub), 2222, 443, 8443"
echo -e "  ${BOLD}Local bind:${NC}   8443 (Caddy, bound to 127.0.0.1)"
echo ""
