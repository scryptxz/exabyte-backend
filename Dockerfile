# ---------- Etapa 1: compilação ----------
# Mesma versão do GHC do snapshot lts-24.67 (stack.yaml), então o Stack usa o
# GHC da imagem em vez de baixar outro.
FROM haskell:9.10.3-bookworm AS build

RUN apt-get update \
 && apt-get install -y --no-install-recommends libpq-dev pkg-config \
 && rm -rf /var/lib/apt/lists/*

WORKDIR /app

# Dependências primeiro: esta camada fica em cache enquanto o stack.yaml e o
# package.yaml não mudarem, e só o código do projeto é recompilado.
# -j1 reduz o pico de memória (compilar Yesod consome bastante RAM).
COPY stack.yaml stack.yaml.lock package.yaml ./
COPY config ./config
RUN stack build --system-ghc --only-dependencies -j1

COPY . .
RUN stack build --system-ghc -j1 --copy-bins --local-bin-path /app/bin

# ---------- Etapa 2: imagem final (só o executável) ----------
FROM debian:bookworm-slim

# libpq5: cliente do PostgreSQL | ca-certificates: HTTPS do ViaCEP
RUN apt-get update \
 && apt-get install -y --no-install-recommends libpq5 ca-certificates libgmp10 netbase \
 && rm -rf /var/lib/apt/lists/*

COPY --from=build /app/bin/exabyte-api /usr/local/bin/exabyte-api

# O servidor lê PORT e DATABASE_URL do ambiente (padrão: porta 3000).
ENV PORT=3000
EXPOSE 3000
CMD ["exabyte-api"]
