<#
.Synopsis
    First Boot device verifier
.DESCRIPTION
    Used to verify that SSD is indeed first boot device on a system with two hard drives.
	If necessary, sets a variable needed to switch installation drives.
.EXAMPLE
    ResetTPMOwner.ps1
.NOTES
    Created:	 2018-05-02
    Version:	 1.0
    Author - Anton Romanyuk
    Twitter: @admiraltolwyn
    Blog   : http://www.vacuumbreather.com
    Disclaimer:
    This script is provided 'AS IS' with no warranties, confers no rights and 
    is not supported by the author.
.LINK
    http://www.vacuumbreather.com
.NOTES

#>

# Determine where to do the logging 
$tsenv = New-Object -COMObject Microsoft.SMS.TSEnvironment 
$logPath = $tsenv.Value("LogPath")  
$logFile = "$logPath\$($myInvocation.MyCommand).log"
$Model = $TSenv.Value("Model")
$disks = @()

# Create Log folder
$testPath = Test-Path $logPath
If (!$testPath)
{
    New-Item -ItemType Directory -Path $logPath
}
 
# Create Logfile
Write-Output "$ScriptName - Create Logfile" > $logFile
 
Function Logit($TextBlock1){
	$TimeDate = Get-Date
	$OutPut = "$ScriptName - $TextBlock1 - $TimeDate"
	Write-Output $OutPut >> $logFile
}

