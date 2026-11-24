#!/usr/bin/env bash
# Roteiro da apresentação (24/11/2026). Rode com: bash scripts/demo.sh
set -u
C=sdl-servico; URL="http://localhost:${HOST_PORT:-8080}"
pausa() { read -r -p $'\n[ENTER para continuar] ' _; }
echo "== 1. Inicia e testa =="; docker compose up --build -d; sleep 3
docker ps; curl -s "$URL/"; echo; docker exec $C id; pausa
echo "== 2. Falha controlada (container precisa ter >= 10 s no ar) =="
sleep 10
docker inspect -f 'ANTES: restarts={{.RestartCount}} started={{.State.StartedAt}}' $C
curl -s "$URL/fail"; echo; sleep 5; pausa
echo "== 3. Recuperação =="
docker inspect -f 'DEPOIS: status={{.State.Status}} restarts={{.RestartCount}} started={{.State.StartedAt}}' $C
docker logs --tail 12 $C; curl -s "$URL/"; echo; pausa
echo "== Parada normal =="; docker stop $C; docker ps -a --filter name=$C
