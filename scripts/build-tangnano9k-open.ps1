[CmdletBinding()]
param(
    [string]$ToolBin,
    [string]$BuildDirectory,
    [string]$RomInitFile,
    # Zero selects the reviewed default for the selected build mode below.
    # The product image uses the verified 4 KiB bootloader geometry; generic
    # FPGA bring-up keeps its historic 8 KiB default.
    [ValidateRange(0, 8)]
    [int]$RomKiB = 0,
    [ValidateRange(1, 44)]
    [int]$SramKiB = 44,
    [switch]$McuMode,
    [switch]$SkipPack,
    # The product profile deliberately uses the full GW1N-9C LUT fabric.
    # nextpnr's generic 0.90 local-density target rejects an otherwise legal
    # high-density placement before it has tried enough legal sites. Keep the
    # chosen value explicit, reproducible and recorded in the manifest.
    [ValidateRange(0.50, 1.00)]
    [double]$PlacerHeapBeta = 0.99,
    [int]$Seed = 1
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$projectRoot = Split-Path -Parent $PSScriptRoot
$projectRoot = (Resolve-Path -LiteralPath $projectRoot).Path
if ([string]::IsNullOrWhiteSpace($BuildDirectory)) {
    $BuildDirectory = Join-Path $projectRoot 'build\tangnano9k-open'
}
if ([string]::IsNullOrWhiteSpace($RomInitFile)) {
    $RomInitFile = if ($McuMode) {
        Join-Path $projectRoot 'build\sdk\omcu_bootloader.hex'
    } else {
        Join-Path $projectRoot 'rtl\platform\tangnano9k\firmware\gpio_bringup.hex'
    }
}
if ($RomKiB -eq 0) {
    $RomKiB = if ($McuMode) { 4 } else { 8 }
}
if ($McuMode -and ($RomKiB -ne 4 -or $SramKiB -ne 44)) {
    throw 'McuMode fixes the validated geometry at 4 KiB boot ROM plus 44 KiB SRAM (40 KiB application + 4 KiB loader scratch).'
}

function Resolve-OpenTool {
    param([string]$Name)

    $candidateNames = @($Name, "$Name.exe")
    if (-not [string]::IsNullOrWhiteSpace($ToolBin)) {
        foreach ($candidateName in $candidateNames) {
            $candidatePath = Join-Path $ToolBin $candidateName
            if (Test-Path -LiteralPath $candidatePath -PathType Leaf) {
                return $candidatePath
            }
        }
    }

    foreach ($candidateName in $candidateNames) {
        $command = Get-Command $candidateName -ErrorAction SilentlyContinue
        if ($null -ne $command) {
            return $command.Source
        }
    }
    throw "Missing $Name. Install yowasp-yosys and yowasp-nextpnr-himbaechel-gowin, then pass -ToolBin <their Scripts directory> or add it to PATH."
}

$yosys = Resolve-OpenTool 'yowasp-yosys'
$nextpnr = Resolve-OpenTool 'yowasp-nextpnr-himbaechel-gowin'
$gowinPack = if ($SkipPack) { $null } else { Resolve-OpenTool 'gowin_pack' }

if ($McuMode) {
    & (Join-Path $PSScriptRoot 'check-tangnano9k-project.ps1') -McuMode
} else {
    & (Join-Path $PSScriptRoot 'check-tangnano9k-project.ps1')
}

New-Item -ItemType Directory -Force -Path $BuildDirectory | Out-Null
$buildDirectory = (Resolve-Path -LiteralPath $BuildDirectory).Path
$projectRootPrefix = $projectRoot.TrimEnd(
    [System.IO.Path]::DirectorySeparatorChar,
    [System.IO.Path]::AltDirectorySeparatorChar
) + [System.IO.Path]::DirectorySeparatorChar
if (-not $buildDirectory.StartsWith($projectRootPrefix, [System.StringComparison]::OrdinalIgnoreCase)) {
    throw "BuildDirectory must be inside the repository because the YoWASP WebAssembly tools require project-relative paths: $buildDirectory"
}
if (-not (Test-Path -LiteralPath $RomInitFile -PathType Leaf)) {
    throw "ROM initialization file is missing: $RomInitFile"
}
$romWords = $RomKiB * 256
$sramBytes = $SramKiB * 1024
$romInitFile = (Resolve-Path -LiteralPath $RomInitFile).Path
if (-not $romInitFile.StartsWith($projectRootPrefix, [System.StringComparison]::OrdinalIgnoreCase)) {
    throw "RomInitFile must be inside the repository because the YoWASP WebAssembly tools require project-relative paths: $romInitFile"
}

$artifactStem = if ($McuMode) { 'omcu_tn9k_mcu' } else { 'omcu_tn9k_bringup' }
$topModule = if ($McuMode) { 'omcu_tn9k_mcu_top' } else { 'omcu_tn9k_bringup_top' }
$jsonPath = Join-Path $buildDirectory ($artifactStem + '.json')
$pnrPath = Join-Path $buildDirectory ($artifactStem + '_pnr.json')
$reportPath = Join-Path $buildDirectory ($artifactStem + '_report.json')
$bitstreamPath = Join-Path $buildDirectory ($artifactStem + '.fs')
$yosysLogPath = Join-Path $buildDirectory 'yosys.log'
$pnrLogPath = Join-Path $buildDirectory 'nextpnr.log'
$romImagePath = Join-Path $buildDirectory 'omcu_rom_image.hex'
$romConfigPath = Join-Path $buildDirectory 'omcu_rom_image_config.vh'
$cstPath = Join-Path $projectRoot 'rtl\platform\tangnano9k\project\omcu_tn9k_bringup.cst'
$sdcPath = Join-Path $projectRoot 'rtl\platform\tangnano9k\project\omcu_tn9k_bringup.sdc'

function Get-ProjectRelativePath {
    param([string]$Path)

    # Path.GetRelativePath exists on modern .NET, but the Windows PowerShell
    # shipped with many FPGA workstations still runs on .NET Framework where it
    # is absent. Keep the build flow usable there without changing its
    # project-relative YoWASP path contract.
    $getRelativePath = [System.IO.Path].GetMethod(
        'GetRelativePath', [type[]]@([string], [string])
    )
    if ($null -ne $getRelativePath) {
        return [System.IO.Path]::GetRelativePath($projectRoot, $Path).Replace('\', '/')
    }

    $basePath = $projectRoot.TrimEnd(
        [System.IO.Path]::DirectorySeparatorChar,
        [System.IO.Path]::AltDirectorySeparatorChar
    ) + [System.IO.Path]::DirectorySeparatorChar
    $baseUri = [System.Uri]::new($basePath)
    $targetUri = [System.Uri]::new($Path)
    return [System.Uri]::UnescapeDataString(
        $baseUri.MakeRelativeUri($targetUri).ToString()
    ).Replace('\', '/')
}

function New-PaddedRomImage {
    param(
        [string]$InputPath,
        [string]$OutputPath,
        [int]$WordCount
    )

    # GNU objcopy's Verilog image uses @<word-address> records. Materialize a
    # dense image with RISC-V NOP fill so synthesis has one deterministic ROM
    # initializer and no accidentally uninitialized executable holes.
    $words = New-Object 'System.String[]' $WordCount
    for ($index = 0; $index -lt $WordCount; $index += 1) {
        $words[$index] = '00000013'
    }
    $wordAddress = 0
    foreach ($rawLine in Get-Content -LiteralPath $InputPath) {
        $line = $rawLine.Trim()
        if ([string]::IsNullOrWhiteSpace($line) -or $line.StartsWith('#')) {
            continue
        }
        if ($line.StartsWith('@')) {
            $wordAddress = [Convert]::ToInt32($line.Substring(1), 16)
            continue
        }
        foreach ($token in ($line -split '\s+')) {
            if ($wordAddress -lt 0 -or $wordAddress -ge $WordCount) {
                throw "ROM image word address 0x$($wordAddress.ToString('X')) is outside the configured $WordCount-word ROM."
            }
            if ($token -notmatch '^[0-9A-Fa-f]{1,8}$') {
                throw "Unsupported Verilog ROM token '$token' in $InputPath."
            }
            $words[$wordAddress] = ('{0:X8}' -f [Convert]::ToUInt32($token, 16))
            $wordAddress += 1
        }
    }
    [System.IO.File]::WriteAllLines(
        $OutputPath,
        $words,
        [System.Text.UTF8Encoding]::new($false)
    )
}

$relativeJsonPath = Get-ProjectRelativePath $jsonPath
$relativePnrPath = Get-ProjectRelativePath $pnrPath
$relativeReportPath = Get-ProjectRelativePath $reportPath
$relativeBitstreamPath = Get-ProjectRelativePath $bitstreamPath
$relativeYosysLogPath = Get-ProjectRelativePath $yosysLogPath
$relativePnrLogPath = Get-ProjectRelativePath $pnrLogPath
$relativeRomConfigDir = Get-ProjectRelativePath (Split-Path -Parent $romConfigPath)
$relativeCstPath = Get-ProjectRelativePath $cstPath
$relativeSdcPath = Get-ProjectRelativePath $sdcPath
$relativeRomInitFile = Get-ProjectRelativePath $romInitFile
$relativeRomImageFile = Get-ProjectRelativePath $romImagePath
$placerHeapBetaText = $PlacerHeapBeta.ToString(
    [System.Globalization.CultureInfo]::InvariantCulture
)
New-PaddedRomImage -InputPath $romInitFile -OutputPath $romImagePath -WordCount $romWords
$romConfigText = @(
    ([char]96) + 'ifndef OMCU_ROM_IMAGE_CONFIG_INCLUDED'
    ([char]96) + 'define OMCU_ROM_IMAGE_CONFIG_INCLUDED'
    ([char]96) + 'define OMCU_ROM_IMAGE_FILE "' + $relativeRomImageFile + '"'
    ([char]96) + 'endif'
    ''
) -join [Environment]::NewLine
[System.IO.File]::WriteAllText(
    $romConfigPath,
    $romConfigText,
    [System.Text.UTF8Encoding]::new($false)
)

$sourceList = @(
    Get-Content -LiteralPath (Join-Path $projectRoot 'rtl\files.f') |
        Where-Object { -not [string]::IsNullOrWhiteSpace($_) -and -not $_.TrimStart().StartsWith('#') } |
        ForEach-Object { $_.Trim().Replace('\', '/') }
)
$bringupTopSource = 'rtl/platform/tangnano9k/omcu_tn9k_bringup_top.sv'
$tangTopSource = if ($McuMode) {
    'rtl/platform/tangnano9k/omcu_tn9k_mcu_top.sv'
} else {
    $bringupTopSource
}
$romAwareSources = @(
    'rtl/cpu/omcu_picorv32_system.sv'
)
if ($McuMode) {
    $romAwareSources += @($bringupTopSource, $tangTopSource)
    $sourceList += @($bringupTopSource, $tangTopSource)
} else {
    $romAwareSources += $tangTopSource
    $sourceList += $tangTopSource
}

function Quote-YosysPath {
    param([string]$Path)
    return '"' + $Path.Replace('"', '\"') + '"'
}

function Get-ExternalToolVersion {
    param([string]$ToolPath)

    # nextpnr prints its normal version banner on stderr.  With the script's
    # global ErrorActionPreference=Stop PowerShell turns that harmless native
    # stderr output into a terminating NativeCommandError after P&R/packing
    # have already succeeded.  Capture it deliberately, restore the caller's
    # policy immediately, then judge success solely by the native exit code.
    $savedErrorActionPreference = $ErrorActionPreference
    try {
        $ErrorActionPreference = 'Continue'
        $versionOutput = @(& $ToolPath --version 2>&1)
        $versionExitCode = $LASTEXITCODE
    } finally {
        $ErrorActionPreference = $savedErrorActionPreference
    }
    if ($versionExitCode -ne 0) {
        throw "Unable to query tool version for $ToolPath (exit code $versionExitCode)."
    }
    if ($versionOutput.Count -eq 0) {
        throw "Tool version query returned no output: $ToolPath"
    }
    return $versionOutput[$versionOutput.Count - 1].ToString().Trim()
}

function ConvertTo-CompatibleHashtable {
    param([object]$Value)

    if ($null -eq $Value) {
        return $null
    }
    if ($Value -is [System.Management.Automation.PSCustomObject]) {
        $result = @{}
        foreach ($property in $Value.PSObject.Properties) {
            $result[$property.Name] = ConvertTo-CompatibleHashtable -Value $property.Value
        }
        return $result
    }
    if (($Value -is [System.Collections.IEnumerable]) -and
        -not ($Value -is [string])) {
        $result = @()
        foreach ($item in $Value) {
            $result += ,(ConvertTo-CompatibleHashtable -Value $item)
        }
        return ,$result
    }
    return $Value
}

function Read-JsonHashtable {
    param([string]$Path)

    $jsonCommand = Get-Command -Name ConvertFrom-Json
    if ($jsonCommand.Parameters.ContainsKey('AsHashtable')) {
        return Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json -AsHashtable
    }
    return ConvertTo-CompatibleHashtable -Value (
        Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json
    )
}

function Get-BootRomInitEvidence {
    param(
        [string]$NetlistPath,
        [string]$ModuleName
    )

    # The JSON emitted by Yosys and nextpnr keeps the BSRAM INIT_RAM_xx
    # parameters.  Hashing the exact ordered set gives the release manifest a
    # machine-checkable proof that the placed netlist retained the synthesized
    # boot-ROM contents; a file hash alone only proves which input was requested.
    $netlist = Read-JsonHashtable -Path $NetlistPath
    if (-not $netlist['modules'].ContainsKey($ModuleName)) {
        throw "Missing module '$ModuleName' while checking boot-ROM initialization in $NetlistPath"
    }
    $cells = $netlist['modules'][$ModuleName]['cells']
    $romCellNames = @(
        $cells.Keys | Where-Object {
            $_ -like '*boot_rom.*' -and
            $cells[$_]['parameters'].ContainsKey('INIT_RAM_00')
        } | Sort-Object
    )
    if ($romCellNames.Count -eq 0) {
        throw "No initialized system.boot_rom BSRAM cells found in $NetlistPath"
    }

    $fingerprintLines = [System.Collections.Generic.List[string]]::new()
    foreach ($cellName in $romCellNames) {
        $parameters = $cells[$cellName]['parameters']
        $initKeys = @($parameters.Keys | Where-Object { $_ -like 'INIT_RAM_*' } | Sort-Object)
        if ($initKeys.Count -eq 0) {
            throw "Boot-ROM cell '$cellName' has no INIT_RAM_xx parameters in $NetlistPath"
        }
        foreach ($initKey in $initKeys) {
            $fingerprintLines.Add("$cellName/$initKey=$($parameters[$initKey])")
        }
    }

    $fingerprintText = ($fingerprintLines -join "`n") + "`n"
    $sha256 = [System.Security.Cryptography.SHA256]::Create()
    try {
        $digest = $sha256.ComputeHash([System.Text.Encoding]::UTF8.GetBytes($fingerprintText))
    } finally {
        $sha256.Dispose()
    }
    return [ordered]@{
        bram_cells = $romCellNames.Count
        init_sha256 = ([System.BitConverter]::ToString($digest)).Replace('-', '').ToLowerInvariant()
    }
}

Push-Location $projectRoot
try {
    $readCommands = $sourceList | ForEach-Object {
        if ($_ -in $romAwareSources) {
            "read_verilog -sv -DOMCU_ROM_IMAGE_BUILD -I$relativeRomConfigDir $(Quote-YosysPath $_)"
        } else {
            "read_verilog -sv $(Quote-YosysPath $_)"
        }
    }
    $yosysProgram = ($readCommands + @(
        "chparam -set ROM_WORDS $romWords $topModule",
        "chparam -set SRAM_BYTES $sramBytes $topModule",
        "synth_gowin -top $topModule -family gw1n -json $(Quote-YosysPath $relativeJsonPath)"
    )) -join '; '

    & $yosys -q -l $relativeYosysLogPath -p $yosysProgram
    if ($LASTEXITCODE -ne 0) {
        throw "Yosys synthesis failed with exit code $LASTEXITCODE. See $yosysLogPath"
    }
} finally {
    Pop-Location
}

if (-not (Test-Path -LiteralPath $jsonPath -PathType Leaf)) {
    throw "Yosys reported success but did not emit the Gowin JSON netlist: $jsonPath"
}
$sourceBootRomEvidence = Get-BootRomInitEvidence `
    -NetlistPath $jsonPath `
    -ModuleName $topModule

Push-Location $projectRoot
try {
    & $nextpnr `
        -q `
        --json $relativeJsonPath `
        --write $relativePnrPath `
        --device 'GW1NR-LV9QN88PC6/I5' `
        --vopt 'family=GW1N-9C' `
        --vopt "cst=$relativeCstPath" `
        --sdc $relativeSdcPath `
        --freq 27 `
        --placer-heap-beta $placerHeapBetaText `
        --seed $Seed `
        --report $relativeReportPath `
        --detailed-timing-report `
        --log $relativePnrLogPath
    if ($LASTEXITCODE -ne 0) {
        throw "nextpnr place-and-route failed with exit code $LASTEXITCODE. See $pnrLogPath"
    }

    if (-not $SkipPack) {
        & $gowinPack -d 'GW1N-9C' -o $relativeBitstreamPath $relativePnrPath
        if ($LASTEXITCODE -ne 0) {
            throw "gowin_pack failed with exit code $LASTEXITCODE"
        }
    }
} finally {
    Pop-Location
}

if (-not (Test-Path -LiteralPath $pnrPath -PathType Leaf) -or
    -not (Test-Path -LiteralPath $reportPath -PathType Leaf)) {
    throw 'nextpnr reported success but did not emit both placed netlist and report.'
}
$pnrBootRomEvidence = Get-BootRomInitEvidence -NetlistPath $pnrPath -ModuleName 'top'
if ($sourceBootRomEvidence.init_sha256 -ne $pnrBootRomEvidence.init_sha256 -or
    $sourceBootRomEvidence.bram_cells -ne $pnrBootRomEvidence.bram_cells) {
    throw ('Boot-ROM initialization changed between synthesis and place-and-route: ' +
        "source=$($sourceBootRomEvidence.init_sha256) ($($sourceBootRomEvidence.bram_cells) BSRAM), " +
        "pnr=$($pnrBootRomEvidence.init_sha256) ($($pnrBootRomEvidence.bram_cells) BSRAM).")
}

$report = Get-Content -LiteralPath $reportPath -Raw | ConvertFrom-Json
$fmaxEntries = @($report.fmax.PSObject.Properties)
if ($fmaxEntries.Count -ne 1) {
    throw "Expected exactly one constrained clock in $reportPath, found $($fmaxEntries.Count)."
}

$clockName = $fmaxEntries[0].Name
$clockTiming = $fmaxEntries[0].Value
$achievedMhz = [double]$clockTiming.achieved
$constraintMhz = [double]$clockTiming.constraint
if ([double]::IsNaN($achievedMhz) -or [double]::IsNaN($constraintMhz) -or
    $achievedMhz -le 0 -or $constraintMhz -le 0) {
    throw "Invalid timing values for $clockName in $reportPath."
}
if ($achievedMhz -lt $constraintMhz) {
    throw ("Timing failed for {0}: achieved {1:N3} MHz, required {2:N3} MHz." -f
        $clockName, $achievedMhz, $constraintMhz)
}

$utilizationSummary = [ordered]@{}
foreach ($resourceName in @('LUT4', 'DFF', 'BSRAM', 'ALU', 'MULT36X36', 'IOB')) {
    $resourceProperty = $report.utilization.PSObject.Properties[$resourceName]
    if ($null -ne $resourceProperty) {
        $utilizationSummary[$resourceName] = [ordered]@{
            used = [int]$resourceProperty.Value.used
            available = [int]$resourceProperty.Value.available
        }
    }
}

if (-not $SkipPack) {
    if (-not (Test-Path -LiteralPath $bitstreamPath -PathType Leaf)) {
        throw "gowin_pack reported success but did not emit bitstream: $bitstreamPath"
    }
}

$manifest = [ordered]@{
    generated_utc = [DateTime]::UtcNow.ToString('o')
    device = 'GW1NR-LV9QN88PC6/I5'
    family = 'GW1N-9C'
    top_module = $topModule
    mcu_mode = [bool]$McuMode
    yosys = Get-ExternalToolVersion $yosys
    nextpnr = Get-ExternalToolVersion $nextpnr
    placer = [ordered]@{
        algorithm = 'heap'
        heap_beta = $PlacerHeapBeta
        seed = $Seed
    }
    json_netlist = $relativeJsonPath
    pnr_netlist = $relativePnrPath
    report = $relativeReportPath
    rom_init_file = $relativeRomInitFile
    rom_init_sha256 = (Get-FileHash -LiteralPath $romInitFile -Algorithm SHA256).Hash.ToLowerInvariant()
    rom_image_file = $relativeRomImageFile
    rom_image_sha256 = (Get-FileHash -LiteralPath $romImagePath -Algorithm SHA256).Hash.ToLowerInvariant()
    rom_embedding = [ordered]@{
        source_bram_cells = $sourceBootRomEvidence.bram_cells
        source_bram_init_sha256 = $sourceBootRomEvidence.init_sha256
        pnr_bram_cells = $pnrBootRomEvidence.bram_cells
        pnr_bram_init_sha256 = $pnrBootRomEvidence.init_sha256
        verified = $true
    }
    memory = [ordered]@{
        rom_kib = $RomKiB
        rom_words = $romWords
        sram_kib = $SramKiB
        sram_bytes = $sramBytes
    }
    user_flash = if ($McuMode) {
        [ordered]@{
            bytes = 77824
            slots = 2
            slot_bytes = 36864
            application_payload_max_bytes = 36800
        }
    } else {
        $null
    }
    bitstream = if ($SkipPack) { $null } else { $relativeBitstreamPath }
    bitstream_sha256 = if ($SkipPack) { $null } else { (Get-FileHash -LiteralPath $bitstreamPath -Algorithm SHA256).Hash.ToLowerInvariant() }
    timing = [ordered]@{
        clock = $clockName
        achieved_mhz = $achievedMhz
        constraint_mhz = $constraintMhz
        slack_ns = ((1000.0 / $constraintMhz) - (1000.0 / $achievedMhz))
    }
    utilization = $utilizationSummary
}
$manifestPath = Join-Path $buildDirectory ($artifactStem + '_manifest.json')
[System.IO.File]::WriteAllText(
    $manifestPath,
    ($manifest | ConvertTo-Json -Depth 4),
    [System.Text.UTF8Encoding]::new($false)
)

if ($SkipPack) {
    Write-Output "PASS: Tang Nano 9K open P&R completed (packing skipped): $reportPath"
} else {
    Write-Output "PASS: Tang Nano 9K open bitstream completed: $bitstreamPath"
    Write-Output "SHA256: $($manifest.bitstream_sha256)"
}
Write-Output ("Timing: {0} achieved {1:N3} MHz / {2:N3} MHz constraint; slack {3:N3} ns" -f
    $clockName, $achievedMhz, $constraintMhz, $manifest.timing.slack_ns)
Write-Output "ROM init: $relativeRomInitFile"
Write-Output "Memory: ROM $RomKiB KiB ($romWords words), SRAM $SramKiB KiB ($sramBytes bytes)"
if ($McuMode) {
    Write-Output 'MCU mode: bootloader in FPGA configuration; applications use the separate 76 KiB User Flash A/B slots.'
}
foreach ($resourceName in $utilizationSummary.Keys) {
    $resource = $utilizationSummary[$resourceName]
    $percent = if ($resource.available -eq 0) { 0.0 } else { 100.0 * $resource.used / $resource.available }
    Write-Output ("Resource: {0} {1}/{2} ({3:N2}%)" -f
        $resourceName, $resource.used, $resource.available, $percent)
}
