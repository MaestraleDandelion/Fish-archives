param([switch]$NoBrowser, [switch]$Desktop)

# 鱼鱼档案库 · 本地预览
# 由 本地预览.bat 启动：起一个只在本机可访问的小服务器，然后打开浏览器。

$ErrorActionPreference = 'Stop'
$root = $PSScriptRoot
try {
    & (Join-Path $root '更新搜索索引.ps1')
} catch {
    Write-Warning "索引未更新，可在预览中检查页面：$_"
}
$port = 8787

while ($true) {
    try {
        $listener = [System.Net.HttpListener]::new()
        $listener.Prefixes.Add("http://localhost:$port/")
        $listener.Start()
        break
    } catch {
        if ($port -ge 8820) { throw '找不到可用端口，请关掉其他预览窗口再试。' }
        $port++
    }
}

$url = "http://localhost:$port/"

Write-Host ''
Write-Host '  鱼鱼档案库 · 本地预览' -ForegroundColor Cyan
Write-Host "  $url" -ForegroundColor Yellow
Write-Host '  关掉这个窗口，预览就停了。' -ForegroundColor DarkGray
Write-Host ''

if (-not $NoBrowser) {
    if ($Desktop) { Start-Process ($url + '_预览/桌面对照.html') }
    else { Start-Process $url }
}

$mime = @{
    '.html' = 'text/html; charset=utf-8'
    '.md'   = 'text/markdown; charset=utf-8'
    '.css'  = 'text/css; charset=utf-8'
    '.js'   = 'application/javascript; charset=utf-8'
    '.json' = 'application/json; charset=utf-8'
    '.png'  = 'image/png'
    '.jpg'  = 'image/jpeg'
    '.jpeg' = 'image/jpeg'
    '.gif'  = 'image/gif'
    '.webp' = 'image/webp'
    '.svg'  = 'image/svg+xml'
    '.ico'  = 'image/x-icon'
    '.woff' = 'font/woff'
    '.woff2'= 'font/woff2'
}

while ($listener.IsListening) {
    try {
        $ctx = $listener.GetContext()
    } catch {
        break
    }

    $req = $ctx.Request
    $res = $ctx.Response

    try {
        $rel = [System.Uri]::UnescapeDataString($req.Url.AbsolutePath)
        if ($rel -eq '/' -or $rel -eq '') { $rel = '/index.html' }

        $local = $rel.TrimStart('/') -replace '/', '\'
        $path = [System.IO.Path]::GetFullPath((Join-Path $root $local))

        if (-not $path.StartsWith($root, [System.StringComparison]::OrdinalIgnoreCase)) {
            $res.StatusCode = 403
        }
        elseif (Test-Path -LiteralPath $path -PathType Container) {
            $path = Join-Path $path 'index.html'
        }

        if ($res.StatusCode -eq 200 -and (Test-Path -LiteralPath $path -PathType Leaf)) {
            $ext = [System.IO.Path]::GetExtension($path).ToLower()
            $res.ContentType = if ($mime.ContainsKey($ext)) { $mime[$ext] } else { 'application/octet-stream' }
            $res.Headers.Add('Cache-Control', 'no-store')
            $bytes = [System.IO.File]::ReadAllBytes($path)
            $res.ContentLength64 = $bytes.Length
            $res.OutputStream.Write($bytes, 0, $bytes.Length)
        }
        elseif ($res.StatusCode -eq 200) {
            $res.StatusCode = 404
            $msg = [System.Text.Encoding]::UTF8.GetBytes("404  $rel")
            $res.ContentType = 'text/plain; charset=utf-8'
            $res.ContentLength64 = $msg.Length
            $res.OutputStream.Write($msg, 0, $msg.Length)
        }
    } catch {
        try { $res.StatusCode = 500 } catch { }
    } finally {
        try { $res.Close() } catch { }
    }
}
