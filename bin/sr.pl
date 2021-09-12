#!/usr/bin/perl

use Data::Dumper;
use MinorImpact;
use Uravo;

use Getopt::Long;

my $uravo = new Uravo;
my @args;
my $delim   = "\n";
my $params = {};

GetOptions("delim=s"   => \$delim,
           "verbose"   => \$verbose,
           "help"      => sub { usage(); },
           "flat"      => sub { $delim=' ' },
         ) || usage();


eval { &main(); };
print "$@\n" if ($@);
exit;


sub main {
    my $action  = shift @ARGV;

    foreach my $param (@ARGV)  {
        if ($param =~ /^(\w+)="([^"]*")$/) {
            $params->{$1}  = $2;
        }
        elsif ($param =~ /^(\w+)=(\S*)$/) {
            $params->{$1}  = $2;
        }
         else {
            push @args, $param;
        }
    }
    $params = Uravo::Util::clean_params($params);
    eval "do_$action(\$params)";
    print "$@\n" if ($@);
}

sub do_add {
    my $params = shift;
    my $local_params = Uravo::Util::clean_params(MinorImpact::cloneHash($params));

    my $arg = shift(@args);
    $arg =~s/s$//;
    if ($arg eq 'cluster') {
        my $id = shift(@args) || $local_params->{cluster_id};
        if ($id && !defined($local_params->{cluster_id})) { $local_params->{cluster_id} = $id; }
        die("you must specify cluster_id") unless ($id);
        Uravo::Serverroles::Cluster::add($local_params);
    }
    elsif ($arg eq 'server') {
        my $id = shift(@args) || $local_params->{server_id};
        if ($id && !defined($local_params->{server_id})) { $local_params->{server_id} = $id; }
        die("you must specify server_id") unless ($id);
        Uravo::Serverroles::Server::add($local_params);
    }
    elsif ($arg eq 'silo') {
        my $id = shift(@args) || $local_params->{silo_id};
        if ($id && !defined($local_params->{silo_id})) { $local_params->{silo_id} = $id; }
        die("you must specify silo_id") unless ($id);
        $silo = Uravo::Serverroles::Silo::add($local_params);
        print("added " . $silo->id() . "\n") if ($verbose && $silo);
    }
    elsif ($arg eq 'threshold') {
        my $id = shift(@args);
        my $id2 = shift(@args);
        $local_params->{AlertGroup} = $id unless (defined($local_params->{AlertGroup}) and $local_params->{AlertGroup} != "");
        $local_params->{AlertKey} = $id2 unless (defined($local_params->{AlertKey}) and $local_params->{AlertKey} != "");
        die("you must specify an AlertGroup") unless ($local_params->{AlertGroup});
        print("adding $local_params->{AlertGroup}\n") if ($verbose);
        $uravo->updateThreshold($local_params);
    }
    elsif ($arg eq 'type') {
        my $type_id = shift(@args) || $local_params->{type_id};
        $local_params->{type_id} = $type_id;
        my $type = $uravo->getType($type_id);
        die "'$type_id' type already exists" if ($type);
        die("you must specify type_id") unless (defined($type_id));
        Uravo::Serverroles::Type::add($local_params);
    }
    else {
        die("unknown item '$arg'");
    }
}

sub do_del {
    return do_delete(@_);
}

sub do_delete {
    my $params = shift;
    my $local_params = MinorImpact::cloneHash($params);
    my $arg = shift(@args);
    $arg =~s/s$//;
    if ($arg =~/^event$/ || $arg eq 'alert' ) {
        if (length(@args) > 0) {
            $id = shift(@args);
        }
        elsif (defined($local_params->{Identifier})) {
            $id = $local_params->{Identifier};
        }
        elsif (defined($local_params->{Serial})) {
            $id = $local_params->{Serial};
        }
        my $event = $uravo->getEvent($id) if ($id);
        return unless $event;
        print("deleting " . $event->toString() . "\n") if ($verbose);
        $event->clear();
    }
    elsif ($arg eq 'cluster') {
        my $id = shift(@args) || $local_params->{cluster_id};
        if ($id && !defined($local_params->{cluster_id})) { $local_params->{cluster_id} = $id; }
        die("you must specify cluster_id") unless ($id);
        Uravo::Serverroles::Cluster::delete($local_params);
    }
    elsif ($arg eq 'silo' ) {
        my $id = shift(@args) || $local_params->{silo_id};
        die("you must specify a silo_id") unless ($id);
        my $silo = $uravo->getSilo($id) || die "can't get $id";
        print("deleting " . $silo->toString() . "\n") if ($verbose);
        $silo->delete();
    }
    elsif ($arg eq 'threshold') {
        my $id = shift(@args);
        my $id2 = shift(@args);
        $local_params->{AlertGroup} = $id unless (defined($local_params->{AlertGroup}) and $local_params->{AlertGroup} != "");
        $local_params->{AlertKey} = $id2 unless (defined($local_params->{AlertKey}) and $local_params->{AlertKey} != "");
        die("you must specify an AlertGroup") unless ($local_params->{AlertGroup});
        print("deleting $local_params->{AlertGroup}\n") if ($verbose);
        $uravo->deleteThreshold($local_params);
    }
    elsif ($arg eq 'type' ) {
        die("you must specify type_id") unless (defined($local_params->{type_id}));
        my $type = $uravo->getType($local_params->{type_id});
        die("invalid type") unless ($type);
        print("deleting " . $type->toString() . "\n") if ($verbose);
        $type->delete();
    }
}

