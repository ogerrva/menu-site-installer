#!/usr/bin/env bash
# install-menu-site.sh — FYX-AUTOWEB Installer
# Versão 5.0 - Final Stable (Rehost Fix + System Tools)

export DEBIAN_FRONTEND=noninteractive
set -u

# --- URL DE ATUALIZAÇÃO ---
# Link direto para este script (Raw)
UPDATE_URL="https://raw.githubusercontent.com/ogerrva/menu-site-installer/refs/heads/main/install-menu-site.sh"

# --- CORES E ESTILOS ---
RED='\033[1;31m'
GREEN='\033[1;32m'
YELLOW='\033[1;33m'
BLUE='\033[1;34m'
CYAN='\033[1;36m'
WHITE='\033[1;37m'
NC='\033[0m'
BOX_COLOR='\033[0;35m'

# --- FUNÇÕES DE INSTALAÇÃO ---
log_header() {
  clear
  echo -e "${BOX_COLOR}╔══════════════════════════════════════════════════════════════╗${NC}"
  echo -e "${BOX_COLOR}║ ${CYAN}                 ⚡ FYX-AUTOWEB INSTALLER ⚡              ${BOX_COLOR}║${NC}"
  echo -e "${BOX_COLOR}╚══════════════════════════════════════════════════════════════╝${NC}"
  echo ""
}

log_step() { echo -ne "${BLUE}[INFO]${NC} $1... "; }
log_success() { echo -e "${GREEN}✅ SUCESSO${NC}"; }

wait_for_apt() {
  while fuser /var/lib/dpkg/lock >/dev/null 2>&1 || fuser /var/lib/apt/lists/lock >/dev/null 2>&1 || fuser /var/lib/dpkg/lock-frontend >/dev/null 2>&1; do
    echo -ne "${YELLOW}⏳ Aguardando apt... ${NC}\r"
    sleep 3
  done
}

if [[ $EUID -ne 0 ]]; then echo -e "${RED}Execute como root.${NC}"; exit 1; fi

# --- INÍCIO DA INSTALAÇÃO DO SISTEMA ---
log_header

log_step "Preparando sistema"
wait_for_apt
systemctl stop nginx caddy >/dev/null 2>&1 || true
# Não removemos configs existentes para permitir atualização segura
rm -f /etc/apt/sources.list.d/caddy*
log_success

log_step "Instalando dependências"
wait_for_apt
apt-get update -qq >/dev/null 2>&1
apt-get install -y -qq apt-transport-https ca-certificates curl gnupg2 dirmngr dos2unix nano iptables iptables-persistent jq >/dev/null 2>&1
log_success

log_step "Verificando Node.js"
if ! command -v node &> /dev/null; then
    curl -fsSL https://deb.nodesource.com/setup_18.x | bash - >/dev/null 2>&1
    wait_for_apt
    apt-get install -y nodejs >/dev/null 2>&1
else
    echo -e "${GREEN}✅${NC}"
fi

log_step "Atualizando PM2"
npm install -g pm2 http-server >/dev/null 2>&1
pm2 update >/dev/null 2>&1
env PATH=$PATH:/usr/bin pm2 startup systemd -u root --hp /root >/dev/null 2>&1 || true
pm2 save --force >/dev/null 2>&1
log_success

log_step "Instalando Caddy"
curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/gpg.key' | gpg --dearmor -o /usr/share/keyrings/caddy-stable-archive-keyring.gpg
cat > /etc/apt/sources.list.d/caddy-stable.list <<EOF
deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/caddy-stable-archive-keyring.gpg] https://dl.cloudsmith.io/public/caddy/stable/deb/debian any-version main
EOF
wait_for_apt
apt-get update -qq >/dev/null 2>&1
apt-get install -y caddy >/dev/null 2>&1
mkdir -p /etc/caddy
if [[ ! -f /etc/caddy/Caddyfile ]]; then echo "# FYX-AUTOWEB Config" > /etc/caddy/Caddyfile; fi
systemctl enable caddy >/dev/null 2>&1
systemctl restart caddy
log_success

# --- CRIAÇÃO DO MENU (BINÁRIO) ---
log_step "Gerando Menu v5.0"
cat > /usr/local/bin/menu-site <<'EOF'
#!/usr/bin/env bash
# FYX-AUTOWEB v5.0
set -u

# VARIAVEIS GLOBAIS
CADDYFILE="/etc/caddy/Caddyfile"
CF_CONFIG="/etc/caddy/.cf_config"
CF_CERT="/etc/caddy/cloudflare.crt"
CF_KEY="/etc/caddy/cloudflare.key"
UPDATE_URL="https://raw.githubusercontent.com/ogerrva/menu-site-installer/refs/heads/main/install-menu-site.sh"
BASE_PORT=3000

