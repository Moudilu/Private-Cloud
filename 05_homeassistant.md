# Add Home Assistant VM

A KVM VM is added. A container setup is also possible, much more tedious and less supported.

## Install Home Assistant OS

```bash
# Check that your CPU can run VMs
egrep -c '(vmx|svm)' /proc/cpuinfo
# Check that you can use KVM acceleration
kvm-ok

sudo apt install -y qemu-kvm libvirt-daemon-system libvirt-clients bridge-utils ovmf virtinst

# Enable libvirtd to directly use the Ubuntu lvm volumes as storage backend
sudo virsh pool-define-as lvm-pool logical --source-name ubuntu-vg --target /dev/ubuntu-vg
sudo virsh pool-start lvm-pool
sudo virsh pool-autostart libvirt-lvm
# Create a volume for Homeassistant
sudo virsh vol-create-as --pool lvm-pool --name homeassistant --capacity 50G --format raw

# Download and verify the image
DL_DIR="$(mktemp -d)"
HAOS_VERSION="$(curl -s https://api.github.com/repos/home-assistant/operating-system/releases/latest | jq -r '.tag_name')"
HAOS_DOWNLOAD_URL="https://github.com/home-assistant/operating-system/releases/download/${HAOS_VERSION}"
# run the download stuff in a subshell
(
  cd "${DL_DIR}"
  chmod 755 "${DL_DIR}" && \
  wget "${HAOS_DOWNLOAD_URL}/haos_ova-${HAOS_VERSION}.qcow2.xz" "${HAOS_DOWNLOAD_URL}/SHA256SUMS" "${HAOS_DOWNLOAD_URL}/SHA256SUMS.sigstore.json" && \
  chmod 644 haos_ova-${HAOS_VERSION}.qcow2.xz SHA256SUMS SHA256SUMS.sigstore.json && \
  # verify signature of the checksums
  sudo docker run --rm -v "${DL_DIR}:/work" -w /work ghcr.io/sigstore/cosign/cosign verify-blob \
    --bundle SHA256SUMS.sigstore.json \
    --certificate-identity-regexp "^https://github.com/home-assistant/operating-system/" \
    --certificate-oidc-issuer "https://token.actions.githubusercontent.com" \
    SHA256SUMS && \
  sha256sum --ignore-missing -c SHA256SUMS && \
  echo "Extracting image..." && unxz "haos_ova-${HAOS_VERSION}.qcow2.xz" && \
  echo "Writing image to logical volume..." && sudo qemu-img convert -f qcow2 -O raw haos_ova-${HAOS_VERSION}.qcow2 /dev/ubuntu-vg/homeassistant && \
  rm -r "$DL_DIR"
)

# Add a network bridge s.t. the VM is directly connected to the network
: ${NETWORK_INTERFACE:?Set the variable NETWORK_INTERFACE to the name of your interface to the local network and rerun the next steps}
sudo install -m 600 /dev/stdin /etc/netplan/80-br-local.yaml <<EOF
network:
  version: 2
  ethernets:
    # disable DHCP on the physical interface
    $NETWORK_INTERFACE:
      dhcp4: false
      dhcp6: false
  bridges:
    brlocal:
      dhcp4: true
      dhcp6: true
      critical: true
      interfaces:
      - $NETWORK_INTERFACE
      # explicitly clone the MAC address of the physical interface
      macaddress: "$(</sys/class/net/$NETWORK_INTERFACE/address)"
  vlans:
    # set the ifDMZ to attach to the new bridge
    ifDMZ:
      link: brlocal
EOF
sudo netplan try

# Install an isolated host-only network
cat << EOF > /tmp/isolated-net.xml
<network>
  <name>isolated</name>
  <bridge name='virbr-isolated' stp='on' delay='0'/>
  <ip address='192.168.123.1' netmask='255.255.255.0'>
    <dhcp>
      <range start='192.168.123.2' end='192.168.123.254'/>
    </dhcp>
  </ip>
</network>
EOF
sudo virsh net-define /tmp/isolated-net.xml
rm /tmp/isolated-net.xml
sudo virsh net-start isolated
sudo virsh net-autostart isolated

# Install the VM
# The command is based on https://www.home-assistant.io/installation/linux#create-and-configure-the-virtual-machine, viewed on 13.10.2026
# Changes:
# - 4 instead of 2 vcpus
# - use the lvm volume instead of the qcow file
# - the network option added
# - the backup folder and the media folder mounted
# - the autostart option added
# - don't automatically start into the console
# The hostdev option maps a USB device into the VM - use it only if you want to pass e.g. a radio dongle. Find the ID with lsusb
virt-install \
  --name haos \
  --description "Home Assistant OS" \
  --os-variant=generic \
  --ram=4096 \
  --vcpus=4 \
  --disk vol=lvm-pool/homeassistant,bus=virtio \
  --import \
  --graphics none \
  --boot uefi \
  --hostdev 10c4:ea60 \
  --network bridge=brlocal,model=virtio \
  --network network=isolated,model=virtio \
  --autostart \
  --noautoconsole
```

