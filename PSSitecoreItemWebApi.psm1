# Get the location of the invocation context
$root = Split-Path $MyInvocation.MyCommand.Path -Parent

# Load the scripts
Get-ChildItem (Join-Path $root "Scripts") | % { Import-Module $_.FullName }