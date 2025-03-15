#!/bin/bash
# ----------------------------------------------------------------------------------------
# Script : configure_wazuh_discord.sh
# Description : Configure automatiquement le serveur Wazuh pour désactiver les
#               notifications par e-mail et relayer les alertes vers Discord via active response.
#
# Auteur : ChatGPT
# Version : 1.0
# ----------------------------------------------------------------------------------------

set -e

# Variables
OSSEC_CONF="/var/ossec/etc/ossec.conf"
BACKUP_CONF="/var/ossec/etc/ossec.conf.bak_$(date '+%Y%m%d_%H%M%S')"
COMMANDS_CONF="/var/ossec/etc/active-response/commands.conf"
ALERT_SCRIPT_DIR="/var/ossec/active-response"
ALERT_SCRIPT="${ALERT_SCRIPT_DIR}/discord_alert.sh"
WEBHOOK_URL="https://discord.com/api/webhooks/1350498539435851892/AUPDvMkhBGv34V-x6RSqDQAg4pVC5nduhQlnkqOdGmjXGa50fwE-V8ALsYNh2n_P6ejK"

echo "=== Configuration automatique du serveur Wazuh pour Discord ==="

# 1. Sauvegarde du fichier de configuration existant
if [ -f "$OSSEC_CONF" ]; then
    echo "Sauvegarde de l'ancien ossec.conf dans $BACKUP_CONF"
    cp "$OSSEC_CONF" "$BACKUP_CONF"
else
    echo "ERREUR : $OSSEC_CONF introuvable."
    exit 1
fi

# 2. Déploiement du nouveau fichier de configuration ossec.conf
echo "Déploiement de la nouvelle configuration ossec.conf..."
cat << 'EOF' > "$OSSEC_CONF"
<?xml version="1.0" encoding="UTF-8"?>
<ossec_config>
  <!-- Configuration globale -->
  <global>
    <email_notification>no</email_notification>
    <logall>yes</logall>
    <log_level>1</log_level>
  </global>

  <!-- Configuration de la réception des agents -->
  <remote>
    <connection>
      <port>1514</port>
      <protocol>tcp</protocol>
    </connection>
  </remote>

  <!-- Surveillance des logs locaux du manager -->
  <localfile>
    <log_format>syslog</log_format>
    <location>/var/ossec/logs/ossec.log</location>
  </localfile>

  <!-- Réponse active pour relayer les alertes vers Discord -->
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
echo "Nouveau fichier ossec.conf déployé."

# 3. Configuration de la commande active response dans commands.conf
# On ajoute ou met à jour la commande "discord_alert"
echo "Mise à jour de $COMMANDS_CONF avec la commande discord_alert..."
if [ -f "$COMMANDS_CONF" ]; then
    # On supprime toute ligne existante contenant discord_alert pour éviter les doublons
    sed -i '/<name>discord_alert<\/name>/,+3d' "$COMMANDS_CONF"
else
    echo "Le fichier $COMMANDS_CONF n'existe pas, création..."
    mkdir -p "$(dirname "$COMMANDS_CONF")"
    touch "$COMMANDS_CONF"
fi

cat << 'EOF' >> "$COMMANDS_CONF"
<command>
  <name>discord_alert</name>
  <executable>/var/ossec/active-response/discord_alert.sh</executable>
  <timeout_allowed>yes</timeout_allowed>
</command>
EOF
echo "Commande discord_alert ajoutée à $COMMANDS_CONF."

# 4. Création du script discord_alert.sh
echo "Création du script d'alerte Discord..."
mkdir -p "$ALERT_SCRIPT_DIR"
cat << EOF > "$ALERT_SCRIPT"
#!/bin/bash
# Script pour envoyer une alerte Wazuh vers Discord via webhook
WEBHOOK_URL="$WEBHOOK_URL"
ALERT_MESSAGE="\$1"
curl -H "Content-Type: application/json" -X POST -d "{\"content\": \"Alerte Wazuh : \$ALERT_MESSAGE\"}" "\$WEBHOOK_URL"
EOF

chmod +x "$ALERT_SCRIPT"
echo "Script $ALERT_SCRIPT créé et rendu exécutable."

# 5. Redémarrage du service Wazuh Manager
echo "Redémarrage du service wazuh-manager..."
if systemctl restart wazuh-manager; then
    echo "Le service wazuh-manager a été redémarré avec succès."
else
    echo "ERREUR : Le service wazuh-manager n'a pas pu être redémarré."
    exit 1
fi

echo "=== Configuration de Wazuh pour Discord terminée avec succès ! ==="
