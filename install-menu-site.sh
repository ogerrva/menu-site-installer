#!/usr/bin/env bash
# install-menu-site.sh — FYX-AUTOWEB Installer
# Versão 17.0 - Anti-Freeze & Verbose Mode

# 1. Configurações de Segurança e Não-Interatividade
export DEBIAN_FRONTEND=noninteractive
export LC_ALL=C.UTF-8
set -u

# Opções do APT para não perguntar nada (Força Sim para tudo e mantêm configs antigas)
APT_OPTS="-y -o Dpkg::Options::=--force-confdef -o Dpkg::Options::=--force-confold"

# 2. DEFINIÇÃO DE CORES
RED='\033[1;31m'
GREEN='\033[1;32m'
YELLOW='\033[1;33m'
BLUE='\033[1;34m'
CYAN='\033[1;36m'
WHITE='\033[1;37m'
NC='\033[0m'
BOX_COLOR='\033[0;35m'

UPDATE_URL="https://raw.githubusercontent.com/ogerrva/menu-site-installer/refs/heads/main/install-menu-site.sh"

# --- FUNÇÕES DE LOG ---
log_header() {
  clear
  echo -e "${BOX_COLOR}╔══════════════════════════════════════════════════════════════╗${NC}"
  echo -e "${BOX_COLOR}║ ${CYAN}             ⚡ FYX-AUTOWEB SYSTEM 17.0 ⚡               ${BOX_COLOR}║${NC}"
  echo -e "${BOX_COLOR}╚══════════════════════════════════════════════════════════════╝${NC}"
  echo ""
}
log_step() { echo -ne "${BLUE}[INFO]${NC} $1... "; }
log_success() { echo -e "${GREEN}✅ SUCESSO${NC}"; }

# Função de espera do APT melhorada
wait_for_apt() {
  local count=0
  while fuser /var/lib/dpkg/lock >/dev/null 2>&1 || fuser /var/lib/apt/lists/lock >/dev/null 2>&1 || fuser /var/lib/dpkg/lock-frontend >/dev/null 2>&1; do
    echo -ne "${YELLOW}⏳ O apt está ocupado por outro processo... aguardando ($count s)${NC}\r"
    sleep 5
    count=$((count+5))
    # Se demorar mais de 60s, tenta matar processos travados
    if [ $count -gt 60 ]; then
        echo -e "\n${RED}Desbloqueando apt forçadamente...${NC}"
        killall apt apt-get 2>/dev/null
        rm -f /var/lib/apt/lists/lock /var/cache/apt/archives/lock /var/lib/dpkg/lock*
    fi
  done
}

if [[ $EUID -ne 0 ]]; then echo -e "${RED}Erro: Execute como root.${NC}"; exit 1; fi

# --- SETUP DO SISTEMA ---
log_header
log_step "Backup de perfis Cloudflare"
CF_PROFILE_DIR="/etc/caddy/cf_profiles"
BACKUP_DIR="/tmp/cf_profiles_backup"
[[ -d "$CF_PROFILE_DIR" ]] && cp -r "$CF_PROFILE_DIR" "$BACKUP_DIR"
echo ""

log_step "Preparando sistema"
wait_for_apt
systemctl stop nginx >/dev/null 2>&1 || true
rm -f /etc/apt/sources.list.d/caddy*

# --- MODO VERBOSO ATIVADO PARA DEPENDÊNCIAS ---
echo -e "${CYAN}--- INICIANDO INSTALAÇÃO DE PACOTES (MODO VERBOSO) ---${NC}"
echo -e "${YELLOW}Se demorar, você verá o motivo abaixo:${NC}"

wait_for_apt
apt-get update

echo -e "${BLUE}> Instalando gerenciador de repositórios...${NC}"
apt-get install $APT_OPTS software-properties-common

