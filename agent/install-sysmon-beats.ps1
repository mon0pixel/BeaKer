<#

.SYNOPSIS
This Powershell script installs and configures Microsoft Sysinternals Sysmon and Elastic Winlogbeat with the aim
of shipping network connection events to a centralized Elasticsearch server.

.DESCRIPTION
This script install Microsoft Sysinternals Sysmon and Elastic Winlogbeat to the Windows Program Files directory.
Sysmon is then configured to report network connections and Winlogbeat is configured to send connection logs to
the desired Elasticsearch server.

.PARAMETER ESHost
The IP address or hostname of the Elasticsearch server to send connection logs. This should not contain a protocol descriptor such as "https://".

.PARAMETER ESPort
The port on which the Elasticsearch server is listening. Defaults to TCP 9200.

.PARAMETER ESUsername
Warning: Insecure!
The username used to authenticate to the Elasticsearch server. If ESUsername is not specified,
the script will ask for the username at runtime. In order to avoid recording the Elasticsearch
username, consider editing this file. Change the line `[string]$ESUsername="",` to
`[string]$ESUsername="YOUR_ELASTIC_USERNAME_HERE",.

.PARAMETER ESPassword
Warning: Insecure!
The password used to authenticate to the Elasticsearch server. If ESPassword is not specified,
the script will ask for the password at runtime. In order to avoid recording the Elasticsearch
password, consider editing this file. Change the line `[string]$ESPassword="",` to
`[string]$ESPassword="YOUR_ELASTIC_PASSWORD_HERE",.

.EXAMPLE
# Asks for Elasticsearch authentication details at runtime
.\install-sysmon-beats.ps1 my-es-host.com 9200

# Reads Elasticsearch authentication details from the command line aguments
.\install-sysmon-beats.ps1 my-es-host.com 9200 elastic elastic_password

.NOTES
The Elasticsearch credentials are stored locally using Elastic Winlogbeat's secure
storage facilities. The ESUsername and ESPassword parameters should not be passed
into the script in a secure environment. Instead, either leave the credentials blank and
enter the credentials during the installation process, or edit the parameters' default values in the script.
#>

param (
    [Parameter(Mandatory=$true)][string]$ESHost,
    [string]$ESPort="9200",
    [string]$ESUsername="",
    [string]$ESPassword=""
)

