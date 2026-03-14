#Requires -Version 5.1
<#
.SYNOPSIS
    Goldfish POS Cash Drawer Bridge  —  PowerShell edition
    Runs as a background HTTP server on http://127.0.0.1:8765/

    No Python, no pip, no extra installs.
    Windows PowerShell 5.1 is pre-installed on every Windows 10/11 PC.

    Endpoints:
      GET  /status       – confirm the bridge is running
      GET  /printers     – list installed Windows printers
      POST /open-drawer  – send ESC/POS kick to the cash drawer
      POST /print        – print a receipt via ESC/POS

.USAGE
    Normally started automatically at logon by the Windows Task Scheduler.
    To run manually / debug: double-click run_bridge_debug.bat
#>

param(
    [int]   $Port = 8765,
    [string]$PrinterName = ''      # blank = Windows default printer
)

# ── ESC/POS kick command (drawer port 0, ~50 ms pulse) ───────────────────────
$KickCommand = [byte[]](0x1B, 0x70, 0x00, 0x19, 0xFA)

# ── Logging ───────────────────────────────────────────────────────────────────
$AppDir = Join-Path $env:APPDATA 'GoldfishPOS'
$null = New-Item -ItemType Directory -Force -Path $AppDir
$LogFile = Join-Path $AppDir 'bridge.log'

function Write-Log {
    param([string]$Level, [string]$Msg)
    $entry = '{0}  {1,-7}  {2}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Level, $Msg
    Add-Content -Path $LogFile -Value $entry -Encoding UTF8
    Write-Host $entry
}

# ── Windows winspool.drv via C# P/Invoke (raw printer access, no extra libs) ─
Add-Type -Language CSharp -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
using System.Text;

public static class WinSpool {
    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
    struct DOC_INFO_1 {
        public string pDocName;
        public string pOutputFile;
        public string pDatatype;
    }

    [DllImport("winspool.drv", CharSet = CharSet.Unicode, SetLastError = true)]
    static extern bool OpenPrinter(string szPrinter, out IntPtr hPrinter, IntPtr pDefault);

    [DllImport("winspool.drv", CharSet = CharSet.Unicode, SetLastError = true)]
    static extern int StartDocPrinter(IntPtr hPrinter, int Level, ref DOC_INFO_1 info);

    [DllImport("winspool.drv", SetLastError = true)]
    static extern bool StartPagePrinter(IntPtr hPrinter);

    [DllImport("winspool.drv", SetLastError = true)]
    static extern bool WritePrinter(IntPtr hPrinter, byte[] pBuf, int cbBuf, out int pcWritten);

    [DllImport("winspool.drv", SetLastError = true)]
    static extern bool EndPagePrinter(IntPtr hPrinter);

    [DllImport("winspool.drv", SetLastError = true)]
    static extern int EndDocPrinter(IntPtr hPrinter);

    [DllImport("winspool.drv", SetLastError = true)]
    static extern bool ClosePrinter(IntPtr hPrinter);

    [DllImport("winspool.drv", CharSet = CharSet.Unicode, SetLastError = true)]
    static extern bool GetDefaultPrinter(StringBuilder pszBuffer, ref int pcchBuffer);

    public static string GetDefaultPrinterName() {
        int size = 256;
        var buf = new StringBuilder(size);
        if (!GetDefaultPrinter(buf, ref size))
            throw new Exception("No default printer configured. Set one in Windows Settings -> Printers & scanners.");
        return buf.ToString();
    }

    public static void SendRaw(string printerName, byte[] data) {
        IntPtr hPrinter;
        if (!OpenPrinter(printerName, out hPrinter, IntPtr.Zero))
            throw new Exception(string.Format(
                "OpenPrinter(\"{0}\") failed — Windows error {1}. Is the printer installed?",
                printerName, Marshal.GetLastWin32Error()));
        try {
            var doc = new DOC_INFO_1 { pDocName = "GoldfishPOS", pDatatype = "RAW" };
            int job = StartDocPrinter(hPrinter, 1, ref doc);
            if (job == 0) throw new Exception("StartDocPrinter failed: " + Marshal.GetLastWin32Error());
            try {
                StartPagePrinter(hPrinter);
                int written;
                WritePrinter(hPrinter, data, data.Length, out written);
                EndPagePrinter(hPrinter);
            } finally { EndDocPrinter(hPrinter); }
        } finally { ClosePrinter(hPrinter); }
    }
}
'@ -ErrorAction Stop

