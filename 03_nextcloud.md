# Install Nextcloud and backup services

## Backup to coud & monitoring

### Configure rclone

Since the rclone version in the Ubuntu repositories is quite outdated, it has happened that Onedrive could not be accessed anymore using the repository rclone version. Therefore, rclone is used in a docker container, which is one of the recommended usage variants.

Create a configuration passwort for rclone and save it to a root-only readable file, so that scripts can use rclone:

```bash
read -sp "Enter the password for your rclone configuration: " RCLONE_CONFIG_PASS
sudo install -m 640 /dev/null /etc/rclone.configpass
echo "RCLONE_CONFIG_PASS=$RCLONE_CONFIG_PASS" | sudo tee /etc/rclone.configpass > /dev/null
```

On your development host, open an SSH connection forwarding port 53682 with the command `ssh -L localhost:53682:localhost:53682 username@remote_server`, in order to be able to see the authentication web page. See https://rclone.org/remote_setup/ for other options.

If you have already created a Client ID for OneDrive according to https://rclone.org/onedrive/#getting-your-own-client-id-and-key before, you might be able to extend the validity of the token. New registrations seem disabled, if the documentation has not been updated you might have to (and I think can) just go with the default rclone client ID. It might be throttled, but short tests have shown no difference.

Run `sudo docker run --rm -it --volume /root/.config/rclone:/config/rclone -p 53682:53682 --env-file /etc/rclone.configpass rclone/rclone:latest config` and complete the following steps:

