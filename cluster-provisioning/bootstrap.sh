#!/bin/bash

# This script prepares Helm dependencies and deploys applications.

set -e

echo "📂 Detecting project path..."
PROJECT_PATH=$(cd "$(dirname "$0")" && pwd)
cd "$PROJECT_PATH"
echo "✅ Project Root detected: $PROJECT_PATH"
echo "-----------------------------------------------------------------------"

echo "📦 Adding Helm repositories..."
helm repo add bitnami "https://charts.bitnami.com/bitnami"
helm repo update
helm repo add ollama "https://helm.otwld.com"
echo "✅ Repositories added."
echo "-----------------------------------------------------------------------"

echo "🔄 Updating Helm dependencies..."
helm dependency update apps/camunda8/
helm dependency update apps/ollama/
helm dependency update apps/postgresql/
echo "✅ Dependencies updated."
echo "-----------------------------------------------------------------------"

echo "🔧 Creating namespaces..."
kubectl create namespace camunda --dry-run=client -o yaml | kubectl apply -f -
kubectl create namespace ollama --dry-run=client -o yaml | kubectl apply -f -
kubectl create namespace postgresql --dry-run=client -o yaml | kubectl apply -f -
echo "✅ Namespaces ready."
echo "-----------------------------------------------------------------------"

echo "🔑 Setting up PostgreSQL secret..."

# Prompt for a password
read -s -p "Enter the password for PostgreSQL: " DB_PASSWORD
echo ""
echo "Using password: $DB_PASSWORD"

kubectl create secret generic camunda-db-secret \
  --namespace camunda \
  --from-literal=postgres-password=$DB_PASSWORD \
  --dry-run=client -o yaml | kubectl apply -f -
echo "✅ Secret created."
echo "-----------------------------------------------------------------------"

echo "🚀 Proceeding with Helm deployment..."

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
echo "🚀 Deployment Complete! Check status with: kubectl get pods -A"
echo "-----------------------------------------------------------------------"