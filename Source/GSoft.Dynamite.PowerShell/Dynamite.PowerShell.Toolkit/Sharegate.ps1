
function Test-SharegateModule {

	# Check if Sharegate is installed
	if ((Get-Module | where { $_.Name -eq "Sharegate" }).Count -ne 1) {
		Throw "Sharegate PowerShell module is not correctly installed."
	}
}

<#
    .SYNOPSIS
		Import data into a site and subsites hierarchy using Sharegate.
	
    .DESCRIPTION
		Recursively import data from a folder hierarchy into a mirror site and subsites hierarchy. 
		The folder structure can be generated by using the feature "Export from SharePoint" from Sharegate

    --------------------------------------------------------------------------------------
    Module 'Dynamite.PowerShell.Toolkit'
    by: GSoft, Team Dynamite.
    > GSoft & Dynamite : http://www.gsoft.com
    > Dynamite Github : https://github.com/GSoft-SharePoint/Dynamite-PowerShell-Toolkit
    > Documentation : https://github.com/GSoft-SharePoint/Dynamite-PowerShell-Toolkit/wiki
    --------------------------------------------------------------------------------------
		
    .PARAMETER FromFolder
	    [REQUIRED] The root folder path that contains data

    .PARAMETER ToUrl
	    [REQUIRED] The root folder URL to import to. Must be a mirror strucutre as the folder one

	.PARAMETER Keys
	    [OPTIONAL] The keys used to determine duplicates between imported imtes. By default, Sharegate uses 'Title' and 'Created' 

	.PARAMETER PropertyTemplateFile
	    [OPTIONAL] The Sharegate property mapping template file to use for all lists and libraries

	.PARAMETER TemplateName
	    [OPTIONAL] The template name chosen during the UI Sharegate template export

    .EXAMPLE
		    PS C:\> Import-Data -FromFolder "C:\Sharegate" -ToUrl "http://webapp/sites/test"

			PS C:\> Import-Data -FromFolder "C:\Sharegate" -ToUrl "http://webapp/sites/test" -Keys "ID","ContentType","MyCustomColumn"

			PS C:\> Import-Data -FromFolder "C:\Sharegate" -ToUrl "http://webapp/sites/test" -PropertyTemplateFile "C:\mytemplate.sgt" -TemplateName "MyTemplate"

    .LINK
    GSoft, Team Dynamite on Github
    > https://github.com/GSoft-SharePoint
    
    Dynamite PowerShell Toolkit on Github
    > https://github.com/GSoft-SharePoint/Dynamite-PowerShell-Toolkit
    
    Documentation
    > https://github.com/GSoft-SharePoint/Dynamite-PowerShell-Toolkit/wiki
    
