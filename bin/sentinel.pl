#!/usr/bin/perl
################################################################################
# Application to perform network latency and download speed tests              #
# Designed be called from sentinelManager.pl                                   #
# Written by: Owen L Griffith                                                  #
# Date: 2008-06-19                                                             #
################################################################################

use IPC::Open3 ();
use IO::Socket;
use Digest::MD5 qw(md5);
use Time::HiRes qw(gettimeofday tv_interval);

# extract parameters
@params=split(/\,/,$ARGV[0]);

# turn off both LEDs
system("/usr/local/bin/outb 0x278 0");

# turn on the top green LED on the left to indocate that a test is running
system("/usr/local/bin/outb 0x278 2");

# these parameters from supplied by sentinelManager.pl, which in turn reads from the local configuration file
$unitName=getParam("unitName");
$msisdn=getParam("msisdn");
$configMd5Hash=getParam("configMd5Hash");


# these parameters from supplied from by sentinelManager.pl, as read from the call-set configuration file
$localConfigFile=getParam("localConfigFile");
$testName=getParam("testName");
$testMode=getParam("testMode");
$apn=getParam("apn");
$apnUsername=getParam("apnUsername");
$apnPassword=getParam("apnPassword");
$apnAuthenticationMethod=getParam("apnAuthenticationMethod");
$sourceIpRange=getParam("sourceIpRange");
$exitOnDestinationPingFailure=getParam("exitOnDestinationPingFailure");
$url=getParam("url");
$sequenceNumber=getParam("sequenceNumber");
$waitTime=getParam("waitTime");
$smsResultsDestinationNumber=getParam("smsResultsDestinationNumber");
$httpDownloadTimeout=getParam("httpDownloadTimeout");
$buildConnectionMaxTime=getParam("buildConnectionMaxTime");

if ($localConfigFile eq "") { print "Please specify the local configuration file.\n"; exit; }
if ($unitName eq "") { print "Please specify the unitName of the unit e.g. 14th Ave.\n"; exit; }
if ($testName eq "") { $testName="unspecified test name" }
if ($testMode eq "") { print "You have not specified the test mode e.g. 2G or 3G, defaulting to 3G.\n"; $testMode="3G" }
if ($apn eq "") { print "Please specify the APN to use for testing e.g. internet.\n"; exit; }
if ($apnAuthenticationMethod eq "") { print "Please specify the APN authentication method. e.g. none,pap or chap.\n"; exit; }
if ($url eq "") { print "Please specify the URL to use for testing e.g. http://speedtest.techconcepts.co.za/speedtest/random350x350.jpg.\n"; exit; }
if ($waitTime eq "") { print "You have not specified the wait time after the test is complete. Defaulting to 300 seconds.\n"; $waitTime=300; }
if ($buildConnectionMaxTime eq "") { $buildConnectionMaxTime = 20 }
if ($httpDownloadTimeout eq "") { $httpDownloadTimeout = 30 }


@dnsServers = ();
push(@dnsServers, "rb-anycast01.ns.mtnbusiness.co.za");
push(@dnsServers, "rb-anycast02.ns.mtnbusiness.co.za");
push(@dnsServers, "jh-anycast01.ns.mtnbusiness.co.za");
push(@dnsServers, "jh-anycast02.ns.mtnbusiness.co.za");
push(@dnsServers, "tb-anycast01.ns.mtnbusiness.co.za");
push(@dnsServers, "tb-anycast02.ns.mtnbusiness.co.za");
push(@dnsServers, "anycast01.ns.jnb6.za.mtnbusiness.net");
push(@dnsServers, "anycast01.ns.cpt1.za.mtnbusiness.net");

getDateTime();
if ($testName =~ /noCache/)
{
	$addRandomTime="abc".time;
	$url.="?x=$addRandomTime";
}

print "Test started at $hour:$min:$sec\n";
print "Settings from master configuration:\n";
print "Local Configuration File:   $localConfigFile\n";
print "Unit Name:                  $unitName\n";
print "MSISDN:                     $msisdn\n";
print "Configuration MD5 hash:     $configMd5Hash\n";
print "Test name:                  $testName\n";
print "Test mode:                  $testMode\n";
print "APN:                        $apn\n";
print "APN username:               $apnUsername\n";
print "APN password:               $apnPassword\n";
print "APN authentication method:  $apnAuthenticationMethod\n";
print "Build Connection Max Count: $buildConnectionMaxTime\n";
print "Source IP Range:            $sourceIpRange\n";
print "URL:                        $url\n";
print "Download Timeout:           $httpDownloadTimeout\n";
print "Sequence number:            $sequenceNumber\n";
print "Wait time:                  $waitTime\n";
print "SMS results destination:    $smsResultsDestinationNumber\n";


&readLocalConfigFile;

$callSetConfigurationFile=getLocalParam("callSetConfigurationFile");
$ttyName=getLocalParam("ttyName");
$interfaceName=getLocalParam("interfaceName");
$modemNumber=getLocalParam("modemNumber");
$callBackFlagFile=getLocalParam("callBackFlagFile");
$modemResponseTimeout=getLocalParam("modemResponseTimeout");
$callBackWaitTime=getLocalParam("callBackWaitTime");
$apnToUseForCallback=getLocalParam("apnToUseForCallback");
$sentinelResultsHost=getLocalParam("sentinelResultsHost");
$smsServiceCenterNumber=getLocalParam("smsServiceCenterNumber");
$unsentResultsLocation=getLocalParam("unsentResultsLocation");

if ($ttyName eq "") { print "Please specify the tty name e.g. ttyHS1.\n"; exit; }
if ($interfaceName eq "") { print "Please specify the interface name.\n"; exit; }
if ($modemNumber eq "") { print "Please specify the modem number, e.g. 1.\n"; exit; }

print "Settings from local configuration file:\n";
print "Call-set Configuration:     $callSetConfigurationFile\n";
print "TTY name:                   $ttyName\n";
print "Interface name:             $interfaceName\n";
print "Modem number:               $modemNumber\n";
print "Call-back Flag File:        $callBackFlagFile\n";
print "Modem Response Timeout:     $modemResponseTimeout\n";
print "Call-back wait time:        $callBackWaitTime\n";
print "APN To Use For Call-back:   $apnToUseForCallback\n";
print "SENTINEL Results Host:      $sentinelResultsHost\n";
print "SMS Service Center Number:  $smsServiceCenterNumber\n";
print "Unsent Results Location:    $unsentResultsLocation\n";



# determine local IP address
$ipInfo=`ifconfig eth0`;

$ipStartPos=index($ipInfo,"inet addr:")+10;
$ipEndPos=index($ipInfo,"Bcast",$ipStartPos);
$localStaticIp=substr($ipInfo,$ipStartPos,$ipEndPos-$ipStartPos);
$localStaticIp=~s/ //g;

print "\n\nLocal static IP address:$localStaticIp:\n";



# extract hostname from URL for DNS lookup
&extractHostFromURL;


# mount tmpfs on /ram
if (`mount|grep -c /ram` == 0)
{
  print "tmpfs is not mounted. Mounting on /ram...\n";
  system("mount -t tmpfs tmpfs /ram");
  system("mkdir /ram/unsentResults");
}

# mount flash drive on /mnt/flash
if (`mount|grep -c /mnt/flash` == 0)
{
  print "flash drive is not mounted. Mounting on /mnt/flash...\n";
  $flashDriveMountStatus=system("mount /dev/sda1 /mnt/flash");
  print "Flash drive mount status: $flashDriveMountStatus\n";
  if ($flashDriveMountStatus != 0) {sleep 60; system("reboot")}
}


# destroy the existing wireless interface
system("/sbin/ifconfig $interfaceName down");

open(MODEM,"+>/dev/$ttyName") || errorHandler("tty");

# flush modem buffer contents
#sysread(MODEM,$flush,1024);

print "Flushed from modem: $flush\n";


sendToModem("at+creg=2");
readFromModem("OK");
if ($response =~ /OK/)
{
  print "Modem seems to be happy\n";
}
elsif ($response =~ /ERROR/)
{
  writeToLog("Modem error response to AT+CREG=2: $response",401);
  $resetModem;
  exit;
}
elsif ($response =~ /pattern match timed out/i)
{
  writeToLog("Modem read timed out waiting for AT+CREG=2 response",402);
  &resetModem;
  exit;
}
else
{
  writeToLog("Unexpected response to AT+CREG=2",403);
  &resetModem;
  exit;
}

# set modem to the radio technology it's supposed to be on
if ($testMode eq "2G")
{
        sendToModem("at_opsys=0");
        print "Setting modem to 2G only...\n";
}
else
{
        sendToModem("at_opsys=1");
        print "Setting modem to 3G only...\n";
}
readFromModem("OK");

if ($response =~ /OK/)
{
  print "Modem seems to be happy\n";
}
elsif ($response =~ /ERROR/)
{
  writeToLog("Modem error response to AT_OPSYS=(0|1): $response",401);
  $resetModem;
  exit;
}
elsif ($response =~ /pattern match timed out/i)
{
  writeToLog("Modem read timed out waiting for AT_OPSYS response",402);
  &resetModem;
  exit;
}
else
{
  writeToLog("Unexpected response to AT_OPSYS",403);
  &resetModem;
  exit;
}
sleep 10;

# check if the modem is registered on the network
if (checkNetworkRegistration() eq "notAttached")
{ 
  print "Modem is not attached to the GSM network, attempting to reset...\n";
  resetModem();

  open(MODEM,"+>/dev/$ttyName") || errorHandler("tty");

  if (checkNetworkRegistration() eq "notAttached")
  {
    writeToLog("Modem failed to attach to the PLMN after reset",404);
    close MODEM;
    exit;
  }
}


