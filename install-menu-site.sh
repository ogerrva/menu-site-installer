#!/usr/bin/env bash
# install-menu-site.sh — FYX-AUTOWEB Installer
# Versão 7.0 - Safe Persistence & Diagnostics Tool

export DEBIAN_FRONTEND=noninteractive
set -u

# --- URL DE ATUALIZAÇÃO ---
UPDATE_URL="https://raw.githubusercontent.com/ogerrva/menu-site-installer/refs/heads/main/install-menu-site.sh"

# --- CORES ---
RED='\033[1;31m'
GREEN='\033[1;32m'
YELLOW='\033[1;33m'
BLUE='\033[1;34m'
CYAN='\033[1;36m'
WHITE='\033[1;37m'
NC='\033[0m'
BOX_COLOR='\033[0;35m'

# --- FUNÇÕES DE LOG ---
log_header() {
  clear
  echo -e "${BOX_COLOR}╔══════════════════════════════════════════════════════════════╗${NC}"
  echo -e "${BOX_COLOR}║ ${CYAN}              ⚡ FYX-AUTOWEB SYSTEM 7.0 ⚡              ${BOX_COLOR}║${NC}"
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

log_header

# --- PROTEÇÃO DE DADOS (PERSISTÊNCIA) ---
log_step "Verificando configurações existentes"
CF_BACKUP="/tmp/cf_config_backup"
if [[ -f "/etc/caddy/.cf_config" ]]; then
    cp "/etc/caddy/.cf_config" "$CF_BACKUP"
    echo -ne "${GREEN}(Backup das chaves Cloudflare realizado)${NC} "
fi
echo ""

log_step "Preparando sistema"
wait_for_apt
systemctl stop nginx >/dev/null 2>&1 || true
rm -f /etc/apt/sources.list.d/caddy*

# Dependências
log_step "Instalando dependências (net-tools adicionado)"
apt-get update -qq >/dev/null 2>&1
apt-get install -y -qq apt-transport-https ca-certificates curl gnupg2 dirmngr dos2unix nano iptables iptables-persistent jq net-tools >/dev/null 2>&1
log_success

# Node.js
log_step "Verificando Node.js"
if ! command -v node &> /dev/null; then
    curl -fsSL https://deb.nodesource.com/setup_18.x | bash - >/dev/null 2>&1
    wait_for_apt
    apt-get install -y nodejs >/dev/null 2>&1
else
    echo -e "${GREEN}✅${NC}"
fi

# PM2
log_step "Atualizando PM2"
npm install -g pm2 http-server >/dev/null 2>&1
pm2 update >/dev/null 2>&1
env PATH=$PATH:/usr/bin pm2 startup systemd -u root --hp /root >/dev/null 2>&1 || true
pm2 save --force >/dev/null 2>&1
log_success

# Caddy
log_step "Configurando Caddy"
curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/gpg.key' | gpg --dearmor -o /usr/share/keyrings/caddy-stable-archive-keyring.gpg
cat > /etc/apt/sources.list.d/caddy-stable.list <<EOF
deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/caddy-stable-archive-keyring.gpg] https://dl.cloudsmith.io/public/caddy/stable/deb/debian any-version main
EOF
wait_for_apt
apt-get update -qq >/dev/null 2>&1
apt-get install -y caddy >/dev/null 2>&1

