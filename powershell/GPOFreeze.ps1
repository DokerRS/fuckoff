param(
    [Parameter(Mandatory=$true)]
    [ValidateSet("Freeze", "Unfreeze")]
    [string]$Mode
)

function Freeze-GPO {
    Write-Host "[1/5] Отключаем фоновое обновление GPO..." -ForegroundColor Cyan
    reg add "HKLM\SOFTWARE\Policies\Microsoft\Windows\System" /v GroupPolicyMinTransferRate /t REG_DWORD /d 0 /f > $null
    reg add "HKLM\SOFTWARE\Policies\Microsoft\Windows\System\GroupPolicy" /v DisableBkGndGroupPolicy /t REG_DWORD /d 1 /f > $null
    reg add "HKLM\SOFTWARE\Policies\Microsoft\Windows\System\GroupPolicy" /v SlowLink /t REG_DWORD /d 1 /f > $null

    Write-Host "[2/5] Блокируем доступ к папкам GroupPolicy..." -ForegroundColor Cyan
    takeown /f "C:\Windows\System32\GroupPolicy" /r /d y | Out-Null
    takeown /f "C:\Windows\System32\GroupPolicyUsers" /r /d y | Out-Null
    icacls "C:\Windows\System32\GroupPolicy" /inheritance:r | Out-Null
    icacls "C:\Windows\System32\GroupPolicy" /grant:r "Администраторы:(OI)(CI)F" | Out-Null
    icacls "C:\Windows\System32\GroupPolicy" /remove "SYSTEM" | Out-Null
    icacls "C:\Windows\System32\GroupPolicyUsers" /inheritance:r | Out-Null
    icacls "C:\Windows\System32\GroupPolicyUsers" /grant:r "Администраторы:(OI)(CI)F" | Out-Null
    icacls "C:\Windows\System32\GroupPolicyUsers" /remove "SYSTEM" | Out-Null

    Write-Host "[3/5] Блокируем SMB и RPC к контроллерам домена..." -ForegroundColor Cyan
    $domainName = (Get-CimInstance Win32_ComputerSystem).Domain
    if ($domainName -and $domainName -ne $env:COMPUTERNAME) {
        try {
            $nlOutput = nltest /dclist:$domainName 2>$null
            $dcList = @()
            foreach ($line in $nlOutput) {
                if ($line -match "\\") {
                    $server = ($line -split "\\")[-1].Trim()
                    if ($server) { $dcList += $server }
                }
            }
            if ($dcList.Count -gt 0) {
                foreach ($dc in $dcList) {
                    New-NetFirewallRule -DisplayName "Block GPO SMB $dc" -Direction Outbound -RemoteAddress $dc -Protocol TCP -RemotePort 445 -Action Block -ErrorAction SilentlyContinue
                    New-NetFirewallRule -DisplayName "Block GPO RPC $dc" -Direction Outbound -RemoteAddress $dc -Protocol TCP -RemotePort 135 -Action Block -ErrorAction SilentlyContinue
                }
            } else {
                Write-Host "Контроллеры домена не найдены — шаг пропущен" -ForegroundColor Yellow
            }
        } catch {
            Write-Host "Ошибка при получении списка DC — шаг пропущен" -ForegroundColor Yellow
        }
    } else {
        Write-Host "Машина не в домене — шаг пропущен" -ForegroundColor Yellow
    }

    Write-Host "[4/5] Отключаем gpsvc (служба политик групп)..." -ForegroundColor Cyan
    $regPath = "HKLM\SYSTEM\CurrentControlSet\Services\gpsvc"
    Start-Process -FilePath "reg.exe" -ArgumentList "add `"$regPath`" /v Start /t REG_DWORD /d 4 /f" -Verb RunAs -WindowStyle Hidden

    Write-Host "[5/5] Готово. Перезагрузите компьютер для применения." -ForegroundColor Green
}

function Unfreeze-GPO {
    Write-Host "[1/5] Восстанавливаем параметры GPO..." -ForegroundColor Cyan
    reg delete "HKLM\SOFTWARE\Policies\Microsoft\Windows\System" /v GroupPolicyMinTransferRate /f > $null
    reg delete "HKLM\SOFTWARE\Policies\Microsoft\Windows\System\GroupPolicy" /v DisableBkGndGroupPolicy /f > $null
    reg delete "HKLM\SOFTWARE\Policies\Microsoft\Windows\System\GroupPolicy" /v SlowLink /f > $null

    Write-Host "[2/5] Восстанавливаем права на папки GroupPolicy..." -ForegroundColor Cyan
    icacls "C:\Windows\System32\GroupPolicy" /reset /T | Out-Null
    icacls "C:\Windows\System32\GroupPolicyUsers" /reset /T | Out-Null

    Write-Host "[3/5] Удаляем правила брандмауэра..." -ForegroundColor Cyan
    Get-NetFirewallRule | Where-Object { $_.DisplayName -like "Block GPO*" } | Remove-NetFirewallRule

    Write-Host "[4/5] Включаем gpsvc обратно..." -ForegroundColor Cyan
    $regPath = "HKLM\SYSTEM\CurrentControlSet\Services\gpsvc"
    Start-Process -FilePath "reg.exe" -ArgumentList "add `"$regPath`" /v Start /t REG_DWORD /d 2 /f" -Verb RunAs -WindowStyle Hidden

    Write-Host "[5/5] Готово. Перезагрузите компьютер для применения." -ForegroundColor Green
}

if ($Mode -eq "Freeze") {
    Freeze-GPO
} elseif ($Mode -eq "Unfreeze") {
    Unfreeze-GPO
}
