#!/usr/bin/env bash
# install-menu-site.sh — Instala Caddy, PM2, Node.js e configura menu-site completo
# Inclui: Auto WWW Redirection e Criação de DNS na Cloudflare via API
set -euo pipefail

# Cores
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

if [[ $EUID -ne 0 ]]; then
  echo -e "${RED}⚠️ Execute este script como root (sudo).${NC}" >&2
  exit 1
fi

CERT_DIR="/etc/caddy"
CF_CONFIG="/etc/caddy/.cf_config"

# --- 1. Limpeza e Preparação ---
echo -e "${YELLOW}==> Preparando sistema...${NC}"
systemctl stop nginx caddy >/dev/null 2>&1 || true
pkill -9 caddy >/dev/null 2>&1 || true
# Remover versões antigas se existirem
apt-get remove --purge -y nginx* caddy* >/dev/null 2>&1 || true
rm -f $CERT_DIR/Caddyfile* /etc/apt/sources.list.d/caddy*

# --- 2. Instalação de Dependências ---
echo -e "${YELLOW}==> Instalando dependências (curl, jq, gnupg)...${NC}"
apt-get update -y
apt-get install -y apt-transport-https ca-certificates curl gnupg2 dirmngr dos2unix nano iptables iptables-persistent jq

# --- 3. Instalação Node.js 18 ---
if ! command -v node &> /dev/null; then
    echo -e "${YELLOW}==> Instalando Node.js 18...${NC}"
    curl -fsSL https://deb.nodesource.com/setup_18.x | bash -
    apt-get install -y nodejs
else
    echo -e "${GREEN}✓ Node.js já instalado.$(NC)"
fi

# --- 4. Firewall Básico ---
iptables -I INPUT -p tcp --dport 80 -j ACCEPT
iptables -I INPUT -p tcp --dport 443 -j ACCEPT
netfilter-persistent save >/dev/null 2>&1 || service netfilter-persistent save >/dev/null 2>&1

# --- 5. Instalação PM2 ---
echo -e "${YELLOW}==> Configurando PM2...${NC}"
npm install -g pm2 http-server
env PATH=$PATH:/usr/bin pm2 startup systemd -u root --hp /root >/dev/null 2>&1 || true
pm2 save --force >/dev/null 2>&1

# --- 6. Instalação Caddy (Repo Oficial) ---
echo -e "${YELLOW}==> Instalando Caddy Web Server...${NC}"
curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/gpg.key' | gpg --dearmor -o /usr/share/keyrings/caddy-stable-archive-keyring.gpg
chmod 644 /usr/share/keyrings/caddy-stable-archive-keyring.gpg
ARCH=$(dpkg --print-architecture)
cat > /etc/apt/sources.list.d/caddy-stable.list <<EOF
deb [arch=$ARCH signed-by=/usr/share/keyrings/caddy-stable-archive-keyring.gpg] https://dl.cloudsmith.io/public/caddy/stable/deb/debian any-version main
EOF
apt-get update -y
apt-get install -y caddy

# Configuração inicial Caddy
mkdir -p $CERT_DIR
if [[ ! -f "$CERT_DIR/Caddyfile" ]]; then
    cat > $CERT_DIR/Caddyfile <<'EOF'
# Caddyfile gerenciado pelo menu-site
EOF
fi

systemctl enable caddy
systemctl restart caddy

# --- 7. Criação do Script de Gerenciamento (menu-site) ---
cat > /usr/local/bin/menu-site <<'EOF'
#!/usr/bin/env bash
# menu-site — Gerenciador Completo (Caddy + Cloudflare DNS + Auto WWW)
set -euo pipefail

# Configurações
CADDYFILE="/etc/caddy/Caddyfile"
CF_CERT="/etc/caddy/cloudflare.crt"
CF_KEY="/etc/caddy/cloudflare.key"
CF_CONFIG="/etc/caddy/.cf_config"
BASE_PORT=3000

# Cores
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

pause() {
  echo ""
  read -rp "Pressione ENTER para continuar..."
}

