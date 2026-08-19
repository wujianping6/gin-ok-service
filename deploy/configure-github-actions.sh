#!/usr/bin/env bash
set -Eeuo pipefail

config_file=${1:-deploy/github-actions-config.env}

if [[ ! -f $config_file ]]; then
  echo "config file not found: $config_file" >&2
  echo "copy deploy/github-actions-config.env.example and fill in its values first" >&2
  exit 1
fi

set -a
# shellcheck disable=SC1090
source "$config_file"
set +a

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

echo "Uploading GitHub Actions variables"
gh variable set SERVER_USER --body "$SERVER_USER" --repo "$GITHUB_REPOSITORY"
gh variable set SERVER_PORT --body "$SERVER_PORT" --repo "$GITHUB_REPOSITORY"
gh variable set DEPLOY_PATH --body "$DEPLOY_PATH" --repo "$GITHUB_REPOSITORY"
gh variable set APP_BIND_ADDRESS --body "$APP_BIND_ADDRESS" --repo "$GITHUB_REPOSITORY"
gh variable set APP_PORT --body "$APP_PORT" --repo "$GITHUB_REPOSITORY"
gh variable set ENABLE_DEPLOY --body "$ENABLE_DEPLOY" --repo "$GITHUB_REPOSITORY"

echo "Configuration uploaded successfully"
gh secret list --repo "$GITHUB_REPOSITORY"
gh variable list --repo "$GITHUB_REPOSITORY"
