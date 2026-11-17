#!/usr/bin/env bash
# Cria os topicos do FIAP X em um cluster Kafka existente.
# Uso: KAFKA_BOOTSTRAP_SERVERS=localhost:9094 ./create-topics.sh
set -euo pipefail

BOOTSTRAP="${KAFKA_BOOTSTRAP_SERVERS:-localhost:9094}"
PARTITIONS="${KAFKA_PARTITIONS:-3}"
REPLICATION="${KAFKA_REPLICATION:-1}"

for topico in fiapx.video.solicitado fiapx.video.processado fiapx.video.falha; do
  docker run --rm --network host apache/kafka:3.9.1 \
    /opt/kafka/bin/kafka-topics.sh \
    --bootstrap-server "$BOOTSTRAP" \
    --create --if-not-exists \
    --topic "$topico" \
    --partitions "$PARTITIONS" \
    --replication-factor "$REPLICATION"
done

docker run --rm --network host apache/kafka:3.9.1 \
  /opt/kafka/bin/kafka-topics.sh --bootstrap-server "$BOOTSTRAP" --list
