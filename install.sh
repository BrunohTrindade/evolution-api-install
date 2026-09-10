#!/usr/bin/env bash
# Instalador interativo da Evolution API (Docker Compose).
# Uso: sudo ./install.sh
# Não-interativo: EVOLUTION_NONINTERACTIVE=1 sudo -E ./install.sh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DOCKER_IMAGE="evoapicloud/evolution-api"
DEFAULT_DIR="/opt/evolution-api"
DEFAULT_VERSION="latest"
START_PORT=8080

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

log()  { printf "${GREEN}==>${NC} %s\n" "$*"; }
warn() { printf "${YELLOW}aviso:${NC} %s\n" "$*"; }
err()  { printf "${RED}erro:${NC} %s\n" "$*" >&2; }
die()  { err "$*"; exit 1; }

need_root() {
  if [[ "${EUID}" -ne 0 ]]; then
    die "Executa como root: sudo $0"
  fi
}

is_noninteractive() {
  [[ "${EVOLUTION_NONINTERACTIVE:-0}" == "1" ]] || [[ ! -t 0 ]]
}

ask() {
  local dest="$1" prompt="$2" default="${3:-}"
  local reply
  if is_noninteractive; then
    printf -v "$dest" '%s' "$default"
    return
  fi
  if [[ -n "$default" ]]; then
    read -r -p "$prompt [$default]: " reply || true
  else
    read -r -p "$prompt: " reply || true
  fi
  printf -v "$dest" '%s' "${reply:-$default}"
}

ask_yes_no() {
  local dest="$1" prompt="$2" default="${3:-n}"
  local hint reply
  if [[ "$default" =~ ^[sSyY]$ ]]; then
    hint="S/n"
  else
    hint="s/N"
  fi
  if is_noninteractive; then
    printf -v "$dest" '%s' "$default"
    return
  fi
  read -r -p "$prompt [$hint]: " reply || true
  reply="${reply:-$default}"
  if [[ "$reply" =~ ^[sSyY]$ ]]; then
    printf -v "$dest" '%s' "s"
  else
    printf -v "$dest" '%s' "n"
  fi
}

port_in_use() {
  local port="$1"
  ss -H -tln 2>/dev/null | awk '{print $4}' | grep -qE ":${port}$" && return 0
  return 1
}

port_held_by_stack() {
  local port="$1"
  command -v docker >/dev/null 2>&1 || return 1
  docker inspect evolution_api >/dev/null 2>&1 || return 1
  docker port evolution_api 2>/dev/null | grep -qE ":${port}$"
}

find_free_port() {
  local port="$START_PORT"
  while port_in_use "$port" || [[ "$port" == "80" || "$port" == "443" ]]; do
    port=$((port + 1))
    if [[ "$port" -gt 8999 ]]; then
      die "Não encontrei uma porta livre entre ${START_PORT} e 8999"
    fi
  done
  printf '%s' "$port"
}

public_ip() {
  local ip
  ip="$(ip -4 route get 1.1.1.1 2>/dev/null | awk '{for (i=1;i<=NF;i++) if ($i=="src") {print $(i+1); exit}}')"
  if [[ -z "$ip" ]]; then
    ip="$(hostname -I 2>/dev/null | awk '{print $1}')"
  fi
  printf '%s' "${ip:-127.0.0.1}"
}

ensure_docker() {
  if command -v docker >/dev/null 2>&1 && docker compose version >/dev/null 2>&1; then
    log "Docker e Compose já estão instalados ($(docker --version | head -n1))"
    systemctl enable --now docker >/dev/null 2>&1 || true
    return
  fi

  log "A instalar Docker Engine e o plugin Compose (repositório oficial)"
  export DEBIAN_FRONTEND=noninteractive
  apt-get update -y
  apt-get install -y ca-certificates curl gnupg
  install -m 0755 -d /etc/apt/keyrings
  if [[ ! -f /etc/apt/keyrings/docker.asc ]]; then
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
    chmod a+r /etc/apt/keyrings/docker.asc
  fi
  . /etc/os-release
  local codename="${UBUNTU_CODENAME:-$VERSION_CODENAME}"
  printf 'deb [arch=%s signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu %s stable\n' \
    "$(dpkg --print-architecture)" "$codename" > /etc/apt/sources.list.d/docker.list
  apt-get update -y
  apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
  systemctl enable --now docker
  docker --version
  docker compose version
}

