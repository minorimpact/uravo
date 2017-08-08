package Uravo::Agent::procs;

use strict;

use Uravo;
use Uravo::Util;
use Data::Dumper;

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

    my $options = $uravo->{options} || {};
    my $server_id = $server->id();
    my $monitoringValues = $server->getMonitoringValues();
    my $Severity;

    my $ps = Uravo::Util::ps();
    return unless ($ps && scalar keys %$ps);
    my $proc_count = scalar keys %$ps;

    # Check maximum process count.
    my $panic = $monitoringValues->{procs_total}{red};
    my $warn = $monitoringValues->{procs_total}{yellow};

    $Severity = 'green';
    my $proc_count = scalar keys %$ps;
    $server->graph('procs_total',$proc_count);
    if ($proc_count >= $panic && !$monitoringValues->{procs_total}{disabled}) {
        $Severity = 'red';
    } elsif ($proc_count >= $warn && !$monitoringValues->{procs_total}{disabled}) {
        $Severity = 'yellow';
    }
    my $Summary = "Found $proc_count processes";
    $server->alert({Summary=>$Summary, AlertGroup=>'procs_total', Severity=>$Severity});

    my $procs = $server->getProcs();
    return unless (scalar keys %$procs);

    my %most_common = ();
    foreach my $pid (keys %$ps) {
        $most_common{$ps->{$pid}{program}}++;
    }

    foreach my $proc (sort keys %$procs) {
        my $expr = $procs->{$proc} || '>=1';

        my $process_count = 0;
        my $defunct_count = 0;
        foreach my $pid (keys %$ps) {
            if ($ps->{$pid}{program} =~ /$proc/i) {
                if ($ps->{$pid}{status} =~ /(defunct|dead)/) {
                    $defunct_count++;
                } else {
                    $process_count++;
                }
            }
        }

        my $Severity = 'green';
        my $Summary = sprintf "%-s (%s) - %3d %s", $proc, $expr, $process_count, "instance".($process_count == 1 ? '' : 's')." running";
        $expr = "=$expr" if ($expr =~/^=[0-9]+/);
        my $true = "";
        eval "\$true = (\$process_count $expr)";
        unless ($true) {
            if ($defunct_count) {
                # transient error
                $Severity = 'yellow';
                $Summary .= " - $defunct_count defuct processes present: transient error";
            } else {
                $Severity = 'red';
            }
        }
        $server->alert({Summary=>$Summary, AlertGroup=>'proc_count', AlertKey=>$proc, Severity=>$Severity});
    }
}

1;
