package Uravo::Agent::ifconfig;

use Uravo;
use Uravo::Util;
use parent 'Uravo::Agent::Module';

sub run {
    my $self = shift || return;
    my $uravo = $self->{uravo};
    my $server = $uravo->getServer() || return;

    my $options = $uravo->{options};

    my $IFCONFIG = "/sbin/ifconfig";

    my %interface = ();
    my $i = "";
    my $RTX = "";
    open(FILE, "$IFCONFIG |") or die "can't open $@\n";
    while(my $line = <FILE>){
        chomp($line);
        last if ($line =~ /^lo:?\s/);
        $i = $1 if ($line =~ /^((eth|bond)\d:?\d?)\s/);
        my $RTX = $1 if ($line =~ /^\s+([RT]X)\s/);
        next unless ($i ne "");
        $interface{$i}{'inet addr'} = $2 if ($line =~ /inet (addr:|)(\S+)/);
        $interface{$i}{$RTX}{'overruns'} = $1 if ($line =~ /overruns[ :](\d+)/);
        $interface{$i}{$RTX}{'dropped'} = $1 if ($line =~ /dropped[: ](\d+)/);
        $interface{$i}{$RTX}{'carrier'} = $1 if ($line =~ /carrier[: ](\d+)/);
    }
    close FILE;


    my $Summary = '';
    foreach my $i (sort keys %interface) {
        my $iname = "$i ($interface{$i}{'inet addr'})";
        foreach my $RTX (grep {!/inet addr/; } keys %{$interface{$i}}) {
            my $last_overruns = $server->getLast('ifconfig', "$i-$RTX-overruns");
            my $last_dropped = $server->getLast('ifconfig', "$i-$RTX-dropped");
            my $last_carrier = $server->getLast('ifconfig', "$i-$RTX-carrier");

            my $ops = (($interface{$i}{$RTX}{'overruns'} - $last_overruns)/300);
            my $dps = (($interface{$i}{$RTX}{'dropped'} - $last_dropped)/300);
            my $cps = (($interface{$i}{$RTX}{'carrier'} - $last_carrier)/300);

            my $Severity = $self->getSeverity('ifconfig_overruns', undef, $ops);
            $Summary = sprintf("%s Overruns:%d (%.2f/s)", "$iname/$RTX", $interface{$i}{$RTX}{'overruns'}, $ops);
            $server->alert({Summary=>$Summary, Severity=>$Severity, AlertGroup=>'ifconfig_overruns', AlertKey=>"$i-$RTX", Recurring=>1}) unless ($options->{dryrun});

            $Severity = $self->getSeverity('ifconfig_dropped', undef, $dps);
            $Summary = sprintf("%s dropped:%d (%.2f/s)", "$iname/$RTX", $interface{$i}{$RTX}{'dropped'}, $dps);
            $server->alert({Summary=>$Summary, Severity=>$Severity, AlertGroup=>'ifconfig_dropped', AlertKey=>"$i-$RTX", Recurring=>1}) unless ($options->{dryrun});

            $Severity = $self->getSeverity('ifconfig_carrier', undef, $cps);
            $Summary = sprintf("%s carrier:%d (%.2f/s)", "$iname/$RTX", $interface{$i}{$RTX}{'carrier'}, $cps);
            $server->alert({Summary=>$Summary, Severity=>$Severity, AlertGroup=>'ifconfig_carrier', AlertKey=>"$i-$RTX", Recurring=>1}) unless ($options->{dryrun});

            $server->setLast('ifconfig', "$i-$RTX-overruns", $interface{$i}{$RTX}{'overruns'}) if (! $options->{noupdate});
            $server->setLast('ifconfig', "$i-$RTX-dropped", $interface{$i}{$RTX}{'dropped'}) if (! $options->{noupdate});
            $server->setLast('ifconfig', "$i-$RTX-carrier", $interface{$i}{$RTX}{'carrier'}) if (! $options->{noupdate});
        }
    }

    return;
}

1;
