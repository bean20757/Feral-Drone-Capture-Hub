$ErrorActionPreference = "Stop"

$timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
$contracts = "C:\EVE Project\builder-examples\smart-turret\packages\contracts"
$log = Join-Path $contracts ("judge-validation-" + $timestamp + ".log")

Set-Location $contracts

"=== Smart Turret Judge Validation ===" | Tee-Object -FilePath $log
("Timestamp: " + (Get-Date -Format o)) | Tee-Object -FilePath $log -Append
"" | Tee-Object -FilePath $log -Append

"[1/3] Compile" | Tee-Object -FilePath $log -Append
forge build 2>&1 | Tee-Object -FilePath $log -Append
"" | Tee-Object -FilePath $log -Append

"[2/3] Full tests" | Tee-Object -FilePath $log -Append
forge test -vv 2>&1 | Tee-Object -FilePath $log -Append
"" | Tee-Object -FilePath $log -Append

"[3/3] Demo script broadcast" | Tee-Object -FilePath $log -Append
forge script script/TriggerCapture.s.sol --rpc-url http://127.0.0.1:8546 --broadcast 2>&1 | Tee-Object -FilePath $log -Append
"" | Tee-Object -FilePath $log -Append

("Validation log saved: " + $log) | Tee-Object -FilePath $log -Append
Write-Host "Validation complete. Log: $log"
