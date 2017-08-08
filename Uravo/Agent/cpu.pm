package Uravo::Agent::cpu;

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

    my $uptime = (Uravo::Util::do_cmd('uptime'))[0];
    return if ($uptime !~ /load average: (\d+\.\d\d),? (\d+\.\d\d),? (\d+\.\d\d)/);

    my $la = $2;
    my $message;
    my $yellow_flag = 0;
    my $yellow = $monitoringValues->{'cpu_load_average'}{'yellow'};
    my $red = $monitoringValues->{'cpu_load_average'}{'red'};
    if ($monitoringValues->{'cpu_load_average'}{'disabled'}) {
        my $Severity = 'green';
        my $Summary = "Load average is $la. (DISABLED)";
        $self->{server}->alert({AlertGroup=>'cpu_load_average', Summary=>$Summary, Severity=>$Severity, Recurring=>1}) unless ($options->{dryrun});
    } else {
        my $Severity = 'green';
        if ($la > $red) {
            $Severity = "red";
        } elsif ($la > $yellow) {
            $yellow_flag = 1;
            $Severity = 'yellow';
        } else {
            $Severity = 'green';
        }
        my $Summary = "load average is $la.";
        $server->alert({AlertGroup=>'cpu_load_average', Summary=>$Summary, Severity=>$Severity, Recurring=>1}) unless ($options->{dryrun});
    }
    $server->graph('cpu_load_average', $la) unless ($options->{dryrun});

    if ($yellow_flag) {
        my $yellow_start = $server->getLast("cpu", "yellow_start");
        my $now = time;
        if (!$yellow_start) {
            $server->setLast("cpu", "yellow_start", $now) unless ($options->{dryrun});
            $server->Alert({AlertGroup=>'cpu_yellow_time', Severity=>"green", Summary=>"Server is yellow.", Recurring=>1}) unless ($options->{dryrun});
        } else {
            my $minutes = ($now - $yellow_start)/60;
            my $Severity = "green";
            if ($minutes > $monitoringValues->{'cpu_yellow_time'}{'red'}) {
                $Severity = "red";
            } elsif ($minutes > $monitoringValues->{'cpu_yellow_time'}{'yellow'}) {
                $Severity = "yellow";
            }
            my $Summary = "Server has been yellow for " . sprintf("%.2f", $minutes) . " minutes.";
            $server->alert({AlertGroup=>'cpu_yellow_time', Severity=>$Severity, Summary=>$Summary, Recurring=>1}) unless ($options->{dryrun});
        }
    } else {
        $server->setLast('cpu', 'yellow_start') unless ($options->{dryrun});
        my $Severity = "green";
        my $Summary = "CPU is not yellow.";
        $server->alert({AlertGroup=>'cpu_yellow_time', Severity=>$Severity, Summary=>$Summary, Recurring=>1}) unless ($options->{dryrun});
    }

    return;
}

1;
