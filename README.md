PSSitecoreItemWebApi
====================

A PowerShell module to interact with the Sitecore Item Web API

**Requires**: PowerShell 3.0

Install
-------

To get up and running using the module run the following (in PowerShell of course!)


    <#
        .SYNOPSIS
        Simple install script for PSSitecoreItemWebAPI
    #>

    $moduleName = "PSSitecoreItemWebApi"
    $branch = "master"
    $urlStub = "https://raw.github.com/Kieranties/$moduleName/$branch/"
    $psd = "$urlStub$moduleName.psd1"
    $psm = "$urlStub$moduleName.psm1"

    $client = New-Object System.Net.WebClient
    $modPath = $env:PSModulePath.Split(";") | ? { $_ } | select -First 1 # or wherever you put your modules
    $modFolder = New-Item (Join-Path $modPath $moduleName) -ItemType directory -Force # force used so you can use same script to update

    $psd,$psm | % {
        $fileName = Split-Path $_ -leaf
        $client.DownloadFile($_, (Join-Path $modFolder $filename))
    }

    "$moduleName install complete"
    
Usage
-----

To start using the module:

    Import-Module PSSSitecoreItemWebApi

To find out what functions are available:

    Get-Command -Module PSSitecoreItemWebApi

Don't forget, each function has help associated with it ( -examples not yet complete):

    Get-Help Get-SitecoreItem

Assuming you've got the API enabled and running on a site you can start interacting
with Sitecore straight away.  [Check out the gist examples] for further information.

Links
-------
+ [@Kieranties]
+ [License] - MIT, go crazy.

[@Kieranties]: http://twitter.com/kieranties
[License]: http://kieranties.mit-license.org/
[Check out the gist examples]: https://gist.github.com/Kieranties/5059684
