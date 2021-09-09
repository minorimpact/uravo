package Uravo::Agent::procs;

use strict;

use Data::Dumper;
use Uravo;
use Uravo::Util;

use parent 'Uravo::Agent::Module';

sub run {
    my $self = shift || return;
    my $uravo = $self->{uravo};

    my $options = $uravo->{options} || {};

    my $ps = Uravo::Util::ps();
    return unless ($ps && scalar keys %$ps);
    my $proc_count = scalar keys %$ps;
    $self->{server}->graph('procs_total',$proc_count);

    my $Severity = $self->getSeverity('procs_total', undef, $proc_count);
    my $Summary = "Found $proc_count processes";
    $self->{server}->alert({Summary=>$Summary, AlertGroup=>'procs_total', Severity=>$Severity});

    my $procs = $self->{server}->getProcs();
    return unless (scalar keys %$procs);

    my %most_common = ();
    foreach my $pid (keys %$ps) {
        $most_common{$ps->{$pid}{program}}++;
    }

    foreach my $proc (sort keys %$procs) {
        my $expr = $procs->{$proc}->{red} || '>0';

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
        my $Summary = sprintf "%-s (%s) - %d %s", $proc, $expr, $process_count, "instance".($process_count == 1 ? '' : 's');
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
        $self->{server}->alert({Summary=>$Summary, AlertGroup=>'proc_count', AlertKey=>$proc, Severity=>$Severity});
    }
}

1;
