[CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'High')]
param(
    [Parameter(Mandatory = $true)]
    [string]$BitstreamPath,
    [ValidateSet('sram', 'flash')]
    [string]$Destination = 'sram',
    [switch]$ConfirmFlash,
    [string]$OpenFPGALoader,
    [switch]$AllowUnverifiedArtifact
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if (-not (Test-Path -LiteralPath $BitstreamPath -PathType Leaf)) {
    throw "Bitstream is missing: $BitstreamPath"
}
$bitstreamPath = (Resolve-Path -LiteralPath $BitstreamPath).Path
if ([System.IO.Path]::GetExtension($bitstreamPath) -ne '.fs') {
    throw "Tang Nano 9K programming expects a packed .fs bitstream, got: $bitstreamPath"
}

if ($Destination -eq 'flash' -and -not $ConfirmFlash) {
    throw 'Flash programming overwrites persistent FPGA configuration. Re-run with -Destination flash -ConfirmFlash only after verifying the board and artifact.'
}

function Resolve-Programmer {
    param([string]$RequestedPath)

    if (-not [string]::IsNullOrWhiteSpace($RequestedPath)) {
        if (-not (Test-Path -LiteralPath $RequestedPath -PathType Leaf)) {
            throw "openFPGALoader was requested at a missing path: $RequestedPath"
        }
        return (Resolve-Path -LiteralPath $RequestedPath).Path
    }
    $command = Get-Command openFPGALoader -ErrorAction SilentlyContinue
    if ($null -eq $command) {
        throw 'openFPGALoader was not found. Install a version with board=tangnano9k support or pass -OpenFPGALoader <path>.'
    }
    return $command.Source
}

$actualHash = (Get-FileHash -LiteralPath $bitstreamPath -Algorithm SHA256).Hash.ToLowerInvariant()
$artifactStem = [System.IO.Path]::GetFileNameWithoutExtension($bitstreamPath)
$manifestPath = Join-Path (Split-Path -Parent $bitstreamPath) ($artifactStem + '_manifest.json')
if (-not $AllowUnverifiedArtifact) {
    if (-not (Test-Path -LiteralPath $manifestPath -PathType Leaf)) {
        throw "Refusing an artifact without its build manifest: $manifestPath. Use -AllowUnverifiedArtifact only for an artifact you independently verified."
    }
    $manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
    if ($manifest.device -ne 'GW1NR-LV9QN88PC6/I5' -or $manifest.family -ne 'GW1N-9C') {
        throw 'The artifact manifest does not identify the Tang Nano 9K GW1NR-LV9QN88PC6/I5 target.'
    }
    if ([string]::IsNullOrWhiteSpace($manifest.bitstream_sha256) -or
        $actualHash -ne $manifest.bitstream_sha256.ToLowerInvariant()) {
        throw "Bitstream SHA-256 does not match its manifest. Actual: $actualHash"
    }
}

$programmerArguments = @('-b', 'tangnano9k')
if ($Destination -eq 'flash') {
    $programmerArguments += '-f'
}
$programmerArguments += $bitstreamPath

Write-Output "Artifact: $bitstreamPath"
Write-Output "SHA256: $actualHash"
Write-Output "Target: Tang Nano 9K GW1NR-LV9QN88PC6/I5, destination: $Destination"
if ($Destination -eq 'sram') {
    Write-Output 'SRAM mode is volatile: power cycling or reset removes the loaded configuration.'
} else {
    Write-Warning 'FLASH mode changes persistent configuration flash. Keep USB power stable and do not disconnect during programming.'
}

$action = "program $bitstreamPath"
if ($PSCmdlet.ShouldProcess("Tang Nano 9K ($Destination)", $action)) {
    $programmerPath = Resolve-Programmer $OpenFPGALoader
    $programmerOutput = @(& $programmerPath @programmerArguments 2>&1)
    $programmerExitCode = $LASTEXITCODE
    $programmerOutput | ForEach-Object { Write-Output $_ }
    if ($programmerExitCode -ne 0) {
        throw "openFPGALoader failed with exit code $programmerExitCode."
    }
    # Some openFPGALoader/Gowin/FTDI paths return zero after printing a CRC
    # failure, a standalone FAIL, or an MPSSE USB transport failure. Treat the
    # programmer's text result as authoritative too; strip terminal
    # colour/control sequences before matching it.
    $programmerText = ($programmerOutput | ForEach-Object { $_.ToString() }) -join "`n"
    $plainProgrammerText = [regex]::Replace(
        $programmerText,
        [char]27 + '\[[0-?]*[ -/]*[@-~]',
        ''
    )
    $programmerFailurePattern = @(
        'CRC\s+check\s*:\s*fail(?:ed)?\b',
        '^\s*FAIL(?:ED)?\s*$',
        'mpsse_(?:write|read|store):[^\r\n]*\bfail',
        'usb\s+bulk\s+(?:read|write)\s+failed',
        'Loopback\s+failed',
        'unable\s+to\s+config\s+pins'
    ) -join '|'
    if ($plainProgrammerText -match ('(?im)' + $programmerFailurePattern)) {
        throw 'openFPGALoader reported a programming/USB transport failure despite returning exit code 0.'
    }
    Write-Output 'openFPGALoader completed. This confirms the host-side command result only; run the documented board-level functional checks before calling the MCU validated.'
} else {
    Write-Output ('Dry run command: openFPGALoader ' + ($programmerArguments -join ' '))
}