# ── Helper: resolve effective printer name ────────────────────────────────────
function Get-PrinterNameToUse {
    if ($PrinterName) { return $PrinterName }
    return [WinSpool]::GetDefaultPrinterName()
}

# ── Open cash drawer ──────────────────────────────────────────────────────────
function Invoke-OpenDrawer {
    try {
        $name = Get-PrinterNameToUse
        Write-Log 'INFO' "Opening drawer via printer: $name"
        [WinSpool]::SendRaw($name, $KickCommand)
        Write-Log 'INFO' 'Drawer opened OK.'
        return @{ ok = $true; message = 'ok' }
    }
    catch {
        $msg = $_.Exception.Message
        Write-Log 'ERROR' "open_drawer: $msg"
        return @{ ok = $false; message = $msg }
    }
}

# ── List installed printers ───────────────────────────────────────────────────
function Get-PrinterList {
    try {
        $names = @(Get-Printer | Select-Object -ExpandProperty Name)
        return @{ ok = $true; printers = $names }
    }
    catch {
        Write-Log 'ERROR' "get_printers: $($_.Exception.Message)"
        return @{ ok = $true; printers = @() }
    }
}

# ── Print ESC/POS receipt ─────────────────────────────────────────────────────
function Invoke-PrintReceipt {
    param($Data)
    try {
        $printerName = if ($Data.printer) { "$($Data.printer)" } else { Get-PrinterNameToUse }

        [byte]$ESC = 0x1B; [byte]$GS = 0x1D; [byte]$LF = 0x0A
        $INIT = [byte[]]($ESC, 0x40)
        $LEFT = [byte[]]($ESC, 0x61, 0x00); $CTR = [byte[]]($ESC, 0x61, 0x01); $RIGHT = [byte[]]($ESC, 0x61, 0x02)
        $BON = [byte[]]($ESC, 0x45, 0x01); $BOFF = [byte[]]($ESC, 0x45, 0x00)
        $SZ1 = [byte[]]($GS, 0x21, 0x00); $SZ2 = [byte[]]($GS, 0x21, 0x11)
        $CUT = [byte[]]($GS, 0x56, 0x41, 0x00)
        $SEP = [System.Text.Encoding]::ASCII.GetBytes(('-' * 42))

        $out = [System.Collections.Generic.List[byte]]::new()
        $out.AddRange($INIT)

        foreach ($ln in @($Data.lines)) {
            if ($ln.cut) { $out.AddRange($CUT); continue }
            if ($ln.separator) { $out.AddRange($LEFT); $out.AddRange($SZ1); $out.AddRange($BOFF); $out.AddRange($SEP); $out.Add($LF); continue }

            switch ("$($ln.align)") {
                'center' { $out.AddRange($CTR) }
                'right' { $out.AddRange($RIGHT) }
                default { $out.AddRange($LEFT) }
            }
            if (($ln.size -as [int]) -ge 2) { $out.AddRange($SZ2) } else { $out.AddRange($SZ1) }
            if ($ln.bold -eq $true) { $out.AddRange($BON) } else { $out.AddRange($BOFF) }
            $text = if ($ln.text) { "$($ln.text)" } else { '' }
            $out.AddRange([System.Text.Encoding]::UTF8.GetBytes($text))
            $out.Add($LF)
        }
        $out.AddRange($LEFT); $out.AddRange($SZ1); $out.AddRange($BOFF)

        [WinSpool]::SendRaw($printerName, $out.ToArray())
        Write-Log 'INFO' "Receipt printed OK on $printerName"
        return @{ ok = $true; message = 'ok' }
    }
    catch {
        $msg = $_.Exception.Message
        Write-Log 'ERROR' "print_receipt: $msg"
        return @{ ok = $false; message = $msg }
    }
}

