#!/bin/bash

########### STEP 1: PREREQUISITES INSTALLATION ###########
# Make setup script executable and run it to install prerequisites
# Verification commands to confirm installations
# after creating setup.sh
chmod +x ./setup.sh
bash ./setup.sh
docker --version
k3d --version
kubectl version --client
argocd version --client

########### STEP 2: K3d CLUSTER CREATION ###########
# Create K3d cluster 
chmod +x ./clusterCreate.sh
bash ./clusterCreate.sh

sudo k3d cluster list #(should show dbanfiC running).
sudo kubectl get nodes #(should show one ready node).
sleep 45 # Wait a moment for system pods to start
sudo kubectl get pods -A #(system pods like Traefik should be running).

########### STEP 3: ArgoCD INSTALLATION ###########

# Install ArgoCD into the cluster
chmod +x ./argocdInstall.sh
bash ./argocdInstall.sh

# Verify installation
sleep 5
sudo kubectl get pods -n argocd #(all pods ready, e.g., argocd-server, argocd-application-controller).

########### STEP 4: DEPLOY APPLICATION VIA ArgoCD ###########
chmod +x ./argocdDeploy.sh
bash ./argocdDeploy.sh
