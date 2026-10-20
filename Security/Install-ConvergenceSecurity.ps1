########################################################
# Description : Setup convergence security for Windows
# Create DATE : 2026.10.14
# Last Update DATE : 2026.10.15 by ashurei
# Copyright (c) ashurei@sktelecom.com, 2026
########################################################
#requires -Version 5.1
#requires -RunAsAdministrator

[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$PackageVersion = '2.3.0'
$PackageDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$InstallDir = Join-Path $env:ProgramFiles 'ConvergenceSecurity\BMC'
$DataDir = Join-Path $env:ProgramData 'ConvergenceSecurity\BMC'
$ConfigPath = Join-Path $DataDir 'config.json'
$StatePath = Join-Path $DataDir 'State\bmc_state.json'
$InstallMarkerPath = Join-Path $DataDir 'install.json'
$InstallInProgressPath = Join-Path $DataDir 'install.inprogress'
$TaskName = 'ConvergenceSecurity-BmcMonitor'
$EventSource = 'ConvergenceSecurityBMC'
$PowerShellExe = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
#$SchtasksExe = Join-Path $env:SystemRoot 'System32\schtasks.exe'
$LegacyTaskNames = @('ConvergenceSecurity-HPE-BmcMonitor', 'ConvergenceSecurity-Dell-BmcMonitor')
$StepStatus = @('PENDING', 'PENDING', 'PENDING', 'PENDING', 'PENDING')
$StepMessage = @('', '', '', '', '')
$CurrentStep = 0
$script:ResolvedVendor = 'UNKNOWN'
$script:ServerRelease = 'UNKNOWN'

function Write-Step {
    param([int]$Number, [string]$Message)
    $script:CurrentStep = $Number
    Write-Host ('[{0}/5] {1}' -f $Number, $Message)
}

function Complete-Step {
    param([int]$Number, [string]$Message)
    $script:StepStatus[$Number - 1] = 'OK'
    $script:StepMessage[$Number - 1] = $Message
    Write-Host ('[OK] {0}' -f $Message)
}

function Skip-Step {
    param([int]$Number, [string]$Message)
    $script:StepStatus[$Number - 1] = 'SKIPPED'
    $script:StepMessage[$Number - 1] = $Message
    Write-Host ('[SKIPPED] {0}' -f $Message)
}

function Write-FinalSummary {
    param(
        [ValidateSet('INSTALLED', 'SKIPPED', 'FAILED')]
        [string]$Outcome,
        [string]$Message = ''
    )

    Write-Host ''
    Write-Host '============================================================'
    Write-Host ('Convergence Security Windows BMC package {0}' -f $PackageVersion)
    for ($i = 0; $i -lt $StepStatus.Count; $i++) {
        $stepText = $StepMessage[$i]
        if ([string]::IsNullOrWhiteSpace($stepText)) { $stepText = '-' }
        Write-Host ('Step {0}: {1,-8} {2}' -f ($i + 1), $StepStatus[$i], $stepText)
    }

    switch ($Outcome) {
        'INSTALLED' {
            Write-Host '[FINAL] OK - installation completed'
            Write-Host ('Vendor       : {0}' -f $script:ResolvedVendor)
            Write-Host ('Server       : {0}' -f $script:ServerRelease)
            Write-Host ('Install path : {0}' -f $InstallDir)
            Write-Host ('Log path     : {0}' -f (Join-Path $DataDir 'Logs\bmc_monitor.log'))
            Write-Host ('Task name    : {0}' -f $TaskName)
        }
        'SKIPPED' {
            Write-Host ('[FINAL] SKIPPED - {0}' -f $Message)
        }
        'FAILED' {
            Write-Host ('[FINAL] FAILED - {0}' -f $Message)
        }
    }
    Write-Host '============================================================'
}

function Test-ScheduledTaskExists {
    param([string]$Name)
    $task = Get-ScheduledTask -TaskName $Name -ErrorAction SilentlyContinue
    return ($null -ne $task)
}

function Get-ExistingInstallationEvidence {
    $evidence = New-Object System.Collections.ArrayList
    $installedMonitor = Join-Path $InstallDir 'Monitor-ConvergenceSecurityBmc.ps1'
    $installedLog = Join-Path $DataDir 'Logs\bmc_monitor.log'

    # The marker is written only after all five installation steps succeed.
    if (Test-Path -LiteralPath $InstallMarkerPath -PathType Leaf) {
        [void]$evidence.Add("install marker: $InstallMarkerPath")
    }

    # This complete file set also recognizes an older successful package that
    # predates install.json. Files from an early STEP 1/2 failure are insufficient.
    if ((-not (Test-Path -LiteralPath $InstallInProgressPath -PathType Leaf)) -and
        (Test-Path -LiteralPath $installedMonitor -PathType Leaf) -and
        (Test-Path -LiteralPath $ConfigPath -PathType Leaf) -and
        (Test-Path -LiteralPath $StatePath -PathType Leaf) -and
        (Test-Path -LiteralPath $installedLog -PathType Leaf)) {
        [void]$evidence.Add('installed monitor, configuration, state, and log files')
    }

    foreach ($scheduledName in @($TaskName) + $LegacyTaskNames) {
        if (Test-ScheduledTaskExists -Name $scheduledName) {
            [void]$evidence.Add("scheduled task: $scheduledName")
        }
    }

    return @($evidence)
}

function Get-ExistingVendor {
    if (-not (Test-Path -LiteralPath $ConfigPath -PathType Leaf)) { return 'UNKNOWN' }
    try {
        $config = Get-Content -LiteralPath $ConfigPath -Raw | ConvertFrom-Json
        if ($config.PSObject.Properties['Vendor']) { return [string]$config.Vendor }
    }
    catch {
        Write-Warning "Existing config could not be read while checking installation state: $($_.Exception.Message)"
    }
    return 'UNKNOWN'
}

function Get-Sha256 {
    param([string]$Path)
    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
}

function Write-InstallerIdentity {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "Vendor installer not found: $Path"
    }

    $hash = Get-Sha256 -Path $Path
    Write-Host ('[INFO] Installer: {0}' -f $Path)
    Write-Host ('[INFO] SHA256   : {0}' -f $hash)

    try {
        $signature = Get-AuthenticodeSignature -LiteralPath $Path
        if ($signature.Status -eq 'Valid') {
            Write-Host ('[OK] Authenticode signature: {0}' -f $signature.SignerCertificate.Subject)
        }
        else {
            Write-Warning ('Installer signature status is {0}. Verify the file source before deployment.' -f $signature.Status)
        }
    }
    catch {
        Write-Warning "Installer signature could not be inspected: $($_.Exception.Message)"
    }
}

