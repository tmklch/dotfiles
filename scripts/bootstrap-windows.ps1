<#
.SYNOPSIS
Bootstraps the C# Neovim config on Windows.

.DESCRIPTION
Installs Neovim, .NET SDK 10, git, ripgrep, fd, a C++ compiler, and CMake via
winget, then clones (or pulls) the Neovim config repo into place and syncs
plugins/LSP.

.PARAMETER RepoUrl
The git URL of the Neovim config repo. If omitted, falls back to the
NVIM_CONFIG_REPO environment variable, then to the $DefaultRepo placeholder
near the top of this script.

.PARAMETER Help
Show this help text.

.EXAMPLE
.\bootstrap-windows.ps1 https://github.com/youruser/nvim-config.git

.EXAMPLE
$env:NVIM_CONFIG_REPO = "https://github.com/youruser/nvim-config.git"
.\bootstrap-windows.ps1
#>

param(
    [Parameter(Position = 0)]
    [string]$RepoUrl,

    [switch]$Help
)

$ErrorActionPreference = "Stop"

$DefaultRepo = ""  # fill in once the config repo has a remote
$ConfigDir = if ($env:XDG_CONFIG_HOME) { Join-Path $env:XDG_CONFIG_HOME "nvim" } else { "$env:LOCALAPPDATA\nvim" }

function Show-Help {
    Get-Help $PSCommandPath -Full
}

function Resolve-RepoUrl {
    param([string]$ArgUrl)

    if ($ArgUrl) { return $ArgUrl }
    if ($env:NVIM_CONFIG_REPO) { return $env:NVIM_CONFIG_REPO }
    return $DefaultRepo
}

function Update-EnvPath {
    $machinePath = [System.Environment]::GetEnvironmentVariable("Path", "Machine")
    $userPath = [System.Environment]::GetEnvironmentVariable("Path", "User")
    $env:Path = "$machinePath;$userPath"
}

function Install-Prerequisite {
    param(
        [string]$Id,
        [string[]]$ExtraArgs = @()
    )
    Write-Host "==> Installing $Id via winget..."
    $installArgs = @("install", "--id", $Id, "-e", "--source", "winget", "--accept-package-agreements", "--accept-source-agreements") + $ExtraArgs
    & winget @installArgs
    $installExit = $LASTEXITCODE

    if ($installExit -ne 0) {
        $listResult = & winget list --id $Id --source winget 2>$null
        if ($LASTEXITCODE -ne 0 -or -not ($listResult -match [regex]::Escape($Id))) {
            throw "winget install of $Id failed (exit $installExit) and it is not already installed."
        }
        Write-Host "==> $Id is already installed, continuing."
    }
}

function Install-Prerequisites {
    Install-Prerequisite -Id "Neovim.Neovim"
    Install-Prerequisite -Id "Microsoft.DotNet.SDK.10"
    Install-Prerequisite -Id "Git.Git"
    Install-Prerequisite -Id "BurntSushi.ripgrep.MSVC"
    Install-Prerequisite -Id "sharkdp.fd"
    Install-Prerequisite -Id "tree-sitter.tree-sitter-cli"
    Install-Prerequisite -Id "Kitware.CMake"
    Install-Prerequisite -Id "Microsoft.VisualStudio.2022.BuildTools" -ExtraArgs @(
        "--override", "--wait --quiet --add Microsoft.VisualStudio.Workload.VCTools --includeRecommended"
    )
}

function Deploy-Config {
    param([string]$RepoUrl, [string]$TargetDir)

    if (Test-Path (Join-Path $TargetDir ".git")) {
        $currentOrigin = (git -C $TargetDir remote get-url origin 2>$null)
        if ($currentOrigin -eq $RepoUrl) {
            Write-Host "==> Existing config at $TargetDir already tracks $RepoUrl, pulling latest..."
            git -C $TargetDir pull
            return
        }
    }

    if (Test-Path $TargetDir) {
        $backup = "$TargetDir.bak.$(Get-Date -Format yyyyMMddHHmmss)"
        Write-Host "==> Backing up existing config to $backup"
        Move-Item -Path $TargetDir -Destination $backup
    }

    Write-Host "==> Cloning $RepoUrl into $TargetDir"
    git clone $RepoUrl $TargetDir
}

function Sync-Plugins {
    Write-Host "==> Syncing plugins..."
    nvim --headless "+Lazy! sync" +qa
    Write-Host "==> Installing Roslyn via Mason..."
    nvim --headless -c "MasonInstall roslyn" -c "qa"
    Write-Host "==> Installing C# treesitter parser..."
    nvim --headless -c "lua require('nvim-treesitter').install({'c_sharp'}):wait(300000)" -c "qa"
}

function Main {
    if ($Help) {
        Show-Help
        return
    }

    $resolvedUrl = Resolve-RepoUrl -ArgUrl $RepoUrl
    if (-not $resolvedUrl) {
        Write-Error "No config repo URL given. Pass it as an argument, set NVIM_CONFIG_REPO, or edit `$DefaultRepo in this script."
        exit 1
    }

    Install-Prerequisites
    Update-EnvPath
    Deploy-Config -RepoUrl $resolvedUrl -TargetDir $ConfigDir
    Sync-Plugins

    Write-Host ""
    Write-Host "==> Done. Open a .cs file in nvim to verify (e.g. nvim path\to\file.cs)."
}

Main
