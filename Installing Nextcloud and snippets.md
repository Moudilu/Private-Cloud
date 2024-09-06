# Nextcloud setup on QNAP NAS

Reference: https://github.com/nextcloud/all-in-one#how-to-use-this

## IPv6 for Docker enabled

... according to https://github.com/nextcloud/all-in-one/blob/main/docker-ipv6-support.md

Unique local IPv6 prefix generated with https://unique-local-ipv6.com/

`/etc/docker/daemon.json`:

```
{
  "ipv6": true,
  "fixed-cidr-v6": "fd0e:ed26:bf36::/64",
  "experimental": true,
  "ip6tables": true
}
```

Restart

Create network with `sudo docker network create --subnet="fd0e:ed26:bf36::/64" --driver bridge --ipv6 nextcloud-aio`

Check IPv6 is enabled with `sudo docker network inspect nextcloud-aio | grep EnableIPv6`

## Create docker container

With data in separate folder and hardware transcoding enabled

```bash
docker run \
--init \
--sig-proxy=false \
--name nextcloud-aio-mastercontainer \
--restart always \
--publish 80:80 \
--publish 8080:8080 \
--publish 8443:8443 \
--volume nextcloud_aio_mastercontainer:/mnt/docker-aio-config \
--volume /var/run/docker.sock:/var/run/docker.sock:ro \
--env NEXTCLOUD_DATADIR="/share/nextcloud-data" \
--env NEXTCLOUD_ENABLE_DRI_DEVICE=true \
--env NEXTCLOUD_ADDITIONAL_APKS="imagemagick bash ffmpeg libva-utils libva-vdpau-driver libva-intel-driver intel-media-driver mesa-va-gallium" \
--env AIO_COMMUNITY_CONTAINERS="memories fail2ban" \
nextcloud/all-in-one:latest
```

## Set default phone region

Since the security check complains about it, edit the config file with
`docker run -it --rm --volume nextcloud_aio_nextcloud:/var/www/html:rw alpine sh -c "apk add --no-cache nano && nano /var/www/html/config/config.php"`
and add the line `'default_phone_region' => 'CH',`