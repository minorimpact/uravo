#!/usr/bin/perl

use strict;
use lib "/usr/local/uravo/lib";
use MIME::Lite;
use Uravo;
use Uravo::Util;
use Getopt::Long;
use Carp;
use Data::Dumper;
use Time::HiRes qw(gettimeofday tv_interval);

my $uravo = new Uravo;
my $options  = $uravo->{options};
my $load_time = time() - 60;

my $rc = GetOptions($options, qw/help verbose force debug/);

if (! $rc || $options->{help}) {
    print "Usage: $0 <options/values>\n";
    print "  --help       - this screen\n";
    print "  --verbose    - turn on debugging\n";
    print "  --force      - run even if one is already running\n";
    print "  --debug      - turn on debug output\n";
    return;
}

my $debug = $options->{debug};

if (! $options->{force} && Uravo::Util::CheckForDuplicates(1, 0, 0, 0, $uravo->{config}{run_dir})) {
    print "Already running one of these\n" if ($options->{verbose});
    exit;
}

print "DEBUG: ON\n" if ($debug);

my $db = $uravo->{db};

my $automations = { 
    email => { runtime=>time(), function=>\&email_notifications },
    tsunami => { runtime=>time(), function=>\&purple_tsunami },
    rootcause => { runtime=>time(), function=>\&rootcause },
    depth => { runtime=>time(), function=>\&calculate_depth },
    cleanup => { runtime=>time(), function=>\&cleanup },
};