# http://ramblingcookiemonster.github.io/Join-Object/
function Join-Object
{
    [CmdletBinding()]
    Param
    (
        [Parameter(Mandatory=$true,
                   ValueFromPipeLine = $true)]
        [object[]] $Left,

        # List to join with $Left
        [Parameter(Mandatory=$true)]
        [object[]] $Right,

        [Parameter(Mandatory = $true)]
        [string] $LeftJoinProperty,

        [Parameter(Mandatory = $true)]
        [string] $RightJoinProperty,

        [object[]]$LeftProperties = '*',

        # Properties from $Right we want in the output.
        # Like LeftProperties, each can be a plain name, wildcard or hashtable. See the LeftProperties comments.
        [object[]]$RightProperties = '*',

        [validateset( 'AllInLeft', 'OnlyIfInBoth', 'AllInBoth', 'AllInRight')]
        [Parameter(Mandatory=$false)]
        [string]$Type = 'AllInLeft',

        [string]$Prefix,
        [string]$Suffix
    )
    Begin
    {
        function AddItemProperties($item, $properties, $hash)
        {
            if ($null -eq $item)
            {
                return
            }

            foreach($property in $properties)
            {
                $propertyHash = $property -as [hashtable]
                if($null -ne $propertyHash)
                {
                    $hashName = $propertyHash["name"] -as [string]         
                    $expression = $propertyHash["expression"] -as [scriptblock]

                    $expressionValue = $expression.Invoke($item)[0]
            
                    $hash[$hashName] = $expressionValue
                }
                else
                {
                    foreach($itemProperty in $item.psobject.Properties)
                    {
                        if ($itemProperty.Name -like $property)
                        {
                            $hash[$itemProperty.Name] = $itemProperty.Value
                        }
                    }
                }
            }
        }

        function TranslateProperties
        {
            [cmdletbinding()]
            param(
                [object[]]$Properties,
                [psobject]$RealObject,
                [string]$Side)

            foreach($Prop in $Properties)
            {
                $propertyHash = $Prop -as [hashtable]
                if($null -ne $propertyHash)
                {
                    $hashName = $propertyHash["name"] -as [string]         
                    $expression = $propertyHash["expression"] -as [scriptblock]

                    $ScriptString = $expression.tostring()
                    if($ScriptString -notmatch 'param\(')
                    {
                        Write-Verbose "Property '$HashName'`: Adding param(`$_) to scriptblock '$ScriptString'"
                        $Expression = [ScriptBlock]::Create("param(`$_)`n $ScriptString")
                    }
                
                    $Output = @{Name =$HashName; Expression = $Expression }
                    Write-Verbose "Found $Side property hash with name $($Output.Name), expression:`n$($Output.Expression | out-string)"
                    $Output
                }
                else
                {
                    foreach($ThisProp in $RealObject.psobject.Properties)
                    {
                        if ($ThisProp.Name -like $Prop)
                        {
                            Write-Verbose "Found $Side property '$($ThisProp.Name)'"
                            $ThisProp.Name
                        }
                    }
                }
            }
        }

        function WriteJoinObjectOutput($leftItem, $rightItem, $leftProperties, $rightProperties)
        {
            $properties = @{}

            AddItemProperties $leftItem $leftProperties $properties
            AddItemProperties $rightItem $rightProperties $properties

            New-Object psobject -Property $properties
        }

        #Translate variations on calculated properties.  Doing this once shouldn't affect perf too much.
        foreach($Prop in @($LeftProperties + $RightProperties))
        {
            if($Prop -as [hashtable])
            {
                foreach($variation in ('n','label','l'))
                {
                    if(-not $Prop.ContainsKey('Name') )
                    {
                        if($Prop.ContainsKey($variation) )
                        {
                            $Prop.Add('Name',$Prop[$Variation])
                        }
                    }
                }
                if(-not $Prop.ContainsKey('Name') -or $Prop['Name'] -like $null )
                {
                    Throw "Property is missing a name`n. This should be in calculated property format, with a Name and an Expression:`n@{Name='Something';Expression={`$_.Something}}`nAffected property:`n$($Prop | out-string)"
                }


                if(-not $Prop.ContainsKey('Expression') )
                {
                    if($Prop.ContainsKey('E') )
                    {
                        $Prop.Add('Expression',$Prop['E'])
                    }
                }
            
                if(-not $Prop.ContainsKey('Expression') -or $Prop['Expression'] -like $null )
                {
                    Throw "Property is missing an expression`n. This should be in calculated property format, with a Name and an Expression:`n@{Name='Something';Expression={`$_.Something}}`nAffected property:`n$($Prop | out-string)"
                }
            }        
        }

        $leftHash = @{}
        $rightHash = @{}

        # Hashtable keys can't be null; we'll use any old object reference as a placeholder if needed.
        $nullKey = New-Object psobject
        
        $bound = $PSBoundParameters.keys -contains "InputObject"
        if(-not $bound)
        {
            [System.Collections.ArrayList]$LeftData = @()
        }
    }
    Process
    {
        #We pull all the data for comparison later, no streaming
        if($bound)
        {
            $LeftData = $Left
        }
        Else
        {
            foreach($Object in $Left)
            {
                [void]$LeftData.add($Object)
            }
        }
    }
    End
    {
        foreach ($item in $Right)
        {
            $key = $item.$RightJoinProperty

            if ($null -eq $key)
            {
                $key = $nullKey
            }

            $bucket = $rightHash[$key]

            if ($null -eq $bucket)
            {
                $bucket = New-Object System.Collections.ArrayList
                $rightHash.Add($key, $bucket)
            }

            $null = $bucket.Add($item)
        }

        foreach ($item in $LeftData)
        {
            $key = $item.$LeftJoinProperty

            if ($null -eq $key)
            {
                $key = $nullKey
            }

            $bucket = $leftHash[$key]

            if ($null -eq $bucket)
            {
                $bucket = New-Object System.Collections.ArrayList
                $leftHash.Add($key, $bucket)
            }

            $null = $bucket.Add($item)
        }

        $LeftProperties = TranslateProperties -Properties $LeftProperties -Side 'Left' -RealObject $LeftData[0]
        $RightProperties = TranslateProperties -Properties $RightProperties -Side 'Right' -RealObject $Right[0]

        #I prefer ordered output. Left properties first.
        [string[]]$AllProps = $LeftProperties

        #Handle prefixes, suffixes, and building AllProps with Name only
        $RightProperties = foreach($RightProp in $RightProperties)
        {
            if(-not ($RightProp -as [Hashtable]))
            {
                Write-Verbose "Transforming property $RightProp to $Prefix$RightProp$Suffix"
                @{
                    Name="$Prefix$RightProp$Suffix"
                    Expression=[scriptblock]::create("param(`$_) `$_.'$RightProp'")
                }
                $AllProps += "$Prefix$RightProp$Suffix"
            }
            else
            {
                Write-Verbose "Skipping transformation of calculated property with name $($RightProp.Name), expression:`n$($RightProp.Expression | out-string)"
                $AllProps += [string]$RightProp["Name"]
                $RightProp
            }
        }

        $AllProps = $AllProps | Select -Unique

        Write-Verbose "Combined set of properties: $($AllProps -join ', ')"

        foreach ( $entry in $leftHash.GetEnumerator() )
        {
            $key = $entry.Key
            $leftBucket = $entry.Value

            $rightBucket = $rightHash[$key]

            if ($null -eq $rightBucket)
            {
                if ($Type -eq 'AllInLeft' -or $Type -eq 'AllInBoth')
                {
                    foreach ($leftItem in $leftBucket)
                    {
                        WriteJoinObjectOutput $leftItem $null $LeftProperties $RightProperties | Select $AllProps
                    }
                }
            }
            else
            {
                foreach ($leftItem in $leftBucket)
                {
                    foreach ($rightItem in $rightBucket)
                    {
                        WriteJoinObjectOutput $leftItem $rightItem $LeftProperties $RightProperties | Select $AllProps
                    }
                }
            }
        }

        if ($Type -eq 'AllInRight' -or $Type -eq 'AllInBoth')
        {
            foreach ($entry in $rightHash.GetEnumerator())
            {
                $key = $entry.Key
                $rightBucket = $entry.Value

                $leftBucket = $leftHash[$key]

                if ($null -eq $leftBucket)
                {
                    foreach ($rightItem in $rightBucket)
                    {
                        WriteJoinObjectOutput $null $rightItem $LeftProperties $RightProperties | Select $AllProps
                    }
                }
            }
        }
    }
}
 
# Start Main Code Here
$ScriptName = $MyInvocation.MyCommand.Name

. Logit "$($myInvocation.MyCommand) - Retrieving physical disks"

