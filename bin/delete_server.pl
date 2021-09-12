#!/usr/bin/perl

use strict;
use lib "/usr/local/uravo/lib";
use Uravo;
use Getopt::Long;

my $verbose = 0;
my $force = 0;

GetOptions("help", sub { usage(); },
           "verbose|v+", \$verbose,
           "force", \$force,
         ) || usage();

main();

sub main {
    if (scalar(@ARGV) == 0) {
        usage();
    }
    my $uravo = new Uravo;
    foreach my $server_id (@ARGV) {
        my $server = $uravo->getServer($server_id);
        if (!$server) {
            print "Unable to get serverroles info for $server_id\n" if ($verbose);
            next;
        }
        my $verify;
        if ($force) {
            $verify = 'y';
        } else {
            while(!$verify) {
                print "Are you sure you want delete '$server_id'? [y/N] ";
                $verify = scalar(<STDIN>);
            }
            chomp($verify);
        }

        if (lc($verify) eq 'y') {
            print "Deleting '$server_id'...\n" if ($verbose);
            Uravo::Serverroles::Server::delete({server_id=>$server_id, changelog=>{user=>$ENV{AUTH_USERNAME}, note=>"Deleting server: $server_id"}});
        } else {
            print "Skipping '$server_id'.\n" if ($verbose);
        }
    }
}

sub usage {
    my $error = shift;
    $0 =~/([^\/]+)$/;
    my $shortname = $1 || $0;

    my $usage .= <<USAGE;
usage: $shortname [options] server [server]...

OPTIONS
    --help      This help message.
    --verbose   Verbose output.
    --force     Don't ask for confirmation.

USAGE
    print $usage;
    exit(1);
}

