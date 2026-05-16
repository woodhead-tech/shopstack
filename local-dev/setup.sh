#!/usr/bin/env bash
# First-time setup for ShopStack local dev environment.
# Run once, then use: docker compose up -d

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# 1. Create .env from example if it doesn't exist
if [ ! -f "$SCRIPT_DIR/.env" ]; then
  cp "$SCRIPT_DIR/.env.example" "$SCRIPT_DIR/.env"
  # Generate passwords
  NEXTCLOUD_DB_PASS=$(openssl rand -hex 16)
  NEXTCLOUD_ADMIN_PASS=$(openssl rand -hex 16)
  INVOICENINJA_DB_PASS=$(openssl rand -hex 16)
  INVOICENINJA_APP_KEY="base64:$(openssl rand -base64 32)"
  WP_ADMIN_PASS=$(openssl rand -hex 16)
  WOOCOMMERCE_DB_PASS=$(openssl rand -hex 16)

  sed -i "s/NEXTCLOUD_ADMIN_PASS=changeme/NEXTCLOUD_ADMIN_PASS=${NEXTCLOUD_ADMIN_PASS}/" "$SCRIPT_DIR/.env"
  sed -i "s/NEXTCLOUD_DB_PASS=changeme/NEXTCLOUD_DB_PASS=${NEXTCLOUD_DB_PASS}/" "$SCRIPT_DIR/.env"
  sed -i "s|INVOICENINJA_APP_KEY=base64:changeme|INVOICENINJA_APP_KEY=${INVOICENINJA_APP_KEY}|" "$SCRIPT_DIR/.env"
  sed -i "s/INVOICENINJA_DB_PASS=changeme/INVOICENINJA_DB_PASS=${INVOICENINJA_DB_PASS}/" "$SCRIPT_DIR/.env"
  sed -i "s/WP_ADMIN_PASS=changeme/WP_ADMIN_PASS=${WP_ADMIN_PASS}/" "$SCRIPT_DIR/.env"
  sed -i "s/WOOCOMMERCE_DB_PASS=changeme/WOOCOMMERCE_DB_PASS=${WOOCOMMERCE_DB_PASS}/" "$SCRIPT_DIR/.env"

  echo "Generated .env with random passwords."
  echo ""
  echo "Nextcloud admin password:   ${NEXTCLOUD_ADMIN_PASS}"
  echo "Invoice Ninja app key:      ${INVOICENINJA_APP_KEY}"
  echo "WordPress admin password:   ${WP_ADMIN_PASS}"
fi

# 2. Add /etc/hosts entries if missing
HOSTS_ENTRIES=(
  "127.0.0.1 shopstack.local"
  "127.0.0.1 traefik.shopstack.local"
  "127.0.0.1 files.shopstack.local"
  "127.0.0.1 billing.shopstack.local"
  "127.0.0.1 shop.shopstack.local"
)

HOSTS_UPDATED=false
for entry in "${HOSTS_ENTRIES[@]}"; do
  if ! grep -qF "$entry" /etc/hosts; then
    echo "$entry" | sudo tee -a /etc/hosts > /dev/null
    HOSTS_UPDATED=true
  fi
done

if $HOSTS_UPDATED; then
  echo "Added shopstack.local entries to /etc/hosts."
fi

echo ""
echo "Setup complete. Run: docker compose up -d"
echo ""
echo "Services (accept the self-signed cert warning in your browser):"
echo "  https://traefik.shopstack.local   Traefik dashboard"
echo "  https://files.shopstack.local     Nextcloud"
echo "  https://billing.shopstack.local   Invoice Ninja"
echo "  https://shop.shopstack.local      WooCommerce"
