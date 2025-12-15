#!/bin/bash

# Create the Argo CD namespace and install:
sudo kubectl create namespace argocd
sudo kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml

# Wait for pods to start
sudo kubectl wait --for=condition=Ready pods --all -n argocd --timeout=300s

# Forward the port 
sudo kubectl port-forward svc/argocd-server -n argocd 8081:443 #(access at https://localhost:8081).
#Get initial password (manually)
#sudo argocd admin initial-password -n argocd #(login as admin).
#Change password (best to skip and do in web UI)
#sudo argocd account update-password

# Verify installation (manually)
# sudo kubectl get pods -n argocd #(all pods ready, e.g., argocd-server, argocd-application-controller).