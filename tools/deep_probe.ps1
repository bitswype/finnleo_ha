param([string]$IP, [int]$Port = 6668)

function Probe-Protocol {
    param([string]$Name, [byte[]]$Data)
    try {
        $c = New-Object System.Net.Sockets.TcpClient
        $c.Connect($IP, $Port)
        $s = $c.GetStream()
        $s.ReadTimeout = 3000
        $s.WriteTimeout = 3000

        # Send probe
        $s.Write($Data, 0, $Data.Length)
        $s.Flush()

        Start-Sleep -Milliseconds 500

        $buf = New-Object byte[] 4096
        try {
            $n = $s.Read($buf, 0, 4096)
            $hex = [BitConverter]::ToString($buf[0..($n-1)])
            $ascii = [Text.Encoding]::ASCII.GetString($buf[0..($n-1)]) -replace '[^\x20-\x7E]', '.'
            Write-Host "[$Name] Got $n bytes!"
            Write-Host "  Hex: $hex"
            Write-Host "  ASCII: $ascii"
        } catch {
            Write-Host "[$Name] Sent OK, no response within 3s"
        }
        $c.Close()
    } catch {
        Write-Host "[$Name] Failed: $($_.Exception.Message)"
    }
}

Write-Host "=== Probing ${IP}:${Port} ==="
Write-Host ""

# 1. HTTP GET
$httpGet = [Text.Encoding]::ASCII.GetBytes("GET / HTTP/1.1`r`nHost: ${IP}`r`n`r`n")
Probe-Protocol "HTTP GET" $httpGet

# 2. HTTP GET on /status (common IoT endpoint)
$httpStatus = [Text.Encoding]::ASCII.GetBytes("GET /status HTTP/1.1`r`nHost: ${IP}`r`n`r`n")
Probe-Protocol "HTTP /status" $httpStatus

# 3. MQTT CONNECT packet
$mqtt = [byte[]]@(0x10, 0x0E, 0x00, 0x04, 0x4D, 0x51, 0x54, 0x54, 0x04, 0x02, 0x00, 0x3C, 0x00, 0x02, 0x68, 0x61)
Probe-Protocol "MQTT CONNECT" $mqtt

# 4. Single newline
Probe-Protocol "Newline" ([byte[]]@(0x0A))

# 5. JSON hello
$json = [Text.Encoding]::ASCII.GetBytes('{"type":"hello"}' + "`n")
Probe-Protocol "JSON hello" $json

# 6. Huum-style 0x0B greeting (what if it speaks Sauna360 protocol?)
$huumGreet = [byte[]]@(0x0B, 0x00, 0x00, 0x00, 0x00, 0x00)
Probe-Protocol "Binary 0x0B greeting" $huumGreet

# 7. Huum-style 0x02 ping frequency set
$huumPing = [byte[]]@(0x02, 0x00, 0x00, 0x00, 0x00, 0x3C, 0x00)
Probe-Protocol "Binary 0x02 ping" $huumPing

# 8. Just a null byte
Probe-Protocol "Null byte" ([byte[]]@(0x00))

# 9. Sauna360 RS485-style frame (SOF 0x98)
$rs485 = [byte[]]@(0x98, 0x40, 0x09, 0x00, 0x00, 0x00, 0x00, 0x00, 0x9C)
Probe-Protocol "RS485-style frame" $rs485

# 10. TLS ClientHello probe (just first few bytes to see if it responds with TLS)
$tlsProbe = [byte[]]@(0x16, 0x03, 0x01, 0x00, 0x05, 0x01, 0x00, 0x00, 0x01, 0x00)
Probe-Protocol "TLS ClientHello" $tlsProbe
