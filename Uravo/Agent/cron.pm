package Uravo::Agent::cron;

use Uravo;
use Uravo::Util;
use Uravo::Cron;

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
    my $server_id = $server->id();
    my $options = $uravo->{options};

    my %cron_log;
    my %clean_cron_log;
    # Collect all the cron data in one call, and parse it into a complicated hash.
    my $data = $uravo->{db}->selectall_arrayref("SELECT name, exit_status,error_output,UNIX_TIMESTAMP(start_date) AS start, UNIX_TIMESTAMP(eta_date) AS eta, UNIX_TIMESTAMP(end_date) AS end, sleep FROM cron_log WHERE server_id=?", {Slice=>{}}, ($server_id));
    foreach my $row (@$data) {
        push (@{$cron_log{$row->{name}}}, $row);
    }
    foreach my $script_name (keys %cron_log) {
        # Sort the results by date, and just keep the last 10.
        @{$cron_log{$script_name}} = sort {$a->{start} <=> $b->{start}}  @{$cron_log{$script_name}};
        splice(@{$cron_log{$script_name}}, 0, -10);

        # Later, we're going to blow away anything in the database that's older than this value in the cleaning hash.  If a crontab entry is still
        # valid, this date will get reset to the top 10th date event date.
        $clean_cron_log{$script_name} = time();
    }

    my $message;
    my @crontab_files = ("/var/spool/cron/root");
    push(@crontab_files, glob("/etc/cron.d/*"));
    foreach my $crontab_file (@crontab_files) {
        next unless (-f $crontab_file);
        print "  $crontab_file\n" if ($options->{verbose});
        foreach my $cron (split("\n",`cat $crontab_file`)) {
            print "  $cron\n" if ($options->{verbose});
            $cron =~s/^\s+//;
            next unless ($cron =~/^[\*\d]/);

            my $now = time();

            my $sleep = 0;
            if ($cron =~/sleep \$\(\(([0-9]+)\*\$RANDOM\/32767\)\)/) {
                $sleep = $1;
            }

            my $last_run = Uravo::Cron::last_run_time($cron, ($now - $sleep));

            # Find the how often this cron runs, and adjust the number of allowed failures.
            my $prev_last_run = Uravo::Cron::last_run_time($cron, $last_run - 1);
            my $cron_interval = $last_run - $prev_last_run;
            if ($cron_interval <= 300) {
                # If a cron runs every 5 minutes or faster, allow it to fail twice before alarming, so set the run
                # last run time to two times ago.
                $last_run = Uravo::Cron::last_run_time($cron, $prev_last_run - 1);
            } elsif ($cron_interval <= 3600) {
                # If a cron runs less than once an hour, allow it to fail once before alarming. Set the last run time to
                # the previous value.
                $last_run = $prev_last_run;
            }


            my %perl_scripts = ();
            while ($cron =~m/(\/[^ ]+\.pl)/g) {
                my $script = $1;
                next if ($script =~/\/tmp/);

                $cron =~/($script[^;>|]+)/;
                my $full = $1;
                $full =~s/ 2$//;
                $full =~s/\&$//;
                $full =~s/ +$//;
                $full =~s/  +/ /;
                $full =~s/"([^"]*)"/\1/g;
                $full =~s/'([^']*)'/\1/g;
                my $skey = $full;
                $skey =~s/ /_/g;
                $perl_scripts{$skey}{base} = $script;
                $perl_scripts{$skey}{full} = $full;
            }

            foreach my $skey (keys %perl_scripts) {
                my $base = $perl_scripts{$skey}{base};
                my $full = $perl_scripts{$skey}{full};

                if (! -f $base) {
                    $server->alert({Recurring=>1, AlertGroup=>'cron_exists', AlertKey=>$skey, Summary=>"$base does not exist", Severity=>'red'});
                    next;
                }            
                $server->alert({Recurring=>1, AlertGroup=>'cron_exists', AlertKey=>$skey, Summary=>"$base exists", Severity=>'green'});

                if (!`/bin/grep -e "^[^#]*Uravo::Cron::execCron" $base`) {
                    next;
                }

                my $color = 'green';

                # The last item in the array is the most recently run script.
                my $data = $cron_log{$full}[scalar(@{$cron_log{$full}}) - 1];
                if (!$data->{start}) {
                    # Script has never been run.

                    $server->alert({Recurring=>1, AlertGroup=>'cron_end_time', AlertKey=>$skey, Summary=>"end date check not applicable.", Severity=>'green'});
                    $server->alert({Recurring=>1, AlertGroup=>'cron_exit_status', AlertKey=>$skey, Summary=>"exit status check not applicable.", Severity=>'green'});

                    my $mtime = (stat($base))[9];
                    if ($mtime > $last_run) {
                        $server->alert({Recurring=>1, AlertGroup=>'cron_start_time', AlertKey=>$skey, Summary=>"$full has never been run, but $base was modified after last run time: (" . localtime($mtime) . " > " . localtime($last_run) . ")", Severity=>'green'});
                    } else {
                        $server->alert({Recurring=>1, AlertGroup=>'cron_start_time', AlertKey=>$skey, Summary=>"$full has never been run", Severity=>'red'});
                    }
                } elsif (!$data->{end}) {
                    # Script is still running.

                    $server->alert({Recurring=>1, AlertGroup=>'cron_start_time', AlertKey=>$skey, Summary=>"$full started at " . localtime($data->{start}) , Severity=>'green'});
                    $server->alert({Recurring=>1, AlertGroup=>'cron_exit_status', AlertKey=>$skey, Summary=>"exit status check not applicable.", Severity=>'green'});

                    # Collect the eta value.
                    my $eta = $data->{eta};
                    if (!$eta) {
                        # 'eta' value wasn't set in the execCron parameters.  Get it from the cron_eta table.
                        my $eta_data = $uravo->{db}->selectrow_hashref("SELECT eta FROM cron_eta WHERE name = ?", undef, ($full));
                        if (!$eta_data) {
                            # There's no entry in cron_eta.  Create a value with a null record, and leave $eta blank.
                            $uravo->{db}->do("INSERT INTO cron_eta (name, eta, create_date) VALUES (?, NULL, NOW())", undef, ($full));
                        } elsif ($eta_data->{eta} > 0) {
                            # There's a cron_eta record, and it's positive. Use that to determine how when this script should complete.
                            $eta = $data->{start} + ($eta_data->{eta} * 60) + ($data->{sleep} || 0);
                        } 
                    }

                    # Check and see if the script is past the designated eta time, if it's defined.  Just set the alarm green if 
                    # it's not.
                    if ($eta && $now > ($eta + 300)) {
                        $server->alert({Recurring=>1, AlertGroup=>'cron_end_time', AlertKey=>$skey, Summary=>"$full should have completed by: " . localtime($eta), Severity=>'red', AdditionalInfo=>$cron});
                    } elsif ($eta && $now > $eta) {
                        $server->alert({Recurring=>1, AlertGroup=>'cron_end_time', AlertKey=>$skey, Summary=>"$full should have completed by: " . localtime($eta), Severity=>'yellow', AdditionalInfo=>$cron});
                    } else {
                        $server->alert({Recurring=>1, AlertGroup=>'cron_end_time', AlertKey=>$skey, Summary=>"$full is still running.", Severity=>'green'});
                    }
                } else {
                    # No instance is currently running.


                    # Check and see if the script ran the last time it was supposed to.
                    if ($data->{start} < $last_run && $data->{end} <= $last_run) {
                        # Script hasn't run since the before the computed 'last' run time.
                        $server->alert({Recurring=>1, AlertGroup=>'cron_start_time', AlertKey=>$skey, Summary=>"$full should have run at  " . localtime($last_run), Severity=>'red', AdditionalInfo=>$cron});
                        $server->alert({Recurring=>1, AlertGroup=>'cron_end_time', AlertKey=>$skey, Summary=>"$full ended at " . localtime($data->{end}), Severity=>'green', AdditionalInfo=>$cron});
                    } elsif ($data->{start} < $last_run && $data->{end} > $last_run) {
                        # No script started since the last run time, but the previous script was
                        # still running when the new one should have started.
                        $server->alert({Recurring=>1, AlertGroup=>'cron_start_time', AlertKey=>$skey, Summary=>"$full started at " . localtime($data->{start}), Severity=>'green', AdditionalInfo=>$cron});
                        $server->alert({Recurring=>1, AlertGroup=>'cron_end_time', AlertKey=>$skey, Summary=>"$full ended at " . localtime($data->{end}), Severity=>'green', AdditionalInfo=>$cron});
                    } else {
                        $server->alert({Recurring=>1, AlertGroup=>'cron_start_time', AlertKey=>$skey, Summary=>"$full started at " . localtime($data->{start}), Severity=>'green', AdditionalInfo=>$cron});
                        $server->alert({Recurring=>1, AlertGroup=>'cron_end_time', AlertKey=>$skey, Summary=>"$full ended at " . localtime($data->{end}), Severity=>'green', AdditionalInfo=>$cron});
                    }

                    # Check the exit status.
                    if ($data->{exit_status}) {
                        my $Severity = 'red';
                        if ($data->{exit_status} > 0) {
                            $Severity = 'green';
                        }

                        my $addinfo;
                        if ($data->{error_output}) {
                            $addinfo .= "ADDINFO:";
                            foreach my $line (split(/\n/, $data->{error_output})) {
                                $addinfo .= $line . "_CR_";
                            }
                        }
                        $server->alert({Recurring=>1, AlertGroup=>'cron_exit_status', AlertKey=>$skey, Summary=>"$full exit status: " . $data->{exit_status}, Severity=>$Severity, AdditionalInfo=>$addinfo});
                    } else {
                        $server->alert({Recurring=>1, AlertGroup=>'cron_exit_status', AlertKey=>$skey, Summary=>"$full exit status: " . $data->{exit_status}, Severity=>'green', AdditionalInfo=>$cron});
                    }
                }
                
                # This script is live, so set the date in the cleaning hash to the oldest value in our array
                # (which we already cut down to the 10 most recent items when we built it).
                $clean_cron_log{$full} = $cron_log{$full}[0]->{start};
            }
        }
    }

    foreach my $script (keys %clean_cron_log) {
        # Blow away anything older than the date in the cleaning hash.  For any script that wasn't listed in the 
        # crontab, this will be all items.  This is how we maintain a self-cleaning cron_log database.
        $uravo->{db}->do("DELETE FROM cron_log WHERE server_id=? AND name=? AND start_date < FROM_UNIXTIME(?)", undef, ($server_id, $script, $clean_cron_log{$script}));
    }
}

1;
