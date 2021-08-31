package Uravo::Event;

use Uravo;

my $uravo;

my $SEVERITY = {};
$SEVERITY->{0} = "Clear";
$SEVERITY->{1} = "Unknown";
$SEVERITY->{2} = "Warning";
$SEVERITY->{3} = "Minor";
$SEVERITY->{4} = "Major";
$SEVERITY->{5} = "Critical";

sub new {
    my $self = {};
    my $class = shift || return;
    my $id = shift || return;
    my $params = shift || {};

    $uravo = new Uravo;

    if (ref($id) eq "HASH") {
        my $data = $id;

        return unless ($data->{server_id} && $data->{AlertGroup} && $data->{Severity} && $data->{Summary});

        my $server = $uravo->getServer($data->{server_id});
        next unless ($server);

        $data->{cluster_id} = $server->cluster_id();
        if (!defined($data->{AdditionalInfo})) {
            $data->{AdditionalInfo} = '';
        }
        if (!defined($data->{AlertKey}) && defined($data->{AlertGroup})) {
            $data->{AlertKey} = $data->{AlertGroup};
        }
        if (!defined($data->{Recurring})) {
            $data->{Recurring} = 0;
        }
        if (!defined($data->{Timeout})) {
            $data->{Timeout} = 0;
        } elsif ($data->{Timeout} < 1440) {
            $data->{Timeout} = time() + ($data->{Timeout} * 60);
        }

        print "  $data->{server_id}: $data->{Severity} - $data->{Summary}\n" if ($uravo->{options}->{verbose});
        if ($data->{Severity} eq 'red') { $data->{Severity} = 4; }
        elsif ($data->{Severity} eq 'orange') { $data->{Severity} = 4; }
        elsif ($data->{Severity} eq 'yellow') { $data->{Severity} = 3; }
        elsif ($data->{Severity} eq 'blue') { $data->{Severity} = 2; }
        elsif ($data->{Severity} eq 'gray') { $data->{Severity} = 1; }
        elsif ($data->{Severity} eq 'green') { $data->{Severity} = 0; }

        foreach my $key (keys %$data) {
            my $value = $data->{$key};
            $value = substr($value, 0, 16384);
            #$value =~s/\n/_CR_/g;
            #$value =~s/\|/_PIPE_/g;
            #$value =~s/'/_APOST_/g;
            if ($value && $value < .001 && $value=~/^[0-9.e-]+$/) {
                $value = sprintf("%.8f", $value);
            }
            $data->{$key} = $value;
        }

        unless (defined($data->{Agent}) && $data->{Agent}) {
            $data->{Agent} = "$uravo->{server_id}:$uravo->{script_name}";
        }
        $data->{Identifier} = "$data->{server_id} $data->{AlertGroup} $data->{AlertKey} SOCKET";

        # Add a record to the summary table.
        my $sql = "INSERT INTO alert_summary (server_id, AlertGroup, Agent, recurring, mod_date) VALUES (?,?,?,?, NOW()) ON DUPLICATE KEY UPDATE mod_date=NOW(), reported=0, recurring=?";
        $uravo->{db}->do($sql, undef, ($data->{server_id}, $data->{AlertGroup}, $data->{Agent}, $data->{Recurring}), $data->{Recurring}) || die($uravo->{db}->errstr);
        if ($data->{Recurring}) {
            $sql = "UPDATE alert SET Severity=0 WHERE AlertGroup='timeout' AND AlertKey=? AND server_id=?";
            $uravo->{db}->do($sql, undef, ("$data->{AlertGroup}", $data->{server_id})) || die($uravo->{db}->errstr);
        }

        my $alerts = $uravo->getCache("active_alerts");
        if (!$alerts) {
            $alerts = $uravo->{db}->selectall_hashref("SELECT Identifier, Severity FROM alert WHERE Severity > 0", "Identifier");
            $uravo->setCache("active_alerts", $alerts);
        }

        return unless ($data->{Severity} > 0 || defined($alerts->{$data->{Identifier}}));

        $sql = "INSERT INTO new_alert (`" . join("`,`", sort keys %$data) . "`) VALUES (" . join(",", map { '?' } keys %$data) .")";
        eval {
            $uravo->{db}->do($sql, undef, map { $data->{$_}} sort keys %$data)|| die($uravo->{db}->errstr);
        };
        die($@) if ($@);
        $id = $data->{Identifier};
    }

    my $sql = $id=~/^\d+$/ ? "SELECT * FROM alert WHERE Serial = ?" :  "SELECT * FROM alert WHERE Identifier = ?";
    #print "$sql, $id\n";

    # Prepare it
    my $alerts = $uravo->{db}->selectall_arrayref($sql, {Slice=>{}}, ($id)) || die("Can't select alerts: " . $uravo->{db}->errstr);

    foreach my $alert (@$alerts) {
        if ($alert->{Identifier} eq $id || $alert->{Serial} == $id) {
            $self = $alert;
        }
    }
    return unless ($self);

    bless($self);
    return $self;
}