#>
function Import-DSPData {

	Param
	(
		[ValidateScript({Test-Path $_ -PathType 'Container'})] 
		[Parameter(Mandatory=$true)]
		[string]$FromFolder,

		[ValidateScript({(Get-SPWeb $_) -ne $null})]
		[Parameter(Mandatory=$true)]
		[string]$ToUrl,  

		[Parameter(Mandatory=$false)]
		[array]$Keys,

		[ValidateScript({Test-Path $_ -PathType 'Leaf'})]
		[Parameter(Mandatory=$false, ParameterSetName = "PropertyMapping")]
		[string]$PropertyTemplateFile,

		[Parameter(Mandatory=$false, ParameterSetName = "PropertyMapping")]
		[string]$TemplateName
	)

    function Process-WebFolder {

        Param
	    (
            [Parameter(Mandatory=$true)]
		    [string]$WebUrl,

		    [Parameter(Mandatory=$true)]
		    [string]$WebFolder
	    )

        $Lists = New-Object System.Collections.ArrayList

        # Add a new entry for the web
        $Webs.Add($WebUrl, $null)

        $SubFolders = Get-ChildItem $WebFolder -Directory  

		$SubFolders | ForEach-Object {

            $CurrentFolder = $_
            $Title = $CurrentFolder.Name
				
            # Getting only subsites under the current web (first without name trimming)
            $AssociatedSubSites = Get-Subsite -Site (Connect-Site $WebUrl) -Name $Title

			if ($AssociatedSubSites -eq $null -and ($CurrentFolder.Name -match "[\s]*[\d]$"))
			{
				# If the current folder appears to be a duplicate incremented automatically by Sharegate
				$Title = $CurrentFolder.Name -replace "[\s]*[\d]$"
				
				# Getting only subsites under the current web (with name trimming)
				$AssociatedSubSites = Get-Subsite -Site (Connect-Site $WebUrl) -Name $Title
			}
           
            if ($AssociatedSubSites)
            {
                # Get the first web which is not already in the web collection. Theoretically, it should be the same order as Sharegate export
                $AssociatedWeb = $AssociatedSubSites | Where-Object { $Webs.Get_Item($_.Address.AbsoluteUri) -eq $null } | Select-Object -First 1

                $FolderUrl = $CurrentFolder.FullName
                $WebFullUrl = $AssociatedWeb.Address

				Write-Host "Match " -NoNewline 
                Write-Host "'$Title' " -NoNewline -ForegroundColor Green
				Write-Host "with web " -NoNewline
				Write-Host "'$WebFullUrl'" -ForegroundColor Yellow
  
                Process-WebFolder -WebUrl $WebFullUrl -WebFolder $CurrentFolder.FullName 
            }
            else
            {
                $Lists.Add($_) | Out-Null
            }  
        }

        # Add lists for this web
        $Webs.Set_Item($WebUrl, $Lists) 
    }

	Try
	{
        Start-SPAssignment -Global
        
		# Check if Sharegate is installed
		Test-SharegateModule

        # Configure Copy Settings
        $copySettings = New-CopySettings -OnContentItemExists Overwrite 
                       
        $Webs = @{} 

        Process-WebFolder -WebUrl $ToUrl -WebFolder $FromFolder

        $Webs.Keys | Foreach-Object {
        
            $CurrentWeb = $_

            Write-Host "Processing " -NoNewline 
			Write-Host "'$CurrentWeb'" -ForegroundColor Green -NoNewline
			Write-Host "..." 

            $Webs.Item($_) | ForEach-Object {

                $ListName = $_.Name
                $SourceFolder = $_.FullName  
                      
                $Site = Connect-Site -Url $CurrentWeb
                $DestList = Get-List -Site $Site -Name $ListName
				
				Write-Host "`tProcessing list folder " -NoNewline 
				Write-Host "'$ListName'" -ForegroundColor Yellow -NoNewline
				Write-Host "..." 
				
                $ExcelFile = Get-ChildItem $SourceFolder -Include *.xlsx,*.xls -Recurse

                if ($DestList)
                {
					if ([string]::IsNullOrEmpty($PropertyTemplateFile) -eq $false)
					{
						# Import Custom Template for column mappings
						Import-PropertyTemplate -Path $PropertyTemplateFile -List $DestList
						$UseCustomTemplate = $true
					}

                    if ($DestList.BaseType -eq "Document Library")
                    {
                        Write-Host "`t`tList '$ListName' found in web '$CurrentWeb'! Importing documents..."

						if ($UseCustomTemplate)
						{
							Import-Document -ExcelFilePath $ExcelFile.FullName -DestinationList $DestList -TemplateName $TemplateName
						}
						else
						{
							Import-Document -ExcelFilePath $ExcelFile.FullName -DestinationList $DestList 
						}
                    }
                    else
                    {
                        # Trick to get the exact mappings settings for the list
				        $mappingSettings = Get-PropertyMapping -SourceList $DestList -DestinationList $DestList

						# If custom keys are defined 
						if ($Keys -ne $null)
						{
                            Write-Host "`t`tAdding custom keys for duplicates..."

                            $Keys | Foreach-Object {
                            
                                Write-Host "`t`tKey: " -NoNewline
                                Write-Host "$_" -ForegroundColor Yellow

                                # Add custom key
				                $mappingSettings = Set-PropertyMapping -MappingSettings $mappingSettings -Source $_ -Destination $_ -Key
                            }
                          
				            # Remove Sharegate default keys
				            $mappingSettings = Set-PropertyMapping -MappingSettings $mappingSettings -Source Created -Destination Created
				            $mappingSettings = Set-PropertyMapping -MappingSettings $mappingSettings -Source Title -Destination Title
						}
                        
                        # Get a fake list (not needed in the Copy-Content cmdlet because we use an Excel file but necessary for the cmdlet)
                        # To ensure Sharegate will not connect to this list, we have to get one where attachments are disabled (Sharegate hack)
                        # We get a list in the central admin root web to avoid the case where the current web does not contain any list.
                        $webApp = Get-SPWebApplication -IncludeCentralAdministration | Where-Object { $_.IsAdministrationWebApplication -eq $true }
			            $SrcList = Connect-Site -Url $webApp.Url  | Get-List | Where-Object {$_.BaseType -eq "List" -and $_.EnableAttachments -eq $false} | Select -First 1

                        Write-Host "`t`tList '$ListName' found! Importing list items..."

						if ($UseCustomTemplate)
						{
							Copy-Content -SourceList $SrcList -DestinationList $DestList -ExcelFilePath $ExcelFile.FullName -MappingSettings $mappingSettings -TemplateName $TemplateName

						}
						else
						{
							Copy-Content -SourceList $SrcList -DestinationList $DestList -ExcelFilePath $ExcelFile.FullName -MappingSettings $mappingSettings 
						}
                    }
                }
				else
				{					
					    Write-Warning "`t`tList '$ListName' not found in web '$CurrentWeb'! Skipping..."
				}		
            }      
        }

        Stop-SPAssignment -Global
	}
	Catch
	{
		$ErrorMessage = $_.Exception.Message
        Throw $ErrorMessage
	}
}