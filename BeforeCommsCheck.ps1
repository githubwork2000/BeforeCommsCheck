#$global:cred = Get-Credential

$scriptblock = {

    $ErrorActionPreference = "silentlycontinue"

    function Get-Hostname {
        $hostname = $env:computername
        return $hostname
    }

    #May need to run vxprint afterwards
    function Test-VeritasPath {
        Test-Path -Path "C:\Program Files\VERITAS\"
    }

    function Test-VeritasVxprint {
        if (vxprint) {
            return $true
        }
        else {
            return $false
        }
    }

    function Get-ServerServices {

        [string]$servertypes = ""

        $services = Get-Service

        if ($services | Where-Object { $_.DisplayName -match "SQL Server" -and $_.Status -match "Running"}) {
            $servertypes = $servertypes + "MSSQL-"
        }

        if ($services | Where-Object { $_.DisplayName -match "IIS" -and $_.Status -match "Running"}) {
            $servertypes = $servertypes + "IIS-"
        }

        if ($services | Where-Object { $_.DisplayName -match "FTP" -and $_.Status -match "Running"}) {
            $servertypes = $servertypes + "FTP-"
        }

        $defaultShares = @('ADMIN$', 'C$', 'IPC$')
        if (Get-WmiObject -Class Win32_Share | Where-Object { $_.Type -eq 0 -and $defaultShares -notcontains $_.Name } | Select-Object Name, Path) {
            $servertypes = $servertypes + "CIFS-"
        }

        if (Get-NfsShare) {
        $servertypes = $servertypes + "NFS-"
        }

        $printQueues = Get-WmiObject Win32_PrintQueue -ErrorAction SilentlyContinue
        if ($printQueues.Count -gt 0) {
            $servertypes = $servertypes + "Print-"
        }

        if ((Get-Service  | Where-Object { $_.DisplayName -match "MQ" -and $_.Status -match "Running" }) -or
        (Get-Process -Name "mqsvc" -ErrorAction SilentlyContinue)) {
            $servertypes = $servertypes + "MSMQ-"
        }

        if ($services | Where-Object { $_.Name -match "SMTPSVC" -and $_.Status -match "Running" }) {
            $servertypes = $servertypes + "SMTP-"
        }

        if ($services | Where-Object { $_.Name -eq "OracleServiceORCL" -and $_.Status -match "Running" }) {
            $servertypes = $servertypes + "Oracle-"
        }

        $servertypes = $servertypes.Substring(0, $servertypes.Length - 1)
    
        Return $servertypes
    
    }

    Function Get-PublicIpAddress { 
        $WebClient = New-Object System.Net.WebClient
        $PublicIp = $WebClient.DownloadString("https://api.ipify.org")
        return $PublicIp.IPAddressToString
    }

    function Get-BackupIPAddress {
        $backupIP = (Get-WmiObject Win32_NetworkAdapterConfiguration | Where-Object { $_.IPAddress -like "10.*" })[0].IPAddress
    
        if (!$backupIP) {
            #Write-Output "No Backup IP Address found."
            return $null
        }
    
        return $backupIP
    }

    function Get-ReplicationIP {
        $networkInterfaces = Get-NetIPConfiguration | Where-Object { $_.InterfaceAlias -notlike "*Loopback*" -and $_.InterfaceOperationalStatus -eq "Up" }
  
        # check each active network interface for replicationip
        foreach ($interface in $networkInterfaces) {
            $replicationIPs = Get-NetAdapterRsc | Where-Object { $_.Name -eq $interface.InterfaceAlias } -and Where-Object { $_.AddressState -eq 'Preferred' } | Select-Object -ExpandProperty IPv4Address
            if ($replicationIPs) {
                return $replicationIPs.IPAddressToString
            }
        }

        # if no replicationip found, return null or write error message
        #Write-Error "Could not find the replication IP address."
        return $null
    }

    function Get-DNSNames {
        [string]$finaldns = ""
        [string]$ddd = ""
        #$dnsNames = @()
        $ips += (Get-NetIPAddress -AddressFamily IPv4 | Where-Object { $_.InterfaceAlias -notlike "*Loopback*" }) | Select-Object IPAddress -ExpandProperty IPAddress
        foreach ($ip in $ips) {
            $ddd = [System.Net.Dns]::GetHostEntry($ip).HostName
            #[string]$finaldns += $ddd + ' ' -Join ''
        }
        $finaldns = $ddd | get-unique 
        return $finaldns
    }

    function Get-NetworkAdapterInfo {
        $adapters = Get-NetIPConfiguration | Where-Object { $null -ne $_.IPv4Address -and $_.InterfaceAlias -notlike '*loopback*' -and $_.IPv4Address.IPAddressToString -notmatch '^169\.254\.' }
        $adapterInfo = foreach ($adapter in $adapters) {
          [PSCustomObject]@{
            Name = $adapter.InterfaceAlias
            IPAddress = $adapter | Select-Object IPv4Address -ExpandProperty IPv4Address
          }
        }
        return $adapterInfo
      }


      function Get-NetworkStuff {
        $nics = @()
        $final = ""
                    $nicinfo = @(Get-WmiObject Win32_NetworkAdapter -ErrorAction STOP | Where-Object {$_.PhysicalAdapter -and $_.NetEnabled -eq $true} |
                        Select-Object Name,
                        @{Name='ConnectionName';Expression={$_.NetConnectionID}})
        
                    $nwinfo = Get-WmiObject Win32_NetworkAdapterConfiguration -ErrorAction STOP |
                        Select-Object Description, 
                        #@{Name='IpAddress';Expression={$_.IpAddress -join '; '}}, 
                        @{Name='IpAddress';Expression={$_.IpAddress[0]}}
                        #@{Name='DNSServerSearchOrder';Expression={$_.DNSServerSearchOrder -join '; '}}
        
                    foreach ($nic in $nicinfo)
                    {
                        $nicObject = New-Object PSObject
                        $nicObject | Add-Member NoteProperty -Name "Connection Name" -Value $nic.connectionname
                        $ipaddress = ($nwinfo | Where-Object {$_.Description -eq $nic.Name}).IpAddress
                        $nicObject | Add-Member NoteProperty -Name "IPAddress" -Value $ipaddress
        
                        $nics += $nicObject
                    $final +=  $nic.connectionname + '-' + $ipaddress + ';'
                    
                    }
                    $final = $final.Substring(0, $final.Length - 1)
                    return $final
      }

    function Main {

        $hostname = Get-Hostname
        #$adapters = Get-NetworkAdapterInfo
        #$publicIP = Get-PublicIpAddress
        #$backupIP = Get-BackupIPAddress
        #$replicationIP = Get-ReplicationIP
        $dnsName = Get-DNSNames
        $services = Get-ServerServices
        $veritas = Test-VeritasVxprint
        $network = Get-NetworkStuff
        #$network = $adapters | ForEach-Object { $adapter += "$_ "} 

        #$gold = "{0},{1},{2},{3},{4},{5},{6},{7}" -f $hostname, $publicIP, $backupIP, $replicationIP, $dnsName, $services, $veritas, $network
        $gold = "{0},{1},{2},{3},{4}" -f $hostname, $dnsName, $services, $veritas, $network
        return $gold

    }
    Main
} #End of scriptblock


#$s = New-PSSession localhost -Credential $global:cred
##$j = Invoke-Command -Session $s -ScriptBlock $scriptblock -AsJob
#$j | Wait-Job

#Receive-Job -Id 147

#Get-PSSession | Disconnect-PSSession
#Get-PSSession | Remove-PSSession

$ErrorActionPreference = "silentlycontinue"

function Get-RemoteInformation {
    param (
        [Parameter(Mandatory = $true)]
        [string]$ComputerNameFile
    )
    
    $computernames = Get-Content -Path $ComputerNameFile

    foreach ($computername in $computernames) {
        try {
            $session = New-PSSession -ComputerName $computername
            $result = Invoke-Command -Session $session -ScriptBlock $scriptblock
            $result | Out-File -FilePath $HOME\myresults.txt -Append
            Write-Output $result
        }
        catch {
            $computername | Out-File -FilePath $HOME\noconnection.txt -Append
            Write-Output "Could not connect to $computername"
        }
        finally {
            Remove-PSSession -Session $session -ErrorAction SilentlyContinue
        }
    }
}

Get-RemoteInformation computers.txt