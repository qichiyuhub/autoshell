$adapterName = "以太网"

Clear-Host
Write-Host "--- 网关/DNS 快速切换 ---" -ForegroundColor Cyan
Write-Host "[1] 切换为 10.1"
Write-Host "[2] 切换为 10.2"
Write-Host "[3] 切换为 10.3"
Write-Host "[9] 切换为 10.9"
Write-Host "[0] 切换为 10.10"
Write-Host "--------------------------"

Write-Host "请选择：" -NoNewline
$keyInfo = [System.Console]::ReadKey($false)
$choice = $keyInfo.KeyChar

$interface = Get-NetAdapter -Name $adapterName -ErrorAction SilentlyContinue
if (-not $interface) { exit }

function Set-GatewayAndDns([string]$gateway) {
    Remove-NetRoute -InterfaceIndex $interface.ifIndex -DestinationPrefix 0.0.0.0/0 -Confirm:$false -ErrorAction SilentlyContinue | Out-Null
    New-NetRoute -InterfaceIndex $interface.ifIndex -DestinationPrefix 0.0.0.0/0 -NextHop $gateway -ErrorAction SilentlyContinue | Out-Null
    Set-DnsClientServerAddress -InterfaceIndex $interface.ifIndex -ServerAddresses $gateway -ErrorAction SilentlyContinue | Out-Null
}

switch ($choice) {
    "1" { Set-GatewayAndDns "192.168.10.1" }
    "2" { Set-GatewayAndDns "192.168.10.2" }
    "3" { Set-GatewayAndDns "192.168.10.3" }
    "9" { Set-GatewayAndDns "192.168.10.9" }
    "0" { Set-GatewayAndDns "192.168.10.10" }
}