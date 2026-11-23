param(
    [switch]$Check,
    [string]$OutFile
)

# 默认更新清单。-Check 只校验，索引过期或站内链接失效时返回非零。
$ErrorActionPreference = 'Stop'
$root = $PSScriptRoot
if (-not $OutFile) { $OutFile = Join-Path $root 'assets/search-pages.js' }
$folderWeight = @{ '作品' = 10; '杂谈' = 20; '创作' = 30; '灵感' = 40; '摘录' = 50; '视频' = 60; '思考' = 70 }
$fileWeight = @{ 'README.md' = 1; '联系.md' = 2; '使用手册.md' = 3; '说明书.md' = 4; '说明书-精简版.md' = 5; '更新记录.md' = 6 }

function Get-Weight([string]$rel) {
    if ($fileWeight.ContainsKey($rel)) { return $fileWeight[$rel] }
    $top = ($rel -split '/')[0]
    if ($folderWeight.ContainsKey($top)) { return $folderWeight[$top] }
    return 99
}

function Get-PublicFiles([string]$dir) {
    foreach ($item in Get-ChildItem -LiteralPath $dir) {
        if ($item.Name -match '^[._]' -or $item.Name -eq 'AGENTS.md') { continue }
        if ($item.PSIsContainer) {
            Get-PublicFiles $item.FullName
        } else {
            $item.FullName.Substring($root.Length + 1).Replace('\', '/')
        }
    }
}

function Get-LinkTargets([string]$file) {
    # 本库的示例有围栏代码块和四空格缩进代码块，里面的路径只是演示。
    $content = [IO.File]::ReadAllText((Join-Path $root $file))
    $content = [regex]::Replace($content, '(?ms)^ {0,3}(`{3,}|~{3,})[^\n]*\n.*?^ {0,3}\1[\t ]*\r?$', '')
    $content = [regex]::Replace($content, '(?s)<!--.*?-->', '')
    $content = [regex]::Replace($content, '(?m)^(?:    |\t).*$', '')
    $content = [regex]::Replace($content, '(`+)[^\r\n]*?\1', '')
    # Markdown 链接、图片、引用定义和内嵌 HTML。检查文件路径，忽略页内锚点。
    $pattern = '(?im)(?:\]\(\s*|^ {0,3}\[[^\]]+\]:[ \t]*)(?:<(?<url>[^>]+)>|(?<url>[^\s)]+))|\b(?:href|src)\s*=\s*["''](?<url>[^"'']+)["'']'
    foreach ($match in [regex]::Matches($content, $pattern)) {
        $target = $match.Groups['url'].Value
        if ($target -match '^(?:[a-z][a-z0-9+.\-]*:|//)') { continue }
        if ($target.StartsWith('#/')) { $target = $target.Substring(1) }
        $path = ($target -split '[?#]', 2)[0]
        if (-not $path) { continue }
        $path = [Uri]::UnescapeDataString($path).TrimStart('/') -replace '^(\./)+', ''
        if (-not $path -or $path.EndsWith('/')) { $path += 'README.md' }
        elseif (-not [IO.Path]::GetExtension($path)) { $path += '.md' }
        $path
    }
}

# 使用逐字符排序，确保不同语言的 Windows 和发布环境产生同一份清单。
[string[]]$files = @(Get-PublicFiles $root)
[Array]::Sort($files, [StringComparer]::Ordinal)
$pages = @($files | Where-Object { $_ -like '*.md' -and $_ -notlike '模板/*' } |
    Group-Object { Get-Weight $_ } | Sort-Object { [int]$_.Name } | ForEach-Object { $_.Group })
Write-Host ("搜索收录 {0} 个页面。" -f $pages.Count)

$publicFiles = [Collections.Generic.HashSet[string]]::new($files, [StringComparer]::Ordinal)
$sidebarTargets = @(Get-LinkTargets '_sidebar.md')
$broken = foreach ($file in @('_sidebar.md') + $pages) {
    $targets = if ($file -eq '_sidebar.md') { $sidebarTargets } else { Get-LinkTargets $file }
    foreach ($target in $targets) {
        if (-not $publicFiles.Contains($target)) { "$file → $target" }
    }
}
if ($broken) { throw ("站内链接失效：`n" + ($broken -join "`n")) }
foreach ($page in $pages) {
    if ($page -cnotin $sidebarTargets -and $page -ne '说明书-精简版.md') {
        Write-Warning "搜索已收录，侧边栏没有入口：$page"
    }
}

$lines = @(
    '// 由 更新搜索索引.ps1 生成，请勿手改。'
    'window.$docsify = window.$docsify || {};'
    'window.$docsify.search = Object.assign({}, window.$docsify.search, {'
    '  paths: ['
    foreach ($page in $pages) {
        $route = '/' + ($page -replace '\.md$', '')
        "    '" + $route.Replace("'", "\'") + "',"
    }
    '  ]'
    '});'
    ''
)
$expected = $lines -join "`n"
if ($Check) {
    if (-not [IO.File]::Exists($OutFile) -or
        [IO.File]::ReadAllText($OutFile).Replace("`r`n", "`n") -cne $expected) {
        throw '搜索清单缺失或过期。请运行 更新搜索索引.ps1 重新生成。'
    }
    Write-Host '搜索清单和站内文件链接检查通过。'
} else {
    [IO.File]::WriteAllText($OutFile, $expected, [Text.UTF8Encoding]::new($false))
    Write-Host "已生成 $OutFile"
}
