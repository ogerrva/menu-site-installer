#!/usr/bin/env bash
# install-menu-site.sh — FYX-AUTOWEB Installer
# Versão 4.0 - Sync PM2 & Auto-Host

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
BOX_COLOR='\033[0;35m' # Roxo

# --- FUNÇÕES DE LOG VISUAL ---
log_header() {
  clear
  echo -e "${BOX_COLOR}╔══════════════════════════════════════════════════════════════╗${NC}"
  echo -e "${BOX_COLOR}║ ${CYAN}                 ⚡ FYX-AUTOWEB INSTALLER ⚡              ${BOX_COLOR}║${NC}"
  echo -e "${BOX_COLOR}╚══════════════════════════════════════════════════════════════╝${NC}"
  echo ""
}

log_step() { echo -ne "${BLUE}[INFO]${NC} $1... "; }
log_success() { echo -e "${GREEN}✅ SUCESSO${NC}"; }
log_error() { echo -e "${RED}❌ ERRO: $1${NC}"; exit 1; }

wait_for_apt() {
  while fuser /var/lib/dpkg/lock >/dev/null 2>&1 || fuser /var/lib/apt/lists/lock >/dev/null 2>&1 || fuser /var/lib/dpkg/lock-frontend >/dev/null 2>&1; do
    echo -ne "${YELLOW}⏳ Aguardando sistema (apt)... ${NC}\r"
    sleep 3
  done
}

if [[ $EUID -ne 0 ]]; then echo -e "${RED}Execute como root.${NC}"; exit 1; fi

# --- INÍCIO DA INSTALAÇÃO ---
log_header

log_step "Preparando sistema"
wait_for_apt
systemctl stop nginx caddy >/dev/null 2>&1 || true
# Não removemos mais pacotes agressivamente para evitar perda de configs
rm -f /etc/apt/sources.list.d/caddy*
log_success

log_step "Instalando dependências (curl, jq, git)"
wait_for_apt
apt-get update -qq >/dev/null 2>&1
apt-get install -y -qq apt-transport-https ca-certificates curl gnupg2 dirmngr dos2unix nano iptables iptables-persistent jq >/dev/null 2>&1
log_success

log_step "Verificando Node.js"
if ! command -v node &> /dev/null; then
    curl -fsSL https://deb.nodesource.com/setup_18.x | bash - >/dev/null 2>&1
    wait_for_apt
    apt-get install -y nodejs >/dev/null 2>&1
    log_success
else
    echo -e "${GREEN}✅ (Instalado)${NC}"
fi

log_step "Atualizando PM2 (Correção de memória)"
npm install -g pm2 http-server >/dev/null 2>&1
pm2 update >/dev/null 2>&1 # Corrige o erro "In-memory PM2 is out-of-date"
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
if [[ ! -f /etc/caddy/Caddyfile ]]; then
    echo "# Config by FYX-AUTOWEB" > /etc/caddy/Caddyfile
fi
systemctl enable caddy >/dev/null 2>&1
systemctl restart caddy
log_success

# --- CRIAÇÃO DO MENU ---
log_step "Gerando FYX-AUTOWEB Menu"
cat > /usr/local/bin/menu-site <<'EOF'
#!/usr/bin/env bash
# FYX-AUTOWEB — Gerenciador Premium v4.0
set -u

# CONFIGURAÇÕES
CADDYFILE="/etc/caddy/Caddyfile"
CF_CONFIG="/etc/caddy/.cf_config"
CF_CERT="/etc/caddy/cloudflare.crt"
CF_KEY="/etc/caddy/cloudflare.key"
BASE_PORT=3000

# CORES
R='\033[1;31m'
G='\033[1;32m'
Y='\033[1;33m'
B='\033[1;34m'
C='\033[1;36m'
W='\033[1;37m'
NC='\033[0m'
BOX_COLOR='\033[0;35m'

trap '' SIGINT SIGQUIT SIGTSTP

# --- UI HELPERS ---

pause() {
  echo ""
  echo -e "${BOX_COLOR}────────────────────────────────────────────────────────────${NC}"
  echo -e " ${W}Pressione [ENTER] para voltar...${NC}"
  read -r
}

draw_header() {
  clear
  echo -e "${BOX_COLOR}╔══════════════════════════════════════════════════════════╗${NC}"
  echo -e "${BOX_COLOR}║${NC}                 ${C}⚡ FYX-AUTOWEB ⚡${NC}                       ${BOX_COLOR}║${NC}"
  echo -e "${BOX_COLOR}╠══════════════════════════════════════════════════════════╣${NC}"
  echo -e "${BOX_COLOR}║${NC}  IP: ${Y}$(curl -s https://api.ipify.org)${NC}  |  Sites Caddy: ${G}$(grep -c ' {' "$CADDYFILE")${NC}  |  PM2: ${G}$(pm2 list | grep online | wc -l)${NC}   ${BOX_COLOR}║${NC}"
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
  read -rp "Email (Enter p/ usar só Token): " cf_email
  read -rp "API Token/Key: " cf_key
  read -rp "Zone ID: " cf_zone
  if [[ -z "$cf_key" || -z "$cf_zone" ]]; then
    echo -e "\n${R}✖ Dados incompletos.${NC}"
  else
    cat > "$CF_CONFIG" <<CFEOF
CF_EMAIL="$cf_email"
CF_KEY="$cf_key"
CF_ZONE="$cf_zone"
CFEOF
    chmod 600 "$CF_CONFIG"
    echo -e "\n${G}✔ Salvo!${NC}"
  fi
  pause
}

