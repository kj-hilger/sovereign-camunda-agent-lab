#!/bin/bash

set -e

echo "🧹 Cleaning up deployed applications..."
echo "-----------------------------------------------------------------------"

# 1. Delete Helm releases
echo "🗑️ Deleting Helm releases..."
helm uninstall camunda8 --namespace camunda || true
helm uninstall ollama --namespace ollama || true
helm uninstall postgresql --namespace postgresql || true
echo "✅ Helm releases uninstalled."
echo "-----------------------------------------------------------------------"

# 2. Force delete NetworkPolicies (common source of "already exists" errors)
echo "🗑️ Force deleting NetworkPolicies..."
kubectl delete networkpolicy --all --namespace camunda || true
kubectl delete networkpolicy --all --namespace ollama || true
kubectl delete networkpolicy --all --namespace postgresql || true
echo "✅ NetworkPolicies removed."
echo "-----------------------------------------------------------------------"

# 3. Delete Namespaces
echo "🗑️ Deleting namespaces..."
kubectl delete namespace camunda --ignore-not-found || true
kubectl delete namespace ollama --ignore-not-found || true
kubectl delete namespace postgresql --ignore-not-found || true

sleep 5
echo "✅ Namespaces removed (or already gone)."
echo "-----------------------------------------------------------------------"

# 4. Clean local artifacts
echo "🧹 Cleaning local artifacts..."
rm -rf apps/camunda8/charts/*
rm -rf apps/ollama/charts/*
rm -rf apps/postgresql/charts/*
echo "✅ Local Helm artifacts cleared."
echo "-----------------------------------------------------------------------"

echo "✨ Cleanup complete. You can now run bootstrap.sh again."
echo "-----------------------------------------------------------------------"