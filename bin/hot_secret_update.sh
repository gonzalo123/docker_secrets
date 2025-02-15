#!/bin/bash

RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'

if [ "$#" -ne 2 ]; then
  echo "Usage: $0 <SECRET_NAME> <NEW_PASSWORD>"
  exit 1
fi

SECRET_NAME=$1
NEW_PASSWORD=$2

TEMP_SECRET_NAME="$SECRET_NAME.tmp"

if ! docker secret ls --format "{{.Name}}" | grep -qw "$SECRET_NAME"; then
  echo "${RED}[ERROR]${NC} Secret '$SECRET_NAME' does not exist."
  echo "${GREEN}[INFO]${NC} Available secrets in the cluster:"
  docker secret ls --format "table {{.ID}}\t{{.Name}}\t{{.CreatedAt}}"
  exit 1
fi

echo "${GREEN}[INFO]${NC} Creating new temporal secret '$TEMP_SECRET_NAME'..."
echo "$NEW_PASSWORD" | docker secret create "$TEMP_SECRET_NAME" -

echo "${GREEN}[INFO]${NC} Looking for services using secret: '$SECRET_NAME'..."
SERVICES=$(docker service ls --format "{{.Name}}" | while read -r service; do
  if docker service inspect "$service" | jq -e ".[].Spec.TaskTemplate.ContainerSpec.Secrets | map(select(.SecretName == \"$SECRET_NAME\")) | length > 0" >/dev/null; then
    echo "$service"
  fi
done)

echo "${GREEN}[INFO]${NC} Updating services to use the new secret and remove the old one..."
for service in $SERVICES; do
  docker service update --secret-add "$TEMP_SECRET_NAME" --secret-rm "$SECRET_NAME" "$service"
done

echo "${GREEN}[INFO]${NC} Removing the old secret..."
docker secret rm "$SECRET_NAME"
echo "$NEW_PASSWORD" | docker secret create "$SECRET_NAME" -

echo "${GREEN}[INFO]${NC} Renaming the new secret..."
for service in $SERVICES; do
  docker service update --secret-add "$SECRET_NAME" --secret-rm "$TEMP_SECRET_NAME" "$service"
done

echo "${GREEN}[INFO]${NC} Removing the temporary secret..."
docker secret rm "$TEMP_SECRET_NAME"

echo "${GREEN}[INFO]${NC} Secret '$SECRET_NAME' updated successfully."