# Sovereign Camunda Agent Lab 🚀

<div align="center">
  <img src="docs/jetson.jpg" alt="Jetson Orin Nano" style="max-width: 48%; min-width: 280px; vertical-align: middle;" />
  <img src="docs/target-architecture.jpeg" alt="Target Architecture Diagram" style="max-width: 48%; min-width: 280px; vertical-align: middle;" />
</div>

## ⚡ Summary

* A lightweight, ephemeral DevOps lab for rapidly spinning up and tearing down Camunda 8, Ollama, and Keycloak on edge devices.
* Demonstrates core enterprise patterns — including NVIDIA GPU Acceleration, Self-Managed Camunda, local LLMs, GitOps (App-of-Apps), Air-gapped Data Sovereignty, and Agentic AI Observability — each implemented in its simplest form.
* Designed to run and observe Camunda Agentic AI BPMN processes while simulating enterprise workflows like GitOps scaling and disaster recovery.
* Designed primarily for the NVIDIA Jetson Orin Nano (Debian-based edge device), assuming a dedicated device that can be easily wiped and reprovisioned.
* A high-power desktop profile is also provided for development, but caution is advised: its host-level configuration scripts are highly invasive and intended for disposable or dedicated hardware only.

**Table of Contents**
* [⚡ Summary](#-summary)
* [🚀 Roadmap & Phases](#-roadmap--phases)
* [⚠️ Known Limitations & Architectural Caveats](#%EF%B8%8F-known-limitations--architectural-caveats)
* [📋 Prerequisites](#-prerequisites)
* [🏗 Sovereign Infra](#-sovereign-infra)
* [♾️ Cluster GitOps](#%EF%B8%8F-cluster-gitops)
* [⚙️ Camunda Process](#%EF%B8%8F-camunda-process)
* [💻 Alternative Profile for High Power Desktop](#-alternative-profile-for-high-power-desktop)

---

### 🚀 Roadmap & Phases

- **Sovereign Infra:** under test
- **Cluster Gitops:** under development
- **Camunda Process:** planned

---

### ⚠️ Known Limitations & Architectural Caveats

While this Lab serves as a rapid local DevOps lab for the enterprise patterns listed above, certain other enterprise patterns are currently simplified:

* **Host-Level Bootstrapping:** Installation scripts currently modify host configurations directly (e.g., Docker daemon, CNI).
* **Kubernetes Heterogeneity:** Uses Minikube for Desktop and K3s for Edge. *Planned: Standardizing on K3s across all profiles.*
* **Resource Constraints (Edge):** Camunda 8 together with local LLMs requires significant memory. Edge profiles require aggressive resource tuning to avoid OOM issues.

---

## 📋 Prerequisites
- **OS:** Debian-based Linux with NVIDIA Drivers & CUDA Toolkit installed (can be verified by running `nvidia-smi`).
- **Package Manager:** `apt` is available.
- **Basic Tools:** `curl`, `git`, `gpg`, `sed` are installed.
- **Kubernetes Tools:** `kubectl` is installed and available in your PATH.
- **Connectivity:** Internet access is required during the bootstrap process.
- **Repository:** You cloned the repo:
```bash
git clone https://github.com/kj-hilger/sovereign-camunda-agent-lab.git
```

---

## 🏗 Sovereign Infra

Scripts to install tools for NVIDIA GPU Acceleration, K8s and GitOps.

### Bootstrap

```bash
chmod +x ./sovereign-infra/install-jetson.sh
./sovereign-infra/install-jetson.sh
```

#### Detailed documentation

| Step | Description                                                                | Key Challenges                                                                                                                                                                                        |
|------|----------------------------------------------------------------------------|-------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| 0    | Boot Configuration & Cgroups Check                                         | Missing cgroup parameters cause memory crashes; requires reboot.                                                                                                                                      |
| 1    | Pre-Installation Checks                                                    | Verify Jetson hardware presence. **⚠Overwrites /opt/cni/bin/ ⚠**                                                                                                                                    |
| 2    | Installing NVIDIA Container Runtime & Network Config (containerd, flannel) | CRI unblocking and preconfiguring CNI for a stable network; aligning container runtimes with system‑wide containerd + NVIDIA runtime. **⚠fix versions for cni-plugins v1.4.0 and flannel v1.9.0 ⚠** |
| 3    | Installing K3s                                                             | None specific; standard K3s install using containerd endpoint.                                                                                                                                        |
| 4    | Enabling NVIDIA GPU Support in Kubernetes                                  | The Kubernetes resources for NVIDIA Device Plugin fail on Jetson due to PCI‑based affinity and memory management issues, thus patches and enhancements are needed.                                    |
| 5    | Installing ArgoCD                                                          | Annotation limits for large manifests; requires server‑side apply.                                                                                                                                    |
| 6    | Resource Optimization                                                      | Minimizing log overhead and saving unified memory.                                                                                                                                                    |
| 7    | Verification                                                               | Final checks; ensure GPU registration and node allocatable resources.                                                                                                                                 |


### Post-Installation
* The installation configures Docker to run without `sudo` for the current user.
* Run check script:
```bash
chmod +x ./sovereign-infra/check-jetson.sh
./sovereign-infra/check-jetson.sh
```
* Docker and NVIDIA Toolkit will be updated via apt Package Manager.

### Start again after reboot
* K3s starts automatically via systemd service.

### Delete All and Reinstall (with latest software versions)

```bash
chmod +x ./sovereign-infra/k3s-uninstall.sh  # **⚠️ deletes all content under /var/lib/docker ⚠️**
./sovereign-infra/k3s-uninstall.sh

# reboot

# run bootstrap script again
```

---

## ♾️Cluster GitOps

GitOps App-of-Apps Helm-Charts and scripts to install the Camunda 8 (including Camunda Agentic AI Connector, PostgreSQL, Keycloak) and Ollama (including local LLM) self-managed on top of the Sovereign Infra layer. You have air-gapped Data Sovereignty at runtime.

### Bootstrap

```bash
chmod +x ./cluster-gitops/bootstrap.sh
./cluster-gitops/bootstrap.sh
```

#### Detailed documentation

| Step  | Component                        | Action & Structural Rationale                                                                                                                                                                                                                              |
|:------|:---------------------------------|:-----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| **1** | **Detecting project path**       | Applying /cluster-gitops/bootstrap/root-app.yaml triggers the App-of-Apps controller based on the target environment profile.                                                                                                                              |
| **2** | **Adding Helm repositories**     | PostgreSQL and Keycloak are spun up first to guarantee relational data integrity and secure OIDC endpoints before the orchestrator launches.                                                                                                               |
| **3** | **Updating Helm dependencies**   | This downloads the official charts and places them as archives in the automatically created folders within each application structure. These local paths are configured in ArgoCD so the system can access the components without any internet connection. |
| **4** | **Bootstrapping ArgoCD**         | ArgoCD continuously monitors this repository and reconciles the desired state.                                                                                                                                                                             |
| **5** | **Retrieving Login information** | **⚠️ Sensitive Login information is written to terminal output. ⚠️**                                                                                                                                                                                       |


### Post-Installation

ArgoCD monitors the apps and charts directories alongside the Chart.lock files. It handles the internal unzipping of the pre-loaded archives and applies the corresponding values.yaml configurations automatically. Because all dependencies are provisioned locally, the system requires no external communication with Helm repositories. To perform updates, modify the version in the Chart.yaml file, execute a local helm dependency update, and synchronize the updated files. ArgoCD then completes the reconciliation process entirely offline.


### Delete All

```bash
chmod +x ./cluster-gitops/uninstall.sh
./cluster-gitops/uninstall.sh
```

---

## ⚙️Camunda Process

Leverages Camunda 8 Deterministic Orchestration to manage agentic decision flows, ensuring full process visibility, execution logging and Observability. The BPMN Pattern Agentic AI as Subprocess together with a human task ensures "Human-in-the-Loop".

### Bootstrap

```
# planned Process Name: Agentic Orchestrator
```

### Run instances

```
# planned: Link to Operate
```

### Observe Audit Trail
*   **Prompt & Response:** Full visibility into the exact instructions and raw LLM outputs.
*   **Reasoning Path:** Exposure of intermediate "Chain of Thought" (CoT) and logic steps.
*   **Tool Calls:** Precise logging of which internal/external tools or APIs the agent invoked.
*   **Memory Context:** A snapshot of short-term and long-term memory state at the moment of decision.

---

## Alternative Profile for High Power Desktop

| Environment            | Specs (Tested)                           | Use Case                                               |
|:-----------------------|:-----------------------------------------|:-------------------------------------------------------|
| **High-Power Desktop** | 64 GB RAM / 16 GB VRAM (RTX)             | Development, Heavy Load Testing, Large LLMs            |
| **Edge AI (Jetson)**   | 16 GB Unified Memory (Orin Nano)         | Industrial Edge, Power-Efficient continuous operations |

```
chmod +x ./sovereign-infra/install-desktop.sh
./sovereign-infra/install-desktop.sh

# No check script currently available for desktop.

# Delete All and reinstall
chmod +x ./sovereign-infra/uninstall-desktop.sh
./sovereign-infra/uninstall-desktop.sh

# reboot

# run bootstrap script again

# Start again after reboot
minikube start \
--driver=docker \
--cpus=12 \
--memory=32768 \
--gpus=all \
--addons=ingress

# Delete All
minikube delete --all --purge

# Camunda
# This layer is equal for all hardware profiles.
```

### Detailed documentation for Desktop

| Step | Description                                                                | Key Challenges                                                                                                                                                                                       |
|------|----------------------------------------------------------------------------|------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| 1    | NVIDIA Driver & CUDA Check                                                 | Drivers and CUDA toolkit must be manually installed on the host OS beforehand.                                                                                                                       |
| 2    | Installing & Configuring Docker                                            | Non-root user permissions require group modifications (`usermod`), often needing a full system logout/login before the user can interact with the Docker daemon.                                     |
| 3    | NVIDIA Container Toolkit Config                                            | Must target the **host Docker engine** specifically via direct `/etc/docker/daemon.json` configuration, **⚠️ overwrites existing ⚠**, ensuring GPU runtime sharing into downstream containers.      |
| 4    | Installing Minikube & Helm                                                 | Requires a separate, native `kubectl` installation on the host OS to prevent command-not-found errors during automated script execution.                                                             |
| 5    | Bootstrapping Minikube (Tuning)                                            | Enforces Docker runtime internally within the cluster to allow `--gpus=all`. **⚠️Allocates 32768 MB RAM and 12 CPUs. ⚠**                                                                            |
| 6    | Installing ArgoCD                                                          | `--server-side` apply required, adds a desktop-specific patch to `NodePort` for direct access via the local web browser.                                                                             |

---

## 📄Docs

- Architectural diagrams
- Architectural decisions
- Pictures

---

## 📄 License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.
