# Wazuh SIEM Automation Scripts

A suite of Shell and PowerShell scripts to automate the deployment and management of a Wazuh SIEM infrastructure—integrating antivirus, client onboarding, and custom detection rules.

---

## 🚀 Key Features

- **Server Bootstrap**  
  Deploy Wazuh manager, indexer and dashboard with a single `waz.sh` script.

- **Antivirus Integration**  
  Auto-deploy ClamAV for full-system scanning and forward alerts to Wazuh via `clamav-scan.sh`.

- **Linux Client Onboarding**  
  Configure rsyslog and install/register the Wazuh agent in one step with `client_log.sh`.

- **Windows Client Onboarding**  
  Harden Windows logging with Sysmon, deploy the Wazuh agent and set up event forwarding using `client_log.ps1`.

- **Key Management**  
  Generate and register enrollment keys for multiple agents through `keys.sh`.

- **Custom Detection Rules**  
  Ship advanced local rules (e.g., DCSync, Golden Ticket) using the `local-rules.xml` file.

---

## 🛠️ Script-Based Automation

Each script targets a specific task:

- **`waz.sh`**: Bootstraps the Wazuh server components.  
- **`clamav-scan.sh`**: Sets up ClamAV scans and log forwarding.  
- **`client_log.sh`**: Onboards Linux clients (rsyslog + Wazuh agent).  
- **`client_log.ps1`**: Onboards Windows clients (Sysmon + Wazuh agent).  
- **`keys.sh`**: Manages agent enrollment keys.  
- **`local-rules.xml`**: Defines custom Wazuh detection rules.

---

## 💻 Compatibility

- **Server:** Any Linux distribution with bash, curl, sudo and gnupg.  
- **Clients:** Linux (bash) and Windows 10 / Windows Server with PowerShell.