sendToModem("at+creg=0");
readFromModem("OK");
if ($response =~ /OK/)
{
  print "Modem seems to be happy\n";
}
elsif ($response =~ /ERROR/)
{
  writeToLog("Modem error response to AT+CREG=0: $response",405);
  $resetModem;
  exit;
}
elsif ($response =~ /pattern match timed out/i)
{
  writeToLog("Modem read timed out waiting for AT+CREG=0 response",406);
  &resetModem;
  exit;
}
else
{
  writeToLog("Unexpected response to AT+CREG=0",407);
  &resetModem;
  exit;
}


# get mobile network name
$PLMN=getInfoFromModem("at+cops?","COPS:");
($cops1,$cops2,$networkName,$cops4)=split(/:/,$PLMN);
$networkName=~s/"//g;
print "Network Name: $networkName\n";


# check SMS service center address
$smsGT=getInfoFromModem("at+csca?","CSCA:");
($smsGT,$smscDcs)=split(/:/,$smsGT);
$smsGT=~s/"//g;

if ($smsGT eq $smsServiceCenterNumber)
{
  print "SMS service center number is set correctly\n\n";
}
else
{
  sendToModem("at+csca=\"$smsServiceCenterNumber\"");
  readFromModem("OK");
  if ($response =~ /OK/)
  {
    print "SMS service center defined OK\n\n";
  }
  else
  {
    writeToLog("SMS service center definition failed",408);
    &resetModem;
    exit;
  }
}


# check SMS message mode
$smsMode=getInfoFromModem("at+cmgf?","CMGF:");

if ($smsMode eq "1")
{
  print "SMS message mode is correctly set\n\n";
}
else
{
  sendToModem("at+cmgf=1");
  readFromModem("OK");
  if ($response =~ /OK/)
  {
    print "SMS message mode defined OK\n\n";
  }
  else
  {
    writeToLog("SMS message mode definition failed",409);
    &resetModem;
    exit;
  }
}



# check SMS MO message mode to ensure that SMS is sent over packet switched network
$smsMoMode=getInfoFromModem("at+cgsms?","CGSMS:");

if ($smsMoMode eq "2")
{
  print "SMS MO message mode is correctly set\n\n";
}
else
{
  sendToModem("at+cgsms=2");
  readFromModem("OK");
  if ($response =~ /OK/)
  {
    print "SMS MO message mode defined OK\n\n";
  }
  else
  {
    writeToLog("SMS MO message mode definition failed",414);
    &resetModem;
    exit;
  }
}



# check CNMI mode
$cnmiMode=getInfoFromModem("at+cnmi?","CNMI:");

if ($cnmiMode eq "0:0:0:0:0")
{
  print "CNMI mode is correctly set\n\n";
}
else
{
  sendToModem("at+cnmi=0,0,0,0,0");
  readFromModem("OK");
  if ($response =~ /OK/)
  {
    print "CNMI mode defined OK\n\n";
  }
  else
  {
    writeToLog("CNMI mode definition failed",410);
    &resetModem;
    exit;
  }
}


# list and delete SMS messages in the SIM, checking for call back command 
listAndDelete("ALL");



sendToModem("at\+cgdcont=1,\"IP\",\"$apn\"");
readFromModem("OK");
if ($response =~ /OK/)
{
  print "APN defined as $apn\n";
}
else
{
  writeToLog("APN definition failed on local device",411);
  &resetModem;
  exit;
}




if ($apnUsername eq "" and $apnPassword eq "")
{
  print "No username or password was specified\n";
}
else
{
  if ($apnAuthenticationMethod =~ /none/i) { $apnAuth=0 }
  if ($apnAuthenticationMethod =~ /pap/i) { $apnAuth=1 }
  if ($apnAuthenticationMethod =~ /chap/i) { $apnAuth=2 }

  sendToModem("at\$qcpdpp=1,$apnAuth,\"$apnPassword\",\"$apnUsername\"");
  readFromModem("OK");
  if ($response =~ /OK/)
  {
    print "Authentication parameters accepted\n";
  }
  else
  {
    writeToLog("Authentication parameter definition failed on local device",412);
    &resetModem;
    exit;
  }
}




# convert test mode to relevant value for at_opsys=
$opsys=$testMode;
$opsys=~s/2G/0/;
$opsys=~s/3G/3/;


$currentOpsys=getInfoFromModem("at_opsys?","OPSYS:");
($opsysMode,$unsolicited)=split(/:/,$currentOpsys);
print "OPSYS mode: $opsysMode\n";

if ($opsysMode != $opsys)
{
  # set test mode to 2G/3G
  print "Changing network system...\n";
  $opsysResponse=getInfoFromModem("at_opsys=$opsys","OK");
  delay(30);
}
else
{
  print "OPSYS does not have to be changed\n";
}

$signalQuality=getInfoFromModem("at+csq","CSQ:");
($rssi,$ber)=split(/:/,$signalQuality);


# check if the modem is attached to the PS network
if (checkIfPsAttached() eq "notAttached")
{
  if (checkIfPsAttached() eq "notAttached")
  {
    writeToLog("Could not attach to PS network. Resetting modem...",510);
    &resetModem;
    exit;
  }
}



print "Disconnecting previous ps connection, if any...\n";
sendToModem("at_owancall=1,0,1");
readFromModem("OK");




delay(2);

$buildConnectionStartTime=time;

sendToModem("at_owancall=1,1,1");

# wait for the connection to build
readFromModem("_OWANCALL:.*",$buildConnectionMaxTime);

print "response to owancall: $response\n";

if ($response =~ /OWANCALL: 1, 1/)
{
  print "PDP context activation was successful\n";
  $buildConnectionCount=time-$buildConnectionStartTime;
  $pdpUp=1;
}
else
{
  writeToLog("Failed to activate PDP context",512);
  &resetModem;
  &gracefulExit;
}

print "It took $buildConnectionCount seconds to activate the PDP context\n";

if ($buildConnectionCount > 10)
{
  $error="PDP context activation was successful but took too long";
}


# send command to return IP address information
sendToModem("at_owandata=1");
readFromModem("OK");


# at this point we should have an allocated IP address from the GGSN
#$response=~s/\x0a|\x0d//g;
($resp,$allocatedIp,$gatewayIp,$dns1,$dns2,$nbns1,$nbns2,$connectionSpeed)=split(/,/,$response);
$connectionSpeed=~s/\x20|\x0a|\x0d|OK//g;
$allocatedIp=~s/ //g;
$dns1=~s/ //g;
$dns2=~s/ //g;
print "Allocated IP: $allocatedIp\n";
print "Gateway IP: $gatewayIp\n";
print "DNS1: $dns1\n";
print "DNS2: $dns2\n";
print "NBNS1: $nbns1\n";
print "NBNS2: $nbns2\n";


# bring up the new interface
system("ifconfig $interfaceName $allocatedIp");
system("ifconfig");

# check if source IP range was specified, if so, does it match the allocated IP?
if ($sourceIpRange ne "")
{
  $sourceIpRange=~s/\.x//g;

  if ($allocatedIp =~ /^$sourceIpRange/)
  {
    print "Source IP range matches, continuing with internal network test...\n";
  }
  else
  {
    print "Source IP range does not match. This test is not for me. Exiting...\n";
    &gracefulExit;
    exit;
  }
}



if ($hostName =~ /(\d+)(\.\d+){3}/)
{
  print "Host name is an IP address, DNS lookup not required\n";
  $destinationIp=$hostName;
}
else
{
  if ($dns1 eq "0.0.0.0" and $dns2 eq "0.0.0.0")
  {
    writeToLog("No primary or secondary DNS servers have been provided by the GGSN",520);
    &gracefulExit;
    exit;
  }


  if ($dns1 eq "0.0.0.0")
  {
    pingSecondaryDns();    
    $error="No primary DNS server has been provided by the GGSN";
  } 
  else
  {
    # try to ping the primary DNS server
    $dnsUsed=$dns1;

    # add IP route to DNS server
    addRoute($dnsUsed);

    # ping the primary DNS server 
    ($dnsPingPacketsSent,$dnsPingPacketLoss,$dnsPingMinRoundTripTime,$dnsPingAveRoundTripTime,$dnsPingMaxRoundTripTime)=pingTest($dnsUsed);
    print "Packets sent:$dnsPingPacketsSent:\n";
    print "Packet loss:$dnsPingPacketLoss:\n";
    print "Minimum round trip time:$dnsPingMinRoundTripTime:\n";
    print "Average round trip time:$dnsPingAveRoundTripTime:\n";
    print "Maximum round trip time:$dnsPingMaxRoundTripTime:\n";
    
    if ($dnsPingPacketLoss > 50)
    {
      $error="Ping success rate to primary DNS server $dnsUsed is too low. Packet loss: $dnsPingPacketLoss% Using secondary DNS server.";
      pingSecondaryDns();
    }
  }


  &checkNameserverConfiguration;


  # resolve hostname into IP address
  &dnsLookup;

  if ($destinationIp eq "")
  {
    writeToLog("Could not resolve host: $hostName",529);
    &resetModem;
    &gracefulExit;
    exit;
  }

}


# add an entry to the routing table for the new destination
addRoute($destinationIp);


# do some large pings to force switch up to HSDPA if available, to ensure correct cell type identification
system("/bin/ping -s 1024 -c 10 $destinationIp");


$cellType=getInfoFromModem("at_owcti?","OWCTI:");
print "Cell type: $cellType\n";
if ($cellType == 1)
{
  system("/usr/local/bin/outb 0x278 6");
  select(undef,undef,undef,0.5);
  system("/usr/local/bin/outb 0x278 2");
  select(undef,undef,undef,0.5);
  system("/usr/local/bin/outb 0x278 6");
  select(undef,undef,undef,0.5);
  system("/usr/local/bin/outb 0x278 2");
  select(undef,undef,undef,0.5);
  system("/usr/local/bin/outb 0x278 6");
  select(undef,undef,undef,0.5);
  system("/usr/local/bin/outb 0x278 2");
}
if ($cellType =~ /2|3|4/)
{
  system("/usr/local/bin/outb 0x278 6");
  select(undef,undef,undef,0.2);
  system("/usr/local/bin/outb 0x278 2");
  select(undef,undef,undef,0.2);
  system("/usr/local/bin/outb 0x278 6");
  select(undef,undef,undef,0.2);
  system("/usr/local/bin/outb 0x278 2");
  select(undef,undef,undef,0.2);
  system("/usr/local/bin/outb 0x278 6");
  select(undef,undef,undef,0.2);
  system("/usr/local/bin/outb 0x278 2");
  select(undef,undef,undef,0.2);
  system("/usr/local/bin/outb 0x278 6");
  select(undef,undef,undef,0.2);
  system("/usr/local/bin/outb 0x278 2");
}

