#!/bin/bash

RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'

if [ -z "$1" ]; then
  echo "${RED}[ERROR]${NC} You must provide the secret name as a parameter."
  echo "Usage: $0 <SECRET_NAME>"
  exit 1
fi

SECRET_NAME="$1"

echo "${GREEN}[INFO]${NC} Looking for services using secret: '$SECRET_NAME'..."
SERVICES=$(docker service ls --format "{{.Name}}" | while read -r service; do
  if docker service inspect "$service" | jq -e ".[].Spec.TaskTemplate.ContainerSpec.Secrets | map(select(.SecretName == \"$SECRET_NAME\")) | length > 0" >/dev/null; then
    echo "$service"
  fi
done)

if [ -z "$SERVICES" ]; then
  echo "${GREEN}[INFO]${NC} No services using secret: '$SECRET_NAME'."
  exit 0
fi

echo "${GREEN}[INFO]${NC} Containers using secret: '$SECRET_NAME':"
for service in $SERVICES; do
  docker ps --filter "name=${service}" --format "Container {{.ID}} ({{.Names}}) uses the service '$service'"
done
