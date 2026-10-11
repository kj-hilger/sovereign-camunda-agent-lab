# Sovereign Camunda Agent Lab 🚀

* <p align="left">
  <a href="docs/sovereign-camunda-agent-lab" target="_blank" rel="noreferrer">
    <img src="docs/jetson.jpg?raw=true" alt="Jetson Orin Nano" height="240" style="opacity: 0.8; margin-right: 12px;"/>
  </a>
  <a href="docs/sovereign-camunda-agent-lab" target="_blank" rel="noreferrer">
    <img src="docs/camunda-operate-tokyo.png?raw=true" alt="Camunda BPMN Process Flow Tokyo" height="240" style="opacity: 0.8; margin-right: 12px;"/>
  </a>
  <a href="docs/sovereign-camunda-agent-lab" target="_blank" rel="noreferrer">
    <img src="docs/architecture.jpeg?raw=true" alt="Architecture" height="240" style="opacity: 0.8; margin-right: 12px;"/>
  </a>
</p>

## ⚡ Summary

* Lightweight, ephemeral **DevOps lab** for rapidly spinning up a **Camunda 8 Agentic AI** process application together with an **LLM provider** on NVIDIA Jetson Orin Nano.
* Provision & operate enterprise-grade Camunda 8 with **Agentic Tool Calls** to Local LLM on **Kubernetes** within minutes on your desk, no Internet connection needed during runtime and also no Token Budget.
* Optimized for the **NVIDIA Jetson Orin Nano 8 GB**, a compact and cost-effective device that can be easily wiped and reprovisioned. It enables quiet, low-energy operation and is perfectly suited for portable, on-site demonstrations in air-gapped environments.

