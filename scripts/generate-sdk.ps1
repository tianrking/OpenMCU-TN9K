[CmdletBinding()]
param(
    [string]$SpecPath,
    [string]$OutputPath,
    [switch]$Check
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$projectRoot = Split-Path -Parent $PSScriptRoot
if ([string]::IsNullOrWhiteSpace($SpecPath)) {
    $SpecPath = Join-Path $projectRoot 'spec\omcu-v0.json'
}
if ([string]::IsNullOrWhiteSpace($OutputPath)) {
    $OutputPath = Join-Path $projectRoot 'sdk\include\omcu_regs.h'
}

function Convert-HexOffset {
    param([string]$Value)
    if (-not $Value.StartsWith('0x', [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "Expected a hexadecimal offset, got '$Value'."
    }
    return [Convert]::ToUInt32($Value.Substring(2), 16)
}

$spec = Get-Content -LiteralPath $SpecPath -Raw | ConvertFrom-Json
$header = [System.Text.StringBuilder]::new()

[void]$header.AppendLine('#ifndef OMCU_REGS_H_')
[void]$header.AppendLine('#define OMCU_REGS_H_')
[void]$header.AppendLine('')
[void]$header.AppendLine('/*')
[void]$header.AppendLine(' * Generated from spec/omcu-v0.json by scripts/generate-sdk.ps1.')
[void]$header.AppendLine(' * Do not hand-edit this file; change the reviewed specification instead.')
[void]$header.AppendLine(' * MMIO configuration, command and W1C writes require an aligned 32-bit store.')
[void]$header.AppendLine(' * Byte/halfword MMIO writes are ignored unless a register explicitly documents an exception.')
[void]$header.AppendLine(' */')
[void]$header.AppendLine('')
[void]$header.AppendLine('#include <stdint.h>')
[void]$header.AppendLine('')

foreach ($entry in $spec.memory) {
    [void]$header.AppendLine(('#define {0,-24} UINT32_C({1})' -f $entry.macro, $entry.address))
}
[void]$header.AppendLine('')
[void]$header.AppendLine(('#define OMCU_HW_ABI_MAJOR      {0}u' -f $spec.device.abi_major))
[void]$header.AppendLine(('#define OMCU_HW_ABI_MINOR      {0}u' -f $spec.device.abi_minor))
[void]$header.AppendLine('')

foreach ($define in $spec.defines) {
    [void]$header.AppendLine(('#define {0,-24} {1}' -f $define.name, $define.value))
}
if ($spec.defines.Count -gt 0) {
    [void]$header.AppendLine('')
}

foreach ($peripheral in $spec.peripherals) {
    [void]$header.AppendLine('typedef struct {')
    $nextOffset = [uint32]0
    foreach ($register in ($peripheral.registers | Sort-Object { Convert-HexOffset $_.offset })) {
        $offset = Convert-HexOffset $register.offset
        if ($offset -lt $nextOffset) {
            throw "Registers for $($peripheral.name) overlap at $($register.offset)."
        }
        $gapWords = [int](($offset - $nextOffset) / 4)
        if ($gapWords -gt 0) {
            if ($gapWords -eq 1) {
                [void]$header.AppendLine(('  uint32_t _reserved_{0:x2};' -f $nextOffset))
            } else {
                [void]$header.AppendLine(('  uint32_t _reserved_{0:x2}[{1}];' -f $nextOffset, $gapWords))
            }
        }
        $ctype = if ($register.access -eq 'ro') { 'volatile const uint32_t' } else { 'volatile uint32_t' }
        [void]$header.AppendLine(('  {0} {1}; /* +{2}: {3} */' -f $ctype, $register.name, $register.offset, $register.comment))
        $nextOffset = $offset + 4
    }
    [void]$header.AppendLine(('}} {0};' -f $peripheral.ctype))
    [void]$header.AppendLine('')
}

foreach ($peripheral in $spec.peripherals) {
    $macroName = 'OMCU_' + $peripheral.name.ToUpperInvariant()
    [void]$header.AppendLine(('#define {0,-24} (({1} *)(uintptr_t){2})' -f $macroName, $peripheral.ctype, $peripheral.base_macro))
}
[void]$header.AppendLine('')
[void]$header.AppendLine('enum {')
foreach ($constant in $spec.constants) {
    [void]$header.AppendLine(('  {0,-32} = {1},' -f $constant.name, $constant.value))
}
[void]$header.AppendLine('};')
[void]$header.AppendLine('')
[void]$header.AppendLine('#endif  /* OMCU_REGS_H_ */')

$expected = $header.ToString().Replace("`r`n", "`n")
if ($Check) {
    if (-not (Test-Path -LiteralPath $OutputPath -PathType Leaf)) {
        throw "Generated header is missing: $OutputPath"
    }
    # Git may materialize the checked-in generated header as CRLF on Windows,
    # while the generator deliberately writes a canonical LF form.  Compare
    # normalized text so -Check validates the register ABI, not checkout mode.
    $actual = (Get-Content -LiteralPath $OutputPath -Raw).Replace("`r`n", "`n")
    if ($actual -cne $expected) {
        throw "Generated header differs from the specification. Run scripts/generate-sdk.ps1."
    }
    Write-Output 'PASS: generated SDK register header matches specification'
    exit 0
}

$outputDirectory = Split-Path -Parent $OutputPath
New-Item -ItemType Directory -Force -Path $outputDirectory | Out-Null
[System.IO.File]::WriteAllText($OutputPath, $expected, [System.Text.UTF8Encoding]::new($false))
Write-Output "Generated $OutputPath"
