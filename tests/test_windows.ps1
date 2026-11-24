$ErrorActionPreference = 'Stop'

$RootDir = Split-Path -Parent $PSScriptRoot
$InstallPs1 = Join-Path $RootDir 'install.ps1'
$InstallSh = Join-Path $RootDir 'install.sh'

function Assert-True {
  param([bool]$Cond, [string]$Msg)
  if (-not $Cond) { throw "FAIL: $Msg" }
}

function Assert-Eq {
  param([string]$Expected, [string]$Actual, [string]$Msg)
  if ($Expected -ne $Actual) {
    throw "FAIL: $Msg`n  expected: '$Expected'`n  actual:   '$Actual'"
  }
}

function Assert-Contains {
  param([string]$Needle, [string]$Haystack, [string]$Msg)
  if ($null -eq $Haystack -or -not $Haystack.Contains($Needle)) {
    throw "FAIL: $Msg`n  missing: '$Needle'`n  actual:  '$Haystack'"
  }
}

function Assert-LfNoBom {
  param([string]$Path, [string]$Msg)
  Assert-True (Test-Path -LiteralPath $Path) "$Msg (missing $Path)"
  $bytes = [IO.File]::ReadAllBytes($Path)
  if ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) {
    throw "FAIL: $Msg (UTF-8 BOM found in $Path)"
  }
  if ($bytes -contains 13) {
    throw "FAIL: $Msg (CR byte found in $Path)"
  }
}

function Invoke-Git {
  param([Parameter(ValueFromRemainingArguments = $true)][string[]]$GitArgs)
  $prevEap = $ErrorActionPreference
  $ErrorActionPreference = 'Continue'
  try {
    $out = & git @GitArgs 2>&1
    $rc = $LASTEXITCODE
    if ($rc -ne 0) {
      $joined = ($out | ForEach-Object { $_.ToString() }) -join "`n"
      throw "FAIL: git $($GitArgs -join ' ') exited $rc`n$joined"
    }
    return (($out | ForEach-Object { $_.ToString() }) -join "`n").TrimEnd("`r", "`n")
  } finally {
    $ErrorActionPreference = $prevEap
  }
}

function New-TestRepo {
  param([string]$RepoPath)
  New-Item -ItemType Directory -Force -Path $RepoPath | Out-Null
  Invoke-Git -C $RepoPath init -b main | Out-Null
  Invoke-Git -C $RepoPath config user.name user | Out-Null
  Invoke-Git -C $RepoPath config user.email user@example.com | Out-Null
}

$envNames = @(
  'HOME', 'XDG_CONFIG_HOME', 'GIT_CONFIG_NOSYSTEM', 'GIT_CONFIG_GLOBAL',
  'FAKEAUTHOR_DIR', 'NO_FAKEAUTHOR', 'FAKEAUTHOR_TTY', 'FAKEAUTHOR_INSTALL_SH_URL'
)
$savedEnv = @{}
foreach ($n in $envNames) {
  $savedEnv[$n] = [Environment]::GetEnvironmentVariable($n, 'Process')
}
$savedCwd = Get-Location
$sandbox = Join-Path ([IO.Path]::GetTempPath()) ('fa-win-' + [Guid]::NewGuid().ToString('N'))