$cellType=~s/0$/non-3G/;
$cellType=~s/1$/3G/;
$cellType=~s/2$/HSDPA/;
$cellType=~s/3$/HSUPA/;
$cellType=~s/4$/HSDPA+HSUPA/;
print "Cell type: $cellType\n";

if ($cellType =~ /non-3G/)
{
  print "Non WCDMA cell detected...$cellType\n";
  $cellType=getInfoFromModem("at_octi?","OCTI:");
  ($unsolicited,$cellType)=split(/\:/,$cellType);

  if ($cellType == 2)
  {
    system("/usr/local/bin/outb 0x278 6");
    select(undef,undef,undef,0.5);
    system("/usr/local/bin/outb 0x278 2");
  }
  elsif ($cellType == 3)
  {
    system("/usr/local/bin/outb 0x278 6");
    select(undef,undef,undef,0.5);
    system("/usr/local/bin/outb 0x278 2");
    select(undef,undef,undef,0.5);
    system("/usr/local/bin/outb 0x278 6");
    select(undef,undef,undef,0.5);
    system("/usr/local/bin/outb 0x278 2");
  }

  $cellType=~s/1/GSM/;
  $cellType=~s/2/GPRS/;
  $cellType=~s/3/EDGE/;
  print "Cell type: $cellType\n";
}

# ping the destination
$pingingTheDestination=1;
($packetsSent,$packetLoss,$minRoundTripTime,$aveRoundTripTime,$maxRoundTripTime)=pingTest($destinationIp);
print "Packets sent:$packetsSent:\n";
print "Packet loss:$packetsLoss:\n";
print "Minimum round trip time:$minRoundTripTime:\n";
print "Average round trip time:$aveRoundTripTime:\n";
print "Maximum round trip time:$maxRoundTripTime:\n";
  
  
if ($packetLoss > 50)
{
    #writeToLog("Ping success rate to the destination IP $destinationIp is too low. Packet loss: $packetLoss%");
    #&resetModem;
    #&gracefulExit;
    #exit;
    $error="Ping success rate to the destination IP $destinationIp is too low. Packet loss: $packetLoss%";
    if ($testName =~ /Business/) { $error=""; }
}




# perform HTTP download speed test
print "Performing speed test...\n";

# print turn on the bottom right orange LED to indicate that the download test has started
system("/usr/local/bin/outb 0x278 6");

my $rxByteCountBefore=extractDataCounter();
$downloadStartTime=time;


newHttpSpeedTest();


$downloadTime=time-$downloadStartTime;
print "Download time: $downloadTime\n";
my $rxByteCountAfter=extractDataCounter();
print "byte count before speed test: $rxByteCountBefore\n";
print "byte count after speed test:  $rxByteCountAfter\n";
my $rxBytesDifference=$rxByteCountAfter-$rxByteCountBefore;
print "rxBytesDiff: $rxBytesDifference\n";
my $rxBitsDifference=$rxBytesDifference*8;
print "rxBitsDiff: $rxBitsDifference\n";
my $newThroughput=$rxBitsDifference/$downloadTime/1024;
print "New throughput: $newThroughput\n";


# print turn off the bottom right orange LED to indicate that the download test has finished
system("/usr/local/bin/outb 0x278 2");
sleep 1;

if ($error eq "") {$error = "Ok"}
writeToLog($error,200);

gracefulExit();

# end of program











# subs start here

sub gracefulExit
{

  # check for disk stored echo requests and process them
  foreach $echoRequestFile (`ls /sentinel/data/echoRequestQueue/`)
  {
    chomp $echoRequestFile;
    print "Found echo request file: $echoRequestFile\n";

    open(ECHOREQUEST,"/sentinel/data/echoRequestQueue/$echoRequestFile");
    $echoRequestData=<ECHOREQUEST>;
    ($echoRequestText,$echoRequestSender)=split(/,/,$echoRequestData);
    close ECHOREQUEST;

    print "Echo request data: $echoRequestData\n";

    $echoResponseTime=time;

    sendSms("ECHO,$unitName,$echoResponseTime,$cellType,$echoRequestText",$echoRequestSender);
    `rm /sentinel/data/echoRequestQueue/$echoRequestFile`;
  }

  open(CALLBACK,$callBackFlagFile);
  sysread(CALLBACK,$callBackMsisdn,20);
  close CALLBACK;

  if ($callBackMsisdn ne "")
  {
    print "Call-back request is pending.\n";
    if ($apn =~ /$apnToUseForCallback/)
    {
      print "Call back number:$callBackMsisdn\n";
      print "Initiating call back process...\n";
      sendSms("$allocatedIp is the IP of the communication server. You have $callBackWaitTime seconds to connect via $apn APN, starting from $hour:$min.",$callBackMsisdn);
      print "Waiting for remote inbound connection...\n";
   
      # reset flag file
      open(CALLBACK,">$callBackFlagFile");
      print CALLBACK "";
      close CALLBACK;
      delay($callBackWaitTime);
      sendSms("Your call-back session has expired after the configured time of $callBackWaitTime seconds.",$callBackMsisdn);
    }
    else
    {
      print "APN is not suitable for call-back initiation.\n";
    }
  }

  delay("10");

  # bring down wireless interface
  system("ifconfig $interfaceName down");

  if ($pdpUp == 1)
  {
    print "Disconnecting previous ps connection...\n";
    sendToModem("at_owancall=1,0,1");
    readFromModem("OK");
  }
  
  if ($needToUpdateConfig == 1) 
  {
    $numberOfTestsDownloaded=@configArray;
    my $configContainsInternetApn;
    foreach my $configItem (@configArray)
    {
      print "configItem: $configItem\n";
      if ($configItem =~ "apn=\"internet\"") { $configContainsInternetApn = 1 }
    }
    print "Number of tests downloaded from sentinelManager: $numberOfTestsDownloaded\n";;
    if ($numberOfTestsDownloaded != 0 and $configContainsInternetApn == 1)
    {
      print "Updating local configuration...\n";
      open(CONFIG,">$callSetConfigurationFile") || failedToWriteNewConfiguration();
      print CONFIG $configuration;
      close CONFIG;
      print "saving new configuration: $configuration\n";
      delay(10);
    
      # send HUP to parent process (sentinelManager.pl) to restart and therefore re-read the configuration file
      # note that this will cause this process (child) to exit as well.

      #system("ps -ef");

      # this does not work if sentinelManager is run from inittab
      #$parentPID=getppid();

      $parentPID=findPid("sentinelManager.pl");
      print "Sending kill -s HUP $parentPID\n";
      `kill -s HUP $parentPID`;
    }
    else
    {
      print "Not updating configuration. New configuration is empty, or does not contain an internet APN test.\n";
    }
  }


  # wait for preconfigured time before next process can start
  print "Wait $waitTime seconds as per the configuration before next process can start...\n";
  delay($waitTime);

  exit;
}


sub writeToLog
{
  # turn off both LEDs
  system("/usr/local/bin/outb 0x278 0");

  &getDateTime;
  $error .= $errorDns;

  $dataHash{"12-date"}="$year-$mon-$mday";
  $dataHash{"13-time"}="$hour:$min:$sec";
  $dataHash{"14-sequenceNumber"}="$sequenceNumber";
  $dataHash{"15-testName"}="$unitName:$testName-$testMode";
  $dataHash{"16-msisdn"}=$msisdn;
  $dataHash{"17-localStaticIp"}=$localStaticIp;
  $dataHash{"18-networkName"}=$networkName;
  $dataHash{"19-cellId"}=$decimalCellId;
  $dataHash{"20-rssi"}=$rssi;
  $dataHash{"21-ber"}=$ber;
  $dataHash{"22-apn"}=$apn;
  $dataHash{"23-apnAuthenticationMethod"}=$apnAuthenticationMethod;
  $dataHash{"24-allocatedIp"}=$allocatedIp;
  $dataHash{"25-callSetupTime"}=$buildConnectionCount;
  $dataHash{"26-cellType"}=$cellType;
  $dataHash{"27-dnsPrimary"}=$dns1;
  $dataHash{"28-dnsSecondary"}=$dns2;
  $dataHash{"29-dnsUsed"}=$dnsUsed;
  $dataHash{"30-dnsPercentSuccess"}=$digPercentSuccess;
  $dataHash{"31-dnsQueryTime"}=$dnsQueryTime;
  $dataHash{"32-url"}=$url;
  $dataHash{"33-destinationIp"}=$destinationIp;
  $dataHash{"34-packetLoss"}=$packetLoss;
  $dataHash{"35-pingTime"}=$aveRoundTripTime;
  $dataHash{"36-speed"}=$speed;
  $dataHash{"37-downloadSize"}=$sizeSummary;
  $dataHash{"38-downloadType"}=$downloadType;
  $dataHash{"39-error"}=@_[0];
  $dataHash{"40-errorCode"}=@_[1];
  $dataHash{"41-password"}="446225";
  $dataHash{"42-traceroute"}=$tracerouteResults;
  $dataHash{"43-httpLatency"}=$avgHttpLatency;
  $dataHash{"44-allHttpLatencyResults"}=$allHttpLatencies;
  $dataHash{"45-peakDownloadSpeed"}=$peakDlSpeed;
  $dataHash{"45-version"}="2.3";
  if ($speed eq "" && @_[1] eq "200") { $dataHash{"40-errorCode"}=800; $dataHash{"39-error"}="No HTTP throughput - HTTP traffic possibly down?"; }

  dnsServerCheck();
  #if($dataHash{"40-error"} =~/dns/i) { $dataHash{"40-error"} .= " $errorDns."; }
  #$dataHash{"40-error"} .= " $errorDns.";

  foreach $key (sort keys %dataHash)
  {
    print "key: $key value: $dataHash{$key}\n";
    $logData=$logData.$dataHash{$key}.",";
  
    #($keyPosition,$keyName)=split(/-/,$key);
    $httpFormattedResults=$httpFormattedResults."$key=$dataHash{$key}"."&";
  }


  # format get data to be HTTP compliant
  $httpFormattedResults=~s/\x25/\%25/g;   # translate % char
  $httpFormattedResults=~s/\x20/\%20/g;   # translate spaces
  $httpFormattedResults=~s/\+/\%2B/g;     # translate spaces


  # try to send the results via the LAN, if unsuccessful then via wireless, if unsuccessful then via SMS
  print "Sending results to SENTINEL data collection server via the LAN...\n";
  $resultsTransmissionMode="10-resultsTransmissionBearer=LAN";

  if (sendResultsToManagementServer() eq "failed")
  {
    print "The LAN seems to be down. Sending results to SENTINEL data collection server via the wireless interface...\n";
    addRoute($sentinelResultsHost);
    delay(5);
    $resultsTransmissionMode="10-ResultsTransmissionBearer=Wireless";

    # try to send via wireless interface
    if (sendResultsToManagementServer() eq "failed")
    {
       print "The results could not be sent via the wireless interface. Sending results to SENTINEL data collection server via SMS or local queue if SMS fails or is disabled...\n";

      # keep the results as short possible to fit within a 160 char message
      $smsFormattedResults="$year-$mon-$mday,$hour:$min:$sec,$sequenceNumber,$unitName:$testName-$testMode,$apn,@_[0]";
      print "length of results: ",length($smsFormattedResults),"\n";

      # truncate to 160 char
      $smsformattedResults=substr($smsformattedResults,0,160);


      if ($smsResultsDestinationNumber ne "" and $error ne "Ok")
      {
        if (sendSms($smsFormattedResults,$smsResultsDestinationNumber) == 0)
        {
          # write to local queue if SMS cannot be sent
          &writeToLocalQueue;
        }
      }
      else
      {
         # write to local queue because SMS result transmission is disabled or there was no error in the test
         &writeToLocalQueue();
      }
    }
  }
}