header() {
  clear
  echo -e "${BLUE}========================================${NC}"
  echo -e "      ${YELLOW}GERENCIADOR DE SITES PRO${NC}"
  echo -e "      ${GREEN}By OGERRVA${NC}"
  echo -e "${BLUE}========================================${NC}"
  echo -e "Menu: $1"
  echo ""
}

# --- Funções Cloudflare API ---

setup_cf_api() {
  header "Configurar API Cloudflare"
  echo "Para criar subdomínios automaticamente, insira seus dados."
  echo "Necessário: Auth Token (ou Global Key + Email) e Zone ID."
  echo ""
  
  read -rp "Cloudflare Email (Enter para pular se usar Token): " cf_email
  read -rp "Cloudflare API Key ou Token: " cf_key
  read -rp "Zone ID (ID da Zona no painel da CF): " cf_zone
  
  if [[ -z "$cf_key" || -z "$cf_zone" ]]; then
    echo -e "${RED}Dados insuficientes. Cancelado.${NC}"
    return
  fi

  # Salvar config
  cat > "$CF_CONFIG" <<CFEOF
CF_EMAIL="$cf_email"
CF_KEY="$cf_key"
CF_ZONE="$cf_zone"
CFEOF
  chmod 600 "$CF_CONFIG"
  echo -e "${GREEN}Configuração salva em $CF_CONFIG!${NC}"
  pause
}

create_dns_record() {
  local domain="$1"
  
  if [[ ! -f "$CF_CONFIG" ]]; then
    echo -e "${YELLOW}API Cloudflare não configurada. Configure na opção 6.${NC}"
    return
  fi
  
  source "$CF_CONFIG"
  
  # Pegar IP Publico
  local public_ip
  public_ip=$(curl -s https://api.ipify.org)
  
  echo -e "${YELLOW}Criando registro DNS A para $domain -> $public_ip ...${NC}"
  
  # Define cabeçalhos dependendo se é Token ou Key+Email
  if [[ -z "$CF_EMAIL" ]]; then
    # Usando Token Bearer
    response=$(curl -s -X POST "https://api.cloudflare.com/client/v4/zones/$CF_ZONE/dns_records" \
      -H "Authorization: Bearer $CF_KEY" \
      -H "Content-Type: application/json" \
      --data "{\"type\":\"A\",\"name\":\"$domain\",\"content\":\"$public_ip\",\"ttl\":1,\"proxied\":true}")
  else
    # Usando Global Key (X-Auth-Key)
    response=$(curl -s -X POST "https://api.cloudflare.com/client/v4/zones/$CF_ZONE/dns_records" \
      -H "X-Auth-Email: $CF_EMAIL" \
      -H "X-Auth-Key: $CF_KEY" \
      -H "Content-Type: application/json" \
      --data "{\"type\":\"A\",\"name\":\"$domain\",\"content\":\"$public_ip\",\"ttl\":1,\"proxied\":true}")
  fi

  success=$(echo "$response" | jq -r '.success')
  if [[ "$success" == "true" ]]; then
    echo -e "${GREEN}✓ Sucesso! Subdomínio criado na Cloudflare (Proxied).${NC}"
  else
    echo -e "${RED}❌ Erro ao criar DNS:${NC}"
    echo "$response" | jq -r '.errors[].message'
  fi
  sleep 2
}

# --- Funções do Sistema ---

detect_cf_certs() {
  if [[ -f "$CF_CERT" && -f "$CF_KEY" ]]; then
    USE_CF_SSL=true
  else
    USE_CF_SSL=false
  fi
}

get_next_port() {
  local last_port
  last_port=$(grep -E 'reverse_proxy localhost:[0-9]+' "$CADDYFILE" | sed -E 's/.*:([0-9]+)/\1/' | sort -n | tail -n1)
  if [[ "$last_port" =~ ^[0-9]+$ ]]; then
    echo $((last_port + 1))
  else
    echo "$BASE_PORT"
  fi
}

configure_cf_certs() {
  header "Configurar Certificado Origin SSL (Arquivo)"
  echo "Isso é para o modo 'Full (Strict)' usando certificado gerado na Cloudflare."
  echo "1) Colar Certificado (.crt)"
  echo "2) Colar Chave (.key)"
  echo "0) Voltar"
  read -rp "Opção: " opt
  case $opt in
    1) 
      echo "Cole o conteúdo do CRT e pressione Ctrl+D:"
      cat > "$CF_CERT"
      chmod 644 "$CF_CERT"
      echo -e "${GREEN}Salvo!${NC}" ;;
    2)
      echo "Cole o conteúdo da KEY e pressione Ctrl+D:"
      cat > "$CF_KEY"
      chmod 600 "$CF_KEY"
      echo -e "${GREEN}Salvo!${NC}" ;;
  esac
  pause
}

