Import-Module File

enum RCloneOperation {
    copyto
    sync
}

function Get-RCloneCommand (
    [Parameter(Mandatory = $true)] [RCloneOperation] $Operation
    , [Parameter(Mandatory = $true)] [string] $Source
    , [Parameter(Mandatory = $true)] [string] $Destination
    , [Parameter(Mandatory = $false)] [string] $Flags
    , [Parameter(Mandatory = $false)] $Config = (Get-ProfileConfig)
) {
    $line = "rclone $Operation $Source $Destination"
    if ($Flags) { $line += " $Flags" }

    Get-ConsoleCommandAsRoot `
        -Line $line `
        -Config $Config
}

function Invoke-RCloneGroup (
    [Parameter(Mandatory = $true)] [string] $GroupName
    , [Parameter(Mandatory = $false)] [string] $Filter
    , [Parameter(Mandatory = $false)] [switch] $Restore
    , [Parameter(Mandatory = $false)] [switch] $CopyLinks
    , [Parameter(Mandatory = $false)] [switch] $DryRun
    , [Parameter(Mandatory = $false)] [switch] $WhatIf
    , [Parameter(Mandatory = $false)] $Config = (Get-ProfileConfig)
) {
    $backupGroup = Get-RCloneBackupGroup $GroupName $Filter
    if (-not $backupGroup) {
        $f = if ($Filter) { ", filter: $Filter" } else { '' }
        Write-Output "no backup group found for group name: $GroupName$f"
        return
    }

    $backupGroupRemote = Get-RCloneBackupGroupRemote $GroupName
    if (-not $backupGroupRemote) {
        Write-Output "no backup group remote found for group name: $GroupName"
        return
    }

    $remote = $backupGroupRemote.Remote

    $commands = @()

    foreach ($backup in $backupGroup) {
        $path =
            $ExecutionContext.InvokeCommand.ExpandString(
                $backup.Path
            )

        $flags = ''
        if ($CopyLinks.IsPresent) { $flags += ' --copy-links' }
        if ($DryRun.IsPresent) { $flags += ' --dry-run' }

        $localPath = ConvertTo-CrossPlatformPathFormat $path

        $source = "$($Config['rClone']['remote']):`"$localPath`""

        $remotePathPrefix = ConvertTo-CrossPlatformPathFormat `
            $ExecutionContext.InvokeCommand.ExpandString(
                $backupGroupRemote.RemotePath
            )

        $remotePathPostfix = ConvertTo-ExpandedDirectoryPathFormat `
            $ExecutionContext.InvokeCommand.ExpandString(
                $(
                    if ($backup.NewPath) { $backup.NewPath }
                    else { $path }
                )
            )

        $remotePath = "$remotePathPrefix/$(Edit-TrimForwardSlashes $remotePathPostfix)"

        $destination = "$($remote):`"$remotePath`""

        if ($Restore.IsPresent) {
            $p = $source
            $source = $destination
            $destination = $p
        }

        $pathToCheck = if ($Restore.IsPresent) { $remotePath } else { $localPath }

        $commands +=
        if (-not (Test-PathAsRoot -Path $pathToCheck)) {
            Get-ConsoleCommand `
                -Line "Write-Output 'skipping - invalid path: $pathToCheck'" `
                -Config $Config
        } else {
            Get-RCloneCommand `
                -Operation $(
                    if (Test-PathAsRoot -Path $pathToCheck -PathType Leaf) {
                        [RCloneOperation]::copyto
                    } else {
                        [RCloneOperation]::sync
                    }
                ) `
                -Source $source `
                -Destination $destination `
                -Flags $flags `
                -Config $Config
        }
    }

    Invoke-CommandsConcurrent `
        -Commands $commands `
        -WhatIf:$WhatIf
}