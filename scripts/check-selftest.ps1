[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $false
$repoRoot = Split-Path -Parent $PSScriptRoot
$checker = Join-Path $PSScriptRoot 'check.ps1'
# Ubuntu 映像里 pwsh 往往有多条路径。取全部结果的 Source 会被拼成一条命令。
$pwsh = (Get-Command pwsh -CommandType Application | Select-Object -First 1).Source
$utf8 = [System.Text.UTF8Encoding]::new($false)
$tempBase = [System.IO.Path]::GetFullPath([System.IO.Path]::GetTempPath())
$scratch = Join-Path $tempBase ('3dbuilder-check-' + [guid]::NewGuid().ToString('N'))
$failures = [System.Collections.Generic.List[string]]::new()
$caseCount = 0

function Write-FixtureFile([string]$Directory, [string]$Relative, [string]$Text) {
    $destination = Join-Path $Directory $Relative
    $null = New-Item -ItemType Directory -Path (Split-Path -Parent $destination) -Force
    [System.IO.File]::WriteAllText($destination, $Text.Replace("`r`n", "`n"), $utf8)
}

$planPath = 'docs/plans/2024-02-29-selftest.md'
$designPath = 'docs/design/2024-02-29-selftest.md'
$newDesignPath = 'docs/design/2024-03-01-replacement.md'
$plan = @'
# 检查器计划样例

状态：active

## 目标与验收

- [ ] 样例验收。

## 当前进展

仅在临时副本运行。

## 验证证据

样例证据，用于结构检查，不代表产品验证。

## 下一步

继续样例任务。
'@ + "`n"
$design = @'
# 检查器设计样例

状态：proposed

## 问题

验证记录结构。

## 方案与取舍

仅建立测试样例。

## 影响

不修改工作区。

## 验证状态

仅测试检查器。
'@ + "`n"
$donePlan = $plan.Replace('状态：active', '状态：done').Replace('[ ]', '[x]')
$oldDesign = $design.Replace('状态：proposed', '状态：superseded') + "`n替代记录：[新决定](2024-03-01-replacement.md)`n"
$newDesign = $design.Replace('状态：proposed', '状态：accepted') + "`n替代来源：[历史：旧决定](2024-02-29-selftest.md)`n"

function Test-Case([string]$Name, [scriptblock]$Change, [string[]]$Expected = @()) {
    $script:caseCount++
    $caseRoot = Join-Path $scratch $Name
    $null = New-Item -ItemType Directory -Path $caseRoot
    # 每个样例从同一副本开始；不加载第三方技能、Git 或用户临时备份。
    Get-ChildItem -LiteralPath $baseline -Force | Copy-Item -Destination $caseRoot -Recurse
    & $Change $caseRoot
    $output = (& $pwsh -NoLogo -NoProfile -File $checker -Root $caseRoot 2>&1 | Out-String)
    $actual = $LASTEXITCODE
    $expectedCode = if ($Expected.Count -eq 0) { 0 } else { 1 }
    if ($actual -ne $expectedCode) {
        $failures.Add("${Name}: expected exit $expectedCode, got $actual`n$output")
        return
    }
    foreach ($message in $Expected) {
        if (-not $output.Contains($message)) {
            $failures.Add("${Name}: missing diagnostic '$message'`n$output")
        }
    }
    if ($expectedCode -eq 0 -and -not $output.Contains('Repository checks passed')) {
        $failures.Add("${Name}: missing success message`n$output")
    }
}

try {
    $baseline = Join-Path $scratch 'baseline'
    $null = New-Item -ItemType Directory -Path $baseline
    foreach ($entry in @('AGENTS.md', 'README.md', '.editorconfig', '.gitattributes', '.gitignore',
            'docs', 'scripts', '.github', 'src', 'tests')) {
        $source = Join-Path $repoRoot $entry
        if (Test-Path -LiteralPath $source) { Copy-Item -LiteralPath $source -Destination $baseline -Recurse }
    }
    Write-FixtureFile $baseline $planPath $plan
    Write-FixtureFile $baseline $designPath $design

    Test-Case 'valid-active-proposed-leap-date' { param($r) }
    Test-Case 'valid-done-accepted' { param($r)
        Write-FixtureFile $r $planPath $donePlan
        Write-FixtureFile $r $designPath ($design.Replace('状态：proposed', '状态：accepted'))
    }
    Test-Case 'valid-cancelled-rejected' { param($r)
        Write-FixtureFile $r $planPath ($plan.Replace('状态：active', '状态：cancelled').Replace('仅在临时副本运行。', '取消原因：仅测试状态。'))
        Write-FixtureFile $r $designPath ($design.Replace('状态：proposed', '状态：rejected'))
    }
    Test-Case 'valid-supersession-and-history' { param($r)
        Write-FixtureFile $r $designPath $oldDesign
        Write-FixtureFile $r $newDesignPath $newDesign
        Write-FixtureFile $r 'docs/history.md' "[历史：旧决定](design/2024-02-29-selftest.md)`n"
    }
    Test-Case 'valid-code-examples' { param($r)
        $example = "`n``````markdown`n状态：wrong`n## 目标与验收`n[示例](missing.md)`n```````n"
        Write-FixtureFile $r $planPath ($plan + $example + '`[行内示例](missing.md)`' + "`n")
    }
    Test-Case 'invalid-plan-status' { param($r)
        Write-FixtureFile $r $planPath ($plan.Replace('状态：active', '状态：accepted'))
    } @('invalid status')
    Test-Case 'invalid-design-status' { param($r)
        Write-FixtureFile $r $designPath ($design.Replace('状态：proposed', '状态：done'))
    } @('invalid status')
    Test-Case 'missing-status' { param($r)
        Write-FixtureFile $r $planPath ($plan.Replace('状态：active', ''))
    } @('expected exactly one status line')
    Test-Case 'duplicate-status' { param($r)
        Write-FixtureFile $r $planPath ($plan + "`n状态：active`n")
    } @('expected exactly one status line')
    Test-Case 'status-outside-header' { param($r)
        Write-FixtureFile $r $planPath ($plan.Replace('状态：active', '') + "`n状态：active`n")
    } @('status must be in the document header')
    Test-Case 'invalid-filename' { param($r)
        Write-FixtureFile $r 'docs/plans/2024-02-29-Bad_Name.md' $plan
    } @('record filename must be')
    Test-Case 'invalid-date' { param($r)
        Write-FixtureFile $r 'docs/plans/2025-02-29-invalid-date.md' $plan
    } @('invalid record date')
    Test-Case 'missing-section' { param($r)
        Write-FixtureFile $r $planPath ($plan.Replace('## 下一步', '## 其他'))
    } @('expected one section: 下一步')
    Test-Case 'duplicate-section' { param($r)
        Write-FixtureFile $r $designPath ($design + "`n## 问题`n`n重复。`n")
    } @('expected one section: 问题')
    Test-Case 'broken-link' { param($r)
        Write-FixtureFile $r 'docs/link.md' "[丢失文件](missing.md)`n"
    } @('broken local link')
    Test-Case 'link-escapes-repository' { param($r)
        $readme = Join-Path $r 'README.md'
        $text = [System.IO.File]::ReadAllText($readme)
        [System.IO.File]::WriteAllText($readme, ($text + "[仓库外](../)`n"), $utf8)
    } @('local link escapes repository')
    Test-Case 'drive-letter-link' { param($r)
        Write-FixtureFile $r 'docs/drive.md' "[盘符](C:/Windows/win.ini)`n"
    } @('broken local link')
    Test-Case 'done-unchecked' { param($r)
        Write-FixtureFile $r $planPath ($plan.Replace('状态：active', '状态：done'))
    } @('done plan has unchecked acceptance items')
    Test-Case 'done-empty-evidence' { param($r)
        Write-FixtureFile $r $planPath ($donePlan.Replace('样例证据，用于结构检查，不代表产品验证。', ''))
    } @('done plan requires nonempty verification evidence')
    Test-Case 'missing-replacement' { param($r)
        Write-FixtureFile $r $designPath ($design.Replace('状态：proposed', '状态：superseded'))
    } @('superseded design requires one replacement link')
    Test-Case 'replacement-is-not-a-design' { param($r)
        Write-FixtureFile $r $designPath ($oldDesign.Replace('2024-03-01-replacement.md', '../product.md'))
    } @('replacement must be another accepted or superseded design record')
    Test-Case 'missing-backlink' { param($r)
        Write-FixtureFile $r $designPath $oldDesign
        Write-FixtureFile $r $newDesignPath ($design.Replace('状态：proposed', '状态：accepted'))
    } @('replacement missing historical backlink')
    Test-Case 'current-navigation-to-superseded' { param($r)
        Write-FixtureFile $r $designPath $oldDesign
        Write-FixtureFile $r $newDesignPath $newDesign
        Write-FixtureFile $r 'docs/current.md' "[当前决定](design/2024-02-29-selftest.md)`n"
    } @('current navigation links to superseded design')
    Test-Case 'replacement-cycle' { param($r)
        Write-FixtureFile $r $designPath ($oldDesign + "`n替代来源：[历史：另一个](2024-03-01-replacement.md)`n")
        Write-FixtureFile $r $newDesignPath ($newDesign.Replace('状态：accepted', '状态：superseded') + "`n替代记录：[旧决定](2024-02-29-selftest.md)`n")
    } @('cyclic replacement chain')
    Test-Case 'missing-required-file' { param($r)
        Remove-Item -LiteralPath (Join-Path $r 'docs/product.md')
    } @('Missing required file: docs/product.md')
    Test-Case 'powershell-syntax' { param($r)
        Write-FixtureFile $r 'scripts/invalid.ps1' "function Broken {`n"
    } @('PowerShell syntax:')
    Test-Case 'text-format' { param($r)
        [System.IO.File]::WriteAllText((Join-Path $r 'docs/format.md'), "bad `r`nlast", $utf8)
    } @('trailing whitespace', 'use LF line endings', 'missing final newline')
    Test-Case 'utf8-bom' { param($r)
        [System.IO.File]::WriteAllText((Join-Path $r 'docs/bom.md'), "text`n", [System.Text.UTF8Encoding]::new($true))
    } @('remove UTF-8 BOM')
    Test-Case 'invalid-utf8' { param($r)
        [System.IO.File]::WriteAllBytes((Join-Path $r 'docs/invalid.md'), [byte[]]@(0xFF, 0xFE, 0xFF))
    } @('cannot read valid UTF-8 text')
    Test-Case 'empty-file' { param($r)
        Write-FixtureFile $r 'docs/empty.md' ''
    } @('empty file')
}
catch {
    $failures.Add($_.ToString())
}
finally {
    # 递归删除前核实实际绝对路径，只清理本次在系统临时目录创建的副本。
    if (Test-Path -LiteralPath $scratch) {
        $resolved = (Resolve-Path -LiteralPath $scratch).Path
        $expected = [System.IO.Path]::GetFullPath($scratch)
        $prefix = $tempBase.TrimEnd([System.IO.Path]::DirectorySeparatorChar) + [System.IO.Path]::DirectorySeparatorChar
        if ($resolved -ne $expected -or -not $resolved.StartsWith($prefix, [System.StringComparison]::OrdinalIgnoreCase) -or
            (Split-Path -Leaf $resolved) -notmatch '^3dbuilder-check-[a-f0-9]{32}$') {
            throw "Refusing cleanup outside the owned temporary directory: $resolved"
        }
        Remove-Item -LiteralPath $resolved -Recurse -Force
    }
}

if ($failures.Count -gt 0) {
    foreach ($failure in $failures) { [Console]::Error.WriteLine($failure) }
    [Console]::Error.WriteLine("Checker self-tests failed: $($failures.Count) problem(s)")
    exit 1
}
Write-Output "Checker self-tests passed ($caseCount cases). Application tests are not configured."
exit 0
