#!/usr/bin/env bash
# install-menu-site.sh — Instala Caddy, PM2 e configura menu-site com Auto TLS e Cloudflare
set -euo pipefail

if [[ $EUID -ne 0 ]]; then
  echo "⚠️ Execute este script como root (sudo)." >&2
  exit 1
fi

CERT_DIR="/etc/caddy"
CF_CERT="$CERT_DIR/cloudflare.crt"
CF_KEY="$CERT_DIR/cloudflare.key"

# Limpeza inicial
systemctl stop nginx caddy >/dev/null 2>&1 || true
pkill -9 caddy >/dev/null 2>&1 || true
apt-get remove --purge -y nginx* caddy* >/dev/null 2>&1 || true
apt-get autoremove -y >/dev/null 2>&1 || true
rm -f $CERT_DIR/Caddyfile* /etc/apt/sources.list.d/caddy* /usr/share/keyrings/caddy* /etc/apt/keyrings/caddy*

# Dependências básicas
apt-get update -y
apt-get install -y apt-transport-https ca-certificates curl gnupg2 dirmngr dos2unix nano iptables iptables-persistent

# Instala Node.js 18 via NodeSource (inclui npm)
echo "==> Instalando Node.js 18 via NodeSource..."
curl -fsSL https://deb.nodesource.com/setup_18.x | bash -
apt-get install -y nodejs

# Firewall
iptables -I INPUT -p tcp --dport 80 -j ACCEPT
iptables -I INPUT -p tcp --dport 443 -j ACCEPT
netfilter-persistent save >/dev/null 2>&1 || service netfilter-persistent save >/dev/null 2>&1

# Instala PM2
echo "==> Instalando PM2..."
npm install -g pm2
npm install -g http-server


echo "==> Configurando PM2 para iniciar com o sistema..."
env PATH=$PATH:/usr/bin pm2 startup systemd -u root --hp /root
pm2 save --force



# Repositório Caddy
curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/gpg.key' | gpg --dearmor -o /usr/share/keyrings/caddy-stable-archive-keyring.gpg
chmod 644 /usr/share/keyrings/caddy-stable-archive-keyring.gpg
ARCH=$(dpkg --print-architecture)
cat > /etc/apt/sources.list.d/caddy-stable.list <<EOF
deb [arch=$ARCH signed-by=/usr/share/keyrings/caddy-stable-archive-keyring.gpg] https://dl.cloudsmith.io/public/caddy/stable/deb/debian any-version main
EOF

# Instala Caddy
apt-get update -y
apt-get install -y caddy

# Cria Caddyfile vazio
mkdir -p $CERT_DIR
cat > $CERT_DIR/Caddyfile <<'EOF'
# Caddyfile gerenciado pelo menu-site
EOF

# Restaura serviço Caddy em caso de reload travado
systemctl stop caddy
pkill -9 caddy || true
systemctl start caddy
systemctl enable caddy

# Instala menu-site
cat > /usr/local/bin/menu-site <<'EOF'
#!/usr/bin/env bash
# menu-site — Gerencia domínios no Caddy com Auto TLS, Cloudflare SSL e PM2
set -euo pipefail

CADDYFILE="/etc/caddy/Caddyfile"
BASE_PORT=2100
CF_CERT="/etc/caddy/cloudflare.crt"
CF_KEY="/etc/caddy/cloudflare.key"

pause() {
  read -rp "Pressione ENTER para continuar..."
}
setup_pm2() {
  command -v pm2 >/dev/null || { echo "❌ PM2 não está instalado."; exit 1; }
  pm2 save --force >/dev/null 2>&1 || true
}


title() {
  printf "\n===== %s =====\n" "$1"
}

detect_cf() {
  if [[ -f "$CF_CERT" && -f "$CF_KEY" ]]; then
    USE_CF=true
  else
    USE_CF=false
  fi
}


list_sites() {
  title "Sites cadastrados"
  grep -E '^[^#[:space:]].+{' "$CADDYFILE" | sed 's/{.*//' | nl -w2 -s'. ' || echo "(nenhum)"
  pause
}

get_next_port() {
  local last
  last=$(grep -E 'reverse_proxy localhost:[0-9]+' "$CADDYFILE" \
    | sed -E 's/.*:([0-9]+)/\1/' | sort -n | tail -n1)
  if [[ "$last" =~ ^[0-9]+$ ]]; then
    echo $((last+1))
  else
    echo "$BASE_PORT"
  fi
}

paste_pem() {
  local dest="$1"
  echo "Cole o PEM e pressione Ctrl+D quando terminar:"
  cat > "$dest"
  [[ -s "$dest" ]] && echo "→ Salvo em $dest" || { echo "❌ Falha ao salvar $dest"; return 1; }
  return 0
}

