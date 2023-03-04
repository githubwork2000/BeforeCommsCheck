$ErrorActionPreference = "silentlycontinue"

Function Get-VCSReplication {
    # Get all the VCS services on the local machine
    $vcs = Get-WmiObject -Namespace Root\Citrix -Class Xen_VCSService
    # Loop through each of the services detected
    foreach ($vc in $vcs) {
        # Get the current state
        $state = $vc.GetState()
        # Check if its running
        if ($state -eq 0) {
            # Display the hostname and active state
            Write-Host "Hostname: $($vc.hostname) - Status: Active"
            # Check if its replicating
        }
        elseif ($state -eq 3) {
            # Display the hostname and Replicating status
            Write-Host "Hostname: $($vc.hostname) - Status: Replicating"
            # If it's neither running nor replicating then display as Not Running
        }
        else {
            Write-Host "Hostname: $($vc.hostname) -Status: Not Running"
        }
    }
}

function Get-ServerServices {

    $services = Get-Service

    if ($services | Where-Object { $_.DisplayName -match "SQL Server" }) {
        Write-Output "MSSQL"
    }

    if ($services | Where-Object { $_.DisplayName -match "IIS" }) {
        Write-Output "IIS"
    }

    if ($services | Where-Object { $_.DisplayName -match "FTP" }) {
        Write-Output "FTP"
    }

    if (Get-WmiObject Win32_Share ) {
        Write-Output "File shares"
    }

    $printQueues = Get-WmiObject Win32_PrintQueue -ErrorAction SilentlyContinue
    if ($printQueues.Count -gt 0) {
        Write-Output "Print queues"
    }

    if ((Get-Service  | Where-Object { $_.DisplayName -match "MQ" }) -or
    (Get-Process -Name "msmqsvc" -ErrorAction SilentlyContinue)) {
        Write-Output "MSMQ"
    }
}

Function Get-PublicIpAddress { 
    $WebClient = New-Object System.Net.WebClient
    $PublicIp = $WebClient.DownloadString("https://api.ipify.org")
    return $PublicIp
}

function Get-BackupIPAddress {
    $backupIP = (Get-WmiObject Win32_NetworkAdapterConfiguration | Where-Object { $_.IPAddress -like "10.*" })[0].IPAddress
    
    if (!$backupIP) {
        Write-Output "No Backup IP Address found."
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
    Write-Error "Could not find the replication IP address."
    return $null
}

function Get-DNSNames {
    $dnsNames = @()

    # Get all IP addresses assigned to the server
    $ips += (Get-NetIPAddress -AddressFamily IPv4 | Where-Object { $_.InterfaceAlias -notlike "*Loopback*" }) | Select IPAddress -ExpandProperty IPAddress

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
                                                                        
'@

    Get-PublicIpAddress
    Get-BackupIPAddress
    Get-ReplicationIP
    Get-DNSNames
    Get-ServerServices
    Get-VCSReplication

}

Main