# ── HTTP JSON response helper ─────────────────────────────────────────────────
function Send-JsonResponse {
    param($Context, [int]$StatusCode, $Body)
    $json = ConvertTo-Json $Body -Compress -Depth 10
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($json)
    $res = $Context.Response
    $res.StatusCode = $StatusCode
    $res.ContentType = 'application/json'
    $res.ContentLength64 = $bytes.LongLength
    $res.Headers.Add('Access-Control-Allow-Origin', '*')
    $res.Headers.Add('Access-Control-Allow-Methods', 'GET, POST, OPTIONS')
    $res.Headers.Add('Access-Control-Allow-Headers', 'Content-Type')
    $res.OutputStream.Write($bytes, 0, $bytes.Length)
    $res.OutputStream.Close()
}

# ── Start HTTP listener ───────────────────────────────────────────────────────
Write-Log 'INFO' ('=' * 55)
Write-Log 'INFO' 'Goldfish POS Cash Drawer Bridge  (PowerShell — no Python needed)'
Write-Log 'INFO' "Port : $Port  |  Log : $LogFile"
Write-Log 'INFO' ('=' * 55)

$listener = [System.Net.HttpListener]::new()
$listener.Prefixes.Add("http://127.0.0.1:$Port/")
try {
    $listener.Start()
    Write-Log 'INFO' "Listening on http://127.0.0.1:$Port/"
}
catch {
    Write-Log 'ERROR' "Cannot start listener on port $Port`: $($_.Exception.Message)"
    Write-Log 'ERROR' 'If you see "Access Denied", re-run the installer (run_installer.bat) as Administrator to register the URL.'
    exit 1
}

# ── Request loop ──────────────────────────────────────────────────────────────
try {
    while ($listener.IsListening) {
        $ctx = $listener.GetContext()
        $req = $ctx.Request
        $method = $req.HttpMethod
        $path = $req.Url.AbsolutePath

        if ($method -eq 'OPTIONS') {
            $ctx.Response.StatusCode = 204
            $ctx.Response.Headers.Add('Access-Control-Allow-Origin', '*')
            $ctx.Response.Headers.Add('Access-Control-Allow-Methods', 'GET, POST, OPTIONS')
            $ctx.Response.Headers.Add('Access-Control-Allow-Headers', 'Content-Type')
            $ctx.Response.OutputStream.Close()
            continue
        }

        if ($method -eq 'GET' -and $path -eq '/status') {
            Send-JsonResponse $ctx 200 @{ ok = $true; service = 'Goldfish POS Cash Drawer Bridge'; port = $Port; log = $LogFile }
        }
        elseif ($method -eq 'GET' -and $path -eq '/printers') {
            Send-JsonResponse $ctx 200 (Get-PrinterList)
        }
        elseif ($method -eq 'POST' -and $path -eq '/open-drawer') {
            $result = Invoke-OpenDrawer
            Send-JsonResponse $ctx (if ($result.ok) { 200 } else { 500 }) $result
        }
        elseif ($method -eq 'POST' -and $path -eq '/print') {
            try {
                $reader = [System.IO.StreamReader]::new($req.InputStream, [System.Text.Encoding]::UTF8)
                $data = $reader.ReadToEnd() | ConvertFrom-Json
                $result = Invoke-PrintReceipt $data
                Send-JsonResponse $ctx (if ($result.ok) { 200 } else { 500 }) $result
            }
            catch {
                $ctx.Response.StatusCode = 400
                $ctx.Response.OutputStream.Close()
            }
        }
        else {
            $ctx.Response.StatusCode = 404
            $ctx.Response.OutputStream.Close()
        }
    }
}
catch {
    Write-Log 'ERROR' "Fatal error: $($_.Exception.Message)"
}
finally {
    $listener.Stop()
    Write-Log 'INFO' 'Bridge stopped.'
}
