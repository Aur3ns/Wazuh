# ----------------------------------------------------------------------------------------
# Script PowerShell : DeploySysmonThenWazuh.ps1
# Description  : Installe Sysmon (avec configuration maximisant la collecte d'événements),
#                installe l'agent Wazuh et configure ce dernier pour transmettre les logs
#                (canaux Sysmon, Application, System et Security) vers le serveur spécifié.
# ----------------------------------------------------------------------------------------

[CmdletBinding()]
param (
    [string]$WazuhManagerIP = "10.10.0.24",
    [string]$WazuhVersion   = "4.11.1-1",
    [string]$SysmonUrl      = "https://download.sysinternals.com/files/Sysmon.zip"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'  # Arrêter sur toute erreur critique

Write-Host "=== Déploiement de Sysmon, Wazuh Agent et configuration des logs ===" -ForegroundColor Green

# ========================================================================================
# 1. Installation et configuration de Sysmon
# ========================================================================================

function Install-Sysmon {
    param (
        [string]$DownloadUrl
    )

    $SysmonZip         = Join-Path $env:TEMP "Sysmon.zip"
    $SysmonExtractPath = Join-Path $env:TEMP "Sysmon"
    $SysmonConfigPath  = Join-Path $env:TEMP "sysmonconfig.xml"
    $SysmonExe         = Join-Path $SysmonExtractPath "Sysmon64.exe"

    Write-Host "Installation de Sysmon..." -ForegroundColor Green

    # Vérifier si le service Sysmon existe déjà
    $serviceExists = Get-Service -Name "Sysmon" -ErrorAction SilentlyContinue
    if ($serviceExists) {
        Write-Host "Sysmon est déjà installé. Aucune action requise." -ForegroundColor Green
        return
    }

    Write-Host "Téléchargement de Sysmon..." -ForegroundColor Green
    try {
        Invoke-WebRequest -Uri $DownloadUrl -OutFile $SysmonZip -UseBasicParsing
        Write-Host "Téléchargement de Sysmon terminé." -ForegroundColor Green
    }
    catch {
        Write-Error "Échec du téléchargement de Sysmon : $_"
        return
    }

    Write-Host "Extraction de Sysmon..." -ForegroundColor Green
    try {
        if (Test-Path $SysmonExtractPath) {
            Remove-Item -Path $SysmonExtractPath -Recurse -Force
        }
        Expand-Archive -Path $SysmonZip -DestinationPath $SysmonExtractPath -Force
        Write-Host "Extraction terminée." -ForegroundColor Green
    }
    catch {
        Write-Error "Échec de l'extraction de Sysmon : $_"
        return
    }

    Write-Host "Création du fichier de configuration Sysmon..." -ForegroundColor Green
    @"
<Sysmon schemaversion="4.90">
  <EventFiltering>
    <ProcessCreate onmatch="include" />
    <NetworkConnect onmatch="include" />
    <FileCreate onmatch="include" />
    <FileCreateTime onmatch="include" />
    <FileDelete onmatch="include" />
    <ImageLoad onmatch="include" />
    <RegistryEvent onmatch="include" />
  </EventFiltering>
</Sysmon>
"@ | Out-File -FilePath $SysmonConfigPath -Encoding UTF8

    Write-Host "Installation de Sysmon (acceptation de la licence)..." -ForegroundColor Green
    try {
        Start-Process -FilePath $SysmonExe -ArgumentList "-accepteula -i `"$SysmonConfigPath`"" -Wait -NoNewWindow
        Write-Host "Sysmon installé avec succès." -ForegroundColor Green
    }
    catch {
        Write-Error "Échec de l'installation de Sysmon : $_"
        return
    }

    Write-Host "Réapplication de la configuration Sysmon..." -ForegroundColor Green
    try {
        Start-Process -FilePath $SysmonExe -ArgumentList "-c `"$SysmonConfigPath`"" -Wait -NoNewWindow
        Write-Host "Configuration Sysmon réappliquée." -ForegroundColor Green
    }
    catch {
        Write-Warning "Impossible de réappliquer la configuration Sysmon : $_"
    }

    Write-Host "Ajout de Sysmon au PATH..." -ForegroundColor Green
    try {
        $currentPath = [System.Environment]::GetEnvironmentVariable("PATH", [System.EnvironmentVariableTarget]::Machine)
        if ($currentPath -notlike "*$SysmonExtractPath*") {
            [System.Environment]::SetEnvironmentVariable("PATH", "$currentPath;$SysmonExtractPath", [System.EnvironmentVariableTarget]::Machine)
            Write-Host "Sysmon ajouté au PATH du système." -ForegroundColor Green
        }
        else {
            Write-Host "Sysmon est déjà dans le PATH du système." -ForegroundColor Green
        }
    }
    catch {
        Write-Warning "Échec de l'ajout de Sysmon au PATH : $_"
    }

    Write-Host "Nettoyage des fichiers temporaires de Sysmon..." -ForegroundColor Green
    try {
        Remove-Item -Path $SysmonZip -Force
        Remove-Item -Path $SysmonConfigPath -Force
        Write-Host "Nettoyage terminé." -ForegroundColor Green
    }
    catch {
        Write-Warning "Impossible de supprimer certains fichiers temporaires : $_"
    }
}

# ========================================================================================
# 2. Installation de l'Agent Wazuh
# ========================================================================================

function Search-OssecConf {
    # Recherche récursive de ossec.conf dans les dossiers Program Files
    $searchPaths = @("C:\Program Files", "C:\Program Files (x86)")
    foreach ($base in $searchPaths) {
        try {
            $result = Get-ChildItem -Path $base -Filter "ossec.conf" -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1
            if ($result) {
                return $result.DirectoryName
            }
        }
        catch {
            continue
        }
    }
    return $null
}

function Install-WazuhAgent {
    param (
        [string]$ManagerIP,
        [string]$Version
    )

    $WazuhInstallerPath = Join-Path $env:TEMP "wazuh-agent-$Version.msi"
    $WazuhInstallerUrl  = "https://packages.wazuh.com/4.x/windows/wazuh-agent-$Version.msi"

    Write-Host "Installation de l'agent Wazuh..." -ForegroundColor Green

    # Recherche initiale de ossec.conf
    $existingPath = Search-OssecConf
    if ($existingPath) {
        Write-Host "Wazuh Agent déjà installé dans '$existingPath'." -ForegroundColor Green
        return $existingPath
    }

    Write-Host "Téléchargement du MSI Wazuh Agent version $Version..." -ForegroundColor Green
    try {
        Invoke-WebRequest -Uri $WazuhInstallerUrl -OutFile $WazuhInstallerPath -UseBasicParsing
        Write-Host "Téléchargement terminé : $WazuhInstallerPath" -ForegroundColor Green
    }
    catch {
        Write-Error "Échec du téléchargement du MSI Wazuh : $_"
        return $null
    }

    Write-Host "Installation de Wazuh Agent en mode silencieux..." -ForegroundColor Green
    $msiArguments = "/i `"$WazuhInstallerPath`" /qn WAZUH_MANAGER=`"$ManagerIP`""
    try {
        Start-Process -FilePath "msiexec.exe" -ArgumentList $msiArguments -Wait -NoNewWindow
        Write-Host "Wazuh Agent installé avec succès." -ForegroundColor Green
    }
    catch {
        Write-Error "Échec de l'installation de Wazuh Agent : $_"
        return $null
    }

    $installedPath = Search-OssecConf
    if ($installedPath) {
        return $installedPath
    }
    else {
        Write-Warning "Wazuh Agent installé, mais impossible de déterminer le dossier d'installation."
        return $null
    }
}

# ========================================================================================
# 3. Configuration de l'agent Wazuh pour collecter les logs (Sysmon, Application, System et Security)
# ========================================================================================

function Configure-WazuhAgent {
    param (
        [string]$InstallPath
    )

    if (-not $InstallPath) {
        Write-Warning "Chemin d'installation de Wazuh introuvable, impossible de configurer ossec.conf."
        return
    }

    $ossecConfPath = Join-Path $InstallPath "ossec.conf"
    if (-Not (Test-Path $ossecConfPath)) {
        Write-Warning "Le fichier ossec.conf n'existe pas dans '$InstallPath'. Vérifiez l'installation."
        return
    }

    Write-Host "Configuration de l'agent Wazuh pour collecter les logs..." -ForegroundColor Green
    try {
        [xml]$ossecConfig = Get-Content $ossecConfPath
    }
    catch {
        Write-Error "Impossible de lire le fichier ossec.conf : $_"
        return
    }

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
            Write-Host "Ajout du canal '$channelName' dans ossec.conf..." -ForegroundColor Green
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
            Write-Host "Le canal '$channelName' est déjà présent dans ossec.conf." -ForegroundColor Green
        }
    }

    # Ajout des canaux requis
    Add-EventChannel -xmlConfig $ossecConfig -channelName "Microsoft-Windows-Sysmon/Operational"
    Add-EventChannel -xmlConfig $ossecConfig -channelName "Application"
    Add-EventChannel -xmlConfig $ossecConfig -channelName "System"
    Add-EventChannel -xmlConfig $ossecConfig -channelName "Security"

    try {
        $ossecConfig.Save($ossecConfPath)
        Write-Host "ossec.conf mis à jour avec succès pour collecter Sysmon, Application, System et Security." -ForegroundColor Green
    }
    catch {
        Write-Error "Impossible de sauvegarder ossec.conf : $_"
    }
}

# ========================================================================================
# 4. Exécution des opérations dans l'ordre : Sysmon, Wazuh Agent, puis configuration
# ========================================================================================

try {
    Install-Sysmon -DownloadUrl $SysmonUrl
    $wazuhPath = Install-WazuhAgent -ManagerIP $WazuhManagerIP -Version $WazuhVersion
    Configure-WazuhAgent -InstallPath $wazuhPath
    Write-Host "=== Déploiement complet terminé avec succès ! ===" -ForegroundColor Green
}
catch {
    Write-Error "Une erreur imprévue est survenue : $_"
}

# ----------------------------------------------------------------------------------------
# Fin du script
# ----------------------------------------------------------------------------------------
