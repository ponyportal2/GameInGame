$ErrorActionPreference = 'Stop'

$Root = Split-Path -Parent $MyInvocation.MyCommand.Path
$RuntimeDir = Join-Path $Root 'runtime'
$EngineName = 'Godot_v4.7.2-stable_win64.exe'
$EnginePath = Join-Path $RuntimeDir $EngineName
$RuntimeUrl = 'https://github.com/godotengine/godot/releases/download/4.7.2-stable/Godot_v4.7.2-stable_win64.exe.zip'
$RuntimeSha256 = '731980f9608d61333e5baf54a2ef17210acc7a538446c0cb9969f002aca1e953'

function Show-GameSmithMessage([string]$Title, [string]$Message, [string]$Icon = 'Error') {
    try {
        Add-Type -AssemblyName PresentationFramework
        [System.Windows.MessageBox]::Show($Message, $Title, 'OK', $Icon) | Out-Null
    } catch {
        # Last-resort visibility if PresentationFramework is unavailable.
        & msg.exe * "$Title`n`n$Message" 2>$null
    }
}

try {
    # Download only when the executable is genuinely absent. An existing invalid
    # path is treated as an error rather than silently reaching the network.
    if (Test-Path -LiteralPath $EnginePath) {
        if (-not (Test-Path -LiteralPath $EnginePath -PathType Leaf)) {
            throw "Godot runtime path exists but is not a file: $EnginePath"
        }
    } else {
        New-Item -ItemType Directory -Force -Path $RuntimeDir | Out-Null
        $ZipPath = Join-Path $RuntimeDir 'godot-runtime.download.zip'
        try {
            Invoke-WebRequest -Uri $RuntimeUrl -OutFile $ZipPath -UseBasicParsing
            $ActualHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $ZipPath).Hash.ToLowerInvariant()
            if ($ActualHash -ne $RuntimeSha256) {
                throw "Godot runtime checksum mismatch. Got $ActualHash"
            }
            Expand-Archive -LiteralPath $ZipPath -DestinationPath $RuntimeDir -Force
        } finally {
            Remove-Item -LiteralPath $ZipPath -Force -ErrorAction SilentlyContinue
        }
        if (-not (Test-Path -LiteralPath $EnginePath -PathType Leaf)) {
            throw "Verified Godot archive did not contain $EngineName"
        }
    }

    if (-not (Get-Command git.exe -ErrorAction SilentlyContinue)) {
        Show-GameSmithMessage 'GameSmith — Git required' 'Git for Windows was not found on PATH. GameSmith can open, but creating/editing generated games requires Git. Install Git for Windows and restart GameSmith.' 'Warning'
    }

    # The GitHub checkout is the application: run project.godot directly, so a
    # separate checked-in .pck is unnecessary and source stays authoritative.
    $QuotedRoot = '"' + $Root + '"'
    Start-Process -FilePath $EnginePath -WorkingDirectory $Root -ArgumentList @('--path', $QuotedRoot)
} catch {
    Show-GameSmithMessage 'GameSmith failed to start' ($_.Exception.Message + "`n`nYou can also manually place $EngineName in:`n$RuntimeDir") 'Error'
    exit 1
}
