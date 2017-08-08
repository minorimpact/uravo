package Uravo::Agent::squid;

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

    my $Severity;
    my $Summary;
    my $log = '/logs/squid/access.log';
    if (! -f $log || -z $log) {
        $Summary = "Squid is not running on this host (or log file is zero size)";
        $server->alert({AlertGroup=>'squid_log_file', Summary=>$Summary, Severity=>$Severity, Recurring=>1}) unless ($options->{dryrun});

        $Summary = "Squid is not running on this host (or log file is zero size)";
        $server->alert({AlertGroup=>'squid_missrate', Summary=>$Summary, Severity=>$Severity, Recurring=>1}) unless ($options->{dryrun});

        $server->alert({AlertGroup=>'squid_hitrate', Summary=>$Summary, Severity=>$Severity, Recurring=>1}) unless ($options->{dryrun});

        $server->alert({AlertGroup=>'squid_cpu', Summary=>$Summary, Severity=>$Severity, Recurring=>1}) unless ($options->{dryrun});

        return;
    }

    # log rotation happens at 7 minutes after the hour at 2, 7, 13, and 19 hours.
    my ($min, $hour) = (localtime())[1,2];
    sleep 60 if ($min == 7 && ($hour == 2 || $hour == 7 || $hour == 13 || $hour == 19));

    my $time_to   = time();
    my $time_from = $time_to - TIME_BETWEEN_RUNS;

    my $statuses = {};
    my $cnt = 0;
    my $total_ms = 0;
    open(FILE, $log);
    seek(FILE, -20000000, 2);
    while(my $line = <FILE>) {
        chomp $line;
        next if ($line !~ /^(\d+\.\d+)\s+(\d+)\s+[\d\.]+\s+([A-Z_\d]+)\/(\d+)\s/);
        my ($time, $ms, $status, $code) = ($1, $2, $3, $4);
        next if ($time < $time_from);
        last if ($time > $time_to) ;
        $statuses->{$status}++;
        $cnt++;
        $total_ms += $ms;
    }
    close FILE;

    my $message = '';
    my %info;
    my $hitrate = 0;
    my $missrate = 100;
    my $memrate = ($cnt ? $statuses->{TCP_MEM_HIT} / $cnt * 100.0 : 0);

    if ($cnt) {
        foreach my $val (qw/HIT MISS/) {
            my $total = 0;
            foreach my $status (sort { $a cmp $b && $statuses->{$b} <=> $statuses->{$a} } grep { /${val}$/ } keys %$statuses) {
                $total += $statuses->{$status};
                my $perc = $statuses->{$status} / $cnt * 100.0;
                $info{$val} .= sprintf("%s:%0.2f% ", $status, $perc);
            }
            my $perc = $total / $cnt * 100.0;
            $hitrate = $perc if ($val eq 'HIT');
            $missrate = $perc if ($val eq 'MISS');

            $info{$val} .= sprintf("%s:%0.2f%\% ", "Total", $total / $cnt * 100.0);
        }
    }

    my $hits_per_second = $cnt / TIME_BETWEEN_RUNS;
    my $total_seconds = $total_ms / 1000;
    my $seconds_per_request = ( $cnt ? $total_seconds / $cnt : 999999);

    $info{'HIT'} .= sprintf("Hits per second:%0.2f ", $hits_per_second);
    $info{'HIT'} .= sprintf("Average seconds per request:%0.3f ", $seconds_per_request);
    $info{'MISS'} .= sprintf("Average seconds per request:%0.3f ", $seconds_per_request);

    $Severity = 'green';
    if ($hitrate < $monitoringValues->{'squid_itrate'}{'red'} && !$monitoringValues->{'squid_hitrate'}{disabled}) {
        $Severity = 'red';
    } elsif ($hitrate < $monitoringValues->{'squid_hitrate'}{'yellow'} && !$monitoringValues->{'squid_hitrate'}{disabled}) {
        $Severity = 'yellow';
    }
    $Summary = sprintf("Total hit rate is %.2f%%", $hitrate);
    $server->alert({AlertGroup=>'squid_hitrate', Summary=>$Summary, Severity=>$Severity, AdditionalInfo=>$info{'HIT'}, Recurring=>1}) unless ($options->{dryrun});

    $Severity = 'green';
    if ($missrate > $monitoringValues->{'squid_missrate'}{'red'} && !$monitoringValues->{'squid_missrate'}{disabled}) {
        $Severity = 'red';
    } elsif ($missrate > $monitoringValues->{'squid_missrate'}{'yellow'} && !$monitoringValues->{'squid_missrate'}{disabled}) {
        $Severity = 'yellow';
    }
    $Summary = sprintf "Total miss rate is %.2f%%", $missrate);
    $server->alert({AlertGroup=>'squid_missrate', Summary=>$Summary, Severity=>$Severity, AdditionalInfo=>$info{'MISS'}, Recurring=>1}) unless ($options->{dryrun});

    my $top = `/usr/bin/top -b -n 1|grep squid.*squid`;
    my @points = split(/\b\s+/,$top);
    my $cpu_pct = $points[8];

    $Severity = 'green';
    if (!$monitoringValues->{'squid_cpu'}{'disabled'} && $cpu_pct > $monitoringValues->{'squid_cpu'}{'red'}) {
        $Severity = 'red';
    } elsif (!$monitoringValues->{'squid_cpu'}{'disabled'} && $cpu_pct > $monitoringValues->{'squid_cpu'}{'yellow'}) {
        $Severity = 'yellow';
    }
    $Summary = "CPU processs percent: $cpu_pct\%";
    $server->alert({AlertGroup=>'squid_cpu', Summary=>$Summary, Severity=>$Severity, Recurring=>1}) unless ($options->{dryrun});

    unless ($options->{dryrun}) {
        $server->graph('squid,hitrate', $hitrate);
        $server->graph('squid,missrate', $missrate);
        $server->graph('squid,memrate', $memrate);
        $server->graph('http_req_time,squid', $seconds_per_request);
        $server->graph('http_reqs_sec,squid', $hits_per_second);
        $server->graph('squid_cpu_pct', $cpu_pct);
    }

    return;
}

1;