# CORES
R='\033[1;31m'; G='\033[1;32m'; Y='\033[1;33m'; B='\033[1;34m'; C='\033[1;36m'; W='\033[1;37m'; NC='\033[0m'; BOX_COLOR='\033[0;35m'
trap '' SIGINT SIGQUIT SIGTSTP

pause() { echo ""; echo -e "${BOX_COLOR}────────────────────────────────────────────────────────────${NC}"; echo -e " ${W}Enter para voltar...${NC}"; read -r; }

draw_header() {
  clear
  echo -e "${BOX_COLOR}╔══════════════════════════════════════════════════════════╗${NC}"
  echo -e "${BOX_COLOR}║${NC}                 ${C}⚡ FYX-AUTOWEB ⚡${NC}                       ${BOX_COLOR}║${NC}"
  echo -e "${BOX_COLOR}╠══════════════════════════════════════════════════════════╣${NC}"
  echo -e "${BOX_COLOR}║${NC}  IP: ${Y}$(curl -s https://api.ipify.org)${NC}  |  Sites Caddy: ${G}$(grep -c ' {' "$CADDYFILE")${NC}  |  PM2: ${G}$(pm2 list | grep online | wc -l)${NC}   ${BOX_COLOR}║${NC}"
  echo -e "${BOX_COLOR}╚══════════════════════════════════════════════════════════╝${NC}"
  echo ""
}

draw_menu_item() { echo -e "   ${C}[$1]${NC} ${W}$2${NC}"; }

# --- FERRAMENTAS DO SISTEMA ---

system_tools() {
    draw_header
    echo -e "${Y}🛠️  FERRAMENTAS DO SISTEMA${NC}"
    echo -e "${BOX_COLOR}────────────────────────────────────────────────────────────${NC}"
    echo -e "   1) Atualizar Script (Baixar última versão do Git)"
    echo -e "   2) Reinstalar Dependências (Caddy/Node/PM2)"
    echo -e "   3) ${R}RESET TOTAL (Apagar tudo e formatar Caddy)${NC}"
    echo ""
    read -rp "   Opção: " opt
    
    case $opt in
        1)
            echo -e "\n${Y}Baixando atualização...${NC}"
            bash <(curl -sSL "$UPDATE_URL")
            exit 0
            ;;
        2)
            echo -e "\n${Y}Reinstalando pacotes...${NC}"
            apt-get install --reinstall -y caddy nodejs
            npm install -g pm2
            echo -e "${G}Concluído.${NC}"
            pause
            ;;
        3)
            echo -e "\n${R}⚠️  CUIDADO! ISSO APAGARÁ TODOS OS SITES DO CADDY.${NC}"
            echo -e "Os arquivos em /var/www NÃO serão apagados, apenas a configuração."
            read -rp "Digite 'RESET' para confirmar: " confirm
            if [[ "$confirm" == "RESET" ]]; then
                echo "# Config Resetada" > "$CADDYFILE"
                systemctl reload caddy
                echo -e "${G}Caddy resetado.${NC}"
            else
                echo "Cancelado."
            fi
            pause
            ;;
        *) echo "Inválido."; pause ;;
    esac
}

# --- FUNÇÕES LÓGICAS ---

setup_cf_api() {
  draw_header
  echo -e "${Y}🔧 API CLOUDFLARE${NC}"
  read -rp "Email (Enter se usar Token): " cf_email
  read -rp "API Token/Key: " cf_key
  read -rp "Zone ID: " cf_zone
  if [[ -z "$cf_key" ]]; then echo "Cancelado."; else
    cat > "$CF_CONFIG" <<CFEOF
CF_EMAIL="$cf_email"
CF_KEY="$cf_key"
CF_ZONE="$cf_zone"
CFEOF
    chmod 600 "$CF_CONFIG"; echo -e "${G}✔ Salvo!${NC}"
  fi
  pause
}

