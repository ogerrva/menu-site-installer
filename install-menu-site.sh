#!/usr/bin/env bash
# install-menu-site.sh — Installer Profissional By FYXWEB 
# Versão 3.0 - Interface UI Melhorada

export DEBIAN_FRONTEND=noninteractive
set -u

# --- CORES E ESTILOS ---
RED='\033[1;31m'
GREEN='\033[1;32m'
YELLOW='\033[1;33m'
BLUE='\033[1;34m'
CYAN='\033[1;36m'
WHITE='\033[1;37m'
NC='\033[0m'
BG_BLUE='\033[44m'

# --- FUNÇÕES DE LOG VISUAL ---
log_header() {
  clear
  echo -e "${BLUE}╔══════════════════════════════════════════════════════════════╗${NC}"
  echo -e "${BLUE}║ ${CYAN}           INSTALADOR DE AMBIENTE WEB - FYXWEB           ${BLUE}║${NC}"
  echo -e "${BLUE}╚══════════════════════════════════════════════════════════════╝${NC}"
  echo ""
}

log_step() {
  echo -ne "${BLUE}[INFO]${NC} $1... "
}

log_success() {
  echo -e "${GREEN}✅ SUCESSO${NC}"
}

log_error() {
  echo -e "${RED}❌ ERRO${NC}"
  echo -e "${RED}Detalhes: $1${NC}"
  exit 1
}

wait_for_apt() {
  while fuser /var/lib/dpkg/lock >/dev/null 2>&1 || fuser /var/lib/apt/lists/lock >/dev/null 2>&1 || fuser /var/lib/dpkg/lock-frontend >/dev/null 2>&1; do
    echo -ne "${YELLOW}⏳ Aguardando apt... ${NC}\r"
    sleep 3
  done
}

if [[ $EUID -ne 0 ]]; then
  echo -e "${RED}Erro: Execute como root.${NC}"
  exit 1
fi

# --- INÍCIO DA INSTALAÇÃO ---
log_header

log_step "Preparando e limpando o sistema"
wait_for_apt
systemctl stop nginx caddy >/dev/null 2>&1 || true
pkill -9 caddy >/dev/null 2>&1 || true
apt-get remove --purge -y nginx* caddy* >/dev/null 2>&1 || true
rm -rf /etc/caddy /etc/apt/sources.list.d/caddy*
log_success

log_step "Instalando dependências essenciais"
wait_for_apt
apt-get update -qq >/dev/null 2>&1
apt-get install -y -qq apt-transport-https ca-certificates curl gnupg2 dirmngr dos2unix nano iptables iptables-persistent jq >/dev/null 2>&1
log_success

log_step "Configurando Node.js 18 (LTS)"
if ! command -v node &> /dev/null; then
    curl -fsSL https://deb.nodesource.com/setup_18.x | bash - >/dev/null 2>&1
    wait_for_apt
    apt-get install -y nodejs >/dev/null 2>&1
    log_success
else
    echo -e "${GREEN}✅ (Já instalado)${NC}"
fi

log_step "Configurando Firewall (Portas 80/443)"
iptables -I INPUT -p tcp --dport 80 -j ACCEPT
iptables -I INPUT -p tcp --dport 443 -j ACCEPT
netfilter-persistent save >/dev/null 2>&1 || true
log_success

log_step "Instalando PM2 (Gerenciador de Processos)"
npm install -g pm2 http-server >/dev/null 2>&1
env PATH=$PATH:/usr/bin pm2 startup systemd -u root --hp /root >/dev/null 2>&1 || true
pm2 save --force >/dev/null 2>&1
log_success

log_step "Instalando Caddy Web Server"
curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/gpg.key' | gpg --dearmor -o /usr/share/keyrings/caddy-stable-archive-keyring.gpg
cat > /etc/apt/sources.list.d/caddy-stable.list <<EOF
deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/caddy-stable-archive-keyring.gpg] https://dl.cloudsmith.io/public/caddy/stable/deb/debian any-version main
EOF
wait_for_apt
apt-get update -qq >/dev/null 2>&1
apt-get install -y caddy >/dev/null 2>&1
mkdir -p /etc/caddy
echo "# Caddyfile gerenciado pelo menu-site" > /etc/caddy/Caddyfile
systemctl enable caddy >/dev/null 2>&1
systemctl restart caddy
log_success

