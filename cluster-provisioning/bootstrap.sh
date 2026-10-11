#!/bin/bash

# This script prepares Helm dependencies and deploys applications.

set -e

# Environment setup
# We use a variable to make it easier to update if needed
K3S_CONF="/etc/rancher/k3s/k3s.yaml"

echo "--- 1. 📂 Detecting project path ---"
PROJECT_PATH=$(cd "$(dirname "$0")" && pwd)
cd "$PROJECT_PATH"
echo "✅ Project Root detected: $PROJECT_PATH"
echo "-----------------------------------------------------------------------"

echo "--- 2. 📦 Adding Helm repositories ---"
sudo KUBECONFIG=$K3S_CONF helm repo add bitnami "https://charts.bitnami.com/bitnami" || true
sudo KUBECONFIG=$K3S_CONF helm repo update
sudo KUBECONFIG=$K3S_CONF helm repo add ollama "https://helm.otwld.com" || true
echo "✅ Repositories added."
echo "-----------------------------------------------------------------------"

echo "--- 3. 🔄 Updating Helm dependencies ---"
sudo KUBECONFIG=$K3S_CONF helm dependency update apps/camunda8/
sudo KUBECONFIG=$K3S_CONF helm dependency update apps/ollama/
sudo KUBECONFIG=$K3S_CONF helm dependency update apps/postgresql/
echo "✅ Dependencies updated."
echo "-----------------------------------------------------------------------"

echo "--- 4. 🔧 Creating namespaces ---"
sudo KUBECONFIG=$K3S_CONF kubectl create namespace camunda --dry-run=client -o yaml | sudo KUBECONFIG=$K3S_CONF kubectl apply -f - --validate=false
sudo KUBECONFIG=$K3S_CONF kubectl create namespace ollama --dry-run=client -o yaml | sudo KUBECONFIG=$K3S_CONF kubectl apply -f - --validate=false
sudo KUBECONFIG=$K3S_CONF kubectl create namespace postgresql --dry-run=client -o yaml | sudo KUBECONFIG=$K3S_CONF kubectl apply -f - --validate=false
echo "✅ Namespaces ready."
echo "-----------------------------------------------------------------------"

echo "--- 5. 🔑 Setting up PostgreSQL secret ---"

# Prompt for a password
read -s -p "Enter the password for PostgreSQL: " DB_PASSWORD
echo ""
echo "Using password: $DB_PASSWORD"

sudo KUBECONFIG=$K3S_CONF kubectl create secret generic camunda-db-secret \
  --namespace camunda \
  --from-literal=postgres-password=$DB_PASSWORD \
  --dry-run=client -o yaml | sudo KUBECONFIG=$K3S_CONF kubectl apply -f - --validate=false
echo "✅ Secret created."
echo "-----------------------------------------------------------------------"

echo "--- 6. 🚀 Helm deployment ---"

# Deploying PostgreSQL
sudo KUBECONFIG=$K3S_CONF helm upgrade --install postgresql ./apps/postgresql \
  --namespace postgresql \
  --set auth.username=camunda \
  --set auth.password=$DB_PASSWORD \
  --set auth.postgresPassword=$DB_PASSWORD \
  --set service.type=ClusterIP

# Deploying Ollama
sudo KUBECONFIG=$K3S_CONF helm upgrade --install ollama ./apps/ollama \
  --namespace ollama

# Deploying Camunda8
sudo KUBECONFIG=$K3S_CONF helm upgrade --install camunda8 ./apps/camunda8 \
  --namespace camunda \
  --set orchestration.data.secondaryStorage.rdbms.url=jdbc:postgresql://postgresql.postgresql.svc.cluster.local:5432/postgres \
  --set orchestration.data.secondaryStorage.rdbms.username=camunda \
  --set orchestration.data.secondaryStorage.rdbms.secret.name=camunda-db-secret \
  --set orchestration.data.secondaryStorage.rdbms.secret.key=postgres-password

echo "✅ All applications deployed via Helm."
echo "-----------------------------------------------------------------------"

echo "--- 7. 🛠 Installing Camunda Tools ---"
echo "Installing Zdb..."
curl -L https://github.com/ChrisKujawa/zdb/releases/latest/download/zdb-linux-amd64 -o zdb
chmod +x zdb
sudo mv zdb /usr/local/bin/
echo "✅ Zdb installed."

echo "-----------------------------------------------------------------------"
echo "🚀 Deployment Complete! Check status with: sudo kubectl get pods -A"
echo "-----------------------------------------------------------------------"
