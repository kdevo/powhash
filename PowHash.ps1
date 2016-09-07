<#

.SYNOPSIS
    Calculates file hashes by utilizing Get-FileHash, provides a nice progress bar.

.DESCRIPTION
    Use this powershell script to hash multiple files with a nice progress bar. 
    There are several export-possibilites.
    The interactive mode makes it possible to compare with an existing hash (user input).

.OUTPUTS
    Depends on what you specify via OutputType parameter (default: PowerShell object).

.EXAMPLE
    .\PowHash "C:\Example1" -F PowHash -Abs

    Will calculate MD5 and SHA1 hashes (default) with absolute paths and output in PowHash's own format.

.EXAMPLE
    .\PowHash "C:\Example1" "C:\Example2" -A MD5, SHA1, SHA512

    Hashes both Example folders by using MD5, SHA1 and SHA512 algorithms.
    Important is that you use a space (not a comma!) to delimit multiple paths.

.EXAMPLE
    .\PowHash "$env:USERPROFILE\Downloads\*.exe" -R -T JSON-Short -O "$env:USERPROFILE\Downloads\exe_hashes.json"

    Will calculate MD5 and SHA1 hash (default) from every .exe in your download folder.
    Outputs to exe_hashes.json file as JSON. Also includes files in subdirectories (via -R switch).

.EXAMPLE
    (.\PowHash "C:\file.dat" -A MD5 | Select -first 1).Hash | clip

    Will copy the file's MD5 sum to the clipboard.
    Can also be used for directories. Then, the first file's hash will be copied to the clipboard (with "Select -first 1").

.NOTES
    Current version: 1.0a

.LINK
    https://git.io/powhash

#>


Param (
    # Specify multiple paths (files, directories and wildcards like "*.iso" will work).
    # Important: Use a space (' ') to delimit multiple paths! Do NOT use a comma.
    [Parameter(Position = 0, Mandatory=$true, ValueFromRemainingArguments=$true, HelpMessage="Enter the file/directory path(s) to hash.")]
    [Alias("Source", "Src", "File", "Directory")]
    [String[]]$Paths,

    # Specify which hash algorithms you want to use (it's handled as an array - comma-seperate multiple algorithms).
    # Supported algorithms: "SHA1", "SHA256", "SHA384", "SHA512", "MD5", "MACTripleDES", "RIPEMD160"
    # Because needed for a workaround to enable drag 'n' drop, a comma-seperated string is also accepted for the first array element (index: 0). 
    # For instance: "SHA1, SHA256". Not allowed: "SHA1,MD5","SHA256,SHA512".
    [Parameter(HelpMessage="Hash algorithms to use.")]
    [Alias("Algorithms", "A")]
    [String[]]$HashAlgorithms = ("MD5", "SHA1"),

    # Change the way how the hashes are written out .
    # Supported formats: "PowerShell", "PowHash", "JSON-Short", "JSON", "CSV", "XML", "HTML"
    # If you want to work with the result afterwards in another script or command, use "PowerShell".
    # Tip: For file exporting via -OutputFile, use a format which is compact and interchangeable, like "JSON-Short". 
    #      It has less redundant data than "JSON" (which actually is created by using "ConvertTo-JSON") and is easier to read than "XML".
    [Parameter(HelpMessage="Choose an output-format.")]
    [Alias("OutputType", "Format", "F", "Type", "T")]
    [ValidateSet("PowerShell", "PowHash", "JSON-Short", "JSON", "CSV", "XML", "HTML")]
    [String]$OutputFormat = "PowerShell",

    # Specify a file where the results are exported to.
    [Parameter(HelpMessage="Specify a file where the results are exported to.")]
    [Alias("ExportFile", "ExportTo", "ExpTo", "XTo", "XFile", "O")]
    [String]$OutputFile,

    # Enables interactive mode. The script interacts with the user (you) and asks for possible actions.
    # Note that you cannot control the OutputFormat when using this mode.
    [Parameter(HelpMessage="Enable interactive mode for user input.")]
    [Alias("I")]
    [Switch]$Interactive = $false,

    # Enables recursive mode.
    # This will recursively hash every (!) file in every (!) subfolder of this directory.
    [Parameter(HelpMessage="Enable recursive mode.")]
    [Alias("Recursive", "R")]
    [Switch]$Recurse = $false,

    # Enable if you want to have absolute paths instead of filenames only. 
    # Example: "C:\MyFolder\my_file.txt" instead of "my_file.txt".
    [Parameter(HelpMessage="Enables absolute paths instead of outputting filenames only.")]
    [Alias("AbsolutePath", "Absolute", "Abs")]
    [Switch]$AbsolutePaths = $false,

    # Disables the file progress-approximation feature (this could result in a better performance).
    [Parameter(HelpMessage="Disable the file progress-approximation feature.")]
    [Alias("NoFileProgress", "NFP")]
    [Switch]$DisableFileProgress = $false

)