# --- CRIAÇÃO DO MENU-SITE ---
log_step "Gerando script de controle (menu-site)"
cat > /usr/local/bin/menu-site <<'EOF'
#!/usr/bin/env bash
# menu-site — Interface CLI Premium
set -u

# CONFIGURAÇÕES
CADDYFILE="/etc/caddy/Caddyfile"
CF_CONFIG="/etc/caddy/.cf_config"
CF_CERT="/etc/caddy/cloudflare.crt"
CF_KEY="/etc/caddy/cloudflare.key"
BASE_PORT=3000

# CORES
R='\033[1;31m'    # Red
G='\033[1;32m'    # Green
Y='\033[1;33m'    # Yellow
B='\033[1;34m'    # Blue
C='\033[1;36m'    # Cyan
W='\033[1;37m'    # White
NC='\033[0m'      # No Color
BOX_COLOR='\033[0;35m' # Purple for borders

trap '' SIGINT SIGQUIT SIGTSTP # Impede Ctrl+C e Ctrl+Z de fechar abruptamente

# --- UI HELPERS ---

pause() {
  echo ""
  echo -e "${BOX_COLOR}────────────────────────────────────────────────────────────${NC}"
  echo -e " ${W}Pressione [ENTER] para voltar ao menu...${NC}"
  read -r
}

draw_header() {
  clear
  echo -e "${BOX_COLOR}╔══════════════════════════════════════════════════════════╗${NC}"
  echo -e "${BOX_COLOR}║${NC}              ${C}🚀 GERENCIADOR DE SITES PRO${NC}                 ${BOX_COLOR}║${NC}"
  echo -e "${BOX_COLOR}║${NC}                  ${W}Dev: @OGERRVA${NC}                           ${BOX_COLOR}║${NC}"
  echo -e "${BOX_COLOR}╠══════════════════════════════════════════════════════════╣${NC}"
  echo -e "${BOX_COLOR}║${NC}  IP: ${Y}$(curl -s https://api.ipify.org)${NC}  |  Sites Ativos: ${G}$(grep -c ' {' "$CADDYFILE")${NC}            ${BOX_COLOR}║${NC}"
  echo -e "${BOX_COLOR}╚══════════════════════════════════════════════════════════╝${NC}"
  echo ""
}

draw_menu_item() {
  local num=$1
  local text=$2
  echo -e "   ${C}[${num}]${NC} ${W}${text}${NC}"
}

# --- FUNÇÕES LÓGICAS ---

setup_cf_api() {
  draw_header
  echo -e "${Y}🔧 CONFIGURAÇÃO API CLOUDFLARE${NC}"
  echo -e "${BOX_COLOR}────────────────────────────────────────────────────────────${NC}"
  echo "Insira seus dados para automatizar a criação de DNS."
  echo ""
  
  read -rp "Email (Enter p/ usar só Token): " cf_email
  read -rp "API Token/Key: " cf_key
  read -rp "Zone ID: " cf_zone
  
  if [[ -z "$cf_key" || -z "$cf_zone" ]]; then
    echo -e "\n${R}✖ Dados incompletos. Operação cancelada.${NC}"
  else
    cat > "$CF_CONFIG" <<CFEOF
CF_EMAIL="$cf_email"
CF_KEY="$cf_key"
CF_ZONE="$cf_zone"
CFEOF
    chmod 600 "$CF_CONFIG"
    echo -e "\n${G}✔ Configuração salva com sucesso!${NC}"
  fi
  pause
}

