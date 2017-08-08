package Uravo::Agent::log;

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

    my $message;
    my %count;
    my @types = $server->getTypes();
    my $Severity;
    my $Summary;

    foreach my $type (@types) {
        my $logFiles = $type->getLogs();
        unless (scalar(keys %$logFiles)) {
            #$Summary = "No log files to check.";
            #$server->alert({AlertGroup=>'log_content', Summary=>$Summary, Severity=>'green', Recurring=>1}) unless ($options->{dryrun});
            next;
        } 

        foreach my $log_id (keys %$logFiles) {
            my $log = $logFiles->{$log_id};
            my $filename = $log->{log_file};
            unless (-f $filename) {
                $Summary = "$filename doesn't exist.";
                $server->alert({AlertGroup=>'log_exists', AlertKey=>$filename, Summary=>$Summary, Severity=>'red', Recurring=>1}) unless ($options->{dryrun});
                next;
            }
            $Summary = "$filename exists.";
            $server->alert({AlertGroup=>'log_exists', AlertKey=>$filename, Summary=>$Summary, Severity=>'green', Recurring=>1}) unless ($options->{dryrun});

            my @msgs;
            my @ignore;
            foreach my $detail (@{$log->{detail}}) {
                my $regex = $detail->{regex};
                if ($regex =~/^\!/) {
                    push(@ignore, $regex);
                } else {
                    push(@msgs, $regex);
                }
            }

            my @new_messages;
            my @old_messages = split(/\|/,$server->getLast('msgs', $log_id));
            foreach my $m (@old_messages) {
                my ($time, $message) = split(/,/, $m);
                if ($time > (time() - 1800)) {
                    push @new_messages, "$time,$message";
                }
            }

            my $pos = $server->getLast('msgs_pos', $log_id) || 0;
            my $size = -s $filename;
            if (($size - 1024*1024) > $pos) {
                $pos = $size - 1024*1024;
            } elsif ($pos > $size) {
                $pos = 0;
            }
            #print "reading $filename from $pos\n";
            open(LOGFILE, $filename) or next;
            seek(LOGFILE, $pos, 0);
            while (<LOGFILE>) {
                chomp($_);
                foreach my $alertregex (@msgs) {
                    if (/$alertregex/i) {
                        my $ignore = 0;
                        if (scalar(@ignore)) {
                            foreach my $ignoreregex (@ignore) {
                                if (/$ignoreregex/i) {
                                    $ignore = 1;
                                }
                            }
                        }
                        unless ($ignore) {
                            $count{$filename}{$alertregex}++;                            
                            push @new_messages, time() . ",$_";
                        }
                    }
                }
            }
            $pos = tell LOGFILE;
            close(LOGFILE);
            @new_messages = splice(@new_messages, -25) if (scalar @new_messages > 25);
            $server->setLast('msgs_pos', $log_id, $pos) if (! $options->{dryrun});
            $server->setLast('msgs', $log_id, join('|', @new_messages)) if (! $options->{dryrun});

            foreach my $regex (@msgs) {
                my $safe_regex = lc($regex);
                $safe_regex =~s/[^\w]+//g;
                if (defined($count{$filename}{$regex}) && $count{$filename}{$regex}>0) {
                    $Severity = 'red';
                    $Summary = "$filename:/$regex/ entries:$count{$filename}{$regex}";
                } else {
                    $Severity = 'green';
                    $Summary = "$filename:/$regex/ entries:0";
                }
                $server->alert({Summary=>$Summary, Severity=>$Severity, AlertGroup=>'log_errors', AlertKey=>"${filename}_${safe_regex}", Recurring=>1}) unless ($options->{dryrun});
            }
        }
    }

    if (-f "/etc/motd" && -f "/var/cfengine/inputs/modules/module:cfe_motd.sh") {
        my $motd;
        open(MOTD, "</etc/motd");
        while(<MOTD>) {
            $motd .= $_;
        }
        close(MOTD);

        $Severity = 'green';
        if ($motd =~/^Kickstart name: (.+)$/m) {
            $Summary = "/etc/motd: Kickstart name: $1";
        } else {
            $Severity = 'red';
            $Summary = "/etc/motd: Kickstart name not found.";
        }
        $server->alert({Summary=>$Summary, Severity=>$Severity, AlertGroup=>'log_kickstart', Recurring=>1}) unless ($options->{dryrun});

        $Severity = 'green';
        if ($motd =~/^SERVERROLES: (.+)$/m) {
            $Summary = "/etc/motd: SERVERROLES: $1";
        } else {
            $Severity = 'red';
            $Summary = "/etc/motd: SERVERROLES not found.";
        }
        $server->alert({Summary=>$Summary, Severity=>$Severity, AlertGroup=>'log_role', Recurring=>1}) unless ($options->{dryrun});
    }
}

1;