sub getDateTime
{
  ($sec,$min,$hour,$mday,$mon,$year) = localtime(time);
  $mon+=1;
  $mon=sprintf("%02d", $mon);
  $mday=sprintf("%02d", $mday);
  $hour=sprintf("%02d", $hour);
  $min=sprintf("%02d", $min);
  $sec=sprintf("%02d", $sec);
  $year+=1900;
}


sub errorHandler
{
  if (@_[0] eq "tty")
  {
    writeToLog("Cannot open /dev/$ttyName $!",400);
    &resetModem;
    exit;
  }
}


sub sendToModem
{
  $sendData="@_"."\x0d\x0a";
  print "Sending: $sendData to modem...\n";
  #print "Unpacked:", unpack('H*',$sendData),"\n";
  syswrite(MODEM,$sendData,length($sendData));
}


sub connectToCommserver
{
  eval
  {
    local $SIG{ALRM} = sub { die "alarm\n"};
    alarm 10;

    my ($host,$port)=split(/ /,"@_");
    print "Connecting to $host:$port...\n";

    my $proto = getprotobyname('tcp');

    my $iaddr = inet_aton($host);
    my $paddr = sockaddr_in($port,$iaddr);

    socket(SOCKET, PF_INET, SOCK_STREAM, $proto) || socketError("Cannot define socket");
    connect(SOCKET, $paddr) || socketError("Cannot connect to socket");

    alarm 0;
  };
  die if $@ && $@ ne "alarm\n";
  if ($@)
  {
    socketError("Connection timed out");
  }

  if ($connectionStatus eq "")
  {
    return("Ok");
  }
  else
  {
    return($connectionStatus);
  }
}


sub socketError
{
  print "Socket error: @_[0]\n";
  $connectionStatus=@_[0];
}


sub readFromModem
{
  $in="";
  #print "Waiting for response...\n";
  eval
  {
    local $SIG{ALRM} = sub { die "alarm\n"};
    if (@_[1] eq "")
    { 
      print "Waiting $modemResponseTimeout seconds for response...\n";
      alarm $modemResponseTimeout;
    }
    else
    {
      print "Waiting @_[1] seconds for response...\n";
      alarm @_[1];
    }
    $response="";
    while ($response !~ /\x0d\x0a@_[0]\x0d\x0a|\x0d\x0a.*ERROR.*\x0d\x0a/)
    {
      sysread(MODEM,$in,10);
      $response=$response.$in;
      #print "readFromModem response: $response\n";
      #print "unpacked: ",unpack('H*',$response),"\n";
    }

    alarm 0;
  };
  die if $@ && $@ ne "alarm\n";
  if ($@)
  {
    $response="pattern match timed out";
  }
  print "Modem response: $response\n";
}