create_dns_record() {
  local domain="$1"
  if [[ ! -f "$CF_CONFIG" ]]; then return; fi
  
  source "$CF_CONFIG"
  local public_ip
  public_ip=$(curl -s https://api.ipify.org)
  
  echo -ne "${Y}⚡ Criando DNS na Cloudflare ($domain)... ${NC}"
  
  local response
  if [[ -z "$CF_EMAIL" ]]; then
    response=$(curl -s -X POST "https://api.cloudflare.com/client/v4/zones/$CF_ZONE/dns_records" \
      -H "Authorization: Bearer $CF_KEY" -H "Content-Type: application/json" \
      --data "{\"type\":\"A\",\"name\":\"$domain\",\"content\":\"$public_ip\",\"ttl\":1,\"proxied\":true}")
  else
    response=$(curl -s -X POST "https://api.cloudflare.com/client/v4/zones/$CF_ZONE/dns_records" \
      -H "X-Auth-Email: $CF_EMAIL" -H "X-Auth-Key: $CF_KEY" -H "Content-Type: application/json" \
      --data "{\"type\":\"A\",\"name\":\"$domain\",\"content\":\"$public_ip\",\"ttl\":1,\"proxied\":true}")
  fi

  if echo "$response" | jq -r '.success' | grep -q "true"; then
    echo -e "${G}✔ Feito!${NC}"
  else
    echo -e "${R}✖ Falha!${NC}"
  fi
}

get_next_port() {
  local last_port
  last_port=$(grep -E 'reverse_proxy localhost:[0-9]+' "$CADDYFILE" | sed -E 's/.*:([0-9]+)/\1/' | sort -n | tail -n1)
  if [[ "$last_port" =~ ^[0-9]+$ ]]; then echo $((last_port + 1)); else echo "$BASE_PORT"; fi
}

add_site() {
  draw_header
  echo -e "${Y}➕ ADICIONAR NOVO SITE${NC}"
  echo -e "${BOX_COLOR}────────────────────────────────────────────────────────────${NC}"
  
  read -rp "🌐 Domínio (ex: site.com): " raw_domain
  domain=$(echo "$raw_domain" | sed -E 's/^\s*//;s/\s*$//;s/^(https?:\/\/)?(www\.)?//')
  
  if [[ -z "$domain" ]]; then echo -e "${R}Domínio inválido.${NC}"; pause; return; fi
  
  # Check CF API existence
  if [[ -f "$CF_CONFIG" ]]; then
    create_dns_record "$domain"
    create_dns_record "www.$domain"
  fi
  
  echo ""
  echo -e "${C}🔐 TIPO DE SEGURANÇA (SSL):${NC}"
  echo -e "   1) Automático (Let's Encrypt) ${G}[Recomendado]${NC}"
  echo -e "   2) Cloudflare Origin (Requer certificado)"
  echo -e "   3) HTTP (Inseguro)"
  echo ""
  read -rp "Opção [1]: " ssl_opt
  ssl_opt=${ssl_opt:-1}

  local tls_line=""
  local tls_redir=""
  
  case $ssl_opt in
    2) tls_line="tls $CF_CERT $CF_KEY"; tls_redir=$tls_line ;;
    3) domain="http://$domain";;
    *) ;;
  esac

  echo ""
  echo -e "${C}📦 TIPO DE APLICAÇÃO:${NC}"
  echo -e "   1) Site Estático (HTML)"
  echo -e "   2) Aplicação PM2 (Node/Python/Proxy)"
  echo ""
  read -rp "Opção [1]: " app_opt
  app_opt=${app_opt:-1}
  
  local config_block=""
  mkdir -p "/var/www/$domain"
  
  if [[ "$app_opt" == "2" ]]; then
    local port=$(get_next_port)
    config_block="reverse_proxy localhost:$port"
    
    # Create simple server
    cat > "/var/www/$domain/server.js" <<JS
const http = require('http');
http.createServer((req, res) => {
  res.writeHead(200, {'Content-Type': 'text/html; charset=utf-8'});
  res.end('<h1>$domain rodando na porta $port 🚀</h1>');
}).listen($port);
JS
    pm2 start "/var/www/$domain/server.js" --name "$domain" >/dev/null
    pm2 save >/dev/null
    echo -e "\n${G}✔ App iniciada na porta $port${NC}"
  else
    config_block="file_server"
    cat > "/var/www/$domain/index.html" <<HTML
<!DOCTYPE html><html><body style="background:#1a1a1a;color:white;display:flex;justify-content:center;align-items:center;height:100vh;">
<h1>$domain Configurado com Sucesso! 🚀</h1></body></html>
HTML
  fi

  # Add to Caddyfile with WWW redirect logic
  cat >> "$CADDYFILE" <<EOB

www.$domain {
    $tls_redir
    redir https://$domain{uri}
}

