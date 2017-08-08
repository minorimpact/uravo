package Uravo::Agent::iostat;

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

    my $cmd = '/usr/bin/iostat';
    if (! -f $cmd) {
        $server->alert({AlertGroup=>'iostat_file', Summary=>"$cmd does not exist.", Severity=>'red', Recurring=>1}) unless ($options->{dryrun});
    }
    $server->alert({AlertGroup=>'iostat_file', Summary=>"$cmd exists.", Severity=>'green', Recurring=>1}) unless ($options->{dryrun});
    my $IOSTAT = `$cmd -x 3 2`;

    #avg-cpu:  %user   %nice %system %iowait  %steal   %idle
    #           9.33    0.06    0.57    0.27    0.00   89.77

    #$IOSTAT =~/^\s+([\d\.]+)\s+([\d\.]+)\s+([\d\.]+)\s+([\d\.]+)\s+([\d\.]+)\s+([\d\.]+)$/m;
    my $iowait_avg;
    my $iowait;
    while ($IOSTAT =~m/^\s+([\d\.]+)\s+([\d\.]+)\s+([\d\.]+)\s+([\d\.]+)\s+([\d\.]+)\s+([\d\.]+)$/mg) {
        if (!$iowait_avg) {
            $iowait_avg = $4;
        } else {
            $iowait = $4;
        }
    }

    my @keys = ( 'device','rrqm/s','wrqm/s','r/s','w/s','rsec/s','wsec/s','avgrq-sz','avgqu-sz','await','svctm','%util' );
    my %vals;
    while ($IOSTAT =~ m/^(\w+)\s+([\d\.]+)\s+([\d\.]+)\s+([\d\.]+)\s+([\d\.]+)\s+([\d\.]+)\s+([\d\.]+)\s+([\d\.]+)\s+([\d\.]+)\s+([\d\.]+)\s+([\d\.]+)\s+([\d\.]+)$/mg) {
        @{$vals{$1}}{@keys}  =  ($1, $2, $3, $4, $5, $6 , $7 , $8, $9, $10, $11, $12 );
    }

    my $Summary;
    my $Severity = 'green';
    my $iowait_yellow = $monitoringValues->{'iostat_iowait'}{'yellow'};
    my $iowait_red = $monitoringValues->{'iostat_iowait'}{'red'};
    if ($monitoringValues->{'iostat_iowait'}{'disabled'}) {
        $Summary = "iowait: $iowait (DISABLED)";
    } else {
        if ($iowait > $iowait_red) {
            $Summary .= "iowait: $iowait";
        } elsif ($iowait > $iowait_yellow) {
            $Severity = 'yellow';
            $Summary .= "iowait: $iowait";
        } else {
            $Summary .= "iowait: $iowait";
        }
    }
    $server->alert({AlertGroup=>'iostat_iowait', Summary=>$Summary, Severity=>$Severity, Recurring=>1}) unless ($options->{dryrun});

    unless ($options->{dryrun}) {
        foreach my $d (keys %vals) {
            $server->graph("iostat_time,$d\_avg_queue_size", $vals{$d}{'avgqu-sz'} );
            $server->graph("iostat_time,$d\_agv_wait", $vals{$d}{'await'} );
            $server->graph("iostat_time,$d\_service_time", $vals{$d}{'svctm'} );

            $server->graph("iostat_reqs,$d\_reads_per_sec", $vals{$d}{'r/s'} );
            $server->graph("iostat_reqs,$d\_writes_per_sec", $vals{$d}{'w/s'} );
            $server->graph("iostat_reqs,$d\_reads_merged_per_sec", $vals{$d}{'rrqm/s'} );
            $server->graph("iostat_reqs,$d\_writes_merged_per_sec", $vals{$d}{'wrqm/s'} );

            $server->graph("iostat_throughput,$d\_rkb_per_sec", int($vals{$d}{'rsec/s'}/2) );
            $server->graph("iostat_throughput,$d\_wkb_per_sec", int($vals{$d}{'wsec/s'}/2) );

        }
        $server->graph('iostat,iowait', $iowait);
        $server->graph('iostat,iowait_avg', $iowait_avg);
    }

    return;
}

1;
