# =============================================
# Déploiement de Wazuh Agent, installation de Sysmon,
# et configuration de l'agent pour envoyer les logs
# de Sysmon et de l'Observateur d'événements vers le serveur Wazuh.
# =============================================

# ---------------------------
# Partie Wazuh Agent
# ---------------------------
Write-Host "===== Déploiement de Wazuh Agent =====" -ForegroundColor Cyan

# Paramètres pour Wazuh Agent
$WazuhManagerIP     = "10.10.0.24"
$WazuhVersion       = "4.11.1-1"
# URL d'exemple pour Wazuh Agent version 4.11.1-1, vérifiez sur le site officiel si nécessaire
$WazuhInstallerUrl  = "https://packages.wazuh.com/4.x/windows/wazuh-agent-$WazuhVersion.msi"
$WazuhInstallerPath = "$env:TEMP\wazuh-agent-$WazuhVersion.msi"
$WazuhInstallFolder = "C:\Program Files (x86)\Wazuh Agent"

# Vérifier si l'agent Wazuh est déjà installé
if (Test-Path $WazuhInstallFolder) {
    Write-Host "Wazuh Agent est déjà installé." -ForegroundColor Yellow
} else {
    Write-Host "Téléchargement du MSI de Wazuh Agent version $WazuhVersion..."
    try {
        Invoke-WebRequest -Uri $WazuhInstallerUrl -OutFile $WazuhInstallerPath -UseBasicParsing
        Write-Host "Téléchargement terminé : $WazuhInstallerPath"
    }
    catch {
        Write-Error "Échec du téléchargement du MSI de Wazuh Agent: $_"
        exit 1
    }

    Write-Host "Installation de Wazuh Agent..."
    # Installation silencieuse avec configuration du serveur Wazuh
    $msiArguments = "/i `"$WazuhInstallerPath`" /qn WAZUH_MANAGER=`"$WazuhManagerIP`""
    try {
        Start-Process -FilePath "msiexec.exe" -ArgumentList $msiArguments -Wait -NoNewWindow
        Write-Host "Installation de Wazuh Agent terminée avec succès." -ForegroundColor Green
    }
    catch {
        Write-Error "Échec de l'installation de Wazuh Agent: $_"
        exit 1
    }
}

# ---------------------------
# Partie Sysmon
# ---------------------------
Write-Host "===== Installation et configuration de Sysmon =====" -ForegroundColor Cyan

# Variables pour Sysmon
$sysmonUrl = "https://download.sysinternals.com/files/Sysmon.zip"
$sysmonZip = "$env:TEMP\Sysmon.zip"
$sysmonExtractPath = "$env:TEMP\Sysmon"
$sysmonConfigPath = "$env:TEMP\sysmonconfig.xml"

# Fonction pour ajouter Sysmon au PATH système
function Add-SysmonToPath {
    param (
        [string]$PathToSysmon
    )

    Write-Host "Ajout de Sysmon au PATH du système..."
    $currentPath = [System.Environment]::GetEnvironmentVariable("PATH", [System.EnvironmentVariableTarget]::Machine)
    if ($currentPath -notlike "*$PathToSysmon*") {
        [System.Environment]::SetEnvironmentVariable("PATH", "$currentPath;$PathToSysmon", [System.EnvironmentVariableTarget]::Machine)
        Write-Host "Sysmon a été ajouté au PATH du système. Redémarrez PowerShell pour appliquer les changements." -ForegroundColor Green
    } else {
        Write-Host "Sysmon est déjà présent dans le PATH du système." -ForegroundColor Yellow
    }
}

# Téléchargement de Sysmon
Write-Host "Téléchargement de Sysmon..."
try {
    Invoke-WebRequest -Uri $sysmonUrl -OutFile $sysmonZip -UseBasicParsing
    Write-Host "Téléchargement de Sysmon terminé."
}
catch {
    Write-Error "Échec du téléchargement de Sysmon: $_"
    exit 1
}

# Extraction de Sysmon
Write-Host "Extraction de Sysmon..."
try {
    Expand-Archive -Path $sysmonZip -DestinationPath $sysmonExtractPath -Force
    Write-Host "Extraction de Sysmon terminée."
}
catch {
    Write-Error "Échec de l'extraction de Sysmon: $_"
    exit 1
}

# Création du fichier de configuration Sysmon
Write-Host "Création du fichier de configuration Sysmon..."
@"
<Sysmon schemaversion="4.82">
  <EventFiltering>
    <!-- Capture tous les événements -->
    <NetworkConnect onmatch="include" />
    <ProcessCreate onmatch="include" />
    <FileCreate onmatch="include" />
    <FileCreateTime onmatch="include" />
    <FileDelete onmatch="include" />
    <FileWrite onmatch="include" />
    <ImageLoad onmatch="include" />
    <RegistryEvent onmatch="include" />
  </EventFiltering>