function Get-VersionFromFileName {
    param([string]$Name)
    $match = [regex]::Match($Name, '(?<!\d)(\d+\.\d+\.\d+\.\d+)(?!\d)')
    if (-not $match.Success) { return $null }
    try { return [version]$match.Groups[1].Value }
    catch { return $null }
}

function Get-HpeInstaller {
    $toolDir = Join-Path $PackageDir 'Tools\HPE'
    if (-not (Test-Path -LiteralPath $toolDir -PathType Container)) {
        throw "HPE tool directory not found: $toolDir"
    }

    $candidates = @()
    foreach ($file in @(Get-ChildItem -LiteralPath $toolDir -File -ErrorAction SilentlyContinue)) {
        if ($file.Name -notlike 'ilorest-*.msi') { continue }
        $version = Get-VersionFromFileName -Name $file.Name
        if ($null -eq $version) {
            Write-Warning "Ignoring an iLOREST MSI whose version could not be parsed from the filename: $($file.Name)"
            continue
        }
        if ($version -lt [version]'7.3.0.0' -or $version -ge [version]'7.4.0.0') {
            Write-Warning "Ignoring unsupported iLOREST version $($version): $($file.Name)"
            continue
        }
        $candidates += [pscustomobject]@{ File = $file; Version = $version }
    }

    $selected = $candidates | Sort-Object Version -Descending | Select-Object -First 1
    if ($null -eq $selected) {
        throw "No supported HPE iLOREST 7.3.x installer was found. Place ilorest-7.3.*.msi under $toolDir"
    }
    Write-Host ('[INFO] Selected HPE iLOREST installer version {0}: {1}' -f $selected.Version, $selected.File.Name)
    return $selected.File.FullName
}

function Get-DellInstaller {
    param([string]$ServerRelease)

    $toolDir = Join-Path $PackageDir 'Tools\Dell'
    if (-not (Test-Path -LiteralPath $toolDir -PathType Container)) {
        throw "Dell tool directory not found: $toolDir"
    }

    $candidates = @()
    foreach ($file in @(Get-ChildItem -LiteralPath $toolDir -File -ErrorAction SilentlyContinue)) {
        if ($file.Extension -notin @('.exe', '.msi')) { continue }
        if ($file.Name -notmatch '(?i)(idractools|drac[^\\/]*tools|om-drac)') { continue }
        $version = Get-VersionFromFileName -Name $file.Name
        if ($null -eq $version) {
            Write-Warning "Ignoring a Dell installer whose version could not be parsed from the filename: $($file.Name)"
            continue
        }
        $candidates += [pscustomobject]@{ File = $file; Version = $version }
    }

    $eligible = @()
    switch ($ServerRelease) {
        '2016' { $eligible = @($candidates | Where-Object { $_.Version -ge [version]'10.3.0.0' -and $_.Version -lt [version]'10.4.0.0' }) }
        '2019' { $eligible = @($candidates | Where-Object { $_.Version -ge [version]'10.3.0.0' -and $_.Version -lt [version]'10.4.0.0' }) }
        '2022' { $eligible = @($candidates | Where-Object { $_.Version -ge [version]'10.3.0.0' -and $_.Version -lt [version]'10.4.0.0' }) }
        '2025' { $eligible = @($candidates | Where-Object { $_.Version -ge [version]'11.4.0.0' -and $_.Version -lt [version]'11.5.0.0' }) }
        default { throw "Unsupported Windows Server release for Dell installer selection: $ServerRelease" }
    }

    $selected = $eligible | Sort-Object Version -Descending | Select-Object -First 1
    if ($null -eq $selected) {
        if ($ServerRelease -eq '2025') {
            throw "No supported Dell iDRAC Tools 11.4.x installer was found for Windows Server 2025. Place an 11.4.* package under $toolDir"
        }
        throw "No supported Dell iDRAC Tools 10.3.x installer was found for Windows Server $ServerRelease. Place a 10.3.* package under $toolDir"
    }

    Write-Host ('[INFO] Selected Dell iDRAC Tools installer version {0}: {1}' -f $selected.Version, $selected.File.Name)
    return $selected.File.FullName
}

