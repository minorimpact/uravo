#!/usr/bin/perl

use lib "/usr/local/uravo/lib";
use Uravo;
use Data::Dumper;


my $key = $ARGV[0] || die "usage: $0 <key>\n";
my $uravo = new Uravo;
my $value = $uravo->getCache($key);
print Dumper $value;