# Estrutura Modular
mkdir -p /etc/caddy/sites-enabled
cat > /etc/caddy/Caddyfile <<'EOF'
{
    # Global Options
}
import sites-enabled/*
EOF

# --- RESTAURAÇÃO DE DADOS ---
if [[ -f "$CF_BACKUP" ]]; then
    mv "$CF_BACKUP" "/etc/caddy/.cf_config"
    chmod 600 "/etc/caddy/.cf_config"
    log_step "Restaurando chaves Cloudflare"
    log_success
fi

systemctl enable caddy >/dev/null 2>&1
systemctl restart caddy >/dev/null 2>&1 || true

# --- MENU SCRIPT ---
cat > /usr/local/bin/menu-site <<'EOF'
#!/usr/bin/env bash
# FYX-AUTOWEB v7.0 (Safe & Diagnostic)
set -u

# VARIAVEIS
CADDY_DIR="/etc/caddy"
SITES_DIR="/etc/caddy/sites-enabled"
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
  local count=$(ls -1 "$SITES_DIR" 2>/dev/null | wc -l)
  echo -e "${BOX_COLOR}╔══════════════════════════════════════════════════════════╗${NC}"
  echo -e "${BOX_COLOR}║${NC}             ${C}⚡ FYX-AUTOWEB SYSTEM 7.0 ⚡${NC}              ${BOX_COLOR}║${NC}"
  echo -e "${BOX_COLOR}╠══════════════════════════════════════════════════════════╣${NC}"
  echo -e "${BOX_COLOR}║${NC}  IP: ${Y}$(curl -s https://api.ipify.org)${NC}  |  Sites Ativos: ${G}$count${NC}  |  PM2: ${G}$(pm2 list | grep online | wc -l)${NC}   ${BOX_COLOR}║${NC}"
  echo -e "${BOX_COLOR}╚══════════════════════════════════════════════════════════╝${NC}"
  echo ""
}

draw_menu_item() { echo -e "   ${C}[$1]${NC} ${W}$2${NC}"; }

# --- CORE FUNCTIONS ---
reload_caddy() {
    echo -e "\n${Y}Validando configurações...${NC}"
    if ! caddy validate --config /etc/caddy/Caddyfile >/dev/null 2>&1; then
        echo -e "${R}❌ Configuração Inválida! Veja o erro:${NC}"
        caddy validate --config /etc/caddy/Caddyfile
        return 1
    fi
    if systemctl reload caddy >/dev/null 2>&1; then
        echo -e "${G}✔ Caddy Recarregado.${NC}"
    else
        echo -e "${Y}⚠ Reload falhou, forçando Restart...${NC}"
        systemctl restart caddy >/dev/null 2>&1 || { echo -e "${R}❌ Falha crítica no Caddy.${NC}"; return 1; }
        echo -e "${G}✔ Caddy Reiniciado.${NC}"
    fi
    return 0
}

get_next_port() {
  local last=$(grep -r "reverse_proxy localhost:" "$SITES_DIR" 2>/dev/null | sed -E 's/.*:([0-9]+).*/\1/' | sort -n | tail -n1)
  if [[ "$last" =~ ^[0-9]+$ ]]; then echo $((last + 1)); else echo "$BASE_PORT"; fi
}

write_caddy_config() {
    local domain=$1; local ssl=$2; local port=$3
    local tls_line=""; local tls_redir=""
    [[ "$ssl" == "2" ]] && tls_line="tls $CF_CERT $CF_KEY" && tls_redir=$tls_line
    [[ "$ssl" == "3" ]] && domain="http://$domain"
    
    local block="file_server"
    [[ "$port" != "0" ]] && block="reverse_proxy localhost:$port"

    cat > "$SITES_DIR/$domain" <<EOB
# Config: $domain
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
    echo -e "${G}✔ Arquivo criado: $SITES_DIR/$domain${NC}"
}

# --- DIAGNOSTIC TOOL ---
diagnose_system() {
    draw_header
    echo -e "${Y}🕵️  DIAGNÓSTICO DE SISTEMA${NC}"
    echo -e "${BOX_COLOR}────────────────────────────────────────────────────────────${NC}"
    
    # 1. Verifica Caddy
    echo -ne "Serviço Caddy: "
    if systemctl is-active --quiet caddy; then echo -e "${G}ONLINE${NC}"; else echo -e "${R}OFFLINE${NC}"; fi
    
    # 2. Verifica PM2
    echo -ne "Processos PM2: "
    local pm2_count=$(pm2 list | grep online | wc -l)
    echo -e "${G}$pm2_count rodando${NC}"
    
    echo -e "\n${C}--- Verificação de Portas (Apps) ---${NC}"
    
    # Loop pelos sites configurados
    if [[ -z $(ls -A "$SITES_DIR") ]]; then
        echo "Nenhum site configurado."
    else
        for site_file in "$SITES_DIR"/*; do
            local domain=$(basename "$site_file")
            local port=$(grep "reverse_proxy" "$site_file" | awk -F: '{print $2}' | tr -d ' ')
            
            if [[ -n "$port" ]]; then
                # Verifica se algo ouve na porta
                echo -ne "App $domain (Porta $port): "
                if netstat -tulpn 2>/dev/null | grep -q ":$port "; then
                    echo -e "${G}✅ ABERTA (Ouvindo)${NC}"
                else
                    echo -e "${R}❌ FECHADA (Nada rodando)${NC}"
                    echo -e "   -> ${Y}Dica: Seu app Node não está usando a porta $port ou crashou.${NC}"
                fi
            else
                echo -e "Site $domain: ${C}Estático (OK)${NC}"
            fi
        done
    fi
    
    echo -e "\n${C}--- Últimos Logs do Caddy ---${NC}"
    journalctl -u caddy --no-pager -n 5
    pause
}

# --- ACTIONS ---
list_sites() {
  draw_header; echo -e "${Y}📋 SITES ATIVOS${NC}"; echo -e "${BOX_COLOR}────────────────────────────────────────────────────────────${NC}"
  if [[ -z $(ls -A "$SITES_DIR") ]]; then echo "Vazio."; else
      local i=1
      for site_file in "$SITES_DIR"/*; do
          local d=$(basename "$site_file")
          local type="Estático"
          if grep -q "reverse_proxy" "$site_file"; then
             local p=$(grep "reverse_proxy" "$site_file" | awk -F: '{print $2}')
             type="App Porta: $p"
          fi
          printf "   ${C}[%02d]${NC} %-30s ${W}%s${NC}\n" "$i" "$d" "$type"
          ((i++))
      done
  fi
  pause
}

add_site() {
  draw_header; echo -e "${Y}➕ NOVO SITE${NC}"
  read -rp "🌐 Domínio: " d
  d=$(echo "$d" | sed -E 's/^\s*//;s/\s*$//;s/^(https?:\/\/)?(www\.)?//')
  [[ -z "$d" ]] && return
  [[ -f "$CF_CONFIG" ]] && create_dns_record "$d" && create_dns_record "www.$d"
  echo -e "📦 TIPO: 1) Estático  2) App PM2"; read -rp "Opção: " t; t=${t:-1}
  mkdir -p "/var/www/$d"
  p="0"
  if [[ "$t" == "2" ]]; then
    p=$(get_next_port)
    cat > "/var/www/$d/server.js" <<JS
const http = require('http');
http.createServer((r,s)=>{s.writeHead(200);s.end('<h1>$d : $p</h1>')}).listen($p);
JS
    pm2 start "/var/www/$d/server.js" --name "$d" >/dev/null; pm2 save >/dev/null
  else
    [[ ! -f "/var/www/$d/index.html" ]] && echo "<h1>$d</h1>" > "/var/www/$d/index.html"
  fi
  write_caddy_config "$d" "1" "$p"
  reload_caddy
  pause
}

