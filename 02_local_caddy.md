# Reverse proxy for local services

## Configure your DNS for ACME DNS challenge

(taken from https://github.com/caddy-dns/acmedns)

1. Register with an ACME-DNS server. For testing purposes, http://auth.acme-dns.io can be used, self-hosting is encouraged.  
```bash
ACME_SERVER="https://auth.acme-dns.io"
curl -X POST $ACME_SERVER/register | tee /dev/stderr | jq "{username, password, subdomain} + {server_url: \"$ACME_SERVER\"}" | sudo install -D -m 600 /dev/stdin /etc/local-caddy/conf/acme-dns-credentials.json
```
2. Create a DNS CNAME record that points from _acme-challenge.your-domain-for-the-local-services.example.com to the fulldomain from the registration response.

## Install caddy server

Install a caddyserver acting as reverse-proxy with automatic https for services exposed on the local network.

```sh
sudo install -m 600 ./resources/nftables/30-local-caddy.rules /etc/inet-filter.rules.d
sudo systemctl reload nftables

sudo install -D -t /etc/local-caddy ./resources/caddy/compose.yaml
sudo install -D -t /etc/local-caddy/conf ./resources/caddy/Caddyfile
sudo install -d /etc/local-caddy/conf/sites-enabled
sudo install ./resources/services/local-caddy.service /etc/systemd/system
sudo systemctl daemon-reload
sudo systemctl enable --now local-caddy
```