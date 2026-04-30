# Claude Code Installer for Windows
# Usage: irm https://claude.ai/install.ps1 | iex

[CmdletBinding()]
param(
    [string]$Version = "latest",
    [switch]$NoVerify
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$ClaudePackage = "@anthropic-ai/claude-code"
$MinNodeVersion = 18

function Write-Header {
    Write-Host ""
    Write-Host "  Claude Code Installer" -ForegroundColor Cyan
    Write-Host "  =====================" -ForegroundColor Cyan
    Write-Host ""
}

function Write-Step {
    param([string]$Message)
    Write-Host "  --> $Message" -ForegroundColor White
}

function Write-Success {
    param([string]$Message)
    Write-Host "  OK  $Message" -ForegroundColor Green
}

function Write-Warn {
    param([string]$Message)
    Write-Host "  !   $Message" -ForegroundColor Yellow
}

function Write-Fail {
    param([string]$Message)
    Write-Host "  ERR $Message" -ForegroundColor Red
}

function Test-Administrator {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = [Security.Principal.WindowsPrincipal]$identity
    return $principal.IsInRole([Security.Principal.WindowsBuiltinRole]::Administrator)
}

function Get-NodeVersion {
    try {
        $raw = & node --version 2>$null
        if ($raw -match '^v(\d+)') {
            return [int]$Matches[1]
        }
    } catch {}
    return 0
}

function Install-NodeViaWinget {
    Write-Step "Installing Node.js via winget..."
    try {
        & winget install --id OpenJS.NodeJS.LTS --accept-source-agreements --accept-package-agreements --silent
        # Refresh PATH for current session
        $env:Path = [System.Environment]::GetEnvironmentVariable("Path", "Machine") + ";" +
                    [System.Environment]::GetEnvironmentVariable("Path", "User")
        return $true
    } catch {
        return $false
    }
}

function Install-NodeViaChoco {
    Write-Step "Installing Node.js via Chocolatey..."
    try {
        & choco install nodejs-lts --yes --no-progress
        $env:Path = [System.Environment]::GetEnvironmentVariable("Path", "Machine") + ";" +
                    [System.Environment]::GetEnvironmentVariable("Path", "User")
        return $true
    } catch {
        return $false
    }
}

function Assert-NodeInstalled {
    $version = Get-NodeVersion
    if ($version -ge $MinNodeVersion) {
        Write-Success "Node.js v$version found"
        return
    }

    if ($version -gt 0) {
        Write-Fail "Node.js v$version is installed but Claude Code requires v$MinNodeVersion or newer."
        Write-Host "  Download the latest LTS from: https://nodejs.org" -ForegroundColor Yellow
        exit 1
    }

    Write-Warn "Node.js not found. Attempting automatic installation..."

    $installed = $false

    if (Get-Command winget -ErrorAction SilentlyContinue) {
        $installed = Install-NodeViaWinget
    }

    if (-not $installed -and (Get-Command choco -ErrorAction SilentlyContinue)) {
        $installed = Install-NodeViaChoco
    }

    if (-not $installed) {
        Write-Fail "Could not install Node.js automatically."
        Write-Host ""
        Write-Host "  Please install Node.js v$MinNodeVersion+ manually:" -ForegroundColor Yellow
        Write-Host "    https://nodejs.org/en/download" -ForegroundColor Cyan
        Write-Host ""
        exit 1
    }

    $version = Get-NodeVersion
    if ($version -lt $MinNodeVersion) {
        Write-Fail "Node.js installation failed or version is too old (found v$version, need v$MinNodeVersion+)."
        exit 1
    }

    Write-Success "Node.js v$version installed"
}

function Assert-NpmAvailable {
    if (-not (Get-Command npm -ErrorAction SilentlyContinue)) {
        Write-Fail "npm not found. Please reinstall Node.js from https://nodejs.org"
        exit 1
    }
}

function Install-ClaudeCode {
    $packageSpec = if ($Version -eq "latest") { $ClaudePackage } else { "${ClaudePackage}@${Version}" }
    Write-Step "Installing $packageSpec..."

    try {
        $npmArgs = @("install", "--global", $packageSpec, "--loglevel=error")
        & npm @npmArgs
        if ($LASTEXITCODE -ne 0) {
            throw "npm exited with code $LASTEXITCODE"
        }
    } catch {
        # Retry with --prefer-online in case of cache corruption
        Write-Warn "First attempt failed, retrying with --prefer-online..."
        & npm install --global $packageSpec --loglevel=error --prefer-online
        if ($LASTEXITCODE -ne 0) {
            Write-Fail "Failed to install Claude Code. Run with -Verbose for details."
            exit 1
        }
    }
}

function Test-ClaudeInstalled {
    # Refresh PATH so newly installed global npm bins are visible
    $npmPrefix = & npm prefix --global 2>$null
    if ($npmPrefix) {
        $npmBin = Join-Path $npmPrefix "bin"
        if ($env:Path -notlike "*$npmBin*") {
            $env:Path = "$npmBin;$env:Path"
        }
    }

    if (Get-Command claude -ErrorAction SilentlyContinue) {
        return $true
    }
    return $false
}

function Show-PostInstall {
    $claudeVersion = ""
    try { $claudeVersion = " $(& claude --version 2>$null)" } catch {}

    Write-Host ""
    Write-Host "  ============================================" -ForegroundColor Cyan
    Write-Host "  Claude Code$claudeVersion installed successfully!" -ForegroundColor Green
    Write-Host "  ============================================" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "  Get started:" -ForegroundColor White
    Write-Host "    claude          - start an interactive session" -ForegroundColor Gray
    Write-Host "    claude --help   - show all commands" -ForegroundColor Gray
    Write-Host ""
    Write-Host "  Docs: https://docs.anthropic.com/claude-code" -ForegroundColor Cyan
    Write-Host ""
}

function Show-PathWarning {
    Write-Host ""
    Write-Warn "The 'claude' command was not found in your current PATH."
    Write-Host ""
    Write-Host "  This usually means npm's global bin directory is not in your PATH." -ForegroundColor Yellow
    Write-Host "  Either restart your terminal or add npm's global bin to your PATH:" -ForegroundColor Yellow
    Write-Host ""
    $npmBin = & npm prefix --global 2>$null
    if ($npmBin) {
        Write-Host "    $npmBin\bin" -ForegroundColor Cyan
    }
    Write-Host ""
    Write-Host "  To add it permanently, run:" -ForegroundColor Yellow
    Write-Host '    [Environment]::SetEnvironmentVariable("Path", $env:Path + ";' + "$npmBin\bin" + '", "User")' -ForegroundColor Gray
    Write-Host ""
}

# ---- Main ----------------------------------------------------------------

Write-Header

# Windows-only guard
if (-not $IsWindows -and $PSVersionTable.PSVersion.Major -ge 6) {
    Write-Fail "This script is for Windows only."
    Write-Host "  For macOS/Linux, run:" -ForegroundColor Yellow
    Write-Host "    npm install -g @anthropic-ai/claude-code" -ForegroundColor Cyan
    exit 1
}

Assert-NodeInstalled
Assert-NpmAvailable
Install-ClaudeCode

if (Test-ClaudeInstalled) {
    Show-PostInstall
} else {
    Show-PostInstall
    Show-PathWarning
}