sub do_edit {
    return do_update(@_);
}

sub do_info {
    return do_show(@_);
}

sub do_list {
    my $local_params = Uravo::Util::clean_params(shift || {});
    if (!defined($local_params->{silo_id})) {
        $local_params->{all_silos} = 1;
    }
    $local_params->{id_only} = 1;
    $arg = shift(@args);
    $arg =~s/s$//;
    if ($arg eq "check") {
    }
    elsif ($arg eq "cluster") {
        print join($delim, $uravo->getClusters($local_params, {id_only=>1}));
        print "\n";
    }
    elsif ($arg eq "event" ) {
        my @events = $uravo->getEvents($local_params, {id_only=>1});
        my $output = "";
        foreach my $event (@events) {
            $output .= $event->toString() . $delim;
        }
        print $output;
    }
    elsif ($arg eq "netblock" ) {
        print join($delim, $uravo->getNetblocks($local_params, {id_only=>1}));
        print "\n";
    }
    elsif ($arg eq "server" ) {
        print join($delim, $uravo->getServers($local_params, {id_only=>1}));
        print "\n";
    }
    elsif ($arg eq "silo" ) {
        print join($delim, $uravo->getSilos($local_params, {id_only=>1}));
    }
    elsif ($arg eq "threshold" ) {
        my $server = $local_params->{server_id} ? $uravo->getServer($oocal_params->{server_id}) : $uravo->getServer();
        if ($server) {
            my $monitoringValues = $server->getMonitoringValues($local_params);
            for $AlertGroup (sort keys %$monitoringValues) {
                for $AlertKey (sort keys %{$monitoringValues->{$AlertGroup}}) {
                    if (($monitoringValues->{$AlertGroup}{$AlertKey}{red} || $monitoringValues->{$AlertGroup}{$AlertKey}{yellow}) and !$monitoringValues->{$AlertGroup}{$AlertKey}{disabled}) {
                        print "$AlertGroup";
                        if ($AlertGroup ne $AlertKey) { print ",$AlertKey"; }
                        print ": $monitoringValues->{$AlertGroup}{$AlertKey}{yellow}/$monitoringValues->{$AlertGroup}{$AlertKey}{red}";
                        print $monitoringValues->{$AlertGroup}{$AlertKey}{disabled} ? " DISABLED" : "";
                        print $delim;
                    }
                }
            }
        }
    }
    elsif ($arg eq "type" ) {
        print join($delim, $uravo->getTypes($local_params, {id_only=>1}));
        print "\n";
    }
    else {
        die("unknown item '$arg'");
    }
}

sub do_show {
    my $params  = shift;
    my $local_params = MinorImpact::cloneHash($params);
    my $arg = shift(@args);
    if ($arg eq "cluster") {
        my $id = shift(@args) || $local_params->{cluster_id};
        if ($id && !defined($local_params->{cluster_id})) { $local_params->{cluster_id} = $id; }
        my $cluster = $uravo->getCluster($id);
        if ($cluster) {
            print($cluster->info());
        }
    }
    elsif ($arg eq "netblock") {
        my $id = shift(@args) || (defined($local_params->{netblock_id})?$local_params->{netblock_id}:$uravo->get()->id());
        my $netblock = $uravo->getNetblock($id);
        if ($netblock) {
            print($netblock->info());
        }
    }
    elsif ($arg eq "server") {
        my $id = shift(@args) || (defined($local_params->{server_id})?$local_params->{server_id}:$uravo->getServer()->id());
        my $server = $uravo->getServer($id);
        if ($server) {
            print($server->info());
        }
    }
}

