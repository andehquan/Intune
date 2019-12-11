$clientId = "a8967f1a-c363-4f8d-a727-7971accf48a1" #This is the Client ID for your Application Registration in Azure AD
$tenantId = "c5426d86-64d4-4469-8d6f-9330c8030c6e" # This is the Tenant ID of your Azure AD Directory
$redirectUri = "https://login.microsoftonline.com/common/oauth2/nativeclient" # This is the Return URL for your Application Registration in Azure AD
$dnsDomainName = "austin.local" #This is the internal name of your AD Forest/

$Drivemappings = @( #Create a line below for each drive mapping that needs to be created.
    @{"includeSecurityGroup" = "AUSTIN\SG-Data-Users" ; "excludeSecurityGroup" = "" ; "driveLetter" = "S" ; "UNCPath" = "\\aeapp01\Data"}
)

# Add required assemblies
Add-Type -AssemblyName System.Web, PresentationFramework, PresentationCore
 
# Scope - Needs to include all permisions required separated with a space
$scope = "User.Read.All Group.Read.All" # This is just an example set of permissions
 
# Random State - state is included in response, if you want to verify response is valid
$state = Get-Random
 
# Encode scope to fit inside query string 
$scopeEncoded = [System.Web.HttpUtility]::UrlEncode($scope)
 
# Redirect URI (encode it to fit inside query string)
$redirectUriEncoded = [System.Web.HttpUtility]::UrlEncode($redirectUri)
 
# Construct URI
$uri = "https://login.microsoftonline.com/$tenantId/oauth2/v2.0/authorize?client_id=$clientId&response_type=code&redirect_uri=$redirectUriEncoded&response_mode=query&scope=$scopeEncoded&state=$state"
 
# Create Window for User Sign-In
$windowProperty = @{
    Width  = 500
    Height = 700
}
 
$signInWindow = New-Object System.Windows.Window -Property $windowProperty
    
# Create WebBrowser for Window
$browserProperty = @{
    Width  = 480
    Height = 680
}
 
$signInBrowser = New-Object System.Windows.Controls.WebBrowser -Property $browserProperty
 
# Navigate Browser to sign-in page
$signInBrowser.navigate($uri)
    
# Create a condition to check after each page load
$pageLoaded = {
 
    # Once a URL contains "code=*", close the Window
    if ($signInBrowser.Source -match "code=[^&]*") {
 
        # With the form closed and complete with the code, parse the query string
 
        $urlQueryString = [System.Uri]($signInBrowser.Source).Query
        $script:urlQueryValues = [System.Web.HttpUtility]::ParseQueryString($urlQueryString)
 
        $signInWindow.Close()
 
    }
}
 
# Add condition to document completed
$signInBrowser.Add_LoadCompleted($pageLoaded)
 
# Show Window
$signInWindow.AddChild($signInBrowser)
$signInWindow.ShowDialog()
 
# Extract code from query string
$authCode = $script:urlQueryValues.GetValues(($script:urlQueryValues.keys | Where-Object { $_ -eq "code" }))
 
if ($authCode) {
 
    # With Auth Code, start getting token
 
    # Construct URI
    $uri = "https://login.microsoftonline.com/$tenantId/oauth2/v2.0/token"
 
    # Construct Body
    $body = @{
        client_id    = $clientId
        scope        = $scope
        code         = $authCode[0]
        redirect_uri = $redirectUri
        grant_type   = "authorization_code"
    }
 
    # Get OAuth 2.0 Token
    $tokenRequest = Invoke-WebRequest -Method Post -Uri $uri -ContentType "application/x-www-form-urlencoded" -Body $body
 
    # Access Token
    $token = ($tokenRequest.Content | ConvertFrom-Json).access_token
 
}
else {
 
    Write-Error "Unable to obtain Auth Code!"
 
}

$uri = "https://graph.microsoft.com/v1.0/me/memberOf"
$method = "GET"
 
# Run Graph API query 
$query = Invoke-WebRequest -Method $method -Uri $uri -ContentType "application/json" -Headers @{Authorization = "Bearer $token"} -ErrorAction Stop
$output = ConvertFrom-Json $query.Content
$usergroups = @()
foreach ($group in $output.value) {
    $usergroups += $group.displayName
}

$connected=$false
$retries=0
$maxRetries=3

Write-Output "Starting script..."
do {
    if (Resolve-DnsName $dnsDomainName -ErrorAction SilentlyContinue) {
        $connected=$true
    }
    else {
        $retries++
        Write-Warning "Cannot resolve: $dnsDomainName, assuming no connection to fileserver"
        Start-Sleep -Seconds 3
        if ($retries -eq $maxRetries){
            Throw "Exceeded maximum numbers of retries ($maxRetries) to resolve dns name ($dnsDomainName)"
        }
    }
} 
while( -not ($Connected))

Write-Output $usergroups

$drivemappings.GetEnumerator()| ForEach-Object {
    Write-Output $PSItem.UNCPath
    if(($usergroups.contains($PSItem.includeSecurityGroup)) -and ($usergroups.contains($PSItem.excludeSecurityGroup) -eq $false)) {
        Write-Output "Attempting to map $($Psitem.DriveLetter) to $($PSItem.UNCPath)"
        New-PSDrive -PSProvider FileSystem -Name $PSItem.DriveLetter -Root $PSItem.UNCPath -Persist -Scope global
    }
}