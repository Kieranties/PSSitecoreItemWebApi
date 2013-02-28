<# --------------------------------------------------------------- #>
<# Private constants                                               #>
<# --------------------------------------------------------------- #>

New-Variable validHttpMethods -value "put", "get", "post", "delete" `
    -Option Constant -Visibility Private

New-Variable validPayloads -value "min", "content", "full" `
    -Option Constant -Visibility Private

New-Variable validScopes -value  "s", "p", "c" `
    -Option Constant -Visibility Private

<# --------------------------------------------------------------- #>
<# Private Test functions                                          #>
<# --------------------------------------------------------------- #>
           
<#
    .SYNOPSIS
    Test the given value is a guid
#>
Function Test-Guid {
    param($value)
    
    # Error thrown if invalid
    try{
        [guid]::Parse($_)
    } catch [exception] {
        throw
    }
}

<#
    .SYNOPSIS
    Test the given value is greater than zero
#>
Function Test-GreaterThanZero{
    param($value)

    if($value -lt 1){
        throw "Must be a value greater than 0"
    }

    $true
}

<#
    .SYNOPSIS
    Test the given value is a valid http method
#>
Function Test-HttpMethod{
    param($value)
    
    if($validHttpMethods -notcontains $value){
        throw "Valid methods are: $validHttpMethods"
    }

    $true
}

<#
    .SYNOPSIS
    Test the given value is a valid payload
#>
Function Test-Payload{
    param($value)
    
    if($validPayloads -notcontains $value){
        throw "Valid payloads are: $validPayloads"
    }

    $true
}

<#
    .SYNOPSIS
    Test the given value(s) are valid scopes
#>
Function Test-Scope{
    param($value)

    $value | % { 
        if($validScopes -notcontains $_){
            throw "Valid scopes are one or more of: $validScopes"
        }
    }

    $true
}

<# --------------------------------------------------------------- #>
<# Private Helper functions                                        #>
<# --------------------------------------------------------------- #>

<#
    .SYNOPSIS
    Returns a Url encoded query string
#>
Function Format-UrlEncoded{
    param(
        [Parameter(ValueFromPipeline=$true, Position=0, Mandatory=$true)]
        [hashtable]$hash = @{}
    )
    begin {
        $outputValue = ''
    }
    
    process{
        $hash.Keys | % { 
            $outputValue += ($_, [Web.HttpUtility]::UrlEncode($hash.$_) -join '=') + '&'
        }
    }

    end{        
        if($outputValue){
            $outputValue -replace "(.*)&$",'$1'
        }
    }

}

<#
    .SYNOPSIS
    Invokes a web request with raw parameters
#>
Function Invoke-RawRequest{
    param(
        [Parameter(Mandatory=$true, Position=0)]
        [string]$url,
        [ValidateScript({ Test-HttpMethod $_})]
        [string]$method = "get", 
        [hashtable]$headers,
        [hashtable]$queryParams
    )

    $qs = Format-UrlEncoded $queryParams
    $qs = if($qs) { '?' + $qs}

    Write-Verbose "Request URL: $url"
    Write-Verbose "Request query string: $qs"
    Write-Verbose "Request headers:"
    $headers.Keys | % { Write-Verbose "$_ = $($headers.$_)" }

    Invoke-WebRequest $url$qs -Method $method -Headers $headers | Format-ApiResponse
}

<#
    .SYNOPSIS
    Formats an api response
#>
Function Format-ApiResponse{
    param(
        [Parameter(ValueFromPipeline=$true, Position=0, Mandatory=$true)]
        $data
    )

    $jsonObj = $data | ConvertFrom-Json

    # TODO: Tidy this up, what happens if more properties are added?
    $propertyMap = @{"StatusCode" = $jsonObj.StatusCode}
    if($jsonObj.statusCode -eq 200){
        $propertyMap.Add("ResultCount", $jsonObj.Result.ResultCount)
        $propertyMap.Add("TotalCount", $jsonObj.Result.TotalCount)
        $propertyMap.Add("Items", $jsonObj.Result.Items)     
    } else {
        $propertyMap.Add("ErrorMessage", $jsonObj.Error.Message)
    }
        
    # Return the new object
    New-Object -TypeName PSObject -Property $propertyMap    
}

<#
    .SYNOPSIS
    Formats the given parameters into an api url
#>
Function Format-RequestUrl{
    param(
        [Parameter(Mandatory=$true, Position=0, ParameterSetName="default")]
        [string]$domain,
        [string]$path,
        [ValidateScript({ Test-GreaterThanZero $_ })]
        [int]$apiVersion = 1,
        [bool]$ssl
    )
    
    # Parse protocol and domain
    if($domain -match "(?<protocol>https?://)?(?<domain>[^/]*)(.*)"){
        
        $protocol = $Matches.protocol

        # If protocol provided in $domain than igonore $ssl
        if(-not($Matches.protocol)){
            $protocol = if($ssl) { "https://" } else { "http://" }
        }

        $domain = $Matches.domain
    }    

    # Construct URL
    "$protocol$domain/-/item/v$apiVersion/$path"  
}

<#
    .SYNOPSIS
    Returns a header collection for requests
#>
Function Get-RequestHeaders{
    param(
        [Parameter(Position=0)]
        [string]$username,        
        [Parameter(Position=1)]
        [string]$password,
        [Parameter(Position=2)]
        [string]$contentType
    )

    $headers = @{}
    if($username){ $headers.Add("X-Scitemwebapi-Username", $username) }
    if($password){ $headers.Add("X-Scitemwebapi-Password", $password) }
    if($contentType){ $headers.Add("Content-Type", $username) }
    $headers
}
<# --------------------------------------------------------------- #>
<# Exported functions                                              #>
<# --------------------------------------------------------------- #>

<#
    .SYNOPSIS
    Executes a web API request against a Sitecore site

    .DESCRIPTION
    Forms a valid URL based on the given parameters to execute against the given
    domain and web API version.

    .PARAMETER Domain
    [Required] The domain of request to be made.  Can be provided with a protocol
    but is not required.

    .PARAMETER Username
    [Optional] The username to send in the request.  This will be sent in the
    "X-Scitemwebapi-Username" header. Required if "Password" is used.

    .PARAMETER Password
    [Optional] The password to send in the request.  This will be sent in the
    "X-Scitemwebapi-Password" header. Required if "Username" is used.

    .PARAMETER Method
    [Optional] The HTTP method used when executing the request.  Defaults to GET.

    .PARAMETER Path
    [Optional] The Sitecore item path to be used in the request.  Sent as part
    of the URL.

    .PARAMETER Item
    [Optional] The guid identifier for an item.  Can be wrapped in "{}" or not.
    Sent as "sc_itemid" in the query string.

    .PARAMETER Version
    [Optional] Integer value for the version of the item to be returned.  Must be
    greater than zero.  Sent as "sc_itemversion" in the query string.

    .PARAMETER Database
    [Optional] The name of the database for the context of the items to be returned.
    Set as "sc_database" in the query string.

    .PARAMETER Language
    [Optional] The language context for the requested items(s).

    .PARAMETER Fields
    [Optional] String array of fields to return for the given request.  Items may be
    field names or guid identifiers.

    .PARAMETER Payload
    [Optional] Restrict or expand the fields returned from a request.  This parameter
    is ignored in requests that provide the "Fields" parameter. Can only be one of the
    following values:
        min - No fields are returned
        content - Only content fields are returned
        full - All the item fields, including content and standard fields are returned

    .PARAMETER Scope
    [Optional] String array to restrict the scope of items returned from the request.
    Can be one or more of the following values:
        s - Self
        p - Parent
        c - Children

    .PARAMETER Query
    [Optional] The Sitecore query to be executed.  May be prepended by "fast:" or use the 
    "FastQuery" parameter instead.  Will be URL encoded before sending.

    .PARAMETER Page
    [Optional] Integer value for the page of results to return. Must be greater than zero.

    .PARAMETER PageSize
    [Optional] Integer value for the number of results per page.  Must be greater than zero.

    .PARAMETER AddParams
    [Optional] A collection of key/value pairs which will be encoded and added to the query
    string.

    .PARAMETER ApiVersion
    [Optional] The integer version of the API to use.  Defaults to 1.

    .PARAMETER FastQuery
    [Optional] Set if using the "Query" parameter and Sitecore method should run as a fast
    query.

    .PARAMETER ExtractBlob
    [Optional] Set to retrieve BLOB field values

    .PARAMETER Ssl
    [Optional] Set to make requests over HTTPS.  Will override the protocol given in "Domain".


#>
function Invoke-SitecoreRequest{
    param(        
        [Parameter(Mandatory=$true, Position=0, ParameterSetName="default")]
        [Parameter(Mandatory=$true, Position=0, ParameterSetName="auth")]
        [string]$domain,
        [Parameter(Mandatory=$true,  Position=1, ParameterSetName="auth")]
        [string]$username,        
        [Parameter(Mandatory=$true,  Position=2, ParameterSetName="auth")]
        [string]$password,
        [ValidateScript({ Test-HttpMethod $_})]
        [string]$method = "get",                
        [string]$path,
        [ValidateScript({ Test-Guid $_ })]
        [string]$item,
        [ValidateScript({ Test-GreaterThanZero $_ })]
        [int]$version,
        [string]$database,
        [string]$language,
        [string[]]$responseFields,
        [ValidateScript({ Test-Payload $_ })]
        [string]$payload,
        [ValidateScript({ Test-Scope $_ })]
        [string[]]$scope,
        [string]$query,
        [ValidateScript({ Test-GreaterThanZero $_ })]
        [int]$page,
        [ValidateScript({ Test-GreaterThanZero $_ })]
        [int]$pageSize,
        [hashtable]$addParams = @{},        
        [string]$apiVersion = "1",
        [switch]$fastQuery,
        [switch]$extractBlob,
        [switch]$ssl
    )

    # Construct URL
    $url = Format-RequestUrl $domain -path $path -apiVersion $apiVersion -ssl $ssl  
    
    # Get headers
    $headers = Get-RequestHeaders $username $password

    # Construct query string parameters
    # There has to be a better way to do this!

    # Use the given $addParams as the base
    # is initialised to empty hashtable in declaration
    if($item){ $addParams.sc_itemid = $item }
    if($version){ $addParams.sc_itemversion = $version }
    if($database){ $addParams.sc_database = $database }
    if($language){ $addParams.language = $language }
    if($responseFields){ $addParams.fields = $responseFields -join '|' }
    if($payload){ $addParams.payload = $payload }
    if($scope) { $addParams.scope = $scope -join '|' }
    if($query){
        if(($query -notlike "fast:/*") -and $fastQuery){
            $query = "fast:/$query"
        }
        $addParams.query = $query
    }
    if($page){ $addParams.page = $page }
    if($pageSize){ $addParams.pagesize = $pageSize }
    if($extractBlob){ $addParams.extractblob = 1 }
    
    Invoke-RawRequest $url -method $method -headers $headers -queryParams $addParams
}

<#
    .SYNOPSIS
    Creates a new item in Sitecore
#>
Function Add-SitecoreItem{
    param(        
        [Parameter(Mandatory=$true, Position=0, ParameterSetName="default")]
        [Parameter(Mandatory=$true, Position=0, ParameterSetName="auth")]
        [string]$domain,
        [Parameter(Mandatory=$true,  Position=1, ParameterSetName="auth")]
        [string]$username,        
        [Parameter(Mandatory=$true,  Position=2, ParameterSetName="auth")]
        [string]$password,
        [Parameter(Mandatory=$true, ParameterSetName="default")]    
        [Parameter(Mandatory=$true, ParameterSetName="auth")]          
        [string]$template,
        [Parameter(Mandatory=$true, ParameterSetName="default")]
        [Parameter(Mandatory=$true, ParameterSetName="auth")]
        [string]$name,
        [hashtable]$itemFields = @{},
        [string]$path,
        [string]$database,
        [ValidateScript({ Test-Guid $_ })]
        [string]$item,
        [string]$query,
        [ValidateScript({ Test-Scope $_ })]
        [string[]]$scope,
        [string[]]$responseFields,
        [ValidateScript({ Test-Payload $_ })]
        [string]$payload,    
        [string]$apiVersion = "1",
        [switch]$fastQuery,
        [switch]$ssl
    )
}

# Only export the relevant functions
Export-ModuleMember -Function *sitecore*