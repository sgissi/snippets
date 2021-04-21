#!/bin/bash

usage() {
  echo "Usage: $0 id name ip-suffix [ram] [disk]"
  exit 1
}

[[ $# -lt 3 ]] && usage

vmid=$1
name=$2
ipsuffix=$3

[[ -z $4 ]] && ram=2048 || ram=$4
[[ -z $5 ]] && disk=40G || disk=$5

iplan="x.x.x.$ipsuffix/24"
gw=x.x.x.1
ipsan="x.x.x.$ipsuffix/24"

# Validate
[ ! -z "$(find /etc/pve/nodes -name $vmid.conf)" ] && { echo "Id $vmid already in use"; exit 1; }

echo Building VM $vmid - Hostname:$name LAN:$iplan SAN:$ipsan RAM:${ram}Kb Disk:$disk

echo "Check for latest Debian 10 image"
latest=$(curl -s https://cloud.debian.org/images/cloud/buster/| grep "a href=\"202" | sed -e 's%^.*a href=\"%%g;s%/\".*%%g' | sort -n | tail -1)
[ ! -f debian-10-genericcloud-amd64-$latest.qcow2 ] && (echo "Downloading..."; curl -O https://cloud.debian.org/images/cloud/buster/$latest/debian-10-genericcloud-amd64-$latest.qcow2) || echo "Already have latest"
echo "Check integrity"
s512=$(curl -s https://cloud.debian.org/images/cloud/buster/$latest/SHA512SUMS | grep debian-10-genericcloud-amd64-$latest.qcow2)
echo $s512 | sha512sum - -c
[[ $? -ne 0 ]] && { echo "Integrity check failed, remove image to redownload"; exit 1; }
cat << EOF > admin.pub
ssh-rsa [redacted]
EOF

qm create $vmid --name $name --memory $ram --cores 2 --net0 virtio,bridge=vmbr0 --net1 virtio,bridge=vmbr1 --ipconfig0 ip=$iplan,gw=$gw --ipconfig1 ip=$ipsan --ciuser admin --sshkey ./admin.pub --ide2 local:cloudinit --boot c --bootdisk scsi0 --serial0 socket --vga serial0 --scsihw virtio-scsi-pci
[[ $? -ne 0 ]] && { echo "Error creating VM"; exit 1; }
qm importdisk $vmid debian-10-genericcloud-amd64-$latest.qcow2 local-lvm
[[ $? -ne 0 ]] && { echo "Error importing disk"; exit 1; }
qm set $vmid -scsi0 local-lvm:vm-$vmid-disk-0
[[ $? -ne 0 ]] && { echo "Error enabling disk"; exit 1; }
qm resize $vmid scsi0 $disk
[[ $? -ne 0 ]] && { echo "Error resizing disk"; exit 1; }