function Resolve-IloRestExecutable {
    $candidates = New-Object System.Collections.ArrayList
    [void]$candidates.Add((Join-Path $PackageDir 'Tools\HPE\ilorest.exe'))

    $command = Get-Command ilorest.exe -ErrorAction SilentlyContinue
    if ($command) { [void]$candidates.Add($command.Source) }

    $searchRoots = New-Object System.Collections.ArrayList
    foreach ($root in @($env:ProgramFiles, ${env:ProgramFiles(x86)})) {
        if (-not $root) { continue }
        foreach ($relative in @(
            'Hewlett Packard Enterprise\RESTful Interface Tool\ilorest.exe',
            'HPE\RESTful Interface Tool\ilorest.exe'
        )) {
            [void]$candidates.Add((Join-Path $root $relative))
        }
        foreach ($vendorDir in @('Hewlett Packard Enterprise', 'HPE')) {
            $path = Join-Path $root $vendorDir
            if (Test-Path -LiteralPath $path -PathType Container) { [void]$searchRoots.Add($path) }
        }
    }

    foreach ($candidate in $candidates) {
        if ($candidate -and (Test-Path -LiteralPath $candidate -PathType Leaf)) {
            return (Resolve-Path -LiteralPath $candidate).Path
        }
    }

    foreach ($root in $searchRoots) {
        $found = Get-ChildItem -LiteralPath $root -Filter ilorest.exe -File -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($found) { return $found.FullName }
    }
    return $null
}

function Resolve-RacadmExecutable {
    $candidates = New-Object System.Collections.ArrayList
    [void]$candidates.Add((Join-Path $PackageDir 'Tools\Dell\racadm.exe'))

    $command = Get-Command racadm.exe -ErrorAction SilentlyContinue
    if ($command) { [void]$candidates.Add($command.Source) }

    $searchRoots = New-Object System.Collections.ArrayList
    foreach ($root in @($env:ProgramFiles, ${env:ProgramFiles(x86)})) {
        if (-not $root) { continue }
        foreach ($relative in @(
            'Dell\SysMgt\rac5\racadm.exe',
            'Dell\SysMgt\idrac\racadm.exe',
            'Dell\SysMgt\IDRACTools\racadm\racadm.exe',
            'Dell\OpenManage\racadm\racadm.exe',
            'Dell EMC\OpenManage\racadm\racadm.exe'
        )) {
            [void]$candidates.Add((Join-Path $root $relative))
        }
        foreach ($vendorDir in @('Dell', 'Dell EMC')) {
            $path = Join-Path $root $vendorDir
            if (Test-Path -LiteralPath $path -PathType Container) { [void]$searchRoots.Add($path) }
        }
    }

    foreach ($candidate in $candidates) {
        if ($candidate -and (Test-Path -LiteralPath $candidate -PathType Leaf)) {
            return (Resolve-Path -LiteralPath $candidate).Path
        }
    }

    foreach ($root in $searchRoots) {
        $found = Get-ChildItem -LiteralPath $root -Filter racadm.exe -File -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($found) { return $found.FullName }
    }
    return $null
}

function Test-IsVirtualMachine {
    param($ComputerSystem)
    $text = ('{0} {1}' -f $ComputerSystem.Manufacturer, $ComputerSystem.Model)
    return ($text -match '(?i)virtual machine|vmware|virtualbox|kvm|qemu|xen|hyper-v|parallels|bochs')
}

function Resolve-HardwareVendor {
    param($ComputerSystem)
    $manufacturer = [string]$ComputerSystem.Manufacturer
    if ($manufacturer -match '(?i)dell') { return 'DELL' }
    if ($manufacturer -match '(?i)hewlett[ -]?packard|hewlett packard enterprise|\bhpe\b|^hp$') { return 'HPE' }
    throw "Unsupported or unknown hardware manufacturer: '$manufacturer'. This installer supports only physical HPE and Dell servers."
}

function Resolve-SupportedServerRelease {
    param($OperatingSystem)

    $productType = [int]$OperatingSystem.ProductType
    $build = [int]$OperatingSystem.BuildNumber
    if ($productType -notin @(2, 3)) {
        throw "Windows Server is required. Detected: $($OperatingSystem.Caption)"
    }

    switch ($build) {
        14393 { return '2016' }
        17763 { return '2019' }
        20348 { return '2022' }
        26100 { return '2025' }
        default {
            throw "Unsupported Windows Server build $build ($($OperatingSystem.Caption)). Supported releases are Windows Server 2016, 2019, 2022, and 2025."
        }
    }
}

# Remove scheduled task
function Remove-ScheduledTaskIfPresent {
    param([string]$Name)
    if (-not (Test-ScheduledTaskExists -Name $Name)) { return }

    try {
        Stop-ScheduledTask -TaskName $Name -ErrorAction SilentlyContinue
        Unregister-ScheduledTask -TaskName $Name -Confirm:$false -ErrorAction Stop
        Write-Host "[INFO] Removed existing scheduled task: $Name"
    }
    catch {
        throw "Failed to delete scheduled task '$Name': $($_.Exception.Message)"
    }
}

function ConvertTo-ArgumentString {
    param([string[]]$Arguments)
    $parts = foreach ($argument in $Arguments) {
        if ($null -eq $argument -or $argument.Length -eq 0) { '""' }
        elseif ($argument -match '[\s"]') { '"{0}"' -f ($argument -replace '"', '\"') }
        else { $argument }
    }
    return ($parts -join ' ')
}

