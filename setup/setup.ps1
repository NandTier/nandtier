# Copyright 2026 Abdul Muheet Ghani
# SPDX-License-Identifier: Apache-2.0
#
# NandTier setup for Windows 10/11 (PowerShell 5.1 or 7). Double-click
# setup\setup.bat, or run in PowerShell:
#
#   setup\setup.bat                  download what is missing, install, check
#   setup\setup.bat -DownloadOnly    only fill setup\cache (for a USB stick or a lab)
#   setup\setup.bat -Offline         install from setup\cache only, no network at all
#   setup\setup.bat -Check           show what is installed and build the firmware
#
# Everything goes into tools\ in the repository; nothing is installed
# system-wide and no administrator rights are needed. Uninstall: delete
# tools\ and local.mk. The Windows packages for a class can also be prepared
# on Linux: setup/setup.sh --bundle --platform win32-x64.
#
#   OSS CAD Suite        yosys, nextpnr, apicula, openFPGALoader, iverilog, gtkwave
#   RISC-V GCC           xPack riscv-none-elf-gcc
#   Windows Build Tools  xPack: GNU make, sh and the shell commands the Makefiles use
#   Python 3             the installed one, the OSS CAD Suite's, or a private copy
#   pyserial             for sw\nandtier-programmer.py and sw\gamepad.py

[CmdletBinding()]
param(
	[string]$Prefix = "",
	[string]$Cache = "",
	[switch]$DownloadOnly,
	[switch]$Offline,
	[switch]$NoCad,
	[switch]$NoGcc,
	[switch]$NoTest,
	[switch]$Check,
	[switch]$Yes
)