In your DHCP server (router), identify the VM and assign a permanent IP to it.

## Add to the local reverse proxy

In your DNS, add the entries pointing to the IP of your VM.

```bash
read -p "Enter the desired domain name for Home Assistant: " HA_FQDN
sudo install -m 644 /dev/stdin /etc/local-caddy/conf/sites-enabled/homeassistant << EOF
${HA_FQDN} {
	reverse_proxy http://192.168.123.2:8123
}
EOF
read -p "Enter the desired domain name for Music Assistant: " MA_FQDN
sudo install -m 644 /dev/stdin /etc/local-caddy/conf/sites-enabled/musicassistant << EOF
${MA_FQDN} {
	reverse_proxy http://192.168.123.2:8095
}
EOF

sudo systemctl restart local-caddy
```

Under http://<VM IP>:8123/config/network, add `192.168.123.1` to the trusted proxies, enable the additional network adapter, and set a manual IP of 192.168.123.2.

## Enable NFS access to media and backup for VM

```bash
# NFS shall be exported only on the isolated network
cat | sudo install -m 644 -D /dev/stdin /etc/nfs.conf.d/bind-address.conf << EOF
[nfsd]
host=192.168.123.1
EOF
# make sure nfs-server starts only after the interface is up
cat | sudo install -D /dev/stdin /etc/systemd/system/nfs-server.service.d/10-after-libvirtd.conf << EOF
[Unit]
After=network-online.target libvirtd.service
Wants=network-online.target

[Service]
ExecStartPre=/bin/sh -c 'while ! ip addr show dev virbr-isolated 2>/dev/null | grep -q "192.168.123.1"; do sleep 0.5; done'
EOF
# make sure relevant services have not been masked by the security profile
sudo systemctl unmask nfs-server.service rpcbind.service
sudo apt install nfs-kernel-server
sudo systemctl enable --now nfs-kernel-server
# The Homeassistant backup will go in this directory. Since the NFS server remaps the root user to nobody, it shall be owned by it
sudo install -o nobody -g nogroup -d /var/lib/homeassistant/backup
echo "/var/lib/homeassistant/backup  192.168.123.2(rw,sync,no_subtree_check,insecure)" | sudo install -m 644 -D /dev/stdin /etc/exports.d/homeassistant-backup.exports
# To the media folder, only read access is needed
echo "/srv/nc-data-no-bkp/Media  192.168.123.2(ro,sync,no_subtree_check,insecure)" | sudo install -m 644 -D /dev/stdin /etc/exports.d/homeassistant-media.exports
sudo exportfs -rav
sudo install -m 600 ./resources/nftables/40-nfs-homeassistant.rules /etc/inet-filter.rules.d
sudo nft -f /etc/inet-filter.rules.d/40-nfs-homeassistant.rules
```

## Accessing the shell of the VM

To drop into a terminal of the VM, run `virsh console haos`, then enter root (the user). The data of the apps lies under `/mnt/data/supervisor/apps/data/...` at the time of writing. To exit the console, hit Ctrl + ] on your keyboard.

## Home Assistant Backups

In Home Assistant, go to Settings > System > Backups > Set up backups. I recommend to 

- backup at 1:45 (sometime before Nextcloud AIO backups run)
- keep only one backup (since borg backup retains several versions)

Back it up to NFS, server 192.168.123.1, share `/var/lib/homeassistant/backup`.

To add the Homeassistant backup to the automatic Nextcloud backup, it is recommended to add the line `/var/lib/homeassistant/backup` to the extra backup locations in the Nextcloud AIO interface (access it via the settings page of your Nextcloud admin user). It is recommended to test the backup afterwards.
