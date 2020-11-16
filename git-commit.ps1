<#
    Script:     get-commit.ps1
    Author:     jfabry-noc
    Source:     https://github.com/jfabry-noc/GitCommit
#>

# Class to house each new commit.
class CommitMessage {
    [string] $repoName
    [DateTime] $commitDate
    [string] $commitMessage

    # Empty default constructor.
    CommitMessage() {
        # Does nothing.
    }

    # Constructor that takes all values at time of creation.
    CommitMessage([string]$repoName, [DateTime]$commitDate, [string]$commitMessage) {
        $this.repoName = $repoName
        $this.commitDate = $commitDate
        $this.commitMessage = $commitMessage
    }
}

# Function to query a REST API expecting a list of results.
function QueryRestAPIMulti{
    param(
        [Parameter(Mandatory=$true)]$URL,
        [Parameter(Mandatory=$true)]$AuthString
    )

    # Doing this with Invoke-WebRequest because Invoke-RestMethod is a quarter baked at best...
    WriteLog -Message "Making a query to $URL..." -Type info
    try {
        $request = Invoke-WebRequest -Headers @{Authorization=("Basic {0}" -f $AuthString)} -Uri $URL -UseBasicParsing -Method GET


        # Make sure it was successful.
        if($request.StatusCode -eq 404) {
            WriteLog -Message "Received a 404 from $URL. Skipping..." -Type info
            return $null
        } elseif($request.StatusCode -ne 200) {
            WriteLog -Message "ERROR! Status Code: $($request.StatusCode)." -Type error
            exit 1
        } else {
            return $request.Content | ConvertFrom-Json
        }
    } catch {
        WriteLog -Message "Skipping $URL because the GitHub API is... bad." -Type error
        return $null
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
WriteLog -Message "####################" -Type info
WriteLog -Message "Starting the script..." -Type info

# Define a baseline time assuming the code runs every 4 hours.
$initTimestamp = (Get-Date).AddHours(-4)
$initTimeCustom = (Get-Date -Date $initTimestamp -Format "s") + "Z"

# Define the HTMl file.
$htmlFile = "./html/index.html"

# Define the replacement watermark.
$replacementWatermark = "`t`t`t<!-- Watermark -->`n"

# Ensure errors are cleared.
$Error.clear()

# Start with importing the config.
if(Test-Path -Path "./config.json") {
    $configHash = Get-Content -Path "./config.json" | ConvertFrom-Json
} else {
    WriteLog -Message "Could not find the config file! Quitting..." -Type error
    exit
}

# Define URLs.
$repoListURL = "https://api.github.com/user/repos?visibility=all"
$commitBaseURL = "https://api.github.com/repos/" + $configHash.username + "/"

# Create a list to hold all commit messages that are new since the last run.
$commitMessageList = @()


# Parse together the Base64-encoded string for authentication.
$base64AuthInfo = [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes(("{0}:{1}" -f $configHash.username, $configHash.token)))

# Get the full repository list.
WriteLog -Message "Getting the repository list." -Type info
$repoList = QueryRestAPIMulti -URL $repoListURL -AuthString $base64AuthInfo

# Loop through each repo.
foreach($singleRepo in $repoList) {
    # Get the commits for the repo.
    $currentRepoCommitURL = $commitBaseURL + $singleRepo.name + "/commits?since=" + $initTimeCustom

    # Get the commits.
    $currentCommits = QueryRestAPIMulti -URL $currentRepoCommitURL -AuthString $base64AuthInfo

    # Loop through the commits.
    foreach($singleCommit in $currentCommits) {
        # Check if these are legitimate commits to this repo. If not, just continue.
        if($singleRepo.name -eq "GitCommit" -and $singleCommit.commit.message -like "Added * new commits.") {
            continue
        }

        # Convert the commit time to a DateTime object.
        $currentCommitTime = Get-Date -Date $singleCommit.commit.author.date

        # Check to make sure I made the commit.
        if($singleCommit.author.login -eq "jfabry-noc") {
            # If we made it into the conditional we know the commit should be published.
            $winningCommit = [CommitMessage]::new($singleRepo.name, $currentCommitTime, $singleCommit.commit.message)
            $commitMessageList += $winningCommit
        }
    }
}

# Sort the list of valid commits if there are any.
WriteLog -Message "Completed the gathering of all commits!" -Type info
if($commitMessageList.Count -gt 0) {
    # Sort the commits.
    $commitMessageList = $commitMessageList | Sort-Object -Descending -Property CommitDate

    # Write the HTML for each commit message.
    foreach($singleCommitMessage in $commitMessageList) {
        $replacementWatermark += "`t<h3>" + $singleCommitMessage.repoName + "</h3>`n"
        $replacementWatermark += "`t<p>" + $singleCommitMessage.commitMessage + "</p>`n"
        $replacementWatermark += "`t<p class=`"date`">" + $singleCommitMessage.commitDate + "</p>`n"
    }

    # Update the HTML file. First verify it exists.
    WriteLog -Message "Checking the HTML file." -Type info
    if(Test-Path -Path $htmlFile) {
        # Get the file content.
        $htmlContent = Get-Content -Path $htmlFile

        # Loop through each line and set up the new output.
        $htmlOutput = ""
        foreach($line in $htmlContent) {
            # Update with the new content if we hit the watermark.
            if($line.Trim() -eq "<!-- Watermark -->") {
                WriteLog -Message "Matched on the watermark. Updating..." -Type info
                $line = $replacementWatermark
            }

            # Always write the line regardless, but don't add a newline to the very end.
            if($line -eq '</html>') {
                $htmlOutput += $line
            } else {
                $htmlOutput += $line + "`n"
            }
        }

        Write-Output $htmlOutput
        # Overwrite the HTML file.
        WriteLog -Message "Writing the new HTML file." -Type info
        $htmlOutput | Out-File -Path $htmlFile -Encoding ascii -Force

        # Commit to the repo so that Netlify can update via CI.
        WriteLog -Message "Making a new commit for $($commitMessageList.Count) commits." -Type info
        git add ./html/.
        git commit -m "Added $($commitMessageList.Count) new commit(s)."
        git push origin main
    } else {
        WriteLog -Message "Couldn't find the HTML file! Verify your repository isn't borked! Quitting..." -Type error
        exit(1)
    }
} else {
    WriteLog -Message "No new commits to write! Quitting..." -Type info
}

# Log the end of the script.
WriteLog -Message "Gracefully finished the script." -Type info
