param(
  [string]$Mode,
  [string]$Code,
  [Parameter(ValueFromRemainingArguments = $true)][string[]]$Rest
)

function Start-CrocDrop {
  param([string]$Mode, [string]$Code, [string[]]$Rest)

  $ErrorActionPreference = 'Stop'
  $ProgressPreference = 'SilentlyContinue'
  [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

  $Version = '11.5.5'
  $Base = "https://github.com/schollz/croc/releases/download/v$Version"
  $Sums = @{
    'Windows-64bit' = 'b7d266bcce9d88beb4dee9d4f7f174382c5688bbb78832f557f8fc11586f0b10'
    'Windows-ARM64' = '867decb1c5bf2ddf9efd0455b8053ea57543f21c3044d7414b8c342ea8156f53'
    'Windows-32bit' = 'fd2190ccb38cb3372425d3b632fee0b412c4a55b42ec7bf5d117fecd577ba3f1'
  }

  if ($Mode -ne 'send' -and $Mode -ne 'receive') { Write-Host 'Unknown mode.'; return }
  if (-not $Code -or $Code.Length -lt 6) { Write-Host 'Missing or short code.'; return }

  $arch = if ($env:PROCESSOR_ARCHITEW6432) { $env:PROCESSOR_ARCHITEW6432 } else { $env:PROCESSOR_ARCHITECTURE }
  $asset = switch ($arch) {
    'AMD64' { 'Windows-64bit' }
    'ARM64' { 'Windows-ARM64' }
    'x86'   { 'Windows-32bit' }
    default { $null }
  }
  if (-not $asset) { Write-Host 'This computer type is not supported.'; return }

  function Wait-ForPaths {
    param([string[]]$Targets)
    $shown = $false
    while ($true) {
      $gone = $null
      foreach ($t in $Targets) {
        if (-not (Test-Path -LiteralPath $t)) { $gone = $t }
      }
      if (-not $gone) { return }
      if (-not $shown) {
        Write-Host ''
        Write-Host "Cannot find: $gone"
        Write-Host 'If it is on an external drive, make sure the drive is plugged in. Waiting for it to come back...'
        $shown = $true
      }
      Start-Sleep -Seconds 3
    }
  }

  $sandbox = Join-Path ([IO.Path]::GetTempPath()) ('crocdrop-' + [Guid]::NewGuid().ToString('N').Substring(0, 8))
  $keep = $false
  $oldAppData = $env:APPDATA
  $sleepBlocked = $false

  try {
    New-Item -ItemType Directory -Path $sandbox | Out-Null
    New-Item -ItemType Directory -Path (Join-Path $sandbox 'cfg') | Out-Null

    Write-Host ''
    Write-Host 'CrocDrop'
    Write-Host 'Getting ready (one-time download, about 9 MB)...'

    $zip = Join-Path $sandbox 'croc.zip'
    Invoke-WebRequest -UseBasicParsing -Uri "$Base/croc_v${Version}_$asset.zip" -OutFile $zip

    $got = (Get-FileHash -Algorithm SHA256 -Path $zip).Hash.ToLower()
    if ($got -ne $Sums[$asset]) { Write-Host 'The download did not pass the safety check.'; return }

    $bin = Join-Path $sandbox 'bin'
    Expand-Archive -Path $zip -DestinationPath $bin -Force
    $exe = Join-Path $bin 'croc.exe'
    if (-not (Test-Path $exe)) { Write-Host 'Could not unpack the download.'; return }

    $env:APPDATA = Join-Path $sandbox 'cfg'

    if (-not ('CrocDrop.Power' -as [type])) {
      Add-Type -Namespace CrocDrop -Name Power -MemberDefinition '[DllImport("kernel32.dll")] public static extern uint SetThreadExecutionState(uint f);'
    }
    [CrocDrop.Power]::SetThreadExecutionState([uint32]2147483649) | Out-Null
    $sleepBlocked = $true

    if ($Mode -eq 'send') {
      Add-Type -AssemblyName System.Windows.Forms
      $items = @()
      if ($Rest -and $Rest.Count -gt 0) {
        $items = @($Rest)
      } else {
        while ($true) {
          Write-Host ''
          Write-Host 'Drag the files or folder you want to send into this window,'
          Write-Host 'then press Enter. (Or just press Enter to browse.)'
          $line = Read-Host '>'
          $items = @()
          if ([string]::IsNullOrWhiteSpace($line)) {
            $owner = New-Object System.Windows.Forms.Form
            $owner.TopMost = $true
            $dlg = New-Object System.Windows.Forms.FolderBrowserDialog
            $dlg.Description = 'Choose the folder to send'
            if ($dlg.ShowDialog($owner) -eq 'OK') { $items = @($dlg.SelectedPath) }
            $owner.Dispose()
            if ($items.Count -eq 0) { Write-Host 'Nothing chosen.'; continue }
          } else {
            foreach ($m in [regex]::Matches($line, '"([^"]+)"|''([^'']+)''|(\S+)')) {
              $v = if ($m.Groups[1].Success) { $m.Groups[1].Value } elseif ($m.Groups[2].Success) { $m.Groups[2].Value } else { $m.Groups[3].Value }
              $items += $v
            }
          }
          $bad = $false
          foreach ($p in $items) {
            if (-not (Test-Path -LiteralPath $p)) { Write-Host "Cannot find: $p"; $bad = $true }
          }
          if (-not $bad -and $items.Count -gt 0) { break }
        }
      }

      Write-Host ''
      Write-Host 'Waiting for your friend to connect. Keep this window open.'
      $env:CROC_SECRET = $Code
      while ($true) {
        Wait-ForPaths $items
        & $exe --ignore-stdin --disable-clipboard send @items
        if ($LASTEXITCODE -eq 0) { break }
        Write-Host ''
        Write-Host 'Waiting to connect. Keep this window open. (Press Ctrl+C to stop)'
        Start-Sleep -Seconds 5
      }
      $doneMsg = 'All done. Your files were sent.'
    } else {
      $here = (Get-Location).ProviderPath
      if ($Rest -and $Rest.Count -gt 0) {
        $dest = $Rest[0]
      } elseif ($here -ne $env:USERPROFILE -and -not $here.StartsWith($env:windir, [StringComparison]::OrdinalIgnoreCase) -and (Test-Path -LiteralPath $here)) {
        $dest = $here
      } else {
        $dest = Join-Path $env:USERPROFILE 'Downloads\CrocDrop'
      }
      New-Item -ItemType Directory -Path $dest -Force | Out-Null
      Write-Host ''
      Write-Host "Files will be saved to: $dest"
      Write-Host 'Waiting for your friend to send. Keep this window open.'
      while ($true) {
        Wait-ForPaths @($dest)
        & $exe --yes --overwrite --disable-clipboard --out $dest $Code
        if ($LASTEXITCODE -eq 0) { break }
        Write-Host ''
        Write-Host 'Waiting to connect. Keep this window open. (Press Ctrl+C to stop)'
        Start-Sleep -Seconds 5
      }
      $doneMsg = "All done. Your files are in: $dest"
      Start-Process explorer.exe -ArgumentList "`"$dest`""
    }

    Write-Host ''
    Write-Host $doneMsg
    Write-Host ''
    $answer = Read-Host 'Your transferred files are safe and will not be touched. Clean up the small helper program CrocDrop used? Press Enter for yes, or type n to keep it'
    if ($answer -match '^(n|no)$') {
      $keep = $true
      Write-Host "Helper program kept at: $sandbox"
    } else {
      Write-Host 'Cleaned up. Your transferred files were not touched.'
    }
  }
  catch {
    Write-Host ''
    Write-Host "Sorry, something went wrong: $($_.Exception.Message)"
  }
  finally {
    Remove-Item Env:\CROC_SECRET -ErrorAction SilentlyContinue
    $env:APPDATA = $oldAppData
    if ($sleepBlocked) { [CrocDrop.Power]::SetThreadExecutionState([uint32]2147483648) | Out-Null }
    if (-not $keep -and (Test-Path $sandbox)) { Remove-Item -Recurse -Force $sandbox -ErrorAction SilentlyContinue }
  }
}

Start-CrocDrop -Mode $Mode -Code $Code -Rest $Rest