create_dns_record() {
  local domain="$1"
  if [[ ! -f "$CF_CONFIG" ]]; then return; fi
  source "$CF_CONFIG"
  local public_ip
  public_ip=$(curl -s https://api.ipify.org)
  echo -ne "${Y}⚡ Criando DNS Cloudflare ($domain)... ${NC}"
  
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
    echo -e "${R}✖ Falha (Talvez já exista)${NC}"
  fi
}

get_next_port() {
  local last_port
  last_port=$(grep -E 'reverse_proxy localhost:[0-9]+' "$CADDYFILE" | sed -E 's/.*:([0-9]+)/\1/' | sort -n | tail -n1)
  if [[ "$last_port" =~ ^[0-9]+$ ]]; then echo $((last_port + 1)); else echo "$BASE_PORT"; fi
}

write_caddy_config() {
    local domain=$1
    local ssl_mode=$2
    local port=$3 # Se 0, é static file server
    
    local tls_line=""
    local tls_redir=""
    
    case $ssl_mode in
        2) tls_line="tls $CF_CERT $CF_KEY"; tls_redir=$tls_line ;;
        3) domain="http://$domain";;
        *) ;;
    esac

    local config_block=""
    if [[ "$port" != "0" ]]; then
        config_block="reverse_proxy localhost:$port"
    else
        config_block="file_server"
    fi

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
}

sync_pm2_sites() {
    draw_header
    echo -e "${Y}🔄 SINCRONIZAR PROCESSOS PM2${NC}"
    echo -e "${BOX_COLOR}────────────────────────────────────────────────────────────${NC}"
    echo "Buscando processos ativos no PM2 que não estão no Caddy..."
    
    # Pega lista de nomes PM2 (json)
    pm2_apps=$(pm2 jlist | jq -r '.[].name')
    
    found=0
    for app in $pm2_apps; do
        # Verifica se já existe no Caddyfile
        if grep -q "$app {" "$CADDYFILE"; then
            continue
        fi
        
        found=1
        echo -e "\n${C}🔹 Encontrado App:${NC} ${W}$app${NC}"
        read -rp "   Deseja hospedar este app agora? (s/n): " confirm
        if [[ "$confirm" != "s" ]]; then continue; fi
        
        # Tenta adivinhar se o nome do app é um domínio
        default_domain=$app
        read -rp "   Domínio para este app [$default_domain]: " domain
        domain=${domain:-$default_domain}
        
        echo "   Qual porta interna este app está usando?"
        read -rp "   Porta (ex: 3000): " port
        
        if [[ -z "$port" ]]; then echo -e "${R}   Porta obrigatória. Pulando.${NC}"; continue; fi
        
        # Cria DNS
        if [[ -f "$CF_CONFIG" ]]; then
            create_dns_record "$domain"
            create_dns_record "www.$domain"
        fi
        
        # Configura Caddy
        write_caddy_config "$domain" "1" "$port"
        echo -e "${G}   ✔ Configurado para fila de gravação.${NC}"
        
        # Cria pasta dummy se não existir, só pra organização
        mkdir -p "/var/www/$domain"
    done
    
    if [[ $found -eq 0 ]]; then
        echo -e "\n${G}Tudo sincronizado! Nenhum app novo encontrado no PM2.${NC}"
    else
        echo -e "\n${Y}Aplicando configurações...${NC}"
        caddy fmt --overwrite "$CADDYFILE" >/dev/null
        systemctl reload caddy
        echo -e "${G}✔ Caddy recarregado!${NC}"
    fi
    pause
}

