#!/bin/bash

# colors for output
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${YELLOW}=== Jetson Orin Nano K3s GPU Health Check ===${NC}\n"

# 1. check CNI Plugins
echo -n "1. Checking CNI Network Plugins... "
if [ -f /opt/cni/bin/loopback ] && [ -f /opt/cni/bin/flannel ]; then
    echo -e "${GREEN}OK (Present)${NC}"
else
    echo -e "${RED}ERROR (Plugins missing in /opt/cni/bin)${NC}"
fi

# 2. check Containerd Socket in K3s Service
echo -n "2. Checking K3s Containerd Link... "
if grep -q "container-runtime-endpoint" /etc/systemd/system/k3s.service; then
    echo -e "${GREEN}OK (External Socket active)${NC}"
else
    echo -e "${RED}WARNING (K3s might be running internally! Add --container-runtime-endpoint)${NC}"
fi

# 3. check external containerd running
echo -n "3. Checking System-Containerd Status... "
if systemctl is-active --quiet containerd; then
    echo -e "${GREEN}OK (Running)${NC}"
else
    echo -e "${RED}ERROR (System-containerd is stopped!)${NC}"
fi

# Check Daemonset Patch
sudo kubectl get daemonset nvdp-nvidia-device-plugin -n kube-system -o json | \
  grep -q '"--config-file=/etc/nvidia-config/config.yaml"' && \
sudo kubectl get daemonset nvdp-nvidia-device-plugin -n kube-system -o json | \
  grep -q '"name": "nvidia-config-volume"' && \
echo "✅ DaemonSet Patch verified!" || (echo "❌ DaemonSet Patch validation failed!" && exit 1)

# 4. Check the Device Plugin
echo -n "4. Checking NVIDIA Device Plugin Pods... "
POD_STATUS=$(sudo kubectl get pods -n kube-system -l app.kubernetes.io/name=nvidia-device-plugin -o jsonpath='{.items[0].status.phase}' 2>/dev/null)
if [ "$POD_STATUS" == "Running" ]; then
    echo -e "${GREEN}OK (Running)${NC}"
else
    echo -e "${RED}ERROR (Plugin Status is: ${POD_STATUS:-Not found})${NC}"
fi

# 5. The final GPU check
echo -n "5. Checking GPU allocation in the cluster... "
GPU_COUNT=$(sudo kubectl get nodes -o jsonpath='{.items[0].status.allocatable.nvidia\.com/gpu}' 2>/dev/null)
if [ "$GPU_COUNT" == "1" ]; then
    echo -e "${GREEN}PERFECT! NVIDIA GPU (1) is allocatable!${NC}"
else
    echo -e "${RED}ERROR! No GPU detected by Kubelet (Value: ${GPU_COUNT:-0})${NC}"
fi

echo -e "\n${YELLOW}=============================================${NC}"
