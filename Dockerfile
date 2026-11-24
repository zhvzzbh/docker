FROM python:3.12-slim

ENV PYTHONUNBUFFERED=1 \
    PYTHONDONTWRITEBYTECODE=1 \
    APP_PORT=8080 \
    LOG_LEVEL=INFO

# Usuário de sistema sem privilégios, sem home e sem shell de login (UID/GID 10001)
RUN groupadd --system --gid 10001 appgroup \
 && useradd  --system --uid 10001 --gid 10001 --no-create-home \
             --shell /usr/sbin/nologin appuser

WORKDIR /app
# Arquivo pertence ao root e é somente leitura para o appuser (menor privilégio)
COPY app/app.py /app/app.py
RUN chmod 0644 /app/app.py

USER 10001:10001

# Porta > 1024: não exige privilégio nem CAP_NET_BIND_SERVICE
EXPOSE 8080

HEALTHCHECK --interval=10s --timeout=3s --start-period=3s --retries=3 \
  CMD ["python", "/app/app.py", "--healthcheck"]

CMD ["python", "/app/app.py"]
