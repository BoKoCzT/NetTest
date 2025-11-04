# Základné nastavenia
$logDir = "C:\NetworkLogs"
if (-not (Test-Path $logDir)) { New-Item -Path $logDir -ItemType Directory | Out-Null }
$ts = (Get-Date).ToString("yyyyMMdd_HHmmss")
$log = Join-Path $logDir "netlog_$ts.txt"
$hashFile = $log + ".sha256"

# Pomocné funkcie
function Write-SectionHeader {
    param([string]$title)
    $line = ("=" * 60)
    "$line`n$title`n$line" | Out-File $log -Append -Encoding UTF8
}

function Append-CommandOutput {
    param([scriptblock]$cmd)
    & $cmd 2>&1 | Out-File $log -Append -Encoding UTF8
}

# Hlavný záznam - identita a čas
"Timestamp: $ts" | Out-File $log -Encoding UTF8
"Hostname: $(hostname)" | Out-File $log -Append -Encoding UTF8
"User: $env:USERNAME" | Out-File $log -Append -Encoding UTF8
"" | Out-File $log -Append -Encoding UTF8

# Sekcia: IP konfigurácia a adaptéry
Write-SectionHeader "IP CONFIGURATION AND ADAPTERS"
Append-CommandOutput { ipconfig /all }
"" | Out-File $log -Append -Encoding UTF8
Append-CommandOutput { Get-NetAdapter | Format-Table -AutoSize }
Append-CommandOutput { Get-NetIPConfiguration | Format-List }
Append-CommandOutput { Get-NetAdapterStatistics | Format-List }
"" | Out-File $log -Append -Encoding UTF8

# Sekcia: Lokálna LAN dostupnosť (ping na gateway)
Write-SectionHeader "LOCAL GATEWAY PING"
# Snažíme sa zistiť gateway z IP konfigurácie
$gw = (Get-NetIPConfiguration | Where-Object { $_.IPv4DefaultGateway -ne $null } | Select-Object -First 1).IPv4DefaultGateway.NextHop
if (-not $gw) { $gw = "NoGatewayFound" }
"Detected gateway: $gw" | Out-File $log -Append -Encoding UTF8
if ($gw -ne "NoGatewayFound") {
    Append-CommandOutput { ping -n 4 $gw }
} else {
    "Gateway not detected; skipping ping" | Out-File $log -Append -Encoding UTF8
}
"" | Out-File $log -Append -Encoding UTF8

# Sekcia: Internet dostupnosť - ICMP a TCP a DNS
Write-SectionHeader "INTERNET CONNECTIVITY TESTS"
$publicIp = "8.8.8.8"
"Ping $publicIp (ICMP):" | Out-File $log -Append -Encoding UTF8
Append-CommandOutput { ping -n 4 $publicIp }
"" | Out-File $log -Append -Encoding UTF8

"Test-NetConnection TCP test (port 53) to $publicIp:" | Out-File $log -Append -Encoding UTF8
Append-CommandOutput { Test-NetConnection -ComputerName $publicIp -Port 53 -InformationLevel Detailed }
"" | Out-File $log -Append -Encoding UTF8

"DNS resolution test (Resolve example.com):" | Out-File $log -Append -Encoding UTF8
Append-CommandOutput { Resolve-DnsName example.com -ErrorAction SilentlyContinue }
if ($LASTEXITCODE -ne 0) { "Resolve-DnsName returned non-zero exit code" | Out-File $log -Append -Encoding UTF8 }
"" | Out-File $log -Append -Encoding UTF8

# Sekcia: traceroute
Write-SectionHeader "TRACEROUTE TO $publicIp"
Append-CommandOutput { tracert $publicIp }
"" | Out-File $log -Append -Encoding UTF8

# Sekcia: Aktívne spojenia a procesy
Write-SectionHeader "ACTIVE CONNECTIONS (NETSTAT) AND RELATED PROCESSES"
Append-CommandOutput { netstat -ano }
# netstat -b vyžaduje admin; ak nie sú práva, vypíše to chybu do logu
Append-CommandOutput { netstat -b 2>&1 }
"" | Out-File $log -Append -Encoding UTF8

# Sekcia: Relevantné Windows Event logy za poslednú hodinu
Write-SectionHeader "SYSTEM EVENTS (LAST 1 HOUR) - Errors and Warnings"
$since = (Get-Date).AddHours(-1)
Get-WinEvent -FilterHashtable @{LogName='System'; StartTime=$since; Level=@(2,3)} -ErrorAction SilentlyContinue | Format-List | Out-File $log -Append -Encoding UTF8
"" | Out-File $log -Append -Encoding UTF8

# Vypočítaj hash súboru
Get-FileHash $log -Algorithm SHA256 | Format-List | Out-File $hashFile -Encoding UTF8

# Vyhodnotenie základnej konektivity pre MessageBox
# Kritériá: úspešný ping na public IP alebo Test-NetConnection.Success a DNS rezolúcia
$pingResult = Test-Connection -Count 2 -Quiet -ComputerName $publicIp
$tcpCheck = (Test-NetConnection -ComputerName $publicIp -Port 53).TcpTestSucceeded
$dnsResolve = $false
try {
    $r = Resolve-DnsName example.com -ErrorAction Stop
    if ($r) { $dnsResolve = $true }
} catch { $dnsResolve = $false }

$ok = $pingResult -or $tcpCheck -or $dnsResolve

# Zobraz MessageBox s výsledkom
Add-Type -AssemblyName System.Windows.Forms
if ($ok) {
    [System.Windows.Forms.MessageBox]::Show("Konektivita: OK`nPing: $pingResult  TCP53: $tcpCheck  DNS: $dnsResolve", "Network Check", 'OK', 'Information') | Out-Null
} else {
    [System.Windows.Forms.MessageBox]::Show("Konektivita: PROBLÉM`nPing: $pingResult  TCP53: $tcpCheck  DNS: $dnsResolve", "Network Check", 'OK', 'Warning') | Out-Null
}

# Informácie kde sú uložené výsledky
"Log saved: $log" | Out-File $log -Append -Encoding UTF8
"Hash saved: $hashFile" | Out-File $log -Append -Encoding UTF8