$ErrorActionPreference = 'Stop'
$log = 'C:\Temp\install_debug.log'

if (!(Test-Path -Path 'C:\Temp')) { New-Item -ItemType Directory -Path 'C:\Temp' | Out-Null }
Add-Content $log "--- Démarrage installation ---"

# Lancer les 3 téléchargements en parallèle
$jobs = @()

$jobs += Start-Job -ScriptBlock {
    Invoke-WebRequest -Uri 'https://go.microsoft.com/fwlink/?LinkId=2116849&clcid=0x409' -OutFile 'C:\Temp\OnPremiseGatewayInstaller.exe'
} -Name "Gateway"

$jobs += Start-Job -ScriptBlock {
    Invoke-WebRequest -Uri 'https://download.microsoft.com/download/e/4/7/e4771905-1079-445b-8bf9-8a1a075d8a10/IntegrationRuntime_5.57.9350.2.msi' -OutFile 'C:\Temp\IntegrationRuntime.msi'
} -Name "IR"

$jobs += Start-Job -ScriptBlock {
    Invoke-WebRequest -Uri 'https://databricks-bi-artifacts.s3.us-east-2.amazonaws.com/simbaspark-drivers/odbc/2.9.2/SimbaSparkODBC-2.9.2.1008-Windows-64bit.zip' -OutFile 'C:\Temp\SimbaSparkODBC.zip'
} -Name "ODBC"

# Attendre la fin de tous les jobs
$jobs | Wait-Job | Receive-Job
$jobs | Remove-Job

Add-Content $log "Téléchargements terminés"

# === Installation Gateway ===
try {
    Add-Content $log 'Installation Gateway...'
    Start-Process msiexec.exe -ArgumentList "/i C:\Temp\OnPremiseGatewayInstaller.exe /quiet /norestart" -Wait
    Add-Content $log 'Gateway OK'
}
catch {
    Add-Content $log ("[ERREUR] Gateway: " + $_.Exception.Message)
    exit 1
}

# === Installation Integration Runtime ===
try {
    Add-Content $log 'Installation IR...'
    Start-Process msiexec.exe -ArgumentList "/i C:\Temp\IntegrationRuntime.msi /quiet /norestart /l*v C:\Temp\ir_install.log" -Wait
    Add-Content $log 'IR OK'
}
catch {
    Add-Content $log ("[ERREUR] IR: " + $_.Exception.Message)
    exit 1
}

# === Spark ODBC ===
try {
    Add-Content $log 'Vérification ODBC ZIP...'
    $zipExpected = '86D295D1A1C1FACA9C05CE6B0D62B9DA5078F12635A494543B7182E0EDF7E4CD'
    $zipActual   = (Get-FileHash 'C:\Temp\SimbaSparkODBC.zip' -Algorithm SHA256).Hash.ToLower()
    if ($zipActual -ne $zipExpected.ToLower()) { throw 'Checksum ZIP invalide' }

    Expand-Archive -Path 'C:\Temp\SimbaSparkODBC.zip' -DestinationPath 'C:\Temp\SparkODBC' -Force
    $msi = Get-ChildItem 'C:\Temp\SparkODBC' -Recurse -Filter *.msi | Select-Object -First 1
    if (-not $msi) { throw 'Aucun MSI trouvé' }

    Add-Content $log 'Installation Spark ODBC...'
    Start-Process msiexec.exe -ArgumentList "/i `"$($msi.FullName)`" /quiet /norestart /l*v C:\Temp\spark_odbc_install.log" -Wait

    Add-Content $log 'Copie DLL Simba...'
    $src = 'C:\Program Files\Simba Spark ODBC Driver\lib'
    $dst = 'C:\Program Files\On-premises data gateway\m\ODBC Drivers\New\Spark'
    if (!(Test-Path $dst)) { New-Item -ItemType Directory -Force -Path $dst | Out-Null }
    Copy-Item -Path (Join-Path $src '*') -Destination $dst -Recurse -Force

    Add-Content $log 'ODBC OK'
}
catch {
    Add-Content $log ("[ERREUR] ODBC: " + $_.Exception.Message)
    exit 1
}

Add-Content $log "--- Installation terminée avec succès ---"