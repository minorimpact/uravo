package Uravo::Agent::run;

use Uravo;
use Uravo::Util;

use parent 'Uravo::Agent::Module';

sub run {
    my $self = shift || return;
    my $uravo = $self->{uravo};

    my $options = $uravo->{options};

    my $run_dir = $uravo->{config}{run_dir} || '/opt/uravo/run';
    my $runtime = (stat("$run_dir/crond.running"))[9];
    my $time = time;
    my $Summary;
    my $Severity = 'green';
    if ($time >= ($runtime + 300)) {
        $Severity = 'red';
        $Summary = "crond hasn't run since " . localtime($runtime);
    } elsif ($runtime > $time) {
        $Severity = 'yellow';
        $Summary = "crond last run in the future";
    } else {
        $Summary = "crond last run " . localtime($runtime);
    }

    $self->{server}->alert({AlertGroup=>'run_crond', Summary=>$Summary, Severity=>$Severity, Recurring=>1}) unless ($options->{dryrun});
}  

1;
