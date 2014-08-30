Properties {
  if(!$OutDir) {
    $OutDir = "Bin"
  }

  if(!$ProjectDir) {
    $ProjectDir = $PSake.build_script_dir
  }

  if(!$TargetDir) {
    $TargetDir = Join-Path $ProjectDir $OutDir
  }

  if(!$ProjectName) {
    $ProjectName = Split-Path $ProjectDir -Leaf
  }

  if(!$BasePath) {
    $BasePath = Join-Path $ProjectDir $ProjectName
  }
}

Task default

function Get-Nuget {
  $Nuget = (Join-Path $ProjectDir -ChildPath ".nuget\nuget.exe")
  Assert (Test-Path $Nuget) "Nuget.exe not found at $Nuget"
  return $Nuget
}

Task Clean {
  if(Test-Path $TargetDir) {
    rm -Recurse $TargetDir
  }
}

Task GenerateVersion {
  $NuSpec = (Join-Path $ProjectDir "$ProjectName.nuspec")
  Assert (Test-Path $NuSpec) "NuSpec file not found at $NuSpec"
  $NuSpecXml = [Xml](Get-Content -Raw -Path $NuSpec)
  $NuSpecVersion = [Version]($NuSpecXml.Package.Metadata.Version)
  $VersionDate = [DateTime]::Now.ToString("yyyyMMdd")

  if($Env:Build_Number) {
    $OutputVersion = New-Object System.Version($NuSpecVersion.Major, $NuSpecVersion.Minor, $VersionDate, $Env:Build_Number)
    $Script:VersionString = $OutputVersion.ToString()
    echo "BUILD_ID=$Script:VersionString"
  } else {
    $BuildTime = [int]([DateTime]::Now.TimeOfDay.TotalSeconds / 2)
    $OutputVersion = New-Object System.Version($NuSpecVersion.Major, $NuSpecVersion.Minor, $VersionDate, $BuildTime)
    $Script:VersionString = "{0}-manual" -f $OutputVersion.ToString()
  }
}
    
Task Pack -Depends GenerateVersion {
  $Nuget = Get-Nuget

  $NuSpec = (Join-Path $ProjectDir "$ProjectName.nuspec")
  Assert (Test-Path $NuSpec) "NuSpec file not found at $NuSpec"

  if(!(Test-Path $TargetDir)) {
    mkdir $TargetDir > $null
  }

  exec { &$Nuget pack $NuSpec -OutputDirectory $TargetDir -BasePath $BasePath -NoPackageAnalysis -NonInteractive -Version $Script:VersionString }
}