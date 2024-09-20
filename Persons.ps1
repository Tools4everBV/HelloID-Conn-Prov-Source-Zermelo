#####################################################
# HelloID-Conn-Prov-Source-Zermelo-Persons
#
# 1.0.0
#####################################################

# Set TLS to accept TLS, TLS 1.1 and TLS 1.2
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls -bor [Net.SecurityProtocolType]::Tls11 -bor [Net.SecurityProtocolType]::Tls12

$VerbosePreference = "SilentlyContinue"
$InformationPreference = "Continue"
$WarningPreference = "Continue"

$c = $configuration | ConvertFrom-Json

$baseUri = ($c.BaseUrl).Trim()
$token = ($c.Token).Trim()
$schoolCode = ($c.SchoolCode).Trim()
$correlationField = $c.CorrelationField
$SpecialChar = '#'

# Set debug logging
switch ($($c.isDebug)) {
    $true { $VerbosePreference = 'Continue' }
    $false { $VerbosePreference = 'SilentlyContinue' }
}

#region functions
function Resolve-HTTPError {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory,
            ValueFromPipeline
        )]
        [object]$ErrorObject
    )
    process {
        $httpErrorObj = [PSCustomObject]@{
            FullyQualifiedErrorId = $ErrorObject.FullyQualifiedErrorId
            MyCommand             = $ErrorObject.InvocationInfo.MyCommand
            RequestUri            = $ErrorObject.TargetObject.RequestUri
            ScriptStackTrace      = $ErrorObject.ScriptStackTrace
            ErrorMessage          = ''
        }
        if ($ErrorObject.Exception.GetType().FullName -eq 'Microsoft.PowerShell.Commands.HttpResponseException') {
            $httpErrorObj.ErrorMessage = $ErrorObject.ErrorDetails.Message
        }
        elseif ($ErrorObject.Exception.GetType().FullName -eq 'System.Net.WebException') {
            $httpErrorObj.ErrorMessage = [System.IO.StreamReader]::new($ErrorObject.Exception.Response.GetResponseStream()).ReadToEnd()
        }
        Write-Output $httpErrorObj
    }
}

function Get-ErrorMessage {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory,
            ValueFromPipeline
        )]
        [object]$ErrorObject
    )
    process {
        $errorMessage = [PSCustomObject]@{
            VerboseErrorMessage = $null
            AuditErrorMessage   = $null
        }

        if ( $($ErrorObject.Exception.GetType().FullName -eq 'Microsoft.PowerShell.Commands.HttpResponseException') -or $($ErrorObject.Exception.GetType().FullName -eq 'System.Net.WebException')) {
            $httpErrorObject = Resolve-HTTPError -Error $ErrorObject

            $errorMessage.VerboseErrorMessage = $httpErrorObject.ErrorMessage

            $errorMessage.AuditErrorMessage = $httpErrorObject.ErrorMessage
        }

        # If error message empty, fall back on $ex.Exception.Message
        if ([String]::IsNullOrEmpty($errorMessage.VerboseErrorMessage)) {
            $errorMessage.VerboseErrorMessage = $ErrorObject.Exception.Message
        }
        if ([String]::IsNullOrEmpty($errorMessage.AuditErrorMessage)) {
            $errorMessage.AuditErrorMessage = $ErrorObject.Exception.Message
        }

        Write-Output $errorMessage
    }
}