create_dns_record() {
  if [[ ! -f "$CF_CONFIG" ]]; then return; fi
  source "$CF_CONFIG"
  local domain="$1"
  local ip=$(curl -s https://api.ipify.org)
  echo -ne "${Y}⚡ DNS Cloudflare ($domain)... ${NC}"
  local h1="Authorization: Bearer $CF_KEY"
  [[ -n "$CF_EMAIL" ]] && h1="X-Auth-Key: $CF_KEY"
  
  if [[ -z "$CF_EMAIL" ]]; then
      curl -s -X POST "https://api.cloudflare.com/client/v4/zones/$CF_ZONE/dns_records" \
      -H "Authorization: Bearer $CF_KEY" -H "Content-Type: application/json" \
      --data "{\"type\":\"A\",\"name\":\"$domain\",\"content\":\"$ip\",\"ttl\":1,\"proxied\":true}" >/dev/null
  else
      curl -s -X POST "https://api.cloudflare.com/client/v4/zones/$CF_ZONE/dns_records" \
      -H "X-Auth-Email: $CF_EMAIL" -H "X-Auth-Key: $CF_KEY" -H "Content-Type: application/json" \
      --data "{\"type\":\"A\",\"name\":\"$domain\",\"content\":\"$ip\",\"ttl\":1,\"proxied\":true}" >/dev/null
  fi
  echo -e "${G}✔ OK${NC}"
}

get_next_port() {
  local last=$(grep -E 'reverse_proxy localhost:[0-9]+' "$CADDYFILE" | sed -E 's/.*:([0-9]+)/\1/' | sort -n | tail -n1)
  if [[ "$last" =~ ^[0-9]+$ ]]; then echo $((last + 1)); else echo "$BASE_PORT"; fi
}

write_caddy_config() {
    local domain=$1; local ssl=$2; local port=$3
    local tls_line=""; local tls_redir=""
    [[ "$ssl" == "2" ]] && tls_line="tls $CF_CERT $CF_KEY" && tls_redir=$tls_line
    [[ "$ssl" == "3" ]] && domain="http://$domain"
    
    local block="file_server"
    [[ "$port" != "0" ]] && block="reverse_proxy localhost:$port"

    cat >> "$CADDYFILE" <<EOB

www.$domain {
    $tls_redir
    redir https://$domain{uri}
}

$domain {
    $tls_line
    root * /var/www/$domain
    encode gzip
    $block
}
EOB
}

# --- REHOST SITE (CORRIGIDO) ---
rehost_site() {
    draw_header
    echo -e "${Y}📂 RE-HOSPEDAR (/var/www/)${NC}"
    echo -e "${BOX_COLOR}────────────────────────────────────────────────────────────${NC}"
    
    # Lista segura de diretórios
    dirs=($(ls -d /var/www/*/ 2>/dev/null | xargs -n 1 basename))
    
    if [[ ${#dirs[@]} -eq 0 ]]; then echo "Nenhuma pasta encontrada."; pause; return; fi
    
    local i=1
    for dir in "${dirs[@]}"; do
        status=$(grep -q "$dir {" "$CADDYFILE" && echo "${G}[ON]${NC}" || echo "${Y}[OFF]${NC}")
        echo -e "   ${C}[$i]${NC} $dir $status"
        ((i++))
    done
    
    echo ""
    read -rp "Número da pasta para ativar: " num
    
    if [[ "$num" -gt 0 && "$num" -le "${#dirs[@]}" ]]; then
        domain="${dirs[$((num-1))]}"
        echo -e "\n${Y}Selecionado: $domain${NC}"
        
        # PERGUNTA PM2
        read -rp "Este site é um App PM2 (Node/Python)? (s/N): " is_app
        port="0"
        
        # LOGICA DA PORTA (CORRIGIDA)
        if [[ "$is_app" =~ ^[sS]$ ]]; then
             echo ""
             echo -e "   ${C}⚙ MODO DE PORTA:${NC}"
             echo -e "   1) Manual (Já tenho a porta)"
             echo -e "   2) Automática (Gerar nova porta)"
             read -rp "   Opção [1]: " p_opt
             p_opt=${p_opt:-1}
             
             if [[ "$p_opt" == "2" ]]; then
                 port=$(get_next_port)
                 echo -e "   ${G}✔ Porta Gerada: $port${NC}"
                 echo -e "   ${Y}⚠ Nota: Edite seu app para usar a porta $port${NC}"
                 read -rp "   Pressione ENTER confirmar..." dump
             else
                 read -rp "   Digite a porta interna (ex: 3000): " port
             fi
        fi
        
        # SSL
        echo ""
        echo -e "   ${C}🔐 TIPO DE SSL:${NC}"
        echo -e "   1) Auto (Let's Encrypt)"
        echo -e "   2) Cloudflare Origin"
        read -rp "   Opção [1]: " ssl_opt
        ssl_opt=${ssl_opt:-1}
        
        write_caddy_config "$domain" "$ssl_opt" "$port"
        caddy fmt --overwrite "$CADDYFILE" >/dev/null
        systemctl reload caddy
        echo -e "\n${G}✔ Re-hospedado com sucesso!${NC}"
    fi
    pause
}

sync_pm2_sites() {
    draw_header
    echo -e "${Y}🔄 SYNC PM2${NC}"
    pm2_apps=$(pm2 jlist | jq -r '.[].name')
    found=0
    for app in $pm2_apps; do
        if grep -q "$app {" "$CADDYFILE"; then continue; fi
        found=1
        echo -e "\n${C}🔹 App sem site:${NC} ${W}$app${NC}"
        read -rp "   Criar site agora? (s/n): " c
        if [[ "$c" == "s" ]]; then
             read -rp "   Domínio [$app]: " d; d=${d:-$app}
             read -rp "   Porta do App: " p
             [[ -f "$CF_CONFIG" ]] && create_dns_record "$d" && create_dns_record "www.$d"
             write_caddy_config "$d" "1" "$p"
             mkdir -p "/var/www/$d"
             echo -e "${G}   ✔ Configurado.${NC}"
        fi
    done
    [[ $found -eq 0 ]] && echo -e "\n${G}Nada novo.${NC}" || (caddy fmt --overwrite "$CADDYFILE" >/dev/null; systemctl reload caddy; echo -e "${G}✔ Caddy Atualizado!${NC}")
    pause
}

add_site() {
  draw_header
  echo -e "${Y}➕ NOVO SITE${NC}"
  read -rp "🌐 Domínio: " d
  d=$(echo "$d" | sed -E 's/^\s*//;s/\s*$//;s/^(https?:\/\/)?(www\.)?//')
  [[ -z "$d" ]] && return
  
  [[ -f "$CF_CONFIG" ]] && create_dns_record "$d" && create_dns_record "www.$d"
  
  echo -e "📦 TIPO: 1) Estático  2) App PM2"
  read -rp "Opção: " t; t=${t:-1}
  
  mkdir -p "/var/www/$d"
  p="0"
  if [[ "$t" == "2" ]]; then
    p=$(get_next_port)
    cat > "/var/www/$d/server.js" <<JS
const http = require('http');
http.createServer((r,s)=>{s.writeHead(200);s.end('<h1>$d : $p</h1>')}).listen($p);
JS
    pm2 start "/var/www/$d/server.js" --name "$d" >/dev/null
    pm2 save >/dev/null
  else
    [[ ! -f "/var/www/$d/index.html" ]] && echo "<h1>$d</h1>" > "/var/www/$d/index.html"
  fi
  
  write_caddy_config "$d" "1" "$p"
  caddy fmt --overwrite "$CADDYFILE" >/dev/null
  systemctl reload caddy
  echo -e "${G}✔ Online!${NC}"
  pause
}

list_sites() {
  draw_header; echo -e "${Y}📋 SITES${NC}"; grep -E '^[a-zA-Z0-9].+ \{$' "$CADDYFILE" | grep -v "www." | sed 's/ {//' | nl; pause
}

remove_site() {
  draw_header; echo -e "${Y}🗑️  REMOVER${NC}"
  sites=($(grep -E '^[a-zA-Z0-9].+ \{$' "$CADDYFILE" | grep -v "www." | sed 's/ {//'))
  local i=1; for site in "${sites[@]}"; do echo -e "   ${C}[$i]${NC} $site"; ((i++)); done
  read -rp "Número: " num
  if [[ "$num" -gt 0 ]]; then
    d="${sites[$((num-1))]}"
    sed -i "/^$d \{/,/^\}/d" "$CADDYFILE"; sed -i "/^www.$d \{/,/^\}/d" "$CADDYFILE"
    pm2 delete "$d" >/dev/null 2>&1 || true; pm2 save >/dev/null
    read -rp "Apagar arquivos? (s/N): " dl
    [[ "$dl" == "s" ]] && rm -rf "/var/www/$d"
    caddy fmt --overwrite "$CADDYFILE" >/dev/null; systemctl reload caddy
    echo -e "${G}✔ Feito.${NC}"
  fi
  pause
}

while true; do
  draw_header
  draw_menu_item "1" "Listar Sites"
  draw_menu_item "2" "Novo Site"
  draw_menu_item "3" "Re-hospedar Pasta"
  draw_menu_item "4" "Sync Apps PM2"
  draw_menu_item "5" "Remover Site"
  echo ""; draw_menu_item "6" "Config CF API"; draw_menu_item "7" "Monitor PM2"
  echo ""; draw_menu_item "8" "Ferramentas / Atualizar"; draw_menu_item "0" "Sair"; echo ""
  read -rp "Opção: " opt
  case $opt in
    1) list_sites ;; 2) add_site ;; 3) rehost_site ;; 4) sync_pm2_sites ;; 5) remove_site ;; 6) setup_cf_api ;; 7) pm2 monit ;; 8) system_tools ;; 0) exit 0 ;;
  esac
done
EOF
chmod +x /usr/local/bin/menu-site
log_success
echo -e "${GREEN}✅ INSTALAÇÃO CONCLUÍDA! Digite: menu-site${NC}"
menu-site
