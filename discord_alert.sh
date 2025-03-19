#!/bin/bash
#
# Script : discord_alert.sh
# Objectif : Envoyer une alerte Wazuh vers Discord via webhook
#

# 1) Définir l’URL de ton webhook Discord
#    Remplace l'URL ci-dessous par la tienne.
WEBHOOK_URL="https://discord.com/api/webhooks/1350498539435851892/AUPDvMkhBGv34V-x6RSqDQAg4pVC5nduhQlnkqOdGmjXGa50fwE-V8ALsYNh2n_P6ejK"

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
