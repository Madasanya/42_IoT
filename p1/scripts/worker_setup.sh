#!/bin/bash
set -e

SHARED=/vagrant_shared
USER=k3s-admin
SERVER_IP=192.168.56.110

whoami
echo "Waiting for server ... "
while [ ! -f $SHARED/server_ready.txt ]; do
  sleep 2
done

echo "Removing server ready flag file"
sudo rm -f $SHARED/server_ready.txt

#echo "Changing to $USER."
#sudo -i -u $USER

echo "SSHing K3S token."
K3S_TOKEN=$(ssh -o StrictHostKeyChecking=no $USER@$SERVER_IP "sudo cat /var/lib/rancher/k3s/server/node-token")
echo "Installing K3S ... "
curl -sfL https://get.k3s.io | sudo K3S_URL=https://$SERVER_IP:6443 K3S_TOKEN=$K3S_TOKEN sh -

