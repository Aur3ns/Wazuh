# ----------------------------------------------------------------------------------------
# Script PowerShell : DeployWazuhAndSysmon.ps1
# Description  : Déploie l'agent Wazuh, installe Sysmon, configure un fichier Sysmon minimal,
#                et modifie la config Wazuh pour collecter les logs Sysmon et Application.
# ----------------------------------------------------------------------------------------

[CmdletBinding()]
param (
    [string]$WazuhManagerIP = "10.10.0.24",
    [string]$WazuhVersion   = "4.11.1-1",
    [string]$SysmonUrl      = "https://download.sysinternals.com/files/Sysmon.zip"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'  # Stop on any error

Write-Host "=== Début du déploiement Wazuh + Sysmon ===" -ForegroundColor Cyan

# ========================================================================================
# 1. Déploiement de l'Agent Wazuh
# ========================================================================================

function Install-WazuhAgent {
    param (
        [string]$ManagerIP,
        [string]$Version
    )

    $WazuhInstallerPath = Join-Path $env:TEMP "wazuh-agent-$Version.msi"
    $WazuhInstallFolder = "C:\Program Files (x86)\Wazuh Agent"
    $WazuhInstallerUrl  = "https://packages.wazuh.com/4.x/windows/wazuh-agent-$Version.msi"

    # Vérifier si Wazuh est déjà installé
    if (Test-Path $WazuhInstallFolder) {
        Write-Host "Wazuh Agent est déjà installé. Aucune action requise." -ForegroundColor Yellow
        return
    }

    Write-Host "Téléchargement du MSI Wazuh Agent version $Version..."
    try {
        Invoke-WebRequest -Uri $WazuhInstallerUrl -OutFile $WazuhInstallerPath -UseBasicParsing
        Write-Host "Téléchargement terminé : $WazuhInstallerPath"
    }
    catch {
        Write-Error "Échec du téléchargement du MSI Wazuh : $_"
        return
    }

    Write-Host "Installation de Wazuh Agent en mode silencieux..."
    $msiArguments = "/i `"$WazuhInstallerPath`" /qn WAZUH_MANAGER=`"$ManagerIP`""
    try {
        Start-Process -FilePath "msiexec.exe" -ArgumentList $msiArguments -Wait -NoNewWindow
        Write-Host "Wazuh Agent installé avec succès." -ForegroundColor Green
    }
    catch {
        Write-Error "Échec de l'installation de Wazuh Agent : $_"
    }
}

# ========================================================================================
# 2. Installation et configuration de Sysmon
# ========================================================================================

function Install-Sysmon {
    param (
        [string]$DownloadUrl
    )

    $SysmonZip         = Join-Path $env:TEMP "Sysmon.zip"
    $SysmonExtractPath = Join-Path $env:TEMP "Sysmon"
    $SysmonConfigPath  = Join-Path $env:TEMP "sysmonconfig.xml"
    $SysmonExe         = Join-Path $SysmonExtractPath "Sysmon64.exe"

    # Vérifier si Sysmon est déjà présent (via Sysmon64.exe ou le service)
    $serviceExists = Get-Service -Name "Sysmon" -ErrorAction SilentlyContinue
    if ($serviceExists) {
        Write-Host "Sysmon est déjà installé. Aucune action requise." -ForegroundColor Yellow
        return
    }

    Write-Host "Téléchargement de Sysmon..."
    try {
        Invoke-WebRequest -Uri $DownloadUrl -OutFile $SysmonZip -UseBasicParsing
        Write-Host "Téléchargement de Sysmon terminé."
    }
    catch {
        Write-Error "Échec du téléchargement de Sysmon : $_"
        return
    }

    Write-Host "Extraction de Sysmon..."
    try {
        if (Test-Path $SysmonExtractPath) {
            Remove-Item -Path $SysmonExtractPath -Recurse -Force
        }
        Expand-Archive -Path $SysmonZip -DestinationPath $SysmonExtractPath -Force
        Write-Host "Extraction terminée."
    }
    catch {
        Write-Error "Échec de l'extraction de Sysmon : $_"
        return
    }

    Write-Host "Création d'un fichier de configuration Sysmon minimal (schéma 4.50)..."
    @"
<Sysmon schemaversion="4.50">
  <EventFiltering>
    <ProcessCreate onmatch="include" />
  </EventFiltering>
</Sysmon>
"@ | Out-File -FilePath $SysmonConfigPath -Encoding UTF8

    Write-Host "Installation de Sysmon..."
    try {
        # Installation silencieuse + acceptation de la licence
        Start-Process -FilePath $SysmonExe -ArgumentList "-accepteula -i `"$SysmonConfigPath`"" -Wait -NoNewWindow
        Write-Host "Sysmon installé avec succès." -ForegroundColor Green
    }
    catch {
        Write-Error "Échec de l'installation de Sysmon : $_"
        return
    }

    Write-Host "Réapplication de la configuration Sysmon..."
    try {
        Start-Process -FilePath $SysmonExe -ArgumentList "-c `"$SysmonConfigPath`"" -Wait -NoNewWindow
        Write-Host "Configuration Sysmon réappliquée."
    }
    catch {
        Write-Warning "Impossible de réappliquer la configuration Sysmon : $_"
    }

    Write-Host "Ajout de Sysmon au PATH..."
    try {
        $currentPath = [System.Environment]::GetEnvironmentVariable("PATH", [System.EnvironmentVariableTarget]::Machine)
        if ($currentPath -notlike "*$SysmonExtractPath*") {
            [System.Environment]::SetEnvironmentVariable("PATH", "$currentPath;$SysmonExtractPath", [System.EnvironmentVariableTarget]::Machine)
            Write-Host "Sysmon ajouté au PATH du système. (Redémarrez la session PowerShell si nécessaire.)" -ForegroundColor Green
        }
        else {
            Write-Host "Sysmon est déjà dans le PATH du système." -ForegroundColor Yellow
        }
    }
    catch {
        Write-Warning "Échec de l'ajout de Sysmon au PATH : $_"
    }

    Write-Host "Nettoyage des fichiers temporaires..."
    try {
        Remove-Item -Path $SysmonZip -Force
        Remove-Item -Path $SysmonConfigPath -Force
        Write-Host "Nettoyage terminé."
    }
    catch {
        Write-Warning "Impossible de supprimer certains fichiers temporaires : $_"
    }
}

# ========================================================================================
# 3. Configuration de l'agent Wazuh pour collecter Sysmon + Journaux Windows
# ========================================================================================

function Configure-WazuhAgent {
    $ossecConfPath = "C:\Program Files (x86)\Wazuh Agent\ossec.conf"

    if (-Not (Test-Path $ossecConfPath)) {
        Write-Warning "Le fichier ossec.conf n'existe pas. Assurez-vous que Wazuh Agent est installé."
        return
    }

    try {
        [xml]$ossecConfig = Get-Content $ossecConfPath
    }
    catch {
        Write-Error "Impossible de lire le fichier ossec.conf : $_"
        return
    }

    # Récupérer la liste des <localfile> existants
    $localfiles = $ossecConfig.ossec_config.localfile
    if (-not $localfiles) {
        # S'il n'y a pas encore de section <localfile>, on la crée
        $localfiles = @()
    }

    # Fonction utilitaire pour ajouter un canal EventChannel s'il n'existe pas
    function Add-EventChannel {
        param(
            [xml]$xmlConfig,
            [string]$channelName
        )

        $exists = $false
        if ($xmlConfig.ossec_config.localfile) {
            foreach ($lf in $xmlConfig.ossec_config.localfile) {
                if ($lf.location -and $lf.location -eq $channelName) {
                    $exists = $true
                    break
                }
            }
        }

        if (-not $exists) {
            Write-Host "Ajout du canal '$channelName' dans la configuration..."
            $newLocalFile = $xmlConfig.CreateElement("localfile")

            $logFormat = $xmlConfig.CreateElement("log_format")
            $logFormat.InnerText = "eventchannel"
            $newLocalFile.AppendChild($logFormat) | Out-Null

            $location = $xmlConfig.CreateElement("location")
            $location.InnerText = $channelName
            $newLocalFile.AppendChild($location) | Out-Null

            $xmlConfig.ossec_config.AppendChild($newLocalFile) | Out-Null
        }
        else {
            Write-Host "Le canal '$channelName' est déjà présent dans ossec.conf." -ForegroundColor Yellow
        }
    }

    # Ajouter le canal Sysmon
    Add-EventChannel -xmlConfig $ossecConfig -channelName "Microsoft-Windows-Sysmon/Operational"
    # Ajouter le canal Application (en exemple)
    Add-EventChannel -xmlConfig $ossecConfig -channelName "Application"
    # Ajouter d'autres canaux si besoin (System, Security, etc.)
    # Add-EventChannel -xmlConfig $ossecConfig -channelName "System"
    # Add-EventChannel -xmlConfig $ossecConfig -channelName "Security"

    try {
        $ossecConfig.Save($ossecConfPath)
        Write-Host "ossec.conf mis à jour avec succès pour collecter Sysmon et Application." -ForegroundColor Green
    }
    catch {
        Write-Error "Impossible de sauvegarder ossec.conf : $_"
    }
}

# ========================================================================================
# 4. Lancement des opérations
# ========================================================================================

try {
    Install-WazuhAgent -ManagerIP $WazuhManagerIP -Version $WazuhVersion
    Install-Sysmon -DownloadUrl $SysmonUrl
    Configure-WazuhAgent
    Write-Host "=== Déploiement complet terminé avec succès ! ===" -ForegroundColor Green
}
catch {
    Write-Error "Une erreur imprévue est survenue : $_"
}

# ----------------------------------------------------------------------------------------
# Fin du script
# ----------------------------------------------------------------------------------------