add_site() {
  draw_header
  echo -e "${Y}➕ ADICIONAR NOVO SITE${NC}"
  echo -e "${BOX_COLOR}────────────────────────────────────────────────────────────${NC}"
  
  read -rp "🌐 Domínio (ex: site.com): " raw_domain
  domain=$(echo "$raw_domain" | sed -E 's/^\s*//;s/\s*$//;s/^(https?:\/\/)?(www\.)?//')
  if [[ -z "$domain" ]]; then echo -e "${R}Inválido.${NC}"; pause; return; fi
  
  if [[ -f "$CF_CONFIG" ]]; then
    create_dns_record "$domain"
    create_dns_record "www.$domain"
  fi
  
  echo ""
  echo -e "📦 TIPO:"
  echo -e "   1) Estático (HTML)"
  echo -e "   2) App PM2 (Node/Python)"
  read -rp "Opção [1]: " app_opt
  app_opt=${app_opt:-1}
  
  mkdir -p "/var/www/$domain"
  local port="0"
  
  if [[ "$app_opt" == "2" ]]; then
    port=$(get_next_port)
    # Exemplo
    cat > "/var/www/$domain/server.js" <<JS
const http = require('http');
http.createServer((req, res) => {
  res.writeHead(200, {'Content-Type': 'text/html; charset=utf-8'});
  res.end('<h1>$domain na porta $port 🚀</h1>');
}).listen($port);
JS
    pm2 start "/var/www/$domain/server.js" --name "$domain" >/dev/null 2>&1
    pm2 save >/dev/null
  else
    if [[ ! -f "/var/www/$domain/index.html" ]]; then
        echo "<h1>$domain OK</h1>" > "/var/www/$domain/index.html"
    fi
  fi

  write_caddy_config "$domain" "1" "$port"
  
  caddy fmt --overwrite "$CADDYFILE" >/dev/null
  systemctl reload caddy
  echo -e "${G}✔ Online!${NC}"
  pause
}

rehost_site() {
    draw_header
    echo -e "${Y}📂 RE-HOSPEDAR PASTA (/var/www/)${NC}"
    echo -e "${BOX_COLOR}────────────────────────────────────────────────────────────${NC}"
    dirs=($(ls -d /var/www/*/ 2>/dev/null | xargs -n 1 basename))
    if [[ ${#dirs[@]} -eq 0 ]]; then echo "Vazio."; pause; return; fi
    
    local i=1
    for dir in "${dirs[@]}"; do
        status=$(grep -q "$dir {" "$CADDYFILE" && echo "${G}[ON]${NC}" || echo "${Y}[OFF]${NC}")
        echo -e "   ${C}[$i]${NC} $dir $status"
        ((i++))
    done
    
    echo ""
    read -rp "Número da pasta: " num
    if [[ "$num" -gt 0 && "$num" -le "${#dirs[@]}" ]]; then
        domain="${dirs[$((num-1))]}"
        read -rp "É um App PM2? (s/N): " is_app
        port="0"
        if [[ "$is_app" == "s" || "$is_app" == "S" ]]; then
             read -rp "Qual porta ele usa?: " port
        fi
        
        write_caddy_config "$domain" "1" "$port"
        caddy fmt --overwrite "$CADDYFILE" >/dev/null
        systemctl reload caddy
        echo -e "${G}✔ Re-hospedado!${NC}"
    fi
    pause
}

list_sites() {
  draw_header
  echo -e "${Y}📋 SITES NO CADDY${NC}"
  grep -E '^[a-zA-Z0-9].+ \{$' "$CADDYFILE" | grep -v "www." | sed 's/ {//' | nl
  pause
}

remove_site() {
  draw_header
  echo -e "${Y}🗑️  REMOVER${NC}"
  sites=($(grep -E '^[a-zA-Z0-9].+ \{$' "$CADDYFILE" | grep -v "www." | sed 's/ {//'))
  local i=1
  for site in "${sites[@]}"; do echo -e "   ${C}[$i]${NC} $site"; ((i++)); done
  read -rp "Número: " num
  if [[ "$num" -gt 0 ]]; then
    domain="${sites[$((num-1))]}"
    sed -i "/^$domain \{/,/^\}/d" "$CADDYFILE"
    sed -i "/^www.$domain \{/,/^\}/d" "$CADDYFILE"
    pm2 delete "$domain" >/dev/null 2>&1 || true
    pm2 save >/dev/null
    read -rp "Apagar arquivos? (s/N): " del
    [[ "$del" == "s" ]] && rm -rf "/var/www/$domain"
    caddy fmt --overwrite "$CADDYFILE" >/dev/null
    systemctl reload caddy
    echo -e "${G}✔ Feito.${NC}"
  fi
  pause
}

while true; do
  draw_header
  draw_menu_item "1" "Listar Sites"
  draw_menu_item "2" "Novo Site"
  draw_menu_item "3" "Re-hospedar Pasta"
  draw_menu_item "4" "Sincronizar Apps PM2 (Auto-Hospedar)"
  draw_menu_item "5" "Remover Site"
  echo ""
  draw_menu_item "6" "Configurar Cloudflare API"
  draw_menu_item "7" "Monitor PM2"
  echo ""
  draw_menu_item "0" "Sair"
  echo ""
  read -rp "Opção: " opt
  case $opt in
    1) list_sites ;;
    2) add_site ;;
    3) rehost_site ;;
    4) sync_pm2_sites ;;
    5) remove_site ;;
    6) setup_cf_api ;;
    7) pm2 monit ;;
    0) exit 0 ;;
  esac
done
EOF
chmod +x /usr/local/bin/menu-site
log_success

echo ""
echo -e "${GREEN}✅ INSTALAÇÃO FYX-AUTOWEB COMPLETA!${NC}"
echo -e "Digite ${YELLOW}menu-site${NC} para iniciar."
menu-site
