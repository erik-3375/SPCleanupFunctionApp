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

    # Get Graph token
    $body = @{
        client_id     = $clientId
        scope         = "https://graph.microsoft.com/.default"
        client_secret = $clientSecret
        grant_type    = "client_credentials"
    }

    $tokenResponse = Invoke-RestMethod -Method Post -Uri "https://login.microsoftonline.com/$tenantId/oauth2/v2.0/token" -Body $body
    $accessToken = $tokenResponse.access_token
    $headers = @{ Authorization = "Bearer $accessToken" }

    # Resolve Site & Drive
    $siteUrl = "https://graph.microsoft.com/v1.0/sites/${hostname}:/${sitePath}"
    $site = Invoke-RestMethod -Uri $siteUrl -Headers $headers
    $siteId = $site.id

    $drive = Invoke-RestMethod -Uri "https://graph.microsoft.com/v1.0/sites/$siteId/drives" -Headers $headers
    $driveId = ($drive.value | Where-Object { $_.name -eq $libraryName }).id

    # --------- Recursive Cleanup Function ---------
    function FolderCleanup {
        param (
            [string]$folderPath
        )

        $encodedPath = $folderPath -replace ' ', '%20'
        $folderUrl = "https://graph.microsoft.com/v1.0/sites/${siteId}/drives/${driveId}/root:/${encodedPath}:"

        try {
            $folder = Invoke-RestMethod -Uri $folderUrl -Headers $headers
        } catch {
            Write-Warning "❌ Failed to get folder '$folderPath': $($_.Exception.Message)"
            return $false
        }

        if (-not $folder.id) {
            Write-Warning "⚠️ Folder not found or inaccessible: $folderPath"
            return $false
        }

        $folderId = $folder.id

        try {
            $children = Invoke-RestMethod -Uri "$folderUrl/children" -Headers $headers
        } catch {
            Write-Warning "❌ Failed to get children for '$folderPath': $($_.Exception.Message)"
            return $false
        }

        $subfolders = $children.value | Where-Object { $_.folder }
        $files = $children.value | Where-Object { -not $_.folder }

        $allSubfoldersEmpty = $true
        foreach ($subfolder in $subfolders) {
            $subPath = "$folderPath/$($subfolder.name)"
            $result = FolderCleanup -folderPath $subPath
            if (-not $result) {
                $allSubfoldersEmpty = $false
            }
        }

        $isEmpty = ($files.Count -eq 0 -and $allSubfoldersEmpty)

        if ($isEmpty) {
            if ($folder.createdDateTime) {
                $created = [datetime]$folder.createdDateTime
                $age = (Get-Date) - $created

                if ($age.Days -ge $folderAgeThresholdDays) {
                    Write-Host "🗑 Deleting EMPTY folder: $folderPath (Age: $($age.Days) days)" -ForegroundColor Yellow
                    $deleteUrl = "https://graph.microsoft.com/v1.0/sites/$siteId/drives/$driveId/items/$folderId"
                    Invoke-RestMethod -Uri $deleteUrl -Method Delete -Headers $headers
                    return $true
                } else {
                    Write-Host "Skipping: $folderPath is empty but only $($age.Days) days old"
                    return $false
                }
            } else {
                Write-Host "Skipping: No createdDateTime for $folderPath"
                return $false
            }
        } else {
            Write-Host "Skipping: $folderPath contains files or non-empty folders"
            return $false
        }
    }

    # --------- Start Scanning Subfolders ---------
    $encodedPath = $libraryPath -replace ' ', '%20'
    $parentFolderUrl = "https://graph.microsoft.com/v1.0/sites/${siteId}/drives/${driveId}/root:/${encodedPath}:"

    try {
        $parent = Invoke-RestMethod -Uri "$parentFolderUrl/children" -Headers $headers
        $subfolders = $parent.value | Where-Object { $_.folder }
    } catch {
        Write-Warning "❌ Failed to list children of '$libraryPath': $($_.Exception.Message)"
        return
    }

    foreach ($subfolder in $subfolders) {
        $subPath = "$libraryPath/$($subfolder.name)"
        Write-Host "`n🔍 Scanning: $subPath"
        FolderCleanup -folderPath $subPath | Out-Null
    }
}