echo -e "${BLUE}> Adicionando Repositório PHP (Ondrej)...${NC}"
# Adiciona PPA sem travar
if ! grep -q "ondrej/php" /etc/apt/sources.list.d/*; then
    add-apt-repository -y ppa:ondrej/php
fi
apt-get update

echo -e "${BLUE}> Instalando Pacotes Essenciais (PHP, Ferramentas)...${NC}"
# Instalação explícita sem esconder output
apt-get install $APT_OPTS apt-transport-https ca-certificates curl gnupg2 dirmngr dos2unix nano iptables iptables-persistent jq net-tools python3-pip python3-venv python3-full zip unzip git

echo -e "${CYAN}--- DEPENDÊNCIAS CONCLUÍDAS ---${NC}"
log_success

log_step "Verificando Node/PM2"
if ! command -v node &> /dev/null; then 
    echo "Instalando Node.js..."
    curl -fsSL https://deb.nodesource.com/setup_18.x | bash -
    apt-get install $APT_OPTS nodejs
fi
npm install -g pm2 http-server
pm2 update
env PATH=$PATH:/usr/bin pm2 startup systemd -u root --hp /root >/dev/null 2>&1 || true
pm2 save --force
log_success

log_step "Instalando Caddy (Keyring Fix)"
# Garante que a pasta existe
mkdir -p /usr/share/keyrings
curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/gpg.key' | gpg --dearmor --yes -o /usr/share/keyrings/caddy-stable-archive-keyring.gpg
cat > /etc/apt/sources.list.d/caddy-stable.list <<EOF
deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/caddy-stable-archive-keyring.gpg] https://dl.cloudsmith.io/public/caddy/stable/deb/debian any-version main
EOF
wait_for_apt
apt-get update
apt-get install $APT_OPTS caddy

mkdir -p /etc/caddy/sites-enabled
mkdir -p "$CF_PROFILE_DIR"

# Caddyfile Mestre
cat > /etc/caddy/Caddyfile <<'EOF'
{
    # Opções Globais
}
import sites-enabled/*
EOF

if [[ -d "$BACKUP_DIR" ]]; then cp -r "$BACKUP_DIR/"* "$CF_PROFILE_DIR/" 2>/dev/null; fi

systemctl enable caddy >/dev/null 2>&1
systemctl restart caddy >/dev/null 2>&1 || true
log_success

# --- MENU SCRIPT ---
cat > /usr/local/bin/menu-site <<'EOF'
#!/usr/bin/env bash
# FYX-AUTOWEB v17.0
set -u

# VARIAVEIS
CADDY_DIR="/etc/caddy"
SITES_DIR="/etc/caddy/sites-enabled"
CF_PROFILE_DIR="/etc/caddy/cf_profiles"
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
  echo -e "${BOX_COLOR}║${NC}             ${C}⚡ FYX-AUTOWEB SYSTEM 17.0 ⚡${NC}             ${BOX_COLOR}║${NC}"
  echo -e "${BOX_COLOR}╠══════════════════════════════════════════════════════════╣${NC}"
  echo -e "${BOX_COLOR}║${NC}  IP: ${Y}$(curl -s https://api.ipify.org)${NC}  |  Sites Ativos: ${G}$count${NC}  |  PM2: ${G}$(pm2 list | grep online | wc -l)${NC}   ${BOX_COLOR}║${NC}"
  echo -e "${BOX_COLOR}╚══════════════════════════════════════════════════════════╝${NC}"
  echo ""
}

draw_menu_item() { echo -e "   ${C}[$1]${NC} ${W}$2${NC}"; }

# --- CORE FUNCTIONS ---

reload_caddy() {
    echo -e "\n${Y}Aplicando configurações...${NC}"
    if ! caddy validate --config /etc/caddy/Caddyfile >/dev/null 2>&1; then
        echo -e "${R}❌ Erro no Caddyfile!${NC}"
        caddy validate --config /etc/caddy/Caddyfile
        return 1
    fi
    if systemctl reload caddy >/dev/null 2>&1; then
        echo -e "${G}✔ Caddy Recarregado.${NC}"
    else
        systemctl restart caddy >/dev/null 2>&1
        echo -e "${G}✔ Caddy Reiniciado.${NC}"
    fi
    return 0
}

get_next_port() {
  local last=$(grep -r "reverse_proxy localhost:" "$SITES_DIR" 2>/dev/null | sed -E 's/.*:([0-9]+).*/\1/' | sort -n | tail -n1)
  if [[ "$last" =~ ^[0-9]+$ ]]; then echo $((last + 1)); else echo "$BASE_PORT"; fi
}

