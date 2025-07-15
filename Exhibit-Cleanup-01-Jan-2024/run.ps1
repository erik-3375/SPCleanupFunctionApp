param($Timer)

Import-Module "$PSScriptRoot/../Shared/FolderCleanup.ps1"

# Define function-specific value
$tenantId = "7318a427-2f81-408f-8386-6569e958a870"
$clientId = "d01ba7da-01d7-4b6d-8bb4-fab5d10e0e24"
$clientSecret = $env:GraphClientSecret
$hostname = "planetdepos.sharepoint.com"
$sitePath = "sites/ExhibitSubmissionPortal"  # path AFTER the domain
$libraryName = "Exhibits"
$libraryPath = "2024/02 February"
$folderAgeThresholdDays = 60

# Call shared logic
. "$PSScriptRoot/../Shared/FolderCleanup.ps1" `
    -libraryPath $libraryPath `
    -sitePath $sitePath `
    -libraryName $libraryName `
    -folderAgeThresholdDays $folderAgeThresholdDays `
    -clientId $clientId `
    -tenantId $tenantId `
    -clientSecret $clientSecret