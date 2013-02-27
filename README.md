PSSitecoreItemWebApi
================

A PowerShell module to interact with the Sitecore Item Web API


Install (as a script)
---------------------

Just copy PSSitecoreWebAPI.ps1 to your local machine and do what you will.

Install (as a module)
---------------------

To get up and running using the module run the following (in Powershell of course!)

    $url = "https://raw.github.com/Kieranties/PSSitecoreItemWebApi/master/PSSitecoreWebApi.ps1"
    $client = New-Object System.Net.WebClient
    $modPath = $env:PSModulePath.Split(";") | ? { $_ } | select -First 1 # or wherever you put your modules
    $modFolder = New-Item (Join-Path $modPath "PSSitecoreWebApi") -ItemType directory -Force # force used so you can use same script to update
    $client.DownloadFile($url, (Join-Path $modFolder "PSSitecoreWebAPI.psm1"))
 

Once installed run
    
    Import-Module PSSitecoreItemWebAPI # to make the module functions available
    Get-Help Invoke-SitecoreRequest # to find out what you can do
    
Usage
-----

Only some basic GET stuff has been tested so far, but `Invoke-SitecoreRequest` is being made flexible enough to handle other HTTP status codes and _all_ parameters that can be provided.
Have a play and see what you can do.

The expectation is that `Invoke-SitecoreRequest` can be used for all manner of requests but the module may include wrapper functions in the future should they be useful.

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
+ [@Kieranties]
+ [License] - MIT, go crazy.

[@Kieranties]: http://twitter.com/kieranties
[License]: http://kieranties.mit-license.org/

