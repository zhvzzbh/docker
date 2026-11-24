"""Serviço HTTP mínimo para o Trabalho 4 (Sistemas Operacionais).

Configuração 100% por variáveis de ambiente (nada de credenciais no código):
  APP_PORT          porta de escuta dentro do container (padrão 8080)
  LOG_LEVEL         DEBUG | INFO | WARNING | ERROR (padrão INFO)
  APP_MESSAGE       mensagem devolvida na rota "/"
  ENABLE_FAIL_ROUTE "true" habilita GET /fail (falha controlada, só em laboratório)
"""
import json
import logging
import os
import signal
import sys
import threading
import time
import urllib.request
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

PORT = int(os.environ.get("APP_PORT", "8080"))
LOG_LEVEL = os.environ.get("LOG_LEVEL", "INFO").upper()
MESSAGE = os.environ.get("APP_MESSAGE", "Olá do serviço containerizado!")
ENABLE_FAIL = os.environ.get("ENABLE_FAIL_ROUTE", "false").lower() == "true"
STARTED = time.time()

logging.basicConfig(
    level=getattr(logging, LOG_LEVEL, logging.INFO),
    format="%(asctime)s %(levelname)s %(message)s",
    datefmt="%Y-%m-%dT%H:%M:%S%z",
    stream=sys.stdout,
)
log = logging.getLogger("servico")


class Handler(BaseHTTPRequestHandler):
    server_version = "ServicoSO/1.0"

    def _json(self, code, body):
        data = json.dumps(body, ensure_ascii=False).encode()
        self.send_response(code)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def do_GET(self):
        log.info("requisicao metodo=GET caminho=%s origem=%s", self.path, self.client_address[0])
        if self.path == "/":
            self._json(200, {
                "mensagem": MESSAGE,
                "uid": os.getuid(),
                "gid": os.getgid(),
                "pid": os.getpid(),
                "uptime_s": round(time.time() - STARTED, 1),
            })
        elif self.path == "/health":
            self._json(200, {"status": "ok"})
        elif self.path == "/fail" and ENABLE_FAIL:
            log.error("MODO DE FALHA acionado: encerrando o processo principal com codigo 1")
            self._json(200, {"status": "falhando", "codigo_saida": 1})
            threading.Timer(0.3, lambda: os._exit(1)).start()
        else:
            log.warning("rota inexistente caminho=%s", self.path)
            self._json(404, {"erro": "rota nao encontrada"})

    def log_message(self, fmt, *args):  # silencia o log padrão; usamos o logging
        pass


def healthcheck():
    try:
        urllib.request.urlopen(f"http://127.0.0.1:{PORT}/health", timeout=2)
        sys.exit(0)
    except Exception:
        sys.exit(1)


def main():
    if "--healthcheck" in sys.argv:
        healthcheck()
    server = ThreadingHTTPServer(("0.0.0.0", PORT), Handler)

    def on_term(signum, _frame):
        log.info("sinal %s recebido: parada normal", signal.Signals(signum).name)
        threading.Thread(target=server.shutdown).start()

    # PID 1 em container não tem tratamento padrão de sinais: tratamos explicitamente.
    signal.signal(signal.SIGTERM, on_term)
    signal.signal(signal.SIGINT, on_term)

    log.info("servico iniciado porta=%d uid=%d pid=%d log_level=%s fail_route=%s",
             PORT, os.getuid(), os.getpid(), LOG_LEVEL, ENABLE_FAIL)
    server.serve_forever()
    server.server_close()
    log.info("servico encerrado com codigo 0")


if __name__ == "__main__":
    main()
