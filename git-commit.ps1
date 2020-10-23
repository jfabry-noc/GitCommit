<#
    Script:     get-commit.ps1
    Author:     jfabry-noc
    Source:     https://github.com/jfabry-noc/GitCommit
#>

# Function to query a REST API expecting a list of results.
function QueryRestAPIMulti{
    param(
        [Parameter(Mandatory=$true)]$URL,
        [Parameter(Mandatory=$true)]$AuthString
    )

    # Start the loop for possible paging.
    while($URL) {
        # Query NCM.
        try {
            $request = Invoke-RestMethod -Headers @{Authorization=("Basic {0}" -f $AuthString)} -Uri $URL -UseBasicParsing -Method GET
            return $request
        } catch {
            Write-Output "Error making the request! Last error was: $($Error[-1])"
        }
    }
}

# Function to backup the log file after a certain size.
function BackupLog {
    # Verify it exists.
    if(-not(Test-Path -Path "./log.txt")) {
        # Just make it and log that it was created.
        New-Item -Path "./" -Name "log.txt" -ItemType File | Out-Null
        WriteLog -Message "No log file found! Creating a new one..." -Type error
    } else {
        # Get the size of the log in MB.
        $currentLogSize = ((Get-Item -Path "./log.txt").Length/1MB)

        # Check the size.
        if($currentLogSize -gt 5) {
            # Check if there's an existing backup file and remove it.
            if(Test-Path -Path "./log.bkp") {
                try {
                    Remove-Item -Path "./log.bkp" -Force

                    # Move the current log file to the old one.
                    try {
                        Rename-Item -Path "./log.txt" -NewName log.bkp

                        # Create a new log.
                        New-Item -Path "./" -Name "log.txt" -ItemType File | Out-Null
                    } catch {
                        WriteLog -Message "Could not rename the old log file!" -Type error
                    }
                } catch {
                    WriteLog -Message "Could not remove the old log file!" -Type error
                }
            } else {
                # Just rename it.
                try {
                    Rename-Item -Path "./log.txt" -NewName log.bkp
                    New-Item -Path "./" -Name "log.txt" -ItemType File | Out-Null
                } catch {
                    WriteLog -Message "Could not rename the old log file!" -Type error
                }
            }
        }
    }
}

# Function to write to the log file since this will run as a scheduled task.
function WriteLog {
    param(
        [Parameter(Mandatory=$true)][string]$Message,
        [Parameter(Mandatory=$true)][ValidateSet("info", "error")]$Type
    )

    # Write the given message to the log.
    Write-Output "$(Get-Date -Format o): $($Type.ToUpper()): $Message" | Out-File -FilePath "./log.txt" -Encoding ascii -Append -NoClobber
}

# Main code.
Set-Location -Path $PSScriptRoot

# Ensure errors are cleared.
$Error.clear()

# Define URLs.
$repoListURL = "https://api.github.com/user/repos?visibility=all"
$commitBaseURL = "https://api.github.com/repos/"

# Start with importing the config.
if(Test-Path -Path "./config.json") {
    $configHash = Get-Content -Path "./config.json" | ConvertFrom-Json
} else {
    Write-Output "Could not find the config file! Quitting..."
    exit
}

# Parse together the Base64-encoded string for authentication.
$base64AuthInfo = [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes(("{0}:{1}" -f $configHash.username, $configHash.token)))

# Get the full repository list.
$repoList = QueryRestAPIMulti -URL $repoListURL -AuthString $base64AuthInfo
Write-Output $repoList
