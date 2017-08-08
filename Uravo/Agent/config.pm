package Uravo::Agent::config;

use Uravo;
use Uravo::Util;
use Date::Manip;

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

    my $Summary = '';
    my $splay_time;
    my $log_file;
    my $type;

    if ( $server->get('config') eq 'cfengine' || -f "/usr/sbin/cfagent") {
        $log_file = "/tmp/cfagent.log";
        $splay_time = 15;
        $type = 'cfengine';
    } elsif ($server->get('config') eq 'puppet' || -f "/usr/bin/puppet") {
        $log_file = "/var/lib/puppet/state/last_run_summary.yaml";
        $splay_time = 5;
        $type = 'puppet';
    }

    if ($log_file && -f $log_file) {
        #$Summary = "$log_file doesn't exist.";
        #$server->alert({AlertGroup=>'config_log_file', Severity=>'green', Summary=>$Summary, Recurring=>1}) unless ($options->{dryrun});
        my $now = time();
        my $mtime = (stat($log_file))[9];

        my $Severity = 'green';
        if (! open(LOGFILE, $log_file)) {
            $Severity = 'red';
            $Summary = "$log_file exists but cannot be opened for parsing.";
            $server->alert({AlertGroup=>'config_log_file_read', Severity=>$Severity, Summary=>$Summary, Recurring=>1}) unless ($options->{dryrun});
        } else {
            $Summary = "$log_file exists and can be opened for parsing.";
            $server->alert({AlertGroup=>'config_log_file_read', Severity=>'green', Summary=>$Summary, Recurring=>1}) unless ($options->{dryrun});

            if ( -z $log_file) {
                # cfagent has a built-in, random delay.  If the file is empty, and was created in the last $splay_time minutes
                # it's not an error.
                if (($now - $mtime) < ($splay_time * 60)) {
                    $Summary = "$log_file is empty, but is less than $splay_time minutes old.";
                } else {
                    $Severity = 'red';
                    $Summary = "$log_file is empty.";
                }
                $server->alert({AlertGroup=>'config_log_file_empty', Severity=>$Severity, Summary=>$Summary, Recurring=>1}) unless ($options->{dryrun});
            } else {
                $Summary = "$log_file is not empty.";
                $server->alert({AlertGroup=>'config_log_file_empty', Severity=>'green', Summary=>$Summary, Recurring=>1}) unless ($options->{dryrun});

                my $log_data;
                while (my $line = <LOGFILE>) {
                    $log_data .= $line;
                }
                close(LOGFILE);
                if ($type eq 'cfengine') {
                    my $start_date;
                    $Severity = 'green';
                    if ($log_data =~/^Reference time set to (.*)$/m) {
                        $start_date = UnixDate(ParseDate($1), "%s")
                    }
                    my $still_running = ($start_date && (($now - $start_date) < ($monitoringValues->{'config_runtime'}{yellow} * 60)))?1:0;

                    if ($log_data =~ /(Package install command was not successful)/ && !$still_running) {
                        $Severity = 'red';
                        $Summary = "Package install failed.";
                    } elsif (!$still_running) {
                        $Summary = "Package install succeeded or was not attempted.";
                    } else {
                        $Summary = "Still within $monitoringValues->{'config_runtime'}{yellow} minutes of cfengine's start time of " . localtime($start_date);
                    }
                    $server->alert({AlertGroup=>'config_install', Severity=>$Severity, Summary=>$Summary, Recurring=>1}) unless ($options->{dryrun});

                    $Severity = 'green';
                    my $promisesnotkept_yellow = $monitoringValues->{'config_promises'}{'yellow'};
                    my $promisesnotkept_red = $monitoringValues->{'config_promises'}{'red'};
                    if ($log_data =~/Promises not (kept|repaired)\s+(\d+)%/ && !$still_running) {
                        my $promisesnotkept = $2;
                        if ($promisesnotkept >= $promisesnotkept_red) {
                            $Severity = 'red';
                            $Summary = "Promises not kept: $promisesnotkept%";
                        } elsif ($promisesnotkept >= $promisesnotkept_yellow) {
                            $Severity = 'yellow';
                            $Summary = "Promises not kept: $promisesnotkept%";
                        } else {
                            $Summary = "Promises not kept: $promisesnotkept%";
                        }
                    } elsif (!$still_running) {
                        $Severity = 'red';
                        $Summary = "Promises not kept value not present in $log_file."
                    } else {
                        $Summary = "Still within $monitoringValues->{'config_runtime'}{yellow} minutes of cfengine's start time of " . localtime($start_date);
                    }
                    $server->alert({AlertGroup=>'config_promises', Severity=>$Severity, Summary=>$Summary, Recurring=>1}) unless ($options->{dryrun});
                } elsif ($type eq 'puppet') {
                    $Severity = 'green';
                    $Summary = "No puppet event failures.";
                    if ($log_data =~/failure: ([0-9]+)/) {
                        my $event_failures = $1;
                        $Severity = "red" if ($event_failures > 0);
                        $Summary = "puppet event failures: $event_failures";
                    }
                    $server->alert({AlertGroup=>'config_event_failures', Severity=>$Severity, Summary=>$Summary, Recurring=>1}) unless ($options->{dryrun});

                    $Severity = 'green';
                    $Summary = "No puppet resource failures.";
                    if ($log_data =~/failed: ([0-9]+)/) {
                        my $resource_failures = $1;
                        $Severity = "red" if ($resource_failures > 0);
                        $Summary = "puppet resource failures: $resource_failures";
                    }
                    $server->alert({AlertGroup=>'config_resource_failures', Severity=>$Severity, Summary=>$Summary, Recurring=>1}) unless ($options->{dryrun});
                }
            }
        }
    } else {
        #$Summary = "$log_file doesn't exist.";
        #$server->alert({AlertGroup=>'config_log_file', Severity=>'green', Summary=>$Summary, Recurring=>1}) unless ($options->{dryrun});
    }

    return;
}

1;
