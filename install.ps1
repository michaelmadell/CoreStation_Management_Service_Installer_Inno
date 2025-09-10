# This PowerShell  script will install the app as a Windows 11 service
# install.ps1

# Check for admin rights
if (-not ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Host "This script must be run as Administrator." -ForegroundColor Red
    exit 1
}

$serviceName = "CoreStationService"
$exePath = "$PSScriptRoot\nodeWinApp.exe"

Write-Host "Installing $serviceName..."
$existingService = Get-Service -Name $serviceName -ErrorAction SilentlyContinue
if ($existingService) {
    Write-Host "Service $serviceName already exists. Stopping and deleting..."
    Stop-Service -Name $serviceName -Force -ErrorAction SilentlyContinue
    sc.exe delete $serviceName | Out-Null

    # Wait until the service is truly gone
    $maxWait = 15
    $elapsed = 0
    while (Get-Service -Name $serviceName -ErrorAction SilentlyContinue) {
        Start-Sleep -Seconds 1
        $elapsed++
        if ($elapsed -ge $maxWait) {
            throw "Timed out waiting for $serviceName to be deleted."
        }
    }
    Write-Host "$serviceName successfully deleted."
}


# Create the service
New-Service -Name $serviceName `
            -BinaryPathName "`"$exePath`"" `
            -DisplayName "CoreStation Management Service" `
            -StartupType Automatic `
            -Description "Pass network, session and power status to CoreStation management contoller " `
            -ErrorAction Stop

# Set service recovery options (restart on failure 1st/2nd/3rd+ time in ms)
sc.exe failure $serviceName reset= 0 actions= restart/1000/restart/2000/restart/5000

# Start the service
Start-Service -Name $serviceName

Write-Host "$serviceName installed and started successfully."
