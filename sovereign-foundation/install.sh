#!/bin/bash
# install.sh
set -e

echo "--- 1. Boot-Configuration & Cgroups Check ---"
# NOTE: On Jetson Orin Nano cgroup memory must be enabled to prevent K3s API server OOM kills.
if ! grep -q "cgroup_enable=memory" /boot/extlinux/extlinux.conf; then
    echo "🔧 Cgroups missing. adding cgroups..."
    sudo sed -i 's/APPEND /APPEND cgroup_enable=cpuset cgroup_enable=memory cgroup_memory=1 /' /boot/extlinux/extlinux.conf
    echo "🛑 system reboot required. Please: sudo reboot"
    exit 0
fi

echo "--- 2. Pre-Installation Checks ---"
[ -f "/etc/nv_tegra_release" ] || (echo "❌ No Jetson hardware detected." && exit 1)


echo "--- 3. Installing NVIDIA Container Runtime & Network Config ---"
sudo apt-get update -y
sudo apt-get install -y nvidia-container-toolkit nvidia-container-toolkit-base
# NOTE: The NVIDIA container toolkit disables the default CRI in internal containerd. We enable it by removing 'disabled_plugins = ["cri"]' and set default runtime to nvidia.

# Clean containerd base with CRI enabled
sudo mkdir -p /etc/containerd
sudo containerd config default | sudo tee /etc/containerd/config.toml > /dev/null
sudo sed -i 's/disabled_plugins = \["cri"\]/disabled_plugins = \[\]/g' /etc/containerd/config.toml

# Inject NVIDIA runtime into config
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

# 1. Load and extract the standard CNI package for ARM64 (for loopback, host-local, etc.)
wget -q https://github.com/containernetworking/plugins/releases/download/v1.4.0/cni-plugins-linux-arm64-v1.4.0.tgz
sudo tar -xzf cni-plugins-linux-arm64-v1.4.0.tgz -C /opt/cni/bin/
rm -f cni-plugins-linux-arm64-v1.4.0.tgz

# 2. Flannel as ARM64 binary for Jetson
wget -q https://github.com/flannel-io/cni-plugin/releases/download/v1.9.0-flannel1/flannel-arm64 -O flannel-arm64
sudo mv flannel-arm64 /opt/cni/bin/flannel
# NOTE: Flannel must be preconfigured for ARM64 on Jetson; otherwise K3s fails with "CNI network error". We provide a minimal 10‑flannel.conflist.

# 3. Make all binaries in target folder executable
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
sudo rm -f /var/lib/rancher/k3s/agent/etc/containerd/config.toml.tmpl

NODE_IP_DETECTED=$(hostname -I | awk '{print $1}')
curl -sfL https://get.k3s.io | sh -s - \
  --container-runtime-endpoint unix:///var/run/containerd/containerd.sock \
  --disable traefik \
  --disable servicelb \
  --node-ip $NODE_IP_DETECTED
  # NOTE: Disabling Traefik and ServiceLB avoids API server crashes due to insufficient memory cgroup support on Jetson.

mkdir -p ~/.kube
sudo cp /etc/rancher/k3s/k3s.yaml ~/.kube/config
sudo chown -R $USER:$USER ~/.kube
chmod 600 ~/.kube/config
export KUBECONFIG=~/.kube/config

echo "🔍 Wait 15s for network stabilisation..."
sleep 15


echo "--- 6. Enabling NVIDIA GPU Support in Kubernetes ---"
# 1. Create a ConfigMap for Jetson Tegra
sudo kubectl create configmap nvidia-plugin-config \
  -n kube-system \
  --from-literal=config.yaml="version: v1
flags:
  failOnInitError: false
  deviceDiscoveryStrategy: tegra" || echo "ConfigMap exists already."

# Prepare the socket directory
sudo mkdir -p /var/lib/kubelet/device-plugins
sudo chmod 755 /var/lib/kubelet/device-plugins

helm repo add nvdp https://nvidia.github.io/k8s-device-plugin || true
helm repo update

# 2. Install the plugin via Helm – WITH THE SPECIFIED DEVICE-STRATEGY FLAG
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
  # NOTE: We set deviceListStrategy=envvar and nodeSelector=null to allow the NVIDIA Device Plugin to run on Tegra's integrated GPU (no PCI bus).

echo "🔧 Patching DaemonSet..."
sudo kubectl patch daemonset nvdp-nvidia-device-plugin -n kube-system --type='json' -p='[
  {"op": "replace", "path": "/spec/template/spec/containers/0/args", "value": ["--config-file=/etc/nvidia-config/config.yaml"]},
  {"op": "add", "path": "/spec/template/spec/containers/0/volumeMounts/-", "value": {"name": "nvidia-config-volume", "mountPath": "/etc/nvidia-config"}},
  {"op": "add", "path": "/spec/template/spec/volumes/-", "value": {"name": "nvidia-config-volume", "configMap": {"name": "nvidia-plugin-config"}}}
]'

echo "⏳ Wait 15s for Pod creation..."
sleep 15

sudo kubectl rollout restart daemonset nvdp-nvidia-device-plugin -n kube-system
sudo kubectl rollout status daemonset nvdp-nvidia-device-plugin -n kube-system --timeout=60s

sudo kubectl get daemonset nvdp-nvidia-device-plugin -n kube-system -o json | \
  grep -q '"--config-file=/etc/nvidia-config/config.yaml"' && \
sudo kubectl get daemonset nvdp-nvidia-device-plugin -n kube-system -o json | \
  grep -q '"name": "nvidia-config-volume"' && \
echo "✅ DaemonSet Patch verified!" || (echo "❌ DaemonSet Patch verification failed!" && exit 1)

echo "Wait for GPU registration..."
sleep 10
sudo kubectl describe node | grep -A 8 "Allocatable"

if sudo kubectl describe node | grep -A 8 "Allocatable" | grep -q "nvidia.com/gpu:[[:space:]]*1"; then
    echo -e "\e[32m✔ GPU registered successfully!\e[0m"
else
    echo -e "\e[31m✘ Fehler: GPU not found or not ready.\e[0m"
fi

echo "--- 7. Resource Optimization ---"
sudo kubectl autoscale deployment coredns -n kube-system --cpu=70% --min=1 --max=2
