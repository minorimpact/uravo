package Uravo::Agent::disk;

use Disk::SMART;
use Uravo;
use Uravo::Util;

use parent 'Uravo::Agent::Module'; #our @ISA = (Uravo::Agent::Module);

sub run {
    my $self = shift || return;

    my $server = $self->{server};
    my $options = $self->{options};

    my $DFCMD = '/bin/df -lk';
    my $INODE = '/bin/df -li';
    my $DFUSE = "^/dev";
    my $DFEXCLUDE = "(cdrom|netapp|usb|loop|mmcblk0p1)";
    my $RATEEXCLUDE = "(/mnt/db_snapshot)";

    my $full_df = "# $DFCMD\n";

    # get disk space output
    my $df = {};
    open(DF, "$DFCMD |");
    while (my $line = <DF>) {
        $full_df .= $line;
        chomp($line);
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
    my $inode = {};
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
        my $i = readDF($line);
        $inode->{$i->{dev}} = $i;
    }
    close(INODES);

    my $now = time();
    my $seconds = $now - ($server->getLast('disk', 'time') || $now);

    my $message = "";

    foreach my $disk (values %$df) {
        my $Severity = $self->getSeverity('disk_size', $disk->{diskname}, $disk->{percent});
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
                    my $Severity = $self->getSeverity('disk_fill', $disk->{diskname}, $timetofill);
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

    foreach my $disk (values %$inode) {
        my $Severity = $self->getSeverity('inode_size', $disk->{diskname}, $disk->{percent});
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
                    my $Severity = $self->getSeverityLT('inode_fill', $disk->{diskname}, $timetofill);
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
    if ($ENV{USER} == "root") {
        my $done_dev = {};
        foreach my $disk (values %$df) {
            my $dev = $disk->{dev};
            next unless ($dev =~s/\/dev\/sd([a-z])\d+/\/dev\/sd\1/);
            # df lists volumes, we just want to do each physical device once.
            next if (defined($done_dev->{$dev}));

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
            $Summary = sprintf("$dev disk health %s", $health);
            $server->alert({Recurring=>1, Severity=>$Severity, AlertGroup=>"disk_health", AlertKey=>$dev, Summary=>$Summary}) unless ($options->{dryrun});

            # temperature check
            my ($temp_c, $temp_f) = $smart->get_disk_temp($dev);
            my $Severity = $self->getSeverity('disk_temp', $dev, $temp_f);
            $Summary = sprintf("$dev temperature: %d", $temp_f);
            $server->alert({Recurring=>1, Severity=>$Severity, AlertGroup=>"disk_temp", AlertKey=>$dev, Summary=>$Summary}) unless ($options->{dryrun});
            $done_dev->{$dev} = 1;
        }
    }

    if ($self->{uravo}->{config}{disk_write}) {
        my @partitions = split(/,/, $self->{uravo}->{config}{disk_write});
        my $test_data = {};
        foreach my $part (@partitions) {
            $part =~s/\/$//;
            print("writing $part\n") if ($options->{verbose});
            if (!open(disk_write, '>', "$part/disk_write")) {
                $server->alert({Severity=>"red", AlertGroup=>"disk_write_open", AlertKey=>$part, Summary=>"Can't open $part/disk_write for writing", AdditionalInfo=>$@}) unless ($options->{dryrun});
                next;
            }
            $server->alert({Severity=>"green", AlertGroup=>"disk_write_open", AlertKey=>$part, Summary=>"Opened $part/disk_write for writing"}) unless ($options->{dryrun});
            $test_data->{$part} = int(rand(10000));
            print disk_write $test_data->{$part};
            close(disk_write);
        }
        sleep(1);
        foreach my $part (@partitions) {
            $part =~s/\/$//;
            next if (!defined($test_data->{$part}));
            print("reading $part\n") if ($options->{verbose});
            if (!open(disk_write, '<', "$part/disk_write")) {
                $server->alert({Severity=>"red", AlertGroup=>"disk_write_read", AlertKey=>$part, Summary=>"Can't open $part/disk_write for reading", AdditionalInfo=>$@}) unless ($options->{dryrun});
                next;
            }
            $server->alert({Severity=>"green", AlertGroup=>"disk_write_read", AlertKey=>$part, Summary=>"opened $part/disk_write for reading"}) unless ($options->{dryrun});
            read(disk_write, my $val, 5);
            close(disk_write);
            my $Severity = "green";
            my $Summary = "$part is writeable";
            if ($val != $test_data->{$part}) {
                $Severity = "red";
                $Summary = "$part is not writeable";
            }
            unlink("$part/disk_write");
            $server->alert({Recurring=>1, Severity=>$Severity, AlertGroup=>"disk_write", AlertKey=>$part, Summary=>$Summary}) unless ($options->{dryrun});
        }
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
