#!/bin/bash
# Script : clamav-scan.sh
# Emplacement recommandé : /usr/local/bin
# Description : Analyse antivirus complète du système avec suppression des fichiers infectés et journalisation pour Wazuh

# === Paramètres ===
LOGFILE="/var/log/clamav/clamdscan.log"
FORWARD_LOG="/var/log/clamav/clamd-forwarding.log"

# === Date de scan ===
echo "===== Scan du $(date) =====" >> "$LOGFILE"

# === Lancer le scan avec exclusions ===
clamdscan -r --multiscan --fdpass / \
  --exclude-dir=/proc \
  --exclude-dir=/sys \
  --exclude-dir=/dev \
  --exclude-dir=/run \
  --exclude-dir=/mnt \
  --exclude-dir=/media \
  >> "$LOGFILE" 2>/dev/null

# === Rechercher et supprimer les fichiers infectés ===
grep "FOUND" "$LOGFILE" | cut -d: -f1 | while read -r file; do
  if [ -f "$file" ]; then
    echo "$(date) - Fichier infecté supprimé : $file" >> "$LOGFILE"
    rm -f "$file"
  fi
done

# === Forward log à Wazuh ===
grep "FOUND" "$LOGFILE" >> "$FORWARD_LOG"
