#!/usr/bin/perl
################################################################################
# Application to run a set of packet switched network tests                    #
# Designed to run from inittab                                                 #
# Written by: Owen L Griffith                                                  #
# Date: 2008-06-19                                                             #
################################################################################

use Digest::MD5 qw(md5);


$localConfigFile=$ARGV[0];
if ($localConfigFile eq "")
{
  print "Please specify the local configuration file for $0 to use.\n";
  exit;
}

# read local configuration file
&readLocalConfigFile;


$unitName=getParam("unitName");
$msisdn=getParam("msisdn");
$guardTime=getParam("guardTime");
$logFile=getParam("logFile");
$loggingEnabled=getParam("loggingEnabled");
$debugLoggingEnabled=getParam("debugLoggingEnabled");
$debugFilePath=getParam("debugFilePath");
$callSetConfigFile=getParam("callSetConfigurationFile");
$networkTestApplication=getParam("networkTestApplication");

if ($unitName eq "") {print "Please specify the unit name in the local configuration file.";exit}
if ($msisdn eq "") {print "Please specify the MSISDN of the unit in the local configuration file.";exit}
if ($guardTime eq "") {print "Please specify the Guard Time in the local configuration file.";exit}
if ($callSetConfigFile eq "") {print "Please specify the call set configuration file in the local configuration file.";exit}
if ($networkTestApplication eq "") {print "Please specify the network test application to use in the local configuration file.";exit}



writeToLog("Manager start");

print "Unit Name:                   $unitName\n";
print "MSISDN:                      $msisdn\n";
print "Guard Time:                  $guardTime\n";
print "Log File:                    $logFile\n";
print "Logging Enabled:             $loggingEnabled\n";
print "Debug Logging Enabled:       $debugLoggingEnabled\n";
print "Debug File Path:             $debugFilePath\n";
print "Call Set Configuration File: $callSetConfigFile\n";
print "Network Test Application:    $networkTestApplication\n";




# install signal handlers
$SIG{'TERM'}   = \&signalHandler;
$SIG{'INT'}   = \&signalHandler;
$SIG{'HUP'}   = \&hupSignalHandler;
$SIG{'USR1'}   = \&usr1SignalHandler;
$SIG{'USR2'}   = \&usr2SignalHandler;


# get current date and time
getDateTime();

# create codeCheck file for remote code upgrade if it does not exist
unless (-e "/sentinel/bin/codeCheck.dat")
{
    open(CODECHECK,">/sentinel/bin/codeCheck.dat");
    print CODECHECK "1";
    close(CODECHECK);
}

# configuration #
print "PID of this process is $$\n";


# determine uptime
($time,$users,$loadAvg)=split(/,/,`uptime`);


readConfigFile();


