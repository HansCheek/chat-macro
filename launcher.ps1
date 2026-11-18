$macroPath = Join-Path $PSScriptRoot 'macro.ps1'
$launchArguments = '-NoProfile -STA -ExecutionPolicy Bypass -WindowStyle Hidden -File "{0}"' -f $macroPath
$portableExecutable = Join-Path $PSScriptRoot 'dist\ChatMacro.exe'
try {
    if (Test-Path -LiteralPath $portableExecutable) {
        Start-Process -FilePath $portableExecutable -WorkingDirectory $PSScriptRoot -WindowStyle Hidden -Verb RunAs -ErrorAction Stop
    } else {
        Start-Process -FilePath (Join-Path $PSHOME 'powershell.exe') -ArgumentList $launchArguments -WorkingDirectory $PSScriptRoot -WindowStyle Hidden -Verb RunAs -ErrorAction Stop
    }
} catch {
    # Cancelling the Windows permission prompt should simply cancel launch.
    $launchError = $_.Exception
    while ($launchError.InnerException) { $launchError = $launchError.InnerException }
    if ($launchError -is [System.ComponentModel.Win32Exception] -and $launchError.NativeErrorCode -eq 1223) { exit 0 }
    Add-Type -AssemblyName System.Windows.Forms
    [void][System.Windows.Forms.MessageBox]::Show($_.Exception.Message, 'Macro launch failed')
    exit 1
}
