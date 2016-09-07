$VALID_HASH_ALGORITHMS = "SHA1", "SHA256", "SHA384", "SHA512", "MD5", "MACTripleDES", "RIPEMD160"
$DEFAULT_HASH_ALGORITHMS = "MD5,SHA1"
$SHORTCUT_PATH = "$env:USERPROFILE\Desktop\PowHash - Drag 'n' Hash.lnk"

do {
    $hashAlgos = Read-Host "Please type the hash algorithms you want to use as a comma-seperated list (default: MD5,SHA1)"
    $hashAlgos = $hashAlgos.Replace(" ", "")
    if ($hashAlgos -eq "") {
        $hashAlgos = $DEFAULT_HASH_ALGORITHMS
    } else {
        $splitAlgos = $hashAlgos.Split(',')
        ForEach ($algo in $splitAlgos) {
            if (!($algo -in $VALID_HASH_ALGORITHMS)) {
                Write-Host "The algorithm `"$algo`" is not a supported hash algorithm. " -NoNewline -ForegroundColor Red; Write-Host "Supported: $VALID_HASH_ALGORITHMS"
                $hashAlgos = ""
                break
            }
        }
    }
} while($hashAlgos -eq "")


$ws = New-Object -ComObject WScript.Shell
$shortcut = $ws.CreateShortcut($SHORTCUT_PATH)
$shortcut.TargetPath = "$PSHOME\powershell.exe"
$shortcut.Arguments = "-NoLogo -File `"$PSScriptRoot\PowHash.ps1`" -A `"$hashAlgos`" -I"
$shortcut.Description = "Launches PowHash to hash your files via drag 'n' drop."
$shortcut.IconLocation = "$PSHOME\powershell.exe"
$shortcut.Save()

Write-Host "Shortcut `"$SHORTCUT_PATH`" created. It's ready to use for drag 'n' drop." -ForegroundColor Green
Sleep 4