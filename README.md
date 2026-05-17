# ShopStack Recipes

Managed business infrastructure for small businesses — vet clinics, retail shops, salons.
Deploys a complete stack (website, email, file storage, database) on a single server.

## What gets deployed

| Service | Role |
|---------|------|
| PostgreSQL | Shared database backend |
| Traefik | Reverse proxy + automatic TLS via Cloudflare |
| Authentik | SSO identity provider — protects admin interfaces |
| WireGuard | Encrypted remote management tunnel |
| Mailcow | Email server (SMTP/IMAP, webmail, spam filter) |
| Nextcloud | File storage (Dropbox replacement) |
| Uptime Kuma | Internal uptime monitoring |
| Invoice Ninja | Invoicing, client portal, Stripe/PayPal payment collection |

## Platforms

ShopStack runs identically on all three — the Ansible playbooks are platform-agnostic.

| Platform | Hardware | Setup |
|----------|----------|-------|
| **On-premises** | Beelink EQ12 mini PC (~$200, customer buys) | Debian 12, no Terraform needed |
| **AWS** | EC2 t3.large (~$60/mo on-demand) | `terraform/aws/` provisions instance + Elastic IP + Security Group |
| **GCP** | Compute e2-standard-2 (~$50/mo) | `terraform/gcp/` provisions instance + Static IP + Firewall Rules |

## Quick start

### Prerequisites

- A domain on Cloudflare (DNS managed by Cloudflare)
- A Cloudflare API token with **Zone → DNS → Edit** permission for the domain
- An SSH key at `~/.ssh/id_ansible` (or adjust the inventory line)
- Local tools: `ansible`, `terraform` (cloud only)

### Required variables

| Variable | Description |
|----------|-------------|
| `domain` | Base domain, e.g. `yourclinic.com` |
| `cf_api_token` | Cloudflare API token — used by Traefik for DNS-01 TLS |
| `acme_email` | Email for Let's Encrypt registration |
| `postgres_password` | PostgreSQL superuser password |
| `nextcloud_db_pass` | Nextcloud database password |
| `nextcloud_admin_pass` | Nextcloud admin UI password |
| `invoiceninja_db_pass` | Invoice Ninja database password |
| `invoiceninja_app_key` | 32-char random string — generate with `openssl rand -base64 32 \| head -c 32` |

### On-premises (Beelink)

```bash
# 1. Customer installs Debian 12, assigns static LAN IP
# 2. Port-forward these ports on their router to the Beelink:
#    TCP: 80, 443, 25, 465, 587, 143, 993, 995
#    UDP: 51820 (WireGuard)

# 3. Create inventory
cat > inventory.ini <<'EOF'
[shopstack]
shopstack ansible_host=<beelink-ip> ansible_user=root ansible_ssh_private_key_file=~/.ssh/id_ansible
EOF

# 4. Deploy full stack
ansible-playbook ansible/shopstack.yml \
  -i inventory.ini \
  --extra-vars "@profiles/on-prem.yml" \
  --extra-vars "domain=yourclinic.com" \
  --extra-vars "cf_api_token=<cloudflare-token>" \
  --extra-vars "acme_email=admin@yourclinic.com" \
  --extra-vars "postgres_password=<secret>" \
  --extra-vars "nextcloud_db_pass=<secret>" \
  --extra-vars "nextcloud_admin_pass=<secret>"
```

### AWS

```bash
# 1. Provision infrastructure
cd terraform/aws
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars — set client_name, ssh_public_key, admin_cidr_blocks
terraform init && terraform apply
# Outputs: public_ip, ansible_inventory_line

# 2. Create inventory from terraform output
cat > inventory.ini <<'EOF'
[shopstack]
<paste ansible_inventory_line output here>
EOF

# 3. Deploy full stack
cd ../..
ansible-playbook ansible/shopstack.yml \
  -i inventory.ini \
  --extra-vars "@profiles/aws.yml" \
  --extra-vars "domain=yourclinic.com" \
  --extra-vars "cf_api_token=<cloudflare-token>" \
  --extra-vars "acme_email=admin@yourclinic.com" \
  --extra-vars "postgres_password=<secret>" \
  --extra-vars "nextcloud_db_pass=<secret>" \
  --extra-vars "nextcloud_admin_pass=<secret>"
```

### GCP

