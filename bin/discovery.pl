#!/usr/bin/perl

use strict;
use lib "/usr/local/uravo/lib";
use Uravo;
use Uravo::Cron;
use Getopt::Long;
use NetAddr::IP;
use Net::CIDR;
use Net::Ping;
use Data::Dumper;
use MIME::Lite;
use SNMP;
use POSIX ":errno_h";
use POSIX ":sys_wait_h";
use Fcntl;
use Socket;

my $uravo = new Uravo;
my $options  = $uravo->{options};
my $rc = GetOptions($options, qw/verbose force debug netblock_id:s to_address:s ip:s/);

# Create a copy of standard out for use by the forked processes.
open(STDOUT2,">&STDOUT");

my $MAX_CHILD_COUNT = 5;
my %ips;
my $ping = Net::Ping->new("icmp");

my $to_address = $options->{'to_address'} if ($options->{'to_address'});
my $debug = $options->{debug};
my $verbose = $options->{verbose} || $debug;
my $opt_ip = $options->{ip};

my @netblock_ids = split(/,/, $options->{netblock_id});

Uravo::Cron::execCron(\&main, {no_log=>$verbose});
exit;


sub main {
    my $local_server = $uravo->getServer();
    my $results = $uravo->{db}->selectall_arrayref("SELECT ip FROM interface", {Slice=>{}});
    %ips = map {$_->{ip}=>1} @$results;

    $uravo->clearCache();

    my @netblocks = ();
    my %netblocks = ();
    if(scalar(@netblock_ids)) {
        foreach my $netblock_id (@netblock_ids) {
            my $netblock = $uravo->getNetblock($netblock_id);
            if (!$netblock->get('discovery')) {
                print "Discovery is not enabled for $netblock_id. Skipping.\n" if ($verbose);
                next;
            }
            push(@netblocks, $netblock);
        }
    } else {
        my $silo = $local_server->getSilo();
        @netblocks = sort {$a->id() <=> $b->id()} grep { $_->get('discovery') } $silo->getNetblocks();
    }

    foreach my $netblock (@netblocks) {
        $netblocks{$netblock->id()} = $netblock;
    }

    # Collect the auto_id info from all the types for later, but limit it to OIDs.
    my %types;
    foreach my $type ($uravo->getTypes()) {
        my $auto_id_type = $type->get('auto_id_type');
        my $auto_id_source = $type->get('auto_id_source');
        if ($auto_id_type eq 'snmp' && $auto_id_source) {
            $types{$type->id()}{auto_id_source} = $auto_id_source;
            $types{$type->id()}{auto_id_text} = $type->get('auto_id_text');
            $types{$type->id()}{community} = $type->get('community') || 'public';
        }
    }


    # Start scanning netblocks.
    my %fh = ();
    my %rogues = ();
    my %buffer = ();
    my @rogues = ();
    while (scalar(@netblocks) || scalar(keys(%fh))) {
        if (scalar(keys(%fh)) < $MAX_CHILD_COUNT && scalar(@netblocks)) {
            my $netblock = shift(@netblocks);
            my $pid;
            my $f;
            defined ($pid = open($f, "-|")) || die "Can't fork\n";
            if ($pid) {
                # Child processes will report their status back to us via this file handle.  Set it to non-blocking so
                # we can scan through the children and check for status updates.
                my $flags = '';
                fcntl($f, F_GETFL, $flags);
                $flags |= O_NONBLOCK;
                fcntl($f, F_SETFL, $flags);
                $fh{$pid} = $f;
            } else {
                local $SIG{ALRM} = sub { die "timeout"; };
                eval {
                    alarm(600);
                    scanNetblock($netblock);
                };
                exit;
            }
        }

        # Scan through all the child file handles and look for status updates.
        foreach my $pid (keys(%fh)) {
            my $line;
            my $f = $fh{$pid};
            my $b;
            my $rv = sysread($f, $b, 1);
            if (defined($rv) && $! != EAGAIN) {
                $buffer{$pid} .= $b;
                if ($buffer{$pid} =~/\n$/) {
                    $line = $buffer{$pid};
                    chomp($line);
                    delete($buffer{$pid});
                }
            }

            if ($line) {
                print "$pid: \$line='$line'\n" if ($options->{debug});
                my ($netblock_id, $ip,$result) = split(/:/,$line);
                next unless (length($line) && $netblock_id && $ip && $result);
                push(@{$rogues{$netblock_id}}, $ip);
            }
        }
        my $kid = waitpid(-1, WNOHANG);
        if (defined($kid)) {
            delete($fh{$kid});
        }
    }

    my $email_message;
    my $changelog = {user=>$ENV{'USER'}||'discovery.pl', note=>$0};
    # Scan through the IPs we collected and decide what to do with them.
    foreach my $netblock_id (keys %rogues) {
        my $netblock = $uravo->getNetblock($netblock_id) || next;
        my $silo = $netblock->getSilo() || next;
        my $cluster = $silo->getDefaultCluster() || next;

        foreach my $ip (@{$rogues{$netblock_id}}) {
            my $hostname = gethostbyaddr(inet_aton($ip), AF_INET) || next;
            print "hostname for $ip: $hostname\n" if ($debug);
            next unless ($hostname);

            my $server = $uravo->getServer($hostname);
            if ($server) {
                print "Added $ip to " . $server->id() . "\n" if ($verbose);
                $email_message = "Added $ip to " . $server->id() . "\n";
                $server->addInterface({ip=>$ip, network=>$netblock->get('network'), netblock_id=>$netblock}, $changelog);
                next;
            }

            my @type_matches = ();
            foreach my $type_id (keys %types) {
                print "Testing $type_id: $types{$type_id}{community}\n" if ($verbose);
                my $sess = new SNMP::Session(DestHost => $ip, Community => $types{$type_id}{community}, Version => '2c', Timeout => 1000000);
                if (!$sess || $sess->{ErrorNum}) {
                    #$email_message .= "Error creating SNMP session object for $ip: $sess->{ErrorNum} - $sess->{ErrorStr})\n";
                    next;
                }

                my $ifTable = $sess->gettable('ifTable');

                if ($sess->{ErrorNum}) {
                    #$email_message .= "Error collecing interfaces from $ip: $sess->{ErrorNum} - $sess->{ErrorStr}\n";
                    next;
                }
                my $val = $sess->get($types{$type_id}{auto_id_source});
                if ($val =~/$types{$type_id}{auto_id_text}/) {
                    push(@type_matches, $type_id);
                }
            }
            my ($shortname) = ($hostname =~/^([^.]+)/);
            print "shortname='$shortname'\n" if ($debug);

            if (scalar(@type_matches)) {
                $server = Uravo::Serverroles::Server::add({server_id=>$shortname, hostname=>$hostname, cluster_id=>$cluster->id(), type_id=>\@type_matches}, $changelog);
                if ($server) {
                    print "Added $server->id()  to uravo.  IP: $ip Type(s): " . join(",", @type_matches) . "\n" if ($verbose);
                    $email_message .= "Added $server->id()  to uravo.  IP: $ip Type(s): " . join(",", @type_matches) . "\n";
                    $server->addInterface({ip=>$ip, network=>$netblock->get('network'), netblock_id=>$netblock}, $changelog);
                } else {
                    print "Could not add $hostname to uravo.  IP: $ip Type(s): " . join(",", @type_matches) . "\n" if ($verbose);
                    $email_message .= "Could not add $hostname to uravo.  IP: $ip Type(s): " . join(",", @type_matches) . "\n";
                }
                next;
            }
            $email_message .= "Could not collect any information about $ip\n";
        }
    }


    if ($to_address) {
        print "sending output to $to_address\n" if ($verbose);

        my $msg = MIME::Lite->new(From=>$uravo->{settings}->{from_address}, To=>$to_address, Subject=>'Uravo Discovery', Type=>'TEXT', Data=>$email_message);
        if ($msg->send()) {
            print "Message sent to $to_address\n" if ($verbose || $debug);
        } else {
            print "Failed to send message to $to_address\n";
        }
    } else {
        print $email_message;
    }

    return;
}

sub scanNetblock {
    my $netblock = shift || return;
    my $address = $netblock->get('address');
    my $netblock_id = $netblock->id();

    print STDOUT2 "checking " . $netblock->id() . ": $address\n" if ($verbose);

    my $netblock_id = $netblock->id();
    my $netaddr = NetAddr::IP->new($address);
    my $c = 0;
    for (my $count = 0; $count < $netaddr->num(); $count++) {
        my $test = $netaddr->nth($count);
        my $test_ip = $test->addr();
        if (defined($ips{$test_ip})) {
            print STDOUT2 "in serverroles: $test_ip\n" if ($debug);
            next;
        }
        last if ($c++ > 50);
        print STDOUT2 "ping: $test_ip\n" if ($debug);
        if ($ping->ping($test_ip,1)) {
            print "$netblock_id:$test_ip:1\n";
        } else {
            print "$netblock_id:$test_ip:0\n";
        }
    }
    return;
}


