$CliArgs = @($args)

function Find-GitBash {
  param($GitCmd)
  $candidates = @()
  $gitBin = if (-not [string]::IsNullOrWhiteSpace($GitCmd.Source)) { $GitCmd.Source } else { 'git' }
  $execPath = $null
  try {
    $execPath = (& $gitBin --exec-path 2>$null | Select-Object -First 1)
  } catch {}
  if (-not [string]::IsNullOrWhiteSpace($execPath)) {
    $p = $execPath.Trim()
    for ($i = 0; $i -lt 3; $i++) {
      $p = Split-Path -Parent $p
      if ([string]::IsNullOrWhiteSpace($p)) { break }
      $candidates += (Join-Path $p 'bin\sh.exe')
      $candidates += (Join-Path $p 'usr\bin\sh.exe')
    }
  }
  if (-not [string]::IsNullOrWhiteSpace($GitCmd.Source)) {
    $gitDir = Split-Path -Parent $GitCmd.Source
    if (-not [string]::IsNullOrWhiteSpace($gitDir)) {
      $gitParent = Split-Path -Parent $gitDir
      if (-not [string]::IsNullOrWhiteSpace($gitParent)) {
        $candidates += (Join-Path $gitParent 'bin\sh.exe')
        $candidates += (Join-Path $gitParent 'usr\bin\sh.exe')
      }
    }
  }
  if (-not [string]::IsNullOrWhiteSpace($env:ProgramFiles)) {
    $candidates += (Join-Path $env:ProgramFiles 'Git\bin\sh.exe')
  }
  if (-not [string]::IsNullOrWhiteSpace(${env:ProgramFiles(x86)})) {
    $candidates += (Join-Path ${env:ProgramFiles(x86)} 'Git\bin\sh.exe')
  }
  if (-not [string]::IsNullOrWhiteSpace($env:LOCALAPPDATA)) {
    $candidates += (Join-Path $env:LOCALAPPDATA 'Programs\Git\bin\sh.exe')
  }
  foreach ($c in $candidates) {
    if (-not [string]::IsNullOrWhiteSpace($c) -and (Test-Path -LiteralPath $c)) {
      return $c
    }
  }
  return $null
}

function Write-Seg {
  param([string]$Txt, $Fg, [bool]$NoColor)
  if ($NoColor -or $null -eq $Fg) {
    [Console]::Write($Txt)
  } else {
    $prev = [Console]::ForegroundColor
    [Console]::ForegroundColor = $Fg
    [Console]::Write($Txt)
    [Console]::ForegroundColor = $prev
  }
}

function Write-PadEnd {
  param([int]$Used, [int]$Bw)
  $rem = $Bw - $Used
  if ($rem -gt 0) { [Console]::Write((' ' * $rem)) }
  [Console]::Write("`n")
}