function Get-ZermeloEndpointData {
    param(
        [parameter(Mandatory = $true) ]$Token,
        [parameter(Mandatory = $true) ]$BaseUri,
        [parameter(Mandatory = $true) ]$EndPoint,
        [parameter(Mandatory = $false)]$Filter,
        [parameter(Mandatory = $false)]$Fields
    )

    $Method = 'Get'
    $Uri = "$($BaseUri)/api/v3/$endpoint"
    $ContentType = 'application/json'
    try {
        Write-Verbose "Starting downloading Objects through endpoint [$endpoint]"
        $headers = [System.Collections.Generic.Dictionary[[String],[String]]]::new()
        $headers.Add('Authorization', "Bearer $($Token)")

        $splatParams = @{
            Uri         = $Uri
            Headers     = $Headers
            Method      = $Method
            ContentType = $ContentType
        }
        If ($Filter -is [HashTable]) {
            $splatParams['Body'] += $Filter
        }
        if ($fields -is [array]) {
            $splatParams['Body'] += @{fields=$($fields -join ',')}
        }
        elseif ($fields -is [string]) {
            $splatParams['Body'] += @{fields=$fields}
        }
        $data = (Invoke-RestMethod @splatParams -Verbose:$false).response.data
        Write-Verbose "Downloaded [$($data.count)] records through Endpoint [$Endpoint]"
        return $data
    }
    catch {
        $PSCmdlet.ThrowTerminatingError($_)
<#
        $data.Value = $null

        $ex = $PSItem
        $errorMessage = Get-ErrorMessage -ErrorObject $ex

        Write-Verbose "Error at Line [$($ex.InvocationInfo.ScriptLineNumber)]: $($ex.InvocationInfo.Line). Error: $($errorMessage.VerboseErrorMessage)"

        throw "Error querying data from [$uri]. Error Message: $($errorMessage.AuditErrorMessage)"
#>
    }
}
#endregion functions

#Determine Years
$Years = @((Get-Date).AddYears(-1).Year;(Get-Date).Year)

#Query Tables
try {
    $Schools = Get-ZermeloEndpointData -Token:$Token -BaseUri:$baseUri -EndPoint:'schools' -Filter:@{name=$SchoolCode}
    $Sections = Get-ZermeloEndpointData -Token:$Token -BaseUri:$baseUri -EndPoint:'sections'
    $Sections = $Sections | Sort-Object -Property:id | Group-Object -Property:id -AsHashTable
    $TaskGroups = Get-ZermeloEndpointData -Token:$Token -BaseUri:$baseUri -EndPoint:'taskgroups'
    $TaskGroups = $TaskGroups | Sort-Object -Property:id | Group-Object -Property:id -AsHashTable

    $SchoolsInSchoolyears = @()
    $BranchesOfSchools = @()
    $Employees = @()

    $EmployeeFields = @('userCode','firstName','prefix','lastName','employeeNumber')
    if ($ZermeloCorrelationField -notin $EmployeeFields) {
        $EmployeeFields += @($correlationField)
    }

    $Contracts = @()
    $TeacherTeams = @()
    $SectionAssignments = @()
    $SectionOfBranches = @()
    $TaskAssignments = @()
    $TasksInBranchOfSchool = @()

    ForEach ($School in $Schools) {
        ForEach ($Year in $Years) {
            $SchoolsInSchoolyears += Get-ZermeloEndpointData -Token:$Token -BaseUri:$baseUri -EndPoint:'schoolsinschoolyears' -Filter:@{school=$school.id;year=$Year}
        }
        If ($SchoolsInSchoolyears -eq $null) {
            Throw "No Schools in Schoolyears found"
        }
        ForEach ($SchoolInSchoolyear in $SchoolsInSchoolyears) {
            $Employees += Get-ZermeloEndpointData -Token:$Token -BaseUri:$baseUri -EndPoint:'employees' -Filter:@{archived=$false;schoolInSchoolYear=$SchoolinSchoolyear.id} -Fields:$EmployeeFields #@('userCode', 'employeeNumber', 'firstName', 'prefix', 'lastName')
            $Contracts += Get-ZermeloEndpointData -Token:$Token -BaseUri:$baseUri -EndPoint:'contracts' -Filter:@{schoolInSchoolYear=$SchoolinSchoolyear.id} -Fields:@('id', 'employee', 'start', 'end', 'isMainContract', 'defaultFunctionCategory', 'teacherTeam')
            $TeacherTeams += Get-ZermeloEndpointData -Token:$Token -BaseUri:$baseUri -EndPoint:'teacherteams' -Filter:@{schoolInSchoolYear=$SchoolinSchoolyear.id} -Fields:@('id', 'name')
            $SectionAssignments += Get-ZermeloEndpointData -Token:$Token -BaseUri:$baseUri -EndPoint:'sectionassignments' -Filter:@{schoolInSchoolYear=$SchoolinSchoolyear.id}
            $SectionOfBranches += Get-ZermeloEndpointData -Token:$Token -BaseUri:$baseUri -EndPoint:'sectionofbranches' -Filter:@{schoolInSchoolYear=$SchoolinSchoolyear.id}

            $BranchesOfSchools = Get-ZermeloEndpointData -Token:$Token -BaseUri:$baseUri -EndPoint:'branchesofschools' -Filter:@{schoolInSchoolYear=$SchoolinSchoolyear.id}
            ForEach ($BranchOfSchool in $BranchesOfSchools) {
                $TasksInBranchOfSchool += Get-ZermeloEndpointData -Token:$Token -BaseUri:$baseUri -EndPoint:'tasksinbranchofschool' -Filter:@{branchOfSchool=$BranchOfSchool.id}
                $TaskAssignments += Get-ZermeloEndpointData -Token:$Token -BaseUri:$baseUri -EndPoint:'taskassignments' -Filter:@{branchOfSchool=$BranchOfSchool.id}
            }
        }
    }
}
catch {
    $ex = $PSItem
    $errorMessage = Get-ErrorMessage -ErrorObject $ex

    Write-Verbose "Error at Line [$($ex.InvocationInfo.ScriptLineNumber)]: $($ex.InvocationInfo.Line). Error: $($errorMessage.VerboseErrorMessage)"

    throw "Could not query Schools. Error Message: $($errorMessage.AuditErrorMessage)"
}

