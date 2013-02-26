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
        [ValidateSet("get","post","put","delete")]
        [string]$method = "get",                
        [string]$path,
        [ValidateScript({try { [guid]::Parse($_) -ne $null } catch [exception] { $false }})]
        [string]$item,
        [ValidateScript({ $_ -gt 0 })]
        [int]$version,
        [string]$database,
        [string]$language,
        [string[]]$fields,
        [ValidateSet("min","content","full")]
        [string]$payload,
        [ValidateSet("s","p","c")]
        [string[]]$scope,
        [string]$query,
        [ValidateScript({$_ -ge 0 })]
        [int]$page,
        [ValidateScript({$_ -ge 0 })]
        [int]$pageSize,
        [hashtable]$addParams = @{},        
        [string]$apiVersion = "1",
        [switch]$fastQuery,
        [switch]$extractBlob,
        [switch]$ssl
    )

    # Parse protocol and domain
    if($domain -match "(?<protocol>https?://)?(?<domain>[^/]*)(.*)"){
        $protocol = $Matches.protocol
        if(-not($Matches.protocol)){
            $protocol = if($ssl) { "https://" } else { "http://" }
        }
        $domain = $Matches.domain
    }    

    # Construct URL
    $url = "$protocol$domain/-/item/v$apiVersion/$path"  
    
    # Construct query string parameters
    # There has to be a better way to do this!

    # Use the given $addParams as the base
    # is initilised to empty hashtable to in declaration
    if($item){ $addParams.sc_itemid = $item }
    if($version){ $addParams.sc_itemversion = $version }
    if($database){ $addParams.sc_database = $database }
    if($language){ $addParams.language = $language }
    if($fields){ $addParams.fields = $fields }
    if($payload){ $addParams.payload = $payload }
    if($scope) { $addParams.scope = $scope }
    if($query){
        if(($query -notlike "fast:/*") -and $fastQuery){
            $query = "fast:/$query"
        }
        $addParams.query = $query
    }
    if($page){ $addParams.page = $page }
    if($pageSize){ $addParams.pagesize = $pageSize }
    if($extractBlob){ $addParams.extractblob = 1 }
    
    # Parse the query string parameters
    $addParams.Keys | % {
        Write-Verbose "Query param: $_ = $($addParams[$_])"
        $encodedVal = [Web.HttpUtility]::UrlEncode($addParams[$_])
        $qs += "$_=$encodedVal&" 
    }
    if($qs){ $qs = $qs -replace "(.*)&$",'?$1' }

    $headers = @{}
    if($PSCmdlet.ParameterSetName.Equals("auth")){
         $headers = @{
            "X-Scitemwebapi-Username" = $username
            "X-Scitemwebapi-Password" = $password
        }
    }

    
    Write-Verbose "Request URL: $url"
    Write-Verbose "Request headers:"
    $headers.Keys | % { Write-Verbose "$_ = $($headers[$_])" }

    Invoke-WebRequest $url$qs -Headers $headers | ConvertFrom-Json
}