. Logit "$($myInvocation.MyCommand) - Model set to $Model"
 
 
    #Note: we need to make sure that SSD is not the first boot device, so we need to evaluate the disk number as well
	$disksorder = Get-Disk | Select-Object Number,FriendlyName
    $physicaldisks = Get-PhysicalDisk | Select-Object FriendlyName,MediaType
    $disks = Join-Object -Left $disksorder -Right $physicaldisks -LeftJoinProperty FriendlyName -RightJoinProperty FriendlyName
	
    . Logit "$($myInvocation.MyCommand) - Processing retrieved physical disks."
	. Logit "$($myInvocation.MyCommand) - " $disks
 $diskcount=$disks.count
 if($diskcount -gt 1){
   foreach($disk in $disks)
   {
      if($disk.MediaType -like "SSD" -and $disk.Number -gt "0") {
       . Logit "$($myInvocation.MyCommand) - SSD drive detected and it is not the first boot device."
       $TSenv.Value("IsNVMe") = "TRUE"
       Exit 0
     }
        if (($disk.MediaType -like "SSD" -and $disk.Number -eq "0") -and ($disk.MediaType -like "SSD" -and $disk.Number -eq "1") ) {
            . Logit "$($myInvocation.MyCommand) - Both drives are detected as SSD. No change required."
            $TSenv.Value("IsNVMe") = "FALSE"
            Exit 0
       
        }
     if($disk.MediaType -like "SSD" -and $disk.Number -eq "0") {
       . Logit "$($myInvocation.MyCommand) - SSD drive detected and it is the first boot device. No change required."
       $TSenv.Value("IsNVMe") = "FALSE"
       Exit 0
     }
        if ($disk.MediaType -like "HDD" -and $disk.Number -eq "0") {
            . Logit "$($myInvocation.MyCommand) - HDD drive detected and it is the first boot device. No change required."
            $TSenv.Value("IsNVMe") = "FALSE"
            Exit 0
        }
    }
        else {
            Logit "$($myInvocation.MyCommand) - NOT SSD. HDD drive detected and it is the first boot device. No change required."
            $TSenv.Value("IsNVMe") = "FALSE"
             Exit 0
   }
  }

else
    {
        . Logit "$($myInvocation.MyCommand) - Disk count is $diskcount, exit" 
          $TSenv.Value("IsNVMe") = "FALSE"
        Exit 0
    }

