#!/bin/bash

# This script prepares Helm dependencies and deploys applications.

set -e

# Environment setup
K3S_CONF="/etc/rancher/k3s/k3s.yaml"
export KUBECONFIG=$K3S_CONF

echo "--- 1. 📂 Detecting project path ---"
PROJECT_PATH=$(cd "$(dirname "$0")" && pwd)
cd "$PROJECT_PATH"
echo "✅ Project Root detected: $PROJECT_PATH"
echo "-----------------------------------------------------------------------"

echo "--- 2. 📦 Adding Helm repositories ---"
helm repo add bitnami "https://charts.bitnami.com/bitnami" || true
helm repo update
helm repo add ollama "https://helm.otwld.com" || true
echo "✅ Repositories added."
echo "-----------------------------------------------------------------------"

echo "--- 3. 🔄 Updating Helm dependencies ---"
helm dependency update apps/camunda8/
helm dependency update apps/ollama/
helm dependency update apps/postgresql/
echo "✅ Dependencies updated."
echo "-----------------------------------------------------------------------"

echo "--- 4. 🔧 Creating namespaces ---"
kubectl create namespace camunda --dry-run=client -o yaml | kubectl apply -f - --validate=false
kubectl create namespace ollama --dry-run=client -o yaml | kubectl apply -f - --validate=false
kubectl create namespace postgresql --dry-run=client -o yaml | kubectl apply -f - --validate=false
echo "✅ Namespaces ready."
echo "-----------------------------------------------------------------------"

echo "--- 5. 🔑 Setting up PostgreSQL secret ---"

# Prompt for a password
read -s -p "Enter the password for PostgreSQL: " DB_PASSWORD
echo ""
echo "Using password provided."

kubectl create secret generic camunda-db-secret \
  --namespace camunda \
  --from-literal=postgres-password=$DB_PASSWORD \
  --dry-run=client -o yaml | kubectl apply -f - --validate=false
echo "✅ Secret created."
echo "-----------------------------------------------------------------------"

echo "--- 6. 🚀 Helm deployment ---"

# Deploying PostgreSQL
helm upgrade --install postgresql ./apps/postgresql \
  --namespace postgresql \
  --set auth.username=camunda \
  --set auth.password=$DB_PASSWORD \
  --set auth.postgresPassword=$DB_PASSWORD \
  --set service.type=ClusterIP

# Deploying Ollama
helm upgrade --install ollama ./apps/ollama \
  --namespace ollama

# Deploying Camunda8
helm upgrade --install camunda8 ./apps/camunda8 \
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

echo "--- 8. 🤖 Loading LLM ---"
OLLAMA_POD=$(kubectl get pods -n ollama -o jsonpath='{.items[0].metadata.name}')
echo "Detected Ollama pod: $OLLAMA_POD"
kubectl exec -n ollama $OLLAMA_POD -- ollama pull qwen2.5:3b-instruct
echo "✅ LLM model pulled."
echo "-----------------------------------------------------------------------"

echo "🚀 Deployment Complete! Check status with: kubectl get pods -A"
echo "-----------------------------------------------------------------------"
echo "--- 🔟 ⚠️ Manual Steps ---"
echo "To open Camunda Tasklist and Operate in browser, run the following command manually:"
echo "kubectl port-forward svc/camunda8-zeebe-gateway 8080:8080 -n camunda"
echo "-----------------------------------------------------------------------"