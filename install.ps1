$ErrorActionPreference = 'Stop'

# === Préparation ===
$global:LogMain = 'C:\Temp\install_debug.log'
$DownloadDir = 'C:\Temp'
if (!(Test-Path -Path $DownloadDir)) { New-Item -ItemType Directory -Force -Path $DownloadDir | Out-Null }

# Initialise proprement le log
if (!(Test-Path $LogMain)) { New-Item -ItemType File -Path $LogMain -Force | Out-Null }
Set-Content -Path $LogMain -Value "--- Démarrage installation ---"
Write-Output "=== Script CustomScriptExtension démarré ==="

# === Checksums attendus (mettre "" ou "0" pour désactiver) ===
$Checksums = @{
    "OnPremiseGatewayInstaller.exe" = "0"
    "IntegrationRuntime.msi"        = "0"
    "SimbaSparkODBC.zip"            = "86D295D1A1C1FACA9C05CE6B0D62B9DA5078F12635A494543B7182E0EDF7E4CD"
    "SimbaSparkODBC.msi"            = "76E76E472480B811B8C38A641ED4D3B323D87647D29A2E59361AA45BD4FED923"
}

# === Fonctions ===
function Verify-Checksum($FilePath, $ExpectedHash, $ComponentName) {
    if (-not (Test-Path $FilePath)) { throw "$ComponentName introuvable : $FilePath" }

    if ([string]::IsNullOrWhiteSpace($ExpectedHash) -or $ExpectedHash -eq "0") {
        Add-Content $LogMain "Checksum désactivé pour $ComponentName"
        return
    }

    $ActualHash = (Get-FileHash $FilePath -Algorithm SHA256).Hash.ToLower()
    if ($ActualHash -ne $ExpectedHash.ToLower()) {
        throw "Checksum invalide pour $ComponentName ($ActualHash <> $ExpectedHash)"
    }
    Add-Content $LogMain "$ComponentName checksum OK"
}

function Install-MSI($MsiPath, $LogFile, $ComponentName) {
    Verify-Checksum $MsiPath $Checksums[(Split-Path $MsiPath -Leaf)] $ComponentName
    $Arguments = "/i `"$MsiPath`" /quiet /norestart /l*v $LogFile"
    Add-Content $LogMain "Installation $ComponentName avec arguments: $Arguments"
    Write-Output "Installation $ComponentName..."
    $Process = Start-Process msiexec.exe -ArgumentList $Arguments -Wait -PassThru
    switch ($Process.ExitCode) {
        0     { Add-Content $LogMain "$ComponentName installé avec succès" }
        3010  { Add-Content $LogMain "$ComponentName installé (reboot requis)" ; $global:RebootNeeded = $true }
        default { throw "$ComponentName installation failed avec code $($Process.ExitCode)" }
    }
}

function Install-ODBC($ZipPath, $ComponentName) {
    Verify-Checksum $ZipPath $Checksums["SimbaSparkODBC.zip"] $ComponentName
    Expand-Archive -Path $ZipPath -DestinationPath "$DownloadDir\SparkODBC" -Force
    $MsiFile = Get-ChildItem "$DownloadDir\SparkODBC" -Recurse -Filter *.msi | Select-Object -First 1
    if (-not $MsiFile) { throw "Aucun MSI trouvé dans ODBC ZIP" }
    Copy-Item $MsiFile.FullName "$DownloadDir\SimbaSparkODBC.msi" -Force
    Verify-Checksum "$DownloadDir\SimbaSparkODBC.msi" $Checksums["SimbaSparkODBC.msi"] $ComponentName
    Install-MSI "$DownloadDir\SimbaSparkODBC.msi" "$DownloadDir\spark_odbc_install.log" $ComponentName

    Add-Content $LogMain "Copie DLL Simba..."
    $SourceDir = "C:\Program Files\Simba Spark ODBC Driver\lib"
    $TargetDir = "C:\Program Files\On-premises data gateway\m\ODBC Drivers\New\Spark"
    if (!(Test-Path $TargetDir)) { New-Item -ItemType Directory -Force -Path $TargetDir | Out-Null }
    Copy-Item -Path (Join-Path $SourceDir '*') -Destination $TargetDir -Recurse -Force
    Add-Content $LogMain "Spark ODBC OK"
}

# === Téléchargements parallèles ===
$Downloads = @(
    @{ ComponentName = "Gateway"; Url = "https://go.microsoft.com/fwlink/?LinkId=2116849&clcid=0x409"; Path = "$DownloadDir\OnPremiseGatewayInstaller.exe" },
    @{ ComponentName = "IntegrationRuntime"; Url = "https://download.microsoft.com/download/e/4/7/e4771905-1079-445b-8bf9-8a1a075d8a10/IntegrationRuntime_5.57.9350.2.msi"; Path = "$DownloadDir\IntegrationRuntime.msi" },
    @{ ComponentName = "SparkODBC"; Url = "https://databricks-bi-artifacts.s3.us-east-2.amazonaws.com/simbaspark-drivers/odbc/2.9.2/SimbaSparkODBC-2.9.2.1008-Windows-64bit.zip"; Path = "$DownloadDir\SimbaSparkODBC.zip" }
)

$Jobs = foreach ($Download in $Downloads) {
    Start-Job -Name $Download.ComponentName -ScriptBlock {
        param($DownloadUrl, $DownloadPath, $ComponentName, $MainLog)
        try {
            Invoke-WebRequest -Uri $DownloadUrl -OutFile $DownloadPath -UseBasicParsing
            Add-Content $MainLog "$ComponentName téléchargé -> $DownloadPath"
        } catch {
            Add-Content $MainLog "[ERREUR] Téléchargement $ComponentName : $($_.Exception.Message)"
            throw
        }
    } -ArgumentList $Download.Url, $Download.Path, $Download.ComponentName, $LogMain
}

$Jobs | Wait-Job | ForEach-Object {
    if ($_.State -ne 'Completed') {
        Add-Content $LogMain "[ERREUR] Téléchargement $($_.Name) échoué"
        exit 1
    }
    Receive-Job $_ | Out-Null
}
$Jobs | Remove-Job
Add-Content $LogMain "Téléchargements terminés"

# === Installations ===
Install-MSI "$DownloadDir\OnPremiseGatewayInstaller.exe" "$DownloadDir\gateway_install.log" "Power BI Gateway"
Install-MSI "$DownloadDir\IntegrationRuntime.msi" "$DownloadDir\ir_install.log" "Integration Runtime"
Install-ODBC "$DownloadDir\SimbaSparkODBC.zip" "Spark ODBC"

# === Nettoyage ===
Remove-Item "$DownloadDir\OnPremiseGatewayInstaller.exe","$DownloadDir\IntegrationRuntime.msi","$DownloadDir\SimbaSparkODBC.zip" -Force -ErrorAction SilentlyContinue
Add-Content $LogMain "--- Installation terminée avec succès ---"
Write-Output "=== Script terminé avec succès ==="

if ($global:RebootNeeded) {
    Add-Content $LogMain "Redémarrage requis - planifiez un reboot manuel ou automatique"
    # Pour automatiser complètement : décommente la ligne ci-dessous
    # Restart-Computer -Force
}
exit 0