configure_cf() {
  detect_cf
  while true; do
    clear; title "Configurar Cloudflare SSL"
    echo "1) Colar certificado ($CF_CERT)"
    echo "2) Colar chave privada ($CF_KEY)"
    echo "0) Voltar"
    read -rp "Opção: " opt
    case "${opt//[^0-9]/}" in
      1) mkdir -p "$(dirname "$CF_CERT")"; paste_pem "$CF_CERT" && chmod 644 "$CF_CERT";;
      2) mkdir -p "$(dirname "$CF_KEY")"; paste_pem "$CF_KEY" && chmod 600 "$CF_KEY";;
      0) detect_cf; break;;
      *) echo "Inválido.";;
    esac
    pause
  done
}

add_site() {
  detect_cf
  setup_pm2
  title "Adicionar site"
  read -rp "Domínio (ex: exemplo.com): " domain
  echo "Método TLS:"
  echo " 1) HTTP only"
  echo " 2) Auto TLS (Let's Encrypt)"
  echo " 3) Cloudflare SSL"
  read -rp "Escolha [1-3]: " m

  local site tls_line port
  case "${m//[^0-9]/}" in
    1) site="http://$domain"; tls_line="";;
    2) site="$domain"; tls_line="";;
    3)
      if ! $USE_CF; then echo "⚠️ Configure o Cloudflare SSL antes (opção 5)."; pause; return; fi
      site="$domain"; tls_line="    tls $CF_CERT $CF_KEY";;
    *) echo "Inválido."; pause; return;;
  esac

  echo "Tipo de site:"
  echo " 1) Arquivos estáticos (HTML)"
  echo " 2) Reverse Proxy (aplicação local via PM2)"
  read -rp "Escolha [1-2]: " site_type

  if [[ $site_type == "2" ]]; then
    port=$(get_next_port)
    config="    reverse_proxy localhost:$port"
    echo "→ Porta interna: $port"
    pm2 start $(which http-server) --name "$domain" -- -p "$port" "/var/www/$domain"
    pm2 save >/dev/null
  else
    config="    file_server"
  fi

  mkdir -p "/var/www/$domain"
  cat > "/var/www/$domain/index.html" <<HTML
<!DOCTYPE html>
<html lang="pt-BR">
<head><meta charset="utf-8"><title>$domain</title>
<style>body{background:#121212;color:#fff;display:flex;align-items:center;justify-content:center;height:100vh;margin:0;font-family:sans-serif}</style></head>
<body><h1>Bem-vindo a $domain</h1></body></html>
HTML

  cat >> "$CADDYFILE" <<EOB

$site {
$tls_line
$config
}
EOB

  caddy fmt --overwrite "$CADDYFILE"

  if caddy validate --config "$CADDYFILE"; then
    systemctl reload caddy
    echo "→ Adicionado: $site (Caddy recarregado)"
  else
    echo "❌ Caddyfile inválido!"
  fi
  pause
}

view_pm2() {
  title "Sites PM2"
  pm2 ls
  pause
}

remove_site() {
  title "Remover site"
  local sites=($(grep -E '^[^#[:space:]].+{' "$CADDYFILE" | sed 's/{.*//' | sed 's/[[:space:]]*$//'))
  [[ ${#sites[@]} -eq 0 ]] && { echo "(nenhum site cadastrado)"; pause; return; }
  local idx=1; for site in "${sites[@]}"; do echo "$idx. $site"; ((idx++)); done
  read -rp "Índice a remover: " idx
  local domain="${sites[idx-1]}"
  sed -i "/^${domain//./\\.}[[:space:]]*{/,/^}/d" "$CADDYFILE"
  rm -rf "/var/www/$domain"; pm2 delete "$domain" || true; pm2 save >/dev/null
  systemctl reload caddy; pause
}

detect_cf
setup_pm2
while true; do
  clear; title "Gerenciador de Caddy Sites ===By OGERRVA==="
  echo "1) Listar"; echo "2) Adicionar"; echo "3) Remover"; echo "4) Editar"; echo "5) Configurar Cloudflare SSL"; echo "6) Ver sites PM2"; echo "0) Sair"
  read -rp "Opção: " opt
  case "${opt//[^0-9]/}" in
    1) list_sites;; 2) add_site;; 3) remove_site;; 4) edit_site;; 5) configure_cf;; 6) view_pm2;; 0) exit 0;; *) echo "Inválido"; pause;;
  esac
done


EOF
chmod +x /usr/local/bin/menu-site

echo "==> Instalação completa! Iniciando menu-site..."
menu-site
