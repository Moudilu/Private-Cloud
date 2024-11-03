# Install Ubuntu Server

## Installation

Update BIOS, set desired settings. For Dell, find the Service Tag in the BIOS, find latest BIOS on their support website. Deactivate the lid switch. If this option is not available, a workaround in the OS must be found (maybe the lid options in `/etc/UPower/UPower.conf`).

Download latest Ubuntu LTS Server, for which CIS Benchmark and Ubuntu Security Guide exists (22.04 at the time of writing), flash to USB disk with dd.

Boot from the USB stick with network cable attached, start installation process

Create the following logical volumes, with suggested capacities on a 4TB drive:

- /, 25G
- /tmp, 10G
- /srv/media, 700G
- /srv/nc-bkp, 1.3T
- /srv/nc-data, 1.3T
- /var/lib/docker, 50G

Activate Ubuntu Pro, install OpenSSH server and no additional packages

Update

## SSH Authentication

`ssh-copy-id -i my-key-file.pub <USER>@<HOST>`

In `/etc/ssh/sshd_config.d/50-cloud-init.conf` on the server, set password authentication to no, `sudo systemctl restart ssh`.

## Set the screentimeout

In the file `/etc/default/grub`, to the parameter `GRUB_CMDLINE_LINUX_DEFAULT` add the value `consoleblank=60`and then run `sudo update-grub`. This kernel option turns off the screen after 60s.

## Stresstest

To test your hardware, install stress-ng. Run `tmux`, enter the command `stress-ng --sequential 0 --exclude dev --oom-avoid --verify -t 45s | tee stress-ng.log`. This starts each of the ~330 stress tests after each other for 45s each (i. e. total about 4h), of each the number of cpu instances. Exclude the test dev, which brought my Dell 5420 to freeze. Verifies, watch that it doesn't report failed tests.

Hit `Ctrl + B, D` to detach the session, `tmux attach` to reconnect to the session.

Observe output with `tail -f stress-ng.log`.

## Benchmarking

If you wish so, you can run Phoronix test suite for benchmarking your server. Find the latest `.deb` package on https://github.com/phoronix-test-suite/phoronix-test-suite/releases/latest, download it with `wget`.

Install with 

```bash
sudo dpkg -i phoronix*.deb
sudo apt-get install -f
sudo apt install -y php-cli zip build-essential libevent-dev libpcre++-dev dh-autoreconf cmake cmake-data npm sysbench erlang-base default-jre libuuidm-ocaml-dev libexpat1-dev uuid-dev libcurses-ocaml-dev libcurl4-openssl-dev libgmock-dev libmozjs-78-dev liblz4-dev libgflags-dev bison flex mesa-utils vulkan-tools apt-file libzstd-dev lib-readline-dev erlang-dev libbz2-dev php-gd 

# Link install folder to place with a lot! of free space
sudo install -o $(id -u) -g $(id -g) -d /srv/nc-data/phoronix-test-suite
ln -s /srv/nc-data/phoronix-test-suite ~/.phoronix-test-suite 
```

In case you have already applied the CIS security profile you need to make `/tmp` executable temporarily with `sudo mount -o remount,exec /tmp`. You can undo this with `sudo mount -o remount,noexec /tmp`, or it will be fixed on the next boot.

Now the system should be ready to run the whole `pts/server` test suite. However, this takes around two weeks. The following tests should be more than enough, takes 3.5h on my machine.

Run test with

```bash
phoronix-test-suite batch-setup
phoronix-test-suite batch-benchmark pts/apache pts/openssl pts/redis
```

A comparison between two systems can be done by 

```bash
phoronix-test-suite merge-results <results name>
phoronix-test-suite compare-results-two-way <merge results name>
```

Export results with 

```bash
phoronix-test-suite result-file-to-[pdf|html] <results name>
```

The result names are listed if you omit it.

Cleanup
```bash
sudo apt --autoremove purge phoronix-test-suite php-cli zip build-essential libevent-dev libpcre++-dev dh-autoreconf cmake cmake-data npm sysbench erlang-base default-jre libuuidm-ocaml-dev libexpat1-dev uuid-dev libcurses-ocaml-dev libcurl4-openssl-dev libgmock-dev libmozjs-78-dev liblz4-dev libgflags-dev bison flex mesa-utils vulkan-tools apt-file libzstd-dev lib-readline-dev erlang-dev libbz2-dev php-gd 
rm -rf /srv/nc-data/phoronix-test-suite
rm ~/.phoronix-test-suite
```

I am not entirely confident that everything has been cleaned away but nothing broken, you might want to start the installation all over at this point.

