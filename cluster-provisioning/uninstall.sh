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

# 2. Force delete all Pods (Important to release Volumes/PVCs)
echo "🗑️ Force deleting all Pods in relevant namespaces..."
kubectl delete pods --all --namespace camunda --force --grace-period=0 || true
kubectl delete pods --all --namespace ollama --force --grace-period=0 || true
kubectl delete pods --all --namespace postgresql --force --grace-period=0 || true
echo "✅ Pods force-removed."
echo "-----------------------------------------------------------------------"

# 3. Force delete NetworkPolicies
echo "🗑️ Force deleting NetworkPolicies..."
kubectl delete networkpolicy --all --namespace camunda || true
kubectl delete networkpolicy --all --namespace ollama || true
kubectl delete networkpolicy --all --namespace postgresql || true
echo "✅ NetworkPolicies removed."
echo "-----------------------------------------------------------------------"

# 4. Delete Persistent Volume Claims (PVCs)
echo "🗑️ Deleting Persistent Volume Claims..."
kubectl delete pvc --all --namespace postgresql --ignore-not-found || true
kubectl delete pvc --all --namespace camunda --ignore-not-found || true
kubectl delete pvc --all --namespace ollama --ignore-not-found || true
echo "✅ PVCs removed."
echo "-----------------------------------------------------------------------"

# 5. Delete Namespaces
echo "🗑️ Deleting namespaces..."
kubectl delete namespace camunda --ignore-not-found || true
kubectl delete namespace ollama --ignore-not-found || true
kubectl delete namespace postgresql --ignore-not-found || true
echo "✅ Namespaces removed."
echo "-----------------------------------------------------------------------"

# 6. Clean local artifacts
echo "🧹 Cleaning local artifacts..."
rm -rf apps/camunda8/charts/*
rm -rf apps/ollama/charts/*
rm -rf apps/postgresql/charts/*
echo "✅ Local Helm artifacts cleared."
echo "-----------------------------------------------------------------------"

echo "✨ Cleanup complete. You can now run bootstrap.sh again."
echo "-----------------------------------------------------------------------"
