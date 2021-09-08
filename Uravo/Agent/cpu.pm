package Uravo::Agent::cpu;

use Uravo;
use Uravo::Util;

use parent 'Uravo::Agent::Module'; #our @ISA = (Uravo::Agent::Module);

sub run {
    my $self = shift || return;

    my $uravo = $self->{uravo};

    my $uptime = (Uravo::Util::do_cmd('uptime'))[0];
    return if ($uptime !~ /load average: (\d+\.\d\d),? (\d+\.\d\d),? (\d+\.\d\d)/);

    my $la = $2;
    my $message;
    my $Severity = $self->getSeverity('cpu_load_average', undef, $la);
    my $yellow_flag = ($Severity eq 'yellow') ? 1 : 0;
    my $Summary = "load average is $la.";
    $self->{server}->alert({AlertGroup=>'cpu_load_average', Summary=>$Summary, Severity=>$Severity, Recurring=>1}) unless ($self->{options}->{dryrun});
    $self->{server}->graph('cpu_load_average', $la) unless ($self->{options}->{dryrun});

    if ($yellow_flag) {
        my $yellow_start = $self->{server}->getLast("cpu", "yellow_start");
        my $now = time;
        if (!$yellow_start) {
            $self->{server}->setLast("cpu", "yellow_start", $now) unless ($self->{options}->{dryrun});
            $self->{server}->Alert({AlertGroup=>'cpu_yellow_time', Severity=>"green", Summary=>"Server is yellow.", Recurring=>1}) unless ($self->{options}->{dryrun});
        } else {
            my $minutes = ($now - $yellow_start)/60;
            my $Severity = "green";
            my $Severity = $self->getSeverity('cpu_yellow_time', undef, $minutes);
            my $Summary = "Server has been yellow for " . sprintf("%.2f", $minutes) . " minutes.";
            $self->{server}->alert({AlertGroup=>'cpu_yellow_time', Severity=>$Severity, Summary=>$Summary, Recurring=>1}) unless ($self->{options}->{dryrun});
        }
    } else {
        $self->{server}->setLast('cpu', 'yellow_start') unless ($self->{options}->{dryrun});
        my $Severity = "green";
        my $Summary = "CPU is not yellow.";
        $self->{server}->alert({AlertGroup=>'cpu_yellow_time', Severity=>$Severity, Summary=>$Summary, Recurring=>1}) unless ($self->{options}->{dryrun});
    }

    return;
}

1;