$domain {
    $tls_line
    root * /var/www/$domain
    encode gzip
    $config_block
}
EOB

  if caddy fmt --overwrite "$CADDYFILE" >/dev/null && caddy validate --config "$CADDYFILE" >/dev/null; then
    systemctl reload caddy
    echo -e "${G}✔ Site configurado e online!${NC}"
  else
    echo -e "${R}✖ Erro na configuração do Caddyfile.${NC}"
  fi
  pause
}

list_sites() {
  draw_header
  echo -e "${Y}📋 LISTA DE SITES ATIVOS${NC}"
  echo -e "${BOX_COLOR}────────────────────────────────────────────────────────────${NC}"
  printf "${C}%-4s %-30s %-15s${NC}\n" "ID" "DOMÍNIO" "TIPO"
  echo -e "${BOX_COLOR}────────────────────────────────────────────────────────────${NC}"
  
  local i=1
  # Extract domains properly
  grep -E '^[a-zA-Z0-9].+ \{$' "$CADDYFILE" | grep -v "www." | sed 's/ {//' | while read -r site; do
    if grep -q "reverse_proxy" "$CADDYFILE"; then type="Proxy/App"; else type="Estático"; fi
    printf "${W}%-4s %-30s %-15s${NC}\n" "$i" "$site" "$type"
    ((i++))
  done
  echo ""
  pause
}

remove_site() {
  draw_header
  echo -e "${Y}🗑️  REMOVER SITE${NC}"
  echo -e "${BOX_COLOR}────────────────────────────────────────────────────────────${NC}"
  
  sites=($(grep -E '^[a-zA-Z0-9].+ \{$' "$CADDYFILE" | grep -v "www." | sed 's/ {//'))
  if [[ ${#sites[@]} -eq 0 ]]; then echo "Nenhum site."; pause; return; fi
  
  local i=1
  for site in "${sites[@]}"; do echo -e "   ${C}[$i]${NC} $site"; ((i++)); done
  
  echo ""
  read -rp "Digite o número para remover (0 para cancelar): " num
  
  if [[ "$num" -gt 0 && "$num" -le "${#sites[@]}" ]]; then
    domain="${sites[$((num-1))]}"
    
    sed -i "/^$domain \{/,/^\}/d" "$CADDYFILE"
    sed -i "/^www.$domain \{/,/^\}/d" "$CADDYFILE"
    
    pm2 delete "$domain" >/dev/null 2>&1 || true
    pm2 save >/dev/null
    rm -rf "/var/www/$domain"
    
    caddy fmt --overwrite "$CADDYFILE" >/dev/null
    systemctl reload caddy
    echo -e "\n${G}✔ Site $domain removido completamente.${NC}"
  fi
  pause
}

# --- LOOP PRINCIPAL ---
while true; do
  draw_header
  echo -e "   ${Y}MENU PRINCIPAL${NC}"
  draw_menu_item "1" "Listar Sites"
  draw_menu_item "2" "Adicionar Novo Site"
  draw_menu_item "3" "Remover Site"
  echo ""
  draw_menu_item "4" "Configurar API Cloudflare (DNS Auto)"
  draw_menu_item "5" "Editar Certificados Manuais"
  draw_menu_item "6" "Monitor PM2"
  echo ""
  draw_menu_item "0" "Sair"
  echo ""
  echo -e "${BOX_COLOR}────────────────────────────────────────────────────────────${NC}"
  read -rp "Escolha uma opção: " opt
  
  case $opt in
    1) list_sites ;;
    2) add_site ;;
    3) remove_site ;;
    4) setup_cf_api ;;
    5) nano "$CF_CERT"; nano "$CF_KEY"; pause ;;
    6) pm2 monit ;;
    0) clear; echo -e "${G}👋 Até logo!${NC}"; exit 0 ;;
    *) ;;
  esac
done
EOF
chmod +x /usr/local/bin/menu-site
log_success

echo ""
echo -e "${BLUE}╔══════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║      ${GREEN}✅ INSTALAÇÃO CONCLUÍDA COM SUCESSO!${BLUE}                    ║${NC}"
echo -e "${BLUE}║      Digite ${YELLOW}menu-site${BLUE} para começar.                             ║${NC}"
echo -e "${BLUE}╚══════════════════════════════════════════════════════════════╝${NC}"
echo ""

# Iniciar automaticamente
menu-site
