# Add Home Assistant installation

## Install service

In the file [./resources/homeassistant/compose.yml](./resources/homeassistant/compose.yml), change the IP addresses and the parent network interface name according to your needs.

```bash
TZ=$(timedatectl show --property=Timezone --value)
sudo install -D -m 644 -t /etc/homeassistant ./resources/homeassistant/compose.yml
sudo install -m 644 ./resources/services/homeassistant.service /etc/systemd/system
sudo systemctl daemon-reload
sudo systemctl enable --now homeassistant

# To enable the reverse proxy, the config for Home Assistant http integration needs to be set. Also enables the prometheus integration for monitoring.
sudo docker compose -f /etc/homeassistant/compose.yml exec home-assistant bash -c 'echo -e "\nhttp:\n  use_x_forwarded_for: true\n  trusted_proxies:\n    - $(dig +short caddy)\nprometheus:\n  namespace: homeassistant" >> /config/configuration.yaml'
sudo docker compose -f /etc/homeassistant/compose.yml restart home-assistant
```

## Add to the local reverse proxy

In your DNS, add the entries pointing to the main IP of your server.

```bash
read -p "Enter the desired domain name for Home Assistant: " HA_FQDN
sudo install -m 644 /dev/stdin /etc/local-caddy/conf/sites-enabled/homeassistant << EOF
${HA_FQDN} {
	reverse_proxy http://home-assistant-server:8123
}
EOF
read -p "Enter the desired domain name for Music Assistant: " MA_FQDN
sudo install -m 644 /dev/stdin /etc/local-caddy/conf/sites-enabled/musicassistant << EOF
${MA_FQDN} {
	reverse_proxy http://music-assistant-server:8095
}
EOF
read -p "Enter the desired domain name for ESPHome Builder: " ESP_FQDN
sudo install -m 644 /dev/stdin /etc/local-caddy/conf/sites-enabled/esphome << EOF
${ESP_FQDN} {
	reverse_proxy http://esp-home-server:6052
}
EOF

# S.t. the containers can resolve each other via their full name, add an alias to the caddy container on the local caddy network
sudo yq -i '.services.caddy.networks.local-caddy.aliases = ["$HA_FQDN","$MA_FQDN","$ESP_FQDN"]' /etc/local-caddy/compose.yaml

sudo systemctl restart local-caddy
```

## Enable Prometheus

It is possible to hook up Home Assistant to Prometheus, s.t. all (!) its data is logged & stored there.Be aware that this might log some amount of (personal and sensitive) data. Generate a long-lived access token (see https://developers.home-assistant.io/docs/auth_api/#long-lived-access-token) for authentication.

```bash
read -sp "Enter the long lived access token from Home Assistant (create at the bottom of this page: https://${HA_FQDN}/profile/security): " HA_LLAT
echo "${HA_LLAT}" | sudo install -o prometheus -m 600 /dev/stdin /etc/prometheus/homeassistant_credentials
cat | sudo tee -a /etc/prometheus/prometheus.yml << EOF
  - job_name: "Home Assistant"
    static_configs:
      - targets: ['${HA_FQDN}']
    scheme: https
    metrics_path: /api/prometheus
    authorization:
      credentials_file: /etc/prometheus/homeassistant_credentials
EOF
sudo systemctl reload prometheus
```

## Connect Music Assistant

Open the page for Homeassistant. After initial setup, go to Settings > Integrations > Add integration, search for Music Assistant, enter your domain for Music Assistant. In Music Assistant, when asked for the Home Assistant URL, enter your normal Home Assistant URL.

## Home Assistant Backups

In Home Assistant, go to Settings > System > Backups > Set up backups. Store the encryption key safely, enable the default settings. To add the Homeassistant backup to the automatic Nextcloud backup, it is recommended to add the line `homeassistant_backup` to the extra backup locations in the Nextcloud AIO interface (access it via the settings page of your Nextcloud admin user). It is recommended to test the backup afterwards.
