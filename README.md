# Trabalho 4 — Operacionalização segura de um serviço Linux com Docker

**Disciplina:** Sistemas Operacionais — Prof. Guibson Krause
**Curso:** Análise e Desenvolvimento de Sistemas — Faculdade Serra Dourada
**Integrantes:** Daniel Mendes da Fonseca Madeira · Ruberty Carlos

## 1. Visão geral

Serviço HTTP em Python (apenas biblioteca padrão, sem dependências externas) executado em um container Docker, com usuário sem privilégios, configuração por variáveis de ambiente, logs em `stdout`, reinício automático após falha e limites de CPU/memória.

| Rota | Função |
|---|---|
| `GET /` | Devolve JSON com mensagem, **UID/GID efetivos**, PID e uptime |
| `GET /health` | Verificação de saúde (usada pelo `HEALTHCHECK`) |
| `GET /fail` | **Modo de falha controlada**: sai com código 1 (só se `ENABLE_FAIL_ROUTE=true`) |

## 2. Pré-requisitos

- Docker Engine 24+ com plugin Docker Compose v2 (`docker compose version`)
- `curl` e `git`
- Porta 8080 livre no host (ou altere `HOST_PORT` no `.env`)
- Ambiente de laboratório autorizado (máquina própria, VM ou WSL2)

## 3. Estrutura do repositório

```
app/app.py            aplicação
Dockerfile            imagem (usuário 10001, sem root)
compose.yaml          execução (restart, limites, isolamento)
.env.example          modelo de configuração (o .env real NÃO vai ao Git)
scripts/demo.sh       roteiro da apresentação
scripts/evidencias.sh coleta as saídas de terminal em docs/evidencias/
docs/evidencias/      evidências (saídas + capturas de tela)
```

---

# RUNBOOK

## 4. Construir e configurar

```bash
git clone <URL-DO-REPOSITORIO> && cd trabalho4-docker
cp .env.example .env          # edite se quiser mudar porta, log ou mensagem
docker compose up --build -d  # constrói a imagem e inicia
```

**Alternativa com `docker run`** (equivalente ao compose):

```bash
docker build -t so-trabalho4:1.0 .
docker run -d --name sdl-servico \
  --env-file .env -p 8080:8080 \
  --restart on-failure:5 \
  --memory 128m --cpus 0.5 --pids-limit 100 \
  --read-only --tmpfs /tmp \
  --cap-drop ALL --security-opt no-new-privileges:true \
  so-trabalho4:1.0
```

### Configuração externa (sem editar código)

| Variável | Padrão | Efeito |
|---|---|---|
| `APP_PORT` | 8080 | porta dentro do container |
| `HOST_PORT` | 8080 | porta publicada no host |
| `LOG_LEVEL` | INFO | DEBUG / INFO / WARNING / ERROR |
| `APP_MESSAGE` | Olá do serviço… | texto da rota `/` |
| `ENABLE_FAIL_ROUTE` | false (`true` no `.env.example`) | habilita `/fail` |

Para alterar: edite `.env` e rode `docker compose up -d` (recria o container). Exemplo: `LOG_LEVEL=DEBUG`.
O `.env` está no `.gitignore`; no repositório existe somente `.env.example`, sem credenciais reais.

## 5. Iniciar, testar e verificar estado

```bash
curl -s http://localhost:8080/        # {"mensagem": ..., "uid": 10001, ...}
curl -s http://localhost:8080/health  # {"status": "ok"}
docker ps                             # container em execução (STATUS "healthy")
docker ps -a                          # inclui containers parados
docker compose ps
```

## 6. Verificar usuário e permissões

```bash
docker exec sdl-servico id                       # uid=10001(appuser) gid=10001(appgroup)
docker top sdl-servico -o user,pid,ppid,args     # processo roda como appuser
docker inspect -f 'User={{.Config.User}} Privileged={{.HostConfig.Privileged}} ReadOnly={{.HostConfig.ReadonlyRootfs}} CapDrop={{.HostConfig.CapDrop}}' sdl-servico
```

**Acessos necessários e por que são mínimos**