function Show-ScopePicker {
  param([string]$Title, [string]$Opt1, [string]$Opt2)
  $noColor = -not [string]::IsNullOrEmpty($env:NO_COLOR)
  $oldVis = $true
  $oldCtrlC = $false
  try { $oldVis = [Console]::CursorVisible } catch {}
  try { $oldCtrlC = [Console]::TreatControlCAsInput } catch {}
  try {
    try { [Console]::CursorVisible = $false } catch {}
    try { [Console]::TreatControlCAsInput = $true } catch {}
    if ([Console]::CursorLeft -gt 0) { [Console]::Write("`n") }
    $opts = @($Opt1, $Opt2)
    $cur = 0
    $n = 4
    for ($i = 0; $i -lt $n; $i++) { [Console]::Write("`n") }
    $baseTop = [Math]::Max(0, [Console]::CursorTop - $n)
    while ($true) {
      $bw = 80
      try { $bw = [Math]::Max(20, [Console]::BufferWidth - 1) } catch {}
      [Console]::SetCursorPosition(0, $baseTop)
      $t = if ($Title.Length -gt $bw) { $Title.Substring(0, $bw) } else { $Title }
      Write-Seg $t $null $noColor
      Write-PadEnd $t.Length $bw
      for ($i = 0; $i -lt 2; $i++) {
        $num = [string]($i + 1)
        $lbl = $opts[$i]
        if ($i -eq $cur) {
          $pre = '  > '
          $rest = "$num) $lbl"
          $maxRest = [Math]::Max(0, $bw - $pre.Length)
          if ($rest.Length -gt $maxRest) { $rest = $rest.Substring(0, $maxRest) }
          Write-Seg '  ' $null $noColor
          Write-Seg '>' ([ConsoleColor]::Cyan) $noColor
          Write-Seg ' ' $null $noColor
          Write-Seg $rest $null $noColor
          Write-PadEnd ($pre.Length + $rest.Length) $bw
        } else {
          $line = "    $num) $lbl"
          if ($line.Length -gt $bw) { $line = $line.Substring(0, $bw) }
          Write-Seg $line $null $noColor
          Write-PadEnd $line.Length $bw
        }
      }
      $hint = '  Move: arrows/j/k | Select: Enter | Cancel: q/Esc'
      if ($hint.Length -gt $bw) { $hint = $hint.Substring(0, $bw) }
      Write-Seg $hint ([ConsoleColor]::DarkGray) $noColor
      Write-PadEnd $hint.Length $bw

      $k = [Console]::ReadKey($true)
      $ch = [string]$k.KeyChar
      $isCtrlC = ([int]$k.KeyChar -eq 3) -or (($k.Modifiers -band [ConsoleModifiers]::Control) -and ($k.Key -eq [ConsoleKey]::C))
      if ($isCtrlC -or $k.Key -eq [ConsoleKey]::Escape -or $ch -ieq 'q') {
        [Console]::SetCursorPosition(0, [Math]::Min([Console]::BufferHeight - 1, $baseTop + $n))
        return $null
      } elseif ($k.Key -eq [ConsoleKey]::UpArrow -or $k.Key -eq [ConsoleKey]::DownArrow -or $ch -ieq 'j' -or $ch -ieq 'k') {
        $cur = 1 - $cur
      } elseif ($ch -eq '1') {
        $cur = 0
      } elseif ($ch -eq '2') {
        $cur = 1
      } elseif ($k.Key -eq [ConsoleKey]::Enter -or $k.Key -eq [ConsoleKey]::Spacebar -or $ch -eq ' ') {
        [Console]::SetCursorPosition(0, [Math]::Min([Console]::BufferHeight - 1, $baseTop + $n))
        return ($cur + 1)
      }
    }
  } finally {
    try { [Console]::TreatControlCAsInput = $oldCtrlC } catch {}
    try { [Console]::CursorVisible = $oldVis } catch {}
  }
}

