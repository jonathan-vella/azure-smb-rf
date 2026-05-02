#!/bin/sh
# Render /etc/nginx/nginx.conf.default from the shipped template at startup.
# API_BASE_URL is injected as a container app env var (see infra/main.bicep).
set -eu

: "${API_BASE_URL:?API_BASE_URL must be set on the container}"

# Derive the host portion (strip scheme + path) for proxy_set_header / SNI.
API_HOST=$(printf '%s' "$API_BASE_URL" | sed -E 's|^https?://||; s|/.*$||')
export API_HOST API_BASE_URL

# Only substitute the two variables we control; anything else (e.g. nginx's
# own $proxy_add_x_forwarded_for) must be left intact.
envsubst '${API_BASE_URL} ${API_HOST}' \
  < /etc/nginx/templates/nginx.conf.template \
  > /etc/nginx/nginx.conf.default

exec nginx -g 'daemon off;'
