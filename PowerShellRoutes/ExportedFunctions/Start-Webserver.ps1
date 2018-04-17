<#
.SYNOPSIS
    Start a web server that will route requests to a series of script blocks as defined by the -Routes parameter.

.DESCRIPTION
    Starts a single-threaded web server and responds to requests by executing the script blocks that are
    defined as routes on the command line.

.NOTES
    Copyright 2013 Chris Duck

    The idea for this script came from Parul Jain's work at http://poshcode.org/4073

.PARAMETER Routes
    A hashtable that maps a URL fragment to a script block to be executed for matching requests. The URL will be
    matched as a regex to the LocalPath portion of the requested URL.  Use the LocalPath property from 
    [Uri]"http://test/path?qs=test" to identify what part of your URL will be included in LocalPath.

    The script block has 2 automatic variables available to it:

    $Request - The [System.Net.HttpListenerRequest] object representing the incoming request.
    $Response - The [System.Net.HttpListenerResponse] object representing the outgoing response.

    There is also a helper function available in the script block:

    Send-Response -Body <String> [-ContentType <String>]

    Send-Response -Path <String> [-ContentType <String>]

    The default content type is "text/plain".  The Send-Response function will close the response
    output stream, so the entire response must be passed as the value for the Body parameter.  The
    Path parameter reads in the contents of the supplied file (as a single string) and sends it as
    the response.

    To stop the web server, set $Running = $False in any of your script blocks. If the routes table
    does not include a route with the key "Exit", a default exit route will be added.

    If you would like to send a redirect, use:
    
    $Response.Redirect("http://newurl")
    $Response.Close()

.PARAMETER IPAddress
    The IPAddress or host name to listen on.  By default it will listen on all local addresses.

.PARAMETER Port
    The port to listen on.  By default it will listen on port 80.

.EXAMPLE
    $Routes = @{
        "process" = {
            Send-Response -Body (Get-Process | ConvertTo-Html) -ContentType "text/html"
        }
        ".*" = {
            Send-Response -Body "Unknown address, try /Process or /Exit"
        }
    }
    Start-Webserver -Routes $Routes

    This will start a server that responds to requests for /Process by listing out all the running processes in an HTML form.
    Any other request will generate a plain text page suggesting the user try /Process or the default implementation of /Exit

    See Get-Help Start-Webserver -Parameter Routes for more information on building routes.

.EXAMPLE
    $Routes = @{
        "process" = {
            if($Request.QueryString["format"] -eq "json") {
                Send-Response -Body (Get-Process | ConvertTo-Json) -ContentType "application/json"
            } else {
                Send-Response -Body (Get-Process | ConvertTo-Html) -ContentType "text/html"
            }
        }
    }
    Start-Webserver -Routes $Routes -Port 8080

    This shows how to use parameters passed in the query string to alter your output.  To have the script output JSON instead of HTML,
    simply request /Process?format=json

.EXAMPLE
    #Add the System.Web assembly so we can use System.Web.HttpUtility to UrlEncode the return URL
    Add-Type -AssemblyName System.Web

    $Routes = @{
        "GetBarcode" = {
            $ProcessUrl = 'http://' + $Request.UserHostAddress + '/ProcessCode?code={CODE}'
            $RedirectUrl = "zxing://scan/?ret=" + [System.Web.HttpUtility]::UrlEncode($ProcessUrl)

            Write-Debug "Redirecting to $RedirectUrl"
            $Response.Redirect($RedirectUrl)
            $Response.Close()
        }
        "ProcessCode" = {
            Send-Response -Body "The barcode was $($Request.QueryString['code'])"
        }
    }
    Start-Webserver -Routes $Routes

    This example creates a web server that launches Google's Barcode Scanner application when an Android phone browses to /GetBarcode.  When
    a barcode is scanned, the phone is redirected to /ProcessCode?code=THEBARCODE and a message is returned to the browser displaying the
    value of the barcode that was scanned.

    This shows how to use a redirect as well as process input from the user using a query string.        
