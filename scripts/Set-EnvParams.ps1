$ENV_FILE = "config/prd/.env"  # Adjust the path based on your environment

# Step 1: Check if ENV_FILE exists
if (Test-Path $ENV_FILE) {
    Write-Host "ENV_FILE exists: $ENV_FILE"
} else {
    Write-Error "ENV_FILE does not exist: $ENV_FILE"
    exit 1
}

# Step 2: Create a backup of the ENV_FILE
$backupFile = "$ENV_FILE.bak"
if (Test-Path $backupFile) {
    Remove-Item $backupFile -Force
}
Copy-Item -Path $ENV_FILE -Destination $backupFile
Write-Host "Backup of ENV_FILE created: $backupFile"

# Step 3: Remove quotation marks from ENV_FILE
(Get-Content -Path $ENV_FILE -Encoding UTF8) | ForEach-Object {$_ -replace '"',''} | Out-File -FilePath $ENV_FILE -Encoding UTF8
Write-Host "Quotation marks removed from ENV_FILE."

# Step 3: Import environment variables from ENV_FILE
Write-Host "Importing environment variables from file..."
Get-Content -Path $ENV_FILE -Encoding UTF8 | ForEach-Object {
    $envVarName, $envVarValue = ($_ -replace '"','').split('=')
    [System.Environment]::SetEnvironmentVariable($envVarName, $envVarValue, [System.EnvironmentVariableTarget]::Process)
    Write-Host "Set $envVarName to $envVarValue"
}

# Step 4: Set environment variables recursively
Write-Host "Setting environment variables recursively..."
Get-Content -Path $ENV_FILE -Encoding UTF8 | ForEach-Object {
    $envVarName, $envVarValue = ($_ -replace '"','').split('=')
    [System.Environment]::SetEnvironmentVariable($envVarName, $envVarValue, "User")
    Write-Host "Environment variable set: $envVarName = $envVarValue"
}

# Step 5: Confirm Variables set
Write-Host "Confirming environment variables..."
Get-Content -Path $ENV_FILE -Encoding UTF8 | ForEach-Object {
    $envVarName, $envVarValue = ($_ -replace '"','').split('=')
    Write-Host "${envVarName}: $envVarValue"
}

# Step 6: Revert to backup file
$revert = Read-Host "Do you want to revert to the backup file? (y/n)"
if ($revert -eq 'y') {
    if (Test-Path $backupFile) {
        Remove-Item -Path $ENV_FILE -Force
        Copy-Item -Path $backupFile -Destination $ENV_FILE
        Write-Host "Reverted to backup file: $backupFile"
    } else {
        Write-Error "Backup file does not exist: $backupFile"
    }
} else {
    Write-Host "No changes made to the original ENV_FILE."
}

# Step 7: Remove backup file
if (Test-Path $backupFile) {
    Remove-Item -Path $backupFile -Force
    Write-Host "Backup file removed: $backupFile"
} else {
    Write-Host "No backup file to remove."
}

# Pause to confirm
$null = Read-Host "Press Enter to continue..."

# Restart visual studio code
Stop-Process -Name Code -Force
Start-Process -FilePath "C:\Program Files\Microsoft VS Code\Code.exe"