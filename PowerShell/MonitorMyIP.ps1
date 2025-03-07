<#
.SYNOPSIS
A script to monitor a public IP address and send an email to the email associated with a Microsoft Account.

.PARAMETER PhoneNumber
The phone number of the user to send a text (Script Modification Required).

.PARAMETER EmailFrom
The "From" Email Address.

.PARAMETER EmailTo
The "To" Email Address.

.PARAMETER EmailServer
The SMTP Server Address.

.PARAMETER EmailAccount
The account for authenticating email access. Defaults to "EmailFrom".

.PARAMETER Password
The password for the EmailAccount/EmailFrom Account.

.PARAMETER AccessType
The EMail Processor.

.PARAMETER CheckEveryMinutes
The number of minutes to wait to re-check. Must be an integer.
#>

param (
    [string]$EmailFrom,
    [string]$EmailTo,
    [string]$Password,

    [string]$PhoneNumber,
    [string]$EmailServer,
    [string]$EmailAccount,
    [string]$AccessTypeString,
    [int]$CheckEveryMinutes = 30
)

enum EmailAccess
{
    Custom = 0
    Outlook = 1
    GMail = 2
}


#$EmailFrom = ""
#$EmailTo = ""
#$EmailServer = ""
#$phoneNumber = ""
#$EmailAccount = ""
$AccessType = [EmailAccess]::GMail
if ($AccessTypeString) {
    if ($AccessTypeString.ToLower() -eq "custom") {
        $AccessType = [EmailAccess]::GMail
    } elseif ($AccessTypeString.ToLower() -eq "outlook") {
        $AccessType = [EmailAccess]::GMail
    } else {
        $AccessType = [EmailAccess]::GMail
    }
}

# Check if the parameters are provided

# Display usage information if parameters are not provided
if (-not $EmailFrom -or -not $EmailTo -or (-not $EmailServer -and $AccessType -eq [EmailAccess]::Custom)) {
    Write-Host "Usage: ./MonitorMyIP.ps1 -EmailFrom <email address> -EmailTo <to address> [-EmailAccount <defaults to From Address>] [-Password <password>] [-PhoneNumber <Texting Number>] [-AccessType {Custom|Outlook|GMail}] [-CheckEveryMinutes <number>]"
    exit 1
}

if (-not $EmailAccount) {
    $EmailAccount = $EmailFrom
}

if ($PhoneNumber) {
    $smsAddress = "$PhoneNumber@mms.att.net"
}
else {
    $smsAddress = $null
}

if (-not $Password) {
    # Prompt the user for a password
    $SecurePassword = Read-Host -Prompt "Enter your password" -AsSecureString
}
else {
    $SecurePassword = (ConvertTo-SecureString $Password -AsPlainText -Force)
}

# Create an array to store multiple user credentials
$smptInformationsArray = @()

# Add user credentials to the array
$smptInformationsArray += @{
    Server = $EmailServer
}

$smptInformationsArray += @{
    Server = 'smtp.office365.com'
}

$smptInformationsArray += @{
    Server = 'smtp.gmail.com'
}

$previousIp = "Unknown"

function Send-Notification {
    param (
        [string]$currentIp,
        [string]$previousIp
    )

    $subject = "Public IP Address Change Detected"
    $body = "Your public IP address has changed to: $currentIp"
    if ($previousIp -ne 'Unknown') {
        $body = "$body from $previousIp."
    }

    $creds = New-Object System.Management.Automation.PSCredential($EmailAccount, $SecurePassword)

    $mailMessage = @{
        To       = $EmailTo
        From     = $EmailFrom
        Subject  = $subject
        Body     = $body
        SmtpServer = $smptInformationsArray[$AccessType].Server
        Port     = 587
        UseSsl   = $true
        Credential = $creds
    }

    try {
        # Send email
        Send-MailMessage @mailMessage
        Write-Host "Sent Email to [$EmailTo]: $subject"

        if ($smsAddress) {
            # Send SMS
            $mailMessage = @{
                To       = $smsAddress
                From     = $EmailFrom
                Subject  = $subject
       	        Body     = $body
                SmtpServer = $smptInformationsArray[$AccessType].Server
                Port     = 587
                UseSsl   = $true
                Credential = $creds
            }
            Send-MailMessage @mailMessage
            Write-Host "Sent Email to [$smsAddress]: $subject"
        }
    } catch {
        Write-Error "Send Mail Error: $_"
    }
}

# Function to send a text notification using Twilio
function Send-TextNotification {
    param (
        [string]$ToPhoneNumber,
        [string]$newIP,
        [string]$oldIP
    )
    if (-not $ToPhoneNumber) {
        return
    }

    $messageBody = "Your public IP address has changed from $oldIP to $newIP."


    $body = @{
      "phone"=$ToPhoneNumber
      "message"=$messageBody
      "key"="textbelt"
    }
    $submit = Invoke-WebRequest -Uri https://textbelt.com/text -Body $body -Method Post
}

function Format-SecondsAsTime {
    param (
        [int]$totalSeconds
    )
    
    $timeSpan = [System.TimeSpan]::FromSeconds($totalSeconds)
    $formattedTime = $timeSpan.ToString("hh\:mm\:ss")
    return $formattedTime
}

function ShowWaitStatus {

    param (
        [int]$seconds = 10,
        [string]$waitMessage
    )

    $startTime = Get-Date
    $endDate = $startTime.AddSeconds($seconds)
    while ((Get-Date) -lt $endDate) {
        # Calculate the time difference
        $timeDifference = $endDate - (Get-Date)

        $percentComplete = [math]::Round((($seconds - $timeDifference.TotalSeconds) / $seconds) * 100)
        $formattedTime = Format-SecondsAsTime -totalSeconds $timeDifference.TotalSeconds
        Write-Progress -Activity "Countdown Timer" -Status "$formattedTime $waitMessage" -PercentComplete $percentComplete
        Start-Sleep -Seconds 1
    }
}


while ($true) {
    try {
        $currentIp = (Invoke-WebRequest -Uri "http://ifconfig.me/ip").Content.Trim()
        if ($currentIp -ne $previousIp) {
            Write-Host "Public IP Address Changed from $previousIp to $currentIp."
            Send-Notification -currentIp $currentIp -previousIp $previousIp
            $previousIp = $currentIp
        }
    } catch {
        Write-Error "Failed to retrieve public IP address: $_"
    }

    ShowWaitStatus -seconds ($CheckEveryMinutes * 60) -waitMessage "until Next IP Address Check"
}
