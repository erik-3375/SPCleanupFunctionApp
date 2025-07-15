function Invoke-FolderCleanup {
    param (
        [string]$tenantId,
        [string]$clientId,
        [string]$clientSecret,
        [string]$hostname,
        [string]$sitePath,
        [string]$libraryName,
        [string]$libraryPath,
        [int]$folderAgeThresholdDays
    )

# Place your complete cleanup logic here, like you've already built.

# -------------------------------
# Get Microsoft Graph token
# -------------------------------
$body = @{
    client_id     = $clientId
    scope         = "https://graph.microsoft.com/.default"
    client_secret = $clientSecret
    grant_type    = "client_credentials"
}

$tokenResponse = Invoke-RestMethod -Method Post -Uri "https://login.microsoftonline.com/$tenantId/oauth2/v2.0/token" -Body $body
$accessToken = $tokenResponse.access_token
$headers = @{ Authorization = "Bearer $accessToken" }

# -------------------------------
# Resolve Site ID and Drive ID
# -------------------------------
$siteUrl = "https://graph.microsoft.com/v1.0/sites/${hostname}:/${sitePath}"
$site = Invoke-RestMethod -Uri $siteUrl -Headers $headers
$siteId = $site.id

$drive = Invoke-RestMethod -Uri "https://graph.microsoft.com/v1.0/sites/$siteId/drives" -Headers $headers
$driveId = ($drive.value | Where-Object { $_.name -eq $libraryName }).id

# -------------------------------
# Recursive Folder Scanner
# -------------------------------
function FolderCleanup {
    param (
        [string]$folderPath
    )

    $encodedPath = $folderPath -replace ' ', '%20'
    $folderUrl = "https://graph.microsoft.com/v1.0/sites/${siteId}/drives/${driveId}/root:/${encodedPath}`:"
    
    try {
        $folder = Invoke-RestMethod -Uri $folderUrl -Headers $headers
    } catch {
        Write-Warning "Failed to get folder '$folderPath': $($_.Exception.Message)"
        return
    }

    if (-not $folder.id) {
        Write-Warning "Folder not found or inaccessible: $folderPath"
        return
    }

    $folderId = $folder.id

    # Get folder contents
    try {
        $children = Invoke-RestMethod -Uri "$folderUrl/children" -Headers $headers
    } catch {
        Write-Warning "Failed to get children for '$folderPath': $($_.Exception.Message)"
        return
    }

    $subfolders = $children.value | Where-Object { $_.folder }
    $files = $children.value | Where-Object { -not $_.folder }

    # Recurse into subfolders first
    foreach ($subfolder in $subfolders) {
        $subPath = "$folderPath/$($subfolder.name)"
        FolderCleanup -folderPath $subPath
    }

    # Check if folder is empty
    if ($subfolders.Count -eq 0 -and $files.Count -eq 0) {
        if ($folder.createdDateTime) {
            $created = [datetime]$folder.createdDateTime
            $age = (Get-Date) - $created

            if ($age.Days -ge $folderAgeThresholdDays) {
                Write-Host "Deleting EMPTY folder: $folderPath (Age: $($age.Days) days)" -ForegroundColor Yellow
                $deleteUrl = "https://graph.microsoft.com/v1.0/sites/$siteId/drives/$driveId/items/$folderId"
                Invoke-RestMethod -Uri $deleteUrl -Method Delete -Headers $headers
            } else {
                Write-Host "Skipping: $folderPath is empty but only $($age.Days) days old"
            }
        } else {
            Write-Host "Skipping: No createdDateTime found for $folderPath"
        }
    } else {
        Write-Host "Skipping: $folderPath is not empty"
    }
}

# -------------------------------
# Resolve subfolders of target folder (don't delete the target itself)
# -------------------------------
$encodedPath = $libraryPath -replace ' ', '%20'
$parentFolderUrl = "https://graph.microsoft.com/v1.0/sites/${siteId}/drives/${driveId}/root:/${encodedPath}:"

try {
    $parent = Invoke-RestMethod -Uri "$parentFolderUrl/children" -Headers $headers
    $subfolders = $parent.value | Where-Object { $_.folder }
} catch {
    Write-Warning "Failed to list children of '$libraryPath': $($_.Exception.Message)"
    return
}

foreach ($subfolder in $subfolders) {
    $subPath = "$libraryPath/$($subfolder.name)"
    Write-Host "`n🔍 Scanning subfolder: $subPath"
    FolderCleanup -folderPath $subPath
}
}