sub clear {
    my $self = shift || return;

    my $Identifier = $self->{Identifier} if (defined($self->{Identifier}));
    return unless ($Identifier);
    my $username = $ENV{LOGNAME};
    my $serial = $self->{Serial};

    $uravo->{db}->do("UPDATE alert SET ParentIdentifier=NULL where ParentIdentifier='$Identifier'");
    $uravo->{db}->do("update alert set Severity=0, DeletedBy = '$username' where Serial=$serial");
    $uravo->{db}->do("INSERT INTO alert_journal (Serial, user_id, entry, create_date) VALUES (?, ?, ?, NOW())", undef, ($serial, $username, "Alert cleared by $username."));
    return;
}

sub list {
    my $params = shift || {};

    my $uravo = new Uravo;
    my $filters = $uravo->{db}->selectall_hashref("SELECT * FROM filter", "id");
    $filters->{'all'}{'where_str'} = "Serial > 0";
    $filters->{'default'}{'where_str'} = "SuppressEscl < 4 and Severity >= " . ($uravo->{settings}->{minimum_severity}) . " and EventLevel >= 10 and ParentIdentifier IS NULL";

    my $filter = lc($params->{'filter'}) || 'default';
    my $Identifier = $params->{'Identifier'};
    my $ParentIdentifier = $params->{'ParentIdentifier'};
    my $Serial = $params->{'Serial'};
    my $server_id = $params->{'server_id'};

    # Define the SQL statement to be executed
    my $field_list = "Class, Identifier, UNIX_TIMESTAMP(LastOccurrence) as LastOccurrence, Tally, Depth, Serial, server_id, cluster_id, type_id, AlertGroup, Severity, Summary, Ticket, Note, Acknowledged, UNIX_TIMESTAMP(FirstOccurrence) as FirstOccurrence, AdditionalInfo, AlertKey, SiteList, UNIX_TIMESTAMP(StateChange) as StateChange, EventLevel, Action, rack_id, SuppressEscl, ParentIdentifier, Agent, cage_id, silo_id, Timeout";
    my $where = "SuppressEscl < 4 and Severity >= " . ($uravo->{settings}->{minimum_severity}) . " and EventLevel >= 10 and ParentIdentifier IS NULL";

    if ($Serial) {
        $where = "Serial=$Serial";
    } elsif ($Identifier) {
        $where = "Identifier='$Identifier'";
    } elsif ($ParentIdentifier) {
        $where = "ParentIdentifier='$ParentIdentifier'";
    } elsif ($server_id) {
        $where = "server_id='$server_id'";
    } elsif (defined($filters->{$filter})) {
        $where = $filters->{$filter}{where_str};
    }

    my $sql = qq(select $field_list from alert a where $where);

    # Prepare it
    my $sth = $uravo->{db}->prepare($sql);

    # Execute it
    $sth->execute;

    my @list = ();
    # Check for errors
    if ( $sth->errstr ) {
        print $sth->errstr, "\n";
    } else {
        # Process the output
        my $data = ();
        while ( my $data = $sth->fetchrow_hashref) {
            push(@list, new Uravo::Event($data->{Identifier}));

        }
    }
    return @list;
}

sub toString {
    my $self = shift || return;

    $output = sprintf("%d %19s %-10s %-8s %4d %20s", $self->{Serial}, $self->{LastOccurrence}, $self->{server_id}, $SEVERITY->{$self->{Severity}}, $self->{Tally}, $self->{Summary});
    return $output;
}

1;
