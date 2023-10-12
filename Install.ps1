<#
.SYNOPSIS
    Synchronize the local HP CMSL repository and then copy to a remote file share.
.DESCRIPTION
    The script initializes or sets up the local HP CMSL repository, synchronizes it with HP's database,
    checks for errors, and optionally copies the repository to a remote file share using Robocopy.
.NOTES
    2023-10-12 Jack den Ouden <Jack@Ldam.nl>
        Script is created.
.LINK
    http://example.com/documentationlink
.EXAMPLE
    .\YourScriptName.ps1 -FSRepoPath "\\RemoteFileShare\HPRepo"
    This will sync the local HP CMSL repository and then copy it to the provided remote file share.
#>

[CmdletBinding()]
param (
    # Parameter help description
    [Parameter()]
    [string]
    $FSRepoPath
)

#* Load Functions
#region
Get-ChildItem -Path "..\Functions" -Filter "*.ps1" -Recurse | ForEach-Object {
    . $_.FullName
}
#endregion

#* Script
#Region

# Install-Module -Name hpcmsl -Scope AllUsers -Force -AcceptLicense
#Install-Module -Name "PowerShellGet" -Scope AllUsers -Force -AllowClobber

$RepoPath = "$PSScriptRoot\Repository"

$ProgressPreference = "SilentlyContinue"

#* Check if Repository exists else build
#region
Set-HPCMSLLogFormat CMTrace

if (!(Test-Path "$($RepoPath)")) {
    New-Item -Path "$($RepoPath)" -ItemType Directory -Force | Out-Null
    Set-Location -Path "$($RepoPath)"
    Initialize-Repository
    Set-RepositoryConfiguration -Setting OfflineCacheMode -CacheValue Enable  # do once
    Set-RepositoryConfiguration -Setting OnRemoteFileNotFound -Value LogAndContinue # do once
}
else {
    Set-Location -Path "$($RepoPath)"

    #* Cleanup old logs
    #region

    $ActivityLog = Get-ChildItem -Path $RepoPath -Recurse -Filter "activity.log"
    if ($ActivityLog) {
        # Ensure $ActivityLog is populated and contains the 'fullname' property
        if ($ActivityLog -and $ActivityLog.fullname) {
            # Get yesterday's date in 'YYYY-MM-DD' format
            $yesterdaysDate = (Get-Date).AddDays(-1).ToString("yyyyMMddHHmmss")

            # Construct the new name for the file
            $newName = "activity_$yesterdaysDate.log"

            # Rename the file
            Rename-Item -Path $ActivityLog.fullname -NewName $newName
        }
        else {
            Write-Error "ActivityLog is not defined or doesn't have the 'fullname' property."
        }

    }

    #endregion
}

#endregion

#* Add Devices to repository
#region
$HPDevices = @(

    Get-HPDeviceDetails -Name "*EliteBook 84*G5*"
    #Get-HPDeviceDetails -Name "*EliteBook 84*G6*"
    #Get-HPDeviceDetails -Name "*EliteBook 84*G7*"
    #Get-HPDeviceDetails -Name "*EliteBook 84*G8*"
    #Get-HPDeviceDetails -Name "*EliteBook 84*G9*"
    #Get-HPDeviceDetails -Name "*EliteBook 84*G10*"
)
($HPDevices | Select-Object -Unique Name).name | ForEach-Object {

    ($HPDevices | Where-Object Name -EQ $_) | ForEach-Object {
        Add-RepositoryFilter -Os win10 -OsVer 21H2 -Category * -Platform $_.SystemID
        Add-RepositoryFilter -Os win10 -OsVer 22H2 -Category * -Platform $_.SystemID
        Add-RepositoryFilter -Os win11 -OsVer 22H2 -Category * -Platform $_.SystemID
    }


}
#endregion

#* Perform Sync
#region

Invoke-RepositorySync -Quiet
Invoke-RepositoryCleanup

#endregion

#* Check for Errors
#region
 
$MissingSoftPaqs = Get-Content -Path (Get-ChildItem -Path $RepoPath -Recurse -Filter "activity.log").fullname  | Where-Object { $_ -match 'failed' } | Select-String -Pattern 'sp\d+\.exe' -AllMatches | ForEach-Object {
    [PSCustomObject]@{
        SoftPaqName = $_.Matches.Value
    }
} | Select-Object SoftPaqName -Unique

if ($MissingSoftPaqs) {
    $MissingSoftPaqs | ForEach-Object {
        $nr = $Null
        $nr = $_.SoftPaqName.replace(".exe", "").replace("sp", "")

        if ($nr) {
            Write-Host "downloading $($_.SoftPaqName)"
            Get-SoftpaqMetadataFile -Number $nr -Quiet -Overwrite:Yes
            Get-Softpaq -Number $nr -Quiet -Overwrite:yes -KeepInvalidSigned
        }
    }
}

#endregion

#* RoboCopy files to FileShare
#region

if ($FSRepoPath) {
    . Robocopy.exe $RepoPath $FSRepoPath /NS /NC /NFL /NDL /NP /NJH /MIR /R:5 /W:5
}
#endregion

#endregion