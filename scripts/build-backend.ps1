# Compila y prueba el backend local en Windows: SQL, motor C++, servidor Java y
# cliente web.
#
#   powershell -ExecutionPolicy Bypass -File scripts/build-backend.ps1
#   $env:BUILD_TYPE = "Debug"; powershell -File scripts/build-backend.ps1
#   $env:SKIP_WEB_TESTS = "1"   (sin Node.js)
$ErrorActionPreference = "Stop"

$Root = Split-Path -Parent $PSScriptRoot
$Backend = Join-Path $Root "backend"
$BuildType = if ($env:BUILD_TYPE) { $env:BUILD_TYPE } else { "Release" }
$CoreBuild = Join-Path $Backend "core\build"

function Step([string]$Text) {
    Write-Host ""
    Write-Host "== $Text"
}

function Invoke-Checked([string]$File, [string[]]$Arguments) {
    & $File @Arguments
    if ($LASTEXITCODE -ne 0) {
        throw "Falló: $File $($Arguments -join ' ')"
    }
}

Step "Pruebas del esquema SQL"
if ((Get-Command sqlite3 -ErrorAction SilentlyContinue) -and (Get-Command bash -ErrorAction SilentlyContinue)) {
    Invoke-Checked "bash" @("$Backend/sql/tests/run.sh")
} else {
    Write-Host "Se omiten (requieren sqlite3 y bash); el motor C++ las cubre igual"
}

Step "Motor C++ ($BuildType)"
Invoke-Checked "cmake" @("-S", (Join-Path $Backend "core"), "-B", $CoreBuild)
Invoke-Checked "cmake" @("--build", $CoreBuild, "--config", $BuildType, "--parallel")
Invoke-Checked "ctest" @("--test-dir", $CoreBuild, "--build-config", $BuildType, "--output-on-failure")

# Con Visual Studio las bibliotecas quedan en build\<Release|Debug>.
$LibraryDir = Join-Path $CoreBuild $BuildType
if (-not (Test-Path (Join-Path $LibraryDir "voxoncore.dll"))) {
    $LibraryDir = $CoreBuild
}

Step "Servidor Java"
Push-Location (Join-Path $Backend "server")
try {
    Invoke-Checked ".\gradlew.bat" @("test", "installDist", "--console=plain", "-PvoxonCoreDir=$LibraryDir")
} finally {
    Pop-Location
}

Step "Cliente web"
if (-not $env:SKIP_WEB_TESTS -and (Get-Command node -ErrorAction SilentlyContinue)) {
    Push-Location (Join-Path $Backend "web")
    try {
        Invoke-Checked "npm" @("test")
    } finally {
        Pop-Location
    }
} else {
    Write-Host "Node.js no está disponible; se omiten las pruebas web"
}

Step "Listo"
Write-Host "Inicia el servidor con:"
Write-Host "  $Backend\server\build\install\voxon-server\bin\voxon-server.bat"
