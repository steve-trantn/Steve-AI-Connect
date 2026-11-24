<#
.SYNOPSIS
  Biên dịch khung chat: chat\bin\SteveAIChat.exe + SteveAIPanel.ZWCAD.dll (csc có sẵn trong Windows).
  WebView2 SDK tải từ NuGet, đúng phiên bản và mã SHA-256 ghi dưới đây.
#>
param([string]$ZwcadDir = 'C:\Program Files\ZWSOFT\ZWCAD 2026', [string]$Acad48Dir = 'C:\Program Files\Autodesk\AutoCAD 2024', [string]$AcadCoreDir = 'C:\Program Files\Autodesk\AutoCAD 2026')
$ErrorActionPreference = 'Stop'
$wvVer = '1.0.4370.26'; $wvSha = '1c0dacac84b70109b3fd42f90c53a0ba942abc3a87590d7a4e0ccd86e4a06cf4'
$root = Split-Path $PSScriptRoot; $chat = Join-Path $root 'chat'; $bin = Join-Path $chat 'bin'
$num = (Get-Content (Join-Path $root 'VERSION') | Select-Object -First 1).Trim().TrimStart('v')
$cache = Join-Path $env:LOCALAPPDATA "SteveAIBuild\webview2-$wvVer"
New-Item -ItemType Directory -Force $bin, $cache | Out-Null
$zip = Join-Path $cache 'sdk.zip'
if (-not (Test-Path $zip)) {
  [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
  (New-Object Net.WebClient).DownloadFile("https://api.nuget.org/v3-flatcontainer/microsoft.web.webview2/$wvVer/microsoft.web.webview2.$wvVer.nupkg", $zip)
}
if ((Get-FileHash $zip -Algorithm SHA256).Hash.ToLower() -ne $wvSha) { Remove-Item $zip; throw 'WebView2 SDK sai mã SHA-256.' }
Add-Type -AssemblyName System.IO.Compression.FileSystem
$z = [IO.Compression.ZipFile]::OpenRead($zip)
try {
  foreach ($e in 'lib/net462/Microsoft.Web.WebView2.Core.dll', 'lib/net462/Microsoft.Web.WebView2.WinForms.dll', 'runtimes/win-x64/native/WebView2Loader.dll', 'LICENSE.txt') {
    $n = if ($e -eq 'LICENSE.txt') { 'LICENSE-WebView2.txt' } else { Split-Path $e -Leaf }
    [IO.Compression.ZipFileExtensions]::ExtractToFile($z.GetEntry($e), (Join-Path $bin $n), $true)
  }
} finally { $z.Dispose() }
if (Test-Path (Join-Path $bin 'web')) { Remove-Item (Join-Path $bin 'web') -Recurse -Force }
Copy-Item (Join-Path $chat 'web') $bin -Recurse
$csc = Join-Path $env:WINDIR 'Microsoft.NET\Framework64\v4.0.30319\csc.exe'
$src = Join-Path $env:TEMP "SteveAIChat-$PID.cs"
[IO.File]::WriteAllText($src, [IO.File]::ReadAllText((Join-Path $chat 'SteveAIChat.cs')).Replace('@VERSION@', $num), (New-Object Text.UTF8Encoding $true))
$fw = Split-Path $csc
& $csc /nologo /target:winexe /optimize+ /platform:x64 "/out:$bin\SteveAIChat.exe" "/reference:$bin\Microsoft.Web.WebView2.Core.dll" "/reference:$bin\Microsoft.Web.WebView2.WinForms.dll" /reference:System.Windows.Forms.dll /reference:System.Drawing.dll /reference:System.Web.Extensions.dll "/reference:$fw\System.Runtime.dll" "/reference:$fw\System.Threading.Tasks.dll" $src
$rc = $LASTEXITCODE; Remove-Item $src; if ($rc) { throw 'csc: SteveAIChat' }
# CAD palette plugins, one per .NET generation:
#   ZWCAD (.NET Framework) | AutoCAD 2021-2024, Civil 3D (.NET Framework 4.8) | AutoCAD / Civil 3D 2026-2027 (.NET 10)
function Get-NuGet([string]$id, [string]$ver, [string]$sha) {
  $dir = Join-Path $env:LOCALAPPDATA "SteveAIBuild\$id-$ver"; $z = "$dir.zip"
  if (-not (Test-Path $z)) { [Net.ServicePointManager]::SecurityProtocol = 'Tls12'; (New-Object Net.WebClient).DownloadFile("https://api.nuget.org/v3-flatcontainer/$id/$ver/$id.$ver.nupkg", $z) }
  if ((Get-FileHash $z -Algorithm SHA256).Hash.ToLower() -ne $sha) { Remove-Item $z; throw "$id sai mã SHA-256." }
  if (-not (Test-Path "$dir\.ok")) { if (Test-Path $dir) { Remove-Item $dir -Recurse -Force }; [IO.Compression.ZipFile]::ExtractToDirectory($z, $dir); New-Item "$dir\.ok" -ItemType File | Out-Null }
  return $dir
}
$src2 = Join-Path $env:TEMP "SteveAIPanel-$PID.cs"
[IO.File]::WriteAllText($src2, [IO.File]::ReadAllText((Join-Path $chat 'SteveAIPanel.cs')).Replace('@VERSION@', $num), (New-Object Text.UTF8Encoding $true))
$forms = '/reference:System.Windows.Forms.dll', '/reference:System.Drawing.dll', "/reference:$fw\WPF\PresentationCore.dll", "/reference:$fw\WPF\WindowsBase.dll"
try {
  if (Test-Path "$ZwcadDir\ZwManaged.dll") {
    & $csc /nologo /target:library /optimize+ /platform:x64 "/out:$bin\SteveAIPanel.ZWCAD.dll" "/reference:$ZwcadDir\ZwManaged.dll" "/reference:$ZwcadDir\ZwDatabaseMgd.dll" $forms $src2
    if ($LASTEXITCODE) { throw 'csc: ZWCAD' }
  } else { Write-Warning 'Thiếu ZWCAD: không có SteveAIPanel.ZWCAD.dll' }
  $ac = { param($d) foreach ($f in 'acmgd', 'accoremgd', 'acdbmgd', 'AdWindows') { "/reference:$d\$f.dll" } }
  if (Test-Path "$Acad48Dir\acmgd.dll") {
    & $csc /nologo /target:library /optimize+ /platform:x64 /define:ACAD "/out:$bin\SteveAIPanel.ACAD48.dll" (& $ac $Acad48Dir) $forms "/reference:$fw\WPF\PresentationFramework.dll" /reference:System.Xaml.dll $src2 (Join-Path $chat 'SteveAIRibbon.cs')
    if ($LASTEXITCODE) { throw 'csc: ACAD48' }
  } else { Write-Warning 'Thiếu AutoCAD 2024: không có SteveAIPanel.ACAD48.dll' }
  if (Test-Path "$AcadCoreDir\acmgd.dll") {
    $ros = Get-NuGet 'microsoft.net.compilers.toolset' '5.12.0' '1a498048ddc7bd5fdc2883e7c77f733a3727693e88518851cf8a8ef93cb5fa8d'
    $core = Get-NuGet 'microsoft.netcore.app.ref' '10.0.15' '71d5c46b014531d3226cb716e82b1a6e5434ac4a151a941d37ea34e1eb5e1c8e'
    $desk = Get-NuGet 'microsoft.windowsdesktop.app.ref' '10.0.15' '648517d72a772bc461be25ef637bba3c689de426ef71f73cff4b4c1cd63a77a6'
    $names = @{}; $refs = foreach ($f in @(Get-ChildItem "$desk\ref\net10.0\*.dll") + @(Get-ChildItem "$core\ref\net10.0\*.dll")) { if (-not $names[$f.Name]) { $names[$f.Name] = 1; "/reference:$($f.FullName)" } }
    $rsp = Join-Path $env:TEMP "SteveAIPanel-$PID.rsp"
    [IO.File]::WriteAllLines($rsp, [string[]](@('/nologo', '/nostdlib+', '/target:library', '/optimize+', '/platform:x64', '/define:ACAD', '/nowarn:CA1416', "/out:`"$bin\SteveAIPanel.ACADNET.dll`"") + @((@($refs) + @(& $ac $AcadCoreDir)) | ForEach-Object { '/reference:"' + $_.Substring(11) + '"' }) + "`"$src2`"" + "`"$(Join-Path $chat 'SteveAIRibbon.cs')`""))
    & "$ros\tasks\net472\csc.exe" /noconfig "@$rsp"; $rc = $LASTEXITCODE; Remove-Item $rsp
    if ($rc) { throw 'csc: ACADNET' }
  } else { Write-Warning 'Thiếu AutoCAD 2026: không có SteveAIPanel.ACADNET.dll' }
} finally { Remove-Item $src2 -ErrorAction SilentlyContinue }
Get-ChildItem $bin -File | ForEach-Object { "{0,10:N0}  {1}" -f $_.Length, $_.Name }
