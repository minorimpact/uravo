package Uravo::Agent::ntp;

use Uravo;
use Uravo::Util;

my $uravo;

sub new {
    my $class = shift || return;

    my $self = {};

    $uravo = new Uravo;

    bless($self, $class);
    return $self;
}

sub run {
    my $self = shift || return;
    my $server = $uravo->getServer() || return;

    my $options = $uravo->{options};
    my $monitoringValues = $server->getMonitoringValues();

    my $message = '';
    unless (-f "/usr/bin/ntpstat") {
        print "  /usr/bin/ntpstat is not installed\n" if ($options->{verbose});
        return;
    }

    my $cmd = "/usr/bin/ntpstat 2>/dev/null";
    my $ntpstat = `$cmd`;
    my $ret = $?;


    my $Severity = 'green';
    if ($ret == 0) {
        $Summary = "ntpstat: synchronised to NTP server";
        my ($time_offset) = $ntpstat =~/correct to within (\d+) ms/;
        if ($time_offset) {
            $server->graph("ntp_offset", $time_offset);
        }
    } elsif ($ntpstat =~ /synchronised to local net/) {
        $Severity = 'red';
        $Summary = "ntpstat:synchronised to local net";
    } elsif ($ntpstat eq '') {
        $Severity = 'red';
        $Summary = "no output from ntpstat";
    } else {
        $Severity = 'red';
        $Summary .= "ntpstat:$ntpstat";
    }
    $server->alert({AlertGroup=>'ntp_ntpstat', Severity=>$Severity, Summary=>$Summary, Recurring=>1}) unless ($options->{dryrun});

    return;
}

1;
