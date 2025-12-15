#!/bin/bash

# Create a K3d cluster named "mycluster" with default settings
# Expose port 8080 on the host to access applications via the load balancer
# Set the kubeconfig context to the new cluster
# Verification commands to confirm cluster creation and status

sudo k3d cluster create mycluster --port 8080:80@loadbalancer  # Exposes port 8080 on host for app access
sudo k3d kubeconfig merge mycluster --kubeconfig-switch-context

sudo k3d cluster list #(should show mycluster running).
sudo kubectl get nodes #(should show one ready node).
sudo kubectl get pods -A #(system pods like Traefik should be running).