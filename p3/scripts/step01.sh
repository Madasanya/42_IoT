#!/bin/bash

# Make setup script executable and run it to install prerequisites
# Verification commands to confirm installations
# after creating setup.sh
chmod +x ./setup.sh
bash ./setup.sh
docker --version
k3d --version
kubectl version --client
argocd version --client