#!/bin/bash

# Définition des variables
IP_ADDRESS="10.10.0.24"
INDEXER_NODE="node-1"
WAZUH_SERVER="wazuh-1"
DASHBOARD_NODE="dashboard"
DASHBOARD_PORT="443"  # Vous pouvez le changer (ex: 8443, 8080, etc.)

echo "🚀 Début de l'installation complète de Wazuh sur $IP_ADDRESS..."

# Étape 1: Téléchargement des fichiers nécessaires
echo "📥 Téléchargement des fichiers d'installation..."
curl -sO https://packages.wazuh.com/4.11/wazuh-install.sh
curl -sO https://packages.wazuh.com/4.11/config.yml

# Étape 2: Configuration automatique de config.yml
echo "🛠️ Configuration du fichier config.yml..."
cat > config.yml <<EOL
nodes:
  indexer:
    - name: $INDEXER_NODE
      ip: "$IP_ADDRESS"

  server:
    - name: $WAZUH_SERVER
      ip: "$IP_ADDRESS"

  dashboard:
    - name: $DASHBOARD_NODE
      ip: "$IP_ADDRESS"
EOL
echo "✅ Fichier config.yml généré avec succès."

# Étape 3: Génération des fichiers de configuration
echo "🔑 Génération des fichiers de configuration..."
bash wazuh-install.sh --generate-config-files

# Vérification de la génération des fichiers
if [ ! -f wazuh-install-files.tar ]; then
    echo "❌ Erreur : Le fichier wazuh-install-files.tar n'a pas été créé."
    exit 1
fi
echo "✅ Fichiers de configuration générés avec succès."

# Étape 4: Installation du Wazuh Indexer
echo "📦 Installation du Wazuh Indexer ($INDEXER_NODE)..."
bash wazuh-install.sh --wazuh-indexer $INDEXER_NODE
echo "✅ Wazuh Indexer installé avec succès."

# Étape 5: Initialisation du cluster
echo "🔄 Initialisation du cluster Wazuh Indexer..."
bash wazuh-install.sh --start-cluster
echo "✅ Cluster initialisé avec succès."

# Étape 6: Installation du Wazuh Server
echo "📦 Installation du Wazuh Server ($WAZUH_SERVER)..."
bash wazuh-install.sh --wazuh-server $WAZUH_SERVER
echo "✅ Wazuh Server installé avec succès."

# Étape 7: Installation du Wazuh Dashboard
echo "📦 Installation du Wazuh Dashboard ($DASHBOARD_NODE) sur le port $DASHBOARD_PORT..."
bash wazuh-install.sh --wazuh-dashboard $DASHBOARD_NODE -p $DASHBOARD_PORT
echo "✅ Wazuh Dashboard installé avec succès."

# Étape 8: Extraction des identifiants d'accès
echo "🔐 Récupération des identifiants d'accès..."
ADMIN_PASSWORD=$(tar -O -xvf wazuh-install-files.tar wazuh-install-files/wazuh-passwords.txt | grep -P "'admin'" -A 1 | tail -n1 | awk -F"'" '{print $2}')

echo "✅ Installation complète de Wazuh terminée avec succès !"
echo "🌐 Accédez à l’interface web ici : https://$IP_ADDRESS:$DASHBOARD_PORT"
echo "👤 Identifiants :"
echo "   - Utilisateur : admin"
echo "   - Mot de passe : $ADMIN_PASSWORD"

# Étape 9: Vérification du cluster
echo "🔍 Vérification du cluster..."
curl -k -u admin:$ADMIN_PASSWORD https://$IP_ADDRESS:9200/_cat/nodes?v

echo "🎉 Wazuh est maintenant entièrement opérationnel sur $IP_ADDRESS !"
