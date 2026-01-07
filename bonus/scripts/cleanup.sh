#!/bin/bash

echo "=== Cleaning up ArgoCD Application and Resources ==="

# Stop any running port-forward processes
echo "Stopping port-forward processes..."
sudo pkill -f "kubectl port-forward svc/argocd-server" 2>/dev/null
sudo pkill -f "kubectl port-forward svc/playground-service" 2>/dev/null
sudo pkill -f "kubectl port-forward svc/gitlab-webservice" 2>/dev/null
sudo pkill -f "portForward.sh" 2>/dev/null

# Delete the ArgoCD application (step04.sh)
echo "Deleting ArgoCD application..."
sudo argocd app delete playground-app --yes 2>/dev/null || echo "ArgoCD application not found or already deleted"

# Delete the dev namespace and all its resources (step04.sh)
echo "Deleting dev namespace..."
sudo kubectl delete namespace dev --timeout=60s 2>/dev/null || echo "Namespace 'dev' not found or already deleted"

# Delete GitLab helm release first, then the namespace
echo "Uninstalling GitLab helm release..."
sudo helm uninstall gitlab -n gitlab 2>/dev/null || echo "GitLab helm release not found or already deleted"

echo "Deleting gitlab namespace..."
sudo kubectl delete namespace gitlab --timeout=60s 2>/dev/null || echo "Namespace 'gitlab' not found or already deleted"

# Uninstall ArgoCD (step03.sh)
echo "Uninstalling ArgoCD..."
sudo kubectl delete -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml 2>/dev/null || echo "ArgoCD resources not found"

# Delete the argocd namespace
echo "Deleting argocd namespace..."
sudo kubectl delete namespace argocd --timeout=60s 2>/dev/null || echo "Namespace 'argocd' not found or already deleted"

# Delete the K3d cluster (step02.sh)
echo "Deleting K3d cluster 'dbanfiC'..."
sudo k3d cluster delete dbanfiC 2>/dev/null || echo "Cluster 'dbanfiC' not found or already deleted"

# Verify cleanup
echo ""
echo "=== Verification ==="
echo "K3d clusters:"
sudo k3d cluster list

echo ""
echo "Kubectl contexts:"
sudo kubectl config get-contexts 2>/dev/null || echo "No kubectl contexts available"
sudo kubectl get pvc, secret -lrelease=gitlab -n gitlab 2>/dev/null || echo "No GitLab resources found"
echo ""
echo "=== Cleanup complete ==="