#>
function Start-WebServer {
    param(
        $Routes = @{},
        $IPAddress = "localhost",
        $Port = "80"
    )
    function Stop-WebServer {
        $Script:Running = $false
    }

    function Get-RFC2616Description {
        param(
            [int]$StatusCode
        )
        #Get the private HttpStatusDescription class so I don't have to type them all out myself
        $StatusDescription = [System.Net.HttpListener].Assembly.GetType("System.Net.HttpStatusDescription")
        $PrivateStatic = [System.Reflection.BindingFlags]::NonPublic -bor [System.Reflection.BindingFlags]::Static
        $GetMethod = $StatusDescription.GetMethods($PrivateStatic) | ?{
            $_.Name -eq "Get" -and $_.GetParameters()[0].ParameterType -eq [int32]
        }
        $GetMethod.Invoke($StatusDescription, $StatusCode)
    }

    function Get-ContentType { 
        param(
            $Extension
        )
        $ContentType = (Get-ItemProperty "HKLM:\Software\Classes\$Extension" -Name "Content Type" -ErrorAction SilentlyContinue)."Content Type"
        if($ContentType) {
            $ContentType
        } else {
            "text/plain"
        }
    }

    function Send-Response {
        [CmdletBinding(DefaultParameterSetName="Raw")]
        param(
            [Parameter(Mandatory,ParameterSetName="Raw",Position=0)]
            [ValidateNotNull()]
            $Body,

            [Parameter(Mandatory,ParameterSetName="File")]
            $Path,

            [Parameter(ParameterSetName="Raw")]
            [ValidateNotNull()]
            $ContentType = "text/plain",

            $StatusCode = 200,

            $StatusDescription
        )
        if(!$PSBoundParameters.ContainsKey("StatusDescription")) {
            $StatusDescription = Get-RFC2616Description -StatusCode $StatusCode
        }
        $Response.StatusCode = $StatusCode
        $Response.StatusDescription = $StatusDescription
        if($PsCmdlet.ParameterSetName -eq "File") {
            $Extension = [IO.Path]::GetExtension($Path)
            if($Extension) {
                $ContentType = Get-ContentType $Extension
            }
            if(!$ContentType) {
                $ContentType = "application/octet-stream"
            }
            $Stream = [System.IO.File]::OpenRead($Path)
        } else {
            $Stream = New-Object System.IO.MemoryStream(,[System.Text.Encoding]::UTF8.GetBytes($Body))
        }
        $Response.ContentType = $ContentType
        $Response.ContentLength64 = $Stream.Length
        $Stream.CopyTo($Response.OutputStream)
        #$Response.OutputStream.Write($Buffer, 0 , $Buffer.Length)
        $Response.OutputStream.Close()
        $Stream.Dispose()
    }

    if(!$Routes.Contains("Exit")) {
        $Routes.Add("Exit", $ExitHandler)
    }

    $Listener = New-Object System.Net.HttpListener
    $ListenPrefix = "http://${IPAddress}:${Port}/"
    Write-Debug "Listening on $ListenPrefix"
    $Listener.Prefixes.Add($ListenPrefix)

    $Script:Running = $true
    try {
        $Listener.Start()
        while($Running) {
            $Ctx = $Listener.GetContext()
            $Request = $Ctx.Request
            $Response = $Ctx.Response
            $RouteContextFunctions = @{
                "Send-Response" = ${Function:Send-Response}
                "Stop-WebServer" = ${Function:Stop-WebServer}
                "Get-ContentType" = ${Function:Get-ContentType}
            }
            $RouteContextVariables = @( (Get-Variable Request), (Get-Variable Response), (Get-Variable Running))
            Write-Verbose "Request accepted for $($Request.Url)"

            $RouteFound = $false
            foreach($Route in $Routes.Keys) {
                if($Request.Url.LocalPath -match $Route) {
                    Write-Debug "Matched route $Route"
                    $RouteFound = $true
                    try {
                        $Routes[$Route].InvokeWithContext($RouteContextFunctions, $RouteContextVariables, @())
                    } catch {
                        $Response.StatusCode = 500
                        Send-Response -Body ($_ | Out-String)
                    }
                    break;
                } else {
                    Write-Debug "Route $Route doesn't match"
                }
            }
            if(!$RouteFound) {
                Write-Warning "No route found for $($Request.Url)"
                $Response.Close()
            }
        }
        $Listener.Stop()
    } catch {
        Write-Error -Message "Could not start listener" -Exception $_.Exception
    } finally {
        if($Listener.IsListening) {
            $Listener.Stop()
        }
    }   
}
Export-ModuleMember -Function Start-WebServer