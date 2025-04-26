<#
.SYNOPSIS
    Builds the Godot engine and/or export templates.

.DESCRIPTION
    This script builds the Godot engine and/or export templates for Windows, Web, and Android platforms.
    
    Note: When using -BuildTemplates with specific template values, it must be the last parameter in the command.
    Note: Web templates require emsdk. If emcc is not on PATH, this script will attempt to activate it from C:\emsdk.

.PARAMETER BuildEngine
    When specified, builds the Godot engine.

.PARAMETER BuildTemplates
    When specified as a switch, builds all templates.
    When specified with values (separated by spaces), builds only the specified templates.
    If values are present, this must be the last argument in the command.
    
    Valid template values are:
    - WindowsDebug: Build Windows debug template
    - WindowsRelease: Build Windows release template
    - WebDebug: Build Web debug template
    - WebRelease: Build Web release template
    - AndroidDebug: Build Android debug template
    - AndroidRelease: Build Android release template

.PARAMETER DevBuild
    When specified with BuildEngine, builds with development options.

.EXAMPLE
    .\build.ps1 -BuildEngine -BuildTemplates
    Build everything - the engine and all templates.

.EXAMPLE
    .\build.ps1 -BuildEngine -BuildTemplates WebDebug
    Build the engine and only the Web debug template.

.EXAMPLE
    .\build.ps1 -BuildEngine -BuildTemplates WindowsDebug WebDebug
    Build the engine and only the Windows and Web debug templates.

.EXAMPLE
    .\build.ps1 -BuildEngine -BuildTemplates AndroidDebug AndroidRelease
    Build the engine and only the Android templates.

.EXAMPLE
    .\build.ps1 -BuildEngine -DevBuild -BuildTemplates
    Build the engine with development options and all templates.

.EXAMPLE
    .\build.ps1 -BuildEngine -DevBuild -BuildTemplates WebDebug
    Build the engine with development options and only the Web debug template.

.EXAMPLE
    .\build.ps1 -BuildEngine -DevBuild -BuildTemplates
    Build the engine with development options and only the Windows and Web debug templates.
#>

param(
    [switch]$BuildEngine,
    [switch]$DevBuild=$false,
    
    [Parameter(Position=0)]
    [switch]$BuildTemplates,
    
    [Parameter(ValueFromRemainingArguments=$true, DontShow=$true)]
    [AllowNull()]
    [System.Object[]]$BuildTemplatesValues
)

$ErrorActionPreference = 'Stop'

if (!$BuildEngine -and !$BuildTemplates) {
    Write-Error "Must specify one or both of -BuildEngine or -BuildTemplates"
    exit 1
}

$validTemplates = @('WindowsDebug', 'WindowsRelease', 'WebDebug', 'WebRelease', 'AndroidDebug', 'AndroidRelease')

# Process BuildTemplates values
$templatesToBuild = @()
if ($BuildTemplates) {
    if ($null -eq $BuildTemplatesValues -or $BuildTemplatesValues.Count -eq 0) {
        # If BuildTemplates is present but no value, build all templates
        $templatesToBuild = $validTemplates
        Write-Host "No specific templates specified, building all templates" -ForegroundColor Green
    }
    else {
        # Convert array items to strings and add to templates list
        $templatesToBuild = $BuildTemplatesValues | ForEach-Object { "$_" }
        
        Write-Host "Building specific templates: $($templatesToBuild -join ', ')" -ForegroundColor Green
        
        # Validate template values
        foreach ($template in $templatesToBuild) {
            if ($validTemplates -notcontains $template) {
                Write-Error "Invalid template value: $template. Valid values are: $($validTemplates -join ', ')"
                exit 1
            }
        }
    }
}

# Build the engine
if ($BuildEngine) {
    $devArgs = @(
        'dev_build=yes',
        'vsproj=yes',
        'debug_symbols=yes',
        'vsproj_gen_only=no'
    )

    $args = @(
            'platform=windows',
            'target=editor',
            'tracy_enable=yes',
            'CFLAGS="-fno-emit-frame-pointer -fno-inline -ggdb3"',
            'use_mingw=yes'
    )

    if($DevBuild) {
        $args = @($args + $devArgs)
    }

    Start-Process -Wait -NoNewWindow `
        -FilePath 'scons.cmd' `
        -ArgumentList $args
    if (!$?) {
        Write-Error "Failed to build engine"
        exit 1
    }
}

# Build templates
function Build-Export-Template {
    param(
        [string]$Platform,
        [string]$Target,
        [string[]]$AdditionalArgs
    )

    Write-Host "Building export template $Target for $Platform"
    Start-Process -Wait -NoNewWindow `
        -FilePath 'scons.cmd' `
        -ArgumentList (@(
            "platform=$Platform",
            "target=$Target",
            'production=yes',
            'debug_symbols=yes'
        ) + $AdditionalArgs)
    if (!$?) {
        Write-Error "Failed to build engine template $Target for $Platform"
        exit 1
    }
}

function Copy-Template {
    param(
        [string]$SourcePath,
        [string]$DestinationPath
    )
    
    Write-Host "Copying template from $SourcePath to $DestinationPath"
    Copy-Item -Force -Path $SourcePath -Destination $DestinationPath
}

