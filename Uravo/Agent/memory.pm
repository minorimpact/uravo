package Uravo::Agent::memory;

use strict;

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

    my $options = $uravo->{options};
    my $server = $uravo->getServer() || die("Can't create server object.");
    my $monitoringValues = $server->getMonitoringValues();
  

    my $free = join("\n", Uravo::Util::do_cmd('free'));

    my $mem_total;
    my $mem_used;
    my $mem_free;
    my $mem_percent;

    my $swap_total;
    my $swap_used;
    my $swap_free;
    my $swap_percent;

    my $cache_percent;

    if ($free =~ /Mem:\s+(\d+)\s+(\d+)\s+(\d+)\s+(\d+)\s+(\d+)\s+(\d+)/s) {
        $mem_total = $1;
        $mem_used = $2;
        $mem_free = $3;
        my $shared_used = $4;
        my $buffers_used = $5;
        my $cache_used = $6;
        if ($mem_total) {
            $cache_percent = ($mem_used / $mem_total) * 100;
            #$mem_percent = (($mem_used - $buffers_used) / $mem_total) * 100;
            $mem_percent = (($mem_total - $mem_free) / $mem_total) * 100;
        }
    }
    if ($free =~ /Swap:\s+(\d+)\s+(\d+)\s+(\d+)/s) {
        $swap_total = $1;
        $swap_used = $2;
        $swap_free = $3;
        $swap_percent = ($swap_used / $swap_total) * 100 if ($swap_total);
    }

    if (! $options->{dryrun}) {
        $server->graph('memory,mem', $mem_percent);
        $server->graph('memory,swap', $swap_percent);
        $server->graph('memory,cache', $cache_percent);

        if (-f "/proc/meminfo") {
            foreach my $row (Uravo::Util::do_cmd('cat /proc/meminfo')) {
                if ($row =~ /^([^ :]+): +([^ :]+)/) {
                    my $key = $1;
                    my $value = $2;
                    if ($key =~ /^(LowFree|HighFree|Buffers|Cached)$/) {
                        $server->graph("meminfo,$key", $value);
                    }
                }
            }
        }
    }

    my $Severity = 'green';
    if (!$monitoringValues->{'memory'}{'swap'}{'disabled'} && $swap_percent > $monitoringValues->{'memory'}{'swap'}{'red'}) {
        $Severity = 'red';
    } elsif (!$monitoringValues->{'memory'}{'swap'}{'disabled'} && $swap_percent > $monitoringValues->{'memory'}{'swap'}{'yellow'}) {
        $Severity = 'yellow';
    }

    my $Summary = sprintf("Swap %.2f%% - total:%s used:%s free:%s", $swap_percent, $swap_total, $swap_used, $swap_free);
    $server->alert({Summary=>$Summary, Severity=>$Severity, AlertGroup=>'memory', AlertKey=>'swap', Recurring=>1}) unless ($options->{dryrun});
}

1;