**Table of Contents**
* [⚡ Summary](#-summary)
* [🚀 Roadmap & Phases](#-roadmap--phases)
* [⚠️ Known Limitations & Architectural Caveats](#%EF%B8%8F-known-limitations--architectural-caveats)
* [📋 Prerequisites](#-prerequisites)
* [🏗 Sovereign Foundation](#-sovereign-foundation)
* [♾️ Cluster Provisioning](#cluster-provisioning)
* [⚙️ Agentic Orchestration](#agentic-orchestration)

---

### 🚀 Roadmap & Phases

- **Sovereign Foundation:** ready
- **Cluster Provisioning:** under test, further improvement planned
- **Agentic Orchestration:** under test, further improvement planned

---

### ⚠️ Known Limitations & Architectural Caveats

While this Lab serves as a rapid local DevOps lab for the enterprise patterns listed above, certain other enterprise patterns are currently simplified:

* **Host-Level Bootstrapping:** Installation scripts currently modify host configurations directly (e.g., Docker daemon, CNI).
* **Enterprise Limitations:** No GitOps tooling (only Helm), no pg_admin tooling, no visual observability, no Camunda security available.
* **Resource Constraints (Edge):** Camunda 8 together with Ollama local LLM requires 80% of the 8 GB memory. Edge profile requires aggressive resource tuning to avoid OOM issues.
* **Camunda Scope:** No Camunda Optimize available.

---

## 📋 Prerequisites

### Jetson OS
- **OS:** Debian-based Linux with NVIDIA Drivers & CUDA Toolkit installed (can be verified by running `nvidia-smi`).
- **Package Manager:** `apt` is available.
- **Basic Tools:** `curl`, `git`, `gpg`, `sed` are installed.

### Additional
- **Kubernetes Tools:** `docker`, `kubectl`, also put in PATH.
- **Dev Tools:** `openjdk-25`, `maven`, (sudo apt install -y openjdk-25-jdk maven)
- **Connectivity:** Internet access is required during the bootstrap process.
- **Repository:** Please clone this repo:
```bash
git clone https://github.com/kj-hilger/sovereign-camunda-agent-lab.git
```

---

## 🏗 Sovereign Foundation

Scripts to install tools for NVIDIA GPU Acceleration, K8s and Helm.

### Bootstrap

```bash
sudo ./sovereign-foundation/install.sh # maybe needed before: sudo chmod +x ./sovereign-foundation/install.sh
```

#### Detailed documentation

<details>
<summary>Script Steps</summary>

| Step | Description                                                                | Key Challenges                                                                                                                                                                                        |
|------|----------------------------------------------------------------------------|-------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| 1    | Boot Configuration & Cgroups Check                                         | Missing cgroup parameters cause memory crashes; requires reboot.                                                                                                                                      |
| 2    | Pre-Installation Checks                                                    | Verify Jetson hardware presence. **⚠Overwrites /opt/cni/bin/ ⚠**                                                                                                                                    |
| 3    | Installing NVIDIA Container Runtime & Network Config (containerd, flannel) | CRI unblocking and preconfiguring CNI for a stable network; aligning container runtimes with system‑wide containerd + NVIDIA runtime. **⚠fix versions for cni-plugins v1.4.0 and flannel v1.9.0 ⚠** |
| 4    | Installing K3s                                                             | None specific; standard K3s install using containerd endpoint.                                                                                                                                        |
| 5    | Enabling NVIDIA GPU Support in Kubernetes                                  | The Kubernetes resources for NVIDIA Device Plugin fail on Jetson due to PCI‑based affinity and memory management issues, thus patches and enhancements are needed.                                    |
| 6    | Resource Optimization                                                      | Minimizing log overhead and saving unified memory.                                                                                                                                                    |
| 7    | Installing Tools                                                           | yq for better output formats.                                                                                                                                                                         |

</details>

### Post-Installation
* The installation configures Docker to run without `sudo` for the current user.
* Run check script:
```bash
./sovereign-foundation/check.sh # maybe needed before: chmod +x ./sovereign-foundation/check.sh
```
* Docker and NVIDIA Toolkit will be updated via apt Package Manager.

### Start again after reboot
* K3s starts automatically via systemd service.

### Delete All and Reinstall (with latest software versions)

```bash
./sovereign-foundation/k3s-uninstall.sh # maybe needed before chmod +x ./sovereign-foundation/k3s-uninstall.sh,  **⚠️ deletes all content under /var/lib/docker ⚠️**
# reboot
# run bootstrap script again
```

---

## ♾️Cluster Provisioning

* Manifest Helm-Charts and scripts to provision the cluster self-managed on top of the Sovereign Foundation layer.
* Camunda 8 (minimal cluster size, but including Camunda Agentic AI Connector), PostgreSQL and Ollama (including local LLM Qwen 2.5:3b-instruct).
* You enjoy air-gapped Data Sovereignty at runtime.

### Bootstrap

```bash
sudo bash ./cluster-provisioning/bootstrap.sh # maybe needed before: chmod +x ./cluster-provisioning/bootstrap.sh
```

#### Detailed documentation

<details>
<summary>Script Steps</summary>

| Step | Component                    | Action & Structural Rationale                                                                                                          |
|:-----|:-----------------------------|:---------------------------------------------------------------------------------------------------------------------------------------|
| 1    | Detecting project path       |                                                                                                                                        |
| 2    | Adding Helm repositories     |                                                                                                                                        |
| 3    | Updating Helm dependencies   | This downloads the official charts and places them as archives in the automatically created folders within each application structure. |
| 4    | Creating Namespaces          |                                                                                                                                        |
| 5    | Setting up PostgreSQL secret | Prompts for password of your choice.                                                                                                   |
| 6    | Helm Deployment              |                                                                                                                                        |
| 7    | Installing Camunda Tools     | zdb                                                                                                                                    |

</details>

Manual steps (will be enhanced and moved to the script in the future)
- Patch Connectors
```bash
sudo kubectl set env deployment/camunda8-connectors -n camunda \
CAMUNDA_CLIENT_WORKER_DEFAULTS_STREAMENABLED=false \
ZEEBE_CLIENT_WORKER_DEFAULTS_STREAM_ENABLED=false \
CAMUNDA_CLIENT_PREFER_REST_OVER_GRPC=true
# Deletes and recreates connectors pod, which is also needed because a successful start will only happen after zeebe startup was complete.
```
- load LLM:
```bash
sudo kubectl get pods -n ollama # copy ollama pod name
sudo kubectl exec -it -n ollama <ollama-pod-name> -- ollama pull qwen2.5:3b-instruct
```
Necessary to open Camunda Tasklist and Operate in browser:
```bash
sudo kubectl port-forward svc/camunda8-zeebe-gateway 8080:8080 -n camunda
```

### Operating

* Because all dependencies are provisioned locally, the system requires no external communication with Helm repositories. 
* To perform changes in the configuration, modify the values.yaml files and execute uninstall and bootstrap again.

### Delete All

```bash
sudo ./cluster-provisioning/uninstall.sh # maybe needed before: sudo chmod +x ./cluster-provisioning/uninstall.sh
```

---

## ⚙️Agentic Orchestration

* Leverages Camunda 8 Deterministic Orchestration to manage agentic decision flows, ensuring full process visibility, execution logging and Observability. 
* The BPMN Pattern Agentic AI as Subprocess together with a human task ensures "Human-in-the-Loop".

### Bootstrap

- Build and Deploy Docker Image:
```bash
cd agentic-orchestration
mvn clean package
sudo docker build -t agentic-orchestration:1.0.0 . # set a new version number in each build.
sudo docker save agentic-orchestration:1.0.0 -o agentic-orchestration-1.0.0.tar
sudo k3s ctr images import agentic-orchestration-1.0.0.tar
sudo kubectl apply -f agentic-orchestration.yaml # please change version number in file before
```

### Operating

* <p align="left">
  <a href="docs/sovereign-camunda-agent-lab" target="_blank" rel="noreferrer">
    <img src="docs/camunda-operate-tokyo.png?raw=true" alt="Camunda BPMN Process Flow Tokyo" height="240" style="opacity: 0.8; margin-right: 12px;"/>
  </a>
  <a href="docs/sovereign-camunda-agent-lab" target="_blank" rel="noreferrer">
    <img src="docs/camunda-tasklist-tokyo.png?raw=true" alt="Camunda Form Task Tokyo" height="240" style="opacity: 0.8; margin-right: 12px;"/>
  </a>
</p>

- Open Camunda Tasklist, log in with demo/demo, go to Processes View, start an instance, enter a city and view the result:
```bash
http://localhost:8080/tasklist
```

- Open Camunda Operate, log in with demo/demo, go to Processes View, choose the latest instance and observe its flow and variables.

---

## 📄 License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.