</Sysmon>
"@ | Out-File -FilePath $sysmonConfigPath -Encoding UTF8

# Installation de Sysmon
Write-Host "Installation de Sysmon..."
$sysmonExe = Join-Path $sysmonExtractPath "Sysmon64.exe"
try {
    Start-Process -FilePath $sysmonExe -ArgumentList "-accepteula -i $sysmonConfigPath" -Wait -NoNewWindow
    Write-Host "Sysmon installé avec succès."
}
catch {
    Write-Error "Échec de l'installation de Sysmon: $_"
    exit 1
}

# Réapplication du fichier de configuration Sysmon
Write-Host "Réapplication du fichier de configuration Sysmon..."
try {
    Start-Process -FilePath $sysmonExe -ArgumentList "-c $sysmonConfigPath" -Wait -NoNewWindow
    Write-Host "Réapplication du fichier de configuration terminée."
}
catch {
    Write-Error "Échec de la réapplication du fichier de configuration Sysmon: $_"
    exit 1
}

# Ajout de Sysmon au PATH
Add-SysmonToPath -PathToSysmon $sysmonExtractPath

# Nettoyage des fichiers temporaires pour Sysmon
Write-Host "Nettoyage des fichiers temporaires Sysmon..."
try {
    Remove-Item -Path $sysmonZip, $sysmonConfigPath -Recurse -Force
    Write-Host "Nettoyage terminé."
}
catch {
    Write-Warning "Échec du nettoyage complet des fichiers temporaires : $_"
}

# ---------------------------
# Configuration de l'agent pour transmettre les logs
# ---------------------------
Write-Host "===== Configuration de l'agent Wazuh pour transmettre les logs =====" -ForegroundColor Cyan

# Chemin du fichier de configuration de l'agent Wazuh sur Windows
$ossecConfPath = "C:\Program Files (x86)\Wazuh Agent\ossec.conf"

if (-Not (Test-Path $ossecConfPath)) {
    Write-Warning "Le fichier de configuration ossec.conf n'a pas été trouvé. Assurez-vous que l'agent Wazuh est correctement installé."
} else {
    try {
        [xml]$ossecConfig = Get-Content $ossecConfPath

        # Vérifier et ajouter la configuration pour Sysmon (Event Channel: Microsoft-Windows-Sysmon/Operational)
        $localfiles = $ossecConfig.ossec_config.localfile
        $sysmonConfigExists = $false

        if ($localfiles) {
            foreach ($lf in $localfiles) {
                if ($lf.location -and $lf.location -match "Microsoft-Windows-Sysmon/Operational") {
                    $sysmonConfigExists = $true
                    break
                }
            }
        }

        if (-not $sysmonConfigExists) {
            Write-Host "Ajout de la configuration pour le canal Sysmon dans ossec.conf..."
            $newLocalFile = $ossecConfig.CreateElement("localfile")

            $logFormat = $ossecConfig.CreateElement("log_format")
            $logFormat.InnerText = "eventchannel"
            $newLocalFile.AppendChild($logFormat) | Out-Null

            $location = $ossecConfig.CreateElement("location")
            $location.InnerText = "Microsoft-Windows-Sysmon/Operational"
            $newLocalFile.AppendChild($location) | Out-Null

            $ossecConfig.ossec_config.AppendChild($newLocalFile) | Out-Null
        } else {
            Write-Host "La configuration pour Sysmon existe déjà dans ossec.conf."
        }

        # (Optionnel) Vous pouvez ajouter d'autres canaux d'événements (Application, System, Security, etc.)
        # Exemple pour le canal Application :
        $appConfigExists = $false
        foreach ($lf in $localfiles) {
            if ($lf.location -and $lf.location -match "Application") {
                $appConfigExists = $true
                break
            }
        }
        if (-not $appConfigExists) {
            Write-Host "Ajout de la configuration pour le canal Application..."
            $newLocalFileApp = $ossecConfig.CreateElement("localfile")

            $logFormatApp = $ossecConfig.CreateElement("log_format")
            $logFormatApp.InnerText = "eventchannel"
            $newLocalFileApp.AppendChild($logFormatApp) | Out-Null

            $locationApp = $ossecConfig.CreateElement("location")
            $locationApp.InnerText = "Application"
            $newLocalFileApp.AppendChild($locationApp) | Out-Null

            $ossecConfig.ossec_config.AppendChild($newLocalFileApp) | Out-Null
        }

        # Sauvegarder les modifications
        $ossecConfig.Save($ossecConfPath)
        Write-Host "Le fichier ossec.conf a été mis à jour avec succès."
    }
    catch {
        Write-Error "Échec de la mise à jour de ossec.conf : $_"
    }
}

Write-Host "Déploiement complet de Wazuh Agent, Sysmon et configuration des logs terminé avec succès !" -ForegroundColor Green
