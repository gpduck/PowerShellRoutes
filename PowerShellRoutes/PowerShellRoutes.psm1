$Script:ModuleRoot = $PsScriptRoot

dir (Join-Path $ModuleRoot "ExportedFunctions\*.ps1") | %{
	. $_.fullname
}