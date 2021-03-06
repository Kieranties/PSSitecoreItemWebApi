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
    Validate the given value is a guid
#>
Function Test-Guid {
    param($value)
    
    # Error thrown if invalid
    try{
        [guid]::Parse($value)
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
    Test the given value is greater than or equal to zero
#>
Function Test-GreaterOrEqualToZero{
    param($value)

    if($value -lt 1){
        throw "Must be a value greater than or equal to 0"
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
    Formats an api response
#>
Function Format-ApiResponse{
    param(
        [Parameter(ValueFromPipeline=$true, Position=0, Mandatory=$true)]
        $data
    )

    $jsonObj = $data | ConvertFrom-Json

    # TODO: Tidy this up, what happens if more properties are added?
    $propertyMap = if($jsonObj.Error) { $jsonObj.Error} # Use the error properties as the base
        else{
            $result = $jsonObj.Result # Use the result properties as a base...

            # But on a DELETE the response object has a different structure....
            # Lets normalise it with the normal 200 response sent by other
            # operations
            if($result.ItemIds){ # Only sent by DELETE operations

                # Delete returns a Count proprty but this overrides the count function
                # of the number of entries in the hash which is confusing!
                $result | Add-Member NoteProperty -Name totalCount -Value $result.ItemIds.Count
                $result | Add-Member NoteProperty -Name resultCount -Value $result.ItemIds.Count               

                # Normal response object has result.items (hash) with ID properties
                # not result.itemids (array)
                $itemArr = @()
                $result.ItemIds | % { $itemArr += ( New-Object PSObject -Property @{ "ID" = $_ })}

                $result | Add-Member NoteProperty -Name items -Value $itemArr               

                # Remove the old key/values
                $result = $result | select * -ExcludeProperty count,itemIds
            }

            $result
        }
            
    # Add the status code to the return obj
    $propertyMap | Add-Member NoteProperty -Name StatusCode -Value $jsonObj.statusCode   

    $propertyMap
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
        [hashtable]$additional = @{}
    )

    $headers = @{}

    if($username){ $headers.Add("X-Scitemwebapi-Username", $username) }
    if($password){ $headers.Add("X-Scitemwebapi-Password", $password) }
    $additional.Keys | % { $headers.Add($_, $additional.$_) }
 
    $headers
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
        [hashtable]$queryParams,
        [string]$body,
        [string]$contentType = ''
    )

    $qs = Format-UrlEncoded $queryParams
    $qs = if($qs) { '?' + $qs}

    Write-Verbose "Request URL: $url"
    Write-Verbose "Request query string: $qs"
    Write-Verbose "Request headers:"
    $headers.Keys | % { Write-Verbose "$_ = $($headers.$_)" }

    $result = if($body){
                Invoke-WebRequest $url$qs -Method $method -Headers $headers `
                    -ContentType $contentType -Body $body
              } else {
                Invoke-WebRequest $url$qs -Method $method -Headers $headers `
                    -ContentType $contentType
              }
    $result | Format-ApiResponse
}

<# --------------------------------------------------------------- #>
<# Exported functions                                              #>
<# --------------------------------------------------------------- #>

<#
    .SYNOPSIS
    Executes a request using the Sitecore Item Web API

    .DESCRIPTION
    This is the "free form" way to interact with the Sitecore Item Web API. Using 
    this function will not perform validation on your parameters but will encode 
    query string parameters and attempt to format pararmeters for the url (e.g the
    scope array if provided will be sent as a pipe-delimited string).

    Use this function if you want maximum control or to send parameters that are
    not catered for by other functions.

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

    .PARAMETER ResponseFields
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

    .SYNOPSIS ContentType
    [Optional] The Content-Type header value for the request

    .SYNOPSIS
    [Optional] The raw body content to send in the request
#>
Function Invoke-SitecoreRequest{
    param(        
        [Parameter(Mandatory=$true, Position=0)]
        [string]$domain,
        [string]$username,        
        [string]$password,
        [string]$method = "get",                
        [string]$path,
        [string]$item,
        [int]$version,
        [string]$database,
        [string]$language,
        [string[]]$responseFields,
        [string]$payload,
        [string[]]$scope,
        [string]$query,
        [int]$page,
        [int]$pageSize,
        [hashtable]$addParams = @{},        
        [int]$apiVersion = 1,
        [bool]$fastQuery,
        [bool]$extractBlob,
        [bool]$ssl,
        [string]$contentType,
        [string]$body
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
    
    Invoke-RawRequest $url -method $method -headers $headers -queryParams $addParams `
        -body $body -contentType $contentType
}

<#
    .SYNOPSIS
    Creates a new item in Sitecore using the Sitecore Item Web API

    .DESCRIPTION
    Creates a new item in Sitecore using the given name and template.
    Location for the item will be resolved by Sitecore based on the given
    parameters.

    .PARAMETER Domain
    [Required] The domain of request to be made.  Can be provided with a protocol
    but is not required.

    .PARAMETER Username
    [Optional] The username to send in the request.  This will be sent in the
    "X-Scitemwebapi-Username" header. Required if "Password" is used.

    .PARAMETER Password
    [Optional] The password to send in the request.  This will be sent in the
    "X-Scitemwebapi-Password" header. Required if "Username" is used.

    .PARAMETER Template
    [Required] The path for the template based from the Template folder 
    e.g. Sample/Sample Item

    .PARAMETER Name
    [Required] The name of the item to be created

    .PARAMETER ItemFields
    [Optional] A hashtable of values to set on the new item once it is created.
    Key/value pairs can be provided as <fieldname>/value or <fieldId>/value.
    The given values will be encoded before being added to the body.

    .PARAMETER Path
    [Optional] The Sitecore item path to be used in the request.  Sent as part
    of the URL.
    
    .PARAMETER Database
    [Optional] The name of the database for the context of the items to be returned.
    Set as "sc_database" in the query string.
    
    .PARAMETER Item
    [Optional] The guid identifier for an item.  Can be wrapped in "{}" or not.
    Sent as "sc_itemid" in the query string.

    .PARAMETER Query
    [Optional] The Sitecore query to be executed.  May be prepended by "fast:" or use the 
    "FastQuery" parameter instead.  Will be URL encoded before sending.

    .PARAMETER Scope
    [Optional] String array to restrict the scope of items returned from the request.
    Can be one or more of the following values:
        s - Self
        p - Parent
        c - Children

    .PARAMETER ResponseFields
    [Optional] String array of fields to return for the given request.  Items may be
    field names or guid identifiers.

    .PARAMETER Payload
    Restrict or expand the fields returned from a request.  This parameter
    is ignored in requests that provide the "Fields" parameter. Can only be one of the
    following values:
        min - No fields are returned
        content - Only content fields are returned
        full - All the item fields, including content and standard fields are returned
    
    .PARAMETER ApiVersion
    [Optional]The integer version of the API to use.  Defaults to 1.

    .PARAMETER FastQuery
    [Optional]Set if using the "Query" parameter and Sitecore method should run as a fast
    query.

    .PARAMETER Ssl
    [Optional]Set to make requests over HTTPS.  Will override the protocol given in "Domain".
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
        [ValidateScript({ Test-GreaterThanZero $_ })]
        [int]$apiVersion = 1,
        [switch]$fastQuery,
        [switch]$ssl
    )

    $addParams = @{ 
        name = $name
        template = $template
    }

    $body = Format-UrlEncoded $itemFields

    Invoke-SitecoreRequest $domain -method "POST" -username $username -password $password `
        -path $path -database $database -item $item -query $query -scope $scope `
        -responseFields $responseFields -payload $payload -apiVersion $apiVersion `
        -fastQuery $fastQuery -ssl $ssl -addParams $addParams -body $body `
        -contentType "application/x-www-form-urlencoded"
}

<#
    .SYNOPSIS
    Updates an item in Sitecore using the Sitcore Item Web API

    .DESCRIPTION
    Updates the contextual items in Sitecore.  Fields will only be updated if 
    the item has the field to being with.

    .PARAMETER Domain
    [Required] The domain of request to be made.  Can be provided with a protocol
    but is not required.

    .PARAMETER Username
    [Optional] The username to send in the request.  This will be sent in the
    "X-Scitemwebapi-Username" header. Required if "Password" is used.

    .PARAMETER Password
    [Optional] The password to send in the request.  This will be sent in the
    "X-Scitemwebapi-Password" header. Required if "Username" is used.

    .PARAMETER ItemFields
    [Optional] A hashtable of values to set on the new item once it is created.
    Key/value pairs can be provided as <fieldname>/value or <fieldId>/value.
    The given values will be encoded before being added to the body.

    .PARAMETER Path
    [Optional] The Sitecore item path to be used in the request.  Sent as part
    of the URL.
    
    .PARAMETER Database
    [Optional] The name of the database for the context of the items to be returned.
    Set as "sc_database" in the query string.
    
    .PARAMETER Item
    [Optional] The guid identifier for an item.  Can be wrapped in "{}" or not.
    Sent as "sc_itemid" in the query string.

    .PARAMETER Language
    [Optional] The language context for the requested items(s).

    .PARAMETER Query
    [Optional] The Sitecore query to be executed.  May be prepended by "fast:" or use the 
    "FastQuery" parameter instead.  Will be URL encoded before sending.

    .PARAMETER Scope
    [Optional] String array to restrict the scope of items returned from the request.
    Can be one or more of the following values:
        s - Self
        p - Parent
        c - Children

    .PARAMETER ResponseFields
    [Optional] String array of fields to return for the given request.  Items may be
    field names or guid identifiers.

    .PARAMETER Payload
    Restrict or expand the fields returned from a request.  This parameter
    is ignored in requests that provide the "Fields" parameter. Can only be one of the
    following values:
        min - No fields are returned
        content - Only content fields are returned
        full - All the item fields, including content and standard fields are returned
    
    .PARAMETER ApiVersion
    [Optional]The integer version of the API to use.  Defaults to 1.

    .PARAMETER FastQuery
    [Optional]Set if using the "Query" parameter and Sitecore method should run as a fast
    query.

    .PARAMETER Ssl
    [Optional]Set to make requests over HTTPS.  Will override the protocol given in "Domain".
#>
Function Set-SitecoreItem{
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
        [hashtable]$itemFields = @{},
        [string]$path,
        [string]$database,
        [ValidateScript({ Test-Guid $_ })]
        [string]$item,
        [string]$language,
        [string]$query,
        [ValidateScript({ Test-Scope $_ })]
        [string[]]$scope,
        [string[]]$responseFields,
        [ValidateScript({ Test-Payload $_ })]
        [string]$payload,  
        [ValidateScript({ Test-GreaterThanZero $_ })]  
        [int]$apiVersion = 1,
        [switch]$fastQuery,
        [switch]$ssl
    )
    
    $body = Format-UrlEncoded $itemFields

    Invoke-SitecoreRequest $domain -method "PUT" -username $username -password $password `
        -path $path -database $database -item $item -query $query -scope $scope `
        -responseFields $responseFields -payload $payload -apiVersion $apiVersion `
        -fastQuery $fastQuery -ssl $ssl -body $body -language $language `
        -contentType "application/x-www-form-urlencoded"
}

<#
    .SYNOPSIS
    Requests items from Sitecore using the Sitecore Item Web API

    .DESCRIPTION
    Returns one or more items from the Sitecore Item Web API based on the context
    provided

    .PARAMETER Domain
    [Required] The domain of request to be made.  Can be provided with a protocol
    but is not required.

    .PARAMETER Username
    [Optional] The username to send in the request.  This will be sent in the
    "X-Scitemwebapi-Username" header. Required if "Password" is used.

    .PARAMETER Password
    [Optional] The password to send in the request.  This will be sent in the
    "X-Scitemwebapi-Password" header. Required if "Username" is used.

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

    .PARAMETER ResponseFields
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
Function Get-SitecoreItem{
    param(        
        [Parameter(Mandatory=$true, Position=0, ParameterSetName="default")]
        [Parameter(Mandatory=$true, Position=0, ParameterSetName="auth")]
        [string]$domain,
        [Parameter(Mandatory=$true,  Position=1, ParameterSetName="auth")]
        [string]$username,        
        [Parameter(Mandatory=$true,  Position=2, ParameterSetName="auth")]
        [string]$password,               
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
        [ValidateScript({ Test-GreaterOrEqualToZero $_ })]
        [int]$page,
        [ValidateScript({ Test-GreaterThanZero $_ })]
        [int]$pageSize,     
        [ValidateScript({ Test-GreaterThanZero $_ })] 
        [int]$apiVersion = 1,
        [bool]$fastQuery,
        [bool]$extractBlob,
        [bool]$ssl
    )

    Invoke-SitecoreRequest $domain -username $username -password $password `
        -path $path -item $item -version $version -database $database `
        -language $language -responseFields $responseFields -payload $payload `
        -scope $scope -query $query -page $page -pageSize $pageSize `
        -apiVersion $apiVersion -fastQuery $fastQuery -extractBlob $extractBlob `
        -ssl $ssl
}

<#
    .SYNOPSIS
    Deletes items from Sitecore using the Sitecore Item Web API

    .DESCRIPTION
    Deletes any item that matches the context provided

    .PARAMETER Domain
    [Required] The domain of request to be made.  Can be provided with a protocol
    but is not required.

    .PARAMETER Username
    [Optional] The username to send in the request.  This will be sent in the
    "X-Scitemwebapi-Username" header. Required if "Password" is used.

    .PARAMETER Password
    [Optional] The password to send in the request.  This will be sent in the
    "X-Scitemwebapi-Password" header. Required if "Username" is used.

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

    .PARAMETER ApiVersion
    [Optional] The integer version of the API to use.  Defaults to 1.

    .PARAMETER FastQuery
    [Optional] Set if using the "Query" parameter and Sitecore method should run as a fast
    query.

    .PARAMETER Ssl
    [Optional] Set to make requests over HTTPS.  Will override the protocol given in "Domain".
#>
Function Remove-SitecoreItem{
    param(        
        [Parameter(Mandatory=$true, Position=0, ParameterSetName="default")]
        [Parameter(Mandatory=$true, Position=0, ParameterSetName="auth")]
        [string]$domain,
        [Parameter(Mandatory=$true,  Position=1, ParameterSetName="auth")]
        [string]$username,        
        [Parameter(Mandatory=$true,  Position=2, ParameterSetName="auth")]
        [string]$password,               
        [string]$path,
        [ValidateScript({ Test-Guid $_ })]
        [string]$item,
        [ValidateScript({ Test-GreaterThanZero $_ })]
        [int]$version,        
        [string]$database,
        [string]$language,
        [ValidateScript({ Test-Scope $_ })]
        [string[]]$scope,
        [string]$query,
        [ValidateScript({ Test-GreaterOrEqualToZero $_ })]
        [int]$page,
        [ValidateScript({ Test-GreaterThanZero $_ })]
        [int]$pageSize,     
        [ValidateScript({ Test-GreaterThanZero $_ })]     
        [int]$apiVersion = 1,
        [bool]$fastQuery,
        [bool]$ssl
    )

    Invoke-SitecoreRequest $domain -method "DELETE" -username $username -password $password `
        -path $path -item $item -version $version -database $database -language $language `
        -scope $scope -query $query -apiVersion $apiVersion -fastQuery $fastQuery -ssl $ssl
}

# Only export the relevant functions
Export-ModuleMember -Function *sitecore*