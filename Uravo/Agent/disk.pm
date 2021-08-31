package Uravo::Agent::disk;

use Disk::SMART;
use Uravo;
use Uravo::Util;

my $uravo;

sub new {
    my $self = {};

    my $class = shift || return;

    $uravo = new Uravo;

    bless($self, $class);
    return $self;
}

sub run {
    my $self = shift || return;
    my $server = $uravo->getServer() || return;

    my $options = $uravo->{options};
    my $monitoringValues = $server->getMonitoringValues();

    my $DFCMD = '/bin/df -lk';
    my $INODE = '/bin/df -li';
    my $DFUSE = "^/dev";
    my $DFEXCLUDE = "(cdrom|netapp|usb|loop)";
    my $RATEEXCLUDE = "(/mnt/db_snapshot)";

    my $full_df = "# $DFCMD\n";

    # get disk space output
    my @df = ();
    open(DF, "$DFCMD |");
    while (my $line = <DF>) {
        $full_df .= $line;
        chomp($line);
        # handle this case:
        # [root@de30-203 (11:09:57) ~]# df -k /var/lib/mysql
        # Filesystem           1K-blocks      Used Available Use% Mounted on
        # /dev/mapper/db-db_data
        #                      123854820  32491340  85072024  28% /var/lib/mysql
        if (split(/\s+/, $line) == 1) {
            my $line2 = <DF>;
            $line .= $line2;
            $full_df .= $line2;
            chomp $line;
        }
        next if ($line =~ /$DFEXCLUDE/);
        next unless ($line =~ /$DFUSE/);
        $d = readDF($line);
        $df->{$d->{dev}} = $d;
    }
    close(DF);

    # now, inodes
    my @inode = ();
    my $full_inode = "# $INODE\n";
    open(INODES, "$INODE |");
    while (my $line = <INODES>) {
        $full_inode .= $line;
        if (split(/\s+/, $line) == 1) {
            my $line2 = <INODES>;
            $line .= $line2;
            $full_inode .= $line2;
            chomp $line;
        }
        chomp($line);
        next if ($line =~ /$DFEXCLUDE/);
        next unless ($line =~ /$DFUSE/);
        push @inode, $line;
    }
    close(INODES);

    my $now = time();
    my $seconds = $now - ($server->getLast('disk', 'time') || $now);

    my $message = "";

    foreach my $disk (values %$df) {
        my $Severity = "green";
        if (!$monitoringValues->{'disk_size'}{'disabled'} && $disk->{percent} >= $monitoringValues->{'disk_size'}{'red'}) {
            $Severity = "red";
        } elsif (!$monitoringValues->{'disk_size'}{'disabled'} && $disk->{percent} >= $monitoringValues->{'disk_size'}{'yellow'}) {
            $Severity = "yellow";
        }
        $Summary = "$disk->{diskname} ($disk->{percent}% full)";
        $server->graph("disk_size.$disk->{diskname}", $disk->{percent});
        $server->alert({Severity=>$Severity, AlertGroup=>'disk_size', AlertKey=>$disk->{diskname}, Summary=>$Summary, Recurring=>1}) unless ($options->{dryrun});

        # db_snapshot is only mounted during backups, and will always show a heavy write rate.
        unless ($disk->{diskname} =~ /$RATEEXCLUDE/) {
            my $last_used = $server->getLast('disk_fill', $disk->{diskname});
            if ($seconds > 0) {
                my $rate = ($used - $last_used)/$seconds;
                my $timetofill = ($rate > 0) ? ($available / $rate) / 60:0;

                if ($timetofill) {
                    my $Severity = "green";
                    if (!$monitoringValues->{'disk_fill'}{'disabled'} && $timetofill < $monitoringValues->{'disk'}{'rate'}{'red'}) {
                        $Severity = "red";
                    } elsif (!$monitoringValues->{'disk_fill'}{'disabled'} && $timetofill < $monitoringValues->{'disk'}{'rate'}{'yellow'}) {
                        $Severity = "yellow";
                    }
                    $Summary = sprintf("$disk->{diskname} will be full in approximately %s", days($timetofill));
                    $server->alert({Recurring=>1, Severity=>$Severity, AlertGroup=>"disk_fill", AlertKey=>$disk->{diskname}, Summary=>$Summary }) unless ($options->{dryrun});
                } else {
                    $Summary = "$disk->{diskname} has not changed size in the last 5 minutes.";
                    $server->alert({Recurring=>1, Severity=>"green", AlertGroup=>"disk_fill", AlertKey=>$disk->{diskname}, Summary=>$Summary }) unless ($options->{dryrun});
                }
            } else {
                $Summary = "$disk->{diskname} check run too soon.";
                $server->alert({Recurring=>1, Severity=>"green", AlertGroup=>"disk_fill", AlertKey=>$disk->{diskname}, Summary=>$Summary}) unless ($options->{dryrun});
            }
            $server->setLast('disk_fill', $disk->{diskname}, $used) unless ($options->{dryrun});
        }
    }

    foreach my $disk (values %$df) {
        my $Severity = "green";
        if ($disk->{percent} >= $monitoringValues->{inode_size}{red} && !$monitoringValues->{inode_size}{disabled}) {
            $Severity = "red";
        } elsif ($disk->{percent} >=  $monitoringValues->{inode_size}{yellow} && !$monitoringValues->{inode_size}{disabled}) {
            $Severity = "yellow";
        }
        $Summary = "$disk->{diskname} inodes used: $disk->{percent}%";
        $server->graph("inode_size", $disk->{percent});
        $server->alert({Recurring=>1, Severity=>$Severity, AlertGroup=>"inode_size", AlertKey=>$disk->{diskname}, Summary=>$Summary}) unless ($options->{dryrun});

        # db_snapshot is only mounted during backups, and will always show a heavy write rate.
        unless ($disk->{diskname} =~ /$RATEEXCLUDE/) {
            my $last_inode = $server->getLast('inode_fill', "$disk->{diskname}");
            if ($seconds > 0) {
                my $rate = ($disk->{current} - $last_inode)/$seconds;
                my $timetofill = ($rate > 0) ? ($available / $rate) / 60:0;

                if ($timetofill) {
                    my $Severity = 'green';
                    if ($timetofill <  $monitoringValues->{inode_fill}{red} && !$monitoringValues->{inode_fill}{disabled}) {
                        $Severity = "red";
                    } elsif ($timetofill < $monitoringValues->{inode_fill}{yellow} && !$monitoringValues->{inode_fill}{disabled}) {
                        $Severity = "yellow";
                    }
                    $Summary = sprintf("$disk->{diskname} will run out of inodes in approximately %s", days($timetofill));
                    $server->alert({Recurring=>1, Severity=>$Severity, AlertGroup=>"inode_fill", AlertKey=>$disk->{diskname}, Summary=>$Summary}) unless ($options->{dryrun});
                } else {
                    $Summary = "$disk->{diskname} inode usage has not increased.";
                    $server->alert({Recurring=>1, Severity=>"green", AlertGroup=>"inode_fill", AlertKey=>$disk->{diskname}, Summary=>$Summary }) unless ($options->{dryrun});
                }
            } else {
                $Summary = "Run too soon.";
                $server->alert({Recurring=>1, Severity=>"green", AlertGroup=>"inode_fill", AlertKey=>$disk->{diskname}, Summary=>$Summary }) unless ($options->{dryrun});
            }
            $server->setLast('inode_fill', "$disk->{diskname}", $disk->{current}) unless ($options->{dryrun});
        }
    }

    # Check SMART values, if available
    foreach my $disk (values %$df) {
        my $dev = $disk->{dev};
        next unless ($dev =~s/\/dev\/sd([a-z])\d+/\/dev\/sd\1/);
        my $smart;
        eval {
            $smart = Disk::SMART->new($dev);
        };
        next if (!defined($smart) or $@);

        # health check
        my $Severity = "green";
        my $health = $smart->get_disk_health($dev);
        if ($health != "PASSED") {
            $Severity = "red";
        }
        $Summary = sprintf("$disk->{diskname} disk health %s", $health);
        $server->alert({Recurring=>1, Severity=>$Severity, AlertGroup=>"disk_health", AlertKey=>$disk->{diskname}, Summary=>$Summary}) unless ($options->{dryrun});

        # temperature check
        my $Severity = "green";
        my ($temp_c, $temp_f) = $smart->get_disk_temp($dev);
        if ($temp_f <  $monitoringValues->{disk_temp}{red} && !$monitoringValues->{disk_smart_temp}{disabled}) {
            $Severity = "red";
        } elsif ($temp_f < $monitoringValues->{disk_temp}{yellow} && !$monitoringValues->{disk_smart_temp}{disabled}) {
            $Severity = "yellow";
        }
        $Summary = sprintf("$disk->{diskname} temperature: %d", $temp_f);
        $server->alert({Recurring=>1, Severity=>$Severity, AlertGroup=>"disk_temp", AlertKey=>$disk->{diskname}, Summary=>$Summary}) unless ($options->{dryrun});
    }

    $server->setLast('disk', 'time', time()) unless ($options->{dryrun});
}

sub readDF {
    my $df_text = shift;
    my $diskname = "";
    my $percent = "";
    my $dev = "";
    my $current = 0;
    my $available = 0;

    my @dfline = split(/\s+/, $df_text);

    $dev = $dfline[0];
    $current = $dfline[2];
    $available = $dfline[3];
    $percent = $dfline[4];
    $diskname = $dfline[5];
    $percent =~ s/\%//;
    
    return {dev=>$dev, current=>$current, available=>$available, diskname=>$diskname, percent=>$percent};
}

sub days {
    my $minutes = shift;

    my $then = time;
    my $now = $then + int($minutes * 60);

    my $difference = $now - $then;

    my $seconds = $difference % 60;
    $difference = ($difference - $seconds) / 60;
    my $second_s = ($seconds == 1)?"":"s";

    $minutes = $difference % 60;
    $difference = ($difference - $minutes) / 60;
    my $minute_s = ($minutes == 1)?"":"s";

    my $hours = $difference % 24;
    $difference = ($difference - $hours) / 24;
    my $hour_s = ($hours == 1)?"":"s";

    my $days = $difference;
    my $day_s = ($days == 1)?"":"s";

    return "$days day$day_s, $hours hour$hour_s and $minutes minute$minute_s";
}

1;
