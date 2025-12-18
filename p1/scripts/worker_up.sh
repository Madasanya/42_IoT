#!/bin/bash
set -e

SSH_DIR=/home/vagrant/.ssh
SHARED=/vagrant_shared
USER=k3s-admin
SERVER_IP=192.168.56.110

# Create non-root user
echo "Creating user $USER"
adduser -D -s /bin/bash $USER
echo "Add $USER to sudoers"
echo "$USER ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/$USER

# Create .ssh folder for the user
echo "Creating .ssh folder for $USER"
mkdir -p /home/$USER/.ssh
chmod 700 /home/$USER/.ssh
chown $USER:$USER /home/$USER/.ssh

# Generate SSH key for non-root user if it doesn't exist
if [ ! -f /home/$USER/.ssh/id_rsa ]; then
  sudo -u $USER ssh-keygen -t rsa -b 4096 -N "" -f /home/$USER/.ssh/id_rsa
fi

# Copy worker's public key to shared folder for server
cp /home/$USER/.ssh/id_rsa.pub $SHARED/worker_id_rsa.pub
chmod 644 $SHARED/worker_id_rsa.pub