if (-NOT ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator"))  
{  
    # Use param values instead of $args because $args doesn't appear to get populated if param values are specified
    # Also set the ExecutionPolicy to Bypass otherwise this will likely fail as script
    # execution is disabled by default.
    $arguments = "-ExecutionPolicy", "Bypass", "-File", $myinvocation.mycommand.definition, $ESHost, $ESPort
    if($ESUsername) 
    {
        # Only add this argument if the user provided it, otherwise it will be blank and will cause an error
        $arguments += $ESUsername
    }
    if($ESPassword) 
    {
        # Only add this argument if the user provided it, otherwise it will be blank and will cause an error
        $arguments += $ESPassword
    }

    Start-Process -FilePath powershell -Verb runAs -ArgumentList $arguments
    Break
}

if (-not (Test-Path "$Env:programfiles\Sysmon" -PathType Container)) {
  Invoke-WebRequest -OutFile Sysmon.zip https://download.sysinternals.com/files/Sysmon.zip
  Expand-Archive .\Sysmon.zip
  remove-item .\Sysmon.zip
  new-item -path "$Env:ProgramFiles\Sysmon" -ItemType Directory
  $SysmonFiles = Get-ChildItem .\Sysmon
  foreach ($file in $SysmonFiles){copy-item -path ".\Sysmon\$file" -Destination "$Env:programfiles\Sysmon"}
  remove-item .\Sysmon -Recurse
}

echo @"
<Sysmon schemaversion="4.22">
    <HashAlgorithms>md5,sha256,IMPHASH</HashAlgorithms>
    <EventFiltering>
        <ProcessCreate onmatch="include">
            <!--SYSMON EVENT ID 1 : PROCESS CREATION [ProcessCreate]-->
        </ProcessCreate>

        <FileCreateTime onmatch="include">
            <!--SYSMON EVENT ID 2 : FILE CREATION TIME RETROACTIVELY CHANGED IN THE FILESYSTEM [FileCreateTime]-->
        </FileCreateTime>

        <NetworkConnect onmatch="exclude">
            <!--SYSMON EVENT ID 3 : NETWORK CONNECTION INITIATED [NetworkConnect]-->
        </NetworkConnect>

        <!--SYSMON EVENT ID 4 : RESERVED FOR SYSMON SERVICE STATUS MESSAGES-->

        <ProcessTerminate onmatch="include">
            <!--SYSMON EVENT ID 5 : PROCESS ENDED [ProcessTerminate]-->
        </ProcessTerminate>

        <DriverLoad onmatch="include">
            <!--SYSMON EVENT ID 6 : DRIVER LOADED INTO KERNEL [DriverLoad]-->
        </DriverLoad>

        <ImageLoad onmatch="include">
            <!--SYSMON EVENT ID 7 : DLL (IMAGE) LOADED BY PROCESS [ImageLoad]-->
        </ImageLoad>

        <CreateRemoteThread onmatch="include">
            <!--SYSMON EVENT ID 8 : REMOTE THREAD CREATED [CreateRemoteThread]-->
        </CreateRemoteThread>

        <RawAccessRead onmatch="include">
            <!--SYSMON EVENT ID 9 : RAW DISK ACCESS [RawAccessRead]-->
        </RawAccessRead>

        <ProcessAccess onmatch="include">
            <!--SYSMON EVENT ID 10 : INTER-PROCESS ACCESS [ProcessAccess]-->
        </ProcessAccess>

        <FileCreate onmatch="include">
            <!--SYSMON EVENT ID 11 : FILE CREATED [FileCreate]-->
        </FileCreate>

        <RegistryEvent onmatch="include">
            <!--SYSMON EVENT ID 12 & 13 & 14 : REGISTRY MODIFICATION [RegistryEvent]-->
        </RegistryEvent>

        <FileCreateStreamHash onmatch="include">
            <!--SYSMON EVENT ID 15 : ALTERNATE DATA STREAM CREATED [FileCreateStreamHash]-->
        </FileCreateStreamHash>

        <!--SYSMON EVENT ID 16 : SYSMON CONFIGURATION CHANGE-->

        <PipeEvent onmatch="include">
            <!--SYSMON EVENT ID 17 & 18 : PIPE CREATED / PIPE CONNECTED [PipeEvent]-->
        </PipeEvent>

        <WmiEvent onmatch="include">
            <!--SYSMON EVENT ID 19 & 20 & 21 : WMI EVENT MONITORING [WmiEvent]-->
        </WmiEvent>

        <DnsQuery onmatch="include">
            <!--SYSMON EVENT ID 19 & 20 & 21 : WMI EVENT MONITORING [WmiEvent]-->
        </DnsQuery>

        <!--SYSMON EVENT ID 255 : ERROR-->
    </EventFiltering>
</Sysmon>
"@ > "$Env:programfiles\Sysmon\sysmon-net-only.xml"


& "$Env:programfiles\Sysmon\Sysmon64.exe" -accepteula -i "$Env:programfiles\Sysmon\sysmon-net-only.xml"

if (-not (Test-Path "$Env:programfiles\winlogbeat*" -PathType Container)) {
  Invoke-WebRequest -OutFile WinLogBeat.zip https://artifacts.elastic.co/downloads/beats/winlogbeat/winlogbeat-7.5.2-windows-x86_64.zip
  Expand-Archive .\WinLogBeat.zip
  remove-item .\WinLogBeat.zip
  $winlogbeatName = Get-ChildItem -path .\WinlogBeat | where-object name -like winlogbeat*
  new-item -path "$Env:ProgramFiles\$($winlogbeatName.Name)" -ItemType Directory
  $WinlogBeatFiles = Get-ChildItem ".\WinLogBeat\$winlogbeatName"
  foreach ($file in $WinlogBeatFiles){copy-item -path ".\WinLogBeat\$($winlogbeatName.Name)\$file" -Destination "$Env:ProgramFiles\$($winlogbeatName.Name)" -Recurse}
  remove-item .\WinLogBeat -Recurse
}

cd "$Env:programfiles\winlogbeat*\"
.\winlogbeat.exe --path.data "C:\ProgramData\winlogbeat" keystore create
if($ESUsername) {
  Write-Output "$ESUsername" | .\winlogbeat.exe --path.data "C:\ProgramData\winlogbeat" keystore add ES_USERNAME --stdin
} else {
  .\winlogbeat.exe --path.data "C:\ProgramData\winlogbeat" keystore add ES_USERNAME
}
if($ESPassword) {
  Write-Output "$ESPassword" | .\winlogbeat.exe --path.data "C:\ProgramData\winlogbeat" keystore add ES_PASSWORD --stdin
} else {
  .\winlogbeat.exe --path.data "C:\ProgramData\winlogbeat" keystore add ES_PASSWORD
}

rm .\winlogbeat.yml
echo @"
winlogbeat.event_logs:
  - name: Microsoft-Windows-Sysmon/Operational
    event_id: 3
    processors:
      - script:
          lang: javascript
          id: sysmon
          file: ${path.home}/module/sysmon/config/winlogbeat-sysmon.js

setup.ilm.enabled: false
setup.template.enabled: true
setup.template.name: `"sysmon`"
setup.template.pattern: `"sysmon-*`"

output.elasticsearch:
  hosts:
    - https://${ESHost}:${ESPort}
  index: `"sysmon-%{+YYYY.MM.dd}`"
  username: `"`${ES_USERNAME}`"
  password: `"`${ES_PASSWORD}`"
  ssl:
    enabled: true
    verification_mode: none
"@ > winlogbeat.yml
PowerShell.exe -ExecutionPolicy UnRestricted -File "$Env:ProgramFiles\$($winlogbeatName.Name)\install-service-winlogbeat.ps1"
Start-Service winlogbeat
