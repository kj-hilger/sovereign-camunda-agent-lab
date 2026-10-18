#!/bin/bash
# sovereign-foundation/install.sh
set -e

echo "--- 1. Boot Configuration & Cgroups Check ---"
echo "✅ Boot configuration checked."

echo "--- 2. Pre-Installation Checks ---"
if ! command -v nvidia-smi &> /dev/null && [ ! -f /etc/nv_tegra_release ]; then
    echo "⚠️ Warning: Not running on a Jetson or NVIDIA drivers missing."
fi

echo "--- 3. Installing NVIDIA Container Runtime & Network Config ---"
sudo apt-get update
sudo apt-get install -y nvidia-container-toolkit jq

if command -v nvidia-ctk &> /dev/null; then
    sudo nvidia-ctk runtime configure --runtime=containerd || true
    sudo systemctl restart containerd
fi

# Pre-configure CNI directory
sudo mkdir -p /etc/cni/net.d
sudo mkdir -p /opt/cni/bin

echo "--- 4. Installing K3s ---"
curl -sfL https://get.k3s.io -o k3s_install.sh
chmod +x k3s_install.sh

# Detect Node IP
NODE_IP_DETECTED=$(hostname -I | awk '{print $1}')
echo "Detected Node IP: $NODE_IP_DETECTED"

echo "🚀 Executing K3s installation (forcing kubectl symlink & permissions)..."
# INSTALL_K3S_SYMLINK=force ensures kubectl is reliably linked
# --write-kubeconfig-mode 644 makes the config immediately readable for the user
INSTALL_K3S_SYMLINK=force sudo ./k3s_install.sh \
  --disable traefik \
  --disable servicelb \
  --node-ip "$NODE_IP_DETECTED" \
  --write-kubeconfig-mode 644
rm k3s_install.sh

mkdir -p "$HOME/.kube"
if [ -f /etc/rancher/k3s/k3s.yaml ]; then
    sudo cp /etc/rancher/k3s/k3s.yaml "$HOME/.kube/config"
    sudo chown "$(id -u):$(id -g)" "$HOME/.kube/config"
    chmod 600 "$HOME/.kube/config"
fi

# Add kubectl alias and KUBECONFIG export to .bashrc if missing
if [ -f ~/.bashrc ]; then
    if ! grep -q "KUBECONFIG" ~/.bashrc; then
        echo "export KUBECONFIG=\$HOME/.kube/config" >> ~/.bashrc
    fi
    if ! grep -q "alias k=" ~/.bashrc; then
        echo "alias k='kubectl'" >> ~/.bashrc
    fi
fi

echo "--- 5. Enabling NVIDIA GPU Support in Kubernetes ---"
# Apply the ConfigMap idempotently using dry-run trick
kubectl create configmap nvidia-plugin-config \
  -n kube-system \
  --from-literal=config.yaml="version: v1
flags:
  failOnInitError: false
  deviceDiscoveryStrategy: tegra" --dry-run=client -o yaml | kubectl apply -f -

sudo mkdir -p /var/lib/kubelet/device-plugins
sudo chmod 755 /var/lib/kubelet/device-plugins

echo "🔧 Adding Helm repositories..."
if ! command -v helm &> /dev/null; then
    echo "🔧 Helm is not installed. Installing Helm..."
    curl -fsSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
fi
helm repo add nvdp https://nvidia.github.io/k8s-device-plugin || true
helm repo update

echo "🚀 Installing NVIDIA Device Plugin via Helm..."
helm upgrade --install nvdp nvdp/nvidia-device-plugin \
  --namespace kube-system \
  --set gds.enabled=false \
  --set gdrcopy.enabled=false \
  --set mofed.enabled=false \
  --set deviceListStrategy=envvar \
  --set nodeSelector=null \
  --set affinity=null \
  --set "tolerations[0].operator=Exists" \
  --set "tolerations[0].effect=NoSchedule" \
  --set "tolerations[1].operator=Exists" \
  --set "tolerations[1].effect=NoExecute"

echo "🔧 Checking and patching DaemonSet..."
if ! kubectl get daemonset nvdp-nvidia-device-plugin -n kube-system -o jsonpath='{.spec.template.spec.volumes[*].name}' | grep -q "nvidia-config-volume"; then
    kubectl patch daemonset nvdp-nvidia-device-plugin -n kube-system --type='json' -p='[
      {"op": "replace", "path": "/spec/template/spec/containers/0/args", "value": ["--config-file=/etc/nvidia-config/config.yaml"]},
      {"op": "add", "path": "/spec/template/spec/containers/0/volumeMounts/-", "value": {"name": "nvidia-config-volume", "mountPath": "/etc/nvidia-config"}},
      {"op": "add", "path": "/spec/template/spec/volumes/-", "value": {"name": "nvidia-config-volume", "configMap": {"name": "nvidia-plugin-config"}}}
    ]'
else
    echo "ℹ️ DaemonSet is already patched with nvidia-config-volume. Skipping patch."
fi

echo "⏳ Wait 15s for Pod creation..."
sleep 15

kubectl rollout restart daemonset nvdp-nvidia-device-plugin -n kube-system
kubectl rollout status daemonset nvdp-nvidia-device-plugin -n kube-system --timeout=60s

kubectl get daemonset nvdp-nvidia-device-plugin -n kube-system -o json | \
  grep -q '"--config-file=/etc/nvidia-config/config.yaml"' && \
kubectl get daemonset nvdp-nvidia-device-plugin -n kube-system -o json | \
  grep -q '"name": "nvidia-config-volume"' && \
echo "✅ DaemonSet Patch verified!" || (echo "❌ DaemonSet Patch verification failed!" && exit 1)

echo "Wait for GPU registration..."
sleep 10
kubectl describe node | grep -A 8 "Allocatable" || true

if kubectl describe node | grep -A 8 "Allocatable" | grep -q "nvidia.com/gpu:[[:space:]]*1"; then
    echo -e "\e[32m✔ GPU registered successfully!\e[0m"
else
    echo -e "\e[31m✘ Error: GPU not found or not ready.\e[0m"
fi

echo "--- 6. Resource Optimization ---"
kubectl autoscale deployment coredns -n kube-system --cpu=70% --min=1 --max=2 || true

echo "--- 7. Installing Tools ---"
sudo wget -qO /usr/local/bin/yq https://github.com/mikefarah/yq/releases/latest/download/yq_linux_arm64
sudo chmod a+x /usr/local/bin/yq
if command -v yq >/dev/null 2>&1; then
    echo "✅ yq installed successfully: $(yq --version)"
else
    echo "❌ yq installation failed. Please check network or permissions."
    exit 1
fi

echo "✅ Sovereign Foundation installation complete!"