sub do_update {
    my $params = shift;
    my $local_params = MinorImpact::cloneHash($params);

    my $arg = shift(@args);
    $arg =~s/s$//;
    if ($arg eq "bu") {
        $id = shift(@args) || $local_params->{bu_id};
        if ($id && !defined($local_params->{bu_id})) { $local_params->{bu_id} = $id; }
        die("you must specify bu_id") unless (defined($local_params->{bu_id}));
        $bu = new Uravo::Serverroles::BU($local_params->{bu_id});
        $bu->update($local_params);
        print("updated " . $bu->id() . "\n") if ($verbose);
    }
    elsif ($arg eq "cluster" ) {
        my $id = shift(@args) || (defined($local_params->{cluster_id})?$local_params->{cluster_id}:undef);
        my $cluster = $id ? $uravo->getCluster($id) : $uravo->getCluster();
        if ($cluster) {
            print("updating " . $cluster->id() . "\n");
            $cluster->update($local_params);
        }
    }
    elsif ($arg eq "server" ) {
        my $id = shift(@args) || (defined($local_params->{server_id})?$local_params->{server_id}:undef);
        my $server = $id ? $uravo->getServer($id) : $uravo->getServer();
        if ($server) {
            print("updating " . $server->id() . "\n");
            $server->update($local_params);
        }
    }
    elsif ($arg eq "netblock") {
        my $id = shift(@args) || (defined($local_params->{netblock_id})?$local_params->{netblock_id}:undef);
        die("you must specify netblock_id") unless ($id);
        my $netblock = new Uravo::Serverroles::Netblock($id);
        $netblock->update($local_params);
        print("updated " . $netblock->id() . "\n") if ($verbose);
    }
    elsif ($arg eq "silo") {
        my $id = shift(@args) || (defined($local_params->{silo_id})?$local_params->{silo_id}:undef);
        die("you must specify silo_id") unless ($id);
        my $silo = new Uravo::Serverroles::Silo($id);
        $silo->update($local_params);
        print("updated " . $silo->id() . "\n") if ($verbose);
    }
    elsif ($arg eq 'threshold') {
        unshift(@args, "threshold");
        return do_add($params)
    }
    elsif ($arg eq "type" ) {
        my $id = shift(@args) || (defined($local_params->{type_id})?$local_params->{type_id}:undef);
        if ($id) {
            my $type = $uravo->getType($id);
            if (defined($type)) {
                print("updating " . $type->name() . "\n");
                $local_params->{type_id} = $id;
                $type->update($local_params);
            }
        }
    }
}


sub usage {
    my $error       = shift;
    $0              =~/([^\/]+)$/;
    my $shortname   = $1 || $0;

    print "$error" if ($error);
    print "\n" unless (!$error || $error =~/\n$/);
    print <<USAGE;
usage: $shortname [options] <command> [--params [...] ]

OPTIONS
    --flat          Print the results horizontally (space delimited) rather than
                    vertically (\\n delimited).
    --help          Display this message.
    --params        a list of 'name=value' pairs that can be passed to commands to set values for the actions.

COMMANDS
    One of the following must be passed to $shortname:
        add threshold
        delete threshold
        list clusters/events/netblocks/servers/thresholds/types
        show server
        update server/threshold/type

PARAMETERS
    Parameters can be passed to various commands in the form of a 'name=value' pairs.
    See the following examples.

EXAMPLES
    Print a list of clusters:
        $ $shortname list clusters
        cluster_id_1
        cluster_id_2

    Print a list of servers for a given cluster:
        $ $shortname list servers cluster=cluster_id_1
        server_id_1
        server_id_2

    Print a list of all servers, horizontally:
        $ $shortname --flat list servers 
        server_id_1 server_id_2 server_id_3 server_id_4

    Show all the servers of a particular type in a particular cluster:
        $ $shortname list servers type=type_id_1 cluster=cluster_id_2
        server_id_3

    Display the servers that are not of a certain type:
        $ $shortname list servers type=\!type_id_1
        server_id_1
        server_id_2
        server_id_4

       (Note the backslash to escape the '!' character.  Shells do weird things with
        '!'s.)

    Miscelaneous:
        $ $shortname show server [server_id]
        $ $shortname add threshold disk_temp /dev/sdb --params server_id=mincemeat red=115 yellow=110
        $ $shortname delete threshold disk_temp --params AlertKey=/dev/sdb
        $ $shortname list netblocks
        $ $shortname list thresholds --params server_id=pumpkin
        $ $shortname add type linux
        $ $shortname update type linux --params procs=+mysql:">0"
        $ $shoftname update type linux --params  module_id=+log,procs
        $ $shortname update server --params type_id=linux,ubuntu
        $ $shortname update server mincemeat --params type_id=linux,debian,outpost
        $ $shortname update netblock 192_168_0_0_24 --params silo_id=halsey
        $ $shortname --verbose delete alert 1287493

USAGE
    exit;
}
