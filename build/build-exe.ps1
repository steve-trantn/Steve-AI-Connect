<#
.SYNOPSIS
  Đóng gói Steve AI Connect thành MỘT file exe để gửi cho người khác:
    dist\Steve-AI-Connect-Setup-<version>.exe
  Dùng trình biên dịch C# có sẵn trong Windows (.NET Framework 4.x), không cần cài thêm gì.
.EXAMPLE
  powershell -ExecutionPolicy Bypass -File build\build-exe.ps1
#>
param([switch]$NoRegister)   # -NoRegister: test exe while $script:RegisterUrl is still empty
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot
$ver = (Get-Content (Join-Path $root 'VERSION') | Select-Object -First 1).Trim()   # v4.0.0
$num = $ver.TrimStart('v')
if (-not $NoRegister -and (Get-Content (Join-Path $root 'app\core.ps1') -Raw) -notmatch "RegisterUrl = 'https://script\.google\.com/macros/s/[^']+/exec'") {
  throw 'Chưa điền $script:RegisterUrl trong app\core.ps1 (xem register\README.md). Bản thử: thêm -NoRegister.'
}
$dist = Join-Path $root 'dist'
$work = Join-Path $env:TEMP "SteveCADBuild-$PID"
New-Item -ItemType Directory -Force $dist, $work | Out-Null
Add-Type -AssemblyName System.IO.Compression, System.IO.Compression.FileSystem, System.Drawing

try {
  # 1. payload: the same files Install-Self copies, without caches
  $stage = Join-Path $work 'payload'
  & (Join-Path $PSScriptRoot 'build-chat.ps1') | Out-Null   # chat window + CAD palette
  $items = 'app', 'CAD', 'server', 'templates', 'chat', 'VERSION', 'README.md', 'LICENSE', 'NOTICE', 'Uninstall.cmd', 'Steve AI Connect.cmd'
  foreach ($i in $items) {
    $p = Join-Path $root $i
    if (Test-Path $p -PathType Container) {
      foreach ($f in Get-ChildItem $p -Recurse -File | Where-Object { $_.FullName -notmatch '\\__pycache__\\|\.pyc$|\.bak' }) {
        $to = Join-Path $stage $f.FullName.Substring($root.Length + 1)
        New-Item -ItemType Directory -Force (Split-Path $to) | Out-Null
        Copy-Item $f.FullName $to
      }
    } elseif (Test-Path $p) { Copy-Item $p $stage }
  }
  $zip = Join-Path $work 'payload.zip'
  [IO.Compression.ZipFile]::CreateFromDirectory($stage, $zip, [IO.Compression.CompressionLevel]::Optimal, $false)

  # 2. icon: blue rounded square, white S, gold AI (same as the tool), PNG frames 16..256
  function New-IconPng([int]$n) {
    $bmp = New-Object Drawing.Bitmap $n, $n
    $g = [Drawing.Graphics]::FromImage($bmp); $g.SmoothingMode = 'AntiAlias'; $g.TextRenderingHint = 'AntiAliasGridFit'; $g.Clear([Drawing.Color]::Transparent)
    $k = $n / 64.0; $r = [Math]::Max(3, 14 * $k); $m = $n - 1
    $path = New-Object Drawing.Drawing2D.GraphicsPath
    $path.AddArc(0, 0, $r, $r, 180, 90); $path.AddArc($m - $r, 0, $r, $r, 270, 90); $path.AddArc($m - $r, $m - $r, $r, $r, 0, 90); $path.AddArc(0, $m - $r, $r, $r, 90, 90); $path.CloseFigure()
    $g.FillPath((New-Object Drawing.Drawing2D.LinearGradientBrush (New-Object Drawing.Point 0, 0), (New-Object Drawing.Point ($n + 1), ($n + 1)), ([Drawing.Color]::FromArgb(24, 150, 250)), ([Drawing.Color]::FromArgb(0, 88, 228))), $path)
    $sf = New-Object Drawing.StringFormat; $sf.Alignment = 'Center'; $sf.LineAlignment = 'Center'
    $f1 = New-Object Drawing.Font 'Segoe UI', ([float](25 * $k)), ([Drawing.FontStyle]::Bold), ([Drawing.GraphicsUnit]::Pixel)
    $g.DrawString('S', $f1, [Drawing.Brushes]::White, (New-Object Drawing.RectangleF 0, (2 * $k), (40 * $k), (40 * $k)), $sf)
    $f2 = New-Object Drawing.Font 'Segoe UI', ([float](17 * $k)), ([Drawing.FontStyle]::Bold), ([Drawing.GraphicsUnit]::Pixel)
    $g.DrawString('AI', $f2, (New-Object Drawing.SolidBrush ([Drawing.Color]::FromArgb(255, 196, 0))), (New-Object Drawing.RectangleF (22 * $k), (26 * $k), (42 * $k), (36 * $k)), $sf)
    $g.Dispose()
    $ms = New-Object IO.MemoryStream; $bmp.Save($ms, [Drawing.Imaging.ImageFormat]::Png); $bmp.Dispose(); return , $ms.ToArray()
  }
  $sizes = 16, 24, 32, 48, 64, 128, 256
  $pngs = @($sizes | ForEach-Object { , (New-IconPng $_) })
  $ico = Join-Path $work 'app.ico'
  $fs = [IO.File]::Create($ico); $bw = New-Object IO.BinaryWriter $fs
  $bw.Write([uint16]0); $bw.Write([uint16]1); $bw.Write([uint16]$sizes.Count)
  $off = 6 + 16 * $sizes.Count
  for ($i = 0; $i -lt $sizes.Count; $i++) {
    $s = $sizes[$i]; $b = if ($s -ge 256) { 0 } else { $s }
    $bw.Write([byte]$b); $bw.Write([byte]$b); $bw.Write([byte]0); $bw.Write([byte]0)
    $bw.Write([uint16]1); $bw.Write([uint16]32); $bw.Write([uint32]$pngs[$i].Length); $bw.Write([uint32]$off)
    $off += $pngs[$i].Length
  }
  foreach ($p in $pngs) { $bw.Write($p) }
  $bw.Close()

  # 3. compile
  $fw = Join-Path $env:WINDIR 'Microsoft.NET\Framework64\v4.0.30319'
  $csc = Join-Path $fw 'csc.exe'
  $src = Join-Path $work 'SteveCADSetup.cs'
  [IO.File]::WriteAllText($src, ([IO.File]::ReadAllText((Join-Path $PSScriptRoot 'SteveCADSetup.cs')).Replace('@VERSION@', $num)), (New-Object Text.UTF8Encoding $true))
  $out = Join-Path $dist "Steve-AI-Connect-Setup-$ver.exe"
  $cscArgs = @('/nologo', '/target:winexe', '/optimize+', '/platform:anycpu', "/out:$out", "/win32icon:$ico",
               "/resource:$zip,payload.zip", "/reference:$fw\System.IO.Compression.dll", "/reference:$fw\System.IO.Compression.FileSystem.dll",
               '/reference:System.Windows.Forms.dll', '/reference:System.Drawing.dll', $src)
  & $csc @cscArgs
  if ($LASTEXITCODE -ne 0) { throw "csc báo lỗi ($LASTEXITCODE)" }
  $kb = [Math]::Round((Get-Item $out).Length / 1KB)
  Write-Host "Xong: $out ($kb KB)" -ForegroundColor Green
} finally {
  Remove-Item $work -Recurse -Force -ErrorAction SilentlyContinue
}
