# 7-Zip Windows pack: build every working makefile target and copy binaries to OUT\.
# Usage:
#   .\pack.cmd
#   .\pack.cmd -Arch x64
#   .\pack.cmd -Arch x86 -Rebuild

[CmdletBinding()]
param(
    [ValidateSet('x64', 'x86')]
    [string]$Arch = 'x64',
    [switch]$Rebuild
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$Root = $PSScriptRoot
$OutRoot = Join-Path $Root 'OUT'
$OutDir = Join-Path $OutRoot $Arch
$TempBat = Join-Path $env:TEMP ("7zip-pack-{0}.cmd" -f $PID)

function Write-Step([string]$Message) {
    Write-Host ""
    Write-Host "==> $Message" -ForegroundColor Cyan
}

function Find-VcVars {
    $vswhere = Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio\Installer\vswhere.exe'
    if (-not (Test-Path $vswhere)) {
        throw "vswhere.exe not found. Install Visual Studio 2022 with the Desktop C++ workload."
    }

    $vsPath = & $vswhere -latest -products * `
        -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 `
        -property installationPath
    if (-not $vsPath) {
        throw "No Visual Studio with MSVC x86/x64 tools was found."
    }

    $vcvars = Join-Path $vsPath 'VC\Auxiliary\Build\vcvarsall.bat'
    if (-not (Test-Path $vcvars)) {
        throw "vcvarsall.bat not found under: $vsPath"
    }
    return $vcvars
}

# Leaf projects that nmake actually produces. Archive\makefile and Compress\makefile
# are stale (missing subdirs) and are intentionally skipped.
$CppLeafDirs = @(
    'CPP\7zip\UI\Client7z',
    'CPP\7zip\UI\Console',
    'CPP\7zip\UI\Explorer',
    'CPP\7zip\UI\Far',
    'CPP\7zip\UI\FileManager',
    'CPP\7zip\UI\GUI',
    'CPP\7zip\Bundles\Alone',
    'CPP\7zip\Bundles\Alone2',
    'CPP\7zip\Bundles\Alone7z',
    'CPP\7zip\Bundles\Fm',
    'CPP\7zip\Bundles\Format7z',
    'CPP\7zip\Bundles\Format7zF',
    'CPP\7zip\Bundles\Format7zR',
    'CPP\7zip\Bundles\Format7zExtract',
    'CPP\7zip\Bundles\Format7zExtractR',
    'CPP\7zip\Bundles\LzmaCon',
    'CPP\7zip\Bundles\SFXCon',
    'CPP\7zip\Bundles\SFXSetup',
    'CPP\7zip\Bundles\SFXWin'
)

$UtilMakefiles = @(
    @{ Dir = 'C\Util\7z';            File = 'makefile' }
    @{ Dir = 'C\Util\7zipInstall';   File = 'makefile' }
    @{ Dir = 'C\Util\7zipUninstall'; File = 'makefile' }
    @{ Dir = 'C\Util\Lzma';          File = 'makefile' }
    # LzFind.c + PCH + MSVC 14.4x immintrin.h emits C4514; Compiler.h only disables it for _MSC_VER < 1900.
    @{ Dir = 'C\Util\LzmaLib';       File = 'makefile'; Extra = '"CFLAGS_WARN_LEVEL=-Wall -wd4514"'; Also = @(($Arch + '\sLZMA.lib')) }
    @{ Dir = 'C\Util\SfxSetup';      File = 'makefile' }
)

# Bundles\Fm also emits 7zFM.exe; keep the File Manager binary as 7zFM.exe.
$Artifacts = @(
    @{ Rel = 'CPP\7zip\UI\Console';                 Name = '7z.exe';              Dest = '7z.exe' }
    @{ Rel = 'CPP\7zip\UI\FileManager';             Name = '7zFM.exe';            Dest = '7zFM.exe' }
    @{ Rel = 'CPP\7zip\UI\GUI';                     Name = '7zG.exe';             Dest = '7zG.exe' }
    @{ Rel = 'CPP\7zip\UI\Explorer';                Name = '7-zip.dll';           Dest = '7-zip.dll' }
    @{ Rel = 'CPP\7zip\UI\Far';                     Name = '7-ZipFar.dll';        Dest = '7-ZipFar.dll' }
    @{ Rel = 'CPP\7zip\UI\Client7z';                Name = '7zcl.exe';            Dest = '7zcl.exe' }
    @{ Rel = 'CPP\7zip\Bundles\Format7zF';          Name = '7z.dll';              Dest = '7z.dll' }
    @{ Rel = 'CPP\7zip\Bundles\Alone';              Name = '7za.exe';             Dest = '7za.exe' }
    @{ Rel = 'CPP\7zip\Bundles\Alone2';             Name = '7zz.exe';             Dest = '7zz.exe' }
    @{ Rel = 'CPP\7zip\Bundles\Alone7z';            Name = '7zr.exe';             Dest = '7zr.exe' }
    @{ Rel = 'CPP\7zip\Bundles\Fm';                 Name = '7zFM.exe';            Dest = '7zFM_standalone.exe' }
    @{ Rel = 'CPP\7zip\Bundles\Format7z';           Name = '7za.dll';             Dest = '7za.dll' }
    @{ Rel = 'CPP\7zip\Bundles\Format7zR';          Name = '7zra.dll';            Dest = '7zra.dll' }
    @{ Rel = 'CPP\7zip\Bundles\Format7zExtract';    Name = '7zxa.dll';            Dest = '7zxa.dll' }
    @{ Rel = 'CPP\7zip\Bundles\Format7zExtractR';   Name = '7zxr.dll';            Dest = '7zxr.dll' }
    @{ Rel = 'CPP\7zip\Bundles\LzmaCon';            Name = 'lzma.exe';            Dest = 'lzma.exe' }
    @{ Rel = 'CPP\7zip\Bundles\SFXWin';             Name = '7z.sfx';              Dest = '7z.sfx' }
    @{ Rel = 'CPP\7zip\Bundles\SFXCon';             Name = '7zCon.sfx';           Dest = '7zCon.sfx' }
    @{ Rel = 'CPP\7zip\Bundles\SFXSetup';           Name = '7zS.sfx';             Dest = '7zS.sfx' }
    @{ Rel = 'C\Util\SfxSetup';                     Name = '7zS2.sfx';            Dest = '7zS2.sfx' }
    @{ Rel = 'C\Util\SfxSetup';                     Name = '7zS2con.sfx';         Dest = '7zS2con.sfx'; OutSubdir = ($Arch + 'con') }
    @{ Rel = 'C\Util\7zipInstall';                  Name = '7zipInstall.exe';     Dest = '7zipInstall.exe' }
    @{ Rel = 'C\Util\7zipUninstall';                Name = '7zipUninstall.exe';   Dest = '7zipUninstall.exe' }
    @{ Rel = 'C\Util\7z';                           Name = '7zDec.exe';           Dest = '7zDec.exe' }
    @{ Rel = 'C\Util\Lzma';                         Name = 'LZMAc.exe';           Dest = 'LZMAc.exe' }
    @{ Rel = 'C\Util\LzmaLib';                      Name = 'LZMA.dll';            Dest = 'LZMA.dll' }
)

function Get-OutSubdir([hashtable]$Item) {
    if ($Item.ContainsKey('OutSubdir') -and $Item.OutSubdir) { return $Item.OutSubdir }
    return $Arch
}

function Get-ArtifactPath([hashtable]$Item) {
    return Join-Path $Root (Join-Path $Item.Rel (Join-Path (Get-OutSubdir $Item) $Item.Name))
}

function Remove-BuildDirs {
    Write-Step "Cleaning previous object dirs ($Arch)"
    foreach ($rel in $CppLeafDirs) {
        $dir = Join-Path $Root (Join-Path $rel $Arch)
        if (Test-Path $dir) { Remove-Item $dir -Recurse -Force }
    }
    foreach ($item in $UtilMakefiles) {
        $dir = Join-Path $Root (Join-Path $item.Dir $Arch)
        if (Test-Path $dir) { Remove-Item $dir -Recurse -Force }
    }
    $conDir = Join-Path $Root (Join-Path 'C\Util\SfxSetup' ($Arch + 'con'))
    if (Test-Path $conDir) { Remove-Item $conDir -Recurse -Force }
}

function Invoke-Build([string]$VcVars) {
    $vcArg = if ($Arch -eq 'x86') { 'amd64_x86' } else { 'x64' }
    $conO = $Arch + 'con'

    $lines = New-Object System.Collections.Generic.List[string]
    [void]$lines.Add('@echo off')
    [void]$lines.Add('setlocal')
    [void]$lines.Add("call `"$VcVars`" $vcArg")
    [void]$lines.Add('if errorlevel 1 exit /b 1')
    [void]$lines.Add("cd /d `"$Root\CPP\7zip`"")
    [void]$lines.Add("nmake /nologo PLATFORM=$Arch")
    [void]$lines.Add('if errorlevel 1 exit /b 1')

    foreach ($item in $UtilMakefiles) {
        $extra = ''
        if ($item.ContainsKey('Extra') -and $item.Extra) { $extra = ' ' + $item.Extra }
        [void]$lines.Add("cd /d `"$Root\$($item.Dir)`"")
        [void]$lines.Add("nmake /nologo /f $($item.File) PLATFORM=$Arch$extra")
        [void]$lines.Add('if errorlevel 1 exit /b 1')
        if ($item.ContainsKey('Also')) {
            foreach ($target in $item.Also) {
                [void]$lines.Add("nmake /nologo /f $($item.File) PLATFORM=$Arch$extra $target")
                [void]$lines.Add('if errorlevel 1 exit /b 1')
            }
        }
    }

    [void]$lines.Add("cd /d `"$Root\C\Util\SfxSetup`"")
    [void]$lines.Add("nmake /nologo /f makefile_con PLATFORM=$Arch O=$conO")
    [void]$lines.Add('if errorlevel 1 exit /b 1')
    [void]$lines.Add('exit /b 0')

    Set-Content -Path $TempBat -Value $lines -Encoding ASCII
    Write-Step "Building $Arch (MSVC + nmake)"
    try {
        & cmd.exe /c "`"$TempBat`""
        if ($LASTEXITCODE -ne 0) {
            throw "nmake failed with exit code $LASTEXITCODE"
        }
    }
    finally {
        Remove-Item $TempBat -ErrorAction SilentlyContinue
    }
}

function Copy-Sidecar([string]$SourceDir, [string]$BaseName, [string]$DestDir) {
    foreach ($ext in @('.lib', '.exp')) {
        $src = Join-Path $SourceDir ($BaseName + $ext)
        if (Test-Path $src) {
            Copy-Item $src (Join-Path $DestDir (Split-Path $src -Leaf)) -Force
        }
    }
}

function Publish-Output {
    Write-Step "Copying binaries to $OutDir"
    if (Test-Path $OutDir) {
        Remove-Item $OutDir -Recurse -Force
    }
    New-Item -ItemType Directory -Path $OutDir | Out-Null

    $manifest = New-Object System.Collections.Generic.List[string]
    [void]$manifest.Add("arch=$Arch")
    [void]$manifest.Add("built=$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')")
    [void]$manifest.Add('')

    foreach ($item in $Artifacts) {
        $src = Get-ArtifactPath $item
        if (-not (Test-Path $src)) {
            throw "Build succeeded but missing: $src"
        }
        $dest = Join-Path $OutDir $item.Dest
        Copy-Item $src $dest -Force
        $srcDir = Split-Path $src -Parent
        $base = [System.IO.Path]::GetFileNameWithoutExtension($item.Name)
        Copy-Sidecar $srcDir $base $OutDir

        $size = (Get-Item $src).Length
        [void]$manifest.Add(("{0,-24}  {1,10}  {2}\{3}\{4}" -f $item.Dest, $size, $item.Rel, (Get-OutSubdir $item), $item.Name))
    }

    $lzmaStatic = Join-Path $Root "C\Util\LzmaLib\$Arch\sLZMA.lib"
    if (Test-Path $lzmaStatic) {
        Copy-Item $lzmaStatic (Join-Path $OutDir 'sLZMA.lib') -Force
        [void]$manifest.Add(("{0,-24}  {1,10}  C\Util\LzmaLib\{2}\sLZMA.lib" -f 'sLZMA.lib', (Get-Item $lzmaStatic).Length, $Arch))
    }

    $docDir = Join-Path $OutRoot 'doc'
    New-Item -ItemType Directory -Path $docDir -Force | Out-Null
    foreach ($doc in @('License.txt', 'unRarLicense.txt', 'copying.txt')) {
        $src = Join-Path $Root (Join-Path 'DOC' $doc)
        if (Test-Path $src) {
            Copy-Item $src (Join-Path $docDir $doc) -Force
        }
    }

    $manifestPath = Join-Path $OutDir 'MANIFEST.txt'
    Set-Content -Path $manifestPath -Value $manifest -Encoding UTF8
    Write-Host ($manifest -join [Environment]::NewLine)
}

$vcvars = Find-VcVars
Write-Host "vcvars: $vcvars"
Write-Host "arch:   $Arch"
Write-Host "out:    $OutDir"

if ($Rebuild) {
    Remove-BuildDirs
}

Invoke-Build $vcvars
Publish-Output

Write-Step "Done"
Write-Host "Output: $OutDir"
exit 0