- make sure the configuration is encrypted: s -> a
- Create all remotes, where you want the backup to be stored (maybe distributed to several remotes)
- - If you have several cloud locations you want to join to store your backup: 
    
    Create a remote of type [`union`](https://rclone.org/union/) with the name `remote-nc-bkp`, with the remotes and paths where you want the backup stored. The other settings should be ok with the default values. 
  - If the backup is only in one location, name the remote directly `remote-nc-bkp`. The backup will be stored in the root of this remote, if the scripts are not adjusted accordingly.

### Restore backup

If you have a backup, you should restore it at the latest now. Copy the borg archive to `/srv/nc-bkp`.

One of these commands might come in handy:

```bash
sudo rclone sync remote-nc-bkp:backup/$(hostname)/nc-bkp /srv/nc-bkp/ -v

# or

sudo rclone sync /media/nc-bkp-ext/backup/mf-srv/nc-bkp /srv/nc-bkp/ -v
```

### Backup to cloud

Install the backup script and services which trigger it

```bash
sudo apt install -y inotify-tools 
sudo install -d /opt/private-cloud/scripts /var/lib/private-cloud/stats
sudo install ./scripts/backup-nc-bkp.sh ./scripts/mount-cloud-nc-bkp.sh ./scripts/mount-disc-nc-bkp.sh /opt/private-cloud/scripts
sudo apt install borgbackup # install the tool to enable mounting the backup
sudo install ./resources/services/backup-cloud.service ./resources/services/backup-cloud.path /etc/systemd/system
sudo systemctl daemon-reload
sudo systemctl enable backup-cloud.path
sudo systemctl start backup-cloud.path
```

### Backup to external harddrive

Format your drive with ext4. Plug the harddrive to your server.

Create the mountpoint and find the UUID of your partition:

```bash
sudo mkdir /media/nc-bkp-ext
lsblk -o NAME,FSTYPE,UUID,SIZE,MOUNTPOINTS
read -p "Identify the UUID of the partition for your external backup in the list above and enter it: " EXT_UUID
if [ -e "/dev/disk/by-uuid/$EXT_UUID" ]; then
  echo "UUID=$EXT_UUID /media/nc-bkp-ext ext4 defaults,noauto 0 1" | sudo tee -a /etc/fstab
  echo "Created mountpoint for external disk, will be mounted automatically by the backup service"
else
  echo "Disk with UUID $EXT_UUID can't be found. Make sure it is plugged in and try again."
fi
```

Install the service which automatically runs the backup when the disc is plugged in.

```bash
sudo apt install -y vorbis-tools yaru-theme-sound alsa-utils
sudo install ./resources/services/backup-external-end.service /etc/systemd/system
cat ./resources/services/backup-external.service | EXT_UUID_SYSTEMD="$(systemd-escape -p /dev/disk/by-uuid/$EXT_UUID)" envsubst | sudo tee /etc/systemd/system/backup-external.service
sudo systemctl daemon-reload
sudo systemctl enable backup-external.service
```

If you want to hear a notification sound when the backup is complete, ensure that the volume is set appropriately and is not muted with `sudo alsamixer`.

You can add the dashboard with ID 21260 to Grafana.

## Install Nextcloud AIO

Create the docker compose file to start the nextcloud AIO stack.

```bash
# install yq
sudo wget https://github.com/mikefarah/yq/releases/latest/download/yq_linux_amd64 -O /usr/bin/yq && sudo chmod o+x /usr/bin/yq

read -p 'Enter the first IP address on which you want to expose this Nextcloud instance (e.g. "192.168.1.7" or "[1f97:1bc1:e360:0195::4]", IPv6 addresses must be enclosed in curly brackets!): ' NEXTCLOUD_IP

# get docker compose file, apply custom settings
# prepopulate the nextcloud-aio network in order to control the interface name, s.t. it can be referenced in the firewall rules
curl https://raw.githubusercontent.com/nextcloud/all-in-one/refs/heads/main/compose.yaml \
| yq "
  .services.nextcloud-aio-mastercontainer.environment.NEXTCLOUD_DATADIR = \"/srv/nc-data\" |
  .services.nextcloud-aio-mastercontainer.networks = [\"nextcloud-aio\"] |
  del(.services.nextcloud-aio-mastercontainer.network_mode) |
  .services.nextcloud-aio-mastercontainer.ports =  [\"$NEXTCLOUD_IP:80:80\", \"8080:8080\"] |
  .services.nextcloud-aio-mastercontainer.ports.[] style=\"double\" |
  (.services.nextcloud-aio-mastercontainer.ports | key) line_comment=\"Omit port 8443, add it if you want to expose the AIO management interface on the internet with a certificate\" |
  .networks.nextcloud-aio = {
    \"driver\": \"bridge\",
    \"driver_opts\": {\"com.docker.network.bridge.name\": \"nextcloud-aio\"},
    \"name\": \"nextcloud-aio\"
  }
" | sudo tee /opt/private-cloud/nextcloud.docker-compose.yaml
```

For any additional IP address you want to expose Nextcloud on, run the following snippet (e.g. an IPv6 address):

```bash
read -p 'Enter the additional IP address on which you want to expose this Nextcloud instance (e.g. "192.168.1.7" or "[1f97:1bc1:e360:0195::4]", IPv6 addresses must be enclosed in curly brackets!): ' NEXTCLOUD_IP
sudo yq -i "
  .services.nextcloud-aio-mastercontainer.ports +=  \"$NEXTCLOUD_IP:80:80\"
" /opt/private-cloud/nextcloud.docker-compose.yaml
```

You might want to change the configuration to include some community containers. This additional configuration enables the memories and fail2ban containers. Also, it gives access to the directory `/srv/nc-data-no-bkp`, which can be mounted as external storage in nextcloud (it will not be included in any backup).

```bash
sudo yq -i "
  .services.nextcloud-aio-mastercontainer.environment.NEXTCLOUD_MOUNT = \"/srv/nc-data-no-bkp\" |
  .services.nextcloud-aio-mastercontainer.environment.NEXTCLOUD_ENABLE_DRI_DEVICE = \"true\" |
  .services.nextcloud-aio-mastercontainer.environment.NEXTCLOUD_ADDITIONAL_APKS=\"imagemagick bash ffmpeg libva-utils libva-vdpau-driver libva-intel-driver intel-media-driver mesa-va-gallium\" |
  .services.nextcloud-aio-mastercontainer.environment.NEXTCLOUD_MEMORY_LIMIT=\"2048M\"
" /opt/private-cloud/nextcloud.docker-compose.yaml
```

Configure the firewall to allow forwarding of packets to Nextcloud:

```bash
sudo install -m 600 ./resources/nftables/20-nextcloud.rules /etc/inet-filter.rules.d
sudo systemctl reload nftables.service
```

The nextcloud instance is started with the command `sudo docker compose -f /opt/private-cloud/nextcloud.docker-compose.yaml up -d`. It is marked to restart always so will restart also after a reboot. If you change any configuration in the docker compose file, e. g. add a community container or so, you can run the same command. This will not delete any data.

To stop the nextcloud service, you should go to the webinterface of the mastercontainer, see its [readme](https://github.com/nextcloud/all-in-one).

Remember to open ports 80, 443 and, if you want to run the talk container, also 3478 in your router. This usually includes adding firewall exceptions for those ports to your nextcloud instance and adding NAT forwarding rules for IPv4.

If you run Nextcloud with only a public IPv6 address (e.g. for testing), you have to set additionally the environment variable `SKIP_DOMAIN_VALIDATION` to `"true"`.

## Configure Nextcloud

Now you should be able to go to https://\<internal IP of nextcloud instance\>:8080 (you will get a warning because of the self signed certificate, you can ignore it) and start configuring your server or restore your backup if you have one.

In the section `Backup and restore`, enter the path `/srv/nc-bkp` and click on `Create backup` to create the initial backup. After it completed, submit a time when the daily automated backups shall be run.

Please refer to the extensive and very good documentation of [Nextcloud AIO](https://github.com/nextcloud/all-in-one).

The following settings might be interesting:

```bash
# Set the time for non-time critical background tasks to 11pm UTC (see https://docs.nextcloud.com/server/latest/admin_manual/configuration_server/background_jobs_configuration.html)
sudo docker exec --user www-data -it nextcloud-aio-nextcloud php occ config:system:set maintenance_window_start --type=integer --value=23

# Set the default phone region (as Nextcloud security check might complain about it otherwhise), see https://docs.nextcloud.com/server/latest/admin_manual/configuration_server/config_sample_php_parameters.html#default-phone-region
# Use a code from https://en.wikipedia.org/wiki/ISO_3166-1_alpha-2#Officially_assigned_code_elements
sudo docker exec --user www-data -it nextcloud-aio-nextcloud php occ config:system:set default_phone_region --value="CH"
```

## Export metrics to Prometheus

https://github.com/xperimental/nextcloud-exporter

Create a random token, e.g. with `TOKEN=$(openssl rand -hex 32)`, and run `sudo docker exec --user www-data -it nextcloud-aio-nextcloud php occ config:app:set serverinfo token --value "$TOKEN"`.

Create the file with environment variables for configuration:

```bash
read -p "Enter the public domain of your nextcloud installation (e.g. https://private-cloud.org): " NC_FQDN
sudo tee -a /etc/prometheus-nextcloud-exporter.env <<EOF
NEXTCLOUD_SERVER=${NC_FQDN}
NEXTCLOUD_AUTH_TOKEN=$TOKEN
NEXTCLOUD_INFO_APPS=true
EOF
sudo chmod 600 /etc/prometheus-nextcloud-exporter.env
```

Install service for starting prometheus-nextcloud-exporter and its alerting rules

```bash
sudo install ./resources/services/prometheus-nextcloud-exporter.service /etc/systemd/system
sudo systemctl daemon-reload
sudo systemctl enable prometheus-nextcloud-exporter.service
sudo systemctl start prometheus-nextcloud-exporter.service
sudo install --mode=644 ./resources/prometheus/nextcloud-exporter.yml /etc/prometheus/alerts.d
```

Add a section to the scrape_configs section of Prometheus and reload:

```bash
sudo tee -a /etc/prometheus/prometheus.yml <<EOF
  - job_name: 'nextcloud'
    static_configs:
      - targets: ['$(hostname):9205']
EOF
sudo systemctl reload prometheus
```

Add the dashboard with ID 20716 to Grafana.