$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"   # Invoke-WebRequest is 10x faster without it
try { [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 } catch {}

$Here = Split-Path -Parent $MyInvocation.MyCommand.Path
$Root = (Resolve-Path (Join-Path $Here "..")).Path
if (-not $Prefix) { $Prefix = Join-Path $Root "tools" }
if (-not $Cache)  { $Cache  = Join-Path $Here "cache" }
New-Item -ItemType Directory -Force -Path $Prefix, $Cache | Out-Null
$Prefix = (Resolve-Path $Prefix).Path
$Cache  = (Resolve-Path $Cache).Path
$Lock   = Join-Path $Cache "lock.txt"
$Platform = "win32-x64"

function Say($m)  { Write-Host "==> $m" -ForegroundColor Cyan }
function Ok($m)   { Write-Host "    ok " -ForegroundColor Green -NoNewline; Write-Host $m }
function Warn($m) { Write-Host "    !! $m" -ForegroundColor Yellow }
function Die($m)  { Write-Host "error: $m" -ForegroundColor Red; exit 1 }

if (-not [Environment]::Is64BitOperatingSystem) { Die "NandTier needs 64-bit Windows" }

# --- versions.txt ------------------------------------------------------------------
$V = @{}
Get-Content (Join-Path $Here "versions.txt") | ForEach-Object {
	if ($_ -match '^\s*([A-Z_0-9]+)=(.*)$') { $V[$Matches[1]] = $Matches[2].Trim() }
}

# --- downloading ---------------------------------------------------------------------

function Lock-Get($key) {
	if (-not (Test-Path $Lock)) { return "" }
	$l = Get-Content $Lock | Where-Object { $_ -like "$key=*" } | Select-Object -Last 1
	if ($l) { return $l.Substring($key.Length + 1) } else { return "" }
}
function Lock-Set($key, $val) {
	$lines = @()
	if (Test-Path $Lock) { $lines = @(Get-Content $Lock | Where-Object { $_ -notlike "$key=*" }) }
	$lines += "$key=$val"
	Set-Content -Path $Lock -Value $lines -Encoding ASCII
}

function Http-Get($url, $file) {
	$curl = Get-Command curl.exe -ErrorAction SilentlyContinue
	if ($curl) {
		& $curl.Source -fL --retry 3 --connect-timeout 20 --progress-bar -o $file $url
		if ($LASTEXITCODE -ne 0) { throw "curl failed ($LASTEXITCODE)" }
	} else {
		Invoke-WebRequest -UseBasicParsing -Uri $url -OutFile $file
	}
}
function Http-Text($url) {
	$c = (Invoke-WebRequest -UseBasicParsing -Uri $url -Headers @{ "User-Agent" = "nandtier-setup" }).Content
	if ($c -is [byte[]]) { $c = [Text.Encoding]::UTF8.GetString($c) }
	return [string]$c
}

function GitHub-Asset($repo, $tag, $regex) {
	if ($tag -eq "latest") { $api = "https://api.github.com/repos/$repo/releases/latest" }
	else { $api = "https://api.github.com/repos/$repo/releases/tags/$tag" }
	try { $r = Http-Text $api | ConvertFrom-Json } catch { return "" }
	foreach ($a in $r.assets) { if ($a.name -match "^$regex$") { return $a.browser_download_url } }
	return ""
}

function Resolve-Url($key) {
	$url = Lock-Get $key
	if ($url -and ($Offline -or (Test-Path (Join-Path $Cache ([IO.Path]::GetFileName($url)))))) { return $url }
	if ($Offline) { Die "no $key in $Lock`: fill the cache first (setup.bat -DownloadOnly)" }
	switch ($key) {
		"oss-cad-win32-x64" {
			$r = $V.OSS_CAD_RELEASE
			# a .tgz since mid 2026, a self-extracting .exe before
			if ($r -eq "latest") { $url = GitHub-Asset "YosysHQ/oss-cad-suite-build" "latest" "oss-cad-suite-windows-x64-[0-9]+\.(tgz|exe)" }
			else { $url = "https://github.com/YosysHQ/oss-cad-suite-build/releases/download/$r/oss-cad-suite-windows-x64-$($r -replace '-','').tgz" }
		}
		"riscv-gcc-win32-x64" {
			$r = $V.RISCV_GCC_VERSION
			if ($r -eq "latest") { $url = GitHub-Asset "xpack-dev-tools/riscv-none-elf-gcc-xpack" "latest" "xpack-riscv-none-elf-gcc-[0-9.]+-[0-9]+-win32-x64\.zip" }
			else { $url = "https://github.com/xpack-dev-tools/riscv-none-elf-gcc-xpack/releases/download/v$r/xpack-riscv-none-elf-gcc-$r-win32-x64.zip" }
		}
		"win-build-tools" {
			$r = $V.WIN_BUILD_TOOLS_VERSION
			if ($r -eq "latest") { $url = GitHub-Asset "xpack-dev-tools/windows-build-tools-xpack" "latest" "xpack-windows-build-tools-[0-9.]+-[0-9]+-win32-x64\.zip" }
			else { $url = "https://github.com/xpack-dev-tools/windows-build-tools-xpack/releases/download/v$r/xpack-windows-build-tools-$r-win32-x64.zip" }
		}
		"python-win" { $url = "https://www.python.org/ftp/python/$($V.PYTHON_WIN_VERSION)/python-$($V.PYTHON_WIN_VERSION)-embed-amd64.zip" }
		"pyserial"   { $url = $V.PYSERIAL_WHEEL }
	}
	if (-not $url) { Die "could not find the $key download on GitHub (no internet, or the GitHub API limit). Pin a version in setup\versions.txt." }
	return $url
}

function Get-Part($key, $sum = "") {
	$url = Resolve-Url $key
	$f = Join-Path $Cache ([IO.Path]::GetFileName($url))
	if (-not (Test-Path $f) -or (Get-Item $f).Length -eq 0) {
		if ($Offline) { Die "$([IO.Path]::GetFileName($f)) is not in $Cache" }
		Say "downloading $([IO.Path]::GetFileName($f))"
		try { Http-Get $url "$f.part" } catch { Remove-Item -Force "$f.part" -ErrorAction SilentlyContinue; Die "download failed: $url" }
		Move-Item -Force "$f.part" $f
	}
	$shaFile = "$f.sha256"
	if (-not $sum -and -not $Offline -and -not (Test-Path $shaFile) -and $url -like "*xpack*") {
		try {
			$h = ((Http-Text "$url.sha").Trim() -split '\s+')[0]
			if ($h -match '^[0-9a-fA-F]{64}$') { Set-Content -Path $shaFile -Value $h -Encoding ASCII }
		} catch {}
	}
	if (-not $sum -and (Test-Path $shaFile)) { $sum = (Get-Content $shaFile | Select-Object -First 1).Trim() }
	if ($sum) {
		$h = (Get-FileHash -Algorithm SHA256 $f).Hash.ToLower()
		if ($h -ne $sum.ToLower()) { Remove-Item -Force $f; Die "checksum mismatch for $([IO.Path]::GetFileName($f)), removed it: run again" }
	}
	Lock-Set $key $url
	return $f
}

function Unzip($zip, $dest) {
	New-Item -ItemType Directory -Force -Path $dest | Out-Null
	$tar = Get-Command tar -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
	if ($tar) {
		& $tar.Source -xf $zip -C $dest 2>$null
		if ($LASTEXITCODE -eq 0) { return }
		Remove-Item -Recurse -Force $dest; New-Item -ItemType Directory -Force -Path $dest | Out-Null
	}
	Add-Type -AssemblyName System.IO.Compression.FileSystem
	[IO.Compression.ZipFile]::ExtractToDirectory($zip, $dest)
}

# --- download only ---------------------------------------------------------------------

if ($DownloadOnly) {
	Say "downloading for $Platform into $Cache"
	if (-not $NoCad) { Get-Part "oss-cad-win32-x64" | Out-Null; Ok "OSS CAD Suite" }
	if (-not $NoGcc) { Get-Part "riscv-gcc-win32-x64" | Out-Null; Ok "RISC-V GCC" }
	Get-Part "win-build-tools" | Out-Null; Ok "make for Windows"
	Get-Part "pyserial" $V.PYSERIAL_SHA256 | Out-Null; Ok "pyserial"
	Get-Part "python-win" | Out-Null; Ok "Python (used only if none is installed)"
	Write-Host ""
	Write-Host "Done. Copy the whole repository folder (with setup\cache) to the other PCs and run there:"
	Write-Host "    setup\setup.bat -Offline"
	exit 0
}

# --- install ---------------------------------------------------------------------------

$CadDir = Join-Path $Prefix "oss-cad-suite"
$GccDir = Join-Path $Prefix "riscv-gcc"
$BtDir  = Join-Path $Prefix "win-build-tools"
$PyDir  = Join-Path $Prefix "python"
$PyLib  = Join-Path $Prefix "pylib"

function Stamp-Ok($dir, $file) {
	$s = Join-Path $dir ".nandtier-from"
	return ((Test-Path $s) -and ((Get-Content $s) -eq [IO.Path]::GetFileName($file)))
}
function Stamp-Set($dir, $file) { Set-Content -Path (Join-Path $dir ".nandtier-from") -Value ([IO.Path]::GetFileName($file)) -Encoding ASCII }

function Install-Cad {
	$a = Get-Part "oss-cad-win32-x64"
	if (Stamp-Ok $CadDir $a) { Ok "OSS CAD Suite already installed"; return }
	Say "unpacking $([IO.Path]::GetFileName($a)) (about 2 GB, a few minutes)"
	if (Test-Path $CadDir) { Remove-Item -Recurse -Force $CadDir }
	if ($a -like "*.exe") {
		# older releases: a 7-Zip self-extracting archive, -y (no questions) -o<folder>
		$p = Start-Process -FilePath $a -ArgumentList @("-y", "-o`"$Prefix`"") -Wait -PassThru -NoNewWindow
		$rc = $p.ExitCode
	} else {
		# tar.exe comes with Windows 10 (1803) and later
		$tar = Get-Command tar -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
		if (-not $tar) { Die "tar.exe not found (Windows 10 1803 or later has it)" }
		& $tar.Source -xzf $a -C $Prefix
		$rc = $LASTEXITCODE
	}
	if ($rc -ne 0 -or -not (Test-Path (Join-Path $CadDir "bin"))) { Die "unpacking the OSS CAD Suite failed (exit $rc)" }
	Stamp-Set $CadDir $a
	Ok "OSS CAD Suite in $CadDir"
}

function Install-Zip($key, $dir, $glob, $name) {
	$a = Get-Part $key
	if (Stamp-Ok $dir $a) { Ok "$name already installed"; return }
	Say "unpacking $([IO.Path]::GetFileName($a))"
	$tmp = Join-Path $Prefix ".tmp"
	if (Test-Path $tmp) { Remove-Item -Recurse -Force $tmp }
	Unzip $a $tmp
	if (Test-Path $dir) { Remove-Item -Recurse -Force $dir }
	$inner = Get-ChildItem -Directory $tmp | Where-Object { $_.Name -like $glob } | Select-Object -First 1
	if (-not $inner) { Die "unexpected contents in $a" }
	Move-Item $inner.FullName $dir
	Remove-Item -Recurse -Force $tmp
	Stamp-Set $dir $a
	Ok "$name in $dir"
}

function Test-Python($exe, [string[]]$pre = @()) {
	try {
		$out = & $exe @pre -c "import sys; print(sys.executable if sys.version_info >= (3, 6) else '')" 2>$null
		if ($LASTEXITCODE -eq 0 -and $out) { return ($out | Select-Object -First 1).Trim() }
	} catch {}
	return ""
}

function Find-Python {
	# the py launcher and python.exe from python.org (not the Microsoft Store stub)
	$py = Get-Command py.exe -ErrorAction SilentlyContinue
	if ($py) { $p = Test-Python $py.Source @("-3"); if ($p) { return $p } }
	$py = Get-Command python.exe -ErrorAction SilentlyContinue
	if ($py -and $py.Source -notlike "*WindowsApps*") { $p = Test-Python $py.Source; if ($p) { return $p } }
	foreach ($c in @((Join-Path $CadDir "lib\python3.exe"), (Join-Path $CadDir "bin\python3.exe"), (Join-Path $PyDir "python.exe"))) {
		if (Test-Path $c) { $p = Test-Python $c; if ($p) { return $p } }
	}
	return ""
}

function Install-PrivatePython {
	$a = Get-Part "python-win"
	if (-not (Stamp-Ok $PyDir $a)) {
		Say "installing a private Python in $PyDir"
		if (Test-Path $PyDir) { Remove-Item -Recurse -Force $PyDir }
		Unzip $a $PyDir
		Stamp-Set $PyDir $a
	}
	# the embeddable Python ignores PYTHONPATH; its ._pth file lists the paths
	$pth = Get-ChildItem $PyDir -Filter "python*._pth" | Select-Object -First 1
	if ($pth -and -not ((Get-Content $pth.FullName) -contains "..\pylib")) {
		Add-Content -Path $pth.FullName -Value "..\pylib"
	}
}

function Install-Pyserial {
	$a = Get-Part "pyserial" $V.PYSERIAL_SHA256
	if (Test-Path (Join-Path $PyLib "serial")) { Ok "pyserial already installed"; return }
	if (Test-Path $PyLib) { Remove-Item -Recurse -Force $PyLib }
	Add-Type -AssemblyName System.IO.Compression.FileSystem
	[IO.Compression.ZipFile]::ExtractToDirectory($a, $PyLib)   # a wheel is a zip
	Ok "pyserial in $PyLib"
}

function Fwd($p) { return ($p -replace '\\', '/') }

function Write-Config($cad, $py) {
	$paths = @()
	if ($cad) { $paths += (Fwd "$cad\bin"); $paths += (Fwd "$cad\lib") }
	$paths += (Fwd "$GccDir\bin")
	$paths += (Fwd "$BtDir\bin")
	$pathLine = ($paths -join ';')
	$date = Get-Date -Format "yyyy-MM-dd HH:mm"
	$mk = @"
# Written by setup\setup.ps1 on $date. Run it again to update, or edit by
# hand. A value on the make command line still wins.
RISCV_PATH  ?= $(Fwd $GccDir)
RISCV_NAME  ?= riscv-none-elf
OSS_CAD     ?= $(if ($cad) { Fwd $cad } else { "" })
PYTHON_NAME ?= $(Fwd $py)
GOWIN_HOME  ?= C:/Gowin/Gowin_V1.9.9_x64/IDE

# the tools first on PATH, for every make in the project
export PATH := $pathLine;`$(PATH)
export PYTHONPATH := $(Fwd $PyLib)
"@
	Set-Content -Path (Join-Path $Root "local.mk") -Value $mk -Encoding ASCII

	$winPaths = ($paths | ForEach-Object { $_ -replace '/', '\' }) -join ';'
	$ps = @"
# NandTier tools in this PowerShell:   . .\env.ps1
`$env:NANDTIER = "$Root"
`$env:PATH = "$winPaths;" + `$env:PATH
`$env:PYTHONPATH = "$PyLib"
"@
	Set-Content -Path (Join-Path $Root "env.ps1") -Value $ps -Encoding ASCII
	$bat = "@rem NandTier tools in this cmd window:   env.bat`r`n@set NANDTIER=$Root`r`n@set PATH=$winPaths;%PATH%`r`n@set PYTHONPATH=$PyLib`r`n"
	Set-Content -Path (Join-Path $Root "env.bat") -Value $bat -Encoding ASCII
	Ok "wrote local.mk, env.ps1 and env.bat"
}

function Check-All($cad, $py) {
	Say "checking"
	$bad = $false
	$gcc = Join-Path $GccDir "bin\riscv-none-elf-gcc.exe"
	if (Test-Path $gcc) { try { Ok ((& $gcc --version | Select-Object -First 1)) } catch { Warn "$gcc does not run"; $bad = $true } }
	else { Warn "no RISC-V GCC at $gcc"; $bad = $true }
	$make = Join-Path $BtDir "bin\make.exe"
	if (Test-Path $make) { try { Ok ((& $make --version | Select-Object -First 1)) } catch { Warn "$make does not run"; $bad = $true } }
	else { Warn "no make at $make"; $bad = $true }
	if ($cad) {
		foreach ($t in @("yosys", "nextpnr-himbaechel", "openFPGALoader", "iverilog")) {
			$e = Get-ChildItem (Join-Path $cad "bin") -Filter "$t.*" -ErrorAction SilentlyContinue | Select-Object -First 1
			if ($e) { Ok $t } else { Warn "missing $t in $cad\bin"; $bad = $true }
		}
	}
	$env:PYTHONPATH = $PyLib
	if ($py -and (Test-Python $py) -and ((& $py -c "import serial; print('ok')" 2>$null) -eq "ok")) { Ok "$(& $py --version 2>&1) with pyserial" }
	else { Warn "python with pyserial not working"; $bad = $true }

	if (-not $NoTest -and -not $bad) {
		Say "building the boot ROM, the launcher and the games (make)"
		$env:PATH = ((Join-Path $GccDir "bin") + ";" + (Join-Path $BtDir "bin") + ";" + $env:PATH)
		$log = Join-Path $Prefix "setup-build.log"
		Push-Location $Root
		& $make -s all *> $log
		$rc = $LASTEXITCODE
		Pop-Location
		if ($rc -eq 0) { Ok "firmware built: fw\fw-flash\build\fw-flash.v, fw\games\build\carts.img" }
		else { Warn "the build failed, see $log"; $bad = $true }
	}
	return (-not $bad)
}

Say "NandTier setup on Windows"
Write-Host "    repository: $Root"
Write-Host "    tools:      $Prefix"
if ($Offline) { Write-Host "    cache:      $Cache  (offline: no downloads)" } else { Write-Host "    cache:      $Cache" }

if (-not $Check) {
	if (-not $NoCad) { Install-Cad }
	if (-not $NoGcc) { Install-Zip "riscv-gcc-win32-x64" $GccDir "xpack-riscv-none-elf-gcc-*" "RISC-V GCC" }
	Install-Zip "win-build-tools" $BtDir "xpack-windows-build-tools-*" "make for Windows"
	Install-Pyserial
}
$py = Find-Python
if (-not $py) {
	if ($Check) { Die "no Python 3 found" }
	Install-PrivatePython
	$py = Find-Python
	if (-not $py) { Die "could not set up Python" }
}
Ok "Python: $py"

if (Test-Path (Join-Path $CadDir "bin")) { $cad = $CadDir } else { $cad = "" }
Write-Config $cad $py

if (Check-All $cad $py) {
	Write-Host ""
	Say "ready. In this folder, in PowerShell:"
	Write-Host "    . .\env.ps1                    the tools in this window (or env.bat in cmd)"
	Write-Host "    make                           boot ROM, launcher and games"
	Write-Host "    make fpga                      the bitstream (Tang Nano 9K; BOARD=tangnano20k or ulx3s)"
	Write-Host "    make fpga-load                 load it into the FPGA (see README: USB driver)"
	Write-Host "    make program COMx=COM5         launcher into the flash, games onto the SD card"
} else {
	Write-Host ""
	Warn "setup finished with problems (see above)"
	exit 1
}
