param(
    [switch]$Check,
    [string]$OutFile
)

# 鱼鱼档案库 · 全站搜索索引
#
# 扫描仓库里应该被搜索到的 .md 页面，生成 assets/search-pages.js。
# 网页上的搜索框读这份清单，所以不用再靠侧边栏「捎带」收录。
#
# 不收录：
#   - 模板/            给 AI 看的骨架，搜出来只会干扰
#   - _ 开头的文件/目录  本地专用，不上传（_私密、_待上传、_收件箱、_sidebar 自己）
#
# 用法：
#   powershell -NoProfile -ExecutionPolicy Bypass -File 更新搜索索引.ps1
#   powershell ... -File 更新搜索索引.ps1 -Check    只检查、不写文件

$ErrorActionPreference = 'Stop'

$root = $PSScriptRoot
if (-not $OutFile) { $OutFile = Join-Path $root 'assets\search-pages.js' }
$sidebarFile = Join-Path $root '_sidebar.md'

$skipTopDirs = @('模板')
# 这些页面本来就不需要出现在侧边栏里，别当成漏链报警
$sidebarExempt = @('说明书-精简版.md')
$folderWeight = @{ '作品' = 10; '杂谈' = 20; '创作' = 30; '灵感' = 40; '摘录' = 50; '视频' = 60; '思考' = 70 }
$fileWeight = @{ 'README.md' = 1; '联系.md' = 2; '使用手册.md' = 3; '说明书.md' = 4; '说明书-精简版.md' = 5 }

function Get-RelativePath([string]$base, [string]$full) {
    return $full.Substring($base.Length).TrimStart('\').Replace('\', '/')
}

function Get-Weight([string]$rel) {
    if ($fileWeight.ContainsKey($rel)) { return $fileWeight[$rel] }
    $top = ($rel -split '/')[0]
    if ($folderWeight.ContainsKey($top)) { return $folderWeight[$top] }
    return 99
}

# 1. 收集页面
$pages = New-Object System.Collections.Generic.List[string]
Get-ChildItem -Path $root -Recurse -Filter *.md -File | ForEach-Object {
    $rel = Get-RelativePath $root $_.FullName
    $segments = $rel -split '/'
    if (@($segments | Where-Object { $_.StartsWith('_') }).Count -gt 0) { return }
    if ($segments.Count -gt 1 -and ($skipTopDirs -contains $segments[0])) { return }
    $pages.Add($rel)
}

$pages = @($pages | Sort-Object @{ Expression = { Get-Weight $_ } }, @{ Expression = { $_ } })

# 2. 顺手体检：侧边栏链接
$sidebarLinks = New-Object System.Collections.Generic.List[string]
if (Test-Path -LiteralPath $sidebarFile) {
    $sidebarText = [System.IO.File]::ReadAllText($sidebarFile, [System.Text.Encoding]::UTF8)
    foreach ($m in [regex]::Matches($sidebarText, '\]\(([^)#]+?)\)')) { $sidebarLinks.Add($m.Groups[1].Value) }
    foreach ($m in [regex]::Matches($sidebarText, 'href="([^"#]+?)"')) { $sidebarLinks.Add($m.Groups[1].Value) }
}
$sidebarLinks = @($sidebarLinks | ForEach-Object { $_.Trim() } | Where-Object { $_ } | Select-Object -Unique)

$brokenLinks = @($sidebarLinks | Where-Object { -not (Test-Path -LiteralPath (Join-Path $root ($_ -replace '/', '\')) -PathType Leaf) })
$notInSidebar = @($pages | Where-Object { $sidebarLinks -notcontains $_ -and $sidebarExempt -notcontains $_ })

Write-Host ''
Write-Host '  鱼鱼档案库 · 搜索索引' -ForegroundColor Cyan
Write-Host ("  收录页面：{0} 个" -f $pages.Count) -ForegroundColor Gray

if ($notInSidebar.Count -gt 0) {
    Write-Host '  这些页面没进侧边栏（搜索能搜到，左侧导航里没有）：' -ForegroundColor Yellow
    $notInSidebar | ForEach-Object { Write-Host ("    · {0}" -f $_) -ForegroundColor Yellow }
}

if ($brokenLinks.Count -gt 0) {
    Write-Host '  侧边栏里有链接指向不存在的文件：' -ForegroundColor Red
    $brokenLinks | ForEach-Object { Write-Host ("    × {0}" -f $_) -ForegroundColor Red }
}

if ($Check) {
    Write-Host ''
    Write-Host '  只检查，没有写文件。' -ForegroundColor DarkGray
    Write-Host ''
    exit 0
}

# 3. 写清单
$lines = New-Object System.Collections.Generic.List[string]
$lines.Add('// 由 更新搜索索引.ps1 生成，请勿手改。')
$lines.Add('// 网页搜索会抓取并索引下面这些页面（不含 模板/ 和 _ 开头的本地文件）。')
$lines.Add('window.$docsify = window.$docsify || {};')
$lines.Add('window.$docsify.search = Object.assign({}, window.$docsify.search, {')
$lines.Add('  paths: [')
foreach ($p in $pages) {
    # 写成 docsify 路由（不带 .md）。插件看到没有 /README 时会自己补一个 "/"，
    # 首页就会被索引两遍；第一个正是 /README，刚好挡住。
    $route = '/' + ($p -replace '\.md$', '')
    $lines.Add(("    '{0}'," -f $route))
}
$lines.Add('  ]')
$lines.Add('});')
$lines.Add('')

$utf8NoBom = New-Object System.Text.UTF8Encoding($false)
[System.IO.File]::WriteAllText($outFile, ($lines -join "`n"), $utf8NoBom)

Write-Host ("  已写入 {0}" -f (Get-RelativePath $root $outFile)) -ForegroundColor Green
Write-Host ''
