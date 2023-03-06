#$cred = Get-Credential

$scriptblock = {

    $ErrorActionPreference = "silentlycontinue"

    function Get-Hostname {
        $hostname = $env:computername
        return $hostname
    }
    function Test-VeritasPath {
        Test-Path -Path "C:\Program Files\VERITAS\"
    }
    function Get-ServerServices {

        [string]$servertypes = ""

        $services = Get-Service

        if ($services | Where-Object { $_.DisplayName -match "SQL Server" }) {
            $servertypes = $servertypes + "MSSQL-"
        }

        if ($services | Where-Object { $_.DisplayName -match "IIS" }) {
            $servertypes = $servertypes + "IIS-"
        }

        if ($services | Where-Object { $_.DisplayName -match "FTP" }) {
            $servertypes = $servertypes + "FTP-"
        }

        $defaultShares = @('ADMIN$', 'C$', 'IPC$')
        if (Get-WmiObject -Class Win32_Share | Where-Object { $_.Type -eq 0 -and $defaultShares -notcontains $_.Name } | Select-Object Name, Path) {
            $servertypes = $servertypes + "File-"
        }

        $printQueues = Get-WmiObject Win32_PrintQueue -ErrorAction SilentlyContinue
        if ($printQueues.Count -gt 0) {
            $servertypes = $servertypes + "Print-"
        }

        if ((Get-Service  | Where-Object { $_.DisplayName -match "MQ" }) -or
    (Get-Process -Name "mqsvc" -ErrorAction SilentlyContinue)) {
            $servertypes = $servertypes + "MSMQ-"
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
        $dnsNames = @()

        # Get all IP addresses assigned to the server
        $ips += (Get-NetIPAddress -AddressFamily IPv4 | Where-Object { $_.InterfaceAlias -notlike "*Loopback*" }) | Select-Object IPAddress -ExpandProperty IPAddress

        # For each IP address, get the corresponding DNS name using nslookup
        foreach ($ip in $ips) {

            [System.Net.Dns]::GetHostEntry($ip).HostName
        }

        return $dnsNames
    }

    function Main {
        Clear-Host
        Write-Output @'

    ╔══╗      ╔═╗           ╔═══╗                ╔═══╗╔╗          ╔╗  
    ║╔╗║      ║╔╝           ║╔═╗║                ║╔═╗║║║          ║║  
    ║╚╝╚╗╔══╗╔╝╚╗╔══╗╔═╗╔══╗║║ ╚╝╔══╗╔╗╔╗╔╗╔╗╔══╗║║ ╚╝║╚═╗╔══╗╔══╗║║╔╗
    ║╔═╗║║╔╗║╚╗╔╝║╔╗║║╔╝║╔╗║║║ ╔╗║╔╗║║╚╝║║╚╝║║══╣║║ ╔╗║╔╗║║╔╗║║╔═╝║╚╝╝
    ║╚═╝║║║═╣ ║║ ║╚╝║║║ ║║═╣║╚═╝║║╚╝║║║║║║║║║╠══║║╚═╝║║║║║║║═╣║╚═╗║╔╗╗
    ╚═══╝╚══╝ ╚╝ ╚══╝╚╝ ╚══╝╚═══╝╚══╝╚╩╩╝╚╩╩╝╚══╝╚═══╝╚╝╚╝╚══╝╚══╝╚╝╚╝
                                                                        
'@ | Out-Null

        $hostname = Get-Hostname
        $publicIP = Get-PublicIpAddress
        $backupIP = Get-BackupIPAddress
        $replicationIP = Get-ReplicationIP
        $dnsName = Get-DNSNames
        $services = Get-ServerServices
        $veritas = Get-DNSNames

        [PSCustomObject]@{
            Hostname             = $hostname
            PublicIPAddress      = $publicIP
            BackupIPAddress      = $backupIP
            ReplicationIPAddress = $replicationIP
            DNSName              = $dnsName
            ServerType           = $services
            VCSVVR               = $veritas -join ', '
        } | Out-Null

        $gold = "{0},{1},{2},{3},{4},{5},{6}" -f $hostname, $publicIP, $backupIP, $replicationIP, $dnsName, $services, $veritas
        return $gold

        Get-DNSNames
        Get-VCSReplication

    }
} #End of scriptblock

$nodes = "localhost"
foreach ($node in $nodes) {
    Write-Host "`n"
    Write-Host "Executing on node $node"
    $gold = Invoke-Command -ComputerName "$node" -scriptblock $scriptblock -Credential $cred
    $gold | add-content -path C:\output.csv
}
Main