$DebugPreference = "SilentlyContinue" # To enable debugging, change from "SilentlyContinue" to "Continue" or simply use the "-Debug" parameter.
$VerbosePreference = "SilentlyContinue" # To enable verbose output, change from "SilentlyContinue" to "Continue" or simply use the "-Verbose" parameter.
$ProgressPreference = "Continue"

# CONSTANTS {
$VALID_HASH_ALGORITHMS = ("SHA1", "SHA256", "SHA384", "SHA512", "MD5", "MACTripleDES", "RIPEMD160")

$COUNTER_ID_PROCESS = 230
$COUNTER_ID_PID = 784
$COUNTER_ID_READBYTES = 1420

$SYMBOL_FLASH = [char]0x26A1
$SYMBOL_POINTER = [char]0x25BA
$SYMBOL_ARROW_DOWN = [char]0x2193
$SYMBOL_ARROW_RIGHT = [char]0x2192

$TITLE = "PowHash $SYMBOL_FLASH by Pyotek ($SYMBOL_ARROW_RIGHT git.io/pyo)"
# } CONSTANTS

# SETUP {
Set-StrictMode -Version 2.0 # This makes finding typos easier.
$Host.UI.RawUI.WindowTitle = $TITLE

# Preprocess "HashAlgorithms" parameter in case a comma seperated string is used:
if ($HashAlgorithms[0].Contains(',')) {
    if ($HashAlgorithms.Length -gt 1) {
        Write-Error "Please either use an array or a comma-seperated string. Using both is not allowed." -Category InvalidArgument
        return
    } else {
        $HashAlgorithms = $HashAlgorithms[0].Replace(' ', '').Split(',')
    }
}

