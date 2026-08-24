[CmdletBinding()]
param(
    [string]$ProjectPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$projectRoot = Split-Path -Parent $PSScriptRoot
if ([string]::IsNullOrWhiteSpace($ProjectPath)) {
    $ProjectPath = Join-Path $projectRoot 'rtl\platform\tangnano9k\project\omcu_tn9k_bringup.gprj'
}
if (-not (Test-Path -LiteralPath $ProjectPath -PathType Leaf)) {
    throw "Tang Nano 9K project file is missing: $ProjectPath"
}

[xml]$projectXml = Get-Content -LiteralPath $ProjectPath -Raw
$expectedDevice = 'GW1NR-LV9QN88PC6/I5'
if ($projectXml.Project.Device.pn -ne $expectedDevice) {
    throw "Expected Tang Nano 9K device '$expectedDevice', got '$($projectXml.Project.Device.pn)'."
}

$projectDirectory = Split-Path -Parent (Resolve-Path -LiteralPath $ProjectPath)
$projectFileSet = [System.Collections.Generic.HashSet[string]]::new(
    [System.StringComparer]::OrdinalIgnoreCase
)
$projectSourceList = [System.Collections.Generic.List[string]]::new()
foreach ($entry in @($projectXml.Project.FileList.File)) {
    if ($entry.enable -eq '0') {
        continue
    }
    $candidate = [System.IO.Path]::GetFullPath((Join-Path $projectDirectory $entry.path))
    if (-not (Test-Path -LiteralPath $candidate -PathType Leaf)) {
        throw "Tang Nano 9K project references a missing file: $($entry.path)"
    }
    [void]$projectFileSet.Add($candidate)
    if ($entry.path -match '\.(sv|v)$') {
        [void]$projectSourceList.Add($candidate)
    }
}

$fileListPath = Join-Path $projectRoot 'rtl\files.f'
if (-not (Test-Path -LiteralPath $fileListPath -PathType Leaf)) {
    throw "Canonical RTL file list is missing: $fileListPath"
}

$requiredSources = @(
    Get-Content -LiteralPath $fileListPath |
        Where-Object { -not [string]::IsNullOrWhiteSpace($_) -and -not $_.TrimStart().StartsWith('#') } |
        ForEach-Object { [System.IO.Path]::GetFullPath((Join-Path $projectRoot $_.Trim())) }
)
$requiredSources += [System.IO.Path]::GetFullPath(
    (Join-Path $projectRoot 'rtl\platform\tangnano9k\omcu_tn9k_bringup_top.sv')
)

$missingSources = @($requiredSources | Where-Object { -not $projectFileSet.Contains($_) })
if ($missingSources.Count -ne 0) {
    $relativeMissing = $missingSources | ForEach-Object { $_.Substring($projectRoot.Length + 1) }
    throw "Tang Nano 9K project omits canonical RTL source(s): $($relativeMissing -join ', ')"
}

if ($projectSourceList.Count -ne $requiredSources.Count) {
    throw "Tang Nano 9K project source count ($($projectSourceList.Count)) does not match canonical RTL count ($($requiredSources.Count))."
}
for ($index = 0; $index -lt $requiredSources.Count; $index++) {
    if ($projectSourceList[$index] -ne $requiredSources[$index]) {
        $expected = $requiredSources[$index].Substring($projectRoot.Length + 1)
        $actual = $projectSourceList[$index].Substring($projectRoot.Length + 1)
        throw "Tang Nano 9K project source order differs at index ${index}: expected '$expected', got '$actual'."
    }
}

$constraints = @($projectXml.Project.FileList.File | Where-Object {
    $_.path -match '\.(cst|sdc)$' -and $_.enable -ne '0'
})
if ($constraints.Count -ne 2) {
    throw 'Tang Nano 9K project must include exactly one CST and one SDC constraint file.'
}
if (-not ($constraints.path -match '\.cst$') -or -not ($constraints.path -match '\.sdc$')) {
    throw 'Tang Nano 9K project must include both CST pin and SDC clock constraints.'
}

Write-Output "PASS: Tang Nano 9K project covers $($requiredSources.Count) canonical RTL sources in build order for $expectedDevice"
