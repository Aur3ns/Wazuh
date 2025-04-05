#!/bin/bash
# ----------------------------------------------------------------------------------------
# Script : install_rsyslog_wazuh_agent.sh
# Description : Installe et configure rsyslog pour surveiller :
#               - Fail2ban, Osquery, Chrony, Auditd, Lynis, Samba,
#               - les logs système (/var/log/syslog), d'authentification (/var/log/auth.log)
#               - les logs de cron (/var/log/cron)
#               Puis installe le Wazuh Agent et le configure pour envoyer ses logs
#               vers le serveur principal (Wazuh Manager).
# ----------------------------------------------------------------------------------------

set -e

# Paramètres modifiables
WAZUH_MANAGER_IP="10.10.0.24"  # Adresse IP du serveur principal Wazuh
LOG_FILE="/var/log/rsyslog_install.log"

echo "$(date '+%Y-%m-%d %H:%M:%S') - Début de l'installation et configuration de rsyslog" | tee -a "$LOG_FILE"

#########################################
# Partie 1 : Installation et configuration de rsyslog
#########################################

# Installation de rsyslog si nécessaire
if ! command -v rsyslogd >/dev/null 2>&1; then
    echo "$(date '+%Y-%m-%d %H:%M:%S') - rsyslog n'est pas installé, installation..." | tee -a "$LOG_FILE"
    apt-get update && apt-get install -y rsyslog
else
    echo "$(date '+%Y-%m-%d %H:%M:%S') - rsyslog est déjà installé." | tee -a "$LOG_FILE"
fi

# Activation et redémarrage de rsyslog
echo "$(date '+%Y-%m-%d %H:%M:%S') - Activation et redémarrage de rsyslog" | tee -a "$LOG_FILE"
systemctl enable rsyslog
systemctl restart rsyslog

# Création du fichier de configuration personnalisé pour rsyslog
CONFIG_FILE="/etc/rsyslog.d/50-custom-logs.conf"
echo "$(date '+%Y-%m-%d %H:%M:%S') - Déploiement du fichier de configuration rsyslog : $CONFIG_FILE" | tee -a "$LOG_FILE"

cat << 'EOF' > "$CONFIG_FILE"
# Chargement du module imfile pour surveiller les fichiers journaux personnalisés
module(load="imfile" PollingInterval="10")

########### Surveillance des logs spécifiques ###########

# Fail2ban
input(type="imfile"
      File="/var/log/fail2ban.log"
      Tag="fail2ban:"
      Severity="info"
      Facility="local7")

# Osquery - résultats
input(type="imfile"
      File="/var/log/osquery/osqueryd.results.log"
      Tag="osquery-results:"
      Severity="info"
      Facility="local7")

# Osquery - erreurs
input(type="imfile"
      File="/var/log/osquery/osqueryd.ERROR"
      Tag="osquery-errors:"
      Severity="error"
      Facility="local7")

# Auditd
input(type="imfile"
      File="/var/log/audit/audit.log"
      Tag="auditd:"
      Severity="info"
      Facility="local7")

# Lynis
input(type="imfile"
      File="/var/log/lynis.log"
      Tag="lynis:"
      Severity="info"
      Facility="local7")

# Samba (exemple : log.smbd)
input(type="imfile"
      File="/var/log/samba/log.smbd"
      Tag="samba-smbd:"
      Severity="info"
      Facility="local7")

########### Surveillance des logs système et de sécurité ###########

# Logs d'authentification (sécurité)
input(type="imfile"
      File="/var/log/auth.log"
      Tag="auth:"
      Severity="info"
      Facility="auth")

# Journaux de cron
input(type="imfile"
      File="/var/log/cron.log"
      Tag="cron:"
      Severity="info"
      Facility="local7")

# ClamAV Rapport de Détection
input(type="imfile"
      File="/var/log/clamav/clamd.log"
      Tag="clamav:"
      Severity="info"
      Facility="local6")

local6.* /var/syslog
local6.* /var/log/clamav/clamd-forwarding.log
EOF

echo "$(date '+%Y-%m-%d %H:%M:%S') - Fichier de configuration rsyslog déployé." | tee -a "$LOG_FILE"
echo "$(date '+%Y-%m-%d %H:%M:%S') - Redémarrage de rsyslog" | tee -a "$LOG_FILE"
systemctl restart rsyslog
echo "$(date '+%Y-%m-%d %H:%M:%S') - Installation et configuration de rsyslog terminées avec succès." | tee -a "$LOG_FILE"

#########################################
# Partie 2 : Installation et configuration du Wazuh Agent
#########################################

echo "$(date '+%Y-%m-%d %H:%M:%S') - Début de l'installation du Wazuh Agent" | tee -a "$LOG_FILE"

# Ajout de la clé GPG et du dépôt Wazuh
echo "$(date '+%Y-%m-%d %H:%M:%S') - Configuration du dépôt Wazuh" | tee -a "$LOG_FILE"
curl -s https://packages.wazuh.com/key/GPG-KEY-WAZUH | apt-key add -
echo "deb https://packages.wazuh.com/4.x/apt/ stable main" > /etc/apt/sources.list.d/wazuh.list
apt-get update

# Installation du Wazuh Agent
if ! dpkg -l | grep -q wazuh-agent; then
    echo "$(date '+%Y-%m-%d %H:%M:%S') - Installation du paquet wazuh-agent" | tee -a "$LOG_FILE"
    apt-get install -y wazuh-agent
else
    echo "$(date '+%Y-%m-%d %H:%M:%S') - Le paquet wazuh-agent est déjà installé." | tee -a "$LOG_FILE"
fi

# Configuration du Wazuh Agent pour pointer vers le serveur principal
OSSEC_CONF="/var/ossec/etc/ossec.conf"
if [ -f "$OSSEC_CONF" ]; then
    echo "$(date '+%Y-%m-%d %H:%M:%S') - Mise à jour de ossec.conf pour pointer vers $WAZUH_MANAGER_IP" | tee -a "$LOG_FILE"
    # On modifie (ou insère) l'adresse du serveur dans la section <client>
    if grep -q "<address>" "$OSSEC_CONF"; then
        sed -i "s|<address>.*</address>|<address>$WAZUH_MANAGER_IP</address>|" "$OSSEC_CONF"
    else
        # Ajout simple dans la section <client> (à adapter selon votre configuration existante)
        sed -i "/<client>/ a\    <server>\n      <address>$WAZUH_MANAGER_IP</address>\n      <port>1514</port>\n    </server>" "$OSSEC_CONF"
    fi
else
    echo "$(date '+%Y-%m-%d %H:%M:%S') - ERREUR : Fichier ossec.conf introuvable." | tee -a "$LOG_FILE"
fi

# Activation et redémarrage du service wazuh-agent
echo "$(date '+%Y-%m-%d %H:%M:%S') - Activation et redémarrage du service wazuh-agent" | tee -a "$LOG_FILE"
systemctl enable wazuh-agent
systemctl restart wazuh-agent

echo "$(date '+%Y-%m-%d %H:%M:%S') - Installation et configuration du Wazuh Agent terminées avec succès." | tee -a "$LOG_FILE"

echo "$(date '+%Y-%m-%d %H:%M:%S') - Déploiement complet terminé avec succès." | tee -a "$LOG_FILE"