## Check set timezone

Check with `cat /etc/timezone`, set with `sudo timedatectl set-timezone Europe/Zurich`

## Add environment variable with email address

Add an environment variable with the email address where you want to receive server notifications etc. It will be used to configure files lateron.

```bash
echo "Enter email address"
read ADMIN_EMAIL
export ADMIN_EMAIL="${ADMIN_EMAIL}"
tee -a ~/.profile <<EOF

# This is the system administrators email address
ADMIN_EMAIL="${ADMIN_EMAIL}"
EOF
```

## Set default editor

`sudo update-alternatives --config editor`

## Alias for batterycheck

For a convenient check of the battery status, install the following alias:

`echo 'alias battery="upower -i /org/freedesktop/UPower/devices/battery_BAT0"' >> ~/.bash_aliases`

## Clone this repository

To be able to copy some files, you have to clone this repository to your server. Remember to remove it after you are done.

```bash
git clone https://github.com/Faebu93/Private-Cloud.git ~/Private-Cloud
```

## Install docker

TODO: Maybe just use packages docker.io, docker-compose and docker-buildx from the official repositories instead: https://packages.ubuntu.com/search?keywords=docker&searchon=names&suite=jammy&section=all

Follow https://docs.docker.com/engine/install/ubuntu/#install-using-the-repository

## Apply CIS security profile

Following [this](https://ubuntu.com/security/certifications/docs/2204/disa-stig/installation) guide

```shell
sudo apt update
sudo apt install ubuntu-advantage-tools
sudo ua enable usg
sudo apt install usg
```

When a new security guide version is released, regenerate the tailoring file with `sudo usg generate-tailoring cis_level1_server tailor.xml`, redisable the rules at the top of the old tailor.xml.

Audit with `sudo usg audit --html-file /tmp/report.html --tailoring-file ./resources/tailor.xml`.

To look at the report you need to change the permissions. Remember to delete the outputs afterwards!

See the script to apply the fixes with `sudo usg generate-fix --tailoring-file /tmp/tailor.xml --output /tmp/fix.sh`

Apply the configuration with `sudo usg fix --tailoring-file /tmp/tailor.xml`, then reboot and audit.

### Manually fix remaining problems

After this, reboot and audit.

#### Configure nftables

Allow incoming SSH connections, deny everything else

```bash
sudo install -m 700 -d /etc/inet-filter.rules.d
sudo install --mode 600 ./resources/nftables/00-base.rules ./resources/nftables/99-ssh.rules /etc/inet-filter.rules.d
echo 'include "/etc/inet-filter.rules.d/*.rules"' | sudo tee -a /etc/nftables.conf
sudo systemctl reload nftables.service
```

See rules with `sudo nft list ruleset`.

#### Limit users SSH Access

Allow only the principal server user to login via SSH.

```bash
echo "AllowUsers ${USER}" | sudo tee /etc/ssh/sshd_config.d/10-restrict-users.conf
```

## Configure IP addresses

The setup of your IP configuration might differ depending on your setup. You should already have been assigned an IPv4 address via DHCP. You might want to make it permanent in your router setting, or make this assignment static by deleting the file `/etc/netplan/00-installer-config.yaml` and adding a similar file like below for IPv4.

Dynamic IPv6 assignments have been disabled by a rule in the CIS security profile, since listening to and applying IPv6 router announcements might be a security risk. The below snippet adds a static IPv6 address. You have to find your IPv6 prefix in your router (if you have any) and pick an address from this range.

```bash
read -p "Your static IPv6 address: " IPV6_ADDRESS
read -p "IPv6 address of your router within your network: " IPV6_ROUTER
sudo tee /etc/netplan/50-ipv6-manual-config.yaml <<EOF
network:
  version: 2
  ethernets:
    enp0s31f6:
      critical: true
      addresses:
        - "$IPV6_ADDRESS/128"
      routes:
        - to: default
          via: $IPV6_ROUTER
EOF
sudo netplan try
```

## Configure Shutdown on low battery

Edit `/etc/UPower/UPower.conf`.

Change the `CriticalPowerAction` at the end to `PowerOff`. Also raise the `PercentageAction` (or `TimeAction` if `UsePercentageForPolicy` is false), e.g. to 8 or so.

Restart with `sudo systemctl restart upower`.

It is recommended to test this by setting the value to some value that will occur soon.

## Reboot every week

Reboots the system every Sunday at 5am.

```bash
sudo install ./resources/services/reboot.timer /etc/systemd/system
sudo systemctl daemon-reload
sudo systemctl enable reboot.timer
```
