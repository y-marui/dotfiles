Write-Host "=== $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') Update started ==="

winget upgrade --all --silent --accept-source-agreements --include-unknown

# Enable-WURemoting
Get-WindowsUpdate -Verbose
Install-WindowsUpdate -AcceptAll -Verbose

Write-Host "=== $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') Update completed ==="