function Show-PersonaPicker {
  param([string]$InitCsv = 'claude')
  $noColor = -not [string]::IsNullOrEmpty($env:NO_COLOR)
  $names = @('claude', 'copilot', 'codex', 'cursor', 'aider', 'devin')
  $labels = @(
    'Claude   <noreply@anthropic.com>',
    'Copilot  <223556219+Copilot@users.noreply.github.com>',
    'Codex    <noreply@openai.com>',
    'Cursor   <cursoragent@cursor.com>',
    'aider    <aider@aider.chat>',
    'Devin    (author mode: git devin commit)'
  )
  $sel = [bool[]]@($false, $false, $false, $false, $false, $false)
  foreach ($item in ($InitCsv -split ',')) {
    $t = $item.Trim()
    if ($t -eq 'all') {
      for ($i = 0; $i -lt 5; $i++) { $sel[$i] = $true }
    } else {
      $idx = [Array]::IndexOf($names, $t)
      if ($idx -ge 0) { $sel[$idx] = $true }
    }
  }

  $oldVis = $true
  $oldCtrlC = $false
  try { $oldVis = [Console]::CursorVisible } catch {}
  try { $oldCtrlC = [Console]::TreatControlCAsInput } catch {}
  try {
    try { [Console]::CursorVisible = $false } catch {}
    try { [Console]::TreatControlCAsInput = $true } catch {}
    if ([Console]::CursorLeft -gt 0) { [Console]::Write("`n") }
    $cur = 0
    $errMsg = ''
    $n = 8
    for ($i = 0; $i -lt $n; $i++) { [Console]::Write("`n") }
    $baseTop = [Math]::Max(0, [Console]::CursorTop - $n)
    while ($true) {
      $bw = 80
      try { $bw = [Math]::Max(20, [Console]::BufferWidth - 1) } catch {}
      [Console]::SetCursorPosition(0, $baseTop)
      $hdr = 'Pick co-author(s) (arrows/j/k move, Space toggle, a all, Enter):'
      if ($hdr.Length -gt $bw) { $hdr = $hdr.Substring(0, $bw) }
      Write-Seg $hdr $null $noColor
      Write-PadEnd $hdr.Length $bw
      for ($i = 0; $i -lt 6; $i++) {
        $num = [string]($i + 1)
        $box = if ($sel[$i]) { '[x]' } else { '[ ]' }
        $lbl = $labels[$i]
        $prefixLen = 8
        $rest = "$num) $lbl"
        $maxRest = [Math]::Max(0, $bw - $prefixLen)
        if ($rest.Length -gt $maxRest) { $rest = $rest.Substring(0, $maxRest) }
        Write-Seg '  ' $null $noColor
        if ($i -eq $cur) { Write-Seg '>' ([ConsoleColor]::Cyan) $noColor } else { Write-Seg ' ' $null $noColor }
        Write-Seg ' ' $null $noColor
        if ($sel[$i]) { Write-Seg $box ([ConsoleColor]::Green) $noColor } else { Write-Seg $box $null $noColor }
        Write-Seg ' ' $null $noColor
        Write-Seg $rest $null $noColor
        Write-PadEnd ($prefixLen + $rest.Length) $bw
      }
      if (-not [string]::IsNullOrEmpty($errMsg)) {
        $foot = "  $errMsg"
        if ($foot.Length -gt $bw) { $foot = $foot.Substring(0, $bw) }
        Write-Seg $foot ([ConsoleColor]::Yellow) $noColor
        Write-PadEnd $foot.Length $bw
      } else {
        $picked = @()
        for ($i = 0; $i -lt 6; $i++) { if ($sel[$i]) { $picked += $names[$i] } }
        $csv = if ($picked.Count -gt 0) { $picked -join ',' } else { 'none' }
        $foot = "  Selected: $csv (q/Esc cancel)"
        if ($foot.Length -gt $bw) { $foot = $foot.Substring(0, $bw) }
        Write-Seg $foot ([ConsoleColor]::DarkGray) $noColor
        Write-PadEnd $foot.Length $bw
      }

      $k = [Console]::ReadKey($true)
      $ch = [string]$k.KeyChar
      $isCtrlC = ([int]$k.KeyChar -eq 3) -or (($k.Modifiers -band [ConsoleModifiers]::Control) -and ($k.Key -eq [ConsoleKey]::C))
      if ($isCtrlC -or $k.Key -eq [ConsoleKey]::Escape -or $ch -ieq 'q') {
        [Console]::SetCursorPosition(0, [Math]::Min([Console]::BufferHeight - 1, $baseTop + $n))
        return $null
      } elseif ($k.Key -eq [ConsoleKey]::UpArrow -or $ch -ieq 'k') {
        $cur = ($cur + 5) % 6
      } elseif ($k.Key -eq [ConsoleKey]::DownArrow -or $ch -ieq 'j') {
        $cur = ($cur + 1) % 6
      } elseif ($k.Key -eq [ConsoleKey]::Spacebar -or $ch -eq ' ') {
        $sel[$cur] = -not $sel[$cur]
        $errMsg = ''
      } elseif ($ch -ge '1' -and $ch -le '6') {
        $cur = [int]::Parse($ch) - 1
        $sel[$cur] = -not $sel[$cur]
        $errMsg = ''
      } elseif ($ch -ieq 'a') {
        $allOn = $sel[0] -and $sel[1] -and $sel[2] -and $sel[3] -and $sel[4]
        for ($i = 0; $i -lt 5; $i++) { $sel[$i] = -not $allOn }
        $errMsg = ''
      } elseif ($ch -ieq 'n') {
        for ($i = 0; $i -lt 6; $i++) { $sel[$i] = $false }
        $errMsg = ''
      } elseif ($k.Key -eq [ConsoleKey]::Enter) {
        $picked = @()
        for ($i = 0; $i -lt 6; $i++) { if ($sel[$i]) { $picked += $names[$i] } }
        if ($picked.Count -gt 0) {
          [Console]::SetCursorPosition(0, [Math]::Min([Console]::BufferHeight - 1, $baseTop + $n))
          return ($picked -join ',')
        }
        $errMsg = 'Select at least one (Space to toggle, q to cancel)'
      }
    }
  } finally {
    try { [Console]::TreatControlCAsInput = $oldCtrlC } catch {}
    try { [Console]::CursorVisible = $oldVis } catch {}
  }
}