try {
    $Persons = $Employees | Sort-Object -Property:userCode | Select-Object -Property:* -Unique
    $Persons = $Persons | Where-Object {($_.firstname -ne $null) -and ($_.lastname -ne $null)}
    Write-Verbose "Persons unique records count:$($Persons.count)"
    $persons | Add-Member -MemberType:NoteProperty -Name:"Contracts" -Value:@() -Force
    $persons | Add-Member -MemberType:NoteProperty -Name:"ExternalId" -Value:$null -Force
    $persons | Add-Member -MemberType:NoteProperty -Name:"DisplayName" -Value:$Null -Force

    $Contracts | Add-Member -MemberType:NoteProperty -Name:"ExternalId" -Value:$null -Force
    $Contracts | Add-Member -MemberType:NoteProperty -Name:"Sections" -Value:$null -Force
    $Contracts | Add-Member -MemberType:NoteProperty -Name:"Tasks" -Value:$null -Force
    $Contracts = $Contracts | Group-Object -Property:employee -AsHashTable

    $TeacherTeams = $TeacherTeams | Group-Object -Property:id -AsHashTable

    $TaskAssignments = $TaskAssignments | Sort-Object -Property:contract,start,end
    $TasksInBranchOfSchool = $TasksInBranchOfSchool |Group-Object -Property:id -AsHashTable

    $SectionAssignments = $SectionAssignments | Group-Object -Property:contract -AsHashTable
    $SectionOfBranches = $SectionOfBranches | Group-Object -Property:id -AsHashTable

    $PersonsFiltered = $Persons | Where-Object {$_.$correlationField -ne $null -and $_.$correlationField -ne ''}
    If ($PersonsFiltered -eq $null) {
        throw "No persons left after filtering empty correlation field"
    }
    If ($CorrelationField.ToLower() -ne 'employeenumber') { #Check if all persons have a valid correlation field when using not standard field
        $Invalid = ($PersonsFiltered | Where-Object {$_.$correlationField -notlike "$SpecialChar*$SpecialChar"})
        If ($Invalid -ne $null) {
            throw "One or more Persons found with invalid correlation field"
        }
    }
    Write-Information "Person records after filtering:$($PersonsFiltered.Count)"


    $exportedPersons = 0
    ForEach ($Person in ($PersonsFiltered)) {
        Switch ($correlationField.ToLower()) {
            'employeenumber' {
                $Person.ExternalId = $person.$correlationField
            }
            default { #Remove SpecialChar at start en and to get clean ExternalID
                $Person.ExternalId = $person.$correlationField.SubString($SpecialChar.Length,$person.$correlationField.Length - (2 * $SpecialChar.Length))
            }
        }

        $Person.DisplayName = "$($Person.firstname) $(if ($Person.prefix) {"$($Person.prefix) $($person.lastname)"} else {"$($person.lastname)"}) ($($Person.userCode.ToUpper()))"

        If ($c.Compact -ne $false) {
            ForEach ($Contract in $Contracts[$Person.userCode]) {
                $SubContractNr = 0
                $ContractTaskAssignments = @() + ($TaskAssignments | Where-Object {$_.contract -eq $Contract.id}| Group-Object -Property:start, end)
                Do {
                    $SubContract = ($Contract | Select-Object -Property:*)
                    $SubContract.ExternalId = "$($SubContract.id)-$($SubContractNr)"

                    If ($SubContract.teacherTeam -ne $null) {
                        $SubContract.teacherTeam = @{
                            'ExternalId' = $TeacherTeams[$SubContract.teacherTeam].id
                            'Name' = $TeacherTeams[$SubContract.teacherTeam].name
                        }
                    }
                    Else {
                        $SubContract.teacherTeam = @{'ExternalId' = $null; 'Name' = $null}
                    }

                    ForEach ($SectionAssignment in $SectionAssignments[$SubContract.id]) {
                        ForEach ($SectionOfBranch in $SectionOfBranches[$SectionAssignment.sectionOfBranch]) {
                            $SubContract.Sections += $Sections[$SectionOfBranch.section]
                        }
                    }
                    $SubContract.Sections = @() + ($SubContract.Sections | Select-Object -Property:@{Name = 'ExternalId'; Expression = {$_.id}}, @{Name = 'Code'; Expression = {$_.abbreviation}}, @{Name = 'Name'; Expression = {$_.Name}} -Unique ) |ConvertTo-Json
                    If ($SubContract.Sections -eq $null) {
                        $SubContract.Sections = @(@{'ExternalId' = $null; 'Code' = $null; 'Name' = $null}) |ConvertTo-Json
                    }

                    If ($ContractTaskAssignments.Count -gt 0) {
                        $ContractTaskAssignment = $ContractTaskAssignments[$SubContractNr]

                        If (($ContractTaskAssignment.Values[0] -ne $null) -or
                            ($ContractTaskAssignment.Values[1] -ne $null)) {
                            $SubContract.start = $ContractTaskAssignment.Values[0]
                            $SubContract.end = $ContractTaskAssignment.Values[1]
                        }
                        $SubContract.Tasks = @()
                        ForEach ($TaskAssignment in $ContractTaskAssignment.Group) {
                            $SubContract.Tasks += $TasksInBranchOfSchool[$TaskAssignment.taskInBranchOfSchool]
                        }
                        $SubContract.Tasks = @() + ($SubContract.Tasks | Select-Object -Property:@{Name = 'ExternalId'; Expression = {$_.id}}, @{Name = 'Code'; Expression = {$_.taskAbbreviation}}, @{Name = 'Name'; Expression = {$_.taskName}}, @{Name = 'Description'; Expression = {$_.taskDescription}} -Unique) |ConvertTo-Json

                    }
                    Else {
                        $SubContract.Tasks = @(@{'ExternalId' = $null; 'Code' = $null; 'Name' = $null; 'Description' = $null}) |ConvertTo-Json
                    }

                    $SubContract.start = $SubContract.start -replace '(?<yyyy>\d\d\d\d)(?<MM>\d\d)(?<dd>\d\d)', '${yyyy}-${MM}-${dd}'
                    $SubContract.end = $SubContract.end -replace '(?<yyyy>\d\d\d\d)(?<MM>\d\d)(?<dd>\d\d)', '${yyyy}-${MM}-${dd}'
                    $Person.Contracts += $SubContract

                    $SubContractNr ++
                } While ($SubContractNr -lt $ContractTaskAssignments.Count)
            }
        }
        Else {
            ForEach ($Contract in $Contracts[$Person.userCode]) {
                If ($Contract.teacherTeam -ne $null) {
                    $Contract.teacherTeam = @{
                        'ExternalId' = $TeacherTeams[$Contract.teacherTeam].id
                        'Name' = $TeacherTeams[$Contract.teacherTeam].name
                    }
                }
                Else {
                    $Contract.teacherTeam = @{'ExternalId' = $null; 'Name' = $null}
                }


                If ($SectionAssignments[$Contract.id].Count -gt 0 -or ($TaskAssignments | Where-Object {$_.contract -eq $Contract.id}).Count -gt 0) {

                    ForEach ($SectionAssignment in $SectionAssignments[$Contract.id]) {
                        ForEach ($SectionOfBranch in $SectionOfBranches[$SectionAssignment.sectionOfBranch]) {
                            $SubContract = ($Contract | Select-Object -Property:*)
                            $SubContract.ExternalId = "$($SubContract.id)-S$($SectionOfBranch.id)"
                            $SubContract.Sections = $Sections[$SectionOfBranch.section] | Select-Object -Property:@{Name = 'ExternalId'; Expression = {$_.id}}, @{Name = 'Code'; Expression = {$_.abbreviation}}, @{Name = 'Name'; Expression = {$_.Name}}

                            $SubContract.Tasks = @{'ExternalId' = $null; 'Code' = $null; 'Name' = $null; 'Description' = $null}

                            $SubContract.start = $Contract.start -replace '(?<yyyy>\d\d\d\d)(?<MM>\d\d)(?<dd>\d\d)', '${yyyy}-${MM}-${dd}'
                            $SubContract.end = $Contract.end -replace '(?<yyyy>\d\d\d\d)(?<MM>\d\d)(?<dd>\d\d)', '${yyyy}-${MM}-${dd}'
                            $Person.Contracts += $SubContract
                        }
                    }

                    ForEach ($TaskAssignment in ($TaskAssignments | Where-Object {$_.contract -eq $Contract.id})) {
                        $SubContract = ($Contract | Select-Object -Property:*)
                        $SubContract.ExternalId = "$($SubContract.id)-T$($TasksInBranchOfSchool[$TaskAssignment.taskInBranchOfSchool].id)"
                        $SubContract.Tasks = $TasksInBranchOfSchool[$TaskAssignment.taskInBranchOfSchool] | Select-Object -Property:@{Name = 'ExternalId'; Expression = {$_.id}}, @{Name = 'Code'; Expression = {$_.taskAbbreviation}}, @{Name = 'Name'; Expression = {$_.taskName}}, @{Name = 'Description'; Expression = {$_.taskDescription}}

                        $SubContract.Sections = @{'ExternalId' = $null; 'Code' = $null; 'Name' = $null}

                        If ($TaskAssigment.Start -ne $null) {
                            $SubContract.Start = $TaskAssigment.Start
                        }
                        If ($TaskAssigment.End -ne $null) {
                            $SubContract.End = $TaskAssigment.End
                        }
                        $SubContract.start = $Contract.start -replace '(?<yyyy>\d\d\d\d)(?<MM>\d\d)(?<dd>\d\d)', '${yyyy}-${MM}-${dd}'
                        $SubContract.end = $Contract.end -replace '(?<yyyy>\d\d\d\d)(?<MM>\d\d)(?<dd>\d\d)', '${yyyy}-${MM}-${dd}'
                        $Person.Contracts += $SubContract
                    }

                }
                Else {
                    $Contract.ExternalId = "$($Contract.id)"

                    $Contract.Sections = @{'ExternalId' = $null; 'Code' = $null; 'Name' = $null}
                    $Contract.Tasks = @{'ExternalId' = $null; 'Code' = $null; 'Name' = $null; 'Description' = $null}

                    $Contract.start = $Contract.start -replace '(?<yyyy>\d\d\d\d)(?<MM>\d\d)(?<dd>\d\d)', '${yyyy}-${MM}-${dd}'
                    $Contract.end = $Contract.end -replace '(?<yyyy>\d\d\d\d)(?<MM>\d\d)(?<dd>\d\d)', '${yyyy}-${MM}-${dd}'
                    $Person.Contracts += $Contract
                }
            }
        }
        Write-Output $Person| ConvertTo-Json -Depth 10
        $exportedPersons++
    }
    Write-Information "Successfully enhanced and exported person objects to HelloID. Result count: $($exportedPersons)"
    Write-Information "Person import completed"
}
catch {
    $ex = $PSItem
    $errorMessage = Get-ErrorMessage -ErrorObject $ex

    # If debug logging is toggled, log on which person and line the error occurs
    if ($c.isDebug -eq $true) {
        Write-Warning "Error occurred for person [$($personInProcess.ExternalId)]. Error at Line [$($ex.InvocationInfo.ScriptLineNumber)]: $($ex.InvocationInfo.Line). Error: $($errorMessage.VerboseErrorMessage)"
    }

    throw "Could not enhance and export person objects to HelloID. Error Message: $($errorMessage.AuditErrorMessage)"
}