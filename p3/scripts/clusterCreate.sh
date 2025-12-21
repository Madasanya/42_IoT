#!/bin/bash

# Create a K3d cluster named "dbanfiC" with default settings
# Expose port 8080 on the host to access applications via the load balancer
# Set the kubeconfig context to the new cluster
# Verification commands to confirm cluster creation and status

sudo k3d cluster create dbanfiC --port 8080:80@loadbalancer --k3s-arg "--node-name=dbanfiS@server:0"  # Exposes port 8080 on host for app access
sudo k3d kubeconfig merge dbanfiC --kubeconfig-switch-context

