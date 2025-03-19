#!/bin/bash
# ----------------------------------------------------------------------------------------
# Script : configure_wazuh_discord.sh
# Description : Fusionne la configuration existante de Wazuh avec l'active response Discord.
# ----------------------------------------------------------------------------------------

set -e

# 📌 Variables
WEBHOOK_URL="https://discord.com/api/webhooks/1350498539435851892/AUPDvMkhBGv34V-x6RSqDQAg4pVC5nduhQlnkqOdGmjXGa50fwE-V8ALsYNh2n_P6ejK"
OSSEC_CONF="/var/ossec/etc/ossec.conf"
COMMANDS_CONF="/var/ossec/etc/active-response/commands.conf"
ALERT_SCRIPT_DIR="/var/ossec/active-response"
ALERT_SCRIPT="${ALERT_SCRIPT_DIR}/discord_alert.sh"

echo "=== Fusion de la configuration existante de Wazuh avec l'active response Discord ==="

# 🔹 Vérification de la présence des outils nécessaires
if ! command -v xmlstarlet &> /dev/null; then
    echo "Installation de xmlstarlet..."
    apt update && apt install -y xmlstarlet
fi

# 🔹 Sauvegarde de l'ancien ossec.conf
if [ -f "$OSSEC_CONF" ]; then
    cp "$OSSEC_CONF" "${OSSEC_CONF}.bak_$(date '+%Y%m%d_%H%M%S')"
    echo "Ancien ossec.conf sauvegardé."
else
    echo "ERREUR : Fichier ossec.conf introuvable !"
    exit 1
fi

# 🔹 Vérifier si <active-response> existe, sinon l'ajouter juste avant </ossec_config>
if ! grep -q "<active-response>" "$OSSEC_CONF"; then
    echo "Ajout du bloc <active-response>..."
    sed -i '/<\/ossec_config>/i \ \n  <active-response>\n  </active-response>\n' "$OSSEC_CONF"
fi

# 🔹 Vérifier si la commande discord_alert est déjà présente
if ! grep -q "<command>discord_alert</command>" "$OSSEC_CONF"; then
    echo "Ajout de la commande discord_alert dans active-response..."
    sed -i '/<active-response>/a \    <command>discord_alert</command>\n    <location>local</location>\n    <timeout>600</timeout>' "$OSSEC_CONF"
else
    echo "La commande discord_alert est déjà présente dans ossec.conf."
fi

# 🔹 Vérification du fichier XML
if ! xmllint --noout "$OSSEC_CONF" 2>/dev/null; then
    echo "ERREUR : ossec.conf est invalide après modification. Annulation des changements..."
    mv "${OSSEC_CONF}.bak_$(date '+%Y%m%d_%H%M%S')" "$OSSEC_CONF"
    exit 1
else
    echo "✅ ossec.conf mis à jour avec succès."
fi

# 🔹 Ajustement des permissions
chown -R wazuh:wazuh /var/ossec/etc
chmod 770 /var/ossec/etc
chmod 660 "$OSSEC_CONF"

# 🔹 Mise à jour de la commande active response dans commands.conf
if [ ! -f "$COMMANDS_CONF" ]; then
    mkdir -p "$(dirname "$COMMANDS_CONF")"
    touch "$COMMANDS_CONF"
fi
if ! grep -q "<name>discord_alert</name>" "$COMMANDS_CONF"; then
    cat << 'EOF' >> "$COMMANDS_CONF"
<command>
  <name>discord_alert</name>
  <executable>/var/ossec/active-response/discord_alert.sh</executable>
  <timeout_allowed>yes</timeout_allowed>
</command>
EOF
    echo "✅ Commande discord_alert ajoutée dans $COMMANDS_CONF."
else
    echo "ℹ️ La commande discord_alert est déjà présente dans $COMMANDS_CONF."
fi

# 🔹 Création du script discord_alert.sh
mkdir -p "$ALERT_SCRIPT_DIR"
cat << EOF > "$ALERT_SCRIPT"
#!/bin/bash
#
# Script : discord_alert.sh
# Objectif : Envoyer une alerte Wazuh vers Discord via webhook
#

# 1) Définir l’URL de ton webhook Discord
#    Remplace l'URL ci-dessous par la tienne.
WEBHOOK_URL="https://discord.com/api/webhooks/TON_WEBHOOK_ID/TON_TOKEN"

# 2) Debug (optionnel) : enregistrer les arguments reçus par Wazuh
echo "[$(date)] ARGS: $@" >> /tmp/discord_alert_debug.log

# 3) Récupérer les arguments passés par Wazuh Active Response
ACTION="$1"       # add/delete
IP="$2"           # IP concernée
USER="$3"         # Nom d’utilisateur (si présent)
RULE_ID="$4"      # ID de la règle (ex: 5716, 100001, etc.)
LOCATION="$5"     # local/global
FULL_LOG="$6"     # Le log complet qui a déclenché l’alerte (souvent)
DECODER="$7"      # Nom du décodeur (ex: sshd, syslog, etc.)

# 4) Construire un message plus complet pour Discord
MESSAGE="**Alerte Wazuh**\n"
MESSAGE+="Action : \`${ACTION}\`\n"
MESSAGE+="IP : \`${IP}\`\n"
MESSAGE+="User : \`${USER}\`\n"
MESSAGE+="Rule ID : \`${RULE_ID}\`\n"
MESSAGE+="Location : \`${LOCATION}\`\n"
MESSAGE+="Decoder : \`${DECODER}\`\n"
MESSAGE+="Log : \`${FULL_LOG}\`"

# 5) Envoyer la requête à Discord
curl -H "Content-Type: application/json" \
     -X POST \
     -d "{\"content\": \"${MESSAGE}\"}" \
     "${WEBHOOK_URL}"
EOF
chmod +x "$ALERT_SCRIPT"
echo "✅ Script discord_alert.sh créé et rendu exécutable."

# 🔹 Redémarrage de Wazuh Manager pour appliquer la configuration
echo "🔄 Redémarrage du service wazuh-manager..."
systemctl restart wazuh-manager

echo "🎉 === Configuration de Wazuh avec Discord fusionnée avec succès ! ==="