```bash
# 1. Provision infrastructure
cd terraform/gcp
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars — set gcp_project, client_name, ssh_public_key, admin_cidr_blocks
terraform init && terraform apply
# Outputs: public_ip, ansible_inventory_line

# 2. Create inventory from terraform output
cat > inventory.ini <<'EOF'
[shopstack]
<paste ansible_inventory_line output here>
EOF

# 3. Deploy full stack
cd ../..
ansible-playbook ansible/shopstack.yml \
  -i inventory.ini \
  --extra-vars "@profiles/gcp.yml" \
  --extra-vars "domain=yourclinic.com" \
  --extra-vars "cf_api_token=<cloudflare-token>" \
  --extra-vars "acme_email=admin@yourclinic.com" \
  --extra-vars "postgres_password=<secret>" \
  --extra-vars "nextcloud_db_pass=<secret>" \
  --extra-vars "nextcloud_admin_pass=<secret>"
```

### Post-deploy checklist

**DNS** — create these Cloudflare A records pointing to the server's public IP before the playbook finishes (Traefik requests TLS certs on first start):

| Record | Proxy |
|--------|-------|
| `mail.yourclinic.com` | DNS-only |
| `files.yourclinic.com` | DNS-only |
| `auth.yourclinic.com` | DNS-only |
| `wg.yourclinic.com` | DNS-only (never proxy) |
| `billing.yourclinic.com` | DNS-only |
| `www.yourclinic.com` | Proxied |

**Authentik first-time setup:**
1. Browse to `https://auth.yourclinic.com/if/flow/initial-setup/`
2. Create your admin account
3. Admin → Applications → Providers → Create → **Proxy Provider** (Forward auth, domain level), external host: `https://auth.yourclinic.com`
4. Admin → Applications → Create, assign the provider
5. Admin → Outposts → Edit the default outpost, add the application
6. To protect a service, add `middlewares: [authentik@file]` to its Traefik router config

**WireGuard:**
- Client configs are written to `ansible/wireguard/clients/` on your local machine after the playbook runs
- Import the `.conf` file into the WireGuard app on your devices
- For phones: `cat /etc/wireguard/clients/<name>.qr` on the server and scan the output

**Invoice Ninja (billing):**
- Browse to `https://billing.yourclinic.com` after deploy
- Complete the first-run wizard to create your admin account
- Settings → Payment Gateways → Add Stripe (enter your publishable + secret keys)
- Settings → Company Details → fill in business name, address, logo
- Create your first invoice → click **Send** → client receives a payment link via email
- Clients pay by card through Stripe; Invoice Ninja records it automatically

**Mailcow:**
- After Mailcow starts, log in at `https://mail.yourclinic.com` (default: `admin` / `moohoo`)
- Change the admin password immediately
- Admin → Configuration → ARC/DKIM keys → generate keys, then add the MX, SPF, DKIM, and DMARC records Mailcow displays

## Support

For clients on a managed ShopStack plan, primary support is provided via **WhatsApp**, phone, and email. 

- **Managed Clients**: Message Brandon directly on WhatsApp for "it's broken" emergencies or configuration changes. Response is typically within 1 hour during business hours.
- **Open Source Users**: Support is provided via GitHub Issues on a best-effort basis.

---

## Directory layout

```
shopstack/
  ansible/
    shopstack.yml          # Master playbook — runs all services in order
    traefik/               # Reverse proxy + TLS
    authentik/             # SSO identity provider
    wireguard/             # Remote management VPN tunnel
    mailcow/               # Email server
    nextcloud/             # File storage
    postgres/              # Database
    uptime-kuma/           # Monitoring
    invoicing/             # Invoice Ninja — invoicing + Stripe payment collection
  terraform/
    aws/                   # EC2 + Elastic IP + Security Group
    gcp/                   # Compute + Static IP + Firewall Rules
  profiles/
    on-prem.yml            # Vars for Beelink mini PC
    aws.yml                # Vars for AWS EC2
    gcp.yml                # Vars for GCP Compute
```

## Per-client pricing reference

| Tier | Setup | Monthly | Infrastructure cost | Margin |
|------|-------|---------|---------------------|--------|
| On-Premises | $500 | $200/mo | $0 (customer buys ~$200 Beelink) | ~$200/mo |
| Plug & Play | $800 | $200/mo | ~$200 hardware + shipping (included in setup) | ~$170/mo |
| Cloud — AWS | $300 | $250/mo | ~$60/mo EC2 | ~$190/mo |
| Cloud — GCP | $300 | $250/mo | ~$50/mo Compute | ~$200/mo |

**Plug & Play**: you purchase and pre-configure a Beelink EQ12, then ship it to the customer. They plug in power and ethernet — nothing else required on their end. Best fit for non-technical owners who want zero setup involvement.

## Topics

`ansible` `terraform` `self-hosted` `mailcow` `nextcloud` `postgresql` `traefik` `authentik` `wireguard` `uptime-kuma` `invoice-ninja` `stripe` `invoicing` `infrastructure-as-code` `small-business` `debian` `aws` `gcp` `open-source`
