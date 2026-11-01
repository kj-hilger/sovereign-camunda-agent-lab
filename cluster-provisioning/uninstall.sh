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

# 4. Deep Clean Persistent Storage (PVCs & PVs)
echo "🗑️ Deep Cleaning Persistent Storage..."

# Try to delete PVCs first
kubectl delete pvc --all --namespace postgresql --ignore-not-found || true
kubectl delete pvc --all --namespace camunda --ignore-not-found || true
kubectl delete pvc --all --namespace ollama --ignore-not-found || true

# Radical Step A: Remove finalizers from all PVCs (handles stuck Terminating status)
echo "✨ Removing finalizers from stuck PVCs..."
for pvc in $(kubectl get pvc -A --no-headers | grep Terminating | awk '{print $1}'); do
  kubectl patch pvc $pvc -p '{"metadata":{"finalizers":null}}' --type=merge || true
done

# Radical Step B: Remove VolumeAttachments (This is the common reason for hanging volumes)
echo "🔥 Deleting all VolumeAttachments..."
kubectl delete volumeattachments --all --no-headers || true

# Radical Step C: Remove finalizers from all PVs
echo "✨ Removing finalizers from PVs..."
for pv in $(kubectl get pv --no-headers | grep Bound | awk '{print $1}'); do
  kubectl patch pv $pv -p '{"metadata":{"finalizers":null}}' --type=merge || true
done

echo "✅ Storage deep clean completed."
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
