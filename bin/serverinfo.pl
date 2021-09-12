#!/usr/bin/perl

use strict;
use Uravo;
use Getopt::Long;

my @args;
my $server_id = '';
my $verbose = 0;

GetOptions("help", sub { usage(); },
           "server_id=s", \$server_id,
         ) || usage();


$server_id ||= shift @ARGV;

if (!$server_id) {
    $server_id = `hostname -s`;
   chomp($server_id);
}

usage() unless ($server_id);;

eval { &main(); };
print "$@\n" if ($@);
exit;


sub main {
    my $uravo = new Uravo || die "Unable to create Uravo object.\n";
    my $output = '';

    my $server = $uravo->getServer($server_id) || die "Can't load a server object for '$server_id'.\n";

    my $hostname = $server->hostname();
    my $cluster_id = $server->cluster_id();
    my @types = $server->getTypes({id_only=>1});

    $output .= "server_id = $server_id\n";
    $output .= "hostname = $hostname\n";
    $output .= "cluster_id = $cluster_id\n";
    $output .= "type_id = " . join(",", @types) . "\n";
    
    print $output;
}


sub usage {
    my $error = shift;
    $0 =~/([^\/]+)$/;
    my $shortname = $1 || $0;

    my $usage = "";
    $usage .= "usage: $0 [options] [server_id]

Outputs information about a server for use in shell scripts.  If [server_id]
is not specified, it will default to localhost.

OPTIONS
--help                  This help screen.
--server                Server to look up.

\n";

    print $usage;
    exit(1);
}
