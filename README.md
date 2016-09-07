# PowHash
:warning: **Test/Alpha phase**

This PowerShell script makes it possible to hash multiple files **with progress** - plus drag 'n' drop support.

To achieve this, it utilizes the existing [Get-FileHash Utility Cmdlet](https://technet.microsoft.com/library/dn520872.aspx) (which *does not* have a progress indicator) and reads Windows' I/O performance counter data for an approximation of the current progress via [Get-Counter](https://technet.microsoft.com/library/hh849685.aspx).

## Features

- Batch-Hashing - path(s) can be a file or a directory, plus wildcard
- Hash-Algorithms: SHA1, SHA256, SHA384, SHA512, MD5, MACTripleDES, RIPEMD160 (same as [Get-FileHash](https://technet.microsoft.com/library/dn520872.aspx))
- Progress bar shows up when hashing bigger files
- Many export possibilites: PowerShell's standard out, custom PowHash formnat, JSON, HTML, XML, CSV
- Drag 'n' Drop via shortcut (Drag 'n' Hash)
- interactive mode: paste an existing hash to compare
- pure PS script - you only need a working PowerShell, no installation needed

## How to use?

The only requirement on Windows 10 (probably also on older versions) is an [Execution Policy](https://technet.microsoft.com/library/hh847748.aspx) which allows you to run the script.

After you got scripts running you can...
- invoke the **ShortcutHelper.ps1** script if you want to have a shortcut on your desktop where you can simply drag 'n' drop your files to hash. (*You can also create it yourself by specifiying `powershell.exe -NoLogo -File "<PATH_TO_POWHASH>" -I` as a target*)
- always **get help about available parameters** with the `Get-Help <PATH_TO_POWHASH>` command

Enough talk, here are some examples!
## Examples

```powershell
.\PowHash "C:\Example1" -F PowHash -Abs
```
Will calculate MD5 and SHA1 hashes (default) with absolute paths and output in PowHash's own format.

```powershell
.\PowHash "C:\Example1" "C:\Example2" -A MD5, SHA1, SHA512
```
Hashes both Example folders by using MD5, SHA1 and SHA512 algorithms.
Important is that you use a space (not a comma!) to delimit multiple paths.

```powershell
.\PowHash "$env:USERPROFILE\Downloads\*.exe" -R -T JSON-Short -O "$env:USERPROFILE\Downloads\exe_hashes.json"
```
Will calculate MD5 and SHA1 hash (default) from every .exe in your download folder.
Outputs to exe_hashes.json file as JSON. Also includes files in subdirectories (via -R switch).

```powershell
(.\PowHash "C:\file.dat" -A MD5 | Select -first 1).Hash | clip
```
Will copy the file's MD5 sum to the clipboard.
Can also be used for directories. Then, the first file's hash will be copied to the clipboard (with "Select -first 1").
