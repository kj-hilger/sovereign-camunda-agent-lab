#!/bin/bash
# uninstall.sh - Deep Clean Version
set -e

echo "--- 1. Cleaning up Kubernetes Objects & Helm Charts ---"
# ConfigMap löschen, solange kubectl/K3s noch läuft
if command -v kubectl &> /dev/null && kubectl cluster-info &> /dev/null; then
    kubectl delete configmap nvidia-plugin-config -n kube-system --ignore-not-found || true
    echo "✅ NVIDIA Plugin ConfigMap removed."
fi

if helm list -n kube-system 2>/dev/null | grep -q "nvdp"; then
    helm uninstall nvdp -n kube-system || true
    echo "✅ NVIDIA Device Plugin removed."
fi

# Remove Helm Repos
helm repo remove nvdp 2>/dev/null || true

echo "--- 2. Uninstalling K3s ---"
# Run standard K3s uninstallation script
if [ -f "/usr/local/bin/k3s-uninstall.sh" ]; then
    echo "Running k3s-uninstall.sh..."
    sudo bash /usr/local/bin/k3s-uninstall.sh
else
    echo "⚠️ k3s-uninstall.sh not found. Continuing with manual cleanup..."
fi

sudo rm -rf /etc/rancher /var/lib/rancher

echo "--- 3. Cleaning up Kubernetes Configurations (Certificates) ---"
if [ -f "$HOME/.kube/config" ]; then
    rm "$HOME/.kube/config"
    echo "✅ Local kube configuration (~/.kube/config) deleted."
fi

echo "--- 4. Cleaning up Network and Container Configurations ---"
# Delete CNI configs
sudo rm -f /etc/cni/net.d/10-flannel.conflist
sudo rm -f /opt/cni/bin/flannel

# Reset containerd configuration completely to default
if [ -f /etc/containerd/config.toml ]; then
    echo "Resetting containerd config to default..."
    sudo mkdir -p /etc/containerd
    sudo containerd config default | sudo tee /etc/containerd/config.toml > /dev/null
    sudo systemctl restart containerd
fi

echo "--- 5. Cleaning up Device Plugins Directory ---"
sudo rm -rf /var/lib/kubelet/device-plugins || true

echo "--- 6. Cleaning up Packages ---"
sudo apt-get purge -y nvidia-container-toolkit nvidia-container-toolkit-base yq 2>/dev/null || true
sudo apt-get autoremove -y
sudo apt-get autoclean

echo "--- 7. Cleaning up .bashrc ---"
if [ -f ~/.bashrc ]; then
    sed -i "/alias k='kubectl'/d" ~/.bashrc
    sed -i '/KUBECONFIG/d' ~/.bashrc
    echo "✅ Alias and environment variables removed from .bashrc."
fi

echo "✅ Uninstallation completed. Please reboot your Jetson. Afterwards, the system is ready for a clean reinstallation."