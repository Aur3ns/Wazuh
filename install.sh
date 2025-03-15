#!/bin/bash
# ----------------------------------------------------------------------------------------
# Script : install_and_configure_wazuh_discord.sh
# Description : Installe la stack Wazuh (Indexer, Manager, Dashboard, Filebeat) sur
#               Debian/Ubuntu et configure le serveur Wazuh pour relayer les alertes
#               vers Discord via active response.
#
# Auteur : ChatGPT
# Version : 1.0
# ----------------------------------------------------------------------------------------

set -e

# Variables de configuration
WEBHOOK_URL="https://discord.com/api/webhooks/1350498539435851892/AUPDvMkhBGv34V-x6RSqDQAg4pVC5nduhQlnkqOdGmjXGa50fwE-V8ALsYNh2n_P6ejK"
OSSEC_CONF="/var/ossec/etc/ossec.conf"
COMMANDS_CONF="/var/ossec/etc/active-response/commands.conf"
ALERT_SCRIPT_DIR="/var/ossec/active-response"
ALERT_SCRIPT="${ALERT_SCRIPT_DIR}/discord_alert.sh"

echo "=== Mise à jour du système et installation des dépendances ==="
apt update && apt upgrade -y
apt install -y gnupg apt-transport-https curl debconf adduser procps libxml2-utils dos2unix

echo "=== Import de la clé GPG de Wazuh et ajout du dépôt ==="
curl -s https://packages.wazuh.com/key/GPG-KEY-WAZUH | gpg --no-default-keyring --keyring /usr/share/keyrings/wazuh.gpg --import
chmod 644 /usr/share/keyrings/wazuh.gpg
echo "deb [signed-by=/usr/share/keyrings/wazuh.gpg] https://packages.wazuh.com/4.x/apt/ stable main" > /etc/apt/sources.list.d/wazuh.list

echo "=== Ajout du dépôt Elastic pour Filebeat ==="
wget -qO - https://artifacts.elastic.co/GPG-KEY-elasticsearch | apt-key add -
echo "deb https://artifacts.elastic.co/packages/8.x/apt stable main" > /etc/apt/sources.list.d/elastic-8.x.list

echo "=== Mise à jour des dépôts ==="
apt update

echo "=== Installation de la stack Wazuh et Filebeat ==="
apt install -y wazuh-indexer wazuh-manager wazuh-dashboard filebeat

echo "=== Téléchargement de la configuration Filebeat pour Wazuh ==="
curl -so /etc/filebeat/filebeat.yml https://packages.wazuh.com/4.11/tpl/wazuh/filebeat/filebeat.yml

echo "=== Installation du module Wazuh pour Filebeat ==="
curl -s https://packages.wazuh.com/4.x/filebeat/wazuh-filebeat-0.4.tar.gz | tar -xvz -C /usr/share/filebeat/module

# --------------------------------------------------------------------------
# Partie Configuration de Wazuh Manager pour Discord
# --------------------------------------------------------------------------
echo "=== Déploiement de la configuration Wazuh pour Discord ==="

# Sauvegarde de l'ancien ossec.conf (s'il existe)
if [ -f "$OSSEC_CONF" ]; then
    cp "$OSSEC_CONF" "${OSSEC_CONF}.bak_$(date '+%Y%m%d_%H%M%S')"
    echo "Ancien ossec.conf sauvegardé."
fi