rehost_site() {
    draw_header; echo -e "${Y}📂 RE-HOSPEDAR${NC}"; echo -e "${BOX_COLOR}────────────────────────────────────────────────────────────${NC}"
    dirs=($(ls -d /var/www/*/ 2>/dev/null | xargs -n 1 basename))
    if [[ ${#dirs[@]} -eq 0 ]]; then echo "Vazio."; pause; return; fi
    local i=1; for dir in "${dirs[@]}"; do
        status=$(test -f "$SITES_DIR/$dir" && echo "${G}[ON]${NC}" || echo "${Y}[OFF]${NC}")
        echo -e "   ${C}[$i]${NC} $dir $status"
        ((i++))
    done
    echo ""; read -rp "Número: " num
    if [[ "$num" -gt 0 && "$num" -le "${#dirs[@]}" ]]; then
        domain="${dirs[$((num-1))]}"
        read -rp "É App PM2? (s/N): " is_app; port="0"
        if [[ "$is_app" =~ ^[sS]$ ]]; then
             read -rp "1) Manual  2) Auto (Opção): " p_opt
             if [[ "$p_opt" == "2" ]]; then
                 port=$(get_next_port)
                 echo -e "${Y}⚠ Configure seu app na porta $port!${NC}"; read -r
             else
                 read -rp "Porta interna: " port
             fi
        fi
        read -rp "SSL: 1) Auto 2) Cloudflare: " ssl; ssl=${ssl:-1}
        write_caddy_config "$domain" "$ssl" "$port"
        reload_caddy
    fi
    pause
}

remove_site() {
  draw_header; echo -e "${Y}🗑️  REMOVER${NC}"
  if [[ -z $(ls -A "$SITES_DIR") ]]; then echo "Vazio."; pause; return; fi
  sites=($(ls "$SITES_DIR")); local i=1; for site in "${sites[@]}"; do echo -e "   ${C}[$i]${NC} $site"; ((i++)); done
  read -rp "Número: " num
  if [[ "$num" -gt 0 ]]; then
    d="${sites[$((num-1))]}"
    rm -f "$SITES_DIR/$d"
    pm2 delete "$d" >/dev/null 2>&1 || true; pm2 save >/dev/null
    read -rp "Apagar arquivos? (s/N): " dl; [[ "$dl" == "s" ]] && rm -rf "/var/www/$d"
    reload_caddy
    echo -e "${G}✔ Feito.${NC}"
  fi
  pause
}

sync_pm2_sites() {
    draw_header; echo -e "${Y}🔄 SYNC PM2${NC}"
    pm2_apps=$(pm2 jlist | jq -r '.[].name'); found=0
    for app in $pm2_apps; do
        if [[ -f "$SITES_DIR/$app" ]]; then continue; fi
        found=1; echo -e "\n${C}🔹 App novo:${NC} ${W}$app${NC}"
        read -rp "   Criar site? (s/n): " c
        if [[ "$c" == "s" ]]; then
             read -rp "   Domínio [$app]: " d; d=${d:-$app}
             read -rp "   Porta: " p
             [[ -f "$CF_CONFIG" ]] && create_dns_record "$d" && create_dns_record "www.$d"
             write_caddy_config "$d" "1" "$p"
             mkdir -p "/var/www/$d"
        fi
    done
    [[ $found -eq 0 ]] && echo -e "\n${G}Nada novo.${NC}" || reload_caddy
    pause
}

system_tools() {
    draw_header; echo -e "${Y}🛠️  FERRAMENTAS${NC}"
    echo -e "   1) ${G}Atualizar Script${NC}"; echo -e "   2) ${Y}Reparar Instalação${NC}"
    echo -e "   3) ${R}RESET DE FÁBRICA${NC}"; echo -e "   9) ${C}Diagnosticar Erros${NC}"
    echo ""; read -rp "   Opção: " opt
    case $opt in
        1) curl -sSL "$UPDATE_URL" > /tmp/install.sh; bash /tmp/install.sh; exit 0 ;;
        2) apt-get install --reinstall -y caddy nodejs; npm install -g pm2; echo "OK"; pause ;;
        3) read -rp "Digite 'RESET': " c; [[ "$c" == "RESET" ]] && rm -f "$SITES_DIR"/* && reload_caddy && echo "Resetado."; pause ;;
        9) diagnose_system ;;
    esac
}

setup_cf_api() {
  draw_header; echo -e "${Y}🔧 CLOUDFLARE API${NC}"
  read -rp "Email (Enter se usar Token): " e; read -rp "Token/Key: " k; read -rp "Zone ID: " z
  [[ -n "$k" ]] && echo "CF_EMAIL=\"$e\"" > "$CF_CONFIG" && echo "CF_KEY=\"$k\"" >> "$CF_CONFIG" && echo "CF_ZONE=\"$z\"" >> "$CF_CONFIG" && echo -e "${G}Salvo!${NC}"
  pause
}
create_dns_record() {
  if [[ ! -f "$CF_CONFIG" ]]; then return; fi
  source "$CF_CONFIG"; local d=$1; local ip=$(curl -s https://api.ipify.org)
  echo -ne "${Y}⚡ DNS ($d)... ${NC}"
  local H1="Authorization: Bearer $CF_KEY"; [[ -n "$CF_EMAIL" ]] && H1="X-Auth-Key: $CF_KEY"
  local H2=""; [[ -n "$CF_EMAIL" ]] && H2="-H \"X-Auth-Email: $CF_EMAIL\""
  # Curl simplificado para evitar conflito de quotes
  if [[ -z "$CF_EMAIL" ]]; then
      curl -s -X POST "https://api.cloudflare.com/client/v4/zones/$CF_ZONE/dns_records" -H "Authorization: Bearer $CF_KEY" -H "Content-Type: application/json" --data "{\"type\":\"A\",\"name\":\"$d\",\"content\":\"$ip\",\"ttl\":1,\"proxied\":true}" >/dev/null
  else
      curl -s -X POST "https://api.cloudflare.com/client/v4/zones/$CF_ZONE/dns_records" -H "X-Auth-Email: $CF_EMAIL" -H "X-Auth-Key: $CF_KEY" -H "Content-Type: application/json" --data "{\"type\":\"A\",\"name\":\"$d\",\"content\":\"$ip\",\"ttl\":1,\"proxied\":true}" >/dev/null
  fi
  echo -e "${G}OK${NC}"
}

while true; do
  draw_header
  draw_menu_item "1" "Listar Sites"
  draw_menu_item "2" "Novo Site"
  draw_menu_item "3" "Re-hospedar Pasta"
  draw_menu_item "4" "Sync Apps PM2"
  draw_menu_item "5" "Remover Site"
  echo ""; draw_menu_item "6" "Config CF API"; draw_menu_item "7" "Monitor PM2"
  echo ""; draw_menu_item "8" "Ferramentas"; draw_menu_item "9" "Diagnosticar Erros"
  echo ""; draw_menu_item "0" "Sair"; echo ""
  read -rp "Opção: " opt
  case $opt in
    1) list_sites ;; 2) add_site ;; 3) rehost_site ;; 4) sync_pm2_sites ;; 5) remove_site ;; 6) setup_cf_api ;; 7) pm2 monit ;; 8) system_tools ;; 9) diagnose_system ;; 0) exit 0 ;;
  esac
done
EOF
chmod +x /usr/local/bin/menu-site
log_success
echo -e "${GREEN}✅ INSTALAÇÃO 7.0 COMPLETA! Digite: menu-site${NC}"
menu-site