function Invoke-FakeAuthorInstall {
  param([string[]]$ArgsList = @())

  $script:FaRc = 0
  $gitCmd = Get-Command git -ErrorAction SilentlyContinue
  if ($null -eq $gitCmd) {
    [Console]::Error.WriteLine('fakeauthor: git not found on PATH. Install Git for Windows: https://git-scm.com/download/win')
    $script:FaRc = 1
    return
  }
  $gitBin = if (-not [string]::IsNullOrWhiteSpace($gitCmd.Source)) { $gitCmd.Source } else { 'git' }

  $shExe = Find-GitBash -GitCmd $gitCmd
  if ([string]::IsNullOrWhiteSpace($shExe)) {
    [Console]::Error.WriteLine('fakeauthor: Git for Windows bundled sh.exe not found. Install/repair Git for Windows: https://git-scm.com/download/win')
    $script:FaRc = 1
    return
  }

  $hadHome = Test-Path Env:HOME
  $prevHome = $env:HOME
  $hadPreview = Test-Path Env:FAKEAUTHOR_PREVIEW
  $prevPreview = $env:FAKEAUTHOR_PREVIEW
  $tmpSh = $null
  try {
    if ((-not $hadHome) -or [string]::IsNullOrWhiteSpace($env:HOME)) {
      $gitHome = $null
      try {
        $gitHome = (& $gitBin -c 'alias.fa-home=!printf %s "$HOME"' fa-home 2>$null | Select-Object -First 1)
      } catch {}
      if (-not [string]::IsNullOrWhiteSpace($gitHome)) {
        $env:HOME = $gitHome.Trim()
      } elseif (-not [string]::IsNullOrWhiteSpace($env:USERPROFILE)) {
        $env:HOME = $env:USERPROFILE
      }
    }

    $raw = $null
    if (-not [string]::IsNullOrEmpty($PSScriptRoot)) {
      $localSh = Join-Path $PSScriptRoot 'install.sh'
      if (Test-Path -LiteralPath $localSh) {
        $raw = [IO.File]::ReadAllText($localSh)
      }
    }
    if ($null -eq $raw) {
      $url = if (-not [string]::IsNullOrWhiteSpace($env:FAKEAUTHOR_INSTALL_SH_URL)) {
        $env:FAKEAUTHOR_INSTALL_SH_URL
      } else {
        'https://raw.githubusercontent.com/segfawlt/fakeauthor/refs/heads/main/install.sh'
      }
      if (-not [Console]::IsOutputRedirected) {
        [Console]::WriteLine('fakeauthor: downloading installer...')
      }
      try {
        [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
      } catch {}
      $irmParams = @{ Uri = $url }
      if ((Get-Command Invoke-RestMethod).Parameters.ContainsKey('UseBasicParsing')) {
        $irmParams['UseBasicParsing'] = $true
      }
      $raw = Invoke-RestMethod @irmParams
    }

    if ([string]::IsNullOrEmpty($raw)) {
      [Console]::Error.WriteLine('fakeauthor: failed to load install.sh')
      $script:FaRc = 1
      return
    }

    $raw = ($raw -replace "`r`n", "`n") -replace "`r", ""
    $tmpSh = [IO.Path]::Combine([IO.Path]::GetTempPath(), 'fakeauthor-install-' + [Guid]::NewGuid().ToString('N') + '.sh')
    [IO.File]::WriteAllText($tmpSh, $raw, (New-Object System.Text.UTF8Encoding($false)))

    $scopeArg = $null
    $forceArg = $false
    $positional = @()
    foreach ($a in $ArgsList) {
      if ($a -eq '--local') { $scopeArg = 'local' }
      elseif ($a -eq '--global') { $scopeArg = 'global' }
      elseif ($a -eq '--force') { $forceArg = $true }
      else { $positional += $a }
    }

    if ($positional.Count -eq 0 -and (-not [Console]::IsInputRedirected) -and (-not [Console]::IsOutputRedirected) -and [string]::IsNullOrEmpty($env:FAKEAUTHOR_TTY)) {
      $commonDir = $null
      $inRepo = $false
      try {
        $cdOut = (& $gitBin rev-parse --git-common-dir 2>$null | Select-Object -First 1)
        if ($LASTEXITCODE -eq 0 -and -not [string]::IsNullOrWhiteSpace($cdOut)) {
          $inRepo = $true
          $commonDir = $cdOut.Trim()
          if (-not [IO.Path]::IsPathRooted($commonDir)) {
            $commonDir = Join-Path (Get-Location).Path $commonDir
          }
        }
      } catch {}

      $faBase = if (-not [string]::IsNullOrWhiteSpace($env:FAKEAUTHOR_DIR)) {
        $env:FAKEAUTHOR_DIR
      } else {
        Join-Path $env:HOME '.local\share\fakeauthor'
      }
      $globalManifest = Join-Path $faBase 'manifest'
      $localManifest = if ($inRepo) { Join-Path $commonDir 'fakeauthor-manifest' } else { $null }
      $wizManifest = $null
      if ($scopeArg -eq 'local' -and $null -ne $localManifest) {
        $wizManifest = $localManifest
      } elseif ($scopeArg -eq 'global') {
        $wizManifest = $globalManifest
      } elseif (Test-Path -LiteralPath $globalManifest) {
        $wizManifest = $globalManifest
      } elseif ($null -ne $localManifest -and (Test-Path -LiteralPath $localManifest)) {
        $wizManifest = $localManifest
      }
      if ($null -ne $wizManifest -and (Test-Path -LiteralPath $wizManifest)) {
        $mLines = [IO.File]::ReadAllLines($wizManifest)
        $mVer = 'unversioned'
        $mHooksDir = ''
        foreach ($ml in $mLines) {
          if ($ml.StartsWith('script_version=')) { $mVer = $ml.Substring(15) }
          elseif ($ml.StartsWith('hooks_dir=')) { $mHooksDir = $ml.Substring(10) }
        }
        $mDir = Split-Path -Parent $wizManifest
        $cmOk = -not [string]::IsNullOrWhiteSpace($mHooksDir) -and (Test-Path -LiteralPath (Join-Path $mHooksDir 'commit-msg'))
        $ctlOk = Test-Path -LiteralPath (Join-Path $mDir 'fakeauthor.sh')
        if (-not $cmOk -or -not $ctlOk) {
          [Console]::WriteLine("fakeauthor: missing files detected ($mVer), will repair")
        } else {
          [Console]::WriteLine("fakeauthor: existing install detected ($mVer)")
        }
      }

      [Console]::WriteLine('fakeauthor - fake AI co-authors for git commits (parody)')
      if ($null -eq $scopeArg) {
        if ($inRepo) {
          $repoTop = (& $gitBin rev-parse --show-toplevel 2>$null | Select-Object -First 1)
          $repoName = if (-not [string]::IsNullOrWhiteSpace($repoTop)) { Split-Path -Leaf $repoTop.Trim() } else { Split-Path -Leaf (Get-Location).Path }
          [Console]::WriteLine('')
          $pickedScope = Show-ScopePicker -Title "1) Scope (repo: $repoName):" -Opt1 'All repos (global)' -Opt2 'This repo only (local .git/hooks)'
          if ($null -eq $pickedScope) {
            [Console]::WriteLine('Cancelled.')
            $script:FaRc = 0
            return
          }
          $scopeArg = if ($pickedScope -eq 1) { 'global' } else { 'local' }
        } else {
          $scopeArg = 'global'
        }
      }

      $initCsv = 'claude'
      try {
        $cfgCsv = (& $gitBin config "--$scopeArg" --get fakeauthor.persona 2>$null | Select-Object -First 1)
        if ($LASTEXITCODE -eq 0 -and -not [string]::IsNullOrWhiteSpace($cfgCsv)) {
          $initCsv = $cfgCsv.Trim()
        }
      } catch {}

      $pickedCsv = Show-PersonaPicker -InitCsv $initCsv
      if ($null -eq $pickedCsv) {
        [Console]::WriteLine('Cancelled.')
        $script:FaRc = 0
        return
      }

      $shArgs = @("--$scopeArg")
      if ($forceArg) { $shArgs += '--force' }
      $shArgs += $pickedCsv
      $env:FAKEAUTHOR_PREVIEW = '1'
      & $shExe $tmpSh @shArgs
      $script:FaRc = if ($null -eq $LASTEXITCODE) { 0 } else { [int]$LASTEXITCODE }
      return
    }

    if ($null -ne $ArgsList -and $ArgsList.Count -gt 0) {
      & $shExe $tmpSh @ArgsList
    } else {
      & $shExe $tmpSh
    }
    $script:FaRc = if ($null -eq $LASTEXITCODE) { 0 } else { [int]$LASTEXITCODE }
  } finally {
    if ($null -ne $tmpSh -and (Test-Path -LiteralPath $tmpSh)) {
      Remove-Item -LiteralPath $tmpSh -Force -ErrorAction SilentlyContinue
    }
    if ($hadPreview) {
      $env:FAKEAUTHOR_PREVIEW = $prevPreview
    } else {
      Remove-Item Env:FAKEAUTHOR_PREVIEW -ErrorAction SilentlyContinue
    }
    if ($hadHome) {
      $env:HOME = $prevHome
    } else {
      Remove-Item Env:HOME -ErrorAction SilentlyContinue
    }
  }
}

$script:FaRc = 0
if ($CliArgs.Count -gt 0) {
  Invoke-FakeAuthorInstall -ArgsList $CliArgs
} else {
  Invoke-FakeAuthorInstall
}
$global:LASTEXITCODE = $script:FaRc
if ($null -ne $MyInvocation.MyCommand -and $MyInvocation.MyCommand.CommandType -eq 'ExternalScript' -and -not [string]::IsNullOrEmpty($PSCommandPath)) {
  exit $script:FaRc
}
