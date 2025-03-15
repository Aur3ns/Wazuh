#!/bin/bash
# ----------------------------------------------------------------------------------------
# Script : uninstall_wazuh.sh
# Description : Désinstalle complètement Wazuh Manager et supprime toutes les traces
#               de l'installation (configuration, logs, dépôt, etc.).
#
# ATTENTION : Ce script supprimera toutes vos données Wazuh !
# ----------------------------------------------------------------------------------------

set -e

echo "=== Désinstallation complète de Wazuh ==="

# 1. Arrêter le service Wazuh Manager
echo "Arrêt du service wazuh-manager..."
systemctl stop wazuh-manager || echo "Service wazuh-manager non actif ou introuvable."

# 2. Désinstaller Wazuh Manager
if dpkg -l | grep -q wazuh-manager; then
    echo "Désinstallation du paquet wazuh-manager..."
    apt-get purge -y wazuh-manager
    apt-get autoremove -y
else
    echo "Aucun paquet wazuh-manager trouvé."
fi

# 3. Supprimer le répertoire /var/ossec (configuration, logs, etc.)
if [ -d /var/ossec ]; then
    echo "Suppression du répertoire /var/ossec..."
    rm -rf /var/ossec
else
    echo "Le répertoire /var/ossec n'existe pas."
fi

# 4. Supprimer le dépôt Wazuh ajouté dans apt
if [ -f /etc/apt/sources.list.d/wazuh.list ]; then
    echo "Suppression du fichier de dépôt Wazuh..."
    rm -f /etc/apt/sources.list.d/wazuh.list
else
    echo "Aucun fichier de dépôt Wazuh trouvé."
fi

# 5. (Optionnel) Supprimer la clé GPG de Wazuh
# Pour lister les clés installées : apt-key list
# Vous pouvez supprimer la clé de Wazuh si nécessaire, par exemple :
# apt-key del <keyid>

echo "=== Désinstallation complète de Wazuh terminée ==="
