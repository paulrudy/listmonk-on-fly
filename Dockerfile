FROM listmonk/listmonk:latest
ARG PORT ADMIN_USERNAME ADMIN_PASSWORD POSTGRES_HOST POSTGRES_PORT POSTGRES_USER POSTGRES_PASSWORD POSTGRES_DATABASE
ENV LISTMONK_APP__ADDRESS="0.0.0.0:9000" \
  LISTMONK_APP__ADMIN_USERNAME="${ADMIN_USERNAME}" \
  LISTMONK_APP__ADMIN_PASSWORD="${ADMIN_PASSWORD}" \
  LISTMONK_DB__HOST="${POSTGRES_HOST}" \
  LISTMONK_DB__PORT=${POSTGRES_PORT} \
  LISTMONK_DB__USER="${POSTGRES_USER}" \
  LISTMONK_DB__PASSWORD="${POSTGRES_PASSWORD}" \
  LISTMONK_DB__DATABASE="${POSTGRES_DATABASE}" \
  LISTMONK_DB__SSL_MODE="disable" \
  LISTMONK_DB__MAX_OPEN=25 \
  LISTMONK_DB__MAX_IDLE=25 \
  LISTMONK_DB__MAX_LIFETIME="300s"
COPY static/ /tmp/static/
CMD \
  rm -rf /data/listmonk/static; \
  mkdir -p /data/listmonk; \
  cp -r /tmp/static /data/listmonk; \
  ./listmonk --install --idempotent --yes > server.log 2>&1 && \
  ./listmonk --upgrade --yes > server.log 2>&1 &&\
  ./listmonk --static-dir=/data/listmonk/static > server.log 2>&1
