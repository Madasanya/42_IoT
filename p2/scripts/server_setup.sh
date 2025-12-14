#!/bin/bash

sudo apk update
sudo apk add curl iptables
curl -sfL https://get.k3s.io | sudo INSTALL_K3S_EXEC="server --tls-san 192.168.56.110 --write-kubeconfig-mode 644" sh - # Server mode

# Wait for K3s to be ready and config file to be created
echo "Waiting for K3s to be ready..."
timeout=30
while [ ! -f /etc/rancher/k3s/k3s.yaml ] && [ $timeout -gt 0 ]; do
  sleep 2
  timeout=$((timeout - 2))
done

if [ ! -f /etc/rancher/k3s/k3s.yaml ]; then
  echo "Error: K3s config file not created after waiting"
  exit 1
fi

mkdir -p /home/vagrant/.kube
sudo cp /etc/rancher/k3s/k3s.yaml /home/vagrant/.kube/config
sudo chown vagrant:vagrant /home/vagrant/.kube/
sudo chown vagrant:vagrant /home/vagrant/.kube/config
sudo chmod 644 /home/vagrant/.kube/config
export KUBECONFIG=/home/vagrant/.kube/config
echo "export KUBECONFIG=/home/vagrant/.kube/config" >> /home/vagrant/.bashrc
curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
sudo install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl
sudo ln -s /usr/local/bin/kubectl /usr/local/bin/k

# Wait for Traefik service to be ready
echo "Waiting for Traefik service..."
timeout=60
while ! kubectl get svc traefik -n kube-system &>/dev/null; do
  if [ $timeout -le 0 ]; then
    echo "Timeout waiting for Traefik service"
    exit 1
  fi
  sleep 2
  timeout=$((timeout - 2))
done
echo "Traefik service is ready"

# Get Traefik's NodePort and redirect port 80 to it
TRAEFIK_HTTP_PORT=$(kubectl get svc traefik -n kube-system -o jsonpath='{.spec.ports[?(@.name=="web")].nodePort}')
if [ -n "$TRAEFIK_HTTP_PORT" ]; then
  echo "Configuring iptables to redirect port 80 to Traefik port $TRAEFIK_HTTP_PORT"
  sudo iptables -t nat -A PREROUTING -i eth1 -p tcp --dport 80 -j REDIRECT --to-port $TRAEFIK_HTTP_PORT
fi

kubectl apply -f /home/vagrant/configs/