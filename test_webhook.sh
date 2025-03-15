#!/bin/bash

# Remplacez l’URL ci-dessous par votre propre URL de webhook
WEBHOOK_URL="https://discord.com/api/webhooks/1350498539435851892/AUPDvMkhBGv34V-x6RSqDQAg4pVC5nduhQlnkqOdGmjXGa50fwE-V8ALsYNh2n_P6ejK"

# Le message que vous voulez envoyer
MESSAGE="Hello depuis mon script Bash !"

# Envoi du message vers Discord
curl -H "Content-Type: application/json" \
     -X POST \
     -d "{\"content\": \"${MESSAGE}\"}" \
     "${WEBHOOK_URL}"
