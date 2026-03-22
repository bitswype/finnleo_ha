# Copyright 2026 Chris Keeser
# SPDX-License-Identifier: Apache-2.0

param([string]$IP, [int]$Port = 6668)
try {
    $c = New-Object System.Net.Sockets.TcpClient
    $c.Connect($IP, $Port)
    $s = $c.GetStream()
    $s.ReadTimeout = 5000
    $buf = New-Object byte[] 1024
    try {
        $n = $s.Read($buf, 0, 1024)
        Write-Host "Received $n bytes from ${IP}:${Port}:"
        Write-Host "Hex:" ([BitConverter]::ToString($buf[0..($n-1)]))
        Write-Host "ASCII:" ([Text.Encoding]::ASCII.GetString($buf[0..($n-1)]))
    } catch {
        Write-Host "${IP}:${Port} - Connected but no data received within 5s (device waiting for us to speak first)"
    }
    $c.Close()
} catch {
    Write-Host "${IP}:${Port} - Connection failed: $($_.Exception.Message)"
}
