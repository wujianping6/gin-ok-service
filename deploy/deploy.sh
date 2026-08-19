#!/usr/bin/env bash
set -Eeuo pipefail

if [[ $# -lt 4 || $# -gt 5 ]]; then
  echo "usage: $0 <image-name> <image-tag> <bind-address> <host-port> [image-already-loaded]" >&2
  exit 2
fi

image_name=$1
image_tag=$2
bind_address=$3
host_port=$4
image_already_loaded=${5:-false}
deploy_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)

if [[ ! $image_name =~ ^ghcr\.io/[a-z0-9._/-]+$ ]]; then
  echo "invalid image name: $image_name" >&2
  exit 2
fi

if [[ ! $image_tag =~ ^[0-9a-f]{40}$ ]]; then
  echo "invalid image tag: expected a full Git commit SHA" >&2
  exit 2
fi

if [[ $bind_address != "0.0.0.0" && $bind_address != "127.0.0.1" ]]; then
  echo "invalid bind address: use 0.0.0.0 or 127.0.0.1" >&2
  exit 2
fi

if [[ ! $host_port =~ ^[0-9]{1,5}$ ]] || (( 10#$host_port < 1 || 10#$host_port > 65535 )); then
  echo "invalid host port: $host_port" >&2
  exit 2
fi

if [[ $image_already_loaded != "true" && $image_already_loaded != "false" ]]; then
  echo "image-already-loaded must be true or false" >&2
  exit 2
fi

command -v docker >/dev/null || {
  echo "docker is not installed" >&2
  exit 1
}
docker compose version >/dev/null

cd "$deploy_dir"
umask 077

next_env=.env.next
previous_env=.env.previous

if [[ -f .env ]]; then
  cp .env "$previous_env"
else
  rm -f "$previous_env"
fi

printf 'IMAGE_NAME=%s\nIMAGE_TAG=%s\nAPP_BIND_ADDRESS=%s\nAPP_PORT=%s\n' \
  "$image_name" "$image_tag" "$bind_address" "$host_port" > "$next_env"

compose() {
  local env_file=$1
  shift
  docker compose --env-file "$env_file" -f compose.production.yaml "$@"
}

if [[ $image_already_loaded == "true" ]]; then
  echo "Using the image transferred by the CI runner"
  if ! docker image inspect "$image_name:$image_tag" >/dev/null; then
    echo "transferred image is not available: $image_name:$image_tag" >&2
    rm -f "$next_env"
    exit 1
  fi
else
  echo "Pulling $image_name:$image_tag"
  if ! compose "$next_env" pull app; then
    rm -f "$next_env"
    exit 1
  fi
fi

echo "Starting the new container and waiting for its health check"
if compose "$next_env" up -d --remove-orphans --wait --wait-timeout 60; then
  mv "$next_env" .env
  compose .env ps
  echo "Deployment succeeded: $image_name:$image_tag"
  exit 0
fi

echo "Deployment failed; showing recent logs" >&2
compose "$next_env" logs --tail=100 app || true
rm -f "$next_env"

if [[ -f $previous_env ]]; then
  echo "Rolling back to the previous image" >&2
  if compose "$previous_env" up -d --remove-orphans --wait --wait-timeout 60; then
    cp "$previous_env" .env
    echo "Rollback succeeded" >&2
  else
    echo "Rollback also failed; manual intervention is required" >&2
  fi
else
  echo "No previous deployment is available for rollback" >&2
fi

exit 1