# We can't use ValidateSet because of the drag 'n' drop workaround for the "HashAlgorithms" parameter as mentioned above.
# Therefore, it is manually validated here:
ForEach ($algo in $HashAlgorithms) {
    if (!($algo -in $VALID_HASH_ALGORITHMS)) {
        Write-Error "`"$algo`" is not a supported hash algorithm. Supported: $VALID_HASH_ALGORITHMS" -Category InvalidArgument 
        return
    }
}
# } SETUP

# FUNCTIONS {
# MS named the perflib's counter dependent on the system's locale... Not so useful for the programmer. 
# For this purpose, this function is needed to get the counter names in your language.
function _Get-CounterById ($id)
{
    $toSearch = (Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Perflib\CurrentLanguage" -Name "Counter").Counter -split '\n'
    return $toSearch[$toSearch.IndexOf("$id")+1]
}

function _Get-ProcessCounterByPID($processPID, $counterProcess, $processSelector, $counterPID, $counterPerf) {
    $counterSamples = (Get-Counter "\$counterProcess($processSelector)\$counterPID", "\$counterProcess($processSelector)\$counterPerf").CounterSamples
    $path = ($counterSamples | Where Path -Like "*\$counterPID" | Where CookedValue -EQ $processPID).Path
    $startPos = $path.IndexOf('(')
    $processName = $path.Substring($startPos+1, $path.IndexOf(')')-$startPos-1)
    ($counterSamples | Where Path -Like "*\$counterPerf" | Where InstanceName -EQ $processName)
}

# NOTE: This function depends on some global variables. #
function _Get-FileHash($filePath, $hashAlgo, $showProgressSize=10000000) {
    $fileSize = (Get-ItemProperty $filePath).Length
    if ($fileSize -gt $showProgressSize -and !$DisableFileProgress) {
        $runspace = [runspacefactory]::CreateRunspace()
        $psThread = [PowerShell]::Create()
        $psThread.Runspace = $runspace
       
        $runspace.Open()
        [void]$psThread.AddScript({
            Param ($filePath, $hashAlgo)
            Get-FileHash $filePath -Algorithm $hashAlgo
        })
        [void]$psThread.AddArgument($filePath).AddArgument($hashAlgo)
        $asyncObj = $psThread.BeginInvoke()
        
        $readBytes = 0
        $animStr = "|/-\"
        $animIdx = 0

        $progressErrors = 0
        while (!$asyncObj.IsCompleted) {
            if ($progressErrors -lt 5) {
                try {
                    $tmp = (_Get-ProcessCounterByPID $PID $counterProcess "powershell*" $counterPID $counterReadBytes)
                    $bytesPerSec = $tmp.CookedValue
                    if ($bytesPerSec -gt 0) { 
                        $readBytes += $bytesPerSec
                        $percent = ($readBytes / $fileSize * 100)
                        if ($percent -le 100) {
                            Write-Progress -Id 1338 -Activity "$SYMBOL_POINTER Hashing file: $filePath" -Status "Calculating $hashAlgo ($($animStr[$animIdx]))"`
                                           -PercentComplete $percent -SecondsRemaining (($fileSize - $readBytes) / $bytesPerSec) `
                                           -CurrentOperation " "
                                           
                            Write-Verbose "Read $readBytes/$fileSize Bytes ($percent %) @ $bytesPerSec Bytes/s."
                            if ($animIdx -eq ($animStr.Length-1)) {
                                $animIdx = 0
                            } else {
                                $animIdx++
                            }
                        }
                    }
                } catch {
                    $progressErrors++
                    Write-Verbose "[!] Catched Exception: $($_.Exception.GetType().FullName). Message: $($_.Exception.Message)"
                }
            } else {
                $global:DisableFileProgress = $true
                # TODO: It's unclear if this is a PS related or Counter API specific bug. The _GetProcessCounterByPID functionality has been checked.
                Write-Warning "[!] Progress has been disabled automatically because reading the counter failed multiple times. This is probably caused because of another opened PS instance."
                break
            }
        }
        $psThread.EndInvoke($asyncObj)
        $psThread.Dispose()
        if ($progressErrors -lt 5) {
            Write-Progress -Id 1338 -Activity "$SYMBOL_POINTER Hashing file: $filePath ($hashAlgo)" -Status "Finished" -PercentComplete 100 -CurrentOperation " "
        }
    } else {
        Get-FileHash $filePath -Algorithm $hashAlgo
    }
}

function _Get-MultipleHashes($paths, $hashAlgos) {
    $pathsToHash = ForEach ($path in $paths) {
        if ([System.Management.Automation.WildcardPattern]::ContainsWildcardCharacters($path) -or (Get-Item $path) -is [System.IO.DirectoryInfo]) {
            Write-Debug "Directory/Path with wildcard found: $path. Needs to be expanded."
            if ($Recurse) {
                $dirItems = Get-ChildItem $path -Recurse
            } else {
                $dirItems = Get-ChildItem $path
            }
            
            ForEach($item in $dirItems) {
                if ((Get-Item $item.FullName) -is [System.IO.FileInfo]) {
                    $item.FullName
                }
            }
        } else {
            Write-Debug "File found: $path."
            $path
        }
    }
    Write-Verbose "Generated list of files to hash: $pathsToHash"
    $fileAmount = ($pathsToHash | Measure-Object).Count
    $count = 0
    $results = ForEach ($path in $pathsToHash) {
        $iAlgo = 0
        ForEach ($algo in $hashAlgos) {
            Write-Progress -Id 1337 -Activity "$SYMBOL_POINTER Processed files: $count/$fileAmount. Remaining: $($fileAmount-$count) files." -Status "Algorithm: $algo (all: $hashAlgorithms)" `
                           -PercentComplete (($count+$iAlgo/$hashAlgos.Length)/$fileAmount * 100) -CurrentOperation " "
            $tmp = _Get-FileHash $path $algo
            $tmp | Add-Member -NotePropertyName Filename -NotePropertyValue ($tmp.Path | Split-Path -Leaf)
            $tmp
            $iAlgo++
        }
        $count++
    }
    Write-Progress -Id 1337 -Activity "$SYMBOL_POINTER Processed files: $count/$fileAmount." -Status "Finished" -PercentComplete 100 -CurrentOperation " " -Completed
    return $results
}


function _Indent($text, $spaces = 4) {
    return $text.PadLeft($spaces + $text.Length)
}

function _ConvertTo-JSONShort($hashes, $indentationSpaces = 2) {
    "["
    For ($i = 0; $i -lt $hashes.Length; $i++) {
        if ($AbsolutePaths) {
            _Indent "$(ConvertTo-Json($hashes[$i].Path)): {" $indentationSpaces
        } else {
            _Indent "$(ConvertTo-Json($hashes[$i].Filename)): {" $indentationSpaces
        }
        For ($a = 0; $a -lt $HashAlgorithms.Length; $a++) {
            if (($a+1) -lt $HashAlgorithms.Length) {
                _Indent "`"$($hashes[$i].Algorithm)`": `"$($hashes[$i].Hash)`"," ($indentationSpaces * 2)
                $i++
            } else {
                _Indent "`"$($hashes[$i].Algorithm)`": `"$($hashes[$i].Hash)`"" ($indentationSpaces * 2)
            }
        }
        if (($i+1) -lt $hashes.Length) {
            _Indent "}," $indentationSpaces
        } else {
            _Indent "}"
        }
    }
    "]"
}