while(1) {
    my $now = time();
    if ($now > ($load_time + 60)) {
        # Run periodic processes.
        print "reloading uravo object\n" if ($debug);
        $uravo->reload();
        $load_time = $now;

        foreach my $key (keys %$automations) {
            if ($automations->{$key}->{runtime} <= $now) { 
                print "running automation: $key\n" if ($debug);
                eval {
                    $automations->{$key}->{function}->(); 
                };
                print STDERR $@ if ($@);
                my $interval = $uravo->{settings}->{"${key}_interval"} || 1;
                $automations->{$key}->{runtime} = ($now + ($interval * 60));
            }
        }
    }

    my $t0;
    my $sql;

    # Process new alerts.
    $t0 = [gettimeofday];
    $sql = "SELECT * FROM new_alert";
    my @alerts = @{$uravo->{db}->selectall_arrayref($sql, {Slice=>{}})};
    printf("%f:%s\n", tv_interval($t0), $sql) if ($debug);
    foreach my $alert (@alerts) {
        my $t1 = [gettimeofday];
        my $Serial = $alert->{Serial};
        print "Serial=$Serial, $alert->{Identifier}\n" if ($debug);
        # TODO: check to see if AlertGroup exists in monitoring_default_values and add it if it doesn't --
        #       it will be easier to adjust a threshold that already exists than to have to remember what
        #       we called it.

        # Process the alert.
        $t0 = [gettimeofday];
        $sql = "SELECT Tally FROM alert WHERE Identifier=?";
        my $a = $db->selectrow_hashref($sql, undef, ($alert->{Identifier}));
        printf("%f:%s\n", tv_interval($t0), $sql) if ($debug);
        $alert->{Tally} = 1;
        if ($a) {
            $alert->{Tally} = $a->{Tally} + 1;
        }

        $t0 = [gettimeofday];
        $sql = "select type_id, count(*) as c from server_type where type_id in (select distinct(type_id) from server_type where server_id=?) group by type_id order by 2 limit 1";
        $alert->{type_id} = $db->selectrow_hashref($sql, undef, ($alert->{server_id}))->{type_id};
        printf("%f:%s\n", tv_interval($t0), $sql) if ($debug);

        delete($alert->{Serial});
        $t0 = [gettimeofday];
        $sql = "INSERT INTO processed_alert (`" . join("`,`", sort keys %$alert) . "`) values (" . join(",", map { '?' } keys %$alert) .")";
        $db->do($sql, undef, (map { $alert->{$_}} sort keys %$alert)) || die($db->errstr);
        printf("%f:%s\n", tv_interval($t0), $sql) if ($debug);

        $t0 = [gettimeofday];
        $sql = "DELETE FROM new_alert WHERE Serial=?";
        $db->do($sql, undef, ($Serial)) || die ($db->errstr);
        printf("%f:%s\n", tv_interval($t0), $sql) if ($debug);
        printf("%f\n", tv_interval($t1)) if ($debug);
    }
 
    # Apply actions to new alerts after they're processed, but before they're moved into the alerts table.
    foreach my $action (@{$uravo->{db}->selectall_arrayref("SELECT * FROM action ORDER BY actionorder", {Slice=>{}})}) {
        my $sql;
        my $where_str = $action->{where_str};
        $where_str =~s/type_id/server_type.type_id/g;
        $where_str =~s/server_id/processed_alert.server_id/g;

        if ($action->{action} eq 'raise') {
            # Increase the severity of the matching alerts.
            $sql = "UPDATE processed_alert JOIN server_type ON server_type.server_id=processed_alert.server_id SET Severity=Severity+1 WHERE Severity > 0 AND Severity < 5 AND $where_str";
        } elsif ($action->{action} eq 'lower') {
            # Lower the severity of the matching alerts.
            $sql = "UPDATE processed_alert JOIN server_type ON server_type.server_id=processed_alert.server_id SET Severity=Severity-1 WHERE Severity > 1 AND $where_str";
        } elsif ($action->{action} eq 'discard') {
            # Discard these matching alerts.
            $sql = "DELETE processed_alert from processed_alert JOIN server_type ON server_type.server_id=processed_alert.server_id WHERE $where_str";
        } elsif ($action->{action} eq 'hide') {
            # Hide these alerts that match the regular expression.
            $sql = "UPDATE processed_alert JOIN server_type ON server_type.server_id=processed_alert.server_id SET SuppressEscl=5 WHERE $where_str";
        }
        if ($sql) {
            $t0 = [gettimeofday];
            $uravo->{db}->do($sql) || die $uravo->{db}->errstr;
            printf("%f:%s\n", tv_interval($t0), $sql) if ($debug);
        }
    }

    # Move processed alerts into the main alerts table.
    $t0 = [gettimeofday];
    $sql = "SELECT * FROM processed_alert";
    my @alerts = @{$uravo->{db}->selectall_arrayref($sql, {Slice=>{}})};
    printf("%f:%s\n", tv_interval($t0), $sql) if ($debug);
    foreach my $alert (@alerts) {
        my $t1 = [gettimeofday];
        my $Serial = $alert->{Serial};
        print "Serial=$Serial, $alert->{Identifier}\n" if ($debug);

        # Add new alert.
        $t0 = [gettimeofday];
        $sql = "INSERT INTO alert (`" . join("`,`", sort keys %$alert) . "`, FirstOccurrence, LastOccurrence, EventLevel) values (" . join(",", map { '?' } keys %$alert) .", NOW(), NOW(), 10) ON DUPLICATE KEY UPDATE Tally=Tally+1, LastOccurrence=NOW(), Severity=?, Summary=?, AdditionalInfo=?, type_id=?";
        $db->do($sql, undef, ((map { $alert->{$_}} sort keys %$alert), $alert->{Severity}, $alert->{Summary}, $alert->{AdditionalInfo}, $alert->{type_id}, $alert->{Identifier})) || die($db->errstr);
        printf("%f:%s\n", tv_interval($t0), $sql) if ($debug);

        $t0 = [gettimeofday];
        $sql = "DELETE FROM processed_alert WHERE Serial=?";
        $db->do($sql, undef, ($Serial)) || die ($db->errstr);
        printf("%f:%s\n", tv_interval($t0), $sql) if ($debug);
        printf("%f\n", tv_interval($t1)) if ($debug);
    }

    # Generate timeout alerts.
    foreach my $alert (@{$uravo->{db}->selectall_arrayref("SELECT * FROM alert_summary WHERE mod_date < NOW() - INTERVAL ? MINUTE AND recurring=1 AND reported=0", {Slice=>{}}, ($uravo->{settings}->{alert_timeout}))}) {
        print "generating timeout alert for $alert->{server_id}/$alert->{AlertGroup}\n" if ($debug);
        $uravo->alert({server_id=>$alert->{server_id}, AlertGroup=>'timeout', AlertKey=>"$alert->{AlertGroup}", Summary=>"No new $alert->{AlertGroup} alerts from $alert->{Agent}", Severity=>"red", Agent=>$alert->{Agent}});
        $uravo->{db}->do("UPDATE alert_summary SET reported=1 WHERE server_id=? AND AlertGroup=?", undef, ($alert->{server_id}, $alert->{AlertGroup})) || die($uravo->{db}->errstr);
    }

    sleep 1;
}

