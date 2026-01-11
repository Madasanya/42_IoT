#!/bin/bash

# Update package manager and install required dependencies
# curl: needed to download K3s and kubectl binaries
# iptables: needed to configure port forwarding for Traefik
apk update
apk add curl iptables

# Install K3s in server mode with specific network configuration
# --node-ip: sets the IP address for the node (host-only network interface)
# --advertise-address: IP address advertised to other nodes and external clients
# --write-kubeconfig-mode 644: makes kubeconfig readable by non-root users for easier access
curl -sfL https://get.k3s.io | INSTALL_K3S_EXEC="server --node-ip=192.168.56.110 --advertise-address=192.168.56.110 --write-kubeconfig-mode 644" sh -

# Wait for K3s to be fully initialized and generate its configuration file
# The config file is needed to interact with the cluster using kubectl
echo "Waiting for K3s to be ready..."
timeout=120
while [ ! -f /etc/rancher/k3s/k3s.yaml ] && [ $timeout -gt 0 ]; do
  sleep 2
  timeout=$((timeout - 2))
done

if [ ! -f /etc/rancher/k3s/k3s.yaml ]; then
  echo "Error: K3s config file not created after waiting"
  exit 1
fi

# Set up kubectl configuration for the vagrant user
# K3s stores its config in /etc/rancher/k3s/k3s.yaml, but kubectl looks in ~/.kube/config
# Copy and set appropriate permissions so the vagrant user can run kubectl commands without sudo
mkdir -p /home/vagrant/.kube
cp /etc/rancher/k3s/k3s.yaml /home/vagrant/.kube/config
chown vagrant:vagrant /home/vagrant/.kube/
chown vagrant:vagrant /home/vagrant/.kube/config
chmod 644 /home/vagrant/.kube/config

# Export KUBECONFIG environment variable and persist it in .bashrc
# This tells kubectl where to find the configuration file
export KUBECONFIG=/home/vagrant/.kube/config
echo "export KUBECONFIG=/home/vagrant/.kube/config" >> /home/vagrant/.bashrc

# Download and install kubectl binary manually
# This ensures we have the standard kubectl command available
# Also create a shorter alias 'k' for convenience
curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl
ln -s /usr/local/bin/kubectl /usr/local/bin/k

# Wait for Traefik ingress controller to be deployed and running
# K3s includes Traefik by default, but it takes time to start
# Traefik is needed to route external HTTP traffic to our applications
echo "Waiting for Traefik service..."
timeout=120
while ! kubectl get svc traefik -n kube-system &>/dev/null; do
  if [ $timeout -le 0 ]; then
    echo "Timeout waiting for Traefik service"
    exit 1
  fi
  sleep 2
  timeout=$((timeout - 2))
done
echo "Traefik service is ready"

# Configure port forwarding from port 80 to Traefik's NodePort
# Traefik runs on a high NodePort (e.g., 30000-32767), but we want to access apps on standard port 80
# iptables redirects incoming traffic on port 80 (eth1 interface) to Traefik's actual port
# This allows accessing apps via http://192.168.56.110 without specifying a port number
TRAEFIK_HTTP_PORT=$(kubectl get svc traefik -n kube-system -o jsonpath='{.spec.ports[?(@.name=="web")].nodePort}')
if [ -n "$TRAEFIK_HTTP_PORT" ]; then
  echo "Configuring iptables to redirect port 80 to Traefik port $TRAEFIK_HTTP_PORT"
  iptables -t nat -A PREROUTING -i eth1 -p tcp --dport 80 -j REDIRECT --to-port $TRAEFIK_HTTP_PORT
fi

# Deploy all application manifests from the shared confs directory
# This includes deployments, services, ingress rules, configmaps, and persistent volumes
kubectl apply -f /home/vagrant/confs/