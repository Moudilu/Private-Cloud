# Monitoring with Prometheus and Grafana

## Install Prometheus

`sudo apt install -y prometheus-node-exporter prometheus prometheus-alertmanager`

Create alerts files for host monitoring - memory, filesystem, CPU, temperature, ...

```bash
sudo install -m 755 -d /etc/prometheus/alerts.d
sudo install --mode=644 ./resources/prometheus/node-exporter.yml ./resources/prometheus/deadmanswitch.yml /etc/prometheus/alerts.d

# Add additional collectors to node exporter
sudo sed -i 's/ARGS="/ARGS="--collector.systemd --collector.processes/' /etc/default/prometheus-node-exporter
sudo systemctl restart prometheus-node-exporter

# Install service for starting smartctl-exporter and its rules
sudo install --mode 644 ./resources/services/prometheus-smartctl-exporter.service /etc/systemd/system
sudo systemctl daemon-reload
sudo systemctl enable prometheus-smartctl-exporter
sudo systemctl start prometheus-smartctl-exporter
sudo wget -P /etc/prometheus/alerts.d https://raw.githubusercontent.com/samber/awesome-prometheus-alerts/master/dist/rules/s.m.a.r.t-device-monitoring/smartctl-exporter.yml
sudo chmod o+r /etc/prometheus/alerts.d/smartctl-exporter.yml
```

Create config for Prometheus

```bash
cat ./resources/prometheus/prometheus.yml | envsubst | sudo tee /etc/prometheus/prometheus.yml
sudo systemctl reload prometheus
```

Configure the alertmanager to send mails.

```bash
echo "Enter user for SMTP account"
read SMTP_USER
echo "Enter password for SMTP account"
read -s SMTP_PW
cat ./resources/prometheus/alertmanager.yml | SMTP_USER="$SMTP_USER" SMTP_PW="$SMTP_PW" envsubst | sudo tee /etc/prometheus/alertmanager.yml
# lock access to the configfile, to protect its secrets
sudo chown root:prometheus /etc/prometheus/alertmanager.yml
sudo chmod 640 /etc/prometheus/alertmanager.yml
sudo systemctl reload prometheus-alertmanager
```

## Install Grafana

Install grafana according to https://grafana.com/docs/grafana/latest/setup-grafana/installation/debian/

```bash
sudo apt-get install -y apt-transport-https software-properties-common wget
sudo mkdir -p /etc/apt/keyrings/
wget -q -O - https://apt.grafana.com/gpg.key | gpg --dearmor | sudo tee /etc/apt/keyrings/grafana.gpg > /dev/null
sudo chmod o+r /etc/apt/keyrings/grafana.gpg
echo "deb [signed-by=/etc/apt/keyrings/grafana.gpg] https://apt.grafana.com stable main" | sudo tee -a /etc/apt/sources.list.d/grafana.list
# Updates the list of available packages
sudo apt-get update
# Installs the latest OSS release:
sudo apt-get install -y grafana
```

Change general configuration.

```bash
echo "Enter the admin password to be set for Grafana"
read -s GRAFANA_PASSWORD
cat ./resources/grafana/grafana.ini | GRAFANA_PASSWORD="$GRAFANA_PASSWORD" envsubst | sudo tee -a /etc/grafana/grafana.ini

sudo install --mode=644 ./resources/grafana/prometheus.yaml ./resources/grafana/alertmanager.yaml /etc/grafana/provisioning/datasources
sudo systemctl restart grafana-server.service

# Add firewall rule
sudo install ./resources/nftables/10-grafana.rules /etc/inet-filter.rules.d
sudo systemctl reload nftables.service
```

Go to `http://<HOST>:3000`, login, add the dashboard with IDs 1860, 20204.
