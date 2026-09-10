# Evolution API — instalador. FACIL DEMAIS

Instala a [Evolution API](https://github.com/evolution-foundation/evolution-api) no Ubuntu com Docker: API + PostgreSQL + Redis.

## Instalar

```bash
git clone https://github.com/BrunohTrindade/evolution-api-install.git
cd evolution-api-install
sudo ./install.sh
```

Instalação para Ubuntu. Se o Docker não existir, fique tranquilo, o script instala.

O instalador pergunta:

1. **Pasta** — `1` = `/opt/evolution-api` (recomendado), `2` = `/var/www/evolution-api`, `3` = outro caminho
2. **Versão** — `latest` ou uma tag (`v2.3.7`)
3. **Porta** — primeira livre a partir de `8080`
4. **Domínio** — Enter = acede por `http://IP:porta`. Com domínio, podes activar Apache + HTTPS (Let's Encrypt)

No fim aparece o URL, o Manager (`/manager`) e a API key (`apikey`).

## Usar

```bash
cd /opt/evolution-api
docker compose ps
docker compose logs -f api
```

- Documentação: https://doc.evolution-api.com
- Só a API fica na rede. Postgres e Redis ficam internos.

## Actualizar

```bash
cd /opt/evolution-api
sudo ./install.sh
```

Responde **S** para reutilizar o `.env` (mantém a API key e as senhas).

## Sem perguntas

```bash
sudo EVOLUTION_NONINTERACTIVE=1 \
  EVOLUTION_INSTALL_DIR=/opt/evolution-api \
  EVOLUTION_VERSION=latest \
  EVOLUTION_DOMAIN= \
  ./install.sh
```

Opcionais: `EVOLUTION_PORT`, `EVOLUTION_HTTPS=s|n`, `EVOLUTION_APACHE=s|n`, `EVOLUTION_CERTBOT=s|n`, `EVOLUTION_KEEP_ENV=s|n`, `EVOLUTION_RESET_VOLUMES=s|n`.

## Ficheiros

| Ficheiro | Função |
|---|---|
| `install.sh` | Instala e actualiza |
| `docker-compose.yml` | API, Postgres 15, Redis 7 |
| `.env.exemplo` | Modelo |
| `.env` | Gerado na pasta de instalação — **não vai para o Git** |
