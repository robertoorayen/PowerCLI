<#
.Synopsis
   Descripción corta
.DESCRIPTION
   Descripción larga
.EXAMPLE
   Ejemplo de cómo usar este cmdlet
.EXAMPLE
   Otro ejemplo de cómo usar este cmdlet
.INPUTS
   Entradas a este cmdlet (si hay)
.OUTPUTS
   Salidas de este cmdlet (si hay)
.NOTES
   Notas generales
.COMPONENT
   El componente al que pertenece este cmdlet
.ROLE
   El rol al que pertenece este cmdlet
.FUNCTIONALITY
   La funcionalidad que mejor describe a este cmdlet
#>

    [CmdletBinding(DefaultParameterSetName='Parameter Set 1', 
                  SupportsShouldProcess=$true, 
                  PositionalBinding=$false,
                  HelpUri = 'http://www.microsoft.com/',
                  ConfirmImpact='Medium')]
    [Alias()]
    [OutputType([String])]
    Param
    (

        # Descripción de ayuda de Parám3
        [Parameter(Mandatory=$true)]
        [String]
        $FileConfiguration
    )

    Begin
    {
##TODO Gestión de errores

        ##Add VMware PSSnapin/module
        ###Get PowerCli PSSnapin
        $powercli = Get-PSSnapin -Name VMware.VimAutomation.Core -Registered

        ###Check PowerCli version
        ####PowerCLI
        if ($powercli){
            ####Version 6 -> Module
            if ($powercli.Version.Major -eq 6) {
                ###Import Module
                Import-Module -Name VMware.VimAutomation.Core -ErrorAction Stop
                Write-Verbose "[$(Get-Date -format "yyyy/MM/dd - HH:mm:ss")] - Powercli 6 Module imported"
                
            }
            ####Version 5 -> PSSnapin
            elseif ($powercli.Version.Major -eq 5) {
                ###Add PSSnapin
                Add-PSSnapin -Name VMware.VimAutomation.Core -ErrorAction Stop
                Write-Verbose "[$(Get-Date -format "yyyy/MM/dd - HH:mm:ss")] - Powercli 5 PSSnapin added"
            }
            else {
                Write-Error "This script requires PowerCLI version 5 or later"
                return
            }
            
        }
        ####No PowerCli
        else {
            Write-Error "This script requires PowerCLI version 5 or later"
            return
        }


        ##Ignore SSL Warning
        Set-PowerCLIConfiguration -InvalidCertificateAction Ignore -DisplayDeprecationWarnings:$false -Scope User -Confirm:$false | Out-Null
        Write-Verbose "[$(Get-Date -format "yyyy/MM/dd - HH:mm:ss")] - Set PowerCLI Configuration"

        ##Read JSON configuration file
        $ConfigurationSettings = Get-Content $FileConfiguration | ConvertFrom-JSON

        ###vCenters
        $vCenters = $ConfigurationSettings.vCenters
        ####vCenter Connections
        $vCenter_connections = @()
        foreach ($vCenter in $vCenters) {
            #####vCenter Connection 
            $vcenter_connection += Connect-VIServer -Server $vCenter.vCenter -User $vCenter.Username -Pass $vCenter.Password -Erroraction Stop
            Write-Verbose "[$(Get-Date -format "yyyy/MM/dd - HH:mm:ss")] - Connection to $($vCenter.vCenter)"
        }
 
        ###InfluxDB
        $InfluxDB = $ConfigurationSettings.InfluxDB
        $InfluxDB_url = "http://$($InfluxDB.Hostname):$($InfluxDB.Port)/write?db=$($InfluxDB.Database)&epoch=s"
        $InfluxDB_authheader = "Basic " + ([Convert]::ToBase64String([System.Text.encoding]::ASCII.GetBytes("$InfluxDB.Username`:$InfluxDB.Password")))



    }
    Process
    {
        #Summary
        Write-Verbose "[$(Get-Date -format "yyyy/MM/dd - HH:mm:ss")] - Summary"
        New-Variable -Name InfluxDB_Points -Force
        New-Variable -Name Measurement -Value "VMware_Summary" -Force
        ##Total
        ###Datacenters
        Write-Verbose "[$(Get-Date -format "yyyy/MM/dd - HH:mm:ss")] - Get Datacenters"
        $Datacenters = Get-View -ViewType Datacenter -Property Name 

        foreach ($datacenter in $Datacenters) {
            ####vCenter Hostname
            $vCenter_Hostname = $datacenter.client.ServiceUrl.Split("/")[2]
            ###Clusters
            Write-Verbose "[$(Get-Date -format "yyyy/MM/dd - HH:mm:ss")] - Get Clusters of datacenter $datacenter"
            $Clusters = Get-View -ViewType ClusterComputeResource -SearchRoot $datacenter.MoRef -Property Name,Datastore,Host,Network
            $InfluxDB_Points += "$Measurement,vCenter=$vCenter_Hostname,Datacenter=$($datacenter.Name) Num_clusters=$($Clusters.count) `n"
            

            foreach ($cluster in $Clusters) {
                
                $InfluxDB_Points += "$Measurement,vCenter=$vCenter_Hostname,Datacenter=$($datacenter.Name),Cluster=$($cluster.Name) Num_hosts=$($cluster.Host.count) `n"
                $InfluxDB_Points += "$Measurement,vCenter=$vCenter_Hostname,Datacenter=$($datacenter.Name),Cluster=$($cluster.Name) Num_datastores=$($cluster.Datastore.count) `n"
                $InfluxDB_Points += "$Measurement,vCenter=$vCenter_Hostname,Datacenter=$($datacenter.Name),Cluster=$($cluster.Name) Num_networks=$($cluster.Network.count) `n"
                

                ###Hosts
                Write-Verbose "[$(Get-Date -format "yyyy/MM/dd - HH:mm:ss")] - Get Hosts of cluster $cluster"
                $ESXis = Get-View -ViewType HostSystem -Property Name,Vm,Datastore,Network -SearchRoot $cluster.MoRef
                foreach ($ESXi in $ESXis) {
                    $InfluxDB_Points += "$Measurement,vCenter=$vCenter_Hostname,Datacenter=$($datacenter.Name),Cluster=$($cluster.Name),Host=$($ESXi.Name) Num_vms=$($ESXi.Vm.count) `n"
                    $InfluxDB_Points += "$Measurement,vCenter=$vCenter_Hostname,Datacenter=$($datacenter.Name),Cluster=$($cluster.Name),Host=$($ESXi.Name) Num_datastores=$($ESXi.Datastore.count) `n"
                    $InfluxDB_Points += "$Measurement,vCenter=$vCenter_Hostname,Datacenter=$($datacenter.Name),Cluster=$($cluster.Name),Host=$($ESXi.Name) Num_networks=$($ESXi.Network.count) `n"

                    #TODO Numero de máquinas virtuales
                }
            }
        }


        ###VirtualMachines

        ###Datastores

        #Send Points to InfluxDB
        Write-Verbose "[$(Get-Date -format "yyyy/MM/dd - HH:mm:ss")] - Send Summary Data to InfluxDB"
        $iw = Invoke-WebRequest -Headers @{Authorization=$InfluxDB_authheader} -Uri $InfluxDB_url -Method POST -Body $InfluxDB_Points



        #QuickStats
        ###Datacenters
        Write-Verbose "[$(Get-Date -format "yyyy/MM/dd - HH:mm:ss")] - QuickStats"
        Write-Verbose "[$(Get-Date -format "yyyy/MM/dd - HH:mm:ss")] - Get Datacenters"
        $Datacenters = Get-View -ViewType Datacenter -Property Name
    
        foreach ($datacenter in $Datacenters) {
            ####vCenter Hostname
            $vCenter_Hostname = $datacenter.client.ServiceUrl.Split("/")[2]
            ###Clusters
            Write-Verbose "[$(Get-Date -format "yyyy/MM/dd - HH:mm:ss")] - Get Clusters of datacenter $datacenter"
            $Clusters = Get-View -ViewType ClusterComputeResource -SearchRoot $datacenter.MoRef -Property Summary,Name

            New-Variable -Name InfluxDB_Points_QuickStats_Clusters -Force
            New-Variable -Name Measurement_QuickStats_Clusters -Value "VMware_QuickStats_Clusters" -Force
            New-Variable -Name InfluxDB_Points_QuickStats_Hosts -Force
            New-Variable -Name Measurement_QuickStats_Hosts -Value "VMware_QuickStats_Hosts" -Force
            New-Variable -Name InfluxDB_Points_QuickStats_VirtualMachines -Force
            New-Variable -Name Measurement_QuickStats_VirtualMachines -Value "VMware_QuickStats_VirtualMachines" -Force
            
            foreach ($cluster in $Clusters) {
                
                ####Root ResourcePool
                Write-Verbose "[$(Get-Date -format "yyyy/MM/dd - HH:mm:ss")] - Get Root ResourcePool of cluster $cluster"
                $ResourcePool = Get-View -ViewType ResourcePool -SearchRoot $cluster.MoRef -Property Summary.QuickStats,Runtime -Filter @{"Name" = "Resources"}

                $InfluxDB_Points_QuickStats_Clusters += "$Measurement_QuickStats_Clusters,vCenter=$vCenter_Hostname,Datacenter=$($datacenter.Name),Cluster=$($cluster.Name) OverallCpuUsage=$($ResourcePool.Summary.QuickStats.OverallCpuUsage),OverallCpuDemand=$($ResourcePool.Summary.QuickStats.OverallCpuDemand),GuestMemoryUsage=$($ResourcePool.Summary.QuickStats.GuestMemoryUsage),HostMemoryUsage=$($ResourcePool.Summary.QuickStats.HostMemoryUsage),DistributedCpuEntitlement=$($ResourcePool.Summary.QuickStats.DistributedCpuEntitlement),DistributedMemoryEntitlement=$($ResourcePool.Summary.QuickStats.DistributedMemoryEntitlement),StaticCpuEntitlement=$($ResourcePool.Summary.QuickStats.StaticCpuEntitlement),StaticMemoryEntitlement=$($ResourcePool.Summary.QuickStats.StaticMemoryEntitlement),PrivateMemory=$($ResourcePool.Summary.QuickStats.PrivateMemory),SharedMemory=$($ResourcePool.Summary.QuickStats.SharedMemory),SwappedMemory=$($ResourcePool.Summary.QuickStats.SwappedMemory),BalloonedMemory=$($ResourcePool.Summary.QuickStats.BalloonedMemory),OverheadMemory=$($ResourcePool.Summary.QuickStats.OverheadMemory),ConsumedOverheadMemory=$($ResourcePool.Summary.QuickStats.ConsumedOverheadMemory),CompressedMemory=$($ResourcePool.Summary.QuickStats.CompressedMemory),NumVmotions=$($cluster.Summary.NumVmotions),TotalCpu=$($cluster.Summary.TotalCpu),TotalMemory=$($cluster.Summary.TotalMemory),NumcpuCores=$($cluster.Summary.NumcpuCores),NumCpuThreads=$($cluster.Summary.NumCpuThreads),EffectiveCpu=$($cluster.Summary.EffectiveCpu),EffectiveMemory=$($cluster.Summary.EffectiveMemory),NumHosts=$($cluster.Summary.NumHosts)`n"


                #Hosts
                Write-Verbose "[$(Get-Date -format "yyyy/MM/dd - HH:mm:ss")] - Get Hosts of cluster $cluster"
                $ServidoresESXi = Get-View -ViewType HostSystem -Property Summary.QuickStats,Name,Hardware -SearchRoot $cluster.MoRef
                
                foreach ($ServidorESXi in $ServidoresESXi) {
                    $InfluxDB_Points_QuickStats_Hosts += "$Measurement_QuickStats_Hosts,vCenter=$vCenter_Hostname,Datacenter=$($datacenter.Name),Cluster=$($cluster.Name),Host=$($ServidorESXi.Name) OverallCpuUsage=$($ServidorESXi.Summary.QuickStats.OverallCpuUsage),OverallMemoryUsage=$($ServidorESXi.Summary.QuickStats.OverallMemoryUsage),DistributedCpuFairness=$($ServidorESXi.Summary.QuickStats.DistributedCpuFairness),DistributedmemoryFairness=$($ServidorESXi.Summary.QuickStats.DistributedmemoryFairness),Uptime=$($ServidorESXi.Summary.QuickStats.Uptime)`n"

                    #VirtualMachines
                    Write-Verbose "[$(Get-Date -format "yyyy/MM/dd - HH:mm:ss")] - Get VirtualMachines of host $ServidorESXi"
                    $VirtualMachines = Get-View -ViewType VirtualMachine -Property Summary.QuickStats,Name -SearchRoot $ServidorESXi.MoRef
                    
                    foreach ($VirtualMachine in $VirtualMachines) {

                        #####Remove Blank spaces in VirtualMachine Names
                        $VirtualMachineName = $VirtualMachine.Name.Replace(" ","_")

                        $InfluxDB_Points_QuickStats_VirtualMachines += "$Measurement_QuickStats_VirtualMachines,vCenter=$vCenter_Hostname,Datacenter=$($datacenter.Name),Cluster=$($cluster.Name),Host=$($ServidorESXi.Name),VM=$VirtualMachineName OverallCpuUsage=$($VirtualMachine.Summary.QuickStats.OverallCpuUsage),OverallCpuDemand=$($VirtualMachine.Summary.QuickStats.OverallCpuDemand),GuestMemoryUsage=$($VirtualMachine.Summary.QuickStats.GuestMemoryUsage),HostMemoryUsage=$($VirtualMachine.Summary.QuickStats.HostMemoryUsage),DistributedCpuEntitlement=$($VirtualMachine.Summary.QuickStats.DistributedCpuEntitlement),DistributedMemoryEntitlement=$($VirtualMachine.Summary.QuickStats.DistributedMemoryEntitlement),StaticCpuEntitlement=$($VirtualMachine.Summary.QuickStats.StaticCpuEntitlement),StaticMemoryEntitlement=$($VirtualMachine.Summary.QuickStats.StaticMemoryEntitlement),PrivateMemory=$($VirtualMachine.Summary.QuickStats.PrivateMemory),SharedMemory=$($VirtualMachine.Summary.QuickStats.SharedMemory),SwappedMemory=$($VirtualMachine.Summary.QuickStats.SwappedMemory),BalloonedMemory=$($VirtualMachine.Summary.QuickStats.BalloonedMemory),ConsumedOverheadMemory=$($VirtualMachine.Summary.QuickStats.ConsumedOverheadMemory),FtLogBandwidth=$($VirtualMachine.Summary.QuickStats.FtLogBandwidth),FtSecondaryLatency=$($VirtualMachine.Summary.QuickStats.FtSecondaryLatency),CompressedMemory=$($VirtualMachine.Summary.QuickStats.CompressedMemory),UptimeSeconds=$($VirtualMachine.Summary.QuickStats.UptimeSeconds),SsdSwappedMemory=$($VirtualMachine.Summary.QuickStats.SsdSwappedMemory)`n"
                    }
                }
            }
        }

        #Send Points to InfluxDB
        Write-Verbose "[$(Get-Date -format "yyyy/MM/dd - HH:mm:ss")] - Send QuickStats Data to InfluxDB"
        $iw = Invoke-WebRequest -Headers @{Authorization=$InfluxDB_authheader} -Uri $InfluxDB_url -Method POST -Body $InfluxDB_Points_QuickStats_Clusters
        $iw = Invoke-WebRequest -Headers @{Authorization=$InfluxDB_authheader} -Uri $InfluxDB_url -Method POST -Body $InfluxDB_Points_QuickStats_Hosts
        $iw = Invoke-WebRequest -Headers @{Authorization=$InfluxDB_authheader} -Uri $InfluxDB_url -Method POST -Body $InfluxDB_Points_QuickStats_VirtualMachines


    }
    End
    {
        ####vCenter Discconections
        foreach ($vCenter_connection in $vCenter_connections) {
            Write-Verbose "[$(Get-Date -format "yyyy/MM/dd - HH:mm:ss")] - Disconnect form vCenter"
            Disconnect-ViServer $vCenter_connection -Force -Confirm:$false
        }
    }
