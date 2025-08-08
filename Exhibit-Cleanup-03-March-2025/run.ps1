param($Timer)

# Define function-specific value
Import-Module FolderCleanup

$tenantId = "7318a427-2f81-408f-8386-6569e958a870"
$clientId = "d01ba7da-01d7-4b6d-8bb4-fab5d10e0e24"
$clientSecret = $env:GraphClientSecret

$hostname = "planetdepos.sharepoint.com"
$sitePath = "sites/ExhibitSubmissionPortal"
$libraryName = "Exhibits"
$libraryPath = "2025/03 March"
$folderAgeThresholdDays = 60

# Call shared logic
Invoke-FolderCleanup `
    -tenantId $tenantId `
    -clientId $clientId `
    -clientSecret $clientSecret `
    -hostname $hostname `
    -sitePath $sitePath `
    -libraryName $libraryName `
    -libraryPath $libraryPath