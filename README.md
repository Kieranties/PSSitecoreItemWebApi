PSSitecoreItemWebApi
================

A PowerShell module to interact with the Sitecore Item Web API

Install
-------

To get up and running using the module run the following (in Powershell of course!)

    $response = Invoke-WebRequest "https://raw.github.com/Kieranties/PSSitecoreItemWebApi/master/PSSitecoreWebApi.ps1"
    $modPath = $env:PSModulePath.Split(";") | select -First 1

    $modFolder = New-Item (Join-Path $modPath "PSSitecoreWebApi") -ItemType directory -Force
    # Issues with Set-Content and BOM mean System.IO usage :-(
    [System.IO.File]::WriteAllLines((Join-Path $modFolder "PSSitecoreWebAPI.psm1"),$response.content)
 

Once installed run
    
    Import-Module PSSitecoreItemWebAPI # to make the module functions available
    Get-Help Invoke-SitecoreRequest # to find out what you can do
    
Usage
-----

Only some basic GET stuff has been tested so far, but `Invoke-SitecoreRequest` has been made flexible enough to handle other HTTP status codes and _all_ parameters that can be provided.
Have a play and see what you can do.

### Get an item by path
    Invoke-SitecoreRequest mydomain -path "/sitecore/content/home/myitem"

### Get an item by id
    Invoke-SitecoreRequest mydomain -item {C19E9164-FF99-4A05-B8C0-E9C931DA111F}
    
### Provide credentials
    Invoke-SitecoreRequest mydomain -username username -password password -item {C19E9164-FF99-4A05-B8C0-E9C931DA111F}
    
### Response model
The response is just the web response converted from JSON.  Some slight refactoring will be done to this in the future.

Links
-------
[@Kieranties]

[@Kieranties]: http://twitter.com/kieranties

