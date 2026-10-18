#!/bin/bash
# uninstall.sh - Deep Clean Version
set -e

echo "--- 1. Uninstalling Helm Charts ---"
# We use '|| true' so that the script doesn't fail if a chart is already gone.

if helm list -n kube-system | grep -q "kubernetes-dashboard"; then
    helm uninstall kubernetes-dashboard -n kube-system || true
    echo "✅ Kubernetes Dashboard removed."
fi

if helm list -n kube-system | grep -q "nvdp"; then
    helm uninstall nvdp -n kube-system || true
    echo "✅ NVIDIA Device Plugin removed."
fi

# Remove Helm Repos
helm repo remove kubernetes-dashboard || true
helm repo remove nvdp || true

echo "--- 2. Uninstalling K3s ---"
# Run standard K3s uninstallation script
if [ -f "/usr/local/bin/k3s-uninstall.sh" ]; then
    echo "Running k3s-uninstall.sh..."
    sudo bash /usr/local/bin/k3s-uninstall.sh
else
    echo "⚠️ k3s-uninstall.sh not found. Continuing with manual cleanup..."
fi

echo "--- 3. Cleaning up Kubernetes Configurations (Certificates) ---"
# THIS IS THE MOST IMPORTANT STEP AGAINST THE x509 ERROR:
# We delete the local configuration so that kubectl requests
# the new certificates from K3s next time.
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

echo "--- 5. Cleaning up Kubernetes Objects ---"
# Ensure ConfigMaps are deleted
sudo kubectl delete configmap nvidia-plugin-config -n kube-system --ignore-not-found || true
# Delete directory for device plugins
sudo rm -rf /var/lib/kubelet/device-plugins || true

echo "--- 6. Cleaning up Packages ---"
# Remove NVIDIA Toolkit and yq
sudo apt-get purge -y nvidia-container-toolkit nvidia-container-toolkit-base yq
sudo apt-get autoremove -y
sudo apt-get autoclean

echo "--- 7. Cleaning up .bashrc ---"
if [ -f ~/.bashrc ]; then
    # Removes the alias line for kubectl
    sed -i '/alias k=\'kubectl\'/d' ~/.bashrc
    echo "✅ Alias removed from .bashrc."
fi

echo "✅ Uninstallation completed. Please reboot your Jetson. Afterwards, the system is ready for a clean reinstallation."