# Déploiement d'un nouveau ossec.conf minimal avec active response vers Discord
cat << 'EOF' > "$OSSEC_CONF"
<?xml version="1.0" encoding="UTF-8"?>
<ossec_config>
  <!-- Configuration globale minimale -->
  <global>
    <email_notification>no</email_notification>
    <logall>yes</logall>
    <log_level>1</log_level>
  </global>

  <!-- Réception des agents -->
  <remote>
    <connection>
      <port>1514</port>
      <protocol>tcp</protocol>
    </connection>
  </remote>

  <!-- Journalisation locale du manager -->
  <localfile>
    <log_format>syslog</log_format>
    <location>/var/ossec/logs/ossec.log</location>
  </localfile>

  <!-- Active response vers Discord -->
  <active-response>
    <command>discord_alert</command>
    <location>local</location>
    <timeout>600</timeout>
  </active-response>

  <!-- Surveillance d'intégrité des fichiers -->
  <syscheck>
    <frequency>7200</frequency>
    <directories realtime="yes" check_all="yes">/etc,/usr/bin,/usr/sbin</directories>
  </syscheck>

  <!-- Détection de rootkits -->
  <rootcheck>
    <frequency>7200</frequency>
    <scan_on_start>yes</scan_on_start>
  </rootcheck>

  <!-- Inclusion des règles de base -->
  <rules>
    <include>rules_config.xml</include>
  </rules>
</ossec_config>
EOF
echo "Nouveau ossec.conf déployé."

# Correction d'éventuels problèmes d'encodage : suppression d'un BOM si présent
sed -i '1s/^\xEF\xBB\xBF//' "$OSSEC_CONF"
if ! xmllint --noout "$OSSEC_CONF" 2>/dev/null; then
    echo "ERREUR : Le fichier ossec.conf n'est pas un XML valide. Tentative de correction avec dos2unix..."
    dos2unix "$OSSEC_CONF"
    if ! xmllint --noout "$OSSEC_CONF" 2>/dev/null; then
        echo "ERREUR : Le fichier ossec.conf reste invalide. Veuillez le corriger manuellement."
        exit 1
    else
        echo "Fichier ossec.conf corrigé."
    fi
else
    echo "Le fichier ossec.conf est valide."
fi

# Ajustement des permissions pour que le service Wazuh puisse lire la configuration
echo "Ajustement des permissions sur /var/ossec/etc et ossec.conf..."
chown -R wazuh:wazuh /var/ossec/etc
chmod 770 /var/ossec/etc
chmod 660 "$OSSEC_CONF"
echo "Permissions mises à jour."

# Mise à jour de la commande active response dans commands.conf
echo "Mise à jour de la commande active response dans $COMMANDS_CONF..."
if [ ! -f "$COMMANDS_CONF" ]; then
    mkdir -p "$(dirname "$COMMANDS_CONF")"
    touch "$COMMANDS_CONF"
fi
sed -i '/<name>discord_alert<\/name>/,+3d' "$COMMANDS_CONF"
cat << 'EOF' >> "$COMMANDS_CONF"
<command>
  <name>discord_alert</name>
  <executable>/var/ossec/active-response/discord_alert.sh</executable>
  <timeout_allowed>yes</timeout_allowed>
</command>
EOF
echo "Commande discord_alert mise à jour dans $COMMANDS_CONF."

# Création du script discord_alert.sh
echo "Création du script $ALERT_SCRIPT..."
mkdir -p "$ALERT_SCRIPT_DIR"
cat << EOF > "$ALERT_SCRIPT"
#!/bin/bash
# Script pour envoyer une alerte Wazuh vers Discord via webhook
WEBHOOK_URL="$WEBHOOK_URL"
ALERT_MESSAGE="\$1"
curl -H "Content-Type: application/json" -X POST -d "{\"content\": \"Alerte Wazuh : \$ALERT_MESSAGE\"}" "\$WEBHOOK_URL"
EOF
chmod +x "$ALERT_SCRIPT"
echo "Script discord_alert.sh créé et rendu exécutable."

# --------------------------------------------------------------------------
# Redémarrage des services Wazuh
# --------------------------------------------------------------------------
echo "Redémarrage du service wazuh-indexer..."
systemctl restart wazuh-indexer || echo "Redémarrage de wazuh-indexer non nécessaire sur ce serveur."

echo "Redémarrage du service wazuh-manager..."
systemctl restart wazuh-manager

echo "Redémarrage du service wazuh-dashboard..."
systemctl restart wazuh-dashboard

echo "Redémarrage du service filebeat..."
systemctl restart filebeat

echo "=== Installation et configuration de Wazuh avec Discord terminées avec succès ! ==="
