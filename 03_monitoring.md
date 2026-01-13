# Monitoring with Prometheus and Grafana

## Install Prometheus

Create alerts files for host monitoring - memory, filesystem, CPU, temperature, ...

```bash
sudo apt install -y prometheus-node-exporter prometheus prometheus-alertmanager
sudo systemctl disable openipmi # Is installed by the node exporter. Fails on the authors server and is not required by the activated collectors.

sudo install -m 755 -d /etc/prometheus/alerts.d
sudo install --mode=644 ./resources/prometheus/node-exporter.yml /etc/prometheus/alerts.d
# If you want a notification every week, to verify that the system is running, activate also the following rule
# sudo install --mode=644 ./resources/prometheus/deadmanswitch.yml /etc/prometheus/alerts.d

# Add additional collectors to node exporter
sudo sed -i 's/ARGS="/ARGS="--collector.systemd --collector.processes/' /etc/default/prometheus-node-exporter
sudo systemctl restart prometheus-node-exporter

# Install service for starting smartctl-exporter and its rules
sudo install --mode 644 ./resources/services/prometheus-smartctl-exporter.service /etc/systemd/system
sudo systemctl daemon-reload
sudo systemctl enable --now prometheus-smartctl-exporter
sudo wget -P /etc/prometheus/alerts.d https://raw.githubusercontent.com/samber/awesome-prometheus-alerts/master/dist/rules/s.m.a.r.t-device-monitoring/smartctl-exporter.yml
sudo chmod o+r /etc/prometheus/alerts.d/smartctl-exporter.yml
```

Create config for Prometheus

```bash
cat ./resources/prometheus/prometheus.yml | envsubst | sudo tee /etc/prometheus/prometheus.yml
sudo systemctl reload prometheus
```

Keep metrics for 60 days

```bash
sudo sed -i 's/ARGS="/ARGS="--storage.tsdb.retention.time=60d /' /etc/default/prometheus
```

Configure the alertmanager to send mails.

```bash
read -p "Enter the host and port of your SMTP server (e.g. mail.private-cloud.org:465): " SMTP_HOST
read -p "Enter user for SMTP account: " SMTP_USER
read -sp "Enter password for SMTP account: " SMTP_PW
read -p "Enter the sender address to use for the alert emails: " SENDER_MAIL
cat ./resources/prometheus/alertmanager.yml | SMTP_HOST="$SMTP_HOST" SMTP_USER="$SMTP_USER" SMTP_PW="$SMTP_PW" ADMIN_EMAIL="$ADMIN_EMAIL" SENDER_MAIL="$SENDER_MAIL" HOSTNAME="$(hostname)" envsubst | sudo tee /etc/prometheus/alertmanager.yml
# lock access to the configfile, to protect its secrets
sudo chown root:prometheus /etc/prometheus/alertmanager.yml
sudo chmod 640 /etc/prometheus/alertmanager.yml
sudo systemctl reload prometheus-alertmanager
```

## Install Grafana

Install grafana according to https://grafana.com/docs/grafana/latest/setup-grafana/installation/debian/

Make sure that the configuration with the admin user exists before Grafana starts for the first time!

```bash
sudo mkdir -p /etc/grafana/provisioning/datasources
read -sp "Enter the admin password to be set for Grafana" GRAFANA_PASSWORD
cat ./resources/grafana/grafana.ini | GRAFANA_PASSWORD="$GRAFANA_PASSWORD" ADMIN_EMAIL="$ADMIN_EMAIL" envsubst | sudo tee /etc/grafana/grafana.ini

sudo install --mode=644 ./resources/grafana/prometheus.yaml ./resources/grafana/alertmanager.yaml /etc/grafana/provisioning/datasources

sudo apt-get install -y apt-transport-https software-properties-common wget
sudo mkdir -p /etc/apt/keyrings/
wget -q -O - https://apt.grafana.com/gpg.key | gpg --dearmor | sudo tee /etc/apt/keyrings/grafana.gpg > /dev/null
sudo chmod o+r /etc/apt/keyrings/grafana.gpg
echo "deb [signed-by=/etc/apt/keyrings/grafana.gpg] https://apt.grafana.com stable main" | sudo tee /etc/apt/sources.list.d/grafana.list
sudo chmod o+r /etc/apt/sources.list.d/grafana.list

# Updates the list of available packages
sudo apt-get update
# Installs the latest OSS release:
sudo apt-get install -y grafana

sudo chown -R root:grafana /etc/grafana

# Add firewall rule
sudo install -m 600 ./resources/nftables/10-grafana.rules /etc/inet-filter.rules.d
sudo systemctl reload nftables

# Start the server only! now
sudo systemctl enable grafana-server
sudo systemctl start grafana-server
```

Go to `http://<HOST>:3000`, login, add the dashboard with IDs 1860, 20204 by going to Dashboards > New > Import and entering the IDs into the provided field.