list_versions() {
  log "Tags recentes de ${DOCKER_IMAGE}:"
  local json json_v2
  json=""
  json_v2=""
  json="$(curl -fsSL --max-time 12 "https://hub.docker.com/v2/repositories/${DOCKER_IMAGE}/tags?page_size=20&name=v2" 2>/dev/null || true)"
  json_v2="$json"
  if [[ -z "$json_v2" ]]; then
    warn "Não foi possível listar tags no Docker Hub. Usa 'latest' ou uma tag como v2.3.7"
    echo "  - latest"
    return
  fi
  if command -v python3 >/dev/null 2>&1; then
    printf '%s' "$json" | python3 -c '
import json, sys
try:
    data = json.load(sys.stdin)
except Exception:
    sys.exit(0)
names = []
for item in data.get("results", []):
    name = item.get("name") or ""
    if name and name not in names:
        names.append(name)
priority = [n for n in names if n == "latest" or n.startswith("v2.") or n.startswith("2.")]
rest = [n for n in names if n not in priority]
shown = (priority + rest)[:12]
if "latest" not in shown:
    shown = ["latest"] + shown[:11]
for name in shown:
    print("  - " + name)
'
  else
    echo "  - latest"
    printf '%s' "$json" | grep -oE '"name":"v2[^"]+"' | head -n 10 | sed 's/"name":"/  - /;s/"$//'
  fi
}