detect_running_port() {
    local app_name=$1
    local pid=$(pm2 jlist | jq -r ".[] | select(.name == \"$app_name\") | .pid")
    if [[ -z "$pid" || "$pid" == "null" ]]; then echo "0"; return; fi
    local port=$(netstat -tulpn 2>/dev/null | grep " $pid/" | awk '{print $4}' | awk -F: '{print $NF}' | head -n1)
    if [[ -n "$port" ]]; then echo "$port"; else echo "0"; fi
}

# --- PHP MANAGER ---

ensure_php_installed() {
    local ver=$1
    if ! dpkg -l | grep -q "php$ver-fpm"; then
        echo -e "\n${Y}Instalando PHP $ver e extensões...${NC}"
        # Força instalação sem perguntas
        export DEBIAN_FRONTEND=noninteractive
        apt-get update -qq
        apt-get install -y -o Dpkg::Options::=--force-confdef -o Dpkg::Options::=--force-confold "php$ver-fpm" "php$ver-mysql" "php$ver-curl" "php$ver-gd" "php$ver-mbstring" "php$ver-xml" "php$ver-zip"
        echo -e "${G}✔ PHP $ver instalado!${NC}"
    fi
    systemctl start "php$ver-fpm"
    systemctl enable "php$ver-fpm" >/dev/null 2>&1
}

get_php_socket() {
    local ver=$1
    echo "unix//run/php/php$ver-fpm.sock"
}

# --- CLOUDFLARE ---

manage_cf_profiles() {
    draw_header
    echo -e "${Y}☁️  PERFIS CLOUDFLARE${NC}"
    echo -e "   1) Adicionar Perfil"
    echo -e "   2) Listar Perfis"
    echo -e "   0) Voltar"
    echo ""; read -rp "   Opção: " opt
    
    if [[ "$opt" == "1" ]]; then
        echo ""; read -rp "   Nome do Perfil (ex: Pessoal): " p_name
        p_name=$(echo "$p_name" | tr -cd '[:alnum:]_-')
        [[ -z "$p_name" ]] && return
        
        echo -e "\n   ${C}Tutorial: https://dash.cloudflare.com/profile/api-tokens${NC}"
        read -rp "   API Token: " p_token
        read -rp "   Zone ID: " p_zone
        
        echo -ne "   Testando... "
        if curl -s -X GET "https://api.cloudflare.com/client/v4/user/tokens/verify" -H "Authorization: Bearer $p_token" | grep -q "active"; then
            echo -e "${G}VÁLIDO!${NC}"
        else
            echo -e "${R}Token inválido ou erro de conexão.${NC}"
        fi
        
        echo "CF_KEY=\"$p_token\"" > "$CF_PROFILE_DIR/$p_name.conf"
        echo "CF_ZONE=\"$p_zone\"" >> "$CF_PROFILE_DIR/$p_name.conf"
        chmod 600 "$CF_PROFILE_DIR/$p_name.conf"
        echo -e "${G}✔ Salvo!${NC}"; pause
    elif [[ "$opt" == "2" ]]; then
        echo ""; ls -1 "$CF_PROFILE_DIR" | sed 's/.conf//'; pause
    fi
}