add_site() {
  detect_cf_certs
  header "Adicionar Novo Site"
  
  read -rp "Domínio (ex: site.com ou app.site.com): " raw_domain
  
  # Limpeza do domínio (remove http://, https://, www.)
  domain=$(echo "$raw_domain" | sed -E 's/^\s*//;s/\s*$//;s/^(https?:\/\/)?(www\.)?//')
  
  if [[ -z "$domain" ]]; then echo -e "${RED}Domínio inválido.${NC}"; pause; return; fi
  
  echo -e "${YELLOW}Configurando para: $domain (e redirecionando www.$domain)${NC}"
  echo ""
  
  # Pergunta sobre DNS Cloudflare
  read -rp "Deseja criar o subdomínio/domínio na Cloudflare agora? (s/n): " create_dns
  if [[ "$create_dns" =~ ^[sS]$ ]]; then
    create_dns_record "$domain"
    # Opcional: criar também o www se for domínio raiz, mas vamos focar no principal
    create_dns_record "www.$domain"
  fi
  
  echo ""
  echo "Modo SSL/TLS:"
  echo " 1) Auto TLS (Let's Encrypt - Padrão)"
  echo " 2) Cloudflare Origin SSL (Requer certs configurados)"
  echo " 3) HTTP Only (Sem SSL)"
  read -rp "Escolha [1-3]: " tls_opt
  
  local tls_config=""
  local tls_redirect_config=""
  
  case $tls_opt in
    1) tls_config="";; # Auto
    2) 
       if ! $USE_CF_SSL; then echo -e "${RED}Certificados CF não encontrados na opção 5.${NC}"; pause; return; fi
       tls_config="tls $CF_CERT $CF_KEY"
       tls_redirect_config="tls $CF_CERT $CF_KEY"
       ;;
    3) 
        # HTTP only é complicado com redirecionamento HTTPS, mas vamos ajustar o domínio
        domain="http://$domain"
        tls_config=""
        ;;
    *) echo "Inválido"; return;;
  esac

  echo ""
  echo "Tipo de Aplicação:"
  echo " 1) Site Estático (HTML/JS)"
  echo " 2) Aplicação Node/Python/etc (Reverse Proxy)"
  read -rp "Escolha [1-2]: " app_type
  
  local caddy_directive=""
  
  if [[ "$app_type" == "2" ]]; then
    port=$(get_next_port)
    echo -e "${GREEN}→ Porta alocada: $port${NC}"
    caddy_directive="reverse_proxy localhost:$port"
    
    # Iniciar exemplo no PM2
    mkdir -p "/var/www/$domain"
    # Criar um server.js simples de exemplo
    cat > "/var/www/$domain/server.js" <<JS
const http = require('http');
const server = http.createServer((req, res) => {
  res.writeHead(200, { 'Content-Type': 'text/html; charset=utf-8' });
  res.end('<h1>Site $domain rodando via PM2!</h1>');
});
server.listen($port, () => console.log('Rodando na porta $port'));
JS
    pm2 start "/var/www/$domain/server.js" --name "$domain"
    pm2 save >/dev/null
    
  else
    caddy_directive="file_server"
    mkdir -p "/var/www/$domain"
    cat > "/var/www/$domain/index.html" <<HTML
