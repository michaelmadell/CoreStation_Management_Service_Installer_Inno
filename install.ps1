<#
.SYNOPSIS
    Installs and starts the CoreStation service.
.DESCRIPTION
    This script installs the CoreStation service from its executable. It must be run with
    Administrator privileges. If the service already exists, it will be cleanly removed
    before the new version is installed. The script also configures the service to restart
    automatically on failure and then starts it.
.PARAMETER ServiceName
    The name for the new service.
.PARAMETER ExePath
    The full path to the service's executable file. Defaults to 'CoreStationHXAgent.exe' in the same
    directory as the script.
.EXAMPLE
    .\install.ps1
.EXAMPLE
    .\install.ps1 -ServiceName "MyTestService" -ExePath "C:\Path\To\My.exe"
#>

[CmdletBinding(SupportsShouldProcess=$true)]
param (
    [Parameter()]
    [string]$ServiceName = "CoreStationService",

    [Parameter()]
    [string]$ExePath = ""
)

# $PSScriptRoot is empty when launched by Inno Setup's Exec() -- fall back to the
# directory of the script file itself, then the working directory.
if ($ExePath -eq "") {
    $ScriptDir = if ($PSScriptRoot -ne "") {
        $PSScriptRoot
    } elseif ($MyInvocation.MyCommand.Path -ne "") {
        Split-Path -Parent $MyInvocation.MyCommand.Path
    } else {
        (Get-Location).Path
    }
    $ExePath = Join-Path $ScriptDir "CoreStationHXAgent.exe"
}

# Log everything to a file so silent Inno runs can be diagnosed
$LogPath = "C:\Windows\Temp\CoreStation_install.log"
Start-Transcript -Path $LogPath -Force | Out-Null

Write-Host "PSScriptRoot  : '$PSScriptRoot'"
Write-Host "ExePath param : '$ExePath'"
Write-Host "WorkingDir    : '$(Get-Location)'"
Write-Host "Running as    : '$([Security.Principal.WindowsIdentity]::GetCurrent().Name)'"

# 1. Verify the script is running with Administrator privileges
if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Error "This script must be run as Administrator. Please open a new PowerShell terminal with 'Run as Administrator'."
    Stop-Transcript | Out-Null
    exit 1
}

# 2. Verify the executable file exists before we begin
if (-not (Test-Path -Path $ExePath -PathType Leaf)) {
    Write-Error "The service executable was not found at the expected location: '$ExePath'"
    Stop-Transcript | Out-Null
    exit 1
}

Write-Host "Starting installation for service: '$ServiceName'..."

try {
    # 3. Check for and remove any existing version of the service for a clean install
    $existingService = Get-Service -Name $ServiceName -ErrorAction SilentlyContinue
    if ($null -ne $existingService) {
        Write-Host "An existing service named '$ServiceName' was found. Removing it first."

        if ($existingService.Status -ne 'Stopped') {
            Stop-Service -Name $ServiceName -Force
            Write-Host "Waiting for service to stop..."
            $svc = Get-Service -Name $ServiceName
            $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
            while ($svc.Status -ne 'Stopped') {
                if ($stopwatch.Elapsed.TotalSeconds -gt 30) {
                    throw "Timed out waiting for service '$ServiceName' to stop."
                }
                Start-Sleep -Seconds 1
                $svc.Refresh()
            }
            $stopwatch.Stop()
        }

        sc.exe delete $ServiceName | Out-Null

        # Verify removal to prevent conflicts
        $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
        while ($stopwatch.Elapsed.TotalSeconds -lt 15) {
            if ($null -eq (Get-Service -Name $ServiceName -ErrorAction SilentlyContinue)) {
                $stopwatch.Stop(); break
            }
            Start-Sleep -Seconds 1
        }
        if ($stopwatch.IsRunning) {
            throw "Timed out waiting for the existing service to be deleted."
        }
        Write-Host "Existing service removed successfully."
    }

    # 4. Remove legacy executable locations
    $existingApp = Get-ChildItem -Path "C:\ProgramData\ahk\nodeWinApp.exe" -ErrorAction SilentlyContinue
    if ($null -ne $existingApp) {
        Write-Host "Removing legacy executable at 'C:\ProgramData\ahk\nodeWinApp.exe'..."
        Remove-Item -Path "C:\ProgramData\ahk\nodeWinApp.exe" -Force
        Write-Host "Removed successfully."
    }

    # 5. Copy the executable to the install directory (skip if already running from there)
    $DestDir    = "C:\Program Files (x86)\CoreStation HX Agent"
    $NewExePath = "$DestDir\CoreStationHXAgent.exe"

    # Resolve to absolute paths so we can compare regardless of how the script was invoked
    $resolvedSource = [System.IO.Path]::GetFullPath($ExePath)
    $resolvedDest   = [System.IO.Path]::GetFullPath($NewExePath)

    Write-Host "Resolved source : '$resolvedSource'"
    Write-Host "Resolved dest   : '$resolvedDest'"

    if ($resolvedSource -ieq $resolvedDest) {
        Write-Host "Executable is already in the install directory. Skipping copy."
    } else {
        if (-not (Test-Path -Path $DestDir -PathType Container)) {
            Write-Host "Creating destination directory: '$DestDir'..."
            New-Item -ItemType Directory -Path $DestDir -Force | Out-Null
        }

        if (Test-Path -Path $NewExePath -PathType Leaf) {
            Write-Host "Removing existing executable at '$NewExePath'..."
            Remove-Item -Path $NewExePath -Force -ErrorAction Stop
        }

        Write-Host "Copying executable to '$DestDir'..."
        Copy-Item -Path $resolvedSource -Destination $NewExePath -Force -ErrorAction Stop

        if (-not (Test-Path -Path $NewExePath -PathType Leaf)) {
            throw "Copy appeared to succeed but '$NewExePath' was not found. Aborting."
        }
    }

    # 6. Create the new service
    Write-Host "Creating new service from executable: '$NewExePath'..."
    New-Service -Name $ServiceName `
                -BinaryPathName $NewExePath `
                -DisplayName "CoreStation HX Agent" `
                -StartupType Automatic `
                -Description "Passes network, session, and power status to the CoreStation management controller."

    # 7. Configure service recovery options
    Write-Host "Configuring service recovery options..."
    sc.exe failure $ServiceName reset= 0 actions= restart/1000/restart/2000/restart/5000 | Out-Null

    Write-Host "Service '$ServiceName' installed successfully." -ForegroundColor Green
}
catch {
    Write-Error "An error occurred during installation: $_"
    if (Get-Service -Name $ServiceName -ErrorAction SilentlyContinue) {
        Write-Warning "Attempting to clean up partially installed service..."
        sc.exe delete $ServiceName | Out-Null
    }
    Stop-Transcript | Out-Null
    exit 1
}

# 8. Start the service — separate try/catch so a start failure does not roll back the registration
if ($pscmdlet.ShouldProcess($ServiceName, "Start Service")) {
    Write-Host "Starting service..."
    try {
        Start-Service -Name $ServiceName -ErrorAction Stop
        Write-Host "Service '$ServiceName' started successfully." -ForegroundColor Green
    }
    catch {
        Write-Warning "Service was installed but could not be started: $_"
        Write-Warning "Check the Windows Event Log for details:"
        Write-Warning "  Get-EventLog -LogName System -Source 'Service Control Manager' -Newest 5"
        Stop-Transcript | Out-Null
        exit 2
    }
}

Stop-Transcript | Out-Null