# Generate a separate alert for if a whole mess of processes stop reporting
# all at once.
sub purple_tsunami {
    my $purple_count = $uravo->{db}->selectrow_hashref("SELECT COUNT(*) AS purples FROM alert WHERE AlertGroup = 'timeout' and Severity > 0")->{purples}|| 0;
    my $tsunami_warnings = $uravo->{db}->selectrow_hashref("SELECT COUNT(*) AS warnings FROM alert WHERE AlertGroup = 'purple_tsunami' and Severity > 0")->{warnings}|| 0;
    if ($purple_count > $uravo->{settings}->{tsunami_level}) {
        $uravo->alert({server_id=>'global', AlertGroup=>'purple_tsunami', Summary=>"$purple_count purples in the system.", Severity=>"red"});
    } elsif ($tsunami_warnings) {
        $uravo->alert({server_id=>'global', AlertGroup=>'purple_tsunami', Summary=>"$purple_count purples in the system.", Severity=>"green"});
    }
}

# Send out email notifications.
sub email_notifications {
    print "email_notification()\n"  if ($debug);
    my $alerts = $db->selectall_arrayref("SELECT * FROM alert WHERE Severity >= $uravo->{settings}->{minimum_severity} and SuppressEscl < 4 AND Acknowledged IS NULL and EventLevel >=10 and ParentIdentifier IS NULL", {Slice=>{}});

    foreach my $alert (@$alerts) {
        my $server = $uravo->getServer($alert->{server_id}) || next;
        my $contact_group = $server->getContactGroup($alert->{AlertGroup});
        print "server_id='$alert->{server_id}',AlertGroup='$alert->{AlertGroup}',contact_group='$contact_group'\n" if ($debug);
        next if (!$contact_group || $contact_group eq 'NONE');
        my $contacts = $uravo->{db}->selectrow_hashref("SELECT * FROM contacts WHERE contact_group=?", undef, ($contact_group));

        my $to;
        $to =  $contacts->{primary_email} if ($contacts->{primary_email});
        $to .= ",$contacts->{primary_pager}" if ($alert->{AlertCount} > 1 && $contacts->{primary_pager});
        $to .= ",$contacts->{secondary_email}" if ($alert->{AlertCount} > 1 && $contacts->{secondary_email});
        $to .= ",$contacts->{secondary_pager}" if ($alert->{AlertCount} > 3 && $contacts->{secondary_pager});
        $to .= ",$contacts->{tertiary_email}" if ($alert->{AlertCount} > 3 && $contacts->{tertiary_email});
        $to .= ",$contacts->{tertiary_pager}" if ($alert->{AlertCount} > 5 && $contacts->{tertiary_pager});

        $to =~s/^,//;

        if ($to) {
            my $message = <<MESSAGE;
$alert->{server_id} $alert->{AlertGroup}.$alert->{AlertKey}: $alert->{Summary}
Alert Number:    ${\ ($alert->{AlertCount}+1); }
Additional Info: $alert->{AdditionalInfo}
MESSAGE
            print "From=>$uravo->{settings}->{from_address}, To=>$to, Subject=>$alert->{server_id}  $alert->{AlertGroup}/$alert->{AlertKey}: $alert->{Summary}, Message=>$message\n" if ($debug);
            my $msg = MIME::Lite->new(From=>$uravo->{settings}->{from_address}, To=>$to, Subject=>$alert->{server_id} . " $alert->{AlertGroup}/$alert->{AlertKey}:" . $alert->{Summary}, Type=>'TEXT', Data=>$message);
            $msg->send();
            $uravo->{db}->do("UPDATE alert SET AlertCount=? WHERE Serial=?", undef, ($alert->{AlertCount}+1, $alert->{Serial})) || die ($uravo->{db}->errstr);
        }
    }
}