sub pingTest
{
  my @packetArray;
  my $packetsSentField;
  my $packetsSentEndPos;
  my $pingPacketsSent;
  my $packetLossField;
  my $percentPos;
  my $pingPacketLoss;
  my @rttLineArray1;
  my @rttLineArray2;
  my $pingMinRoundTripTime;
  my $pingAveRoundTripTime;
  my $pingMaxRoundTripTime;

  print "Trying to ping @_[0]...\n";
  if ($cellType =~ /HSDPA|HSUPA/ && $pingingTheDestination == 1)
  {
        print "DETECTED HSDPA CELL - STARTING 1K ping!!\n\n\n\n";
        #$newPingPid=IPC::Open3::open3( \*NEWPINGWFH, \*NEWPINGRFH, '', "/bin/ping -s 1024 -c 10 @_[0]" );
        #print "PID IS: $newPingPid\n\n";
        #system("/bin/ping -s 248 -i 0.25 -c 500000 @_[0]");
        system("/bin/ping -s 1024 -c 10 @_[0]");
        print "1K ping finished, now performing actual 32 byte latency test...\n";
        #sleep 4;
  }
  if ($pingingTheDestination != 1)
  {
        $pingPid = IPC::Open3::open3( \*PINGWFH, \*PINGRFH, '', "/bin/ping -s 248 -c 5 @_[0]" );
  }
  else
  {
        $pingPid = IPC::Open3::open3( \*PINGWFH, \*PINGRFH, '', "/bin/ping -s 248 -c 10 @_[0]" );
  }
  $pingingTheDestination=0;
  print "NEW PID IS: $pingPid\n";
  while (<PINGRFH>)
  {
    print $_;

    # extract packets transmitted and packet loss
    if ($_ =~ /packet loss/i)
    {
      @packetArray=split(/,/,$_);

      $packetsSentField=$packetArray[0];
      $packetsSentEndPos=index($packetsSentField,"packets transmit");
      $pingPacketsSent=substr($packetsSentField,0,$packetsSentEndPos-1);
      print "\nPackets Sent:$pingPacketsSent:\n";

      $packetLossField=$packetArray[2];
      if ($packetLossField =~ /packet loss/i)
      {
        $percentPos=index($packetLossField,"%");
        $pingPacketLoss=substr($packetLossField,1,$percentPos-1);
      }
      else {$pingPacketLoss = "-1"}
      print "\nPacket Loss:$pingPacketLoss:\n";
    }

    # extract average round trip time
    if (substr($_,0,3) eq "rtt")
    {
      @rttLineArray1=split(/=/,$_);
      @rttLineArray2=split(/\//,$rttLineArray1[1]);
      $pingMinRoundTripTime=sprintf("%d",$rttLineArray2[0]);
      $pingAveRoundTripTime=sprintf("%d",$rttLineArray2[1]);
      $pingMaxRoundTripTime=sprintf("%d",$rttLineArray2[2]);
    #  print "\nMinimum round trip time:$pingMinRoundTripTime:\n";
    #  print "\nAverage round trip time:$pingAveRoundTripTime:\n";
    #  print "\nMaximum round trip time:$pingMaxRoundTripTime:\n";
    }
  }

  #if ($aveRoundTripTime > 4000)
  #{
  #}

  return($pingPacketsSent,$pingPacketLoss,$pingMinRoundTripTime,$pingAveRoundTripTime,$pingMaxRoundTripTime);
}


sub resetModem
{
  open(RESET,"/tmp/resetCounter.dat");
  sysread(RESET,$resetCounterFromFile,1);
  close RESET;

  $resetCounter=$resetCounterFromFile+1;

  if ($resetCounter >= 3)
  {
    print "Resetting modem...\n";

    if ($pdpUp == 1)
    {
      print "Tearing down PS connection...\n";
      sendToModem("at_owancall=1,0,1");
      readFromModem("OK");
      delay(5);
    }

    print "Taking interface $interfaceName down...\n";
    print `/sbin/ifconfig $interfaceName down`;
    close MODEM;

    delay(5);

    #system("/sbin/ifconfig");

    print "Unloading module hso...\n";
    `/sbin/modprobe -r hso`;

    delay(10);

    if (connectToCommserver("localhost",2011) eq "Ok")
    {
      print "Resetting modem. Sending RESET $modemNumber to localhost:2011\n";
      print SOCKET "RESET $modemNumber\x0d\x0a";
      close SOCKET;
    }
    else
    {
      print "Turning modem power off...\n";
      system("/usr/local/bin/outb 0x278 1");

      delay(10);

      print "Turning modem power on...\n";
      system("/usr/local/bin/outb 0x278 0");
    }

    $pdpUp=0;

    delay(60);

    print "Loading module hso...\n";
    `/sbin/modprobe hso`;

    open(RESET,">/tmp/resetCounter.dat");
    print "Writing 0 to /tmp/resetCounter.dat\n";
    print RESET 0;
    close RESET;
  }
  else
  {
    open(RESET,">/tmp/resetCounter.dat");
    print "Writing $resetCounter to /tmp/resetCounter.dat\n";
    print RESET $resetCounter;
    close RESET;
  }
}


sub delay
{
  if (@_[0] == 1) {$desc = "second"} else {$desc = "seconds"}
  my $count=@_[0];
  print "Waiting for @_[0] $desc\n";
  #sleep @_[0];

#  print "Sleeping for $count seconds\n";
  while ($count != 0)
  {                                                                                                                                                               my $printData=$count."  "."\x0d";
    syswrite(STDOUT,$printData,length($printData));
    sleep 1;
    $count--;
  }
  $printData=$count."   "."\x0d"; 
  syswrite(STDOUT,$printData,length($printData));
  getDateTime();
  print "Timestamp: $hour:$min:$sec\n";
}


sub getInfoFromModem
{
  sendToModem(@_[0]);
  print "looking for response: @_[1]\n";
  readFromModem("OK");

  if ($response =~ /@_[1]/)
  {
    $keyLength=length(@_[1])+1;
    $startPos=index($response,@_[1])+$keyLength;
    $endPos=index($response,"\x0a",$startPos);
    $value=substr($response,$startPos,$endPos-$startPos),
    $value =~ s/\,/\:/g;   # translate comma char to colon char
    $value =~ s/\x0d//g;   # remove linefeeds
  }
  elsif ($response =~ /ERROR/)
  {
    writeToLog("Error response to @_[0]",440);
    &resetModem;
    exit;
  }
  elsif ($response =~ /Read_timeout/)
  {
    writeToLog("Read timeout response to @_[0]",441);
    &resetModem;
    exit;
  }
  else
  {
    writeToLog("Unknown response to @_[0]",442);
    &resetModem;
    exit;
  }
  return($value);
}



sub dnsLookup
{
  while($digCount < 4)
  {
    print "Trying to do a DNS lookup using $dnsUsed...\n";
    $digCount++;
    $digPid = IPC::Open3::open3( \*DIGWFH, \*DIGRFH, '', "dig \@$dnsUsed $hostName" );
    $digResult="";
    $digBuffer="";
    while ($digBuffer=<DIGRFH>)
    {
      $digResult=$digResult.$digBuffer;
    }

    print "Dig result:\n$digResult\n";


    if ($digResult =~ /Got answer:/)
    {
      $digSuccess++;
      print "DNS lookup was successful\n";

      $queryTimeStartPos=index($digResult,"Query time:")+12;
      $queryTimeEndPos=index($digResult,"msec",$queryTimeStartPos)-1;
      $dnsQueryTime=substr($digResult,$queryTimeStartPos,$queryTimeEndPos-$queryTimeStartPos);
      print "DNS query time:$dnsQueryTime:\n";
      &extractIpFromDnsResult;
    }

    print "digCount=$digCount\n";
    print "digSuccess=$digSuccess\n";
    $digPercentSuccess=($digSuccess/$digCount)*100;
    print "digPercentSuccess=$digPercentSuccess\n";

    #$digPercentSuccess = "25";

   # if ($digPercentSuccess <= "50" )
   # {
   #   &resetModem;
   #   exit;
   # }
#
   # if ($dnsQueryTime > "5000" )
   # {
   #   end()
   # }

  }
}

sub dnsServerCheck
{
  local @dnsFails = ();
  foreach $dnsServer(@dnsServers)
  {
    print "Trying to do a DNS lookup using $dnsServer...\n";
    $digPid = IPC::Open3::open3( \*DIGWFH, \*DIGRFH, '', "dig \@$dnsServer $hostName" );
    $digResult="";
    $digBuffer="";
    while ($digBuffer=<DIGRFH>)
    {
      $digResult=$digResult.$digBuffer;
    }
    print "Dig result:\n$digResult\n";
    if ($digResult =~ /Got answer:/)
    {
      $digSuccess++;
      print "DNS lookup was successful\n";
      $queryTimeStartPos=index($digResult,"Query time:")+12;
      $queryTimeEndPos=index($digResult,"msec",$queryTimeStartPos)-1;
      $dnsQueryTime=substr($digResult,$queryTimeStartPos,$queryTimeEndPos-$queryTimeStartPos);
      print "DNS query time:$dnsQueryTime:\n";
      &extractIpFromDnsResult;
    }
    else { push(@dnsFails,$dnsServeri); }
    print "digCount=$digCount\n";
    print "digSuccess=$digSuccess\n";
    $digPercentSuccess=($digSuccess/$digCount)*100;
    print "digPercentSuccess=$digPercentSuccess\n";
  }
  if($#dnsFails > -1) {
    $errorDns = "Dns lookup failed for the following servers: ";
    foreach $item(@dnsFails) { $errorDns .= $item; }
  }
  else { $errorDns = ""; }
}



sub extractIpFromDnsResult
{
      @digResult=split(/\n/,$digResult);

      $arraycount="";
      foreach $line (@digResult)
      {
        if ($line =~ /answer section/i)
        {
          print "Found answer section in array position $arrayCount!\n";
          last;
        }
        $arrayCount++;
      }

      while($splitIpLine[3] ne "A" and $arrayCount < @digResult)
      {
        $arrayCount++;
        $ipLine=$digResult[$arrayCount];
        print "analysing line: $ipLine...\n";
        @splitIpLine=split(" ",$ipLine);
      }

      $destinationIp=$splitIpLine[4];
      print "Extracted destination IP:$destinationIp\n";

}


sub resolvConfError
{
  writeToLog("Cannot update /etc/resolv.conf",628);
  exit;
}


sub checkNameserverConfiguration
{
      print "Checking nameserver configuration...\n";
      $nameserverConfigured=`cat /etc/resolv.conf|grep -v grep|grep -c $dnsUsed`;
      if ($nameserverConfigured == 0)
      {
        print "Updating /etc/resolv.conf with new nameserver address $dnsUsed\n";
        open(NS,">/etc/resolv.conf") || resolvConfError();
        print NS "nameserver $dnsUsed\n";
        close NS;
      }
      else
      {
        print "/etc/resolv.conf contains the correct nameserver.\n";
      }
}


#sub extractHostFromURL
#{
#  $hostStartPos=index($url,"://")+3;
#  $hostEndPos=index($url,"/",$hostStartPos);
#  if ($hostEndPos eq "-1")
#  {
#    $hostEndPos=length($url);
#  }
#  $hostName=substr($url,$hostStartPos,$hostEndPos-$hostStartPos);
#  print "Host name: $hostName\n";
#}
sub extractHostFromURL
{
  if ($url =~ /\@/)
  {
    $hostStartPos=index($url,"@")+1;
  }
  else
  {
    $hostStartPos=index($url,"://")+3;
  }
  $hostEndPos=index($url,"/",$hostStartPos);
  if ($hostEndPos eq "-1")
  {
    $hostEndPos=length($url);
  }
  $hostName=substr($url,$hostStartPos,$hostEndPos-$hostStartPos);
  print "Host name: $hostName\n";
}




sub addRoute
{
  print "Adding a route for @_[0] via dev $interfaceName...\n";
  system("route add -host @_[0] dev $interfaceName");
  system("netstat -nr");
}


sub sendResults
{
  system("netstat -nr");
  print "Opening socket to $sentinelResultsHost...\n";

  
  $resultsSocket=IO::Socket::INET->new(PeerAddr => $sentinelResultsHost,
                                PeerPort => '8080',
                                Timeout  => '5',
                                Proto    => 'tcp')|| return("Cannot connect to SENTINEL results collection server");

  $payload="@_[0]&@_[1]&@_[2]";

  $contentLength=length($payload);

  $data="POST /cgi-bin/sentinelResultsProxy.pl HTTP/1.1\r\n".
        "Host: $sentinelResultsHost\r\n".
        "Accept: */*\r\n".
        "Accept-language: en\r\n".
        "Content-Length: $contentLength\r\n".
        "Content-Type: application/x-www-form-urlencoded\r\n\r\n".
        $payload;

  print "Sending: $data to SENTINEL results server\n";

  $resultsSocket->print($data);


  eval
    {
      local $SIG{ALRM} = sub { die "alarm\n"};
      alarm 30;
  
      #$resultsSocket->recv($response, 4096);

      $receiveBuffer=();
      while ($receiveBuffer !~ /ACCEPTED/)
      {
        $resultsSocket->recv($response, 1);
        $receiveBuffer=$receiveBuffer.$response;
      }

      alarm 0;
  
    };
    die if $@ && $@ ne "alarm\n";
    if ($@)
    {
       return("Read timed out to SENTINEL results server");
    }
  
  
  $resultsSocket->close;

  return($receiveBuffer);
}



sub sendSms
{
  print "Attempting to send SMS...\n";
  sendToModem("at");
  readFromModem("OK");
  print "Modem response to \"at\"\n";

  if ($response =~ /OK/)
  {
    sendToModem("at+cmgs=\"@_[1]\"");
    sleep 1;
    sendToModem("@_[0]\x1a");
    readFromModem("OK",20);

    print "Send SMS response: $response\n";
  }
  else
  {
    writeSmsLog("SMS initialise failed. Response: $response");
    return(3);
  }
  
  if ($response =~ /\+CMGS:/)
  {
    print "Message sent\n";
    writeSmsLog("Sent: @_[0]");
    return(1);
  }
  else
  {
    print "Message not sent\n";
    writeSmsLog("Not sent: @_[0]");
    return(0);
  }
}



sub listAndDelete
{
  $echoRequestCount=0;
  sendToModem("at+cmgl=\"@_[0]\"");
  readFromModem("OK",60);


  if ($response =~ /CMGL:/)
  {
    print "Valid CMGL response received\n";
  }
  elsif ($response =~ /pattern match timed out/)
  {
    print "Read timed out waiting for CMGL response!\n";
    return;
  }
  elsif ($response =~ /ERROR/i)
  {
    print "ERROR response to CMGL received\n";
    return;
  }
  else
  {
    print "Unexpected response to CMGL\n";
    return;
  }

  @messageList=split(/\+CMGL: /,$response);
  $numberOfMessages=@messageList-1;

  if ($numberOfMessages == 1) 
  {
    print "\n\nThere is 1 message in the SIM\n\n";
  }
  else
  {
    print "\n\nThere are $numberOfMessages messages in the SIM\n\n";
  }

  foreach $message (@messageList)
  {
    next if ($message =~ /at\+cmgl/);
    @messageArray=split(/\x0d\x0a/,$message);

    print "header:$messageArray[0]:\n";
    ($messagePosition,$messageStatus,$messageSender,$blah,$messageSentDate,$messageSentTime)=split(/,/,$messageArray[0]);
    $messageSender=~s/"//g;
    print "messagePosition:$messagePosition\n";
    print "messageStatus:$messageStatus\n";
    print "messageSender:$messageSender\n";
    print "messageSentDate:$messageSentDate\n";
    print "messageSentTime:$messageSentTime\n";

    if ($messageArray[1] eq "")
    {
       print "The first character of the text message was a CR\n";
       $text = $messageArray[2]
    }
    else
    {
       $text = $messageArray[1]
    }

    print "Text:$text:\n";



    print "\n\n";

    print "Deleting message number $messagePosition...\n";
    sendToModem("at\+cmgd=$messagePosition");
    readFromModem("OK");
    print "response: $response\n";


    if ($text eq "73684635")
    {
      print "A call-back has been requested!\n";
      open(CALLBACK,">$callBackFlagFile");
      print CALLBACK "$messageSender";
      close CALLBACK;
      delay(2);
    }

    if ($text =~ /73684635 delete debug logs/i)
    {
      print "Instruction sentinelManager.pl to delete debug logs...\n";
      $parentPID=findPid("sentinelManager.pl");
      print "Sending kill -s USR2 $parentPID\n";
      `kill -s USR2 $parentPID`;
      sendSms("sentinelManager.pl has been requested to delete debug files.",$messageSender);
    }

    if ($text =~ /73684635 df/i)
    {
      @df=`df -k`;

      $textToSend=();
      foreach $line (@df)
      {
        $dfLineCount++;
        next if $dfLineCount == 1;
        ($filesystem,$blocks,$used,$available,$percentUsed,$mountedOn)=split(" ",$line);
        $textToSend=$textToSend."$percentUsed $mountedOn\n";
      }

      sendSms($textToSend,$messageSender);
    }

    if ($text =~ /73684635 reboot/i)
    {
      print "Rebooting using default config...\n";
      sleep 5;
      $parentPID=findPid("sentinelManager.pl");
      print "Sending kill -s USR1 $parentPID\n";
      `kill -s USR1 $parentPID`;

      sendSms("Rebooting...",$messageSender);
      sleep 5;
      system("shutdown -r now");
    }

   
    if ($text =~ /73684635 E/)
    {
      print "Received echo request...\n";
      $echoRequestCount++;
      getDateTime();

      @echoRequests=`ls /sentinel/data/echoRequestQueue`;
      $numberOfEchoRequests=@echoRequests;
      print "numberOfEchoRequests: $numberOfEchoRequests\n";
      if ($numberOfEchoRequests < 100)
      {
        print "Adding ECHO request $text from $messageSender to the disk queue. Filename: $year$mon$$mday$hour$min$sec$echoRequestCount\n";
        open(ECHO,">/sentinel/data/echoRequestQueue/$year$mon$$mday$hour$min$sec$echoRequestCount");
        print ECHO "$text,$messageSender";;
        close ECHO;
      }
      else
      {
        print "ECHO request queue is too long, not adding\n";
      }
      writeSmsLog("received: $text");
    }


  }

}


sub generateMd5Hash
{
  my $md5Hash = md5 @_[0];
  return(unpack('H*',$md5Hash));
}



sub parseXML
{
  my $key=@_[0];
  my $buf=@_[1];

  #print "parsing $key from buffer: $buf:\n\n";
  my $keyLength=length($key)+2;
  my $startPos=index($buf,"<$key>");
  if ( $startPos != -1 )
  {
    my $endPos=index($buf,"</$key>")-1;
    my $value=substr($buf,$startPos+$keyLength,$endPos-$startPos-$keyLength+1);
    #print "parsed value: $value:\n";
    return($value);
  }
  else
  {
    return("-1");
  }
}


sub failedToWriteNewConfiguration
{
  writeToLog("Cannot open $callSetConfigurationFile to write new configuration data. $!",630);
  exit;
}


sub findPid
{
  @processInfo=`ps -ef`;
  foreach $process (@processInfo)
  {
    chomp $process;
    next if $process =~ /vi /;

    if ($process =~ /@_[0]/)
    {
      #print "process: $process\n";
      ($user,$processId,$parentProcessId,$cpu,$stime,$tty,$time,$cmd1,$cmd2)=split(" ",$process);
      #print "pid is $processId cmd is $cmd\n";
    }
  }

  return($processId);
}


sub pingSecondaryDns
{
    # try to ping the secondary DNS server
    $dnsUsed=$dns2;
    # add IP route to DNS server
    addRoute($dnsUsed);

    # ping the DNS server first
    ($dnsPingPacketsSent,$dnsPingPacketLoss,$dnsPingMinRoundTripTime,$dnsPingAveRoundTripTime,$dnsPingMaxRoundTripTime)=pingTest($dnsUsed);
    print "Packets sent:$dnsPingPacketsSent:\n";
    print "Packet loss:$dnsPingPacketLoss:\n";
    print "Minimum round trip time:$dnsPingMinRoundTripTime:\n";
    print "Average round trip time:$dnsPingAveRoundTripTime:\n";
    print "Maximum round trip time:$dnsPingMaxRoundTripTime:\n";

    if ($dnsPingPacketLoss > 50)
    {
      $error="Ping success rate to primary DNS server $dnsUsed is too low. Packet loss: $dnsPingPacketLoss%";

      writeToLog("Ping success rate to secondary DNS server $dnsUsed is too low. Packet loss: $dnsPingPacketLoss%",521);
      print "Resetting modem...\n";
      &resetModem;
      &gracefulExit;
      exit;
    }
    return("ok");
}


sub getParam
{
  foreach $parameter (@params)
  {
    ($paramName,$paramVal)=split(/\=/,$parameter);
    if ($paramName eq @_[0])
    {
      #print "paramName: $paramName paramVal:$paramVal\n"; 
      return($paramVal);
    }
  }
}


sub checkNetworkRegistration
{
  sendToModem("at+creg?");
  readFromModem("OK","25");
  
  #$response="CREG: 2,0";
  
  if ($response =~ /CREG: 2,1.*\x0a/)
  {
    print "Modem is registered on the GSM network.\n";
    ($regMode,$regStat,$lac,$cellId)=split(/,/,$&);
    $cellId=~s/"//g;
    print "cellid: $cellId\n";
    $decimalCellId=hex($cellId);
    print "decimal cellid:$decimalCellId:\n";
  }
  elsif ($response =~ /ERROR/)
  {
    writeToLog("Modem error response to AT+CREG query: $response",420);
    $resetModem;
    exit;
  }
  elsif ($response =~ /CREG: 2,0/ or $response =~ /CREG: 2,2/)
  {
    return("notAttached");
  }
  elsif ($response =~ /pattern match timed out/i)
  {
    writeToLog("Modem read timed out waiting for AT+CREG query.",421);
    &resetModem;
    exit;
  }
}


sub checkIfPsAttached
{
  sendToModem("at\+cgatt?");
  readFromModem("OK");
  #$response="CGATT: 0";
  
  if ($response =~ /CGATT: 1/)
  {
    print "Modem is attached to PS network.\n";
  }
  elsif ($response =~ /CGATT: 0/)
  {
    print "Modem is not attached to PS network. Attempting to attach...\n";
    sendToModem("at\+cgatt=0");
    readFromModem("OK");
  
    if ($response =~ /pattern match timed out/i)
    {
      writeToLog("Modem read timed out waiting for AT+CGATT=0 response",425);
      &resetModem;
      exit;
    }
    delay(10);
    sendToModem("at\+cgatt=1");
    readFromModem("OK",120);
    print "response=$response\n";

    if ($response =~ /pattern match timed out/i)
    {
      writeToLog("Timed out waiting for modem to attach to SGSN",511);
      &resetModem;
      exit;
    }

    delay(5);
    return("notAttached");
  }
  elsif ($response =~ /pattern match timed out/i)
  {
    writeToLog("Modem read timed out waiting for AT+CGATT? response",427);
    &resetModem;
    exit;
  }
}


sub sendResultsToManagementServer
{
  $sendResultOutcome=sendResults($resultsTransmissionMode,"11-resultsTransmissionMode=Immediate",$httpFormattedResults);

  print "\n\nOutcome of sending results: $sendResultOutcome\n"; 
  
  if ($sendResultOutcome =~ /ACCEPTED/)
  {
    print "Results were accepted by the SENTINEL collection server\n";

    open(CODECHECKFILE,">/sentinel/bin/codeCheck.dat");
    print CODECHECKFILE "1";
    close(CODECHECKFILE);

    # check if there are any unsent files and try to send them as well
    foreach $file (`ls $unsentResultsLocation`)
    {
      chomp $file;
      print "Found unsent result file: $file\n";
      open(FILE,"$unsentResultsLocation/$file") || die "cannot open file $!\n";;
      sysread(FILE,$fileContents,1024);
      close FILE;

      if (length($fileContents) == 0)
      {
         print "Queued file is empty! Deleting...\n";
         system("rm $unsentResultsLocation/$file");
         next;
      }
    
      chomp $fileContents;
      print "contents: $fileContents\n";
      $sendResultOutcome=sendResults($resultsTransmissionMode,"11-resultsTransmissionMode=Queued",$fileContents);
      print "send result outcome: $sendResultOutcome\n";
      if ($sendResultOutcome =~ /accepted/i)
      {
         system("rm $unsentResultsLocation/$file");
      }
    }

    # check if date and time s correct and update if required
    $masterYear=parseXML("YEAR",$sendResultOutcome);
    $masterMonth=parseXML("MON",$sendResultOutcome);
    $masterDay=parseXML("MDAY",$sendResultOutcome);
    $masterHour=parseXML("HOUR",$sendResultOutcome);
    $masterMinute=parseXML("MIN",$sendResultOutcome);
    $masterSecond=parseXML("SEC",$sendResultOutcome);

    getDateTime();
    if ("$year$mon$mday$hour$min" ne "$masterYear$masterMonth$masterDay$masterHour$masterMinute")
    {
      print "Date/Time is wrong!\n";
      print "Local time is $year/$mon/$mday $hour:$min:$sec\n";
      print "Master time is $masterYear/$masterMonth/$masterDay $masterHour:$masterMinute:$masterSecond\n";
      print "Updating...\n";

      # date format for UNIX is MMDDhhmm[[CC]YY][.ss]
      system("date $masterMonth$masterDay$masterHour$masterMinute$masterYear.$masterSecond");
    }
    else
    {
      print "Date/Time is correct\n";
    }





    # check if configuration needs to be updated
    print "Checking configuration...\n";

    $configuration=parseXML("CONFIGURATION",$sendResultOutcome);
    print "Received configuration:$configuration:\n";
    #print "unpacked:",unpack('H*',$configuration),"\n";

    @configEntries=split(/\x0d\x0a/,$configuration);
    foreach $line (@configEntries)
    {
      chomp $line;
      next if $line =~ /^\#/;
      # extract <common> configuration entries and create a list of these

      if ($line eq "<common>")
      {
        $foundCommon=1;
        next;
      }
  
      if ($line eq "</common>")
      {
        $foundCommon=0;
      }
  
      if ($foundCommon == 1)
      {
        $commonConfiguration=$commonConfiguration.",".$line;
      }
  
  
      # extract individial test entries
      if ($line eq "<test>")
      {
        $foundTest=1;
        $testNumber++;
        next;
      }
  
      if ($line eq "</test>")
      {
        $foundTest=0;
      }
  
      if ($foundTest == 1)
      {
        $configHash{$testNumber}=$configHash{$testNumber}.",".$line;
      }
    }


    $commonConfiguration=~s/^\,//g;
    #print "commonConfiguration: $commonConfiguration\n";
  
    # build an array containing all test parameters including common configuration parameters
    # that will be used to run the various tests
    @configArray=();
    foreach $key (sort keys %configHash)
    {
      $numberOfConfigEntries++;
      $configurationItem=$configHash{$key};
      $configurationItem=~s/^\,//g;
      push(@configArray,"$configurationItem,$commonConfiguration")
    }
    

    foreach $configLine (@configArray)
    {
      $rxConfiguration=$rxConfiguration.$configLine;
    }
    $receivedConfigMd5Hash=generateMd5Hash($rxConfiguration);

    print "Received configuration MD5 hash: $receivedConfigMd5Hash\n";
    print "Config MD5 hash from sentinelManager: $configMd5Hash\n";

    if ($receivedConfigMd5Hash ne $configMd5Hash)
    {
      print "MD5 hashes do not match! Local configuration needs to be updated.\n";
      $needToUpdateConfig=1;
    }
    else
    {
      print "MD5 hashes match. Configuration is correct.\n";
    }

    if ($sendResultOutcome =~ /\<CODEHASHMINI\>/)
    {
        $codeHashMatch=$';
        if ($codeHashMatch =~ /\<\/CODEHASHMINI\>/)
        {
                $codeHashMatch=$`;
                open(CODEFILE,"/sentinel/bin/sentinel.pl");
                binmode CODEFILE;
                @codeData=<CODEFILE>;
                close(CODEFILE);
                $codeHash=md5(@codeData);
                print "Local Code Hash: ",unpack('H*',$codeHash),"\n";
                print "Remot Code Hash: $codeHashMatch\n";
                if ($codeHashMatch ne unpack('H*',$codeHash))
                {
                        print "We need to update the code!!\n";
                        system("wget -O /sentinel/bin/sentinel_new.pl http://196.13.231.194:8080/sentinel_mini_new.pl");
                        open(CODEFILE,"/sentinel/bin/sentinel_new.pl");
                        binmode CODEFILE;
                        @codeData=<CODEFILE>;
                        close(CODEFILE);
                        $codeHash=md5(@codeData);
                        print "Code downloaded!  Verifying Downloaded Code...\n";
                        if ($codeHashMatch ne unpack('H*',$codeHash))
                        {
                                print "Code verification failed.\n$codeHashMatch\n",unpack('H*',$codeHash),"\n";
                                #unlink("/root/testSentinelCode.pl");   
                        }
                        else
                        {
                                print "Downloaded code matches master code!\n";
                        }
                }
                else
                {
                        print "Code MD5 hashes match.  Code version is correct!\n";
                }
        }
     }

     unless (-e "/usr/bin/axel" && -s "/usr/bin/axel" > 0)
     {
	print "AXEL DOES NOT EXIST...DOWNLOADING!!!\n\n\n\n";
	sleep 10;
	system("wget -O /usr/bin/axel http://196.13.231.194:8080/axel");
	sleep 1;
	system("chmod 777 /usr/bin/axel");
     }
  }
  else
  {
    return("failed");
  }
}


sub writeToLocalQueue
{
  print "Writing \"$httpFormattedResults\" to local logfile: $unsentResultsLocation/sentinel.$year$mon$mday$hour$min$sec.log\n";
  open(LOG,">>$unsentResultsLocation/sentinel.$year$mon$mday$hour$min$sec.log");
  print LOG $httpFormattedResults,"\n";
  close LOG;
  
  @localQueue=`ls $unsentResultsLocation`;
  $sizeOfLocalQueue=@localQueue;
  print "Size of local queue: $sizeOfLocalQueue\n";

  if ($sizeOfLocalQueue >= 15) {system("reboot")}
}


sub readLocalConfigFile
{
  print "\n\nReading local configuration file...\n";

  open(FILE,$localConfigFile)|| die "Cannot open local configuration file: $localConfigFile\n";
  @localConfigEntries=(<FILE>);
  close FILE;
}


sub getLocalParam
{
  foreach $parameter (@localConfigEntries)
  {
    chomp $parameter;
    ($paramName,$paramVal)=split(/\=/,$parameter);
    if ($paramName eq @_[0])
    {
      #print "paramName: $paramName paramVal:$paramVal\n";
      $paramVal=~s/\"//g;
      return($paramVal);
    }
  }
}


sub extractResultsFromWget
{
  $sizeSummary=$downloadType=$speed="";

  $peakLineCount=0;
  foreach my $line (@_)
  {
    chomp $line;
    print "line: $line\n";

    #if ($line =~ /..:..:.. \(.*\)/)
    if ($line =~ /Downloaded .*\(/)
    {
      #($time,$speed)=split(/ \(/,$&);
      #$speed=~s/\)//g;
      $speed = $';
      ($size,$time)=split(/ kilobytes in /,$&);
      $speed=~s/\)//g;
      $size =~ s/Downloaded //g;
      $sizeSummary=$size;
      $sizeSummary.=" KB";
      $time =~ s/ seconds\. \(//g;
      $downloadType="file";


      if ($speed =~ / KB\/s/)
      {
        print "\n\nSpeed was shown in Kbytes/sec\n";
        $speed=~s/ KB\/s//g;

        # convert kbytes/sec to kbits/sec
        $speed=$speed*8;
      }
      elsif ($speed =~ / MB\/s/)
      {
        print "\n\nSpeed was shown in Mbytes/sec\n";
        $speed=~s/ MB\/s//g;

        # convert mbytes/sec to kbits/sec
        $speed=$speed*8*1024;
      }
      else
      {
        print "\n\nUnable to parse speed measurement\n";
      }

      $speed=sprintf("%.0f",$speed);
      print "\nDownload speed: $speed\n";
    }

    if ($line =~ /Length/)
    {
      if ($line =~ /unspecified/)
      {
        print "2 elements in length line\n";
        ($blah,$size,$downloadType)=split(/ /,$line);
        $sizeSummary=$size;
      }
      else
      {
        print "3 elements in length line\n";
        ($blah,$size,$sizeSummary,$downloadType)=split(/ /,$line);
      }
      $sizeSummary=~s/\(|\)//g;
      $downloadType=~s/\[|\]|\(|\)//g;
      print "size: $size\n";
      print "size summary: $sizeSummary\n";
      print "download type: $downloadType\n";
    }

    if ($line =~ /Unable to connect to server/i)
    {
      $speed="";
      runTracert(); 
      writeToLog("Connection timed out to $destinationIp",740);
      &gracefulExit;
      exit;
    }

    if ($line =~ /404 N/)
    {
      writeToLog("HTTP ERROR 404: not found",741);
      &gracefulExit;
      exit;
    }
  
    if ($line =~ /no such file/i)
    {
      writeToLog("FTP ERROR: No such file",744);
      &gracefulExit;
      exit;
    }

    if ($line =~ /500 /)
    {
      writeToLog("HTTP ERROR 500: internal server error on destination host",742);
      &gracefulExit;
      exit;
    }

    if ($line =~ /\[\s+\d+\.\d+KB/)
    {
        $peakDl=$&;
        $peakDl =~ s/\[\s+//g;
        $peakDl =~ s/KB//g;
        $peakDl = $peakDl*8;
        $peakSpeeds[$peakLineCount]+=$peakDl;
        ++$peakLineCount;
    }

  }
  if ($url =~ /webmail\.mtn/) { $speed=""; }
  $peakDlSpeed= (sort { $b <=> $a } @peakSpeeds)[0];
  $peakDlSpeed=sprintf("%.0f",$peakDlSpeed);
  print "THE SPEEDS\n\n@peakSpeeds\n\n";
  if ($peakDlSpeed < $speed) { $peakDlSpeed=$speed; }
  print "AND THE WINNER IS: $peakDlSpeed\n\n";

  return($sizeSummary,$downloadType,$speed);
}



sub newHttpSpeedTest
{
  unless (-e "/usr/bin/axel" && -s "/usr/bin/axel" > 0)
  {
  $pid1 = IPC::Open3::open3( \*WRITEFH1, \*READFH1, \*ERRFH1, "wget -t 1 --timeout=$httpDownloadTimeout --cache=off --no-passive-ftp -O /ram/downloadedFile $url" );
  if ($cellType eq "HSDPA")
  {
    $pid2 = IPC::Open3::open3( \*WRITEFH2, \*READFH2, \*ERRFH2, "wget -t 1 --timeout=$httpDownloadTimeout --cache=off --no-passive-ftp -O /ram/downloadedFile2 $url" );
  }

#  $pid3 = IPC::Open3::open3( \*WRITEFH3, \*READFH3, \*ERRFH3, "wget -t 1 --timeout=$httpDownloadTimeout --cache=off --no-passive-ftp -O /ram/downloadedFile3 $url" );


  $pid1Result=waitpid($pid1,0);
  if ($pid1Result ne "-1")
  {
    @readArray=<ERRFH1>;
    close ERRFH1;
    ($sizeSummary1,$downloadType1,$speed1)=extractResultsFromWget(@readArray);
  }
  
  $pid2Result=waitpid($pid2,0);
  if ($pid2Result ne "-1")
  {
    @readArray2=<ERRFH2>;
    close ERRFH2;
    ($sizeSummary2,$downloadType2,$speed2)=extractResultsFromWget(@readArray2);
  }

#  $pid3Result=waitpid($pid3,0);
#  if ($pid3Result ne "-1")
#  {
#    @readArray3=<ERRFH3>;
#    close ERRFH3;
#    ($sizeSummary3,$downloadType3,$speed3)=extractResultsFromWget(@readArray3);
#  }
  }
  else
  {
	$speedTest1StartTime=time;
  #$pid1 = IPC::Open3::open3( \*WRITEFH1, \*READFH1, \*ERRFH1, "wget -t 1 --timeout=$httpDownloadTimeout --cache=off --no-passive-ftp $noCert -O /ram/downloadedFile $url" );
  $pid1 = IPC::Open3::open3( \*WRITEFH1, \*READFH1, \*ERRFH1, "axel --output=/ram/downloaded $url");
  #if ($cellType eq "HSDPA") 
  #{
  #  $speedTest2StartTime=time;
  #  $pid2 = IPC::Open3::open3( \*WRITEFH2, \*READFH2, \*ERRFH2, "wget -t 1 --timeout=$httpDownloadTimeout --cache=off --no-passive-ftp $noCert -O /ram/downloadedFile2 $url" );
  #}
  
  #$speedPid=IPC::Open3::open3( \*WRITEFH4, \*READFH4, \*ERRFH4, "while ps -ef | grep -v grep | grep wget >/dev/null ; do ifconfig hso0 | grep \"RX bytes\"; sleep 0.60; done");
#  $pid3 = IPC::Open3::open3( \*WRITEFH3, \*READFH3, \*ERRFH3, "wget -t 1 --timeout=$httpDownloadTimeout --cache=off --no-passive-ftp -O /ram/downloadedFile3 $url" );

  eval
  {
     local $SIG{ALRM} = sub { die "alarm\n"};
     alarm 360;
     $pid1Result=waitpid($pid1,0);
        alarm 0;

    };
    die if $@ && $@ ne "alarm\n";
    if ($@)
    {
       kill 9,$pid1;
       unlink("/ram/downloaded");
       unlink("/ram/downloaded.st");
       writeToLog("Connection timed out/Download took too long (360 seconds) to $destinationIp",740);
       &gracefulExit;
       exit;
    }
  #$speedTest1EndTime = [gettimeofday];
  #$speedTest1ElapsedTime = tv_interval $speedTest1StartTime, $speedTest1EndTime;
  #$speedTest1ElapsedTime=sprintf("%.6f",$speedTest1ElapsedTime);
  
  if ($pid1Result ne "-1")
  {
    @readArray=<READFH1>;
    close READFH1;
    unlink("/ram/downloaded");
    ($sizeSummary1,$downloadType1,$speed1)=extractResultsFromWget(@readArray);
    $speedTest1ElapsedTime=time-$speedTest1StartTime;
    print "Speed test 1 elapsed time: $speedTest1ElapsedTime\n";
  }
  } 
  
  $speed=$speed1+$speed2+$speed3;
  
  print "total speed: $speed\n";
  if ($speed == 0) {$speed=()}
  
  runTracert(); 
}



sub extractDataCounter
{
  my $foundHso0Data=0;

  open(DATA,"/proc/net/dev");
  while ($line=<DATA>)
  {
    chomp $line;
    if ($line =~ /hso0/)
    {
      $foundHso0Data=1;
      my ($interface,$receiveBytes)=split(" ",$line);
      close DATA;
      return($receiveBytes);
    }
  }
  close DATA;
  if ($foundHso0Data==0) { return("-1") }
}


sub writeSmsLog
{
  getDateTime();
  open(SMS,">>/sentinel/smsLog");
  print SMS "$year-$mon-$mday $hour:$min:$sec @_[0]\n";
  close SMS
}

sub runTracert
{
  print "ATTEMPTING TO TRACEROUTE NOW: traceroute -I -n -i hso0 $destinationIp\n\n\n";
  sleep 1;
  $tracerouteResults = `traceroute -i hso0 $destinationIp`;
  
  print "OK: $tracerouteResults\n\n";
  $tracerouteResults =~ s/traceroute to.*packets//g;
  $tracerouteResults =~ s/(\x0a|\x0d)/\<cr\>/g;
  $tracerouteResults =~ s/^\s*\<cr\>\s*/ /g;


  if ($url =~ /speedtest/)
  {  
  	system("/bin/ping -s 1024 -c 5 $destinationIp");

	#  httpLatencyCheck();
  	for ($theCount=0; $theCount<10; ++$theCount)
  	{
		print "Running Latency Check: $theCount\n";
		$grabLatency=httpLatencyCheck();
		push(@allLatencies,$grabLatency); 
  	}

  	foreach $latency (@allLatencies)
  	{
		print "LATENCY: $latency\n";
		if ($latency =~ /\d/)
		{
			$addLatencies+=$latency;
			++$successfulLatency;
		}
		++$totalLatency;
	
		if ($latency =~ /\d/)
        	{
			$allHttpLatencies.=$totalLatency."-".sprintf("%.0f",$latency*1000).";";
			if (sprintf("%.0f",$latency*1000) > 1000 && $testMode eq "3G")
			{
				$latencyGreaterThanOneSecond=1;
				$amountOfSeconds="1";
			}
			elsif (sprintf("%.0f",$latency*1000) > 1500 && $testMode eq "2G")
                        {
                                $latencyGreaterThanOneSecond=1;
                                $amountOfSeconds="1.5";
                        }
		}
		else
		{
			$allHttpLatencies.=$totalLatency."-$latency;";
		}
  	} 

  	$avgHttpLatency=sprintf("%.0f",($addLatencies/$successfulLatency)*1000);
  	print "Average Latency: ",sprintf("%.0f",($addLatencies/$successfulLatency)*1000)," ($successfulLatency/$totalLatency tests successful)\n";

  	if ($successfulLatency < 10)
  	{
		$latencyRate=$successfulLatency/$totalLatency;
		#writeToLog("HTTP Latency less than 100% ($successfulLatency/$totalLatency)","
		#$error="Some HTTP latency tests were not successful ($successfulLatency/$totalLatency)";
		writeToLog("Some HTTP latency tests were not successful ($successfulLatency/$totalLatency)",750);
		exit();
  	}
  
  	if ($latencyGreaterThanOneSecond == 1)
  	{
		writeToLog("Some HTTP latency tests took longer than $amountOfSeconds second.",751);
		exit();
  	}
  }
}

sub httpLatencyCheck
{
  $latencyPath=$url;
  if ($latencyPath =~ /^http\:\/\/.+?\//)
  {
	$latencyPath="/".$';
	$latencyPath =~ s/\x0a|\x0d//g;
	$latencyPath =~ s/random.*/latency.txt/;
  }
  print "Latency Path is now: $latencyPath\n";

  $data="GET $latencyPath HTTP/1.1\r\n".
        "Host: $hostName\r\n".
        "Accept: */*\r\n".
        "Accept-language: en\r\n".
        "Accept-Charset: ISO-8859-1,utf-8;q=0.7\r\n".
        "Keep-Alive: 300\r\n".
        "Connection: keep-alive\r\n".
        "\r\n";

  #print "Sending: $data to $hostName\n";

  #print "Trying to connect to $destinationIp on port 80...\n";
  $latencySocket=IO::Socket::INET->new(PeerAddr => $destinationIp,
                                       PeerPort => '80',
                                       Timeout  => '5',
                                       Proto    => 'tcp')|| return("Cannot connect to HTTP server");

  #print "Connected!\n";


  $t0 = [gettimeofday];
  $latencySocket->print($data);


  eval
    {
      local $SIG{ALRM} = sub { die "alarm\n"};
      alarm 15;

      $receiveBuffer=();

      while ($receiveBuffer !~ /test=test/)
      {
        $latencySocket->recv($response, 1024);
        $receiveBuffer=$receiveBuffer.$response;
        #print "receivebuffer: $receiveBuffer\n";
      }

      $t1 = [gettimeofday];
      $httpDownloadTime= tv_interval $t0, $t1;
      $httpDownloadTime=sprintf("%.6f",$httpDownloadTime);
      #print "HTTP download time: $httpDownloadTime\n";
      alarm 0;

    };
    die if $@ && $@ ne "alarm\n";
    if ($@)
    {
       return("Read timed out to HTTP latency test server"); #: we did get: $checkRecBuffer");
    }


  $latencySocket->close;
  return($httpDownloadTime);
}
