#!/usr/bin/perl

use strict;

use Uravo;

my $uravo = new Uravo;
my $local_server = $uravo->getServer();

while (1) {
    my $Severity = int(rand(6));
    my $AlertGroup = int(rand(10)) + 1;
    my $Recurring = 0;
    $Recurring = 1 if ($AlertGroup > 5);
    print "AlertGroup=>'random_$AlertGroup', Summary=>'Random Alert: $AlertGroup', Severity=>$Severity, Timeout=>5, Recurring=>$Recurring\n";
    $local_server->alert({AlertGroup=>"random_$AlertGroup", Summary=>"Random Alert: $AlertGroup", Severity=>$Severity, Timeout=>5, Recurring=>$Recurring});
    sleep 15;
}

