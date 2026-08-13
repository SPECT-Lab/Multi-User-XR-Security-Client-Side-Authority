<#
  setup.ps1 - Windows installer for the desktop (PC) attack path.

  For the runtime attack you only need native-Windows Python + frida-tools and the
  prebuilt runtime_logging\runtime_logger.js (already in the repo). This script
  installs/verifies those. Pass -StaticAnalysis to ALSO set up JDK 21 + Ghidra for
  running static analysis on Windows (otherwise do static analysis on Mac/Linux).

  Run from the repo root:
    powershell -ExecutionPolicy Bypass -File setup.ps1
    powershell -ExecutionPolicy Bypass -File setup.ps1 -StaticAnalysis
#>
param(
  [switch]$StaticAnalysis
)

$FridaVer  = "17.9.1"
$GhidraVer = "11.3.2"
$script:warn = 0
function Note($m){ Write-Host "  $m" }
function Ok($m){ Write-Host "  [ OK ] $m" -ForegroundColor Green }
function Bad($m){ Write-Host "  [WARN] $m" -ForegroundColor Yellow; $script:warn++ }

Write-Host "== Relay and Betray :: Windows setup =="

# --- 1) Python (native Windows) ---------------------------------------------
Write-Host "-- Python + host Frida --"
$py = $null
foreach ($c in @("python","python3","py")) {
  if (Get-Command $c -ErrorAction SilentlyContinue) { $py = $c; break }
}
if (-not $py) {
  Bad "Python not found - install Python 3.12 and tick 'Add python.exe to PATH': https://www.python.org/downloads/windows/"
} else {
  $pyv = & $py --version 2>&1
  Ok "Python ($pyv) via '$py'"
  # NOTE: frida-tools and frida (core) are versioned separately. The bundled
  # gadget/server is $FridaVer, and the 'frida' CLI reports the *core* version,
  # so pin frida==$FridaVer (to match the gadget) and let pip pick a compatible
  # frida-tools for the CLIs. (frida-tools never had a 17.x release.)
  Write-Host "   installing host Frida (frida==$FridaVer + frida-tools) ..."
  & $py -m pip install "frida==$FridaVer" frida-tools
  if ($LASTEXITCODE -eq 0) { Ok "host Frida installed (frida $FridaVer + frida-tools CLI)" } else { Bad "pip install failed - re-run, or check your Python/pip" }
}

# --- 2) verify the frida CLI is the native-Windows one ----------------------
$FridaMajMin = ($FridaVer -replace '^(\d+\.\d+).*','$1')   # e.g. 17.9
if (Get-Command frida -ErrorAction SilentlyContinue) {
  $fv = (frida --version) 2>$null
  if ("$fv" -like "$FridaMajMin*") { Ok "frida $fv (matches gadget $FridaVer on major.minor)" }
  else { Bad "frida $fv != $FridaVer - run: $py -m pip install frida==$FridaVer frida-tools" }
} else {
  Bad "frida CLI not on PATH yet - close and reopen the terminal (PATH refresh), then re-run this script"
}

# --- 3) runtime logger (prebuilt bundle is fine) ----------------------------
Write-Host "-- Runtime logger --"
if (Test-Path "runtime_logging\runtime_logger.js") {
  Ok "prebuilt runtime_logging\runtime_logger.js present"
} elseif (Get-Command npm -ErrorAction SilentlyContinue) {
  Note "no prebuilt bundle - building with npm ..."
  Push-Location runtime_logging
  npm install; npm run build
  Pop-Location
  if (Test-Path "runtime_logging\runtime_logger.js") { Ok "built runtime_logger.js" } else { Bad "npm build failed" }
} else {
  Bad "runtime_logger.js missing and npm not found - install Node.js (https://nodejs.org/) or restore the prebuilt bundle"
}

# --- 4) optional: static-analysis deps on Windows ---------------------------
if ($StaticAnalysis) {
  Write-Host "-- Static analysis (optional on Windows) --"

  # JDK 21 (Ghidra needs it)
  $haveJdk = $false
  if (Get-Command java -ErrorAction SilentlyContinue) {
    $jv = (java -version 2>&1 | Select-Object -First 1)
    if ("$jv" -match '"21') { Ok "JDK 21 ($jv)"; $haveJdk = $true }
  }
  if (-not $haveJdk -and (Test-Path ".\jdk21")) {
    $localJava = Get-ChildItem -Recurse ".\jdk21" -Filter java.exe -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($localJava) { $env:JAVA_HOME = Split-Path (Split-Path $localJava.FullName); Ok "using local JDK 21 ($env:JAVA_HOME)"; $haveJdk = $true }
  }
  if (-not $haveJdk) {
    Note "fetching Temurin JDK 21 into .\jdk21 ..."
    $arch = if ($env:PROCESSOR_ARCHITECTURE -eq "ARM64") { "aarch64" } else { "x64" }
    $jdkUrl = "https://api.adoptium.net/v3/binary/latest/21/ga/windows/$arch/jdk/hotspot/normal/eclipse"
    $zip = Join-Path $env:TEMP "temurin21.zip"
    try {
      Invoke-WebRequest -Uri $jdkUrl -OutFile $zip -UseBasicParsing
      if (Test-Path ".\jdk21") { Remove-Item -Recurse -Force ".\jdk21" }
      Expand-Archive $zip -DestinationPath ".\jdk21"
      $localJava = Get-ChildItem -Recurse ".\jdk21" -Filter java.exe | Select-Object -First 1
      if ($localJava) {
        $env:JAVA_HOME = Split-Path (Split-Path $localJava.FullName)
        Ok "installed local JDK 21 ($env:JAVA_HOME)"
        Note "to persist for new shells:  setx JAVA_HOME `"$env:JAVA_HOME`""
      } else { Bad "JDK extracted but java.exe not found under .\jdk21" }
    } catch { Bad "JDK download failed ($($_.Exception.Message)) - install manually: https://adoptium.net/temurin/releases/?version=21" }
    finally { Remove-Item $zip -ErrorAction SilentlyContinue }
  }

  # Ghidra (bundled under static_analysis\)
  $ghidra = "static_analysis\ghidra_${GhidraVer}_PUBLIC"
  if (Test-Path "$ghidra\support\analyzeHeadless.bat") { Ok "Ghidra present ($ghidra)" }
  else { Bad "Ghidra not bundled at $ghidra - download ${GhidraVer}: https://github.com/NationalSecurityAgency/ghidra/releases" }

  # Il2CppDumper (patched, bundled - never fetch upstream)
  if (Test-Path "static_analysis\Il2CppDumper") {
    Ok "bundled Il2CppDumper present"
    if (-not (Get-Command dotnet -ErrorAction SilentlyContinue) -and (Get-ChildItem -Recurse "static_analysis\Il2CppDumper" -Filter Il2CppDumper.dll -ErrorAction SilentlyContinue)) {
      Bad "Il2CppDumper is the .NET build but 'dotnet' is missing - install .NET: https://dotnet.microsoft.com/download"
    }
  } else {
    Bad "bundled (patched) Il2CppDumper missing at static_analysis\Il2CppDumper"
  }
}

Write-Host ""
if ($script:warn -gt 0) { Write-Host "Setup finished with $script:warn warning(s)." }
else { Write-Host "All set." }
Write-Host ""
Write-Host "Run an attack (launch Engage first, confirm the process name with: frida-ps):"
Write-Host '  frida -n Engage.exe -l runtime_logging\runtime_logger.js -l "..\Private Access\Engage\Attack Hooks\Video Surveillance.js"'