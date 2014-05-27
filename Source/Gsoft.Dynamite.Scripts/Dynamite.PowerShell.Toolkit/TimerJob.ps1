﻿#
# Module 'Dynamite.PowerShell.Toolkit'
# Generated by: GSoft, Team Dynamite.
# Generated on: 13/05/2014
# > GSoft & Dynamite : http://www.gsoft.com
# > Dynamite Github : https://github.com/GSoft-SharePoint/Dynamite-PowerShell-Toolkit
# > Documentation : https://github.com/GSoft-SharePoint/Dynamite-PowerShell-Toolkit/wiki
#

<#
	.SYNOPSIS
		Commandlet to configure SharePoint Timer Jobs scheduling

	.DESCRIPTION
		Set scheduling of timer jobs

    --------------------------------------------------------------------------------------
    Module 'Dynamite.PowerShell.Toolkit'
    by: GSoft, Team Dynamite.
    > GSoft & Dynamite : http://www.gsoft.com
    > Dynamite Github : https://github.com/GSoft-SharePoint/Dynamite-PowerShell-Toolkit
    > Documentation : https://github.com/GSoft-SharePoint/Dynamite-PowerShell-Toolkit/wiki
    --------------------------------------------------------------------------------------
   
    .NOTES
         Here is the Structure XML schema.

        <Configuration>
	        <WebApplication Url="http://mywebapp">
		        <Jobs>
			        <!-- Variations Propagate List Items Job Definition 
                         Schedule: http://www.petri.co.il/manage-timer-jobs-sharepoint-2013-with-powershell.htm 
                    -->
			        <Job Guid="02cac8e4-3e5d-4ad5-9f55-bdac0dbf8687" Schedule="Every 5 minutes" Description="Variations Propagate List Items"/>
		        </Jobs>
	        </WebApplication>
        </Configuration>

	.EXAMPLE
		PS C:\> Set-DSPTimerJobs "D:\TimerJobs.xml" 

	.OUTPUTS
		n/a. 
    
  .LINK
    GSoft, Team Dynamite on Github
    > https://github.com/GSoft-SharePoint
    
    Dynamite PowerShell Toolkit on Github
    > https://github.com/GSoft-SharePoint/Dynamite-PowerShell-Toolkit
    
    Documentation
    > https://github.com/GSoft-SharePoint/Dynamite-PowerShell-Toolkit/wiki
    
#>
function Set-DSPTimerJobs() {
	
	[CmdletBinding()]
	Param
	(
		[Parameter(Mandatory=$true, Position=0)]
		[string]$XmlPath
	)

    $Config = [xml](Get-Content $XmlPath)
	
    # Process all Web Applications
	$Config.Configuration.WebApplication | ForEach-Object {

        Schedule-DSPTimerJobs $_.Jobs $_.Url
    }

}

function Schedule-DSPTimerJobs() {
	
	[CmdletBinding()]
	Param
	(
		[Parameter(Mandatory=$true, Position=0)]
		[System.Xml.XmlElement]$Jobs,
		
		[Parameter(Mandatory=$true, Position=1)]
		[string]$WebApplicationUrl
	)

    Write-Verbose "Entering Schedule-DSPTimerJobs with $WebApplicationUrl"
	
	if ($Jobs -ne $null)
	{
        $WebApplication = Get-SPWebApplication -Identity $WebApplicationUrl

        if($WebApplication -ne $null)
        {
            $Jobs.Job | Foreach-Object {
            
                $JobGuid = $_.Guid
                $JobSchedule = $_.Schedule
                $JobDescription = $_.Description

                Write-Verbose "Set $JobDescription job definition scheduling to $JobSchedule"

                Get-SPTimerJob -Identity $JobGuid -WebApplication $WebApplication | Set-SPTimerJob -Schedule $JobSchedule
            }
        }   
    }
}