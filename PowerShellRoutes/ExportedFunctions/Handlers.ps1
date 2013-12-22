$FileHandler = {
    function Get-ContentType { 
        param(
            $Extension
        )
        (Get-ItemProperty "HKLM:\Software\Classes\$Extension" -Name "Content Type" -ErrorAction SilentlyContinue)."Content Type"
    }

    $LocalPath = Join-Path -Path (Get-Location).Path -ChildPath $Request.Url.AbsolutePath
    if([IO.File]::Exists($LocalPath)) {
        Send-Response -Path $LocalPath
    } else {
        Write-Debug "$Response"
        Send-Response -Body "404 $Localpath not found" -StatusCode 404
    }
}
Export-ModuleMember -Variable FileHandler

$ExitHandler = {
    #Set-Variable -name Running -Value $False -Scope 1
    Send-Response -Body "Exiting..."
    Stop-WebServer
}
Export-ModuleMember -Variable ExitHandler