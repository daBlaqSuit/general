#!/usr/bin/perl

use IO::Socket;


$modemNumber=1;

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
  delay(5);
  print "Turning modem power on...\n";
  system("/usr/local/bin/outb 0x278 0");
}


delay(60);

print "Loading module hso...\n";
`/sbin/modprobe hso`;



sub delay
{
  if (@_[0] == 1) {$desc = "second"} else {$desc = "seconds"}
  my $count=@_[0];
  print "Waiting for @_[0] $desc\n";
  #sleep @_[0];

#  print "Sleeping for $count seconds\n";
  while ($count != 0)
  {
    my $printData=$count."  "."\x0d";
    syswrite(STDOUT,$printData,length($printData));
    sleep 1;
    $count--;
  }
  $printData=$count."   "."\x0d";
  syswrite(STDOUT,$printData,length($printData));
  getDateTime();
  print "Timestamp: $hour:$min:$sec\n";
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


sub socketError
{
  print "Socket error: @_[0]\n";
  $connectionStatus=@_[0];
}

