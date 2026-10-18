echo "--- 5. Enabling NVIDIA GPU Support in Kubernetes ---"
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