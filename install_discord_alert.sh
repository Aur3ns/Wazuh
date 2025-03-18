#!/bin/bash
# ----------------------------------------------------------------------------------------
# Script : configure_wazuh_discord.sh
# Description : Configure Wazuh pour envoyer des alertes vers Discord via active response,
#               en fusionnant la configuration existante avec les nouveaux paramètres.
# ----------------------------------------------------------------------------------------

set -e

# Variables
WEBHOOK_URL="https://discord.com/api/webhooks/1350498539435851892/AUPDvMkhBGv34V-x6RSqDQAg4pVC5nduhQlnkqOdGmjXGa50fwE-V8ALsYNh2n_P6ejK"
OSSEC_CONF="/var/ossec/etc/ossec.conf"
COMMANDS_CONF="/var/ossec/etc/active-response/commands.conf"
ALERT_SCRIPT_DIR="/var/ossec/active-response"
ALERT_SCRIPT="${ALERT_SCRIPT_DIR}/discord_alert.sh"

echo "=== Fusion de la configuration existante de Wazuh avec l'active response Discord ==="

# Sauvegarde de l'ancien ossec.conf
if [ -f "$OSSEC_CONF" ]; then
    cp "$OSSEC_CONF" "${OSSEC_CONF}.bak_$(date '+%Y%m%d_%H%M%S')"
    echo "Ancien ossec.conf sauvegardé sous ${OSSEC_CONF}.bak_$(date '+%Y%m%d_%H%M%S')."
else
    echo "ERREUR : Fichier ossec.conf introuvable !"
    exit 1
fi

# Vérifier si le bloc <active-response> existe déjà
if ! grep -q "<active-response>" "$OSSEC_CONF"; then
    # Ajouter le bloc <active-response> à la fin juste avant </ossec_config>
    sed -i '/<\/ossec_config>/i \ \n  <active-response>\n  </active-response>\n' "$OSSEC_CONF"
    echo "Bloc <active-response> ajouté."
fi

# Vérifier si la commande discord_alert est déjà présente
if ! grep -q "<command>discord_alert</command>" "$OSSEC_CONF"; then
    # Ajouter la commande discord_alert dans <active-response>
    sed -i '/<active-response>/a \    <command>discord_alert</command>\n    <location>local</location>\n    <timeout>600</timeout>' "$OSSEC_CONF"
    echo "Commande discord_alert ajoutée dans active-response."
else
    echo "La commande discord_alert est déjà présente dans ossec.conf."
fi

# Vérification et correction du fichier XML
if ! xmllint --noout "$OSSEC_CONF" 2>/dev/null; then
    echo "ERREUR : Le fichier ossec.conf est invalide après modification. Annulation des changements..."
    mv "${OSSEC_CONF}.bak_$(date '+%Y%m%d_%H%M%S')" "$OSSEC_CONF"
    exit 1
else
    echo "ossec.conf mis à jour avec succès."
fi

# Ajustement des permissions
chown -R wazuh:wazuh /var/ossec/etc
chmod 770 /var/ossec/etc
chmod 660 "$OSSEC_CONF"

# Mise à jour de la commande active response dans commands.conf
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
    echo "Commande discord_alert ajoutée dans $COMMANDS_CONF."
else
    echo "La commande discord_alert est déjà présente dans $COMMANDS_CONF."
fi

# Création du script discord_alert.sh
mkdir -p "$ALERT_SCRIPT_DIR"
cat << EOF > "$ALERT_SCRIPT"
#!/bin/bash
# Script pour envoyer une alerte Wazuh vers Discord via webhook
WEBHOOK_URL="$WEBHOOK_URL"
ALERT_MESSAGE="\$1"
curl -H "Content-Type: application/json" -X POST -d "{\"content\": \"Alerte Wazuh : \$ALERT_MESSAGE\"}" "\$WEBHOOK_URL"
EOF
chmod +x "$ALERT_SCRIPT"

# Redémarrage de Wazuh Manager pour appliquer la configuration
echo "Redémarrage du service wazuh-manager..."
systemctl restart wazuh-manager

echo "=== Configuration de Wazuh avec Discord fusionnée avec succès ! ==="
