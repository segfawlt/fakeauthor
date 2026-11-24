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

function Invoke-FakeAuthorInstall {
  param([string[]]$ArgsList = @())

  $gitCmd = Get-Command git -ErrorAction SilentlyContinue
  if ($null -eq $gitCmd) {
    [Console]::Error.WriteLine('fakeauthor: git not found on PATH. Install Git for Windows: https://git-scm.com/download/win')
    return 1
  }
  $gitBin = if (-not [string]::IsNullOrWhiteSpace($gitCmd.Source)) { $gitCmd.Source } else { 'git' }

  $shExe = Find-GitBash -GitCmd $gitCmd
  if ([string]::IsNullOrWhiteSpace($shExe)) {
    [Console]::Error.WriteLine('fakeauthor: Git for Windows bundled sh.exe not found. Install/repair Git for Windows: https://git-scm.com/download/win')
    return 1
  }

  $hadHome = Test-Path Env:HOME
  $prevHome = $env:HOME
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
      return 1
    }

    $raw = ($raw -replace "`r`n", "`n") -replace "`r", ""
    $tmpSh = [IO.Path]::Combine([IO.Path]::GetTempPath(), 'fakeauthor-install-' + [Guid]::NewGuid().ToString('N') + '.sh')
    [IO.File]::WriteAllText($tmpSh, $raw, (New-Object System.Text.UTF8Encoding($false)))

    if ($null -ne $ArgsList -and $ArgsList.Count -gt 0) {
      & $shExe $tmpSh @ArgsList
    } else {
      & $shExe $tmpSh
    }
    if ($null -eq $LASTEXITCODE) { return 0 }
    return [int]$LASTEXITCODE
  } finally {
    if ($null -ne $tmpSh -and (Test-Path -LiteralPath $tmpSh)) {
      Remove-Item -LiteralPath $tmpSh -Force -ErrorAction SilentlyContinue
    }
    if ($hadHome) {
      $env:HOME = $prevHome
    } else {
      Remove-Item Env:HOME -ErrorAction SilentlyContinue
    }
  }
}

$faRc = if ($CliArgs.Count -gt 0) {
  Invoke-FakeAuthorInstall -ArgsList $CliArgs
} else {
  Invoke-FakeAuthorInstall
}
$global:LASTEXITCODE = $faRc
if ($null -ne $MyInvocation.MyCommand -and $MyInvocation.MyCommand.CommandType -eq 'ExternalScript' -and -not [string]::IsNullOrEmpty($PSCommandPath)) {
  exit $faRc
}
