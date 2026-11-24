# Steve AI Connect - error reports. Dot-source after core.ps1 and account.ps1.
# Every part of the tool (window, launcher, MCP server, chat panel) appends errors to errors.log on this PC. They are sent to the
# registration server (Code.gs, action 'report') only when the user agreed (setting SendErrors = $true). Nothing that identifies the
# person, the PC, the drawings or the project is sent: see Protect-Text.
$script:ErrorLog = Join-Path $script:AppHome 'errors.log'

function Protect-Text([string]$s) {
  if (-not $s) { return '' }
  foreach ($n in $env:USERNAME, $env:COMPUTERNAME, $env:USERDOMAIN) { if ($n -and $n.Length -ge 3) { $s = [regex]::Replace($s, '(?i)(?<![A-Za-z0-9])' + [regex]::Escape($n) + '(?![A-Za-z0-9])', '[x]') } }
  # program files of the tool and of the CAD keep their file name (needed to find the line); every other path goes
  $s = [regex]::Replace($s, '(?i)[A-Z]:[\\/][^\r\n"''<>|*?]*?(SteveCADConnect|Program Files(?: \(x86\))?)[\\/]', '$1\')
  $s = [regex]::Replace($s, '(?i)(?:[A-Z]:[\\/]|\\\\)[^\r\n"''<>|*?]+', '[path]')
  $s = [regex]::Replace($s, '(?<![\w)])\\{1,2}[^\r\n"''<>|*?:]+\\[^\r\n"''<>|*?:]+', '[path]')   # \server\share\...
  $s = [regex]::Replace($s, '(?i)[^\s"''\\/:;,(){}\[\]]+( [^\s"''\\/:;,(){}\[\]]+){0,6}\.(dwg|dxf|pdf|xlsx?|docx?|lsp|ifc|rvt|dwt|csv)\b', '[file]')
  $s = [regex]::Replace($s, '[A-Za-z0-9._%+\-]+@[A-Za-z0-9.\-]+\.[A-Za-z]{2,}', '[email]')
  $s = [regex]::Replace($s, '(?<!\d)(?<!\d\.)(?:\+?84|0)[\d .\-]{8,12}\d(?!\d)', '[phone]')
  $s = [regex]::Replace($s, '(?i)(sk-|AIza|ghp_|key[=: ]+)[A-Za-z0-9_\-]{8,}', '[key]')
  if ($s.Length -gt 1500) { $s = $s.Substring(0, 1500) }
  return $s
}
function Add-ErrorLog([string]$src, [string]$msg, [string]$stack = '') {
  try {
    if ((Test-Path $script:ErrorLog) -and (Get-Item $script:ErrorLog).Length -gt 200KB) { Remove-Item $script:ErrorLog -Force }
    $line = @{ t = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss'); src = $src; ver = [string]$script:Version; msg = $msg; stack = $stack } | ConvertTo-Json -Compress
    [IO.File]::AppendAllText($script:ErrorLog, $line + "`n", $script:Utf8)
  } catch {}
}
# the distinct errors that were not sent yet: @(@{ key; src; ver; msg; stack })
function Get-PendingErrors {
  $sent = @(Get-Setting 'ErrSent' @()); $out = [ordered]@{}
  if (-not (Test-Path $script:ErrorLog)) { return @() }
  foreach ($l in [IO.File]::ReadAllLines($script:ErrorLog, [Text.Encoding]::UTF8)) {
    try { $e = $l | ConvertFrom-Json } catch { continue }
    $m = Protect-Text ([string]$e.msg); if (-not $m) { continue }
    $sha = [Security.Cryptography.SHA256]::Create()
    $key = [BitConverter]::ToString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes("$($e.ver)|$($e.src)|$($m -replace '\d+', '#')"))).Replace('-', '').Substring(0, 16).ToLower()
    if ($sent -contains $key -or $out.Contains($key)) { continue }
    $out[$key] = @{ key = $key; src = [string]$e.src; ver = [string]$e.ver; msg = $m; stack = (Protect-Text ([string]$e.stack)) }
  }
  return @($out.Values)
}
# returns how many were sent; silent on every failure, at most 10 new errors a day
function Send-ErrorReports {
  if (-not $script:RegisterUrl -or (Get-Setting 'SendErrors' $false) -ne $true) { return 0 }
  $n = 0
  try {
    $day = (Get-Date).ToString('yyyyMMdd'); $left = 10
    if ([string](Get-Setting 'ErrDay' '') -eq $day) { $left = 10 - [int](Get-Setting 'ErrCount' 0) }
    if ($left -le 0) { return 0 }
    foreach ($e in @(Get-PendingErrors | Select-Object -First $left)) {
      $sys = "Windows $([Environment]::OSVersion.Version)"
      try { $sys += '; ' + ((Get-CadStatus).GetEnumerator() | ForEach-Object { $_.Value.info }) -join '; ' } catch {}
      $r = Invoke-Register @{ action = 'report'; key = $e.key; src = $e.src; version = $e.ver; msg = $e.msg; stack = $e.stack; sys = (Protect-Text $sys) }
      if (-not $r.ok) { break }
      $n++
      Set-Setting 'ErrSent' @(@(Get-Setting 'ErrSent' @()) + $e.key | Select-Object -Last 200)
    }
    if ($n) { Set-Setting 'ErrDay' $day; Set-Setting 'ErrCount' (10 - $left + $n) }
  } catch {}
  return $n
}