function Invoke-MsiInstall {
    param(
        [string]$MsiPath,
        [string]$LogPath,
        [string]$DisplayName
    )

    if (-not (Test-Path -LiteralPath $MsiPath -PathType Leaf)) {
        throw "$DisplayName MSI not found: $MsiPath"
    }

    $arguments = @('/i', $MsiPath, '/qn', '/norestart', '/L*v', $LogPath)
    Write-Host ('[INFO] Installing {0} silently.' -f $DisplayName)
    $process = Start-Process -FilePath 'msiexec.exe' -ArgumentList (ConvertTo-ArgumentString $arguments) -Wait -PassThru
    if ($process.ExitCode -notin @(0, 1641, 3010)) {
        throw "$DisplayName installation failed, exit code: $($process.ExitCode). MSI log: $LogPath"
    }
    if ($process.ExitCode -in @(1641, 3010)) {
        Write-Warning "$DisplayName installation succeeded but requested a reboot. Exit code: $($process.ExitCode)"
    }
}

function Install-HpeIloRest {
    $installer = Get-HpeInstaller
    Write-InstallerIdentity -Path $installer
    $msiLog = Join-Path $env:TEMP ('ConvergenceSecurity_HPE_iLOREST_{0}.log' -f (Get-Date -Format 'yyyyMMdd_HHmmss'))
    Invoke-MsiInstall -MsiPath $installer -LogPath $msiLog -DisplayName 'HPE iLOREST'
}

function Extract-DellMsiFromPackage {
    param([string]$InstallerPath, [string]$DestinationMsiPath)

    $archive = $null
    $entryStream = $null
    $outputStream = $null
    try {
        Add-Type -AssemblyName System.IO.Compression.FileSystem
        $archive = [System.IO.Compression.ZipFile]::OpenRead($InstallerPath)
        $entry = $archive.Entries |
            Where-Object { $_.FullName -match '(?i)(^|/)iDRACTools_x64\.msi$' } |
            Select-Object -First 1

        if ($null -eq $entry) {
            $entry = $archive.Entries |
                Where-Object { $_.Name -match '(?i)(idractools|racadm|drac).*\.msi$' } |
                Sort-Object Length -Descending |
                Select-Object -First 1
        }
        if ($null -eq $entry) {
            throw 'iDRACTools_x64.msi was not found inside the Dell package.'
        }

        $destinationDir = Split-Path -Parent $DestinationMsiPath
        New-Item -ItemType Directory -Path $destinationDir -Force | Out-Null
        $entryStream = $entry.Open()
        $outputStream = [System.IO.File]::Open($DestinationMsiPath, [System.IO.FileMode]::Create, [System.IO.FileAccess]::Write, [System.IO.FileShare]::None)
        $entryStream.CopyTo($outputStream)
        return $DestinationMsiPath
    }
    catch {
        throw "Automatic Dell MSI extraction failed: $($_.Exception.Message). Package: $InstallerPath"
    }
    finally {
        if ($null -ne $outputStream) { $outputStream.Dispose() }
        if ($null -ne $entryStream) { $entryStream.Dispose() }
        if ($null -ne $archive) { $archive.Dispose() }
    }
}