select_and_create_dns() {
    local domain=$1
    if [[ -z $(ls -A "$CF_PROFILE_DIR") ]]; then return; fi
    
    echo -e "\n${Y}⚡ Deseja criar DNS na Cloudflare?${NC}"
    echo "   0) Não criar"
    local i=1; local profiles=()
    for f in "$CF_PROFILE_DIR"/*.conf; do
        local p_name=$(basename "$f" .conf)
        profiles+=("$p_name")
        echo "   $i) Usar: $p_name"
        ((i++))
    done
    read -rp "   Escolha: " p_choice
    
    if [[ "$p_choice" -gt 0 && "$p_choice" -le "${#profiles[@]}" ]]; then
        local selected="${profiles[$((p_choice-1))]}"
        source "$CF_PROFILE_DIR/$selected.conf"
        
        echo -e "\n   ${C}☁️  MODO DA NUVEM (PROXY):${NC}"
        echo -e "   1) ${G}Laranja (Proxied)${NC}"
        echo -e "   2) ${W}Cinza (DNS Only)${NC}"
        read -rp "   Opção [1]: " proxy_opt
        
        local is_proxied="true"
        if [[ "$proxy_opt" == "2" ]]; then is_proxied="false"; fi
        
        local ip=$(curl -s https://api.ipify.org)
        
        echo -ne "   Criando DNS ($domain)... "
        curl -s -X POST "https://api.cloudflare.com/client/v4/zones/$CF_ZONE/dns_records" \
            -H "Authorization: Bearer $CF_KEY" -H "Content-Type: application/json" \
            --data "{\"type\":\"A\",\"name\":\"$domain\",\"content\":\"$ip\",\"ttl\":1,\"proxied\":$is_proxied}" >/dev/null
        echo -e "${G}OK${NC}"
        
        echo -ne "   Criando DNS (www.$domain)... "
        curl -s -X POST "https://api.cloudflare.com/client/v4/zones/$CF_ZONE/dns_records" \
            -H "Authorization: Bearer $CF_KEY" -H "Content-Type: application/json" \
            --data "{\"type\":\"A\",\"name\":\"www.$domain\",\"content\":\"$ip\",\"ttl\":1,\"proxied\":$is_proxied}" >/dev/null
        echo -e "${G}OK${NC}"
    fi
}

write_caddy_config() {
    local domain=$1; local ssl=$2; local type=$3; local extra=$4
    local tls_line=""
    
    if [[ "$ssl" == "2" ]]; then
        if [[ ! -f "$CF_CERT" || ! -f "$CF_KEY" ]]; then
             echo -e "\n${R}❌ ERRO: Certificados manuais não encontrados!${NC}"
             echo -e "${Y}   Usando Auto TLS para não falhar.${NC}"
             ssl="1"; read -rp "   Enter para continuar..." d
        else
             tls_line="tls $CF_CERT $CF_KEY"
        fi
    fi
    
    [[ "$ssl" == "3" ]] && domain="http://$domain"
    
    local block=""
    if [[ "$type" == "static" ]]; then
        block="file_server"
    elif [[ "$type" == "proxy" ]]; then
        block="reverse_proxy localhost:$extra"
    elif [[ "$type" == "php" ]]; then
        local socket=$(get_php_socket "$extra")
        block="php_fastcgi $socket
        file_server"
    fi

    cat > "$SITES_DIR/$domain" <<EOB
# Config: $domain
www.$domain, $domain {
    $tls_line
    
    @www host www.$domain
    handle @www {
        redir https://$domain{uri}
    }

    handle {
        root * /var/www/$domain
        encode gzip
        $block
    }
}
EOB
    echo -e "${G}✔ Configuração salva.${NC}"
}

# --- ACTIONS ---

rehost_site() {
    draw_header; echo -e "${Y}📂 RE-HOSPEDAR (Seguro)${NC}"; echo -e "${BOX_COLOR}────────────────────────────────────────────────────────────${NC}"
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
        local site_path="/var/www/$domain"
        
        # PYTHON VENV CHECK
        if [[ -f "$site_path/requirements.txt" ]]; then
             echo -e "\n${C}🐍 PYTHON DETECTADO${NC}"
             read -rp "   Criar Ambiente Virtual (venv) e instalar dependências? (s/N): " inst_py
             if [[ "$inst_py" =~ ^[sS]$ ]]; then
                 echo -e "   ${Y}Criando venv isolado...${NC}"
                 python3 -m venv "$site_path/venv"
                 echo -e "   ${Y}Instalando requirements...${NC}"
                 if "$site_path/venv/bin/pip" install -r "$site_path/requirements.txt"; then
                     echo -e "   ${G}✔ Instalado.${NC}"
                     echo -e "   ${Y}Interp: $site_path/venv/bin/python${NC}"
                 fi
             fi
        fi

        # CLOUDFLARE DNS CHECK
        select_and_create_dns "$domain"

        if [[ -f "$SITES_DIR/$domain" ]]; then
             echo -e "\n${R}⚠️  ATENÇÃO: $domain já está ativo!${NC}"
             read -rp "Sobrescrever configuração? (s/N): " confirm
             if [[ "$confirm" != "s" && "$confirm" != "S" ]]; then return; fi
        fi

        echo -e "\n${Y}Configurando aplicação...${NC}"
        
        local detected_port=$(detect_running_port "$domain")
        local port="0"
        local site_type="static"
        local extra_data=""

        if [[ "$detected_port" != "0" ]]; then
            echo -e "${G}⚡ DETECTADO!${NC} App na porta ${C}$detected_port${NC}."
            port="$detected_port"
            site_type="proxy"
            extra_data="$port"
        else
            echo -e "Selecione o tipo do site:"
            echo -e "   1) Estático (HTML)"
            echo -e "   2) PHP (WordPress/Laravel)"
            echo -e "   3) Aplicação Node/PM2/Python"
            read -rp "   Opção [1]: " type_opt
            
            case $type_opt in
                2)
                    site_type="php"
                    echo -e "\n   ${C}Escolha a versão do PHP:${NC}"
                    echo -e "   1) PHP 8.3"
                    echo -e "   2) PHP 8.2 (Padrão)"
                    echo -e "   3) PHP 8.1"
                    echo -e "   4) PHP 7.4"
                    read -rp "   Versão [2]: " php_v_opt
                    case $php_v_opt in 1) ver="8.3" ;; 3) ver="8.1" ;; 4) ver="7.4" ;; *) ver="8.2" ;; esac
                    ensure_php_installed "$ver"
                    extra_data="$ver"
                    ;;
                3)
                    site_type="proxy"
                    read -rp "   Porta interna do App: " extra_data
                    ;;
                *) site_type="static" ;;
            esac
        fi
        
        echo ""
        echo -e "🔐 SSL: 1) Auto  2) Cloudflare Manual"
        read -rp "Opção [1]: " ssl; ssl=${ssl:-1}
        
        write_caddy_config "$domain" "$ssl" "$site_type" "$extra_data"
        reload_caddy
    fi
    pause
}

add_site() {
  draw_header; echo -e "${Y}➕ NOVO SITE${NC}"
  read -rp "🌐 Domínio: " d
  d=$(echo "$d" | sed -E 's/^\s*//;s/\s*$//;s/^(https?:\/\/)?(www\.)?//')
  [[ -z "$d" ]] && return
  
  select_and_create_dns "$d"
  
  mkdir -p "/var/www/$d"
  
  echo -e "\n📦 TIPO DE SITE:"
  echo -e "   1) Estático (HTML)"
  echo -e "   2) PHP (WordPress/Laravel)"
  echo -e "   3) App PM2 (Node.js)"
  read -rp "   Opção [1]: " t; t=${t:-1}
  
  local site_type="static"
  local extra_data=""
  
  case $t in
      2)
          site_type="php"
          echo -e "\n   ${C}Versão PHP:${NC} 1) 8.3  2) 8.2  3) 8.1  4) 7.4"
          read -rp "   Escolha [2]: " pv
          case $pv in 1) ver="8.3";; 3) ver="8.1";; 4) ver="7.4";; *) ver="8.2";; esac
          ensure_php_installed "$ver"
          extra_data="$ver"
          if [[ ! -f "/var/www/$d/index.php" ]]; then echo "<?php phpinfo(); ?>" > "/var/www/$d/index.php"; fi
          ;;
      3)
          site_type="proxy"
          local p=$(get_next_port)
          extra_data="$p"
          cat > "/var/www/$d/server.js" <<JS
