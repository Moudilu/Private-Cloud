# Private Cloud - Installing Nextcloud on a hardened Ubuntu Server

## Introduction

This repository contains instructions on how to set up a server with Ubuntu and the awesome [Nextcloud](https://nextcloud.com). It is built with security and reliability as primary goals.

It was originally installed on a repurposed laptop and intended for home use. While this repo serves primarily as the documentation of the setup of the author, it should be applicable by a wider range of users without a lot of modifications.

## Features

The main features/goals of the installed system are the following

- Ubuntu server system, hardened with CIS level 1 server profile
- a Nextcloud instance using its [AIO setup](https://github.com/nextcloud/all-in-one)
- monitoring and alerting with [Prometheus](https://prometheus.io/), visualization with [Grafana](https://grafana.com/grafana/)
- encrypted backups with [borg](https://www.borgbackup.org/), stored on the public cloud of your choice with [rclone](https://rclone.org/)
- nftables firewall
- reliable and automated 3-2-1 backup strategy
- low maintenance effort

## Contribution

If you encounter issues or have suggestions for improvement, feel encouraged to submit them via pull requests or issues, for the benefit of others!

## Instructions

Be aware of the following things:

- usually you need to understand what you are currently doing, just copying and pasting might or might not work
- some of the commands (like appending some text to a file) will lead to unexpected effects when executed more than once

Follow these instructions in sequence:

1. [Install the base operating system](./01_install_os.md)
2. [Monitoring with Prometheus and Grafana](./02_monitoring.md)
3. [Install Nextcloud and backup services](./03_nextcloud.md)

It is highly recommended executing all maintenance steps indicated below now for the first time.

Congratulations, you have your own cloud running!

## Maintenance

I recommend setting up a reminder to monthly do the following things:

- plug in your external hard disk to sync your offline backup
- using the scripts [`mount-cloud-nc-bkp.sh`](scripts/mount-cloud-nc-bkp.sh) & [`mount-disc-nc-bkp.sh`](scripts/mount-disc-nc-bkp.sh), mount your backups, open and check a file you have edited recently (ensures that the backup is readable and up to date)
- log in to the nextcloud admin settings overview, check for warnings & errors in the logs
- log in to your server via SSH, verify no evil warnings show up in the login welcome message, ideally do a security audit with `sudo usg audit --html-file /tmp/report.html --tailoring-file /opt/private-cloud/tailor.xml`, consider also regenerating the tailoring file with the snippet in [Apply CIS security profile](./01_install_os.md#apply-cis-security-profile).
- optionally, check the consistency of one of your backups with [borg check](https://borgbackup.readthedocs.io/en/stable/usage/check.html) (takes a lot of time, depending on the size of your backup): `borg check --verify-data <path to local, cloud or external disk backup>`

## FAQ

### Running Nextcloud occ commands

As pointed out in the [AIO Readme](https://github.com/nextcloud/all-in-one?tab=readme-ov-file#how-to-run-occ-commands):

```bash
sudo docker exec --user www-data -it nextcloud-aio-nextcloud php occ your-command
```

### Examining the Nextcloud database

Run the following line to run a temporary instance of pgadmin:

```bash
sudo docker run --network nextcloud-aio -p 8012:80 -e PGADMIN_DEFAULT_EMAIL=dummy@dummy.net -e PGADMIN_DEFAULT_PASSWORD=dummy dpage/pgadmin4
```

Then, tunnel the port through to your local development machine to bypass the firewall with (on your development computer):

```bash
ssh -L 8012:localhost:8012 <user>@<server>
```

You then can access pgadmin at http://localhost:8012 and add a server according to the instructions in https://github.com/nextcloud/all-in-one?tab=readme-ov-file#phpmyadmin-adminer-or-pgadmin

## Guarantees

None. _You_ are responsible for what you do on your system, so think and try to understand what is done and why before you type, as always. See the attached [license](LICENSE).