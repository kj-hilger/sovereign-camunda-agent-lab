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
DB_PASSWORD="password"
echo "Using dummy password: $DB_PASSWORD"

kubectl create secret generic camunda-db-secret \
  --namespace camunda \
  --from-literal=postgres-password=$DB_PASSWORD \
  --from-literal=password=$DB_PASSWORD \
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
  --set orchestration.data.secondaryStorage.rdbms.url=jdbc:postgresql://postgresql.postgresql.svc.cluster.local:5432/camunda \
  --set orchestration.data.secondaryStorage.rdbms.username=camunda \
  --set orchestration.data.secondaryStorage.rdbms.secret.name=camunda-db-secret \
  --set orchestration.data.secondaryStorage.rdbms.secret.key=postgres-password

# Database User Initialization
echo "✨ Initializing PostgreSQL user 'camunda'..."
POD_NAME=$(kubectl get pods -n postgresql --no-headers | grep postgres | head -n 1 | xargs)

if [ -z "$POD_NAME" ]; then
  echo "❌ Error: Could not find PostgreSQL pod."
  exit 1
fi

echo "Waiting for pod $POD_NAME to be Running..."
until kubectl get pod $POD_NAME -n postgresql | grep -q "Running"; do
  sleep 5
done

kubectl exec -n postgresql $POD_NAME -c postgres -- psql -U postgres -c "CREATE USER camunda WITH PASSWORD 'password';" || true
kubectl exec -n postgresql $POD_NAME -c postgres -- psql -U postgres -c "GRANT ALL PRIVILEGES ON DATABASE camunda TO camunda;" || true
kubectl exec -n postgresql $POD_NAME -c postgres -- psql -U postgres -c "GRANT ALL ON SCHEMA public TO camunda;" || true
kubectl exec -n postgresql $POD_NAME -c postgres -- psql -U postgres -c "GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA public TO camunda;" || true
kubectl exec -n postgresql $POD_NAME -c postgres -- psql -U postgres -c "ALTER DATABASE camunda OWNER TO camunda;" || true

echo "✅ All applications deployed via Helm."
echo "-----------------------------------------------------------------------"

echo "--- 7. 🛠 Installing Camunda Tools ---"
echo "Installing Zdb..."
curl -L https://github.com/ChrisKujawa/zdb/releases/latest/download/zdb-linux-amd64 -o zdb
chmod +x zdb
sudo mv zdb /usr/local/bin/
echo "✅ Zdb installed."
echo "-----------------------------------------------------------------------"

echo "--- 8. 🚀 Pulling LLM Model ---"
OLLAMA_POD_NAME=$(kubectl get pods -n ollama --no-headers | grep ollama | head -n 1 | xargs)

if [ -z "$OLLAMA_POD_NAME" ]; then
  echo "❌ Error: Could not find Ollama pod."
  exit 1
fi

echo "Waiting for pod $OLLAMA_POD_NAME to be Running..."
until kubectl get pod $OLLAMA_POD_NAME -n ollama | grep -q "Running"; do
  sleep 5
done

echo "Pulling the model qwen2.5:3b-instruct..."
kubectl exec -n ollama $OLLAMA_POD_NAME -c ollama -- ollama pull qwen2.5:3b-instruct
echo "✅ Model pulled successfully."
echo "-----------------------------------------------------------------------"
echo "🚀 Deployment Complete!"
echo "-----------------------------------------------------------------------"