# Find rootcause alerts and make them the parent of symptom alerts.
sub rootcause {
    my $rootcauses = $uravo->{db}->selectall_arrayref("SELECT * FROM rootcause ORDER BY causeorder", {Slice=>{}});
    foreach my $rootcause (@$rootcauses) {
        my $where_str = $rootcause->{where_str};
        $where_str =~s/type_id/server_type.type_id/g;
        $where_str =~s/server_id/alert.server_id/g;

        my $alert = $uravo->{db}->selectrow_hashref("SELECT * FROM alert JOIN server_type ON server_type.server_id=alert.server_id WHERE Severity>0 AND $where_str");
        next unless ($alert);
        my $symptoms = $uravo->{db}->selectall_arrayref("SELECT * FROM rootcause_symptom WHERE rootcause_id=?", {Slice=>{}}, ($rootcause->{id}));
        foreach my $symptom (@$symptoms) {
            my $where_str = $symptom->{where_str};
            $where_str =~s/type_id/server_type.type_id/g;
            $where_str =~s/server_id/alert.server_id/g;

            $where_str =~s/SERVER_ID/$alert->{server_id}/;
            $where_str =~s/CLUSTER_ID/$alert->{server_id}/;
            $where_str =~s/AGENT/$alert->{Agent}/;
            $where_str =~s/ALERTKEY/$alert->{AlertKey}/;
            my $sql = "UPDATE alert JOIN server_type ON server_type.server_id=alert.server_id SET ParentIdentifier=? WHERE ParentIdentifier IS NULL AND $where_str";
            $uravo->log("$sql, $alert->{Identifier}", 6);
            $uravo->{db}->do($sql, undef, ($alert->{Identifier}));
        }
    }
}

# Calculate the depth of any parent alerts.
sub calculate_depth {
    my $sql = "SELECT * FROM alert WHERE SuppressEscl < 4 AND Severity >= " . ($uravo->{settings}->{minimum_severity}) . " AND EventLevel >= 10 AND ParentIdentifier IS NULL"; 
    my $alerts = $uravo->{db}->selectall_arrayref($sql, {Slice=>{}});
    foreach my $alert (@$alerts) {
        setDepth($alert);
    }
}

# Set the depth of an alert.
sub setDepth {
    my $alert = shift || return 0;

    my $Identifier = $alert->{Identifier} || return 0;
    my $original_Depth = $alert->{Depth} || 0;
    my $original_Severity = $alert->{Severity};

    my $Depth = 0;
    my $Severity = $original_Severity;

    my $alerts = $uravo->{db}->selectall_arrayref("SELECT * FROM alert WHERE ParentIdentifier=?", {Slice=>{}}, ($Identifier));
    foreach my $child (@$alerts) {
        my @ret = setDepth($child);
        $Depth += $ret[0];
        $Severity = $ret[1] if ($ret[1] > $Severity);
    }
    $Depth += scalar(@$alerts);

    if ($Depth != $original_Depth || $Severity != $original_Severity) {
        $uravo->{db}->do("UPDATE alert SET Depth=?, Severity=? WHERE Identifier=?", undef, ($Depth, $Severity, $Identifier));
    }

    return ($Depth, $Severity);
}

