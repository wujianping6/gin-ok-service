#!/usr/bin/env bash
set -Eeuo pipefail

config_file=${1:-deploy/github-actions-config.env}
acr_config_file=${2:-deploy/acr-config.env}

if [[ ! -f $config_file ]]; then
  echo "config file not found: $config_file" >&2
  echo "copy deploy/github-actions-config.env.example and fill in its values first" >&2
  exit 1
fi

if [[ ! -f $acr_config_file ]]; then
  echo "ACR config file not found: $acr_config_file" >&2
  echo "copy deploy/acr-config.env.example and fill in its values first" >&2
  exit 1
fi

read_config_value() {
  local source_file=$1
  local key=$2
  local line value

  line=$(awk -v wanted="$key" '
    index($0, wanted "=") == 1 { value = $0 }
    END { print value }
  ' "$source_file")
  value=${line#*=}
  value=${value%$'\r'}

  if [[ ${#value} -ge 2 && ${value:0:1} == '"' && ${value: -1} == '"' ]]; then
    value=${value:1:${#value}-2}
  elif [[ ${#value} -ge 2 && ${value:0:1} == "'" && ${value: -1} == "'" ]]; then
    value=${value:1:${#value}-2}
  fi

  printf '%s' "$value"
}

GITHUB_REPOSITORY=$(read_config_value "$config_file" GITHUB_REPOSITORY)
SERVER_HOST=$(read_config_value "$config_file" SERVER_HOST)
SERVER_USER=$(read_config_value "$config_file" SERVER_USER)
SERVER_PORT=$(read_config_value "$config_file" SERVER_PORT)
DEPLOY_PATH=$(read_config_value "$config_file" DEPLOY_PATH)
APP_BIND_ADDRESS=$(read_config_value "$config_file" APP_BIND_ADDRESS)
APP_PORT=$(read_config_value "$config_file" APP_PORT)
DEPLOY_SSH_KEY_FILE=$(read_config_value "$config_file" DEPLOY_SSH_KEY_FILE)
SERVER_KNOWN_HOSTS_FILE=$(read_config_value "$config_file" SERVER_KNOWN_HOSTS_FILE)
ENABLE_DEPLOY=$(read_config_value "$config_file" ENABLE_DEPLOY)

ACR_REGISTRY=$(read_config_value "$acr_config_file" ACR_REGISTRY)
ACR_NAMESPACE=$(read_config_value "$acr_config_file" ACR_NAMESPACE)
ACR_REPOSITORY=$(read_config_value "$acr_config_file" ACR_REPOSITORY)
ACR_USERNAME=$(read_config_value "$acr_config_file" ACR_USERNAME)
ACR_PASSWORD=$(read_config_value "$acr_config_file" ACR_PASSWORD)

required_values=(
  GITHUB_REPOSITORY
  SERVER_HOST
  SERVER_USER
  SERVER_PORT
  DEPLOY_PATH
  APP_BIND_ADDRESS
  APP_PORT
  DEPLOY_SSH_KEY_FILE
  SERVER_KNOWN_HOSTS_FILE
  ENABLE_DEPLOY
  ACR_REGISTRY
  ACR_NAMESPACE
  ACR_REPOSITORY
  ACR_USERNAME
  ACR_PASSWORD
)

for value_name in "${required_values[@]}"; do
  if [[ -z ${!value_name:-} ]]; then
    echo "missing value in $config_file: $value_name" >&2
    exit 1
  fi
done

[[ $GITHUB_REPOSITORY =~ ^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$ ]] || {
  echo "invalid GITHUB_REPOSITORY: $GITHUB_REPOSITORY" >&2
  exit 1
}
[[ $SERVER_HOST =~ ^[A-Za-z0-9.:-]+$ ]] || {
  echo "invalid SERVER_HOST: use a plain IP address or hostname without a URL, user, port or path" >&2
  exit 1
}
[[ $SERVER_USER =~ ^[A-Za-z_][A-Za-z0-9_-]*$ ]] || {
  echo "invalid SERVER_USER: $SERVER_USER" >&2
  exit 1
}
[[ $SERVER_PORT =~ ^[0-9]{1,5}$ ]] && (( 10#$SERVER_PORT >= 1 && 10#$SERVER_PORT <= 65535 )) || {
  echo "invalid SERVER_PORT: $SERVER_PORT" >&2
  exit 1
}
[[ $DEPLOY_PATH =~ ^/[A-Za-z0-9._/-]+$ && $DEPLOY_PATH != "/" ]] || {
  echo "invalid DEPLOY_PATH: $DEPLOY_PATH" >&2
  exit 1
}
[[ $APP_BIND_ADDRESS == "0.0.0.0" || $APP_BIND_ADDRESS == "127.0.0.1" ]] || {
  echo "APP_BIND_ADDRESS must be 0.0.0.0 or 127.0.0.1" >&2
  exit 1
}
[[ $APP_PORT =~ ^[0-9]{1,5}$ ]] && (( 10#$APP_PORT >= 1 && 10#$APP_PORT <= 65535 )) || {
  echo "invalid APP_PORT: $APP_PORT" >&2
  exit 1
}
[[ $ENABLE_DEPLOY == "true" || $ENABLE_DEPLOY == "false" ]] || {
  echo "ENABLE_DEPLOY must be true or false" >&2
  exit 1
}
[[ $ACR_REGISTRY =~ ^[a-z0-9.-]+$ && $ACR_REGISTRY == *.* && $ACR_REGISTRY != .* && $ACR_REGISTRY != *. ]] || {
  echo "invalid ACR_REGISTRY: use the public registry hostname without https:// or a path" >&2
  exit 1
}
[[ $ACR_NAMESPACE =~ ^[a-z0-9][a-z0-9._-]*$ ]] || {
  echo "invalid ACR_NAMESPACE: $ACR_NAMESPACE" >&2
  exit 1
}
[[ $ACR_REPOSITORY =~ ^[a-z0-9][a-z0-9._-]*$ ]] || {
  echo "invalid ACR_REPOSITORY: $ACR_REPOSITORY" >&2
  exit 1
}
[[ $ACR_USERNAME != *$'\n'* && $ACR_PASSWORD != *$'\n'* ]] || {
  echo "ACR credentials must not contain line breaks" >&2
  exit 1
}
[[ -s $DEPLOY_SSH_KEY_FILE ]] || {
  echo "SSH private key file is missing or empty: $DEPLOY_SSH_KEY_FILE" >&2
  exit 1
}
[[ -s $SERVER_KNOWN_HOSTS_FILE ]] || {
  echo "known_hosts file is missing or empty: $SERVER_KNOWN_HOSTS_FILE" >&2
  exit 1
}

command -v gh >/dev/null || {
  echo "GitHub CLI (gh) is not installed" >&2
  exit 1
}
gh auth status --hostname github.com >/dev/null

echo "Uploading GitHub Actions secrets to $GITHUB_REPOSITORY"
printf '%s' "$SERVER_HOST" | gh secret set SERVER_HOST --repo "$GITHUB_REPOSITORY"
gh secret set DEPLOY_SSH_KEY --repo "$GITHUB_REPOSITORY" < "$DEPLOY_SSH_KEY_FILE"
gh secret set SERVER_KNOWN_HOSTS --repo "$GITHUB_REPOSITORY" < "$SERVER_KNOWN_HOSTS_FILE"
printf '%s' "$ACR_USERNAME" | gh secret set ACR_USERNAME --repo "$GITHUB_REPOSITORY"
printf '%s' "$ACR_PASSWORD" | gh secret set ACR_PASSWORD --repo "$GITHUB_REPOSITORY"

echo "Uploading GitHub Actions variables"
gh variable set SERVER_USER --body "$SERVER_USER" --repo "$GITHUB_REPOSITORY"
gh variable set SERVER_PORT --body "$SERVER_PORT" --repo "$GITHUB_REPOSITORY"
gh variable set DEPLOY_PATH --body "$DEPLOY_PATH" --repo "$GITHUB_REPOSITORY"
gh variable set APP_BIND_ADDRESS --body "$APP_BIND_ADDRESS" --repo "$GITHUB_REPOSITORY"
gh variable set APP_PORT --body "$APP_PORT" --repo "$GITHUB_REPOSITORY"
gh variable set ENABLE_DEPLOY --body "$ENABLE_DEPLOY" --repo "$GITHUB_REPOSITORY"
gh variable set ACR_REGISTRY --body "$ACR_REGISTRY" --repo "$GITHUB_REPOSITORY"
gh variable set ACR_NAMESPACE --body "$ACR_NAMESPACE" --repo "$GITHUB_REPOSITORY"
gh variable set ACR_REPOSITORY --body "$ACR_REPOSITORY" --repo "$GITHUB_REPOSITORY"

echo "Configuration uploaded successfully"
gh secret list --repo "$GITHUB_REPOSITORY"
gh variable list --repo "$GITHUB_REPOSITORY"
