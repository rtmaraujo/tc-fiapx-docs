#!/bin/bash
# Cloud-init da instancia k3s (Ubuntu 24.04). Executado como root no primeiro boot.
set -euxo pipefail
exec > >(tee -a /var/log/fiapx-bootstrap.log) 2>&1

# Swap ajuda os JVMs em nos pequenos (t3.large = 8 GB).
if [ ! -f /swapfile ]; then
  fallocate -l 4G /swapfile || dd if=/dev/zero of=/swapfile bs=1M count=4096
  chmod 600 /swapfile
  mkswap /swapfile
  swapon /swapfile
  echo '/swapfile none swap sw 0 0' >> /etc/fstab
fi

PUBLIC_IP=$(curl -fsS http://169.254.169.254/latest/meta-data/public-ipv4)

apt-get update -y
apt-get install -y curl ca-certificates

curl -sfL https://get.k3s.io | INSTALL_K3S_EXEC="server --write-kubeconfig-mode 644 --tls-san ${PUBLIC_IP} --tls-san 127.0.0.1" sh -

echo "k3s pronto em $(date -Is), ip publico ${PUBLIC_IP}" > /var/log/fiapx-ready
