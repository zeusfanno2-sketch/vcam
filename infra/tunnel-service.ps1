$ErrorActionPreference = 'Continue'
$root = 'F:\cong cu\vcam'
$infra = Join-Path $root 'infra'
$cf = Join-Path $infra 'cloudflared.exe'
$log = Join-Path $infra 'tunnel-run.log'
$serverTxt = Join-Path $root 'server.txt'

while ($true) {
    if (Test-Path $log) { Remove-Item $log -Force -ErrorAction SilentlyContinue }
    $p = Start-Process -FilePath $cf -ArgumentList 'tunnel','--url','http://127.0.0.1:8787','--no-autoupdate' `
        -RedirectStandardError $log -RedirectStandardOutput (Join-Path $infra 'tunnel-out.log') -PassThru -WindowStyle Hidden

    $url = $null
    for ($i = 0; $i -lt 60; $i++) {
        Start-Sleep -Milliseconds 700
        if (Test-Path $log) {
            $m = Select-String -Path $log -Pattern 'https://[a-z0-9\-]+\.trycloudflare\.com' -ErrorAction SilentlyContinue |
                 Select-Object -Last 1
            if ($m) { $url = $m.Matches[0].Value; break }
        }
    }

    if ($url) {
        Set-Content -Path $serverTxt -Value $url -Encoding ascii
        Push-Location $root
        git add server.txt 2>$null | Out-Null
        git commit -m "tunnel: $url" 2>$null | Out-Null
        git push 2>$null | Out-Null
        Pop-Location
        Add-Content -Path (Join-Path $infra 'tunnel-history.txt') -Value ("{0}  {1}" -f (Get-Date -Format s), $url)
    }

    Wait-Process -Id $p.Id -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 5
}