- **Arquivos:** `/app/app.py` pertence ao root, modo 0644: o `appuser` só **lê**; não consegue alterar o código.
- **Diretórios:** raiz do container montada somente leitura (`read_only: true`); apenas `/tmp` é gravável (tmpfs em memória).
- **Portas:** usa 8080 (> 1024), por isso não precisa de root nem de `CAP_NET_BIND_SERVICE`.
- **Privilégios:** `privileged: false`, `cap_drop: ALL`, `no-new-privileges`.
- **Isolamento:** o container tem namespaces próprios (PID, rede, mount); a única porta exposta ao host é a publicada.

## 7. Logs

```bash
docker logs sdl-servico            # tudo
docker logs -f --tail 20 sdl-servico   # seguir ao vivo
docker compose logs -f servico
```

Mensagens esperadas: `servico iniciado porta=8080 uid=10001 ...`, `requisicao metodo=GET caminho=/ ...`, `WARNING rota inexistente ...` (teste com `curl /xyz`), `ERROR MODO DE FALHA acionado ...`.

## 8. Limites de recursos

```bash
docker inspect -f 'MemoryBytes={{.HostConfig.Memory}} NanoCpus={{.HostConfig.NanoCpus}} PidsLimit={{.HostConfig.PidsLimit}}' sdl-servico
docker stats --no-stream sdl-servico
```

Aplicados: memória 128 MiB (`134217728`), 0,5 CPU (`500000000` nanoCPUs), máx. 100 processos.
> Observação: em Docker Desktop/WSL2 os limites valem para a VM do Docker; em hosts com cgroup v1 sem swap accounting, o aviso "Your kernel does not support swap limit" pode aparecer e não impede o limite de memória.

## 9. Simular falha e confirmar recuperação

Política: `restart: on-failure:5` — o Docker reinicia o container **somente** quando o processo principal sai com código ≠ 0 (até 5 tentativas). `docker stop` (código 0 / SIGTERM tratado) **não** dispara reinício.
Importante: a política só passa a valer depois que o container ficou **no ar por ao menos 10 segundos**.

```bash
# 1) aguarde >= 10 s após o início e registre o ANTES
docker inspect -f 'status={{.State.Status}} restarts={{.RestartCount}} started={{.State.StartedAt}}' sdl-servico
# 2) provoque a falha (processo principal sai com código 1)
curl -s http://localhost:8080/fail
sleep 5
# 3) registre o DEPOIS: restarts deve ter aumentado em 1 e started_at mudado
docker inspect -f 'status={{.State.Status}} restarts={{.RestartCount}} started={{.State.StartedAt}}' sdl-servico
docker logs --tail 15 sdl-servico   # mostra o ERROR da falha e a nova inicialização
curl -s http://localhost:8080/      # aplicação voltou (uptime_s baixo, pid novo)
```

## 10. Parada normal e limpeza

```bash
docker stop sdl-servico          # ou: docker compose stop
docker ps -a --filter name=sdl-servico    # STATUS: Exited (0)
docker compose down              # remove container e rede
docker image rm so-trabalho4:1.0 # opcional
```

## 11. Solução de problemas

| Sintoma | Causa provável / ação |
|---|---|
| `port is already allocated` | altere `HOST_PORT` no `.env` |
| `/fail` retorna 404 | `ENABLE_FAIL_ROUTE` não está `true` no `.env` (recrie com `docker compose up -d`) |
| Container não reinicia | falha foi antes de 10 s no ar, ou foi parado com `docker stop`, ou já esgotou as 5 tentativas |
| `RestartCount` não sobe após `docker compose up` | o contador zera quando o container é recriado |

## 12. Evidências

Veja `docs/evidencias/`. Gere as saídas com `bash scripts/evidencias.sh` (com o serviço no ar) e salve as capturas de tela em `docs/evidencias/capturas/`.

| Arquivo | Mostra |
|---|---|
| 01-servico-funcionando.txt | `docker ps`, `docker ps -a`, resposta da aplicação |
| 02-usuario-e-configuracao.txt | UID ≠ 0, `Privileged=false`, variáveis de ambiente |
| 03-limites.txt | limites de memória/CPU/PIDs e `docker stats` |
| 04-logs.txt | inicialização e requisições |
| 05-falha-e-recuperacao.txt | RestartCount e StartedAt antes/depois, logs, app respondendo |
