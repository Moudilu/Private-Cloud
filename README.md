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

### Upgrade the Ubuntu release

Perform these steps:

- If possible, pause synchronization on all connected Nextcloud client apps, to reduce the risk of data loss if something goes severely wrong.
- Stop Nextcloud using its AIO admin interface on http://\<your server\>:8080 and perform a Nextcloud backup.   
You also might want to check the integrity of your backup (either using the provided functionality of the AIO interface or by using `borg check` on some other computer). This might take very long (order of hours, scales with the size of your backup), but it might be a good idea to check the integrity from time to time, to be sure the whole backup can be restored in case of failure.
- Plug in your external backup disc and wait for the backup to complete.
- Fully update your system with `sudo apt update && sudo apt upgrade`
- You have to remount `/tmp` without `noexec` for the release upgrade to work: `sudo mount /tmp -o remount,exec`. This should be automatically corrected after the next reboot.
- Start a new session with `tmux`, to be sure the terminal session does not disconnect while SSH is upgraded. You can exit the session with `Ctrl+B D`, and reopen a running session with `tmux attach`.
- Upgrade the system using `sudo do-release-upgrade` and follow the guide.  
If you get asked if you want to keep your locally edited configuration or the package maintainers version and have no idea what the change is and who mad it, it was probably the Ubuntu Security Guide while applying the CIS security profile. In these cases, install the package maintainers version (choose `Y`) since the configuration can be reapplied by USG later on. Some configuration though, like for nftables, Prometheus or the alertmanager, should be kept (choose `N`).
- Reboot
- Reenable/update any extra package repositories
  - Docker:  
    
    ```sh
    echo \
    "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu \
    $(. /etc/os-release && echo "${UBUNTU_CODENAME:-$VERSION_CODENAME}") stable" | \
    sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
    ```

  - Grafana:  

    ```sh
    echo "deb [signed-by=/etc/apt/keyrings/grafana.gpg] https://apt.grafana.com stable main" | sudo tee /etc/apt/sources.list.d/grafana.list
    sudo chmod o+r /etc/apt/sources.list.d/grafana.list
    ```

  - Check under `/etc/apt/sources.list.d/*` if any other repository requiring to be updated, update any old version codes. `ubuntu-cis...` will be updated automatically.
- Do again `sudo apt update && sudo apt upgrade` and reboot again.
- Perform a security audit using the steps in [Apply automatic fixes](01_install_os.md#apply-automatic-fixes) (including installation of the package), reboot, [audit](01_install_os.md#audit) and fix remaining issues manually.
- Check that all systems are working normally:
  - log in to your Grafana interface and look at the Node dashboard of your server
  - if you have not yet received any alert from Prometheus, make sure you get them by triggering some alert for testing
  - Create another Nextcloud backup in its AIO interface and check with `sudo journalctl -fu backup-cloud` that it gets synchronized to the cloud.
  - Restart the Nextcloud containers, login to your Nextcloud. In case you stopped them, restart the sync clients.

References:

- https://documentation.ubuntu.com/server/how-to/software/upgrade-your-release/index.html

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