function _ConvertTo-PowHash($hashes, $alreadyGrouped=$false) {
    if ($alreadyGrouped) {
        $group = $hashes
    } else {
        if ($AbsolutePaths) {
            $group = ($hashes | Group-Object Path)
        } else {
            $group = ($hashes | Group-Object Filename)
        }
    }
    $result = ForEach ($obj in $group) {
        "$SYMBOL_POINTER $($obj.Name)"
        ForEach ($hashObj in $obj.Group) {
            _Indent "$($hashObj.Algorithm): $($hashObj.Hash)"
        }
        ""
    }
    return $result
}


function _Show-MenuCompare() {
    Write-Host "=================`n"
    $compareWith = Read-Host "Enter a hash to compare with"
    Write-Host ""
    #Clear-Host

    $groupByPath = ($results | Group-Object Path)
    try {
        $isPath = Test-Path($compareWith)
    } catch {
        $isPath = $false
    }
    if ($isPath -and $false) { # TODO, make comparison with files/directories possible!
        #$compareResults = _Get-MultipleHashes $compareWith $HashAlgorithms
    } else {
        $matchCount = 0
        ForEach ($obj in $groupByPath) {
        $matchIndices = @()
        For ($i = 0; $i -lt $HashAlgorithms.Length; $i++) {
                if ($obj.Group[$i].Hash -eq $compareWith) {
                    $matchIndices += $i
                }
            }
            if ($matchIndices.Length -gt 0) {
                $lines = _ConvertTo-PowHash $obj -alreadyGrouped $true
                Write-Host $lines[0]
                For ($i = 1; $i -le $HashAlgorithms.Length; $i++) {
                    if(($i-1) -in $matchIndices) {
                        Write-Host $lines[$i] -ForegroundColor Green
                    } else {
                        Write-Host $lines[$i]
                    }
                }
                $matchCount++
            }
        }
        if ($matchCount -gt 0) {
            Write-Host "`nMatches: $matchCount. " -ForegroundColor Green -NoNewline
        } else {
            Write-Host "No matches for `"$compareWith`"! " -ForegroundColor Red -NoNewline
        }
        Write-Host "Searched hashes: $($results.Length) from $($groupByPath.Values.Count) file(s)." 
    }
    Write-Host "`n================="
    $yes = New-Object System.Management.Automation.Host.ChoiceDescription "&Yes", "Compare again"
    $no = New-Object System.Management.Automation.Host.ChoiceDescription "&No", "Exit"
    $answer = $Host.UI.PromptForChoice("Next action", "Do you want to compare again?", @($yes, $no), 1)
    Write-Host ""
    switch ($answer) {
        0 { _Show-MenuCompare }
        1 { return }
    }
}
# } FUNCTIONS

# MAIN {
if (!$DisableFileProgress) {
    # Get the counter names in your language here:
    # This is done every start. On modern systems, this shouldn't take too long (about <25ms each per counter).
    # But if you want more speed, insert the counter names here directly instead of invocating "_Get-CounterById" (you can see them if you enable debugging)
    $counterProcess = _Get-CounterById $COUNTER_ID_PROCESS
    $counterPID = _Get-CounterById $COUNTER_ID_PID
    $counterReadBytes = _Get-CounterByID $COUNTER_ID_READBYTES
    Write-Debug "Got relevant counters in your language - Process: '$counterProcess' PID: '$counterPID' Read bytes/s: '$counterReadBytes'"
}

$results = _Get-MultipleHashes $Paths $HashAlgorithms

if ($AbsolutePaths) {
    $output = $results | Select-Object Path,Algorithm,Hash
} else {
    $output = $results | Select-Object Filename,Algorithm,Hash
}

switch ($OutputFormat) {
    "PowHash" { $output = _ConvertTo-PowHash $output }
    "JSON-Short" { $output = _ConvertTo-JSONShort $output }
    "JSON" { $output = $output | ConvertTo-Json }
    "CSV" { $output = $output | ConvertTo-Csv -NoTypeInformation }
    "XML" { $output = $output | ConvertTo-Xml -As String -NoTypeInformation }
    "HTML" { $output = $output | ConvertTo-Html }
}

if ($OutputFile -ne "") {
    $output | Out-File $OutputFile
}
if ($Interactive) {
    Write-Host "`nPowHash $SYMBOL_ARROW_DOWN Results"
    Write-Host "-----------------`n"
    $lines = _ConvertTo-PowHash $results
    ForEach ($l in $lines) { Write-Host $l }
    _Show-MenuCompare
} else {
    $output
}
# } MAIN