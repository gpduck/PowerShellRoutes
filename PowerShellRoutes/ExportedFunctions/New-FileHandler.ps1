function New-FileHandler {
    param(
        [Parameter(Mandatory=$true)]
        $Path
    )
    {
        $LocalPath = Join-Path -Path $Path -ChildPath $Request.Url.AbsolutePath
        if([IO.File]::Exists($LocalPath)) {
            Send-Response -Path $LocalPath
        } else {
            Write-Debug "$Response"
            Send-Response -Body "404 $Localpath not found" -StatusCode 404
        }
    }.GetNewClosure()
}
Export-ModuleMember -Function New-FileHandler