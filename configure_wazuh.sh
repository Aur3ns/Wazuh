#!/bin/bash
# ----------------------------------------------------------------------------------------
# Script : configure_wazuh_discord.sh
# Description : Installation et configuration automatique du serveur Wazuh pour
#               relayer les alertes vers Discord via active response.
#               Le script déploie un nouveau ossec.conf, vérifie qu'il est valide XML,
#               et en cas d'erreur, tente de corriger le fichier avec dos2unix.
#
# Auteur : ChatGPT
# Version : 1.1
# ----------------------------------------------------------------------------------------

set -e

# Variables
OSSEC_CONF="/var/ossec/etc/ossec.conf"
BACKUP_CONF="/var/ossec/etc/ossec.conf.bak_$(date '+%Y%m%d_%H%M%S')"
COMMANDS_CONF="/var/ossec/etc/active-response/commands.conf"
ALERT_SCRIPT_DIR="/var/ossec/active-response"
ALERT_SCRIPT="${ALERT_SCRIPT_DIR}/discord_alert.sh"
WEBHOOK_URL="https://discord.com/api/webhooks/1350498539435851892/AUPDvMkhBGv34V-x6RSqDQAg4pVC5nduhQlnkqOdGmjXGa50fwE-V8ALsYNh2n_P6ejK"
MINIMAL_CONF="/tmp/minimal_ossec.conf"

echo "=== Début de la configuration automatique de Wazuh pour Discord ==="

# 1. Sauvegarde de l'ancien ossec.conf s'il existe
if [ -f "$OSSEC_CONF" ]; then
    echo "Sauvegarde de l'ancien fichier ossec.conf dans $BACKUP_CONF..."
    cp "$OSSEC_CONF" "$BACKUP_CONF"
else
    echo "Aucun ossec.conf existant trouvé, création d'un nouveau fichier..."
fi

# 2. Déploiement de la nouvelle configuration ossec.conf
echo "Déploiement de la nouvelle configuration dans $OSSEC_CONF..."
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

  <!-- Active response pour relayer les alertes vers Discord -->
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

# 3. Vérification du fichier ossec.conf

# Vérifier qu'il n'est pas vide
if [ ! -s "$OSSEC_CONF" ]; then
    echo "ERREUR : Le fichier ossec.conf est vide."
    exit 1
fi

# Retirer un éventuel BOM de la première ligne
sed -i '1s/^\xEF\xBB\xBF//' "$OSSEC_CONF"

# Vérifier la validité XML avec xmllint
if ! xmllint --noout "$OSSEC_CONF" 2>/dev/null; then
    echo "ERREUR : Le fichier ossec.conf n'est pas un XML valide. Tentative de correction avec dos2unix..."
    if command -v dos2unix >/dev/null 2>&1; then
        dos2unix "$OSSEC_CONF"
        # Re-vérifier après correction
        if xmllint --noout "$OSSEC_CONF" 2>/dev/null; then
            echo "Correction réussie, le fichier ossec.conf est désormais valide."
        else
            echo "ERREUR : Le fichier ossec.conf reste invalide après dos2unix."
            echo "Déploiement d'un fichier de configuration minimal..."
            cp "$OSSEC_CONF" "$BACKUP_CONF"
            cat << 'EOF' > "$OSSEC_CONF"
<?xml version="1.0" encoding="UTF-8"?>
<ossec_config>
  <global>
    <email_notification>no</email_notification>
  </global>
  <remote>
    <connection>
      <port>1514</port>
      <protocol>tcp</protocol>
    </connection>
  </remote>
</ossec_config>
EOF
            echo "Fichier minimal déployé dans $OSSEC_CONF."
        fi
    else
        echo "dos2unix n'est pas installé. Veuillez l'installer ou corriger manuellement le fichier ossec.conf."
        exit 1
    fi
else
    echo "Le fichier ossec.conf est valide."
fi

# 4. Mise à jour de la commande active response dans commands.conf
echo "Mise à jour de la commande active response dans $COMMANDS_CONF..."
if [ ! -f "$COMMANDS_CONF" ]; then
    echo "Le fichier $COMMANDS_CONF n'existe pas, création du dossier et du fichier..."
    mkdir -p "$(dirname "$COMMANDS_CONF")"
    touch "$COMMANDS_CONF"
fi

# Suppression des entrées existantes pour discord_alert pour éviter les doublons
sed -i '/<name>discord_alert<\/name>/,+3d' "$COMMANDS_CONF"

cat << 'EOF' >> "$COMMANDS_CONF"
<command>
  <name>discord_alert</name>
  <executable>/var/ossec/active-response/discord_alert.sh</executable>
  <timeout_allowed>yes</timeout_allowed>
</command>
EOF
echo "Commande discord_alert ajoutée dans $COMMANDS_CONF."

# 5. Création du script discord_alert.sh
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
echo "Script $ALERT_SCRIPT créé et rendu exécutable."

# 6. Redémarrage du service Wazuh Manager
echo "Redémarrage du service wazuh-manager..."
if systemctl restart wazuh-manager; then
    echo "Le service wazuh-manager a été redémarré avec succès."
else
    echo "ERREUR : Le service wazuh-manager n'a pas pu être redémarré. Vérifiez les logs."
    exit 1
fi

echo "=== Configuration et installation de Wazuh pour Discord terminées avec succès ! ==="
