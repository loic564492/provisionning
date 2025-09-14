$ErrorActionPreference = 'Stop'
$log = 'C:\Temp\install_debug.log'

if (!(Test-Path -Path 'C:\Temp')) { New-Item -ItemType Directory -Path 'C:\Temp' | Out-Null }
Add-Content $log "--- Démarrage installation ---"
Write-Output "=== Script CustomScriptExtension démarré ==="

# === Téléchargements en parallèle ===
$jobs = @()
$downloads = @(
    @{ Name = "Gateway"; Url = "https://go.microsoft.com/fwlink/?LinkId=2116849&clcid=0x409"; Path = "C:\Temp\OnPremiseGatewayInstaller.exe" },
    @{ Name = "IR"; Url = "https://download.microsoft.com/download/e/4/7/e4771905-1079-445b-8bf9-8a1a075d8a10/IntegrationRuntime_5.57.9350.2.msi"; Path = "C:\Temp\IntegrationRuntime.msi" },
    @{ Name = "ODBC"; Url = "https://databricks-bi-artifacts.s3.us-east-2.amazonaws.com/simbaspark-drivers/odbc/2.9.2/SimbaSparkODBC-2.9.2.1008-Windows-64bit.zip"; Path = "C:\Temp\SimbaSparkODBC.zip" }
)

foreach ($d in $downloads) {
    $jobs += Start-Job -Name $d.Name -ScriptBlock {
        param($u, $p)
        Invoke-WebRequest -Uri $u -OutFile $p -UseBasicParsing
    } -ArgumentList $d.Url, $d.Path
}

# Attente et récupération
try {
    $jobs | Wait-Job | Receive-Job -ErrorAction Stop
    Write-Output "Téléchargements terminés"
    Add-Content $log "Téléchargements terminés"
} catch {
    Add-Content $log "[ERREUR] Téléchargement: $($_.Exception.Message)"
    exit 1
} finally {
    $jobs | Remove-Job
}

# === Fonction installation MSI ===
function Install-MSI($path, $logfile, $component) {
    if (!(Test-Path $path)) {
        Add-Content $log "[ERREUR] $component introuvable à $path"
        exit 1
    }

    $arguments = "/i `"$path`" /quiet /norestart /l*v $logfile"
    Add-Content $log "Installation $component avec arguments: $arguments"
    Write-Output "Installation $component..."

    $process = Start-Process msiexec.exe -ArgumentList $arguments -Wait -PassThru
    if ($process.ExitCode -ne 0) {
        Add-Content $log "[ERREUR] $component a échoué avec code $($process.ExitCode)"
        exit $process.ExitCode
    } else {
        Add-Content $log "$component installé avec succès"
        Write-Output "$component installé avec succès"
    }
}

# === Installation Gateway ===
Install-MSI "C:\Temp\OnPremiseGatewayInstaller.exe" "C:\Temp\gateway_install.log" "Power BI Gateway"

# === Installation IR ===
Install-MSI "C:\Temp\IntegrationRuntime.msi" "C:\Temp\ir_install.log" "Integration Runtime"

# === Installation Spark ODBC ===
try {
    Add-Content $log "Vérification ODBC ZIP..."
    $zipPath = "C:\Temp\SimbaSparkODBC.zip"
    $zipExpected = '86D295D1A1C1FACA9C05CE6B0D62B9DA5078F12635A494543B7182E0EDF7E4CD'
    $zipActual   = (Get-FileHash $zipPath -Algorithm SHA256).Hash.ToLower()
    if ($zipActual -ne $zipExpected.ToLower()) { throw "Checksum ZIP invalide" }

    Expand-Archive -Path $zipPath -DestinationPath "C:\Temp\SparkODBC" -Force
    $msi = Get-ChildItem "C:\Temp\SparkODBC" -Recurse -Filter *.msi | Select-Object -First 1
    if (-not $msi) { throw "Aucun MSI trouvé dans ODBC ZIP" }

    Install-MSI $msi.FullName "C:\Temp\spark_odbc_install.log" "Spark ODBC"

    Add-Content $log "Copie DLL Simba..."
    $src = "C:\Program Files\Simba Spark ODBC Driver\lib"
    $dst = "C:\Program Files\On-premises data gateway\m\ODBC Drivers\New\Spark"
    if (!(Test-Path $dst)) { New-Item -ItemType Directory -Force -Path $dst | Out-Null }
    Copy-Item -Path (Join-Path $src '*') -Destination $dst -Recurse -Force

    Add-Content $log "Spark ODBC OK"
    Write-Output "Spark ODBC installé avec succès"
}
catch {
    Add-Content $log ("[ERREUR] ODBC: " + $_.Exception.Message)
    exit 1
}

Add-Content $log "--- Installation terminée avec succès ---"
Write-Output "=== Installation terminée avec succès ==="