$ErrorActionPreference = 'Stop'
$log = 'C:\Temp\install_debug.log'

if (!(Test-Path -Path 'C:\Temp')) { New-Item -ItemType Directory -Path 'C:\Temp' | Out-Null }
Add-Content $log "--- Démarrage installation ---"

# === Power BI Gateway ===
try {
    Add-Content $log 'Téléchargement Power BI Gateway...'
    $msiUrl = 'https://go.microsoft.com/fwlink/?LinkId=2116849&clcid=0x409'
    $localPath = 'C:\Temp\OnPremiseGatewayInstaller.exe'
    Invoke-WebRequest -Uri $msiUrl -OutFile $localPath -UseBasicParsing
    Add-Content $log 'Installation Gateway...'
    Start-Process msiexec.exe -ArgumentList "/i `"$localPath`" /quiet /norestart" -Wait
    Add-Content $log 'Power BI Gateway OK'
}
catch {
    Add-Content $log ("[ERREUR] Gateway: " + $_.Exception.Message)
    exit 1
}

# === Integration Runtime ===
try {
    Add-Content $log 'Téléchargement Integration Runtime...'
    $irUrl = 'https://download.microsoft.com/download/e/4/7/e4771905-1079-445b-8bf9-8a1a075d8a10/IntegrationRuntime_5.57.9350.2.msi'
    $irPath = 'C:\Temp\IntegrationRuntime.msi'
    Invoke-WebRequest -Uri $irUrl -OutFile $irPath -UseBasicParsing
    Add-Content $log 'Installation Integration Runtime...'
    Start-Process msiexec.exe -ArgumentList "/i `"$irPath`" /quiet /norestart /l*v C:\Temp\ir_install.log" -Wait
    Add-Content $log 'Integration Runtime OK'
}
catch {
    Add-Content $log ("[ERREUR] IR: " + $_.Exception.Message)
    exit 1
}

# === Spark ODBC Driver ===
try {
    Add-Content $log 'Téléchargement Spark ODBC...'
    $zipUrl = 'https://databricks-bi-artifacts.s3.us-east-2.amazonaws.com/simbaspark-drivers/odbc/2.9.2/SimbaSparkODBC-2.9.2.1008-Windows-64bit.zip'
    $zipPath = 'C:\Temp\SimbaSparkODBC.zip'
    Invoke-WebRequest -Uri $zipUrl -OutFile $zipPath -UseBasicParsing

    $zipExpected = '86D295D1A1C1FACA9C05CE6B0D62B9DA5078F12635A494543B7182E0EDF7E4CD'
    $zipActual   = (Get-FileHash $zipPath -Algorithm SHA256).Hash.ToLower()
    if ($zipActual -ne $zipExpected.ToLower()) { throw 'Checksum ZIP invalide' }

    Expand-Archive -Path $zipPath -DestinationPath 'C:\Temp\SparkODBC' -Force

    $msi = Get-ChildItem 'C:\Temp\SparkODBC' -Recurse -Filter *.msi | Select-Object -First 1
    if (-not $msi) { throw 'Aucun MSI trouvé' }

    $msiPath = 'C:\Temp\SimbaSparkODBC.msi'
    Copy-Item $msi.FullName -Destination $msiPath -Force

    $msiExpected = '76E76E472480B811B8C38A641ED4D3B323D87647D29A2E59361AA45BD4FED923'
    $msiActual   = (Get-FileHash $msiPath -Algorithm SHA256).Hash.ToLower()
    if ($msiActual -ne $msiExpected.ToLower()) { throw 'Checksum MSI invalide' }

    Add-Content $log 'Installation Spark ODBC...'
    Start-Process msiexec.exe -ArgumentList "/i `"$msiPath`" /quiet /norestart /l*v C:\Temp\spark_odbc_install.log" -Wait

    Add-Content $log 'Copie DLL Simba...'
    $src = 'C:\Program Files\Simba Spark ODBC Driver\lib'
    $dst = 'C:\Program Files\On-premises data gateway\m\ODBC Drivers\New\Spark'
    if (-not (Test-Path $src)) { throw 'DLL Simba non trouvées après installation' }
    if (-not (Test-Path $dst)) { New-Item -ItemType Directory -Force -Path $dst | Out-Null }
    Copy-Item -Path (Join-Path $src '*') -Destination $dst -Recurse -Force

    Add-Content $log 'Spark ODBC OK'
}
catch {
    Add-Content $log ("[ERREUR] ODBC: " + $_.Exception.Message)
    exit 1
}

Add-Content $log '--- Installation terminée avec succès ---'
