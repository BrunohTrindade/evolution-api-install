# Evolution API — instalador Docker

Projecto reutilizável para instalar a [Evolution API](https://github.com/evolution-foundation/evolution-api) com PostgreSQL e Redis via Docker Compose.

Baseado na stack da [RosnerTech](https://github.com/RosnerTech/evolution-api), com imagem oficial `evoapicloud/evolution-api`, versão configurável e script de instalação.

## Pré-requisitos

- Ubuntu (testado em 24.04)
- Root (`sudo`)
- O script instala Docker Engine e o plugin Compose se ainda não existirem

## Instalação

```bash
git clone https://github.com/BrunohTrindade/evolution-api-install.git
cd evolution-api-install
sudo ./install.sh
```

O instalador pergunta:

1. Pasta (default `/opt/evolution-api`; aceita `/var/www/evolution-api` ou outro caminho)
2. Versão da Evolution (`latest` = última no Docker Hub, ou uma tag como `v2.3.7`)
3. Porta HTTP (primeira livre a partir de `8080`)
4. Domínio (opcional). Enter = `http://IP:porta`. Com domínio, podes criar vhost Apache e Let's Encrypt

Não-interativo:

```bash
sudo EVOLUTION_NONINTERACTIVE=1 \
  EVOLUTION_INSTALL_DIR=/opt/evolution-api \
  EVOLUTION_VERSION=latest \
  EVOLUTION_DOMAIN= \
  ./install.sh
```

Variáveis úteis: `EVOLUTION_PORT`, `EVOLUTION_HTTPS=s|n`, `EVOLUTION_APACHE=s|n`, `EVOLUTION_CERTBOT=s|n`, `EVOLUTION_KEEP_ENV=s|n`.

## Depois de instalar

- API: o URL indicado no final do script
- Manager: `/manager`
- Documentação: https://doc.evolution-api.com
- Autenticação: cabeçalho `apikey: <AUTHENTICATION_API_KEY>`

```bash
cd /opt/evolution-api
docker compose ps
docker compose logs -f api
```

Actualizar para a última imagem (se a versão for `latest`):

```bash
cd /opt/evolution-api
sudo ./install.sh
```

(responde que queres reutilizar o `.env`)

## Ficheiros

- `install.sh` — instalação / actualização
- `docker-compose.yml` — API, PostgreSQL 15, Redis 7
- `.env.exemplo` — modelo (nunca uses em produção sem alterar)
- `.env` — gerado no destino, **não** vai para o Git

Postgres e Redis não são publicados na rede; só a API fica acessível.

O `.env` está no `.gitignore` e não vai para o Git.