# SIG # Begin signature block
# MIIhOAYJKoZIhvcNAQcCoIIhKTCCISUCAQExDzANBglghkgBZQMEAgEFADB5Bgor
# BgEEAYI3AgEEoGswaTA0BgorBgEEAYI3AgEeMCYCAwEAAAQQH8w7YFlLCE63JNLG
# KX7zUQIBAAIBAAIBAAIBAAIBADAxMA0GCWCGSAFlAwQCAQUABCCi2y5J9pbUsQRZ
# jfGAnZYTeWhpIfvpZcrgT2P+v9Zxb6CCG8owggQVMIIC/aADAgECAgsEAAAAAAEx
# icZQBDANBgkqhkiG9w0BAQsFADBMMSAwHgYDVQQLExdHbG9iYWxTaWduIFJvb3Qg
# Q0EgLSBSMzETMBEGA1UEChMKR2xvYmFsU2lnbjETMBEGA1UEAxMKR2xvYmFsU2ln
# bjAeFw0xMTA4MDIxMDAwMDBaFw0yOTAzMjkxMDAwMDBaMFsxCzAJBgNVBAYTAkJF
# MRkwFwYDVQQKExBHbG9iYWxTaWduIG52LXNhMTEwLwYDVQQDEyhHbG9iYWxTaWdu
# IFRpbWVzdGFtcGluZyBDQSAtIFNIQTI1NiAtIEcyMIIBIjANBgkqhkiG9w0BAQEF
# AAOCAQ8AMIIBCgKCAQEAqpuOw6sRUSUBtpaU4k/YwQj2RiPZRcWVl1urGr/SbFfJ
# MwYfoA/GPH5TSHq/nYeer+7DjEfhQuzj46FKbAwXxKbBuc1b8R5EiY7+C94hWBPu
# TcjFZwscsrPxNHaRossHbTfFoEcmAhWkkJGpeZ7X61edK3wi2BTX8QceeCI2a3d5
# r6/5f45O4bUIMf3q7UtxYowj8QM5j0R5tnYDV56tLwhG3NKMvPSOdM7IaGlRdhGL
# D10kWxlUPSbMQI2CJxtZIH1Z9pOAjvgqOP1roEBlH1d2zFuOBE8sqNuEUBNPxtyL
# ufjdaUyI65x7MCb8eli7WbwUcpKBV7d2ydiACoBuCQIDAQABo4HoMIHlMA4GA1Ud
# DwEB/wQEAwIBBjASBgNVHRMBAf8ECDAGAQH/AgEAMB0GA1UdDgQWBBSSIadKlV1k
# sJu0HuYAN0fmnUErTDBHBgNVHSAEQDA+MDwGBFUdIAAwNDAyBggrBgEFBQcCARYm
# aHR0cHM6Ly93d3cuZ2xvYmFsc2lnbi5jb20vcmVwb3NpdG9yeS8wNgYDVR0fBC8w
# LTAroCmgJ4YlaHR0cDovL2NybC5nbG9iYWxzaWduLm5ldC9yb290LXIzLmNybDAf
# BgNVHSMEGDAWgBSP8Et/qC5FJK5NUPpjmove4t0bvDANBgkqhkiG9w0BAQsFAAOC
# AQEABFaCSnzQzsm/NmbRvjWek2yX6AbOMRhZ+WxBX4AuwEIluBjH/NSxN8RooM8o
# agN0S2OXhXdhO9cv4/W9M6KSfREfnops7yyw9GKNNnPRFjbxvF7stICYePzSdnno
# 4SGU4B/EouGqZ9uznHPlQCLPOc7b5neVp7uyy/YZhp2fyNSYBbJxb051rvE9ZGo7
# Xk5GpipdCJLxo/MddL9iDSOMXCo4ldLA1c3PiNofKLW6gWlkKrWmotVzr9xG2wSu
# kdduxZi61EfEVnSAR3hYjL7vK/3sbL/RlPe/UOB74JD9IBh4GCJdCC6MHKCX8x2Z
# faOdkdMGRE4EbnocIOM28LZQuTCCBMYwggOuoAMCAQICDCRUuH8eFFOtN/qheDAN
# BgkqhkiG9w0BAQsFADBbMQswCQYDVQQGEwJCRTEZMBcGA1UEChMQR2xvYmFsU2ln
# biBudi1zYTExMC8GA1UEAxMoR2xvYmFsU2lnbiBUaW1lc3RhbXBpbmcgQ0EgLSBT
# SEEyNTYgLSBHMjAeFw0xODAyMTkwMDAwMDBaFw0yOTAzMTgxMDAwMDBaMDsxOTA3
# BgNVBAMMMEdsb2JhbFNpZ24gVFNBIGZvciBNUyBBdXRoZW50aWNvZGUgYWR2YW5j
# ZWQgLSBHMjCCASIwDQYJKoZIhvcNAQEBBQADggEPADCCAQoCggEBANl4YaGWrhL/
# o/8n9kRge2pWLWfjX58xkipI7fkFhA5tTiJWytiZl45pyp97DwjIKito0ShhK5/k
# Ju66uPew7F5qG+JYtbS9HQntzeg91Gb/viIibTYmzxF4l+lVACjD6TdOvRnlF4RI
# shwhrexz0vOop+lf6DXOhROnIpusgun+8V/EElqx9wxA5tKg4E1o0O0MDBAdjwVf
# ZFX5uyhHBgzYBj83wyY2JYx7DyeIXDgxpQH2XmTeg8AUXODn0l7MjeojgBkqs2Iu
# YMeqZ9azQO5Sf1YM79kF15UgXYUVQM9ekZVRnkYaF5G+wcAHdbJL9za6xVRsX4ob
# +w0oYciJ8BUCAwEAAaOCAagwggGkMA4GA1UdDwEB/wQEAwIHgDBMBgNVHSAERTBD
# MEEGCSsGAQQBoDIBHjA0MDIGCCsGAQUFBwIBFiZodHRwczovL3d3dy5nbG9iYWxz
# aWduLmNvbS9yZXBvc2l0b3J5LzAJBgNVHRMEAjAAMBYGA1UdJQEB/wQMMAoGCCsG
# AQUFBwMIMEYGA1UdHwQ/MD0wO6A5oDeGNWh0dHA6Ly9jcmwuZ2xvYmFsc2lnbi5j
# b20vZ3MvZ3N0aW1lc3RhbXBpbmdzaGEyZzIuY3JsMIGYBggrBgEFBQcBAQSBizCB
# iDBIBggrBgEFBQcwAoY8aHR0cDovL3NlY3VyZS5nbG9iYWxzaWduLmNvbS9jYWNl
# cnQvZ3N0aW1lc3RhbXBpbmdzaGEyZzIuY3J0MDwGCCsGAQUFBzABhjBodHRwOi8v
# b2NzcDIuZ2xvYmFsc2lnbi5jb20vZ3N0aW1lc3RhbXBpbmdzaGEyZzIwHQYDVR0O
# BBYEFNSHuI3m5UA8nVoGY8ZFhNnduxzDMB8GA1UdIwQYMBaAFJIhp0qVXWSwm7Qe
# 5gA3R+adQStMMA0GCSqGSIb3DQEBCwUAA4IBAQAkclClDLxACabB9NWCak5BX87H
# iDnT5Hz5Imw4eLj0uvdr4STrnXzNSKyL7LV2TI/cgmkIlue64We28Ka/GAhC4evN
# GVg5pRFhI9YZ1wDpu9L5X0H7BD7+iiBgDNFPI1oZGhjv2Mbe1l9UoXqT4bZ3hcD7
# sUbECa4vU/uVnI4m4krkxOY8Ne+6xtm5xc3NB5tjuz0PYbxVfCMQtYyKo9JoRbFA
# uqDdPBsVQLhJeG/llMBtVks89hIq1IXzSBMF4bswRQpBt3ySbr5OkmCCyltk5lXT
# 0gfenV+boQHtm/DDXbsZ8BgMmqAc6WoICz3pZpendR4PvyjXCSMN4hb6uvM0MIIH
# BTCCBO2gAwIBAgITdQARj/r9m+YrG/+lYgABABGP+jANBgkqhkiG9w0BAQsFADA+
# MRMwEQYKCZImiZPyLGQBGRYDbmV0MRMwEQYKCZImiZPyLGQBGRYDZG9pMRIwEAYD
# VQQDEwlET0lJTUNBMjIwHhcNMTkwNDIyMTYyMDU0WhcNMjAwNDIxMTYyMDU0WjAV
# MRMwEQYDVQQDEwpPdWFSZG9sb3RvMIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIB
# CgKCAQEA2zaZfcz7/YfTTKq0V5MrkgpSKEM4pUAYsXR0Cd/dcYsNX4yBQu+Aivv8
# dR4XWYtp/utZ+u9lb3a/VixEACnNqcNIHWN//FPhs9WIXK6NDSpGs04HiNGTKkMQ
# TUYchTK2W3LJpgmxSoHKHIjZXGUXIv/7VbLT6XvLePA1TTbOeKUOqWRgqLthN2Ay
# PnkXHRgiLzI5VHnk01Pw91m1HLnOaDIGQaCp+I59e6I8RAVJ1ft8taS7zhWJGgPS
# B4rLxNgsH+JCwVBWWwPP5wB0reJ6JZqkUgYKuJzX55GsOoRKjlAmKd9i55fAEIM/
# xcx76nQxYFt7oeBb+V+pUaS0qp0SXQIDAQABo4IDIzCCAx8wPQYJKwYBBAGCNxUH
# BDAwLgYmKwYBBAGCNxUIhd7VSaKCaIephyOH3YdMg7XXKIEggdnJQIH29D8CAWUC
# AQAwEwYDVR0lBAwwCgYIKwYBBQUHAwMwCwYDVR0PBAQDAgeAMBsGCSsGAQQBgjcV
# CgQOMAwwCgYIKwYBBQUHAwMwHQYDVR0OBBYEFPciblQhjXbuqwwptoSE9aJDCLkK
# MB8GA1UdIwQYMBaAFP1tPLfXgB9PLZEPGVOSDZuRBjJrMIH2BgNVHR8Ege4wgesw
# geiggeWggeKGgbFsZGFwOi8vL0NOPURPSUlNQ0EyMixDTj1JSU5SRVNJTUNBMjEs
# Q049Q0RQLENOPVB1YmxpYyUyMEtleSUyMFNlcnZpY2VzLENOPVNlcnZpY2VzLENO
# PUNvbmZpZ3VyYXRpb24sREM9ZG9pLERDPW5ldD9jZXJ0aWZpY2F0ZVJldm9jYXRp
# b25MaXN0P2Jhc2U/b2JqZWN0Q2xhc3M9Y1JMRGlzdHJpYnV0aW9uUG9pbnSGLGh0
# dHA6Ly9JSU5SRVNJTUNBMjEvQ2VydEVucm9sbC9ET0lJTUNBMjIuY3JsMIIBMQYI
# KwYBBQUHAQEEggEjMIIBHzCBpAYIKwYBBQUHMAKGgZdsZGFwOi8vL0NOPURPSUlN
# Q0EyMixDTj1BSUEsQ049UHVibGljJTIwS2V5JTIwU2VydmljZXMsQ049U2Vydmlj
# ZXMsQ049Q29uZmlndXJhdGlvbixEQz1kb2ksREM9bmV0P2NBQ2VydGlmaWNhdGU/
# YmFzZT9vYmplY3RDbGFzcz1jZXJ0aWZpY2F0aW9uQXV0aG9yaXR5MFAGCCsGAQUF
# BzAChkRodHRwOi8vSUlOUkVTSU1DQTIxL0NlcnRFbnJvbGwvSUlOUkVTSU1DQTIx
# LmRvaS5uZXRfRE9JSU1DQTIyKDEpLmNydDAkBggrBgEFBQcwAYYYaHR0cDovL29j
# c3AuZG9pLmdvdi9vY3NwMDEGA1UdEQQqMCigJgYKKwYBBAGCNxQCA6AYDBZPdWFS
# ZG9sb3RvQG5wcy5kb2kubmV0MA0GCSqGSIb3DQEBCwUAA4ICAQC6w2BJZjt42R3g
# QUKSQcs+FIVCbMsFH/1WvB4qDnlXNRngzj6XqjCn2q13Z9l3LfqjJEMiXtB8lLHd
# klr9nFIjbcPlBJ5lZbH2FGmb0ZYjR0OeHTMqgD/OS6EOAzsXX1DdsRkhLI2jy6dH
# rcsNCENGylJdpCxKP/YqCUaJHNggYkQaNTeZQV0fTxJAwtyhPWBqCdB59+S+IVh7
# rYm6mDLlvlUoZ2jcf4BkdiJO8Sr4VhLaaVrwJhSnkWNNHkPGCNbNyP5hPkV9VsRV
# ZT7wj72f1O+GwNGcKNVM7Tumc646ZEwiX3dysOa9c6PtLbN7JOU/kG0CKl+zcG3R
# SKyUvPbt2wJLFg97em0X/VWDsiqXvES3kU+f73S8OZY+/eyG8+9V0U6ns+BK0Yt2
# y314KuIEurFhIs+jQnKlBsvTwMbyEgrdMNQnSGixDtVs+7vS4hiCVBlMehrbunUE
# Joh61x3598SRWjIT7GwRco56j7LAi4Sm7cl7ivmRanBPUe3oVFEEHHSkkp2OGJVF
# hJknSeZ9i8JN05hfDfPt+DSPrqOVK/H250jpU9nlr8X6MiLIiqBPg0NuZjxkfwNE
# FmXENmZaprFex3+zGuf3IMZjadkUOPsHpVlDZXws48Ek4daDYXxLWhPLdsDDvZpe
# i/tWUdl08/AqrIAppflHM/D4WBFIozCCC9owggnCoAMCAQICE0wAAAAFXZZDzCDW
# 4gEAAAAAAAUwDQYJKoZIhvcNAQELBQAwFTETMBEGA1UEAxMKRE9JUm9vdENBMjAe
# Fw0xNjA0MjcyMDI5NTdaFw0yMTA0MjcyMDM5NTdaMD4xEzARBgoJkiaJk/IsZAEZ
# FgNuZXQxEzARBgoJkiaJk/IsZAEZFgNkb2kxEjAQBgNVBAMTCURPSUlNQ0EyMjCC
# AiIwDQYJKoZIhvcNAQEBBQADggIPADCCAgoCggIBAMmUhBEboXkL4IArXj4Ey5f6
# lscn2VLFo0I9HI/3ng+912e+zcspWwZnc+0bmVmdgVHSmhgWIstKCtn+eHp6j7q4
# kV881107FSjHniQ+z3McIUt+88OG7F80MOm9HwSr909IDNupK4tW4qyPWikXsdE4
# MuS07Auh49bGT6WGZjfYbmxMhvR8SmgInwsS4yrWzcbAmsUW3vVrEsOfDO0+SpI8
# lwPXW3LCCn4NME9toZu+vQYD6BwtpFQzMAIoh/w94vHf7sWJwJseUkT3E75FSbU5
# Ev8KUIqslZJ4C4nvTRPJZgo80ylt9v/uzTM/5vP6/94DGvveF66Q43F+0dziqr0W
# cGKCmZdCWMP40LqCeS/7eIsG4TP777RwHME9kCEa8AKX5u4wqYP+8vN/chpcKQEP
# QTu0v6m8Isgnm6tPPZH5vBWgAvV+9YASmV+FyCb1XmjxT0VLBm56KYedmsEPvBwT
# JMUL225D2eV2rPu93uR//vUDJzhSLUnYGzGKL3YTkSyjyxjmZsvbdJ3pDMQuPxWO
# IoD1jX91ZwE3GelmDD81wOmhFAzkjoxTLeipyWnbk/uert8wOl9EkqT8FJBax9Ln
# iohZXhgZI8UToTJ9qSLSzCquUMYv8R9orBSDdxju5YIIR+fWTxZBmPnTofLjNi71
# xesJsTz4kBrk1MYUe/D1AgMBAAGjggb4MIIG9DAQBgkrBgEEAYI3FQEEAwIBATAj
# BgkrBgEEAYI3FQIEFgQUA6XGuQ9Fyl6y3kQG2lr5cI6XtkMwHQYDVR0OBBYEFP1t
# PLfXgB9PLZEPGVOSDZuRBjJrMIIE7QYDVR0gBIIE5DCCBOAwggIPBglghkgBZQMC
# ARMwggIAMDAGCCsGAQUFBwIBFiRodHRwOi8vcGtpMi5kb2kubmV0L2xlZ2FscG9s
# aWN5LmFzcAAwggHKBggrBgEFBQcCAjCCAbweggG4AEMAZQByAHQAaQBmAGkAYwBh
# AHQAZQAgAGkAcwBzAHUAZQBkACAAYgB5ACAAdABoAGUAIABEAGUAcABhAHIAdABt
# AGUAbgB0ACAAbwBmACAAdABoAGUAIABJAG4AdABlAHIAaQBvAHIAIABhAHIAZQAg
# AG8AbgBsAHkAIABmAG8AcgAgAGkAbgB0AGUAcgBuAGEAbAAgAHUAbgBjAGwAYQBz
# AHMAaQBmAGkAZQBkACAAVQBTACAARwBvAHYAZQByAG4AbQBlAG4AdAAgAHUAcwBl
# ACAAYQBsAGwAIABvAHQAaABlAHIAIAB1AHMAZQAgAGkAcwAgAHAAcgBvAGgAaQBi
# AGkAdABlAGQALgAgAFUAbgBhAHUAdABoAG8AcgBpAHoAZQBkACAAdQBzAGUAIABt
# AGEAeQAgAHMAdQBiAGoAZQBjAHQAIAB2AGkAbwBsAGEAdABvAHIAcwAgAHQAbwAg
# AGMAcgBpAG0AaQBuAGEAbAAsACAAYwBpAHYAaQBsACAAYQBuAGQALwBvAHIAIABk
# AGkAcwBjAGkAcABsAGkAbgBhAHIAeQAgAGEAYwB0AGkAbwBuAC4wggLJBgpghkgB
# ZQMCARMBMIICuTA1BggrBgEFBQcCARYpaHR0cDovL3BraTIuZG9pLm5ldC9saW1p
# dGVkdXNlcG9saWN5LmFzcAAwggJ+BggrBgEFBQcCAjCCAnAeggJsAFUAcwBlACAA
# bwBmACAAdABoAGkAcwAgAEMAZQByAHQAaQBmAGkAYwBhAHQAZQAgAGkAcwAgAGwA
# aQBtAGkAdABlAGQAIAB0AG8AIABJAG4AdABlAHIAbgBhAGwAIABHAG8AdgBlAHIA
# bgBtAGUAbgB0ACAAdQBzAGUAIABiAHkAIAAvACAAZgBvAHIAIAB0AGgAZQAgAEQA
# ZQBwAGEAcgB0AG0AZQBuAHQAIABvAGYAIAB0AGgAZQAgAEkAbgB0AGUAcgBpAG8A
# cgAgAG8AbgBsAHkAIQAgAEUAeAB0AGUAcgBuAGEAbAAgAHUAcwBlACAAbwByACAA
# cgBlAGMAZQBpAHAAdAAgAG8AZgAgAHQAaABpAHMAIABDAGUAcgB0AGkAZgBpAGMA
# YQB0AGUAIABzAGgAbwB1AGwAZAAgAG4AbwB0ACAAYgBlACAAdAByAHUAcwB0AGUA
# ZAAuACAAQQBsAGwAIABzAHUAcwBwAGUAYwB0AGUAZAAgAG0AaQBzAHUAcwBlACAA
# bwByACAAYwBvAG0AcAByAG8AbQBpAHMAZQAgAG8AZgAgAHQAaABpAHMAIABjAGUA
# cgB0AGkAZgBpAGMAYQB0AGUAIABzAGgAbwB1AGwAZAAgAGIAZQAgAHIAZQBwAG8A
# cgB0AGUAZAAgAGkAbQBtAGUAZABpAGEAdABlAGwAeQAgAHQAbwAgAGEAIABEAGUA
# cABhAHIAdABtAGUAbgB0ACAAbwBmACAAdABoAGUAIABJAG4AdABlAHIAaQBvAHIA
# IABTAGUAYwB1AHIAaQB0AHkAIABPAGYAZgBpAGMAZQByAC4wGQYJKwYBBAGCNxQC
# BAweCgBTAHUAYgBDAEEwCwYDVR0PBAQDAgGGMA8GA1UdEwEB/wQFMAMBAf8wHwYD
# VR0jBBgwFoAUv4YryvNsbT5fHDtOTtiN52rHak8wgfgGA1UdHwSB8DCB7TCB6qCB
# 56CB5IaBsmxkYXA6Ly8vQ049RE9JUm9vdENBMixDTj1JSU5ERU5PUkNBMDEsQ049
# Q0RQLENOPVB1YmxpYyUyMEtleSUyMFNlcnZpY2VzLENOPVNlcnZpY2VzLENOPUNv
# bmZpZ3VyYXRpb24sREM9ZG9pLERDPW5ldD9jZXJ0aWZpY2F0ZVJldm9jYXRpb25M
# aXN0P2Jhc2U/b2JqZWN0Q2xhc3M9Y1JMRGlzdHJpYnV0aW9uUG9pbnSGLWh0dHA6
# Ly9wa2kyLmRvaS5uZXQvQ2VydEVucm9sbC9ET0lSb290Q0EyLmNybDBWBggrBgEF
# BQcBAQRKMEgwRgYIKwYBBQUHMAKGOmh0dHA6Ly9wa2kyLmRvaS5uZXQvQ2VydEVu
# cm9sbC9JSU5ERU5PUkNBMDFfRE9JUm9vdENBMi5jcnQwDQYJKoZIhvcNAQELBQAD
# ggIBANQvEM/T3MqQZ8oWYYEsVcLHX33iMHdGxT7rMkIKG8OVrHX/flXkgNynpLzT
# YI7bL9b7vyVDQKFkc7EpqT75bFnlqjtoHd9Cdjd+TLRrsEn3JRpq0Bi5mJrzoOK2
# 826yEJviqd336ARu1uj3JIHh80aGIYxTgbeDY2tOGn2x2/tcTNHrPR2akBjWbjyc
# UuqEFz0bK8AS1AP1SK2zJiRbpvW0duSt2PbubzxARLMxuY0uF1MAo3/xYVai1I9a
# SqBdmOMQyELDz0nMDzZEkBDB9xWk+pERkWYIFu04TxLOGlShbtha9E08/5tOm6g0
# HdY7vG6LjC6CNk9OrGvpILsJ0TVORDT2On5Eh5A4I6CRaO9gWBvIHFKotI2J+o34
# idRD5KC3wd+wCQVbd772jKYtOPhfxNKgKywgPcRDzjEud3zLcaqYCFnpKQo68OCS
# vTXO64UCDrJtmZr0dnCwiGGXuSAqri2Wjp/Ljjc0W6qOuAVtTrDLoAphWI2m8Kux
# CUyzwsV55ixjlApjnNMDr7QmA9eKcOSpWM9OwEI+cd4zzGcVBP96CJXsaw4vB2ue
# hl1UCxgwNhUfZhTWgfjlspClDK5TUvd+XcwLAEkZ0YlFLWGGHZuJsg+TzIQZz4g7
# 50+q/dOchxXUXP4+aLdqU0zMvaQjvFQK1bM2YboaJ/LwhGQUMYIExDCCBMACAQEw
# VTA+MRMwEQYKCZImiZPyLGQBGRYDbmV0MRMwEQYKCZImiZPyLGQBGRYDZG9pMRIw
# EAYDVQQDEwlET0lJTUNBMjICE3UAEY/6/ZvmKxv/pWIAAQARj/owDQYJYIZIAWUD
# BAIBBQCggYQwGAYKKwYBBAGCNwIBDDEKMAigAoAAoQKAADAZBgkqhkiG9w0BCQMx
# DAYKKwYBBAGCNwIBBDAcBgorBgEEAYI3AgELMQ4wDAYKKwYBBAGCNwIBFTAvBgkq
# hkiG9w0BCQQxIgQgzeMSgrxD4hJFHDflcEbwPI2yAYNCWT7wtWRm9ILOq7AwDQYJ
# KoZIhvcNAQEBBQAEggEAC4h1teKKZslH2rO98i7Z3YUrOhXf7WKymERsb4toGTFU
# LPc419w53odJPG/XCdJGDTrfu5s9nM7qjauM6l0yBxitw6XsBa/4ytJUAfDyBcEM
# ytQkgYy/96Q4iDFZv1PnKHmCTtPgpScwZdMw0NAtzLaYAqg/KAwQ/5jlJYCGaNkb
# pCW0U5R8+DMm/u9/0U8kf5pS903t0IOd6hEbF73uPbQ58f5k5/F2M4N/1IDU/GHa
# Gmyrl/PvOiqoClvSWVPpIK1F4pwYvj2Dzqi+Ve6HXV/ZHA6c7kl4raYVeLZvrzXO
# isyfgo+KLxb7nYGWYqgfhj8CvIgmZu1HvhlVSzJl+qGCArkwggK1BgkqhkiG9w0B
# CQYxggKmMIICogIBATBrMFsxCzAJBgNVBAYTAkJFMRkwFwYDVQQKExBHbG9iYWxT
# aWduIG52LXNhMTEwLwYDVQQDEyhHbG9iYWxTaWduIFRpbWVzdGFtcGluZyBDQSAt
# IFNIQTI1NiAtIEcyAgwkVLh/HhRTrTf6oXgwDQYJYIZIAWUDBAIBBQCgggEMMBgG
# CSqGSIb3DQEJAzELBgkqhkiG9w0BBwEwHAYJKoZIhvcNAQkFMQ8XDTE5MDUwMzE5
# MDg0OVowLwYJKoZIhvcNAQkEMSIEIB1uUfNs1869gCkMpUFEEc86/v8lp5fiWOTl
# 7LJkMhduMIGgBgsqhkiG9w0BCRACDDGBkDCBjTCBijCBhwQUPsdm1dTUcuIbHyFD
# Uhwxt5DZS2gwbzBfpF0wWzELMAkGA1UEBhMCQkUxGTAXBgNVBAoTEEdsb2JhbFNp
# Z24gbnYtc2ExMTAvBgNVBAMTKEdsb2JhbFNpZ24gVGltZXN0YW1waW5nIENBIC0g
# U0hBMjU2IC0gRzICDCRUuH8eFFOtN/qheDANBgkqhkiG9w0BAQEFAASCAQBvr+vy
# QiqJIjughhLaMCEQGC7ExlakqgN6pA1bwZZMsAL0sGDdeZsRT3cXMc88YxVrvtVU
# REvG/IEhrhOb5TM58XJ2kqXZO0yo4JnWyGuYA3M/Ak0GNhiV/NZT71btU8TPMBln
# MKSXSuyJDG3sCaRw83NjXuCJ9wpS3CTrB0ed75eoP7xdUqpnR0FLs8+Ehj/YPY4i
# BZ2v31CqCXRLRQX13PaZUO2RM0nkiPSuRq2+ZfhPHkIS6MuiF/fhkgKjIlvZNCbA
# zOzRZInVlfvHNud4qsAg9cdxz5mOIdi03RCYmvTV4048EvKJMqtbWKt38D7WrX/H
# xdCA2mvSZYI3pqjZ
# SIG # End signature block
