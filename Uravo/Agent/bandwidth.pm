package Uravo::Agent::bandwidth;

use Data::Dumper;
use parent 'Uravo::Agent::Module';

sub run {
    my $self = shift || return;

    my $options = $self->{uravo}->{options};

    my $short_rate_test_seconds = 3;

    my $self_id = $self->{server}->id() || return;

    my $now = time();
    my %if = getNetworkStats();
    sleep($short_rate_test_seconds);
    my %if2 = getNetworkStats();

    my $then = $self->{server}->getLast('bandwidth',"time");
    my $elapsed = ($now - $then) || 1;

    my $cnt = 0;
    foreach my $interface (sort keys %if) {
        next if (!$if{$interface}->{ip} ||
            !$if{$interface}->{out} ||
            $if{$interface}->{ip} eq "127.0.0.1" ||
            $if{$interface}->{ip} eq "0.0.0.0" ||
            !$if{$interface}->{in});
        $cnt++;

        # Check the network rate over the last few seconds to see if this is a super high-rate server.
        my $inrate = bytes_per_sec($if{$interface}->{in}, $if2{$interface}->{in}, $short_rate_test_seconds);
        my $outrate = bytes_per_sec($if{$interface}->{out}, $if2{$interface}->{out}, $short_rate_test_seconds);

        if ($inrate < 5000000 && $outrate < 5000000) {
            # If the short term rate is less than 5MB/sec, then use the value from the last time we ran,
            # which gives us an average over the last 5 minutes.  This is preferable.
            my $lastin  = $self->{server}->getLast('bandwidth_rate', "$if{$interface}->{ip}-in");
            my $lastout = $self->{server}->getLast('bandwidth_rate', "$if{$interface}->{ip}-out");

            $inrate = bytes_per_sec($lastin, $if{$interface}->{in}, $elapsed);
            $outrate = bytes_per_sec($lastout, $if{$interface}->{out}, $elapsed);
        }

        my $Severity = $self->getSeverity('bandwidth_rate', "$interface-in", $inrate);
        my $Summary = $if{$interface}->{name} . "-in: " . $inrate . " B/s";
        $self->{server}->alert({AlertGroup=>'bandwidth_rate', AlertKey=>"$interface-in", Summary=>$Summary, Severity=>$Severity}); 

        my $Severity = $self->getSeverity('bandwidth_rate', "$interface-out", $outrate);
        my $Summary = $if{$interface}->{name} . "-out: " . $outrate . " B/s";
        $self->{server}->alert({AlertGroup=>'bandwidth_rate', AlertKey=>"$interface-out", Summary=>$Summary, Severity=>$Severity}); 

        $self->{server}->setLast('bandwidth_rate', "$if{$interface}->{ip}-in", $if{$interface}->{in});
        $self->{server}->setLast('bandwidth_rate', "$if{$interface}->{ip}-out", $if{$interface}->{out});
 
        $self->{server}->graph("bandwidth,$if{$interface}->{name}.in",$inrate);
        $self->{server}->graph("bandwidth,$if{$interface}->{name}.out",$outrate);
    }

    $self->{server}->setLast('bandwidth', "time", $now);
}

sub getNetworkStats {
    my $IFCONFIG = "/sbin/ifconfig";

    my %if = ();
    my $i = '';
    my $RTX = "";
    open(FILE, "$IFCONFIG |") or die "can't open $@\n";
    while(my $line = <FILE>){
        chomp($line);        
        $i = $2 if ($line =~ /^(((lo|eth|bond)\d?):?\d?)\s/);
        next unless ($i && $i !~/lo/);
        $if{$i}->{name} = $i;
        $if{$i}->{ip} = $2 if ($line =~ /inet (addr:|)(\S+)/);
        $if{$i}->{in} = $1 if ($line =~ /RX .* bytes[ :](\d+)/);
        $if{$i}->{out} = $1 if ($line =~ /TX .* bytes[ :](\d+)/);
    }
    return %if;
}

sub bytes_per_sec {
    my $bytes1 = shift || return;
    my $bytes2 = shift || return;
    my $elapsed = shift || return;

    my $diff = 0;
    ## special case?
    if ($bytes1 > $bytes2) {
        if ((2**32 - $bytes1) > 500000000) {
            # unnatural rollover (ie, powercycle)
            $diff = $bytes2;
        } else {
            $diff = ($bytes2 + 2**32) - $bytes1;
        }
    } else {
        $diff =  $bytes2 - $bytes1;
    }
    return int($diff/$elapsed);
}

1;