const http = require('http');
http.createServer((r,s)=>{s.writeHead(200);s.end('<h1>$d : $p</h1>')}).listen($p);
JS
          pm2 start "/var/www/$d/server.js" --name "$d" >/dev/null; pm2 save >/dev/null
          ;;
      *)
          site_type="static"
          if [[ ! -f "/var/www/$d/index.html" ]]; then echo "<h1>$d</h1>" > "/var/www/$d/index.html"; fi
          ;;
  esac
  
  write_caddy_config "$d" "1" "$site_type" "$extra_data"
  reload_caddy
  pause
}

sync_pm2_sites() {
    draw_header; echo -e "${Y}🔄 SYNC PM2${NC}"
    pm2_apps=$(pm2 jlist | jq -r '.[].name'); found=0
    for app in $pm2_apps; do
        if [[ -f "$SITES_DIR/$app" ]]; then continue; fi
        found=1; echo -e "\n${C}🔹 App novo:${NC} ${W}$app${NC}"
        local p=$(detect_running_port "$app")
        if [[ "$p" != "0" ]]; then echo -e "   (Porta detectada: $p)"; fi
        read -rp "   Hospedar? (s/n): " c
        if [[ "$c" == "s" ]]; then
             read -rp "   Domínio [$app]: " d; d=${d:-$app}
             if [[ "$p" == "0" ]]; then read -rp "   Porta: " p; fi
             select_and_create_dns "$d"
             write_caddy_config "$d" "1" "proxy" "$p"
             mkdir -p "/var/www/$d"
        fi
    done
    [[ $found -eq 0 ]] && echo -e "\n${G}Nada novo.${NC}" || reload_caddy
    pause
}