try {
  $homeDir = Join-Path $sandbox 'home'
  $xdgDir = Join-Path $sandbox 'xdg'
  $repoDir = Join-Path $sandbox 'repo'
  New-Item -ItemType Directory -Force -Path $homeDir, $xdgDir | Out-Null

  $env:HOME = $homeDir
  $env:XDG_CONFIG_HOME = $xdgDir
  $env:GIT_CONFIG_NOSYSTEM = '1'
  Remove-Item Env:GIT_CONFIG_GLOBAL -ErrorAction SilentlyContinue
  Remove-Item Env:FAKEAUTHOR_DIR -ErrorAction SilentlyContinue
  Remove-Item Env:NO_FAKEAUTHOR -ErrorAction SilentlyContinue
  Remove-Item Env:FAKEAUTHOR_TTY -ErrorAction SilentlyContinue
  Remove-Item Env:FAKEAUTHOR_INSTALL_SH_URL -ErrorAction SilentlyContinue

  New-TestRepo -RepoPath $repoDir
  Set-Location $sandbox

  # 1. Global install via install.ps1 with multi-persona
  & $InstallPs1 claude,codex
  Assert-Eq '0' ([string]$LASTEXITCODE) 'install.ps1 claude,codex exits 0'

  $faDir = Join-Path $homeDir '.local\share\fakeauthor'
  Assert-LfNoBom (Join-Path $faDir 'hooks\commit-msg') 'generated commit-msg is LF without BOM'
  Assert-LfNoBom (Join-Path $faDir 'fakeauthor.sh') 'generated fakeauthor.sh is LF without BOM'
  Assert-LfNoBom (Join-Path $faDir 'manifest') 'generated manifest is LF without BOM'

  $hpRaw = Invoke-Git config --global --get core.hooksPath
  Assert-True (-not $hpRaw.Contains('\')) "core.hooksPath uses forward slashes ($hpRaw)"

  [IO.File]::WriteAllText((Join-Path $repoDir 'w1.txt'), "w1`n")
  Invoke-Git -C $repoDir add w1.txt | Out-Null
  Invoke-Git -C $repoDir commit -m 'win test' | Out-Null
  $tr1 = Invoke-Git -C $repoDir log -1 '--pretty=%(trailers)'
  Assert-Contains 'Co-Authored-By: Claude <noreply@anthropic.com>' $tr1 'Windows commit includes Claude'
  Assert-Contains 'Co-authored-by: Codex <noreply@openai.com>' $tr1 'Windows commit includes Codex'

  # 2. git -c fakeauthor.off=true skips trailer
  [IO.File]::WriteAllText((Join-Path $repoDir 'w2.txt'), "w2`n")
  Invoke-Git -C $repoDir add w2.txt | Out-Null
  Invoke-Git -C $repoDir -c fakeauthor.off=true commit -m 'honest win' | Out-Null
  $tr2 = Invoke-Git -C $repoDir log -1 '--pretty=%(trailers)'
  Assert-Eq '' $tr2 '-c fakeauthor.off=true skips trailer on Windows'

  # 3. git fakeauthor status / off / on / devin / git devin commit
  $st = Invoke-Git -C $repoDir fakeauthor status
  Assert-Contains 'active (global)' $st 'status shows active (global)'

  Invoke-Git -C $repoDir fakeauthor off | Out-Null
  Assert-Contains 'paused (global)' (Invoke-Git -C $repoDir fakeauthor status) 'off pauses repo'
  Invoke-Git -C $repoDir fakeauthor on | Out-Null
  Assert-Contains 'active (global)' (Invoke-Git -C $repoDir fakeauthor status) 'on resumes repo'

  Invoke-Git fakeauthor devin | Out-Null
  [IO.File]::WriteAllText((Join-Path $repoDir 'wd.txt'), "wd`n")
  Invoke-Git -C $repoDir add wd.txt | Out-Null
  Invoke-Git -C $repoDir devin commit -m 'win devin' | Out-Null
  $who = Invoke-Git -C $repoDir log -1 '--format=%an <%ae>'
  Assert-Eq 'Devin <158243242+devin-ai-integration[bot]@users.noreply.github.com>' $who 'git devin sets Devin author'
  $trDevin = Invoke-Git -C $repoDir log -1 '--pretty=%(trailers)'
  Assert-Eq '' $trDevin 'git devin skips trailer'

  # 4. git fakeauthor uninstall cleans up completely
  Invoke-Git fakeauthor uninstall | Out-Null
  Assert-True (-not (Test-Path -LiteralPath $faDir)) 'uninstall removes ~/.local/share/fakeauthor'
  $prevEap = $ErrorActionPreference
  $ErrorActionPreference = 'Continue'
  & git config --global --get core.hooksPath *> $null
  $hpRc = $LASTEXITCODE
  $ErrorActionPreference = $prevEap
  Assert-True ($hpRc -ne 0) 'uninstall unsets global core.hooksPath'

  # 5. --local install inside repo + uninstall
  Set-Location $repoDir
  & $InstallPs1 --local cursor
  Assert-Eq '0' ([string]$LASTEXITCODE) 'install.ps1 --local cursor exits 0'
  $prevEap = $ErrorActionPreference
  $ErrorActionPreference = 'Continue'
  & git config --global --get core.hooksPath *> $null
  $hpLocalRc = $LASTEXITCODE
  $ErrorActionPreference = $prevEap
  Assert-True ($hpLocalRc -ne 0) '--local leaves global core.hooksPath unset'

  [IO.File]::WriteAllText((Join-Path $repoDir 'wl.txt'), "wl`n")
  Invoke-Git -C $repoDir add wl.txt | Out-Null
  Invoke-Git -C $repoDir commit -m 'win local' | Out-Null
  $trLoc = Invoke-Git -C $repoDir log -1 '--pretty=%(trailers)'
  Assert-Eq 'Co-authored-by: Cursor <cursoragent@cursor.com>' $trLoc '--local commit appends Cursor trailer'
  Invoke-Git -C $repoDir fakeauthor uninstall | Out-Null
  Assert-True (-not (Test-Path -LiteralPath (Join-Path $repoDir '.git\fakeauthor-manifest'))) '--local uninstall removes manifest'

  # 6. Interactive line-mode via FAKEAUTHOR_TTY containing CRLF
  $ttyFile = Join-Path $sandbox 'tty_crlf.txt'
  [IO.File]::WriteAllText($ttyFile, "2`r`n1,3`r`n`r`n", (New-Object System.Text.UTF8Encoding($false)))
  $env:FAKEAUTHOR_TTY = $ttyFile
  & $InstallPs1
  Assert-Eq '0' ([string]$LASTEXITCODE) 'install.ps1 interactive CRLF FAKEAUTHOR_TTY exits 0'
  $locPersona = Invoke-Git -C $repoDir config --local --get fakeauthor.persona
  Assert-Eq 'codex' $locPersona 'CRLF FAKEAUTHOR_TTY toggles claude off and codex on'
  Invoke-Git -C $repoDir fakeauthor uninstall | Out-Null
  Remove-Item Env:FAKEAUTHOR_TTY -ErrorAction SilentlyContinue

  # 7. iex-style invocation (empty $PSCommandPath + HTTP fetch) must NOT terminate host process
  $repoIex = Join-Path $sandbox 'repo-iex'
  New-TestRepo -RepoPath $repoIex
  Set-Location $repoIex

  $ttyIex = Join-Path $sandbox 'tty_iex.txt'
  [IO.File]::WriteAllText($ttyIex, "2`r`n5`r`n`r`n", (New-Object System.Text.UTF8Encoding($false)))
  $env:FAKEAUTHOR_TTY = $ttyIex

  $listener = New-Object Net.Sockets.TcpListener([Net.IPAddress]::Loopback, 0)
  $listener.Start()
  $port = ([Net.IPEndPoint]$listener.LocalEndpoint).Port

  $rs = [RunspaceFactory]::CreateRunspace()
  $rs.Open()
  $psSrv = [PowerShell]::Create()
  $psSrv.Runspace = $rs
  [void]$psSrv.AddScript({
    param($L, $ShPath)
    try {
      $client = $L.AcceptTcpClient()
      $stream = $client.GetStream()
      $reader = New-Object IO.StreamReader($stream, [Text.Encoding]::ASCII, $false, 1024, $true)
      while ($true) {
        $line = $reader.ReadLine()
        if ($null -eq $line -or $line -eq '') { break }
      }
      $body = [IO.File]::ReadAllBytes($ShPath)
      $hdr = "HTTP/1.1 200 OK`r`nContent-Type: text/plain; charset=utf-8`r`nContent-Length: $($body.Length)`r`nConnection: close`r`n`r`n"
      $hdrBytes = [Text.Encoding]::ASCII.GetBytes($hdr)
      $stream.Write($hdrBytes, 0, $hdrBytes.Length)
      $stream.Write($body, 0, $body.Length)
      $stream.Flush()
      $client.Close()
    } finally {
      $L.Stop()
    }
  }).AddArgument($listener).AddArgument($InstallSh)
  $asyncSrv = $psSrv.BeginInvoke()

  $env:FAKEAUTHOR_INSTALL_SH_URL = "http://127.0.0.1:$port/install.sh"
  $ps1Raw = [IO.File]::ReadAllText($InstallPs1)
  & ([scriptblock]::Create($ps1Raw))
  $iexRc = $LASTEXITCODE
  [void]$psSrv.EndInvoke($asyncSrv)
  $psSrv.Dispose()
  $rs.Dispose()

  Assert-Eq '0' ([string]$iexRc) 'iex invocation exited 0 without killing host process'
  $iexPersona = Invoke-Git -C $repoIex config --local --get fakeauthor.persona
  Assert-Eq 'claude,aider' $iexPersona 'iex invocation persisted local persona via HTTP install.sh'
  Invoke-Git -C $repoIex fakeauthor uninstall | Out-Null

  Write-Host 'ok: test_windows.ps1 passed'
} finally {
  Set-Location $savedCwd
  foreach ($n in $envNames) {
    if ($null -eq $savedEnv[$n]) {
      Remove-Item "Env:$n" -ErrorAction SilentlyContinue
    } else {
      [Environment]::SetEnvironmentVariable($n, $savedEnv[$n], 'Process')
    }
  }
  if (Test-Path -LiteralPath $sandbox) {
    Remove-Item -LiteralPath $sandbox -Recurse -Force -ErrorAction SilentlyContinue
  }
}