while(1)
{
  # delete old debug files to prevent the disk from filling up.
  $numberOfDebugFilesAllowed=100;
  @debugFileList=`ls -t $debugFilePath`;

  $fileCount=0;
  foreach $file (@debugFileList)
  {
    chomp $file;
    print "Debug file found: $file\n";
    $fileCount++;
    if ($fileCount >= $numberOfDebugFilesAllowed)
    {
      print "File: $file needs to be deleted\n";
      system("rm $debugFilePath/$file");
    }
  }
  

  eval
  {     
    local $SIG{ALRM} = sub { die "alarm\n"}; 
    alarm $guardTime;
  
    # look for other Manager processes
    $processCount=`ps -ef|grep -v grep|grep -v vi|grep -c $0`;
    chomp $processCount;
    print "Processcount: $processCount\n";
    if ( $processCount > 1 )
    {
      writeToLog("Another Manager process is already running, exiting...");
      exit;
    }
  
  
    if ($time =~ / 0 min/)
    {
      # wait for 30 seconds before starting tests to allow time for modems to be ready after powerup
      delay(30);
    }
  
    foreach $configLine (@configArray)
    {
      chomp $configLine;
      print "running test: $configLine...\n";
      $testStartTime=time;
      runTest("localConfigFile=$localConfigFile,unitName=$unitName,msisdn=$msisdn,configMd5Hash=$configMd5Hash,$configLine");
      $testExecutionTime=time-$testStartTime;
      print "Test execution time: $testExecutionTime\n";

      if ($testExecutionTime < 10)
      {
        print "There is a problem! Creating default callset config...\n";
        &createDefaultConfig;

	open(CODECHECK,"/sentinel/bin/codeCheck.dat") || die "Can't open codeCheck file! $!\n";;
        $codeData=<CODECHECK>;
        close(CODECHECK);
        print "Codecheck: $codeData\n\n";
        if ($codeData == 0)
        {
                print "Code update appears to be faulty.  Rolling back!\n";
                system("cp /sentinel/bin/sentinel.bak /sentinel/bin/sentinel.pl");
                sleep 5;
        }
	

        sleep 1;
        exit;
      }
    }

  
    alarm 0;
  };
  die if $@ && $@ ne "alarm\n";
  if ($@)
  {
    writeToLog("guardTime of $guardTime seconds exceeded. Killing child processes and exiting...");
    &killChildProcess;
    exit;
  }

  ### NEW REMOTE CODE UPDATE ###
  open(CODECHECK,"/sentinel/bin/codeCheck.dat") || die "Can't open codeCheck file! $!\n";;
  $codeData=<CODECHECK>;
  close(CODECHECK);
  print "Codecheck: $codeData\n\n";
  if ($codeData == 0)
  {
        print "Code update appears to be faulty.  Rolling back!\n";
        system("cp /sentinel/bin/sentinel.bak /sentinel/bin/sentinel.pl");
        sleep 10;
        next;
  }

  if (-e "/sentinel/bin/sentinel_new.pl")
  {
        print "Backing up old version of sentinel...\n";
        system("cp /sentinel/bin/sentinel.pl /sentinel/bin/sentinel.bak");
        sleep 5;
        print "Replacing old version of sentinel with new version...\n";
        system("mv /sentinel/bin/sentinel_new.pl /sentinel/bin/sentinel.pl");
        sleep 5;
        print "Setting permissions...\n";
        system("chmod 777 /sentinel/bin/sentinel.pl");
        open(CODECHECK,">/sentinel/bin/codeCheck.dat");
        print CODECHECK "0";
        close(CODECHECK);
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


sub signalHandler
{
  my $signal = shift;

  writeToLog("$0 Dying on signal $signal...");
  &killChildProcess;
  exit;
}


sub hupSignalHandler
{
  my $signal = shift;

  writeToLog("HUP signal received by $0");
  readConfigFile();
}


sub usr1SignalHandler
{
  my $signal = shift;

  writeToLog("USR1 signal received by $0");
  print "Creating default config file\n";
  &createDefaultConfig;
}


sub usr2SignalHandler
{
  my $signal = shift;

  writeToLog("USR2 signal received by $0");
  print "Deleting debug files\n";
  &deleteDebugFiles;
}


sub killChildProcess
{
  writeToLog("Looking for child processes in list...");
  $childProcessPid=`ps -ef|grep -v grep|grep -v $0|grep $$|awk '{print \$2\" \"}'`;
  $childProcessPid=~s/\x0a|\x0d//g;
  if ($childProcessPid ne "")
  {
    writeToLog("killing child process on PID $childProcessPid...");
    `kill -s TERM $childProcessPid`;   
  }
}


sub delay
{
  my $count=@_[0];
  print "Sleeping for $count seconds\n";
  while ($count != 0)
  {
    my $printData=$count."  "."\x0d";
    syswrite(STDOUT,$printData,length($printData));
    sleep 1;
    $count--;
  }
  $printData=$count."  "."\x0d";
  syswrite(STDOUT,$printData,length($printData));
  print "\nFinished sleeping\n";
}


sub runTest
{
  &getDateTime;
  if ($sequenceNumber == 9999)
  {
    $sequenceNumber=1;
  }
  $sequenceNumber++;

  $paddedSequenceNumber=sprintf("%04s",$sequenceNumber);

  if ($debugLoggingEnabled == 1)
  {
    system("$networkTestApplication \"@_[0],sequenceNumber=$$-$paddedSequenceNumber\" |tee -a $debugFilePath/debug.$$-$paddedSequenceNumber.$year$mon$mday$hour$min$sec");
  }
  else
  {
    system("$networkTestApplication \"@_[0],sequenceNumber=$$-$paddedSequenceNumber\"");
  }
}


sub writeToLog
{
  &getDateTime;
  print "@_[0] @_[1]\n";

  if ($loggingEnabled == 1)
  {
    open(LOG,">>$logFile");
    print LOG "$year/$mon/$mday $hour:$min:$sec @_[0] @_[1]\n";
    close LOG;
  }
}


sub cannotOpenConfigFile
{
  writeToLog("Cannot open call-set config file @_[0] $!");
  print "Creating default config file\n";
  &createDefaultConfig;
  exit;
}


sub generateMd5Hash
{
  my $md5Hash = md5 @_[0];
  return(unpack('H*',$md5Hash));
}


sub readConfigFile
{
  writeToLog("Manager: Reading configuration file $callSetConfigFile...");
  # read configuration file
  open(FILE,"$callSetConfigFile") || cannotOpenConfigFile($callSetConfigFile);
  @configEntries=(<FILE>);
  close FILE;

  # reset memory structures
  %configHash=();
  $testNumber=();
  $numberOfConfigEntries=();
  $commonConfiguration=();

  foreach $line (@configEntries)
  {
    #chomp $line;
    $line=~s/\x0a|\x0d//g;
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
      if (length($testNumber) == 1) { $testNumber="0".$testNumber; }
      $configHash{$testNumber}=$configHash{$testNumber}.",".$line;
    }
  }

  # remove leading comma
  $commonConfiguration=~s/^\,//g;

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

  print "Number of config entries: $numberOfConfigEntries\n";
  foreach $config (@configArray)
  {
	print "CONFIG: $config\n";
  }

  if ($numberOfConfigEntries == 0)
  {
    writeToLog("Configuration is empty!, exiting...");
    &createDefaultConfig;
    exit;
  }


  # calculate MD5 hash
  $localConfiguration="";
  foreach $configLine (@configArray)
  {
    $localConfiguration=$localConfiguration.$configLine;
  }

  $configMd5Hash=generateMd5Hash($localConfiguration);
  writeToLog("Manager: Calculating MD5 hash, result=$configMd5Hash");
}


sub createDefaultConfig
{
  unless (-e "/sentinel.default.callset.config")
  {
  	open(CONFIG,">/sentinel.default.callset.config");
  	print CONFIG "<test>\n".
               "testName=\"default-internet\"\n".
               "testMode=\"2G\"\n".
               "apn=\"internet\"\n".
               "apnAuthenticationMethod=\"none\"\n".
               "apnUsername=\"\"\n".
               "apnPassword=\"\"\n".
               "sourceIpRange=\"\"\n".
               "url=\"http://speedtest.mtnbusiness.co.za/speedtest/random500x500.jpg\"\n".
               "waitTime=\"10\"\n".
               "</test>\n";
  	close CONFIG;
  }
  print "copying /sentinel/default.callset.config to $callSetConfigFile\n";
  `cp /sentinel.default.callset.config $callSetConfigFile`;
  print "Created default config file: $callSetConfigFile\n";
}


sub readLocalConfigFile
{
  print "Reading local configuration file...\n";

  open(FILE,$localConfigFile)|| die "Cannot open local configuration file: $localConfigFile\n";
  @localConfigEntries=(<FILE>);
  close FILE;
}


sub getParam
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


sub deleteDebugFiles
{
  @debugFileList=`ls -rt $debugFilePath`;
  $numberOfDebugFiles=@debugFileList;

  $fileCount=0;
  foreach $file (@debugFileList)
  {
    $fileCount++;
    chomp $file;
    if ($file =~ /debug\./ and $fileCount != $numberOfDebugFiles)
    {
      print "Found debug file: $file Deleting...\n";
      system("rm $debugFilePath/$file");
    }
  }
}