resolve_install_dir() {
  local dest_var="$1"
  local choice=""
  printf "Pasta de instalação:\n"
  printf "  1) %s (recomendado)\n" "$DEFAULT_DIR"
  printf "  2) /var/www/evolution-api\n"
  printf "  3) Outro caminho\n"
  ask choice "Escolhe 1, 2 ou 3" "1"
  case "$choice" in
    1)
      printf -v "$dest_var" '%s' "$DEFAULT_DIR"
      ;;
    2)
      printf -v "$dest_var" '%s' "/var/www/evolution-api"
      ;;
    3)
      ask "$dest_var" "Caminho absoluto" "$DEFAULT_DIR"
      ;;
    /*)
      printf -v "$dest_var" '%s' "$choice"
      ;;
    *)
      printf -v "$dest_var" '%s' "$(pwd)/${choice}"
      warn "«${choice}» não é 1, 2 ou 3; a usar ${!dest_var}"
      ;;
  esac
}

STACK_VOLUMES=(
  evolution-api_evolution_postgres
  evolution-api_evolution_redis
  evolution-api_evolution_instances
)

maybe_reset_volumes() {
  local dest="$1"
  local keep="$2"
  docker volume inspect evolution-api_evolution_postgres >/dev/null 2>&1 || return 0
  if [[ "$keep" == "s" ]]; then
    return 0
  fi
  warn "Já existe um volume Postgres desta stack. Senha nova não funciona com dados antigos."
  local wipe="${EVOLUTION_RESET_VOLUMES:-}"
  if [[ -z "$wipe" ]]; then
    ask_yes_no wipe "Apagar volumes Docker (Postgres, Redis e instâncias) e começar do zero?" "s"
  fi
  if [[ "$wipe" != "s" ]]; then
    die "Não dá para continuar com senha nova e volume antigo. Reutiliza o .env ou apaga os volumes."
  fi
  log "A parar contentores e apagar volumes…"
  (
    cd "$dest"
    docker compose down --remove-orphans
  ) || true
  docker rm -f evolution_api evolution_postgres evolution_redis >/dev/null 2>&1 || true
  docker volume rm -f "${STACK_VOLUMES[@]}" >/dev/null 2>&1 || true
}

copy_project_files() {
  local dest="$1"
  mkdir -p "$dest"
  local file
  for file in docker-compose.yml .env.exemplo install.sh README.md .gitignore; do
    if [[ -f "${SCRIPT_DIR}/${file}" ]]; then
      if [[ "${SCRIPT_DIR}/${file}" != "${dest}/${file}" ]]; then
        cp -a "${SCRIPT_DIR}/${file}" "${dest}/${file}"
      fi
    fi
  done
  chmod +x "${dest}/install.sh" 2>/dev/null || true
}

rand_hex() {
  openssl rand -hex "$1"
}

write_env() {
  local dest="$1"
  local version="$2"
  local port="$3"
  local bind="$4"
  local server_url="$5"
  local keep="${6:-n}"
  local env_path="${dest}/.env"
  local user="evolution"
  local db="evolution"
  local password key

  if [[ -f "$env_path" && "$keep" == "s" ]]; then
    log "A reutilizar ${env_path}"
    set_env_key "$env_path" "EVOLUTION_VERSION" "$version"
    set_env_key "$env_path" "EVOLUTION_PORT" "$port"
    set_env_key "$env_path" "EVOLUTION_BIND" "$bind"
    set_env_key "$env_path" "SERVER_URL" "$server_url"
    return
  fi

  password="$(rand_hex 16)"
  key="$(rand_hex 32)"
  if [[ -f "$env_path" ]]; then
    cp -a "$env_path" "${env_path}.bak.$(date +%Y%m%d%H%M%S)"
  fi

  cat > "$env_path" <<EOF
EVOLUTION_VERSION=${version}
EVOLUTION_PORT=${port}
EVOLUTION_BIND=${bind}
TZ=Europe/Lisbon
LANGUAGE=pt-BR

SERVER_URL=${server_url}

POSTGRES_USER=${user}
POSTGRES_PASSWORD=${password}
POSTGRES_DB=${db}

AUTHENTICATION_API_KEY=${key}
AUTHENTICATION_EXPOSE_IN_FETCH_INSTANCES=true

DATABASE_ENABLED=true
DATABASE_PROVIDER=postgresql
DATABASE_CONNECTION_URI=postgresql://${user}:${password}@postgres:5432/${db}?schema=public
DATABASE_CONNECTION_CLIENT_NAME=evolution
DATABASE_SAVE_DATA_INSTANCE=true
DATABASE_SAVE_DATA_NEW_MESSAGE=true
DATABASE_SAVE_MESSAGE_UPDATE=true
DATABASE_SAVE_DATA_CONTACTS=true
DATABASE_SAVE_DATA_CHATS=true
DATABASE_SAVE_DATA_LABELS=true
DATABASE_SAVE_DATA_HISTORIC=true

CACHE_REDIS_ENABLED=true
CACHE_REDIS_URI=redis://redis:6379/6
CACHE_REDIS_PREFIX_KEY=evolution
CACHE_REDIS_SAVE_INSTANCES=false
CACHE_LOCAL_ENABLED=false

QRCODE_LIMIT=30
DEL_INSTANCE=false
EOF
  chmod 600 "$env_path"
  log "Ficheiro .env criado em ${env_path}"
}

set_env_key() {
  local file="$1" key="$2" value="$3"
  if grep -qE "^${key}=" "$file"; then
    sed -i "s|^${key}=.*|${key}=${value}|" "$file"
  else
    printf '%s=%s\n' "$key" "$value" >> "$file"
  fi
}

read_env_key() {
  local file="$1" key="$2"
  grep -E "^${key}=" "$file" | tail -n1 | cut -d= -f2-
}

enable_apache_proxy() {
  a2enmod proxy proxy_http proxy_wstunnel rewrite headers ssl >/dev/null
}

write_apache_vhost() {
  local domain="$1" port="$2" use_ssl_proto="$3"
  local conf="/etc/apache2/sites-available/evolution-api.conf"
  local proto="http"
  [[ "$use_ssl_proto" == "s" ]] && proto="https"

  cat > "$conf" <<EOF
<VirtualHost *:80>
    ServerName ${domain}
    ProxyPreserveHost On
    ProxyRequests Off
    RequestHeader set X-Forwarded-Proto "${proto}"
    RequestHeader set X-Forwarded-Port "%{SERVER_PORT}s"
    RewriteEngine On
    RewriteCond %{HTTP:Upgrade} =websocket [NC]
    RewriteRule /(.*) ws://127.0.0.1:${port}/\$1 [P,L]
    ProxyPass / http://127.0.0.1:${port}/ upgrade=websocket timeout=3600
    ProxyPassReverse / http://127.0.0.1:${port}/
    ErrorLog \${APACHE_LOG_DIR}/evolution-api-error.log
    CustomLog \${APACHE_LOG_DIR}/evolution-api-access.log combined
</VirtualHost>
EOF
  a2ensite evolution-api.conf >/dev/null
  apache2ctl configtest
  systemctl reload apache2
  log "Vhost Apache criado: ${conf}"
}

maybe_certbot() {
  local domain="$1"
  if ! command -v certbot >/dev/null 2>&1; then
    warn "certbot não está instalado; o domínio ficou só em HTTP"
    return
  fi
  local do_cert="${EVOLUTION_CERTBOT:-}"
  if [[ -z "$do_cert" ]]; then
    ask_yes_no do_cert "Instalar certificado Let's Encrypt para ${domain}?" "n"
  fi
  if [[ "$do_cert" != "s" ]]; then
    return
  fi
  certbot --apache -d "$domain" --non-interactive --agree-tos --register-unsafely-without-email --redirect
}

start_stack() {
  local dest="$1"
  (
    cd "$dest"
    # Evita que EVOLUTION_PORT=auto (ou outros) no ambiente do shell
    # sobreponham o .env do Compose.
    export EVOLUTION_VERSION="$version"
    export EVOLUTION_PORT="$port"
    export EVOLUTION_BIND="$bind"
    log "A obter imagens (pull)…"
    docker compose pull
    log "A subir os contentores…"
    docker compose up -d
    docker compose ps
  )
}

wait_api() {
  local bind="$1" port="$2"
  local host="127.0.0.1"
  [[ "$bind" == "0.0.0.0" || "$bind" == "127.0.0.1" ]] || host="$bind"
  local url="http://${host}:${port}"
  local i code status
  log "A aguardar a API em ${url}…"
  for i in $(seq 1 90); do
    code="$(curl -sS -o /dev/null -w '%{http_code}' --max-time 3 "${url}/" 2>/dev/null || true)"
    if [[ "$code" =~ ^[1-5][0-9][0-9]$ ]]; then
      log "API a responder (HTTP ${code})"
      return 0
    fi
    status="$(docker inspect -f '{{.State.Status}}' evolution_api 2>/dev/null || true)"
    if [[ "$status" == "restarting" && "$i" -ge 8 ]]; then
      warn "O contentor da API está a reiniciar. Últimos logs:"
      docker logs evolution_api --tail 40 2>&1 || true
      return 1
    fi
    sleep 2
  done
  warn "A API ainda não respondeu no tempo esperado. Vê os logs: docker compose -f ${INSTALL_DIR}/docker-compose.yml logs -f api"
  docker logs evolution_api --tail 40 2>&1 || true
  return 1
}

print_summary() {
  local dest="$1" server_url="$2" port="$3" ip="$4" ready="${5:-0}"
  local key title
  key="$(read_env_key "${dest}/.env" AUTHENTICATION_API_KEY)"
  if [[ "$ready" == "1" ]]; then
    title="----- Evolution API pronta -----"
  else
    title="----- Instalação concluída com avisos -----"
  fi
  printf "\n${CYAN}%s${NC}\n" "$title"
  printf "Pasta:     %s\n" "$dest"
  printf "Versão:    %s\n" "$(read_env_key "${dest}/.env" EVOLUTION_VERSION)"
  printf "API:       %s\n" "$server_url"
  printf "Manager:   %s/manager\n" "$server_url"
  printf "Docs:      https://doc.evolution-api.com\n"
  printf "Local:     http://%s:%s\n" "$ip" "$port"
  printf "API key:   %s\n" "$key"
  printf "Header:    apikey: %s\n" "$key"
  printf "\nLogs:      cd %s && docker compose logs -f api\n" "$dest"
  printf "Parar:     cd %s && docker compose down\n" "$dest"
  printf "Actualizar: cd %s && sudo ./install.sh\n\n" "$dest"
}

main() {
  need_root
  printf "${CYAN}Instalador Evolution API${NC}\n\n"

  if [[ "${EVOLUTION_PORT:-}" == "auto" ]]; then
    unset EVOLUTION_PORT
  fi

  ensure_docker

  local install_dir version port bind domain use_https use_apache keep_env
  local ip server_url

  install_dir="${EVOLUTION_INSTALL_DIR:-}"
  if [[ -z "$install_dir" ]]; then
    resolve_install_dir install_dir
  fi
  install_dir="${install_dir%/}"
  [[ -n "$install_dir" ]] || die "Pasta inválida"
  if [[ "$install_dir" != /* ]]; then
    install_dir="$(pwd)/${install_dir}"
  fi
  INSTALL_DIR="$install_dir"
  log "Pasta de instalação: ${install_dir}"

  copy_project_files "$install_dir"

  local existing_version existing_port
  existing_version=""
  existing_port=""
  if [[ -f "${install_dir}/.env" ]]; then
    existing_version="$(read_env_key "${install_dir}/.env" EVOLUTION_VERSION || true)"
    existing_port="$(read_env_key "${install_dir}/.env" EVOLUTION_PORT || true)"
  fi

  list_versions || true
  version="${EVOLUTION_VERSION:-}"
  if [[ -z "$version" ]]; then
    ask version "Versão da Evolution (latest = última disponível)" "${existing_version:-$DEFAULT_VERSION}"
  fi
  version="${version:-$DEFAULT_VERSION}"
  [[ "$version" == latest || "$version" =~ ^v?[0-9] ]] || warn "Tag incomum: ${version}"

  local suggested_port
  if [[ -n "$existing_port" ]]; then
    suggested_port="$existing_port"
  else
    suggested_port="$(find_free_port)"
  fi
  port="${EVOLUTION_PORT:-}"
  if [[ -z "$port" ]]; then
    ask port "Porta HTTP do host" "$suggested_port"
  elif [[ "$port" == "auto" ]]; then
    port="$suggested_port"
  fi
  [[ "$port" =~ ^[0-9]+$ ]] || die "Porta inválida: ${port}"
  if port_in_use "$port" && ! port_held_by_stack "$port"; then
    die "A porta ${port} já está em uso"
  fi

  domain="${EVOLUTION_DOMAIN-}"
  if ! is_noninteractive && [[ -z "${EVOLUTION_DOMAIN+x}" ]]; then
    ask domain "Domínio (Enter = aceder por IP e porta)" ""
  fi
  domain="${domain#http://}"
  domain="${domain#https://}"
  domain="${domain%/}"

  ip="$(public_ip)"
  bind="0.0.0.0"
  use_https="n"
  use_apache="n"

  if [[ -n "$domain" ]]; then
    use_https="${EVOLUTION_HTTPS:-}"
    if [[ -z "$use_https" ]]; then
      ask_yes_no use_https "Usar HTTPS na SERVER_URL (${domain})?" "s"
    fi
    if command -v apache2 >/dev/null 2>&1 || command -v apachectl >/dev/null 2>&1; then
      use_apache="${EVOLUTION_APACHE:-}"
      if [[ -z "$use_apache" ]]; then
        ask_yes_no use_apache "Criar vhost Apache (reverse proxy) para ${domain}?" "s"
      fi
    else
      warn "Apache não encontrado; o domínio fica só na SERVER_URL"
    fi
    if [[ "$use_apache" == "s" ]]; then
      bind="127.0.0.1"
    fi
    if [[ "$use_https" == "s" ]]; then
      server_url="https://${domain}"
    else
      server_url="http://${domain}"
    fi
  else
    server_url="http://${ip}:${port}"
  fi

  keep_env="n"
  if [[ -f "${install_dir}/.env" ]]; then
    keep_env="${EVOLUTION_KEEP_ENV:-}"
    if [[ -z "$keep_env" ]]; then
      ask_yes_no keep_env "Já existe .env. Reutilizar credenciais e só actualizar versão/porta/URL?" "s"
    fi
  fi

  write_env "$install_dir" "$version" "$port" "$bind" "$server_url" "$keep_env"
  maybe_reset_volumes "$install_dir" "$keep_env"
  start_stack "$install_dir"

  if [[ "$use_apache" == "s" && -n "$domain" ]]; then
    enable_apache_proxy
    write_apache_vhost "$domain" "$port" "$use_https"
    if [[ "$use_https" == "s" ]]; then
      maybe_certbot "$domain"
    fi
  fi

  local ready="0"
  if wait_api "$bind" "$port"; then
    ready="1"
  fi
  print_summary "$install_dir" "$server_url" "$port" "$ip" "$ready"
}

main "$@"
