# Steve AI Connect - tab ribbon "Steve AI" cho ZWCAD / AutoCAD (file partial SteveAI.cuix).
# Dot-sourced by core.ps1. The .cuix is a zip of XML parts (same layout as the ADSCivil menus).
# Every button macro first loads SteveAI.lsp when the drawing does not have it yet (LISP is per drawing).

$script:CadMenu = Join-Path $script:AppHome 'SteveAI.cuix'
. (Join-Path $PSScriptRoot 'icons.ps1')

# 16/32 px button icon: rounded square + short label
function New-MenuIcon([string]$label, [Drawing.Color]$bg, [Drawing.Color]$fg, [int]$size) {
  Add-Type -AssemblyName System.Drawing
  $bmp = New-Object Drawing.Bitmap $size, $size
  $g = [Drawing.Graphics]::FromImage($bmp)
  $g.SmoothingMode = 'AntiAlias'; $g.TextRenderingHint = 'AntiAliasGridFit'; $g.Clear([Drawing.Color]::Transparent)
  $r = [Math]::Max(4, [int]($size / 4)); $m = $size - 1
  $p = New-Object Drawing.Drawing2D.GraphicsPath
  $p.AddArc(0, 0, $r, $r, 180, 90); $p.AddArc($m - $r, 0, $r, $r, 270, 90); $p.AddArc($m - $r, $m - $r, $r, $r, 0, 90); $p.AddArc(0, $m - $r, $r, $r, 90, 90); $p.CloseFigure()
  $g.FillPath((New-Object Drawing.SolidBrush $bg), $p)
  $px = if ($label.Length -le 1) { $size * 0.62 } elseif ($label.Length -eq 2) { $size * 0.46 } else { $size * 0.34 }
  $f = New-Object Drawing.Font 'Segoe UI', ([float]$px), ([Drawing.FontStyle]::Bold), ([Drawing.GraphicsUnit]::Pixel)
  $sf = New-Object Drawing.StringFormat; $sf.Alignment = 'Center'; $sf.LineAlignment = 'Center'
  $g.DrawString($label, $f, (New-Object Drawing.SolidBrush $fg), (New-Object Drawing.RectangleF 0, 0, $size, ($size + 1)), $sf)
  $g.Dispose()
  $ms = New-Object IO.MemoryStream; $bmp.Save($ms, [Drawing.Imaging.ImageFormat]::Png); $bmp.Dispose()
  return $ms.ToArray()
}

function ConvertTo-Xml([string]$s) { [Security.SecurityElement]::Escape($s) }

