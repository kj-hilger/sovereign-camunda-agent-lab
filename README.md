# Sovereign Camunda Agent Lab 🚀

<p align="left">
  <a href="docs/jetson.jpg" target="_blank" rel="noreferrer">
    <img src="docs/jetson.jpg?raw=true" alt="Jetson Orin Nano" height="240" style="opacity: 0.8; margin-right: 12px;"/>
  </a>
  <a href="docs/camunda-operate-tokyo.png" target="_blank" rel="noreferrer">
    <img src="docs/camunda-operate-tokyo.png?raw=true" alt="Camunda BPMN Process Flow Tokyo" height="240" style="opacity: 0.8; margin-right: 12px;"/>
  </a>
  <a href="docs/architecture.jpeg" target="_blank" rel="noreferrer">
    <img src="docs/architecture.jpeg?raw=true" alt="Architecture" height="240" style="opacity: 0.8; margin-right: 12px;"/>
  </a>
</p>

Read the formatted documentation on GitHub Pages: [https://github.com/kj-hilger/sovereign-camunda-agent-lab](https://kj-hilger.github.io/sovereign-camunda-agent-lab/)

## ⚡ Summary

* A lightweight, ephemeral **DevOps lab** for rapidly spinning up a complete **Camunda 8 Agentic AI** process application together with an **LLM provider** on NVIDIA Jetson Orin Nano.
* Provision & operate Camunda 8 with **Tool Calls** to a Local LLM on enterprise-style **Kubernetes** within minutes. Don't worry about internet connection at runtime, token costs, update friction, or API changes.
* Use this project as a starting point to understand how all components of a **self-managed enterprise setup** interact and prototype further scenarios. 
* Optimized for the **NVIDIA Jetson Orin Nano 8 GB**, a compact, cost-effective device that is easy to reset and reprovision. It enables quiet, low-energy operation and is perfectly suited for portable, on-site demonstrations in air-gapped environments.

**Table of Contents**
* [⚡ Summary](#-summary)
* [⚠️ Known Limitations & Architectural Caveats](#%EF%B8%8F-known-limitations--architectural-caveats)
* [📋 Prerequisites](#-prerequisites)
* [🏗 Sovereign Foundation](#-sovereign-foundation)
* [♾️ Cluster Provisioning](#cluster-provisioning)
* [⚙️ Agentic Orchestration](#agentic-orchestration)

---

### ⚠️ Known Limitations & Architectural Caveats

While this Lab serves as a rapid local DevOps lab for the enterprise patterns listed above, certain other enterprise patterns are currently simplified:

* **Sovereign Foundation:** Installation scripts directly modify host settings (e.g., Docker daemon, CNI).
* **Cluster Provisioning:** Lacks Build Pipelines, GitOps tooling (Helm only) and UI Observability (pgAdmin, Kubernetes Dashboard).
* **Camunda Scope:** Lacks Camunda Optimize, due to high resource requirements. Lacks Camunda default security configurations. Camunda Modeler is not available for ARM-based Linux.
* **Resource Constraints (Edge):** Camunda 8 together with Ollama local LLM requires 80% of the 8 GB memory. Edge profile requires aggressive resource tuning to avoid OOM issues.

---

## 📋 Prerequisites

### Jetson OS 6.x up to date
- **OS:** Jetson OS with NVIDIA Drivers & CUDA Toolkit installed (can be verified by running `nvidia-smi`). Latest test on 2026/10/18 with Jetson Linux (L4T)-Version: R36.5.2 (Revision 5.2) and JetPack 6.2.3 in mode MAXN SUPER.
- **Package Manager:** `apt` is available.
- **Basic Tools:** `curl`, `wget`, `git`, `gpg`,`tar`, `sed`, `chromium` are available.

### Additional manual installs
- **Kubernetes Tools:** `docker`
- **Dev Tools:** `openjdk-25`, `maven`, (install via `sudo apt install -y openjdk-25-jdk maven`)

### Repository
- Clone the repository:
```bash
git clone https://github.com/kj-hilger/sovereign-camunda-agent-lab.git
```

---

## 🏗 Sovereign Foundation

Scripts to install tools for NVIDIA GPU Acceleration, K8s and Helm.

### Bootstrap

```bash
chmod +x ./sovereign-foundation/install.sh && ./sovereign-foundation/install.sh
```
Note: The bootstrap scripts have been validated on an active JetPack 6.x system. If you run this on a completely fresh JetPack flash and encounter any missing dependencies or script edge-cases, please open an Issue.

<details>
<summary>Documentation of Script Steps</summary>

| Step | Description                                                                | Key Challenges                                                                                                                                                                                        |
|------|----------------------------------------------------------------------------|-------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| 1    | Boot Configuration & Cgroups Check                                         | Missing cgroup parameters cause memory crashes; requires reboot.                                                                                                                                      |
| 2    | Pre-Installation Checks                                                    | Verify Jetson hardware presence. **⚠Overwrites /opt/cni/bin/ ⚠**                                                                                                                                    |
| 3    | Installing NVIDIA Container Runtime & Network Config (containerd, flannel) | CRI unblocking and preconfiguring CNI for a stable network; aligning container runtimes with system‑wide containerd + NVIDIA runtime. **⚠fix versions for cni-plugins v1.4.0 and flannel v1.9.0 ⚠** |
| 4    | Installing K3s                                                             | None specific; standard K3s install using containerd endpoint. Adds k3s kubectl in user path.                                                                                                         |
| 5    | Enabling NVIDIA GPU Support in Kubernetes                                  | The Kubernetes resources for NVIDIA Device Plugin fail on Jetson due to PCI‑based affinity and memory management issues, thus patches and enhancements are needed.                                    |
| 6    | Resource Optimization                                                      | Minimizing log overhead and saving unified memory.                                                                                                                                                    |
| 7    | Installing Tools                                                           | yq for better output formats.                                                                                                                                                                         |

</details>

### Post-Installation
* The installation configures Docker to run without `sudo` for the current user.
* Run check script:
```bash
chmod +x ./sovereign-foundation/check.sh && ./sovereign-foundation/check.sh
```
* Docker and NVIDIA Toolkit will be updated via apt Package Manager.
* K3s starts automatically on reboot via a systemd service.
* To perform a full reset and reinstall: run the uninstall script below, reboot the device, and execute the bootstrap script again.
```bash
chmod +x ./sovereign-foundation/uninstall.sh && ./sovereign-foundation/uninstall.sh 
# **⚠️ deletes all content under /var/lib/docker ⚠️**
```

---

## ♾️Cluster Provisioning

* Manifest Helm-Charts and scripts to provision the cluster self-managed on top of the Sovereign Foundation layer.
* Camunda 8 (minimal cluster size, but including Camunda Agentic AI Connector), PostgreSQL and Ollama (including local LLM Qwen 2.5:3b-instruct and optimizations for flash attention and KV-cache).

### Bootstrap

```bash
chmod +x ./cluster-provisioning/bootstrap.sh && ./cluster-provisioning/bootstrap.sh
```
<details>
<summary>Documentation of Script Steps</summary>

| Step | Component                    | Action & Structural Rationale                                                                                                          |
|:-----|:-----------------------------|:---------------------------------------------------------------------------------------------------------------------------------------|
| 1    | Detecting project path       |                                                                                                                                        |
| 2    | Adding Helm repositories     |                                                                                                                                        |
| 3    | Updating Helm dependencies   | This downloads the official charts and places them as archives in the automatically created folders within each application structure. |
| 4    | Creating Namespaces          |                                                                                                                                        |
| 5    | Setting up PostgreSQL secret | Prompts for password of your choice.                                                                                                   |
| 6    | Helm Deployment              |                                                                                                                                        |
| 7    | Installing Camunda Tools     | zdb                                                                                                                                    |
| 8    | Loading LLM                  | qwen2.5:3b-instruct                                                                                                                                    |

</details>

### Post-Provisioning

* Because all dependencies are provisioned locally, the system requires no external communication with Helm repositories. 
* To update the configuration, modify the values.yaml file(s), then apply the uninstall script below and re-bootstrap the cluster:
```bash
chmod +x ./cluster-provisioning/uninstall.sh && ./cluster-provisioning/uninstall.sh
```

---

## ⚙️Agentic Orchestration

### Application Build & Deploy

```bash
cd agentic-orchestration
mvn clean package
sudo docker build -t agentic-orchestration:1.0.0 .
sudo docker save agentic-orchestration:1.0.0 -o agentic-orchestration-1.0.0.tar
sudo k3s ctr images import agentic-orchestration-1.0.0.tar
sudo kubectl apply -f agentic-orchestration.yaml
# If you want to make a new build, e.g. with a changed .bpmn, set a new version number for each build in the commands and inside agentic-orchestration.yaml.
```

### Operating

The Process Application contains the example Process "Natural Hazard Information".

#### Camunda Tasklist

Open in chromium browser:
```bash
http://localhost:8080/tasklist
```
Log in with demo/demo, go to Processes View, start an instance, enter a city into the free-text input field, for example "Tokyo" and hit the button.
After a few seconds, the LLM-generated response will appear automatically in the task form:
<p align="left">
  <a href="docs/sovereign-camunda-agent-lab" target="_blank" rel="noreferrer">
    <img src="docs/camunda-tasklist-tokyo.png?raw=true" alt="Camunda Form Task Tokyo" height="350" style="opacity: 0.8; margin-right: 12px;"/>
  </a>
</p>

#### Camunda Operate

Open in chromium browser:
```bash
http://localhost:8080/operate
```
Log in with demo/demo, go to Processes View, choose the latest instance and observe its flow and variables.
<p align="left">
  <a href="docs/sovereign-camunda-agent-lab" target="_blank" rel="noreferrer">
    <img src="docs/camunda-operate-tokyo.png?raw=true" alt="Camunda BPMN Process Flow Tokyo" height="450" style="opacity: 0.8; margin-right: 12px;"/>
  </a>
</p>
The agent acted dynamically by evaluating which natural hazards pose a threat to the given city, then selectively invoked the corresponding tools to gather current data for those specific risks only.
For example, when processing "Tokyo", the agent identified risks for earthquakes, volcanoes, and tsunamis - triggering their respective tools and earthquake tool even twice - while skipping the avalanche tool, as Tokyo is not threatened by avalanche.

#### Kubernetes
Monitor resource consumption by executing `kubectl top nodes`, like in this example:
<p align="left">
  <a href="docs/sovereign-camunda-agent-lab" target="_blank" rel="noreferrer">
    <img src="docs/resources-top-nodes.png?raw=true" alt="top nodes" height="40" style="opacity: 0.8; margin-right: 12px;"/>
  </a>
</p>
Peak CPU consumption during tool calls reached 99%, with a total Agentic AI execution duration of ~15 seconds.

---

## 📄 License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.
