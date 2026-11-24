# Steve AI Connect - small illustrated icons (drawn with GDI+, no image files). Dot-sourced by cadmenu.ps1.
# Every icon is drawn on a 32 x 32 grid and scaled, with mid tones that read on light and dark ribbons.
function New-DrawnIcon([string]$name, [int]$size) {
  Add-Type -AssemblyName System.Drawing
  $bmp = New-Object Drawing.Bitmap $size, $size
  $g = [Drawing.Graphics]::FromImage($bmp); $g.SmoothingMode = 'AntiAlias'; $g.PixelOffsetMode = 'HighQuality'; $g.TextRenderingHint = 'AntiAliasGridFit'
  $g.Clear([Drawing.Color]::Transparent); $g.ScaleTransform(($size / 32.0), ($size / 32.0))
  $col = { param($hex) [Drawing.ColorTranslator]::FromHtml($hex) }
  $br = { param($hex) New-Object Drawing.SolidBrush (& $col $hex) }
  $pn = { param($hex, $w) $q = New-Object Drawing.Pen (& $col $hex), ([float]$w); $q.LineJoin = 'Round'; $q.StartCap = 'Round'; $q.EndCap = 'Round'; $q }
  # 'x,y x,y ...' -> points
  $pt = { param($s) , [Drawing.PointF[]]@($s -split ' ' | ForEach-Object { $a = $_ -split ','; New-Object Drawing.PointF ([float]$a[0]), ([float]$a[1]) }) }
  $poly = { param($hex, $s) $g.FillPolygon((& $br $hex), (& $pt $s)) }
  $edge = { param($hex, $w, $s) $g.DrawPolygon((& $pn $hex $w), (& $pt $s)) }
  $line = { param($hex, $w, $s) $g.DrawLines((& $pn $hex $w), (& $pt $s)) }
  $sheet = { param($hex) & $poly $hex '5,2 20,2 27,9 27,30 5,30'; & $poly '#B9C6D6' '20,2 27,9 20,9' }
  switch ($name) {
    'cong-3d' {   # box culvert in perspective: front ring with the opening, top and side going back
      & $poly '#8FA3B8' '2,12 12,4 30,4 20,12'
      & $poly '#5F748A' '20,12 30,4 30,21 20,30'
      & $poly '#C3CFDB' '2,12 20,12 20,30 2,30'
      & $poly '#22303F' '6,16 16,16 16,26 6,26'
      & $poly '#3E5266' '6,26 9,23 16,23 16,26'
      & $line '#4B5F74' 1.2 '8,9 26,9'; & $line '#46596D' 1.2 '25,8 25,25.5'
      & $edge '#37495B' 1 '2,12 12,4 30,4 30,21 20,30 2,30'; & $line '#37495B' 1 '2,12 20,12 30,4'; & $line '#37495B' 1 '20,12 20,30'
    }
    'boc-khoi-luong' {   # table with a sum and a ruler
      & $poly '#F4F7FA' '2,2 25,2 25,22 2,22'; & $poly '#2E9E5B' '2,2 25,2 25,8 2,8'
      foreach ($y0 in 12.5, 17) { & $line '#9AAABC' 1 "2,$y0 25,$y0" }; foreach ($x0 in 10, 17.5) { & $line '#9AAABC' 1 "$x0,8 $x0,22" }
      & $edge '#4C6075' 1.2 '2,2 25,2 25,22 2,22'
      & $poly '#F5B301' '6,23 31,23 31,31 6,31'; & $edge '#9A6F00' 1 '6,23 31,23 31,31 6,31'
      foreach ($x0 in 10, 14, 18, 22, 26) { & $line '#6B4E00' 1.2 "$x0,23 $x0,$(if ($x0 -in 14, 22) { 28 } else { 26.5 })" }
    }
    'kiem-tra-ban-ve' {   # drawing sheet, magnifier with a check
      & $sheet '#F4F7FA'; & $edge '#4C6075' 1.2 '5,2 20,2 27,9 27,30 5,30'
      & $line '#3B82F6' 1.6 '9,14 9,9 15,9'; & $line '#9AAABC' 1.4 '9,25 13,25'; & $line '#9AAABC' 1.4 '9,21 11,21'
      $g.FillEllipse((& $br '#FFFFFF'), 12, 11, 14, 14); $g.DrawEllipse((& $pn '#D97706' 2.4), 12, 11, 14, 14); & $line '#D97706' 3.2 '24,23 30,29'
      & $line '#16A34A' 2.4 '15.5,18 18,20.5 22.5,15.5'
    }
    'viet-lisp' {   # code window with ( λ )
      & $poly '#22303F' '2,4 30,4 30,28 2,28'; & $poly '#3B82F6' '2,4 30,4 30,9 2,9'
      foreach ($x0 in 5, 8.5, 12) { $g.FillEllipse((& $br '#FFFFFF'), ($x0 - 1), 5.6, 2, 2) }
      $g.DrawArc((& $pn '#FFC400' 2.4), 6, 12, 9, 13, 110, 140); $g.DrawArc((& $pn '#FFC400' 2.4), 17, 12, 9, 13, -70, 140)
      & $line '#FFFFFF' 2 '14,13 16,15 18.5,24'; & $line '#FFFFFF' 2 '16.3,17.5 13.5,24'
    }
    'tao-skill' {   # star with a plus
      & $poly '#F5B301' '14,2 18,10.5 27,11.5 20.3,17.6 22.2,26.5 14,22 5.8,26.5 7.7,17.6 1,11.5 10,10.5'
      & $edge '#9A6F00' 1 '14,2 18,10.5 27,11.5 20.3,17.6 22.2,26.5 14,22 5.8,26.5 7.7,17.6 1,11.5 10,10.5'
      $g.FillEllipse((& $br '#16A34A'), 17, 17, 14, 14); & $line '#FFFFFF' 2.4 '24,20.5 24,27.5'; & $line '#FFFFFF' 2.4 '20.5,24 27.5,24'
    }
    'open' {   # chat bubble with a spark
      & $poly '#0068EC' '8,27 8,20 15,23'
      $q = New-Object Drawing.Drawing2D.GraphicsPath; $q.AddArc(1, 2, 10, 10, 180, 90); $q.AddArc(21, 2, 10, 10, 270, 90); $q.AddArc(21, 14, 10, 10, 0, 90); $q.AddArc(1, 14, 10, 10, 90, 90); $q.CloseFigure()
      $g.FillPath((& $br '#0068EC'), $q)
      & $poly '#FFC400' '16,4.5 18,11 24.5,13 18,15 16,21.5 14,15 7.5,13 14,11'
    }
    'skill' {   # a skill the user made: cog wheel of steps
      foreach ($y0 in 5, 14, 23) { $g.FillEllipse((& $br '#F5B301'), 2, $y0, 6, 6); & $line '#8FA3B8' 3 "13,$($y0 + 3) 29,$($y0 + 3)" }
    }
    'list' { foreach ($y0 in 4, 13, 22) { & $poly '#F5B301' "2,$y0 8,$y0 8,$($y0 + 6) 2,$($y0 + 6)"; & $line '#7C8FA5' 2.6 "13,$($y0 + 3) 29,$($y0 + 3)" } }
    'connect' {   # two nodes joined
      & $line '#7C8FA5' 3 '8,23 24,9'; $g.FillEllipse((& $br '#0068EC'), 1, 15, 15, 15); $g.FillEllipse((& $br '#F5B301'), 17, 2, 13, 13)
      & $line '#FFFFFF' 2 '5.5,22.5 8,25 12,20'
    }
    'help' {
      $g.FillEllipse((& $br '#5F748A'), 2, 2, 28, 28)
      $f = New-Object Drawing.Font 'Segoe UI', ([float]20), ([Drawing.FontStyle]::Bold), ([Drawing.GraphicsUnit]::Pixel)
      $sf = New-Object Drawing.StringFormat; $sf.Alignment = 'Center'; $sf.LineAlignment = 'Center'
      $g.DrawString('?', $f, [Drawing.Brushes]::White, (New-Object Drawing.RectangleF 0, 0, 32, 33), $sf)
    }
  }
  $g.Dispose()
  return $bmp
}
$script:DrawnSkills = 'cong-3d', 'boc-khoi-luong', 'kiem-tra-ban-ve', 'viet-lisp', 'tao-skill'
function New-SkillIcon([string]$skill, [int]$size) { return (New-DrawnIcon $(if ($skill -in $script:DrawnSkills) { $skill } else { 'skill' }) $size) }