list_sites() {
  draw_header; echo -e "${Y}📋 SITES ATIVOS${NC}"; echo -e "${BOX_COLOR}────────────────────────────────────────────────────────────${NC}"
  if [[ -z $(ls -A "$SITES_DIR") ]]; then echo "Vazio."; else
      local site_files=($(ls "$SITES_DIR"))
      local i=1
      for site_file in "${site_files[@]}"; do
          local d="$site_file"
          local full_path="$SITES_DIR/$d"
          local type="Estático"
          if grep -q "reverse_proxy" "$full_path"; then
             local p=$(grep "reverse_proxy" "$full_path" | awk -F: '{print $2}')
             type="App Porta: $p"
          elif grep -q "php_fastcgi" "$full_path"; then
             type="PHP"
          fi
          printf "   ${C}[%02d]${NC} %-30s ${W}%s${NC}\n" "$i" "$d" "$type"
          ((i++))
      done
      echo -e "${BOX_COLOR}────────────────────────────────────────────────────────────${NC}"
      echo -e "   [0] Voltar"
      read -rp "   Digite o número para ABRIR O TERMINAL na pasta (ou 0): " opt
      if [[ "$opt" -gt 0 && "$opt" -le "${#site_files[@]}" ]]; then
          local selected_domain="${site_files[$((opt-1))]}"
          local target_dir="/var/www/$selected_domain"
          if [[ -d "$target_dir" ]]; then
              echo -e "\n${Y}Entrando em: $target_dir${NC}"
              echo -e "${C}Digite 'exit' para voltar ao menu.${NC}\n"
              (cd "$target_dir" && bash)
          fi
      fi
  fi
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

system_tools() {
    draw_header; echo -e "${Y}🛠️  FERRAMENTAS${NC}"
    echo -e "   1) ${G}Atualizar Script${NC}"; echo -e "   2) ${Y}Reparar Instalação${NC}"
    echo -e "   3) ${R}RESET DE FÁBRICA${NC}"; echo -e "   4) Editar Certificado Cloudflare (Manual)"
    echo -e "   9) ${C}Diagnosticar Erros${NC}"
    echo ""; read -rp "   Opção: " opt
    case $opt in
        1) curl -sSL "$UPDATE_URL" > /tmp/install.sh; bash /tmp/install.sh; exit 0 ;;
        2) apt-get install --reinstall -y caddy nodejs; npm install -g pm2; echo "OK"; pause ;;
        3) read -rp "Digite 'RESET': " c; [[ "$c" == "RESET" ]] && rm -f "$SITES_DIR"/* && reload_caddy && echo "Resetado."; pause ;;
        4) nano "$CF_CERT"; nano "$CF_KEY"; pause ;;
        9) echo "Diagnóstico básico..."; pm2 list; echo "Use netstat -tulpn para ver portas"; pause ;;
    esac
}

while true; do
  draw_header
  draw_menu_item "1" "Listar Sites / Gerenciar Arquivos"
  draw_menu_item "2" "Novo Site"
  draw_menu_item "3" "Re-hospedar (Auto-Detect)"
  draw_menu_item "4" "Sync Apps PM2"
  draw_menu_item "5" "Remover Site"
  echo ""; draw_menu_item "6" "Gerenciar Perfis Cloudflare"; draw_menu_item "7" "Monitor PM2"
  echo ""; draw_menu_item "8" "Ferramentas"; draw_menu_item "0" "Sair"; echo ""
  read -rp "Opção: " opt
  case $opt in
    1) list_sites ;; 2) add_site ;; 3) rehost_site ;; 4) sync_pm2_sites ;; 5) remove_site ;; 6) manage_cf_profiles ;; 7) pm2 monit ;; 8) system_tools ;; 0) exit 0 ;;
  esac
done
EOF
chmod +x /usr/local/bin/menu-site
log_success
echo -e "${GREEN}✅ INSTALAÇÃO 17.0 COMPLETA! Digite: menu-site${NC}"
menu-site
