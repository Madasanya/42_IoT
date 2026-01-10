#!/bin/bash

sudo apt update

###################### P1 ###############
# Install curl
sudo apt install -y curl

# Add HashiCorp GPG Key and Repository for vagrant and install vagrant
if ! command -v vagrant &> /dev/null; then
    curl -fsSL https://apt.releases.hashicorp.com/gpg | sudo gpg --dearmor -o /usr/share/keyrings/hashicorp-archive-keyring.gpg
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com $(grep -oP '(?<=UBUNTU_CODENAME=).*' /etc/os-release || lsb_release -cs) main" | sudo tee /etc/apt/sources.list.d/hashicorp.list
    sudo apt update && sudo apt install -y vagrant
    # Remove HashiCorp keyring and list after install
    sudo rm -f /usr/share/keyrings/hashicorp-archive-keyring.gpg
    sudo rm -f /etc/apt/sources.list.d/hashicorp.list
else
    echo "Vagrant is already installed"
fi

# Install virtualbox
sudo apt install -y virtualbox

# Install ansible
sudo apt install -y ansible

#################### P2 ################

# Install kubectl
if ! command -v kubectl &> /dev/null; then
    curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
    curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl.sha256"
    if echo "$(cat kubectl.sha256)  kubectl" | sha256sum --check; then
        # If hash matches, install kubectl
        sudo install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl
        echo "kubectl installed successfully."
        rm -f kubectl kubectl.sha256
        sudo ln -s /usr/local/bin/kubectl /usr/local/bin/k
    else
        # If hash does not match, print an error and exit
        echo "Error: The checksum of kubectl does not match the expected value!"
        rm kubectl kubectl.sha256 # Clean up the downloaded files
        exit 1
    fi
fi

# Rerouting
# The line to add
LINE="192.168.56.110 app1.com app2.com app3.com"

# Path to hosts file
HOSTS_FILE="/etc/hosts"

# Check if the exact line already exists (using grep -Fx for fixed string and exact line match)
if grep -Fx "$LINE" "$HOSTS_FILE" > /dev/null; then
    echo "The line $LINE  already exists in $HOSTS_FILE. No changes made."
else
    # Append the line (requires sudo for /etc/hosts)
    echo "$LINE" | sudo tee -a "$HOSTS_FILE" > /dev/null
    echo "$LINE added to $HOSTS_FILE."
fi

#################### P3 ################

# Install Docker and prerequisites (prerequisite for K3d)
if ! command -v docker &> /dev/null; then
    sudo apt install -y ca-certificates gnupg lsb-release
    sudo mkdir -p /etc/apt/keyrings
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
    sudo apt update && sudo apt install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
    sudo usermod -aG docker $USER  # Add user to docker group (log out/in to apply)
    # Remove Docker keyring and list after install
    sudo rm -f /etc/apt/keyrings/docker.gpg
    sudo rm -f /etc/apt/sources.list.d/docker.list
else
    echo "Docker already installed"
fi

# Install K3d (latest version: v5.7.4 or higher; check https://k3d.io for updates)
if ! command -v k3d &> /dev/null; then
    curl -fsSL https://raw.githubusercontent.com/k3d-io/k3d/main/install.sh | bash
else
    echo "k3d already installed"
fi

# Install Argo CD CLI (latest via brew or direct download; assume Linux, use curl for portability)
if ! command -v argocd &> /dev/null; then
    VERSION=$(curl --silent "https://api.github.com/repos/argoproj/argo-cd/releases/latest" | grep '"tag_name"' | sed -E 's/.*"([^"]+)".*/\1/')
    curl -fsSL -o argocd-linux-amd64 https://github.com/argoproj/argo-cd/releases/download/$VERSION/argocd-linux-amd64
    sudo install -m 755 argocd-linux-amd64 /usr/local/bin/argocd
    rm argocd-linux-amd64
else
    echo "argocd already installed"
fi

################### BONUS ##############

# Install Helm (latest v3.x, necessary for gitlab)
if ! command -v helm &> /dev/null; then
    curl -fsSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
else
    echo "helm already installed"
fi