function Write-CadMenu {
  Add-Type -AssemblyName System.IO.Compression, System.Drawing
  $blue = [Drawing.Color]::FromArgb(0, 104, 236); $gold = [Drawing.Color]::FromArgb(255, 196, 0)
  $dark = [Drawing.Color]::FromArgb(32, 33, 36); $white = [Drawing.Color]::White
  $lisp = $script:CadLisp -replace '\\', '/'
  # macro: load SteveAI.lsp into this drawing if needed, then run the command
  $mac = { param($cmd) "^C^C^P(if (not steveai-run) (load `"$lisp`")) ^P$cmd" }

  # buttons: id, ribbon text, tooltip, macro command, icon label, icon colours
  $btn = [ordered]@{}
  function Add-Btn($id, $text, $tipText, $cmd, $ico, $bg, $fg) { $btn[$id] = @{ id = $id; text = $text; tip = $tipText; cmd = $cmd; ico = $ico; bg = $bg; fg = $fg } }
  Add-Btn 'OPEN'   "Steve AI"        'Mở cửa sổ chat với trợ lý AI mặc định (lệnh tắt: AI)' 'AI' 'AI' $blue $gold
  Add-Btn 'CLAUDE' 'Claude Code'     'Mở Claude Code nối với bản vẽ (STEVEAI-CLAUDE)' 'STEVEAI-CLAUDE' 'CL' ([Drawing.Color]::FromArgb(204, 120, 92)) $white
  Add-Btn 'CODEX'  'ChatGPT Codex'   'Mở ChatGPT Codex nối với bản vẽ (STEVEAI-CODEX)' 'STEVEAI-CODEX' 'CO' ([Drawing.Color]::FromArgb(16, 163, 127)) $white
  Add-Btn 'GEMINI' 'Gemini CLI'      'Mở Gemini CLI nối với bản vẽ (STEVEAI-GEMINI)' 'STEVEAI-GEMINI' 'G' ([Drawing.Color]::FromArgb(66, 133, 244)) $white
  $skills = @(Get-SkillList)
  $i = 0
  foreach ($s in $skills) {
    $i++
    $c = 'AI-' + ((ConvertTo-Ascii $s.name).ToUpper() -replace '[^A-Z0-9\-]', '-')
    $d = $s.description; if ($d.Length -gt 220) { $d = $d.Substring(0, 217).TrimEnd() + '...' }
    Add-Btn "SK$i" $s.title "$d ($c)" $c '' $gold $dark
    $btn["SK$i"].draw = $s.name; $btn["SK$i"].group = $s.group
  }
  Add-Btn 'SKILL'  'Chọn skill…'     'Chọn một skill trong danh sách rồi mở AI chạy skill đó (STEVEAI-SKILL)' 'STEVEAI-SKILL' '≡' $gold $dark
  Add-Btn 'CONN'   "Kết nối"         'Mở Steve AI Connect: kết nối CAD với AI, xem danh sách tool (STEVECAD)' 'STEVECAD' 'S' $blue $white
  Add-Btn 'UPD'    'Cập nhật'        'Kiểm tra và cài bản mới của Steve AI Connect; cài xong cần đóng rồi mở lại CAD (STEVEAI-UPDATE)' 'STEVEAI-UPDATE' '^' $blue $white
  Add-Btn 'OPT'    'Tùy chọn'        'Mở Tùy chọn nâng cao của Steve AI Connect (STEVEAI-OPTIONS)' 'STEVEAI-OPTIONS' 'O' $blue $white
  Add-Btn 'SHARE'  'Chia sẻ skill'   'Gửi skill bạn tự tạo cho Steve duyệt (STEVEAI-SHARE)' 'STEVEAI-SHARE' 'S' $gold $dark
  Add-Btn 'FEAT'   'Đề xuất'         'Đề xuất tính năng mới hoặc góp ý (STEVEAI-FEATURE)' 'STEVEAI-FEATURE' '!' $gold $dark
  Add-Btn 'DIAG'   'Báo lỗi'         'Báo lỗi cho Steve: mô tả, xem trước thông tin chẩn đoán rồi gửi (STEVEAI-DIAG)' 'STEVEAI-DIAG' '+' $blue $white
  Add-Btn 'HELP'   'Hướng dẫn'       "Các lệnh Steve AI và liên hệ hỗ trợ: $($script:Contact) (STEVEAI-HELP)" 'STEVEAI-HELP' '?' ([Drawing.Color]::FromArgb(95, 99, 104)) $white

  # drawn icons (app\icons.ps1); the assistants keep their real logos
  foreach ($p0 in @(@('OPEN', 'open'), @('SKILL', 'list'), @('CONN', 'connect'), @('HELP', 'help'), @('UPD', 'update'), @('OPT', 'options'), @('SHARE', 'share'), @('FEAT', 'feature'), @('DIAG', 'diag'))) { $btn[$p0[0]].draw = $p0[1] }

  $hdr = '<?xml version="1.0"?>'
  $ns = 'xmlns:xsd="http://www.w3.org/2001/XMLSchema" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"'
  $rev = '<ModifiedRev MajorVersion="1" MinorVersion="0" UserVersion="1" />'

  $macros = foreach ($b in $btn.Values) {
@"
    <MenuMacro UID="MMU_SAI_$($b.id)">
      <Macro type="Any">
        $rev
        <Name xlate="true" UID="XLS_SAI_N_$($b.id)">$(ConvertTo-Xml $b.text)</Name>
        <Command>$(ConvertTo-Xml (& $mac $b.cmd))</Command>
        <HelpString xlate="true" UID="XLS_SAI_H_$($b.id)">$(ConvertTo-Xml $b.tip)</HelpString>
        <SmallImage Name="SAI_$($b.id)16.png" />
        <LargeImage Name="SAI_$($b.id)32.png" />
      </Macro>
    </MenuMacro>
"@ }
  $menuGroup = "$hdr`r`n<MenuGroup $ns Name=`"STEVEAI`" DisplayName=`"Steve AI`">`r`n  <MacroGroup Name=`"SteveAIMacros`">`r`n$($macros -join "`r`n")`r`n  </MacroGroup>`r`n</MenuGroup>`r`n"

  $rbtn = { param($id, $style)
    $b = $btn[$id]
@"
          <RibbonCommandButton UID="RBN_SAI_B_$id" Id="AcRibbonCommandButton" Text="$(ConvertTo-Xml $b.text)" ButtonStyle="$style" MenuMacroID="MMU_SAI_$id" KeyTip="">
            <TooltipTitle xlate="true" UID="XLS_SAI_T_$id">$(ConvertTo-Xml $b.text)</TooltipTitle>
            $rev
          </RibbonCommandButton>
"@ }
  # a stack of small buttons beside a large one
  $stack = { param($pk, $ids)
    $rows = foreach ($id in $ids) { "            <RibbonRow UID=`"RBN_SAI_RR_$id`">`r`n            $rev`r`n$(& $rbtn $id 'SmallWithText')            </RibbonRow>" }
    "          <RibbonRowPanel UID=`"RBN_SAI_RP_$pk`" ResizeStyle=`"None`" ResizePriority=`"100`" TopJustify=`"True`">`r`n          $rev`r`n$($rows -join "`r`n")`r`n          </RibbonRowPanel>"
  }
  $panel = { param($pk, $title, $body)
@"
    <RibbonPanelSource UID="RBN_SAI_P_$pk" Text="$(ConvertTo-Xml $title)" HiddenInEditor="false">
      $rev
      <Name xlate="true" UID="XLS_SAI_PN_$pk">$(ConvertTo-Xml $title)</Name>
      <RibbonRow UID="RBN_SAI_R_$pk">
        $rev
$body
      </RibbonRow>
    </RibbonPanelSource>
"@ }
  $skillIds = @($btn.Keys | Where-Object { $_ -like 'SK*' -and $_ -ne 'SKILL' })
  $pAi = & $panel 'AI' 'Trợ lý AI' ((& $rbtn 'OPEN' 'LargeWithText') + (& $stack 'AI' @('CLAUDE', 'CODEX', 'GEMINI')))
  # one panel per type of work, small buttons in columns of three; "Chọn skill" ends the last one
  $groups = @(); $gi = 0; $pSk = ''
  foreach ($gn in $script:SkillGroups) {
    $ids = @($skillIds | Where-Object { $btn[$_].group -eq $gn }); if ($gn -eq $script:SkillGroups[-1]) { $ids += 'SKILL' }
    if (-not $ids) { continue }
    $gi++; $body = ''
    for ($j = 0; $j -lt $ids.Count; $j += 3) { $body += (& $stack "G${gi}_$j" @($ids[$j..([Math]::Min($j + 2, $ids.Count - 1))])) + "`r`n" }
    $pSk += & $panel "G$gi" $gn $body
    $groups += @{ key = "G$gi"; title = $gn; ids = $ids }
  }
  $pCn = & $panel 'CONN' 'Hỗ trợ' ((& $stack 'CN' @('CONN', 'UPD', 'OPT')) + "`r`n" + (& $stack 'CN2' @('SHARE', 'FEAT', 'DIAG')) + "`r`n" + (& $stack 'CN3' @('HELP')))
  $refs = foreach ($p in @('AI') + @($groups | ForEach-Object { $_.key }) + 'CONN') { "      <RibbonPanelSourceReference UID=`"RBN_SAI_PR_$p`" PanelId=`"RBN_SAI_P_$p`" ResizeStyle=`"Default`">`r`n        $rev`r`n      </RibbonPanelSourceReference>" }
  $ribbon = @"
$hdr
<RibbonRoot>
  <RibbonPanelSourceCollection $ns>
$pAi$pSk$pCn  </RibbonPanelSourceCollection>
  <RibbonTabSourceCollection>
    <RibbonTabSource Text="Steve AI" UID="RBN_SAI_TAB" DisplayType="Full" DefaultDisplay="AddToWorkSpace" WorkspaceBehavior="MergeOrAddTab">
      $rev
      <Name xlate="true" UID="XLS_SAI_TAB">Steve AI</Name>
$($refs -join "`r`n")
    </RibbonTabSource>
  </RibbonTabSourceCollection>
  <RibbonTabSelectors />
</RibbonRoot>
"@

  # pull-down menu (menu bar) with the same commands
  $pmi = { param($id) "    <PopMenuItem IsSeparator=`"false`" hasDiesel=`"false`" UID=`"PMI_SAI_$id`">`r`n      $rev`r`n      <NameRef UID=`"XLS_SAI_M_$id`" xlate=`"true`">$(ConvertTo-Xml $btn[$id].text)</NameRef>`r`n      <MenuItem>`r`n        <MacroRef MenuMacroID=`"MMU_SAI_$id`" />`r`n      </MenuItem>`r`n    </PopMenuItem>" }
  $sepItem = { $script:SaiSep++; "    <PopMenuItem IsSeparator=`"true`" hasDiesel=`"false`" UID=`"PMI_SAI_S$($script:SaiSep)`">`r`n      $rev`r`n    </PopMenuItem>" }
  $script:SaiSep = 0
  $items = @('OPEN', 'CLAUDE', 'CODEX', 'GEMINI' | ForEach-Object { & $pmi $_ }) + (& $sepItem) + @($groups | ForEach-Object { @($_.ids | ForEach-Object { & $pmi $_ }) + (& $sepItem) }) + @('CONN', 'UPD', 'OPT', 'SHARE', 'FEAT', 'DIAG', 'HELP' | ForEach-Object { & $pmi $_ })
  $pop = "$hdr`r`n<PopMenuRoot $ns>`r`n  <PopMenu hasDiesel=`"false`" UID=`"PMU_SAI_ROOT`">`r`n    $rev`r`n    <Alias>POP1</Alias>`r`n    <Name xlate=`"true`" UID=`"XLS_SAI_POP`">Steve AI</Name>`r`n$($items -join "`r`n")`r`n  </PopMenu>`r`n</PopMenuRoot>`r`n"

  $parts = [ordered]@{
    'Header.cui' = "$hdr`r`n<CustSection $ns>`r`n  <FileVersion MajorVersion=`"0`" MinorVersion=`"6`" IncrementalVersion=`"1`" UserVersion=`"1`" />`r`n  <Header>`r`n    <CommonConfiguration>`r`n      <CommonItems>`r`n        $rev`r`n      </CommonItems>`r`n    </CommonConfiguration>`r`n  </Header>`r`n</CustSection>`r`n"
    'WorkspaceRoot.cui' = "$hdr`r`n<WorkspaceRoot $ns>`r`n  <WorkspaceConfigRoot />`r`n</WorkspaceRoot>`r`n"
    'MenuGroup.cui' = $menuGroup
    'PopMenuRoot.cui' = $pop
    'RibbonRoot.cui' = $ribbon
    'PanelSetRoot.cui' = "$hdr`r`n<PanelSetRoot $ns>`r`n  <PanelSet UID=`"PSTU_SAI_0001`" />`r`n</PanelSetRoot>`r`n"
  }
  foreach ($n in 'AcceleratorRoot', 'OverrideRoot', 'MouseButtonRoot', 'ToolbarRoot', 'DoubleClickRoot', 'QuickPropertiesRoot', 'RolloverTooltipRoot',
                 'QuickAccessToolbarRoot', 'ToolPanelRoot', 'ScreenMenuRoot', 'ImageMenuRoot', 'TabletMenuRoot', 'DigitizerButtonRoot', 'LSPFiles') {
    $parts["$n.cui"] = "$hdr`r`n<$n $ns />`r`n"
  }
  $images = [ordered]@{}
  # the assistants' buttons use their real logos (installed apps / shipped Gemini logo), the others a lettered icon
  $aiOf = @{ CLAUDE = 'claudecode'; CODEX = 'codex'; GEMINI = 'gemini' }
  foreach ($b in $btn.Values) {
    foreach ($sz in 16, 32) {
      $png = $null
      if ($aiOf[$b.id]) {
        $bm = Get-IconBitmap (Get-AiIconSource $aiOf[$b.id]) $sz
        if ($bm) { $ms = New-Object IO.MemoryStream; $bm.Save($ms, [Drawing.Imaging.ImageFormat]::Png); $bm.Dispose(); $png = $ms.ToArray() }
      }
      if (-not $png -and $b.draw) {
        $bm = if ($b.id -like 'SK*' -and $b.id -ne 'SKILL') { New-SkillIcon $b.draw $sz } else { New-DrawnIcon $b.draw $sz }
        $ms = New-Object IO.MemoryStream; $bm.Save($ms, [Drawing.Imaging.ImageFormat]::Png); $bm.Dispose(); $png = $ms.ToArray()
      }
      $images["SAI_$($b.id)$sz.png"] = $(if ($png) { , $png } else { , (New-MenuIcon $b.ico $b.bg $b.fg $sz) })
    }
  }

  # the same buttons for the AutoCAD / Civil 3D plugin (chat\SteveAIRibbon.cs): a text file and the icons
  $icoDir = Join-Path $script:AppHome 'icons'; New-Item -ItemType Directory -Force $icoDir | Out-Null
  foreach ($n in $images.Keys) { try { [IO.File]::WriteAllBytes((Join-Path $icoDir $n), [byte[]]$images[$n]) } catch {} }
  $rows = foreach ($d0 in @(, @('Trợ lý AI', @('OPEN', 'CLAUDE', 'CODEX', 'GEMINI'))) + @($groups | ForEach-Object { , @($_.title, $_.ids) }) + @(, @('Hỗ trợ', @('CONN', 'UPD', 'OPT', 'SHARE', 'FEAT', 'DIAG', 'HELP')))) {
    foreach ($id in $d0[1]) { $b = $btn[$id]; (@($d0[0], $(if ($id -eq 'OPEN') { 'large' } else { 'small' }), $b.text, $b.tip, "(if (not steveai-run) (load `"$lisp`")) $($b.cmd)", "SAI_$id") | ForEach-Object { $_ -replace '[\t\r\n]+', ' ' }) -join "`t" }
  }
  [IO.File]::WriteAllLines((Join-Path $script:AppHome 'ribbon.txt'), [string[]]$rows, (New-Object Text.UTF8Encoding $false))

  $stamp = (Get-Date).ToString('yyyy-MM-ddTHH:mm:ss.fffffffzzz')
  $info = "<?xml version=`"1.0`" encoding=`"utf-8`"?>`r`n<MenuPackageParts>`r`n" + ((@($parts.Keys) + 'Menu_Package_Info.xml' + @($images.Keys) | ForEach-Object { "  <PartData PartData_Name=`"/$_`" PartData_Modified=`"$stamp`" />" }) -join "`r`n") + "`r`n</MenuPackageParts>`r`n"
  $k = 0
  $rels = '<?xml version="1.0" encoding="utf-8"?><Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">' +
    ((@($parts.Keys) | ForEach-Object { $k++; "<Relationship Type=`"CUI`" Target=`"/$_`" Id=`"Rsaic$('{0:D4}' -f $k)`" />" }) -join '') +
    "<Relationship Type=`"MenuPackageInfo`" Target=`"/Menu_Package_Info.xml`" Id=`"Rsaim0001`" />" +
    ((@($images.Keys) | ForEach-Object { $k++; "<Relationship Type=`"Image`" Target=`"/$_`" Id=`"Rsaii$('{0:D4}' -f $k)`" />" }) -join '') + '</Relationships>'
  $types = '<?xml version="1.0" encoding="utf-8"?><Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types"><Default Extension="cui" ContentType="text/xml" /><Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml" /><Default Extension="bmp" ContentType="image/bmp" /><Default Extension="xml" ContentType="text/xml" /><Default Extension="png" ContentType="image/png" /></Types>'

  New-Item -ItemType Directory -Force $script:AppHome | Out-Null
  $tmp = "$($script:CadMenu).tmp"
  Remove-Item $tmp -Force -ErrorAction SilentlyContinue
  $utf8 = New-Object Text.UTF8Encoding $false
  $fs = [IO.File]::Open($tmp, 'CreateNew')
  $zip = New-Object IO.Compression.ZipArchive $fs, ([IO.Compression.ZipArchiveMode]::Create)
  try {
    $put = { param($name, [byte[]]$bytes) $e = $zip.CreateEntry($name); $s = $e.Open(); $s.Write($bytes, 0, $bytes.Length); $s.Close() }
    & $put '[Content_Types].xml' $utf8.GetBytes($types)
    foreach ($n in $parts.Keys) { & $put $n $utf8.GetBytes($parts[$n]) }
    & $put 'Menu_Package_Info.xml' $utf8.GetBytes($info)
    foreach ($n in $images.Keys) { & $put $n $images[$n] }
    & $put '_rels/.rels' $utf8.GetBytes($rels)
  } finally { $zip.Dispose(); $fs.Dispose() }
  # a CAD that has the menu loaded keeps the file open: then keep the old one
  try { Move-Item $tmp $script:CadMenu -Force -ErrorAction Stop } catch { Remove-Item $tmp -Force -ErrorAction SilentlyContinue; Write-Log "  Tab ribbon Steve AI đang được CAD dùng, giữ bản cũ." }
}

# running ZWCAD / AutoCAD: unload the menu group so the CAD forgets SteveAI.cuix
function Remove-CadMenu {
  foreach ($progid in 'ZWCAD.Application', 'AutoCAD.Application') {
    try {
      $app = [Runtime.InteropServices.Marshal]::GetActiveObject($progid)
      foreach ($g in @($app.MenuGroups)) { if ($g.Name -eq 'STEVEAI') { $g.Unload() } }
    } catch {}
  }
  Remove-Item $script:CadMenu -Force -ErrorAction SilentlyContinue
}
