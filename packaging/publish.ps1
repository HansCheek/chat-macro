param([string]$ReleaseNotesPath)
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$config = Get-Content -LiteralPath (Join-Path $PSScriptRoot 'version.json') -Raw | ConvertFrom-Json
$repository = $config.repository
$version = $config.version
$tag = 'v' + $version

# Git Credential Manager supplies the token in memory; never print or persist it here.
$env:GCM_INTERACTIVE = 'never'
$env:GIT_TERMINAL_PROMPT = '0'
$request = "protocol=https`nhost=github.com`n`n"
$credentialLines = $request | git credential fill 2>$null
$credential = @{}
foreach ($line in $credentialLines) {
    $parts = $line -split '=', 2
    if ($parts.Count -eq 2) { $credential[$parts[0]] = $parts[1] }
}
if (-not $credential.ContainsKey('password')) { throw 'Sign in through Git Credential Manager first.' }
$headers = @{ Authorization = 'Bearer ' + $credential['password']; 'User-Agent' = 'ChatMacro-Publisher'; Accept = 'application/vnd.github+json' }
$profile = Invoke-RestMethod -Uri 'https://api.github.com/user' -Headers $headers
if ($repository.Split('/')[0] -ine $profile.login) { throw 'The configured repository owner does not match the authenticated account.' }
$api = 'https://api.github.com/repos/' + $repository
try {
    $repo = Invoke-RestMethod -Uri $api -Headers $headers
} catch {
    if ([int]$_.Exception.Response.StatusCode -ne 404) { throw }
    $body = @{ name = $repository.Split('/')[1]; description = '선택한 클라이언트에 채팅 자동 입력 · 자동 중지 · 선택적 PC 종료 · 서명 검증 자동 업데이트'; private = $false; auto_init = $false } | ConvertTo-Json
    $repo = Invoke-RestMethod -Method Post -Uri 'https://api.github.com/user/repos' -Headers $headers -ContentType 'application/json; charset=utf-8' -Body ([Text.Encoding]::UTF8.GetBytes($body))
}
if ($repo.private) { throw 'Automatic anonymous updates require the intended public repository.' }
try {
    $existing = Invoke-RestMethod -Uri ($api + '/releases/tags/' + $tag) -Headers $headers
    throw "Release $tag already exists. Increment packaging/version.json before publishing."
} catch {
    if (-not $_.Exception.Response -or [int]$_.Exception.Response.StatusCode -ne 404) { throw }
}

& (Join-Path $PSScriptRoot 'build.ps1')
Push-Location $root
try {
    if (-not (Test-Path -LiteralPath '.git')) {
        git init -b main
        if ($LASTEXITCODE -ne 0) { throw 'git init failed.' }
    }
    git config --local user.name $profile.login
    git config --local user.email ($profile.id.ToString() + '+' + $profile.login + '@users.noreply.github.com')
    $remote = git remote get-url origin 2>$null
    $expectedRemote = 'https://github.com/' + $repository + '.git'
    if ($LASTEXITCODE -ne 0) { git remote add origin $expectedRemote }
    elseif ($remote -ne $expectedRemote) { throw 'Origin points to a different repository.' }
    git add -- .gitignore README.md macro.ps1 launcher.ps1 '실행.bat' '사용법.txt' assets packaging
    if ($LASTEXITCODE -ne 0) { throw 'git add failed.' }
    $trackedSecrets = git ls-files -- .release-secrets
    if ($trackedSecrets) { throw 'Refusing to publish signing secrets.' }
    git diff --cached --quiet
    if ($LASTEXITCODE -eq 1) {
        git commit -m ("Release " + $tag + ": signed startup auto-update")
        if ($LASTEXITCODE -ne 0) { throw 'git commit failed.' }
    }
    git push -u origin HEAD:main
    if ($LASTEXITCODE -ne 0) { throw 'git push failed.' }
    git tag $tag
    if ($LASTEXITCODE -ne 0) { throw 'git tag failed.' }
    git push origin $tag
    if ($LASTEXITCODE -ne 0) { throw 'git tag push failed.' }
} finally { Pop-Location }

$notes = ''
if ($ReleaseNotesPath) { $notes = [IO.File]::ReadAllText((Resolve-Path -LiteralPath $ReleaseNotesPath)) }
else { $notes = "채팅 매크로 $tag`n`n- 시작 시 최신 버전 자동 확인 및 적용`n- 업데이트 서명과 SHA-256 검증`n- 인터넷 연결 실패 시 기존 버전 실행`n- 선택한 클라 입력, 분 단위 자동 중지, 선택적 PC 종료 유지`n`nChatMacro.exe를 다운로드해 실행하세요. PC 자동 종료는 기본으로 꺼져 있습니다." }
$releaseBody = @{ tag_name = $tag; target_commitish = 'main'; name = "채팅 매크로 $tag"; body = $notes; draft = $true; prerelease = $false } | ConvertTo-Json
$release = Invoke-RestMethod -Method Post -Uri ($api + '/releases') -Headers $headers -ContentType 'application/json; charset=utf-8' -Body ([Text.Encoding]::UTF8.GetBytes($releaseBody))
$uploadBase = $release.upload_url -replace '\{.*$', ''
foreach ($name in @('ChatMacro.exe', 'update.json', 'SHA256.txt', "ChatMacro-$version.zip")) {
    $path = Join-Path (Join-Path $root 'dist') $name
    $uri = $uploadBase + '?name=' + [Uri]::EscapeDataString($name)
    $asset = Invoke-RestMethod -Method Post -Uri $uri -Headers $headers -ContentType 'application/octet-stream' -InFile $path
    Write-Output ('Uploaded ' + $asset.name)
}
$published = Invoke-RestMethod -Method Patch -Uri ($api + '/releases/' + $release.id) -Headers $headers -ContentType 'application/json' -Body '{"draft":false,"make_latest":"true"}'
Write-Output ('Published: ' + $published.html_url)
Write-Output ('Download: https://github.com/' + $repository + '/releases/latest/download/ChatMacro.exe')
