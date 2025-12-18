#!/bin/bash

set -e

SSH_DIR=/home/vagrant/.ssh
SHARED=/vagrant_shared
USER=k3s-admin

# Create non-root user
adduser -D -s /bin/bash $USER
echo "$USER ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/$USER
# Unlock the user account and set an empty password
echo "$USER:" | sudo chpasswd

sudo -i -u $USER

curl -sfL https://get.k3s.io | sudo INSTALL_K3S_EXEC="server --tls-san 192.168.56.110" sh -

# Create .ssh folder for the user
mkdir -p /home/$USER/.ssh
chmod 700 /home/$USER/.ssh
touch /home/$USER/.ssh/authorized_keys
chmod 600 /home/$USER/.ssh/authorized_keys
chown $USER:$USER /home/$USER/.ssh -R

echo "Waiting for worker ... "
#Wait for worker to create public key
while [ ! -f $SHARED/worker_id_rsa.pub ]; do
  sleep 2
done

echo "Changing to $USER user."
sudo -i -u $USER

echo "Add worker's public key to server's authorized_keys"
# Add worker's public key to server's authorized_keys
cat $SHARED/worker_id_rsa.pub >> /home/$USER/.ssh/authorized_keys

echo "Touched server ready flag file"
touch $SHARED/server_ready.txt
sleep 10
echo "Server setup complete."
