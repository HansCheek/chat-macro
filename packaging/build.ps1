param([string]$Version, [string]$Repository)
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$settings = Get-Content -LiteralPath (Join-Path $PSScriptRoot 'version.json') -Raw | ConvertFrom-Json
if (-not $Version) { $Version = $settings.version }
if (-not $Repository) { $Repository = $settings.repository }
if ($Version -notmatch '^\d{1,5}\.\d{1,5}\.\d{1,5}$') { throw 'Use a version such as 1.1.0.' }
if ($Repository -notmatch '^[A-Za-z0-9-]+/[A-Za-z0-9_.-]+$') { throw 'Use owner/repository.' }
$dist = Join-Path $root 'dist'
$generated = Join-Path $PSScriptRoot 'generated'
$secrets = Join-Path $root '.release-secrets'
foreach ($directory in @($dist, $generated, $secrets)) { [void][IO.Directory]::CreateDirectory($directory) }
$keyPath = Join-Path $secrets 'update-signing-key.xml'
$rsa = New-Object Security.Cryptography.RSACryptoServiceProvider(3072)
$rsa.PersistKeyInCsp = $false
try {
    if (Test-Path -LiteralPath $keyPath) { $rsa.FromXmlString([IO.File]::ReadAllText($keyPath)) }
    else { [IO.File]::WriteAllText($keyPath, $rsa.ToXmlString($true), [Text.Encoding]::ASCII) }
    $publicKey = $rsa.ToXmlString($false)
    $config = @{ repository = $Repository; publicKey = $publicKey } | ConvertTo-Json
    [IO.File]::WriteAllText((Join-Path $generated 'update-config.json'), $config, (New-Object Text.UTF8Encoding($false)))
    $assemblyInfo = '[assembly: System.Reflection.AssemblyVersion("' + $Version + '.0")]' + "`r`n" + '[assembly: System.Reflection.AssemblyFileVersion("' + $Version + '.0")]'
    [IO.File]::WriteAllText((Join-Path $generated 'Version.cs'), $assemblyInfo, [Text.Encoding]::UTF8)
    $manifest = [IO.File]::ReadAllText((Join-Path $PSScriptRoot 'app.manifest')).Replace('version="1.0.0.0"', ('version="' + $Version + '.0"'))
    [IO.File]::WriteAllText((Join-Path $generated 'app.manifest'), $manifest, [Text.Encoding]::UTF8)
    $compiler = Join-Path $env:SystemRoot 'Microsoft.NET\Framework64\v4.0.30319\csc.exe'
    if (-not (Test-Path -LiteralPath $compiler)) { $compiler = Join-Path $env:SystemRoot 'Microsoft.NET\Framework\v4.0.30319\csc.exe' }
    $executable = Join-Path $dist 'ChatMacro.exe'
    $compilerArguments = @(
        '/nologo', '/target:winexe', '/platform:anycpu', '/optimize+', '/codepage:65001'
        ('/out:' + $executable)
        ('/win32icon:' + (Join-Path $root 'assets\chat-macro.ico'))
        ('/win32manifest:' + (Join-Path $generated 'app.manifest'))
        '/reference:System.Windows.Forms.dll', '/reference:System.Drawing.dll', '/reference:System.Web.Extensions.dll'
        ('/resource:' + (Join-Path $root 'macro.ps1') + ',macro.ps1')
        ('/resource:' + (Join-Path $root 'assets\chat-macro.png') + ',assets/chat-macro.png')
        ('/resource:' + (Join-Path $root 'assets\chat-macro.ico') + ',assets/chat-macro.ico')
        ('/resource:' + (Join-Path $generated 'update-config.json') + ',update-config.json')
        (Join-Path $generated 'Version.cs')
        (Join-Path $PSScriptRoot 'StartupUpdater.cs')
        (Join-Path $PSScriptRoot 'ChatMacroLauncher.cs')
    )
    & $compiler @compilerArguments
    if ($LASTEXITCODE -ne 0) { throw 'Executable build failed.' }
    $hash = (Get-FileHash -LiteralPath $executable -Algorithm SHA256).Hash
    $canonical = "ChatMacro-Update-v1`n$Repository`n$Version`nChatMacro.exe`n$hash`n"
    $signature = [Convert]::ToBase64String($rsa.SignData([Text.Encoding]::UTF8.GetBytes($canonical), 'SHA256'))
    $updateManifest = [ordered]@{ format = 1; repository = $Repository; version = $Version; asset = 'ChatMacro.exe'; sha256 = $hash; signature = $signature }
    [IO.File]::WriteAllText((Join-Path $dist 'update.json'), ($updateManifest | ConvertTo-Json), (New-Object Text.UTF8Encoding($false)))
    Copy-Item -LiteralPath (Join-Path $root '사용법.txt') -Destination (Join-Path $dist '사용법.txt') -Force
    Compress-Archive -LiteralPath $executable, (Join-Path $dist '사용법.txt') -DestinationPath (Join-Path $dist "ChatMacro-$Version.zip") -Force
    [IO.File]::WriteAllText((Join-Path $dist 'SHA256.txt'), "$hash  ChatMacro.exe`r`n", [Text.Encoding]::ASCII)
    Write-Output "Built version $Version for $Repository"
    Write-Output $executable
} finally { $rsa.Dispose() }