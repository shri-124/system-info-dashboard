function Send-SystemInfo {
  param(
    [Parameter(Mandatory=$true)][string]$RunId,
    [Parameter(Mandatory=$true)][string]$Server
  )
  $ErrorActionPreference = 'Stop'

  try {
    $os = (Get-CimInstance Win32_OperatingSystem)
    $cs = (Get-CimInstance Win32_ComputerSystem)
    $cpu = (Get-CimInstance Win32_Processor | Select-Object -First 1)
    $ip = (Get-NetIPAddress -AddressFamily IPv4 | Where-Object {$_.IPAddress -notlike '169.*'} | Select-Object -ExpandProperty IPAddress -ErrorAction SilentlyContinue) -join ' '
    $disks = (Get-PSDrive -PSProvider FileSystem | Select-Object Name, @{n='Used(GB)';e={[math]::Round(($_.Used/1GB),1)}}, @{n='Free(GB)';e={[math]::Round(($_.Free/1GB),1)}})
    $procs = Get-Process | Sort-Object CPU -Descending | Select-Object -First 10 Id, ProcessName, CPU, PM

    $payload = [ordered]@{
      hostname   = $env:COMPUTERNAME
      os         = "$($os.Caption) $($os.Version)"
      uptime     = ((Get-Date) - $os.LastBootUpTime).ToString()
      ip_addrs   = $ip
      cpu_model  = $cpu.Name
      cores      = $cpu.NumberOfLogicalProcessors
      memory     = "{0:N1} GB total" -f ($cs.TotalPhysicalMemory/1GB)
      ts         = (Get-Date).ToString("o")
    }

    $json = $payload | ConvertTo-Json -Depth 5
    Invoke-RestMethod -Method Post -Uri "$Server/api/ingest/$RunId" -ContentType "application/json" -Body $json | Out-Null
    Write-Host "✅ Sent system info to $Server (run_id=$RunId)."
  }
  catch {
    Write-Host "❌ Failed: $($_.Exception.Message)"
    exit 1
  }
}

# If executed directly (not dot-sourced), don’t run automatically—index.html will call this as:
# iwr ${origin}/client.ps1 | iex; Send-SystemInfo -RunId '<RUN_ID>' -Server '<ORIGIN>'
