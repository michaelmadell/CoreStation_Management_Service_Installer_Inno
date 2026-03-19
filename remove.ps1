<#
.SYNOPSIS
    Stops and removes CoreStationHXAgent service.
.DESCRIPTION
    This script uninstalls a Windows service from the system. It must be run with
    Administrator privileges.
#>
[CmdletBinding()]
param (
    # Explicitly setting Mandatory to false prevents the prompt
    [string]$ServiceName = "CoreStationService"
)

# 1. Verify the script is running with Administrator privileges
$currentPrincipal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
if (-not $currentPrincipal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Error "This script must be run as Administrator. Please open a new PowerShell terminal with 'Run as Administrator'."
    exit 1
}

Write-Host "Attempting to remove service: '$ServiceName'..." -ForegroundColor Cyan

try {
    # 2. Check if the service actually exists
    $service = Get-Service -Name $ServiceName -ErrorAction SilentlyContinue

    if ($null -eq $service) {
        Write-Host "Service '$ServiceName' does not exist. No action needed." -ForegroundColor Green
        exit 0
    }

    # 3. Stop the service if it's not already stopped
    if ($service.Status -ne 'Stopped') {
        Write-Host "Service status is '$($service.Status)'. Stopping the service..." -ForegroundColor Yellow
        Stop-Service -Name $ServiceName -Force
        
        # Manually wait for the service to stop
        Write-Host "Waiting for service to stop..."
        $timeout = 30 
        $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
        while ($service.Status -ne 'Stopped') {
            if ($stopwatch.Elapsed.TotalSeconds -gt $timeout) {
                throw "Timed out waiting for service '$ServiceName' to stop."
            }
            Start-Sleep -Seconds 1
            $service.Refresh() 
        }
    }

    # 4. Delete the service
    Write-Host "Deleting service from registry..." -ForegroundColor Yellow
    & sc.exe delete $ServiceName | Out-Null
    
    # 5. Verify the service has been removed
    Write-Host "Verifying service removal..."
    $maxWaitSeconds = 15
    $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()

    while ($stopwatch.Elapsed.TotalSeconds -lt $maxWaitSeconds) {
        if ($null -eq (Get-Service -Name $ServiceName -ErrorAction SilentlyContinue)) {
            $stopwatch.Stop()
            Write-Host "Service '$ServiceName' was successfully removed." -ForegroundColor Green
            
            # 6. Delete Application executable
            # Fixed: Use $env:TEMP instead of %temp% for PowerShell compatibility
            $exePath = "C:\ProgramData\ahk\nodeWinApp.exe"
            if (Test-Path $exePath) {
                Write-Host "Moving Application executable to temp..."
                Move-Item -Path $exePath -Destination "$env:TEMP\nodeWinApp.exe" -Force
            }
            $exePath = "C:\Program Files (x86)\CoreStation HX Agent\CoreStationHXAgent.exe"
             if (Test-Path $exePath) {
                Write-Host "Moving Application executable to temp..."
                Move-Item -Path $exePath -Destination "$env:TEMP\CoreStationHXAgent.exe" -Force
            }
            exit 0
        }
        Start-Sleep -Seconds 1
    }
    
    throw "Timed out waiting for '$ServiceName' to be deleted. Please check 'services.msc' manually."

}
catch {
    Write-Error "An error occurred during service removal: $($_.Exception.Message)"
    exit 1
}