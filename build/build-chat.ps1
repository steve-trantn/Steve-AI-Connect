<#
.SYNOPSIS
  Biên dịch khung chat: chat\bin\SteveAIChat.exe + SteveAIPanel.ZWCAD.dll (csc có sẵn trong Windows).
  WebView2 SDK tải từ NuGet, đúng phiên bản và mã SHA-256 ghi dưới đây.
#>
param([string]$ZwcadDir = 'C:\Program Files\ZWSOFT\ZWCAD 2026')
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
if (Test-Path "$ZwcadDir\ZwManaged.dll") {
  & $csc /nologo /target:library /optimize+ /platform:x64 "/out:$bin\SteveAIPanel.ZWCAD.dll" "/reference:$ZwcadDir\ZwManaged.dll" "/reference:$ZwcadDir\ZwDatabaseMgd.dll" "/reference:$fw\WPF\PresentationCore.dll" "/reference:$fw\WPF\WindowsBase.dll" /reference:System.Windows.Forms.dll /reference:System.Drawing.dll (Join-Path $chat 'SteveAIPanel.cs')
  if ($LASTEXITCODE) { throw 'csc: SteveAIPanel' }
}
Get-ChildItem $bin -File | ForEach-Object { "{0,10:N0}  {1}" -f $_.Length, $_.Name }