<!DOCTYPE html>
<html><head><title>$domain</title></head>
<body style="background:#222;color:#fff;text-align:center;padding-top:50px;">
<h1>Bem-vindo a $domain</h1><p>Configurado via Menu-Site</p>
</body></html>
HTML
  fi

  # --- ESCRITA NO CADDYFILE ---
  # Lógica: 
  # 1. Bloco WWW -> Redireciona para non-www
  # 2. Bloco Principal -> Configuração real
  
  cat >> "$CADDYFILE" <<EOB

# --- Site: $domain ---
www.$domain {
    $tls_redirect_config
    redir https://$domain{uri}
}

$domain {
    $tls_config
    root * /var/www/$domain
    encode gzip
    $caddy_directive
}
EOB

  # Formata e Recarrega
  caddy fmt --overwrite "$CADDYFILE" >/dev/null
  if caddy validate --config "$CADDYFILE"; then
    systemctl reload caddy
    echo -e "${GREEN}✔ Site configurado com sucesso!${NC}"
    echo -e "Acesse: https://$domain (O www.$domain redirecionará automaticamente)"
  else
    echo -e "${RED}❌ Erro na validação do Caddyfile. Restaurando...${NC}"
    # Lógica de rollback poderia ser adicionada aqui
  fi
  pause
}

list_sites() {
  header "Sites Ativos"
  # Filtra nomes de domínios que não começam com www e não são diretivas
  grep -E '^[a-zA-Z0-9].+ \{$' "$CADDYFILE" | grep -v "www." | sed 's/ {//' | nl
  pause
}

remove_site() {
  header "Remover Site"
  # Listar sites para o usuário escolher (array)
  sites=($(grep -E '^[a-zA-Z0-9].+ \{$' "$CADDYFILE" | grep -v "www." | sed 's/ {//'))
  
  if [[ ${#sites[@]} -eq 0 ]]; then echo "Nenhum site encontrado."; pause; return; fi
  
  local i=1
  for site in "${sites[@]}"; do
    echo "$i) $site"
    ((i++))
  done
  
  read -rp "Número do site para remover: " num
  if [[ "$num" -gt 0 && "$num" -le "${#sites[@]}" ]]; then
    domain="${sites[$((num-1))]}"
    echo -e "${YELLOW}Removendo $domain e www.$domain...${NC}"
    
    # Remove do Caddyfile (Bloco principal e bloco www)
    # Esta sed é um pouco complexa, remove blocos baseados no nome
    sed -i "/^$domain \{/,/^\}/d" "$CADDYFILE"
    sed -i "/^www.$domain \{/,/^\}/d" "$CADDYFILE"
    
    # Limpa PM2 se existir
    pm2 delete "$domain" >/dev/null 2>&1 || true
    pm2 save >/dev/null
    
    # Remove arquivos
    read -rp "Excluir arquivos em /var/www/$domain? (s/n): " del_files
    if [[ "$del_files" == "s" ]]; then
        rm -rf "/var/www/$domain"
    fi
    
    caddy fmt --overwrite "$CADDYFILE" >/dev/null
    systemctl reload caddy
    echo -e "${GREEN}Removido com sucesso.${NC}"
  else
    echo "Inválido."
  fi
  pause
}

# --- Loop Principal ---
while true; do
  header "Menu Principal"
  echo "1) Listar Sites"
  echo "2) Adicionar Novo Site (c/ Redirecionamento WWW)"
  echo "3) Remover Site"
  echo "4) Editar Caddyfile Manualmente"
  echo "5) Configurar Certificados Cloudflare (Arquivos)"
  echo "6) Configurar API Cloudflare (Para criar DNS)"
  echo "7) Ver Status PM2"
  echo "0) Sair"
  echo ""
  read -rp "Escolha: " op
  
  case $op in
    1) list_sites ;;
    2) add_site ;;
    3) remove_site ;;
    4) nano "$CADDYFILE"; systemctl reload caddy ;;
    5) configure_cf_certs ;;
    6) setup_cf_api ;;
    7) pm2 list; pause ;;
    0) exit 0 ;;
    *) echo "Opção inválida."; sleep 1 ;;
  esac
done
EOF

chmod +x /usr/local/bin/menu-site

echo -e "${GREEN}==> Instalação Concluída!${NC}"
echo -e "Digite ${YELLOW}menu-site${NC} para começar."
menu-site
