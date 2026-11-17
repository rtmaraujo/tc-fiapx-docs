#!/usr/bin/env bash
# Smoke test do FIAP X: cadastro, login, upload, polling e download do ZIP.
# Requisitos: curl, unzip. Uso: ./scripts/smoke-test.sh [arquivo-de-video]
set -euo pipefail

AUTH_URL="${AUTH_URL:-http://localhost:8081}"
VIDEO_URL="${VIDEO_URL:-http://localhost:8082}"
EMAIL="${EMAIL:-smoke.$(date +%s)@fiapx.com}"
SENHA="${SENHA:-senha1234}"
NOME="${NOME:-Smoke Test}"
VIDEO="${1:-video.mp4}"
TENTATIVAS="${TENTATIVAS:-60}"
INTERVALO="${INTERVALO:-3}"

if [[ ! -f "$VIDEO" ]]; then
  echo "arquivo de video nao encontrado: $VIDEO" >&2
  exit 1
fi

echo "==> registrando $EMAIL"
curl -sS -o /dev/null -w 'register: %{http_code}\n' \
  -X POST "$AUTH_URL/api/auth/register" \
  -H 'Content-Type: application/json' \
  -d "{\"nome\":\"$NOME\",\"email\":\"$EMAIL\",\"senha\":\"$SENHA\"}"

echo "==> autenticando"
LOGIN=$(curl -sS -X POST "$AUTH_URL/api/auth/login" \
  -H 'Content-Type: application/json' \
  -d "{\"email\":\"$EMAIL\",\"senha\":\"$SENHA\"}")
TOKEN=$(printf '%s' "$LOGIN" | sed -n 's/.*"accessToken":"\([^"]*\)".*/\1/p')
if [[ -z "$TOKEN" ]]; then
  echo "falha no login: $LOGIN" >&2
  exit 1
fi

echo "==> enviando $VIDEO"
UPLOAD=$(curl -sS -X POST "$VIDEO_URL/api/videos" \
  -H "Authorization: Bearer $TOKEN" \
  -F "arquivo=@$VIDEO")
VIDEO_ID=$(printf '%s' "$UPLOAD" | sed -n 's/.*"id":"\([^"]*\)".*/\1/p')
if [[ -z "$VIDEO_ID" ]]; then
  echo "falha no upload: $UPLOAD" >&2
  exit 1
fi
echo "videoId=$VIDEO_ID"

echo "==> aguardando processamento"
STATUS=""
for ((i = 1; i <= TENTATIVAS; i++)); do
  BODY=$(curl -sS "$VIDEO_URL/api/videos/$VIDEO_ID" -H "Authorization: Bearer $TOKEN")
  STATUS=$(printf '%s' "$BODY" | sed -n 's/.*"status":"\([A-Z]*\)".*/\1/p')
  echo "  tentativa $i: $STATUS"
  case "$STATUS" in
    CONCLUIDO) break ;;
    ERRO)
      echo "processamento falhou: $BODY" >&2
      exit 1
      ;;
  esac
  sleep "$INTERVALO"
done

if [[ "$STATUS" != "CONCLUIDO" ]]; then
  echo "timeout aguardando o processamento (ultimo status: $STATUS)" >&2
  exit 1
fi

echo "==> baixando ZIP"
ZIP="frames-$VIDEO_ID.zip"
curl -sS -f -o "$ZIP" "$VIDEO_URL/api/videos/$VIDEO_ID/download" -H "Authorization: Bearer $TOKEN"

FRAMES=$(unzip -l "$ZIP" | grep -c 'frame_' || true)
echo "frames no ZIP: $FRAMES"
if [[ "$FRAMES" -lt 1 ]]; then
  echo "ZIP sem frames" >&2
  exit 1
fi

echo "OK: fluxo completo validado (video $VIDEO_ID, $FRAMES frames)"