function Install-DellRacadm {
    param([string]$ServerRelease)

    $installer = Get-DellInstaller -ServerRelease $ServerRelease
    Write-InstallerIdentity -Path $installer
    $workDir = Join-Path (Join-Path $env:SystemRoot 'Temp') ('CS_Dell_{0}' -f [guid]::NewGuid().ToString('N'))
    $msiPath = $null

    try {
        if ([System.IO.Path]::GetExtension($installer) -ieq '.msi') {
            $msiPath = $installer
        }
        else {
            $msiPath = Extract-DellMsiFromPackage -InstallerPath $installer -DestinationMsiPath (Join-Path $workDir 'iDRACTools_x64.msi')
        }

        $msiLog = Join-Path $env:TEMP ('ConvergenceSecurity_Dell_iDRACTools_{0}.log' -f (Get-Date -Format 'yyyyMMdd_HHmmss'))
        Invoke-MsiInstall -MsiPath $msiPath -LogPath $msiLog -DisplayName 'Dell iDRAC Tools/RACADM'
    }
    finally {
        if (Test-Path -LiteralPath $workDir -PathType Container) {
            Remove-Item -LiteralPath $workDir -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}

function Invoke-ProcessWithTimeout {
    param([string]$FilePath, [string[]]$Arguments, [int]$TimeoutSeconds = 120)
    $probeDir = Join-Path $env:TEMP ('ConvergenceSecurityProbe_{0}' -f [guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $probeDir -Force | Out-Null
    $stdout = Join-Path $probeDir 'stdout.txt'
    $stderr = Join-Path $probeDir 'stderr.txt'
    try {
        $process = Start-Process -FilePath $FilePath -ArgumentList (ConvertTo-ArgumentString $Arguments) -WindowStyle Hidden -PassThru -RedirectStandardOutput $stdout -RedirectStandardError $stderr
        if (-not $process.WaitForExit($TimeoutSeconds * 1000)) {
            Stop-Process -Id $process.Id -Force -ErrorAction SilentlyContinue
            return [pscustomobject]@{ ExitCode = 124; StdOut = ''; StdErr = "timeout after ${TimeoutSeconds}s" }
        }

        # Complete redirected stdout/stderr processing before reading ExitCode/output.
        $process.WaitForExit()
        $exitCode = $process.ExitCode

        $outText = ''
        if (Test-Path -LiteralPath $stdout) {
            $value = Get-Content -LiteralPath $stdout -Raw -ErrorAction SilentlyContinue
            if ($null -ne $value) { $outText = [string]$value }
        }

        $errText = ''
        if (Test-Path -LiteralPath $stderr) {
            $value = Get-Content -LiteralPath $stderr -Raw -ErrorAction SilentlyContinue
            if ($null -ne $value) { $errText = [string]$value }
        }

        return [pscustomobject]@{ ExitCode = $exitCode; StdOut = $outText; StdErr = $errText }
    }
    finally {
        Remove-Item -LiteralPath $probeDir -Recurse -Force -ErrorAction SilentlyContinue
    }
}

function Resolve-HpeServerGeneration {
    param([string]$Model)

    if ([string]::IsNullOrWhiteSpace($Model)) {
        throw 'HPE server model could not be determined.'
    }

    if ($Model -match '(?i)Gen\s*10\s*(Plus|\+)') { return 'Gen10Plus' }
    if ($Model -match '(?i)Gen\s*10') { return 'Gen10' }
    if ($Model -match '(?i)Gen\s*9') { return 'Gen9' }

    throw "Unsupported HPE server generation for automatic CHIF installation: $Model"
}

function Get-HpeChifInstaller {
    param(
        [string]$ServerRelease,
        [string]$Model
    )

    $generation = Resolve-HpeServerGeneration -Model $Model
    $fileName = $null
    $driverVersion = $null

    # Approved HPE CHIF package matrix.
    # Gen9 + WS2016/2019      : iLO 4 CHIF 4.1.0.0    (cp039985.exe)
    # Gen10/Gen10 Plus + 2022 : iLO 5 CHIF 4.7.1.0(I) (cp069722.exe)
    # Gen10/Gen10 Plus + 2025 : iLO 5 CHIF 4.7.2.0(D) (cp069724.exe)
    switch -Wildcard ("$generation|$ServerRelease") {
        'Gen9|2016'       { $fileName = 'cp039985.exe'; $driverVersion = '4.1.0.0' }
        'Gen9|2019'       { $fileName = 'cp039985.exe'; $driverVersion = '4.1.0.0' }
        'Gen10*|2022'     { $fileName = 'cp069722.exe'; $driverVersion = '4.7.1.0(I)' }
        'Gen10*|2025'     { $fileName = 'cp069724.exe'; $driverVersion = '4.7.2.0(D)' }
        default {
            throw "No approved HPE CHIF package mapping is configured for $generation on Windows Server $ServerRelease. Model: $Model"
        }
    }

    $toolDir = Join-Path $PackageDir 'Tools\HPE'
    if (-not (Test-Path -LiteralPath $toolDir -PathType Container)) {
        throw "HPE tool directory not found: $toolDir"
    }

    # Search recursively so the package may be placed directly under Tools\HPE
    # or under a CHIF subdirectory without changing this script.
    $installer = Get-ChildItem -LiteralPath $toolDir -Filter $fileName -File -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($null -eq $installer) {
        throw "Required HPE CHIF installer was not found: $fileName (driver $driverVersion, $generation, Windows Server $ServerRelease). Place the file anywhere under $toolDir"
    }

    return [pscustomobject]@{
        Path = $installer.FullName
        FileName = $installer.Name
        DriverVersion = $driverVersion
        Generation = $generation
        ServerRelease = $ServerRelease
    }
}

function Test-HpeLocalAccess {
    param(
        [string]$ToolPath,
        [int]$TimeoutSeconds = 120
    )

    $result = Invoke-ProcessWithTimeout -FilePath $ToolPath -Arguments @('serverlogs', '--selectlog=IEL') -TimeoutSeconds $TimeoutSeconds

    $stdoutText = ([string]$result.StdOut).Trim()
    $stderrText = ([string]$result.StdErr).Trim()
    $combined = ("{0}`n{1}" -f $stdoutText, $stderrText).Trim()

    $chifMissing = ($combined -match '(?i)Chif driver not found|iLO channel interface driver.*not.*installed')

    # Valid IEL response from local iLO.
    $validIelOutput = (
        $stdoutText -match '(?m)^Name=iLO Event Log\s*$' -or
        $stdoutText -match '(?m)^OemRecordFormat=Hpe-iLOEventLog\s*$' -or
        $stdoutText -match '(?m)^@odata\.id=/redfish/v1/Managers/.*/LogServices/IEL/'
    )

    # ExitCode can be $null with the current process wrapper.
    # A valid IEL response proves that CHIF/local iLO communication succeeded.
    $success = (-not $chifMissing -and $validIelOutput)

    return [pscustomobject]@{
        Success     = $success
        ChifMissing = $chifMissing
        ExitCode    = $result.ExitCode
        StdOut      = $stdoutText
        StdErr      = $stderrText
        Output      = $combined
    }
}

function Install-HpeChif {
    param(
        [string]$ServerRelease,
        $ComputerSystem
    )

    $package = Get-HpeChifInstaller -ServerRelease $ServerRelease -Model ([string]$ComputerSystem.Model)
    Write-Host ('[INFO] Selected HPE CHIF driver {0} for {1} / Windows Server {2}: {3}' -f $package.DriverVersion, $package.Generation, $ServerRelease, $package.FileName)
    Write-InstallerIdentity -Path $package.Path
    Write-Host '[INFO] Installing the HPE CHIF Smart Component silently. This script does not issue any reboot command.'

    $process = Start-Process -FilePath $package.Path -ArgumentList '/s' -Wait -PassThru
    $exitCode = $process.ExitCode

    # HPE Smart Component return-code conventions vary by component generation.
    # Treat 0-3 as nonfatal here and make the post-install iLOREST local probe
    # the authoritative success check. Any other code is considered a failure.
    if ($exitCode -notin @(0, 1, 2, 3)) {
        throw "HPE CHIF Smart Component installation failed, exit code: $exitCode. Installer: $($package.Path)"
    }

    if ($exitCode -in @(1, 2)) {
        Write-Warning "HPE CHIF Smart Component returned exit code $exitCode. A reboot may be required; local iLO access will be tested before deciding whether installation can continue."
    }
    elseif ($exitCode -eq 3) {
        Write-Host '[INFO] HPE CHIF Smart Component reported that installation was not required/current/not applicable. Local iLO access will be verified.'
    }
    else {
        Write-Host '[OK] HPE CHIF Smart Component process completed.'
    }

    return [pscustomobject]@{
        ExitCode = $exitCode
        Package = $package
    }
}

function Ensure-HpeLocalAccess {
    param(
        [string]$ToolPath,
        [string]$ServerRelease,
        $ComputerSystem
    )

    $probe = Test-HpeLocalAccess -ToolPath $ToolPath -TimeoutSeconds 120
    if ($probe.Success) {
        Write-Host '[OK] HPE local iLO access is available. CHIF installation is not required.'
        return
    }

    if (-not $probe.ChifMissing) {
        throw ("HPE local iLO probe failed before CHIF installation. exit={0}; stderr={1}; stdout={2}" -f $probe.ExitCode, $probe.StdErr, $probe.StdOut)
    }

    Write-Warning 'HPE iLO Channel Interface (CHIF) driver is not available. Attempting an automatic CHIF installation.'
    $installResult = Install-HpeChif -ServerRelease $ServerRelease -ComputerSystem $ComputerSystem

    # Driver activation can take a short time even when a reboot is not needed.
    for ($attempt = 1; $attempt -le 5; $attempt++) {
        if ($attempt -gt 1) { Start-Sleep -Seconds 3 }
        $probe = Test-HpeLocalAccess -ToolPath $ToolPath -TimeoutSeconds 120
        if ($probe.Success) {
            Write-Host '[OK] HPE CHIF is active and local iLO access succeeded without a reboot.'
            return
        }
        if ($attempt -lt 5) {
            Write-Host ('[WAIT] HPE local iLO access is not ready after CHIF installation. retry={0}/5' -f $attempt)
        }
    }

    if ($probe.ChifMissing) {
        throw ("HPE CHIF was installed but is not active yet. Automatic reboot was not performed. Perform a planned Windows reboot and run Install-ConvergenceSecurity.ps1 again. If 'Chif driver not found' persists after reboot, verify the CHIF package/OS/server-generation compatibility. Smart Component exit={0}" -f $installResult.ExitCode)
    }

    throw ("HPE local iLO probe failed after CHIF installation. exit={0}; stderr={1}" -f $probe.ExitCode, (Get-ShortText -Text $probe.StdErr))
}

function Test-VendorTool {
    param([string]$ResolvedVendor, [string]$ToolPath)

    if ($ResolvedVendor -eq 'HPE') {
        $output = & $ToolPath -V 2>&1
        $exitCode = $LASTEXITCODE
        $combined = ($output | Out-String).Trim()

        if ($exitCode -ne 0) {
            throw ("iLOREST version probe failed. exit={0}, output={1}" -f $exitCode, $combined)
        }

        if ([string]::IsNullOrWhiteSpace($combined)) {
            throw 'iLOREST version probe failed because ilorest -V returned no output.'
        }

        $versionMatch = [regex]::Match($combined, '(?<!\d)(\d+\.\d+\.\d+\.\d+)(?!\d)')

        if (-not $versionMatch.Success) {
            throw "iLOREST -V succeeded but a four-part version could not be parsed: $combined"
        }

        $detectedVersion = [version]$versionMatch.Groups[1].Value

        if ($detectedVersion -lt [version]'7.3.0.0' -or
            $detectedVersion -ge [version]'7.4.0.0') {
            throw "Unsupported iLOREST version $detectedVersion. The approved version family is 7.3.x."
        }

        Write-Host "[OK] iLOREST probe succeeded: $combined"
        return
    }

    $lastResult = $null
    for ($attempt = 1; $attempt -le 5; $attempt++) {
        $lastResult = Invoke-ProcessWithTimeout -FilePath $ToolPath -Arguments @('lclog', 'view', '-n', '1') -TimeoutSeconds 120
        if ($lastResult.ExitCode -eq 0) {
            if ([string]::IsNullOrWhiteSpace($lastResult.StdOut)) {
                Write-Warning 'RACADM local probe succeeded but the Lifecycle Log is currently empty.'
            }
            else {
                Write-Host '[OK] RACADM local Lifecycle Log probe succeeded.'
            }
            return
        }
        if ($attempt -lt 5) {
            Write-Host ("[WAIT] RACADM local probe is not ready. retry={0}/5" -f $attempt)
            Start-Sleep -Seconds 3
        }
    }
    throw ("RACADM local probe failed. exit={0}, stderr={1}, stdout={2}" -f $lastResult.ExitCode, ([string]$lastResult.StdErr).Trim(), ([string]$lastResult.StdOut).Trim())
}

$existingEvidence = @(Get-ExistingInstallationEvidence)
if ($existingEvidence.Count -gt 0) {
    $script:ResolvedVendor = Get-ExistingVendor
    $reason = $existingEvidence -join '; '
    for ($step = 1; $step -le 5; $step++) {
        Skip-Step -Number $step -Message "Existing installation detected; no changes were made"
    }
    Write-FinalSummary -Outcome 'SKIPPED' -Message $reason
    exit 0
}

$success = $false
$failure = ''

try {
    Write-Step 1 'Validate Windows Server/hardware and prepare the vendor tool'

    if (-not [Environment]::Is64BitOperatingSystem) { throw 'A 64-bit Windows Server OS is required.' }
    if ($PSVersionTable.PSVersion -lt [version]'5.1') { throw "Windows PowerShell 5.1 or later is required. Current: $($PSVersionTable.PSVersion)" }

    $os = Get-WmiObject -Class Win32_OperatingSystem
    $computer = Get-WmiObject -Class Win32_ComputerSystem
    $script:ServerRelease = Resolve-SupportedServerRelease -OperatingSystem $os
    $script:ResolvedVendor = Resolve-HardwareVendor -ComputerSystem $computer

    if (Test-IsVirtualMachine -ComputerSystem $computer) {
        throw "A virtual machine is not supported for local BMC monitoring: $($computer.Manufacturer) $($computer.Model)"
    }

    Write-Host ("[OK] OS: {0}, build {1}, release {2}" -f $os.Caption, $os.BuildNumber, $script:ServerRelease)
    Write-Host ("[OK] Hardware vendor: {0}, model: {1}" -f $script:ResolvedVendor, $computer.Model)

    if ($script:ResolvedVendor -eq 'HPE') {
        $toolPath = Resolve-IloRestExecutable
        if (-not $toolPath) {
            Install-HpeIloRest
            $toolPath = Resolve-IloRestExecutable
        }
        if (-not $toolPath) { throw 'Windows HPE iLOREST (ilorest.exe) could not be found after installation.' }
    }
    else {
        $toolPath = Resolve-RacadmExecutable
        if (-not $toolPath) {
            Install-DellRacadm -ServerRelease $script:ServerRelease
            $toolPath = Resolve-RacadmExecutable
        }
        if (-not $toolPath) { throw 'Windows Dell RACADM (racadm.exe) could not be found after installation.' }
    }

    Test-VendorTool -ResolvedVendor $script:ResolvedVendor -ToolPath $toolPath

    if ($script:ResolvedVendor -eq 'HPE') {
        Ensure-HpeLocalAccess -ToolPath $toolPath -ServerRelease $script:ServerRelease -ComputerSystem $computer
    }

    Complete-Step 1 ("Validated {0} and vendor tool/local BMC access: {1}" -f $script:ResolvedVendor, $toolPath)

    Write-Step 2 'Deploy common scripts and new-install configuration'
    foreach ($dir in @(
        $InstallDir,
        $DataDir,
        (Join-Path $DataDir 'Logs'),
        (Join-Path $DataDir 'State'),
        (Join-Path $DataDir 'Temp'),
        (Join-Path $DataDir 'Backups')
    )) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
    }

    $inProgress = [ordered]@{
        PackageVersion = $PackageVersion
        StartedUtc = (Get-Date).ToUniversalTime().ToString('o')
        ProcessId = $PID
    }
    $inProgress | ConvertTo-Json -Depth 2 | Set-Content -LiteralPath $InstallInProgressPath -Encoding UTF8

    $monitorSource = Join-Path $PackageDir 'Monitor-ConvergenceSecurityBmc.ps1'
    $adapterSource = Join-Path $PackageDir 'Disable-IdlePhysicalAdapters.ps1'
    if (-not (Test-Path -LiteralPath $monitorSource -PathType Leaf)) { throw "Monitor script not found: $monitorSource" }
    if (-not (Test-Path -LiteralPath $adapterSource -PathType Leaf)) { throw "Idle-adapter script not found: $adapterSource" }

    $monitorTarget = Join-Path $InstallDir 'Monitor-ConvergenceSecurityBmc.ps1'
    $adapterTarget = Join-Path $InstallDir 'Disable-IdlePhysicalAdapters.ps1'
    Copy-Item -LiteralPath $monitorSource -Destination $monitorTarget -Force
    Copy-Item -LiteralPath $adapterSource -Destination $adapterTarget -Force

    if (Test-Path -LiteralPath $StatePath -PathType Leaf) {
        $archiveState = '{0}.preinstall-{1}' -f $StatePath, (Get-Date -Format 'yyyyMMdd_HHmmss')
        Move-Item -LiteralPath $StatePath -Destination $archiveState -Force
        Write-Warning "Pre-existing state was archived before first-install initialization: $archiveState"
    }

    $config = [ordered]@{
        SchemaVersion = 1
        PackageVersion = $PackageVersion
        Vendor = $script:ResolvedVendor
        ToolPath = $toolPath
        TimeoutSeconds = 120
        MaxConsecutiveFailures = 3
        ScheduledSecondPassDelaySeconds = 120
        LifecycleLogFetchLimit = 500
        EnableSelCheck = $true
        SelCleanupThreshold = 200
        EnableSelCleanup = $false
        EnableBmcLogCleanup = $true
        CleanupThreshold = 50
        BackupBeforeCleanup = $true
        BackupRetentionDays = 7
        MaxBackupFiles = 30
        MaxBackupTotalMB = 100
        MaxLogSizeMB = 10
        MaxLogBackups = 10
        LogRetentionDays = 30
        CompressLogBackups = $true
    }
    if ($script:ResolvedVendor -eq 'HPE') { $config['IloRestPath'] = $toolPath }
    else { $config['RacadmPath'] = $toolPath }

    $config | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $ConfigPath -Encoding UTF8

    if (-not [System.Diagnostics.EventLog]::SourceExists($EventSource)) {
        New-EventLog -LogName Application -Source $EventSource
    }
    Complete-Step 2 ("Deployed scripts and config under $InstallDir and $DataDir")

    Write-Step 3 'Initialize BMC baseline and apply the idle physical NIC policy'
    $monitorArgs = @('-NoProfile', '-NonInteractive', '-ExecutionPolicy', 'Bypass', '-File', $monitorTarget, '-Initialize')
    & $PowerShellExe @monitorArgs
    if ($LASTEXITCODE -ne 0) { throw "BMC baseline initialization failed, exit code: $LASTEXITCODE" }

    Write-Host '[INFO] Disabling physical NICs that are disconnected and have no usable IPv4 address/route.'
    $adapterArgs = @('-NoProfile', '-NonInteractive', '-ExecutionPolicy', 'Bypass', '-File', $adapterTarget, '-Apply')
    & $PowerShellExe @adapterArgs
    if ($LASTEXITCODE -ne 0) { throw "Idle physical adapter handling failed, exit code: $LASTEXITCODE" }
    Complete-Step 3 'Initialized the BMC baseline and applied the idle-NIC policy'

    Write-Step 4 'Verify log/state output'
    $logPath = Join-Path $DataDir 'Logs\bmc_monitor.log'
    if (-not (Test-Path -LiteralPath $logPath -PathType Leaf)) { throw "Monitor log was not created: $logPath" }
    if (-not (Test-Path -LiteralPath $StatePath -PathType Leaf)) { throw "Monitor state was not created: $StatePath" }
    $state = Get-Content -LiteralPath $StatePath -Raw | ConvertFrom-Json
    if ([string]$state.Vendor -ne $script:ResolvedVendor) {
        throw "State vendor mismatch: expected=$($script:ResolvedVendor), actual=$($state.Vendor)"
    }
    Complete-Step 4 ("Verified log and state: $logPath")

    Write-Step 5 'Replace legacy scheduling and register the common SYSTEM task'
    foreach ($legacyTask in $LegacyTaskNames) { Remove-ScheduledTaskIfPresent -Name $legacyTask }
    Remove-ScheduledTaskIfPresent -Name $TaskName

    ### v2.2.4
    $taskArguments = @('-NoProfile', '-NonInteractive', '-ExecutionPolicy Bypass', ('-File "{0}"' -f $monitorTarget), '-Scheduled') -join ' '
    $action = New-ScheduledTaskAction -Execute $PowerShellExe -Argument $taskArguments
    $trigger = New-ScheduledTaskTrigger -Once -At (Get-Date).AddMinutes(1) -RepetitionInterval (New-TimeSpan -Minutes 2)
    $principal = New-ScheduledTaskPrincipal -UserId 'SYSTEM' -LogonType ServiceAccount -RunLevel Highest
    $settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable -MultipleInstances IgnoreNew
    Register-ScheduledTask -TaskName $TaskName -Action $action -Trigger $trigger -Principal $principal -Settings $settings -Force | Out-Null
    ##########

    if (-not (Test-ScheduledTaskExists -Name $TaskName)) { throw 'The newly registered scheduled task could not be queried.' }

    $marker = [ordered]@{
        PackageVersion = $PackageVersion
        InstalledUtc = (Get-Date).ToUniversalTime().ToString('o')
        Vendor = $script:ResolvedVendor
        WindowsServerRelease = $script:ServerRelease
        ToolPath = $toolPath
        ScheduledTask = $TaskName
    }
    $marker | ConvertTo-Json -Depth 3 | Set-Content -LiteralPath $InstallMarkerPath -Encoding UTF8
    Remove-Item -LiteralPath $InstallInProgressPath -Force -ErrorAction SilentlyContinue

    Complete-Step 5 ("Registered $TaskName; each run performs two passes separated by $($config.ScheduledSecondPassDelaySeconds) seconds")
    $success = $true
}
catch {
    $failure = $_.Exception.Message
    if ($CurrentStep -ge 1 -and $CurrentStep -le 5 -and $StepStatus[$CurrentStep - 1] -eq 'PENDING') {
        $StepStatus[$CurrentStep - 1] = 'FAILED'
        $StepMessage[$CurrentStep - 1] = $failure
    }
    Write-Error -Message $failure -ErrorAction Continue
}
finally {
    if ($success) { Write-FinalSummary -Outcome 'INSTALLED' }
    else { Write-FinalSummary -Outcome 'FAILED' -Message $failure }
}

if (-not $success) { exit 1 }
exit 0