if ($templatesToBuild.Count -gt 0) {
    $windowsArgs = @(
        'arg=x86_64',
        'use_mingw=yes'
    )
    
    $webArgs= @(
        'dlink_enabled=yes',
        'use_lto=yes',
        'module_dlink_enabled=yes'
    )

    $androidArgs = @(
        'arch=arm64'
    )
    
    # Determine which templates to build
    $buildWindowsDebug   = $templatesToBuild -contains 'WindowsDebug'
    $buildWindowsRelease = $templatesToBuild -contains 'WindowsRelease'
    $buildWebDebug       = $templatesToBuild -contains 'WebDebug'
    $buildWebRelease     = $templatesToBuild -contains 'WebRelease'
    $buildAndroidDebug   = $templatesToBuild -contains 'AndroidDebug'
    $buildAndroidRelease = $templatesToBuild -contains 'AndroidRelease'

    # Activate emsdk if any web templates are requested and emcc is not on PATH
    if ($buildWebDebug -or $buildWebRelease) {
        if (-not (Get-Command emcc -ErrorAction SilentlyContinue)) {
            Write-Host "emcc not found on PATH, activating emsdk from C:\emsdk..." -ForegroundColor Yellow
            $emsdkEnv = 'C:\emsdk\emsdk_env.ps1'
            if (Test-Path $emsdkEnv) {
                & $emsdkEnv
            } else {
                Write-Error "emsdk not found at C:\emsdk. Install it first or add emcc to your PATH."
                exit 1
            }
        }
    }
    
    # Build the selected templates
    if ($buildWindowsDebug) {
        Build-Export-Template -Platform 'windows' -Target 'template_debug' -AdditionalArgs $windowsArgs
    }
    
    if ($buildWindowsRelease) {
        Build-Export-Template -Platform 'windows' -Target 'template_release' -AdditionalArgs $windowsArgs
    }
    
    if ($buildWebDebug) {
        Build-Export-Template -Platform 'web' -Target 'template_debug' -AdditionalArgs $webArgs
    }
    
    if ($buildWebRelease) {
        Build-Export-Template -Platform 'web' -Target 'template_release' -AdditionalArgs $webArgs
    }

    if ($buildAndroidDebug) {
        Build-Export-Template -Platform 'android' -Target 'template_debug' -AdditionalArgs $androidArgs
    }

    if ($buildAndroidRelease) {
        Build-Export-Template -Platform 'android' -Target 'template_release' -AdditionalArgs $androidArgs
    }

    # Run gradle to produce Android APKs if any Android templates were built
    if ($buildAndroidDebug -or $buildAndroidRelease) {
        Write-Host "Running Gradle to assemble Android templates..." -ForegroundColor Green
        Push-Location 'platform/android/java'
        try {
            $gradleArgs = if ($buildAndroidDebug -and $buildAndroidRelease) {
                'generateGodotTemplates'
            } elseif ($buildAndroidDebug) {
                'generateDebugGodotTemplates'
            } else {
                'generateReleaseGodotTemplates'
            }
            & .\gradlew.bat $gradleArgs
            if ($LASTEXITCODE -ne 0) {
                Write-Error "Gradle build failed"
                exit 1
            }
        } finally {
            Pop-Location
        }
    }

    # Copy templates to install directory
    $godotVersion = python .\print_version.py
    $templatePath = "$env:APPDATA\Godot\export_templates\$godotVersion"
    New-Item -Force -ItemType 'Directory' -Path $templatePath | Out-Null

    Write-Host "Preparing to copy selected templates to $templatePath"

    # Copy only the templates that were built
    if ($buildWebRelease) {
        Copy-Template -SourcePath 'bin/godot.web.template_release.wasm32.dlink.zip' -DestinationPath "$templatePath\web_dlink_release.zip"
    }
    
    if ($buildWebDebug) {
        Copy-Template -SourcePath 'bin\godot.web.template_debug.wasm32.dlink.zip' -DestinationPath "$templatePath\web_dlink_debug.zip"
    }

    if ($buildWindowsRelease) {
        Copy-Template -SourcePath 'bin\godot.windows.template_release.x86_64.exe' -DestinationPath "$templatePath\windows_release_x86_64.exe"
        Copy-Template -SourcePath 'bin\godot.windows.template_release.x86_64.console.exe' -DestinationPath "$templatePath\windows_release_x86_64_console.exe"
    }
    
    if ($buildWindowsDebug) {
        Copy-Template -SourcePath 'bin\godot.windows.template_debug.x86_64.exe' -DestinationPath "$templatePath\windows_debug_x86_64.exe"
        Copy-Template -SourcePath 'bin\godot.windows.template_debug.x86_64.console.exe' -DestinationPath "$templatePath\windows_debug_x86_64_console.exe"
    }

    if ($buildAndroidDebug) {
        Copy-Template -SourcePath 'bin\android_debug.apk' -DestinationPath "$templatePath\android_debug.apk"
    }

    if ($buildAndroidRelease) {
        Copy-Template -SourcePath 'bin\android_release.apk' -DestinationPath "$templatePath\android_release.apk"
    }

    if ($buildAndroidDebug -or $buildAndroidRelease) {
        Copy-Template -SourcePath 'bin\android_source.zip' -DestinationPath "$templatePath\android_source.zip"
    }
}