#!/bin/bash
set -e

# Cache Node IP
NODE_IP_DETECTED=$(hostname -I | awk '{print $1}')
K3S_CONF="/etc/rancher/k3s/k3s.yaml"

echo "--- 1. Boot-Configuration & Cgroups Check ---"
if ! grep -q "cgroup_enable=memory" /boot/extlinux/extlinux.conf; then
    echo "🔧 Cgroups missing. Adding cgroups..."
    sudo sed -i 's/APPEND /APPEND cgroup_enable=cpuset cgroup_enable=memory cgroup_memory=1 /' /boot/extlinux/extlinux.conf
    echo "🛑 System reboot required. Please run: sudo reboot"
    exit 0
fi

echo "--- 2. Pre-Installation Checks ---"
[ -f "/etc/nv_tegra_release" ] || (echo "❌ No Jetson hardware detected." && exit 1)

echo "--- 3. Installing NVIDIA Container Runtime & Network Config ---"
sudo mkdir -p /etc/containerd
sudo containerd config default | sudo tee /etc/containerd/config.toml > /dev/null
sudo sed -i 's/disabled_plugins = \["cri"\]/disabled_plugins = \[\]/g' /etc/containerd/config.toml

cat <<EOF | sudo tee -a /etc/containerd/config.toml

[plugins."io.containerd.grpc.v1.cri".containerd]
  default_runtime_name = "nvidia"

[plugins."io.containerd.grpc.v1.cri".containerd.runtimes]
  [plugins."io.containerd.grpc.v1.cri".containerd.runtimes.nvidia]
    privileged_without_host_devices = false
    runtime_engine = ""
    runtime_root = ""
    runtime_type = "io.containerd.runtimes.v2.linux"
    [plugins."io.containerd.grpc.v1.cri".containerd.runtimes.nvidia.options]
      BinaryName = "/usr/bin/nvidia-container-runtime"
EOF

sudo systemctl restart containerd

echo "🔧 Installing CNI plugins and correct Flannel version..."
sudo mkdir -p /opt/cni/bin
wget -q https://github.com/containernetworking/plugins/releases/download/v1.4.0/cni-plugins-linux-arm64-v1.4.0.tgz
sudo tar -xzf cni-plugins-linux-arm64-v1.4.0.tgz -C /opt/cni/bin/
rm -f cni-plugins-linux-arm64-v1.4.0.tgz
wget -q https://github.com/flannel-io/cni-plugin/releases/download/v1.9.0-flannel1/flannel-arm64 -O flannel-arm64
sudo mv flannel-arm64 /opt/cni/bin/flannel
sudo chmod +x /opt/cni/bin/*

echo "🔧 Preparing flannel CNI config file..."
sudo mkdir -p /etc/cni/net.d
cat <<EOF | sudo tee /etc/cni/net.d/10-flannel.conflist
{
  "name": "cbr0",
  "cniVersion": "0.3.1",
  "plugins": [
    { "type": "flannel", "delegate": { "hairpinMode": true, "isDefaultGateway": true } },
    { "type": "portmap", "capabilities": { "portMappings": true } }
  ]
}
EOF
echo "✅ CNI network infrastructure complete and consistent."

echo "--- 4. Installing K3s ---"
curl -sfL https://get.k3s.io -o k3s_install.sh
chmod +x k3s_install.sh

echo "🚀 Executing K3s installation..."
sudo ./k3s_install.sh --disable traefik --disable servicelb --node-ip $NODE_IP_DETECTED
rm k3s_install.sh

# Open K3s config permissions for current user (once via sudo)
sudo chmod 644 $K3S_CONF
export KUBECONFIG=$K3S_CONF

# Persistent entry in .bashrc
if ! grep -q "KUBECONFIG" ~/.bashrc; then
    echo "export KUBECONFIG=$K3S_CONF" >> ~/.bashrc
fi

alias k='kubectl'
if ! grep -q "alias k=" ~/.bashrc; then
    echo "alias k='kubectl'" >> ~/.bashrc
fi

echo "🔍 Waiting for K3s API server to be fully Ready..."
MAX_RETRIES=600
COUNT=0
until kubectl get nodes >/dev/null 2>&1; do
    if [ $COUNT -ge $MAX_RETRIES ]; then
        echo "❌ Error: K3s failed to reach Ready state within 10 minutes."
        exit 1
    fi
    echo "... Waiting for Cluster Ready (attempt $COUNT/$MAX_RETRIES) ..."
    sleep 10
    ((COUNT++))
done
echo "✅ K3s API server is fully up!"

echo "--- 5. Enabling NVIDIA GPU Support in Kubernetes ---"
kubectl create configmap nvidia-plugin-config \
  -n kube-system \
  --from-literal=config.yaml="version: v1
flags:
  failOnInitError: false
  deviceDiscoveryStrategy: tegra" || echo "ConfigMap exists already."

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

echo "🔧 Patching DaemonSet..."
kubectl patch daemonset nvdp-nvidia-device-plugin -n kube-system --type='json' -p='[
  {"op": "replace", "path": "/spec/template/spec/containers/0/args", "value": ["--config-file=/etc/nvidia-config/config.yaml"]},
  {"op": "add", "path": "/spec/template/spec/containers/0/volumeMounts/-", "value": {"name": "nvidia-config-volume", "mountPath": "/etc/nvidia-config"}},
  {"op": "add", "path": "/spec/template/spec/volumes/-", "value": {"name": "nvidia-config-volume", "configMap": {"name": "nvidia-plugin-config"}}}
]'

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
kubectl describe node | grep -A 8 "Allocatable"

if kubectl describe node | grep -A 8 "Allocatable" | grep -q "nvidia.com/gpu:[[:space:]]*1"; then
    echo -e "\e[32m✔ GPU registered successfully!\e[0m"
else
    echo -e "\e[31m✘ Error: GPU not found or not ready.\e[0m"
fi

echo "--- 6. Resource Optimization ---"
kubectl autoscale deployment coredns -n kube-system --cpu=70% --min=1 --max=2

echo "--- 7. Installing Tools ---"
sudo wget -qO /usr/local/bin/yq https://github.com/mikefarah/yq/releases/latest/download/yq_linux_arm64
sudo chmod a+x /usr/local/bin/yq
if command -v yq >/dev/null 2>&1; then
    echo "✅ yq installed successfully: $(yq --version)"
else
    echo "❌ yq installation failed. Please check network or permissions."
    exit 1
fi

echo "✅ Installation complete!"