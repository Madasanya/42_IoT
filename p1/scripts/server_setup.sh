#!/bin/bash

set -e

SHARED=/vagrant_shared
USER=k3s-admin


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
