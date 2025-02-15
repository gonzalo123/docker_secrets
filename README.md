## Hot-reload for Docker secrets in Docker Swarm

The best way to store passwords in a Docker Swarm cluster, apart from proprietary solutions from cloud providers, is the
use of Docker secrets. Docker secrets are a way to securely store sensitive information, such as passwords, API keys,
and authentication tokens, in Docker Swarm. Docker secrets are encrypted, and can only be accessed at runtime by the
services that need them. Docker mounts the secrets as files in the container's filesystem, allowing applications to read
them as if they were regular files. The only problem of Docker secrets is that they cannot be updated once created, so
if we need to change a password, for example, we must create a new secret and update the services that use it. There are
techniques to do this, but we need to update our docker-compose files. Today we will see how to do it without modifying
the docker-compose files and, although some service restarts are necessary, with minimal downtime.

We will start with an example project. It is a Flask API that displays the secret, in this case, the password of a
database, on the screen. The idea is not to expose our password, of course. We only do this to be able to access our
service and see that the password is updated correctly. The API code is as follows:

```python
from flask import Flask

from settings import DB_PASSWORD

app = Flask(__name__)


@app.get("/")
def home():
    return dict(SECRET=DB_PASSWORD)
```

Our service is deployed as follows:

```yaml
version: '3.9'

services:
  ap1:
    image: api_secret:latest
    command: gunicorn -w 1 app:app -b 0.0.0.0:5000 --timeout 180
    secrets:
      - db_password
    ports:
      - "5000:5000"

secrets:
  db_password:
    external: true
```

As we can see, the `db_password` secret is mounted in the `ap1` service container. To deploy our service, we first
create the secret and then deploy the service:

```shell
echo "old password" | docker secret create db_password -
docker build -t api_secret .

docker stack deploy -c docker-compose.yml service1
```

Now we want to update the secret, but without touching the docker-compose and without redeploying. The idea is to create
a temporary secret with the new password, update the service to use the new secret, and then delete the old secret. That
means that our service will have a secret or a temporary secret, but never both at the same time. If there's a temporary
secret, the service will use it. If there's no temporary secret, the service will use the regular secret. That's the
python code to do that:

```python
from get_docker_secret import get_docker_secret


def get_secret(key, default=None):
    return get_docker_secret(
        name=f"{key}.tmp",
        default=get_docker_secret(name=key, default=default)
    )
```

In broad terms, what we do is the following:

```shell
# Create the new secret
echo "new password" | docker secret create db_password.tmp -

# Update the service to use the new secret
docker service update --secret-add db_password.tmp --secret-rm db_password service1_ap1

# Remove the old secret that is no longer used
docker secret rm db_password

# Create the secret again with the new password
echo "new password" | docker secret create db_password -

# Update the service to use the new secret
docker service update --secret-add db_password --secret-rm db_password.tmp service1_ap1

# Remove the temporary secret
docker secret rm db_password.tmp
```

And that's it. It is clear that every time we update a secret, the service restarts, so there will be some downtime. But
it is minimal downtime.

I have created a small bash script that automates what we have discussed.

```shell
#!/bin/bash

if [ "$#" -ne 2 ]; then
  echo "Usage: $0 <SECRET_NAME> <NEW_PASSWORD>"
  exit 1
fi

SECRET_NAME=$1
NEW_PASSWORD=$2

TEMP_SECRET_NAME="$SECRET_NAME.tmp"

if ! docker secret ls --format "{{.Name}}" | grep -qw "$SECRET_NAME"; then
  echo "[ERROR] Secret '$SECRET_NAME' does not exist."
  echo "[INFO] Available secrets in the cluster:"
  docker secret ls --format "table {{.ID}}\t{{.Name}}\t{{.CreatedAt}}"
  exit 1
fi

echo "[INFO] Creating new temporal secret '$TEMP_SECRET_NAME'..."
echo "$NEW_PASSWORD" | docker secret create "$TEMP_SECRET_NAME" -

echo "[INFO] Looking for services using secret: '$SECRET_NAME'..."
SERVICES=$(docker service ls --format "{{.Name}}" | while read -r service; do
  if docker service inspect "$service" | jq -e ".[].Spec.TaskTemplate.ContainerSpec.Secrets | map(select(.SecretName == \"$SECRET_NAME\")) | length > 0" >/dev/null; then
    echo "$service"
  fi
done)

echo "[INFO] Updating services to use the new secret and remove the old one..."
for service in $SERVICES; do
  docker service update --secret-add "$TEMP_SECRET_NAME" --secret-rm "$SECRET_NAME" "$service"
done

echo "[INFO] Removing the old secret..."
docker secret rm "$SECRET_NAME"
echo "$NEW_PASSWORD" | docker secret create "$SECRET_NAME" -

echo "[INFO] Renaming the new secret..."
for service in $SERVICES; do
  docker service update --secret-add "$SECRET_NAME" --secret-rm "$TEMP_SECRET_NAME" "$service"
done

echo "[INFO] Removing the temporary secret..."
docker secret rm "$TEMP_SECRET_NAME"

echo "[INFO] Secret '$SECRET_NAME' updated successfully."
```