sub cleanup {
     print "cleanup()\n" if ($debug);

    # For all manual rollup events, check and see if they have any suppressed events behind them.
    # If not, clear the event.
    # If it does, check to see if all those events are green.
    my $events = $uravo->{db}->selectall_arrayref("select * from alert where AlertGroup='rollup' and Severity > 0", {Slice=>{}});
    foreach my $event (@$events) {
        my $suppEvents = $uravo->{db}->selectall_arrayref("select * from alert where ParentIdentifier='" . $event->{Identifier} . "'", {Slice=>{}});
         if (scalar(@$suppEvents) == 0) {
            $uravo->{db}->do("update alert set ParentIdentifier=NULL where ParentIdentifier=?", undef, ($event->{Identifier}));
            $uravo->{db}->do("update alert set Severity=0 where Identifier=?", undef, ($event->{Identifier}));
        } else {
            my $severity_count = 0;
            foreach my $suppEvent (@$suppEvents) {
                $severity_count += $suppEvent->{Severity};
            }
            if ($severity_count <= scalar(@$suppEvents)) {
            $uravo->{db}->do("update alert set ParentIdentifier=NULL where ParentIdentifier=?", undef, ($event->{Identifier}));
                $uravo->{db}->do("update alert set Severity=0 where Identifier=?", undef, ($event->{Identifier}));
            }
        }
    }

    # For all events that have ParentIdentifier set, check and see if
    # the parent exists.  If not, unsuppress them.
    my $events = $uravo->{db}->selectall_arrayref("select * from alert where (ParentIdentifier IS NOT NULL and ParentIdentifier!='')", {Slice=>{}});
    foreach my $event (@$events) {
        my $ParentIdentifier = $event->{ParentIdentifier};
        my $suppEvents = $uravo->{db}->selectall_arrayref("select * from alert where Identifier=?", {Slice=>{}}, ($ParentIdentifier));
        if (scalar(@$suppEvents) == 0) {
            $uravo->{db}->do("update alert set ParentIdentifier=NULL where ParentIdentifier=?", undef, ($ParentIdentifier));
            $uravo->{db}->do("update alert set Severity=0 where Identifier=?", undef, ($ParentIdentifier));
        }
    }

    # Fix any events that got marked as symptoms of themselves.
    $uravo->{db}->do("update alert set ParentIdentifier=NULL where ParentIdentifier=Identifier");

    # Delete old items from the alert_summary.
    $uravo->{db}->do("DELETE FROM alert_summary WHERE mod_date < (NOW() - INTERVAL 1 DAY)") || die($uravo->{db}->errstr);
    # Delete clears.
    $uravo->{db}->do("DELETE FROM alert WHERE StateChange < (NOW() - INTERVAL 2 MINUTE) AND Severity = 0") || die($db->errstr);

    # Cleanup the historical alerts.
    foreach my $row (@{$uravo->{db}->selectall_arrayref("SELECT Serial FROM historical_alert WHERE DeletedAt < NOW() - INTERVAL ? DAY", {Slice=>{}}, ($uravo->{settings}->{history_to_keep}))}) {
        print "HISTORICAL_CLEANUP: $row->{Serial}\n" if ($debug);
        foreach my $table (qw(historical_Acknowledged historical_ParentIdentifier historical_Severity historical_Summary historical_SuppressEscl historical_Ticket historical_alert alert_journal)) {
            $uravo->{db}->do("DELETE FROM $table WHERE Serial=?", undef, ($row->{Serial}));
        }
    }

    # Clear alerts that have timed out.
    $uravo->{db}->do("UPDATE alert SET Severity=0 WHERE Timeout > 0 AND Timeout IS NOT NULL AND Timeout < UNIX_TIMESTAMP(NOW())");

    # Add all the active alerts to the cache.
    my $alerts = $uravo->{db}->selectall_hashref("SELECT Identifier, Severity FROM alert WHERE Severity > 0", "Identifier");
    $uravo->setCache("active_alerts", $alerts);
}


