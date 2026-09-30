[CmdletBinding()]
param(
    [string]$Root = (Split-Path -Parent $PSScriptRoot)
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$repoRoot = (Resolve-Path -LiteralPath $Root).Path
$problems = [System.Collections.Generic.List[string]]::new()
$utf8 = [System.Text.UTF8Encoding]::new($false, $true)
$records = @{}
$links = [System.Collections.Generic.List[object]]::new()

function Get-SectionText([string]$Text, [string]$Heading) {
    $pattern = '(?ms)^## ' + [regex]::Escape($Heading) + '\s*\n(.*?)(?=^## |\z)'
    $section = [regex]::Match($Text, $pattern)
    return $section.Groups[1].Value.Trim()
}

function Test-InsideRepository([string]$RepositoryRoot, [string]$Candidate) {
    $comparison = [System.StringComparison]::OrdinalIgnoreCase
    $root = [System.IO.Path]::GetFullPath($RepositoryRoot)
    $full = [System.IO.Path]::GetFullPath($Candidate)
    if ($full.Equals($root, $comparison)) { return $true }
    $prefix = $root.TrimEnd('\', '/') + [System.IO.Path]::DirectorySeparatorChar
    return $full.StartsWith($prefix, $comparison)
}

$required = @(
    'AGENTS.md', 'README.md',
    '.editorconfig', '.gitattributes', '.gitignore',
    'docs/README.md', 'docs/product.md', 'docs/architecture.md',
    'scripts/check.ps1', 'scripts/check-selftest.ps1', '.github/workflows/ci.yml'
)

foreach ($relative in $required) {
    $path = Join-Path $repoRoot $relative
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        $problems.Add("Missing required file: $relative")
    }
}

# 仅检查自有文本与脚本，不加载第三方技能和生成文件，也不验证业务代码。
$files = @(Get-ChildItem -LiteralPath $repoRoot -File -Force | Where-Object {
    $_.Extension -eq '.md' -or $_.Name -in @(
        '.editorconfig', '.gitattributes', '.gitignore', '.env.example'
    )
})
foreach ($directory in @('docs', 'scripts', '.github', 'src', 'tests')) {
    $path = Join-Path $repoRoot $directory
    if (Test-Path -LiteralPath $path -PathType Container) {
        $files += @(Get-ChildItem -LiteralPath $path -File -Recurse -Force |
            Where-Object { $_.Extension -in @('.md', '.ps1', '.yml', '.yaml') })
    }
}

foreach ($file in $files) {
    $relative = $file.FullName.Substring($repoRoot.Length).TrimStart('\', '/').Replace('\', '/')
    try {
        $bytes = [System.IO.File]::ReadAllBytes($file.FullName)
        $content = $utf8.GetString($bytes)
    }
    catch {
        $problems.Add("${relative}: cannot read valid UTF-8 text")
        continue
    }
    if ([string]::IsNullOrWhiteSpace($content)) {
        $problems.Add("${relative}: empty file")
        continue
    }
    if ($content[0] -eq [char]0xFEFF) {
        $problems.Add("${relative}: remove UTF-8 BOM")
    }
    if (-not $content.EndsWith("`n")) {
        $problems.Add("${relative}: missing final newline")
    }
    if ($content.Contains("`r")) {
        $problems.Add("${relative}: use LF line endings")
    }
    $lineNumber = 0
    $fence = ''
    $proseLines = [System.Collections.Generic.List[string]]::new()
    foreach ($line in ($content -split "`n")) {
        $lineNumber++
        if ($line -match '[\t ]+\r?$') {
            $problems.Add("${relative}:${lineNumber}: trailing whitespace")
        }
        if ($file.Extension -ne '.md') { continue }
        if ($line -match '^\s*(`{3,}|~{3,})') {
            $marker = $Matches[1]
            if ($fence -eq '') {
                $fence = $marker
            }
            elseif ($marker[0] -eq $fence[0] -and $marker.Length -ge $fence.Length) {
                $fence = ''
            }
            continue
        }
        if ($fence -ne '') { continue }
        $proseLines.Add($line)
        # 支持简单行内链接。代码示例、锚点、引用式链接和至少两个字符的外部 URL 不检查。
        # 单字母加冒号是 Windows 盘符，不能当成 URL 放行。解析结果必须仍在仓库内。
        $prose = [regex]::Replace($line, '`+[^`]*`+', '')
        foreach ($link in [regex]::Matches($prose, '\[([^\]]*)\]\(([^\s)]+)\)')) {
            $target = $link.Groups[2].Value.Trim('<', '>')
            if ($target -match '^(?:[a-zA-Z][a-zA-Z0-9+.-]+:|//|#)') { continue }
            $target = [System.Uri]::UnescapeDataString(($target -split '[#?]', 2)[0])
            if ($target -eq '') { continue }
            try {
                $targetPath = [System.IO.Path]::GetFullPath((Join-Path $file.DirectoryName $target))
            }
            catch {
                $problems.Add("${relative}:${lineNumber}: invalid local link: $target")
                continue
            }
            if (-not (Test-InsideRepository $repoRoot $targetPath)) {
                $problems.Add("${relative}:${lineNumber}: local link escapes repository: $target")
                continue
            }
            if (-not (Test-Path -LiteralPath $targetPath)) {
                $problems.Add("${relative}:${lineNumber}: broken local link: $target")
            }
            $links.Add([pscustomobject]@{
                Source = $file.FullName; Target = $targetPath
                Label = $link.Groups[1].Value; Line = $line
                Location = "${relative}:${lineNumber}"
            })
        }
    }

    if ($file.Extension -eq '.md' -and $relative -match '^docs/(plans|design)/') {
        $kind = $Matches[1]
        if ($file.Name -cnotmatch '^(\d{4}-\d{2}-\d{2})-[a-z][a-z0-9]*(?:-[a-z0-9]+)*\.md$') {
            $problems.Add("${relative}: record filename must be YYYY-MM-DD-topic.md (lowercase)")
        }
        else {
            $date = [datetime]::MinValue
            if (-not [datetime]::TryParseExact($Matches[1], 'yyyy-MM-dd',
                    [cultureinfo]::InvariantCulture, [System.Globalization.DateTimeStyles]::None, [ref]$date)) {
                $problems.Add("${relative}: invalid record date")
            }
        }
        $text = $proseLines -join "`n"
        $states = [regex]::Matches($text, '(?m)^状态[：:]\s*([^\r\n]*)$')
        $state = ''
        $allowed = if ($kind -eq 'plans') { @('active', 'done', 'cancelled') }
            else { @('proposed', 'accepted', 'rejected', 'superseded') }
        if ($states.Count -ne 1) {
            $problems.Add("${relative}: expected exactly one status line")
        }
        else {
            $state = $states[0].Groups[1].Value.Trim()
            if ($state -cnotin $allowed -or $states[0].Value -cne "状态：$state") {
                $problems.Add("${relative}: invalid status; use 状态：$($allowed -join ' | ')")
            }
            $firstSection = [regex]::Match($text, '(?m)^## ')
            $title = [regex]::Match($text, '(?m)^# .+')
            if (-not $title.Success -or $states[0].Index -lt $title.Index -or
                ($firstSection.Success -and $states[0].Index -gt $firstSection.Index)) {
                $problems.Add("${relative}: status must be in the document header after the title")
            }
        }
        $headings = if ($kind -eq 'plans') { @('目标与验收', '当前进展', '验证证据', '下一步') }
            else { @('问题', '方案与取舍', '影响', '验证状态') }
        foreach ($heading in $headings) {
            if ([regex]::Matches($text, ('(?m)^## ' + [regex]::Escape($heading) + '[ \t]*$')).Count -ne 1) {
                $problems.Add("${relative}: expected one section: $heading")
            }
        }
        if ($kind -eq 'plans' -and $state -ceq 'done') {
            if ((Get-SectionText $text '目标与验收') -match '(?m)^\s*(?:[-*+]|\d+[.)])\s+\[ \]') {
                $problems.Add("${relative}: done plan has unchecked acceptance items")
            }
            if ([string]::IsNullOrWhiteSpace((Get-SectionText $text '验证证据'))) {
                $problems.Add("${relative}: done plan requires nonempty verification evidence")
            }
        }
        $records[$file.FullName] = [pscustomobject]@{ Kind = $kind; State = $state; Relative = $relative }
    }
    if ($file.Extension -eq '.ps1') {
        $tokens = $null
        $parseErrors = $null
        $null = [System.Management.Automation.Language.Parser]::ParseInput(
            $content, [ref]$tokens, [ref]$parseErrors
        )
        foreach ($parseError in $parseErrors) {
            $problems.Add("${relative}: PowerShell syntax: $($parseError.Message)")
        }
    }
}

# 用明确的替代标记与历史链接文字验证关系，不猜测正文中的业务含义。
$successors = @{}
foreach ($path in $records.Keys) {
    $record = $records[$path]
    if ($record.Kind -ne 'design' -or $record.State -cne 'superseded') { continue }
    $replacement = @($links | Where-Object { $_.Source -eq $path -and $_.Line -match '^替代记录：' })
    if ($replacement.Count -ne 1) {
        $problems.Add("$($record.Relative): superseded design requires one replacement link (替代记录：)")
        continue
    }
    $next = $replacement[0].Target
    if ($next -eq $path -or -not $records.ContainsKey($next) -or $records[$next].Kind -ne 'design' -or
        $records[$next].State -cnotin @('accepted', 'superseded')) {
        $problems.Add("$($record.Relative): replacement must be another accepted or superseded design record")
        continue
    }
    $successors[$path] = $next
    $backlinks = @($links | Where-Object {
        $_.Source -eq $next -and $_.Target -eq $path -and $_.Line -match '^替代来源：' -and $_.Label.StartsWith('历史：')
    })
    if ($backlinks.Count -eq 0) {
        $problems.Add("$($record.Relative): replacement missing historical backlink (替代来源：)")
    }
}
foreach ($start in $successors.Keys) {
    $seen = @{}
    $cursor = $start
    while ($successors.ContainsKey($cursor)) {
        if ($seen.ContainsKey($cursor)) {
            $problems.Add("$($records[$start].Relative): cyclic replacement chain")
            break
        }
        $seen[$cursor] = $true
        $cursor = $successors[$cursor]
    }
}
foreach ($link in $links) {
    if (-not $records.ContainsKey($link.Target) -or $records[$link.Target].State -cne 'superseded') { continue }
    $isHistory = $records.ContainsKey($link.Source) -and
        $records[$link.Source].State -cin @('done', 'cancelled', 'rejected', 'superseded')
    if (-not $isHistory -and -not $link.Label.StartsWith('历史：')) {
        $problems.Add("$($link.Location): current navigation links to superseded design; use a current record or 历史： label")
    }
}

if ($problems.Count -gt 0) {
    foreach ($problem in $problems) { [Console]::Error.WriteLine($problem) }
    [Console]::Error.WriteLine("Repository checks failed: $($problems.Count) problem(s)")
    exit 1
}

Write-Output "Repository checks passed ($($files.Count) files). Application tests are not configured."
exit 0
