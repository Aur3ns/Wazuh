#!/bin/bash
# Script : generate_client_keys.sh
# Description : Génère des clés d’enrôlement pour 3 agents et les inscrit dans /var/ossec/etc/client.keys
# Agents :
#   - SRV-NS  : Contrôleur de domaine
#   - NS-01   : Poste admin Win10
#   - CNS-01  : Poste client Win10
#
# ATTENTION : Ce script écrase le contenu actuel de /var/ossec/etc/client.keys.
# Si vous avez déjà des clés, elles seront sauvegardées dans client.keys.bak.

set -e

CLIENT_KEYS_FILE="/var/ossec/etc/client.keys"

# Vérifier si le script est lancé avec les droits suffisants
if [ "$(id -u)" -ne 0 ]; then
    echo "Ce script doit être exécuté en tant que root."
    exit 1
fi

# Sauvegarde du fichier client.keys existant (s'il n'est pas vide)
if [ -s "$CLIENT_KEYS_FILE" ]; then
    cp "$CLIENT_KEYS_FILE" "${CLIENT_KEYS_FILE}.bak"
    echo "Sauvegarde du fichier existant dans ${CLIENT_KEYS_FILE}.bak"
fi

# Liste des agents
agents=("SRV-NS" "NS-01" "CNS-01")

# On vide le fichier client.keys
> "$CLIENT_KEYS_FILE"

# Génération et écriture des clés
id=1
for agent in "${agents[@]}"; do
    # Formatage de l'ID sur 3 chiffres (ex: 001, 002, 003)
    id_formatted=$(printf "%03d" "$id")
    # Génération d'une clé aléatoire (32 caractères hexadécimaux)
    key=$(openssl rand -hex 16)
    # Format attendu : ID:KEY:NAME
    echo "${id_formatted}:${key}:${agent}" >> "$CLIENT_KEYS_FILE"
    echo "Clé générée pour $agent : ${id_formatted}:${key}"
    ((id++))
done

# Définition des permissions (propriétaire root et groupe ossec)
chown root:ossec "$CLIENT_KEYS_FILE"
chmod 640 "$CLIENT_KEYS_FILE"

echo "Génération des clés terminée. Le fichier client.keys se trouve ici : $CLIENT_KEYS_FILE"
