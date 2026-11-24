#!/usr/bin/env bash
# Coleta as saídas de terminal usadas como evidência em docs/evidencias/
set -u
C=sdl-servico
URL="http://localhost:${HOST_PORT:-8080}"
OUT="$(dirname "$0")/../docs/evidencias"
mkdir -p "$OUT"
run() { echo "\$ $*"; eval "$*"; echo; }

{ run docker compose ps; run docker ps; run docker ps -a; run "curl -s $URL/"; run "curl -s $URL/health"; } > "$OUT/01-servico-funcionando.txt" 2>&1
{ run "docker inspect -f 'User={{.Config.User}} Privileged={{.HostConfig.Privileged}} ReadOnlyRootfs={{.HostConfig.ReadonlyRootfs}} CapDrop={{.HostConfig.CapDrop}}' $C"
  run "docker exec $C id"; run "docker top $C -o user,pid,ppid,args"
  run "docker exec $C env | grep -E 'APP_|LOG_LEVEL|ENABLE_'"; } > "$OUT/02-usuario-e-configuracao.txt" 2>&1
{ run "docker inspect -f 'MemoryBytes={{.HostConfig.Memory}} NanoCpus={{.HostConfig.NanoCpus}} PidsLimit={{.HostConfig.PidsLimit}}' $C"
  run "docker stats --no-stream $C"; } > "$OUT/03-limites.txt" 2>&1
{ run "docker logs --tail 20 $C"; } > "$OUT/04-logs.txt" 2>&1
{ run "docker inspect -f 'ANTES: status={{.State.Status}} restarts={{.RestartCount}} started={{.State.StartedAt}}' $C"
  run "curl -s $URL/fail"; sleep 6
  run "docker inspect -f 'DEPOIS: status={{.State.Status}} restarts={{.RestartCount}} started={{.State.StartedAt}}' $C"
  run "docker logs --tail 15 $C"; run "curl -s $URL/"; } > "$OUT/05-falha-e-recuperacao.txt" 2>&1
echo "Evidências salvas em $OUT"
