# Installs the developer toolchain and writes an image manifest (what's installed, which versions).
# Lab: packages come from the public Chocolatey community repository. In a bank, the source would be
# an internal mirror (e.g. an Artifactory NuGet/Chocolatey remote with Xray scanning), and versions
# would be pinned.
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

Set-ExecutionPolicy Bypass -Scope Process -Force
[Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor 3072
Invoke-Expression ((New-Object Net.WebClient).DownloadString('https://community.chocolatey.org/install.ps1'))
$env:Path += ";$env:ALLUSERSPROFILE\chocolatey\bin"

$packages = @('git', 'vscode', 'python', 'azure-cli', 'terraform', 'kubernetes-cli')
foreach ($p in $packages) {
  Write-Output "== installing $p"
  choco install $p -y --no-progress
  if ($LASTEXITCODE -notin 0, 3010) { throw "choco install $p failed with exit code $LASTEXITCODE" }
}

# Traceability: which image version contains which tool versions.
$installed = choco list --limit-output | ForEach-Object {
  $name, $version = $_ -split '\|'
  [pscustomobject]@{ name = $name; version = $version }
}
New-Item -ItemType Directory -Force -Path "$env:ProgramData\platformlab" | Out-Null
[pscustomobject]@{
  built_utc = (Get-Date).ToUniversalTime().ToString('o')
  base      = 'MicrosoftWindowsServer:WindowsServer:2025-datacenter-azure-edition-smalldisk'
  packages  = $installed
} | ConvertTo-Json -Depth 3 | Set-Content -Encoding utf8 "$env:ProgramData\platformlab\image-manifest.json"
Get-Content "$env:ProgramData\platformlab\image-manifest.json"
