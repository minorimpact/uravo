#!/usr/bin/perl

$| = 42;
use strict;
use lib "/usr/local/uravo/lib";
use Getopt::Long;
use Uravo;
use Uravo::Util;
use Uravo::Cron;

use constant SLEEP_MAX => 7;

our $SLEEP_TIME = int(rand(SLEEP_MAX)) + 1;
our $PROGRAM = $0; $PROGRAM =~ s/^.*\///g;

my $uravo = new Uravo();
my $options  = $uravo->{options};

$options->{check} = [];

my $rc = GetOptions($options, qw/help verbose force nosleep check=s dryrun debug/);

if (! $rc || $options->{help}) {
    print "Usage: $0 <options/values>\n";
    print "  --help       - this screen\n";
    print "  --verbose    - turn on debugging\n";
    print "  --force      - run even if one is already running\n";
    print "  --nosleep    - turn off sleeping\n";
    print "  --check s    - run these checks only\n";
    print "  --dryrun     - Do not update Uravo.\n";
    print "  --debug      - Turn debugging output ON.\n";
    return;
}

if (! $options->{force} && Uravo::Util::CheckForDuplicates(1,0,0,290, $uravo->{config}{run_dir})) {
    print "Already running one of these\n" if ($options->{verbose});
    exit;
}

my $nosleep =  $options->{nosleep} || $options->{force} || $options->{verbose};

Uravo::Cron::execCron(\&main, {sleep=>(($nosleep)?0:2), no_log=>$options->{verbose}});
exit;

sub main {
    my $server = $uravo->getServer() || die("Can't create server object");
    my $monitoringValues = $server->getMonitoringValues();

    my @checks = ();
    my @modules = $server->getModules({remote=>0, id_only=>1});

    if ($options->{check} && scalar @{$options->{check}}) {
        $options->{check} = [split(/,/, join(',', @{$options->{check}}))];
        foreach my $check (@{$options->{check}}) {
            if (! grep { $_ eq $check } @modules) {
                die "Invalid check '$check' specified - available checks: ".join(',', @modules)."\n";
            }
        }
        @checks = @{$options->{check}};
    } else {
        @checks = @modules;
    }

    $0 = $PROGRAM;

    $server->alert({Recurring=>1, AlertGroup=>'agent', AlertKey=>'agent.pl', Summary=>'agent.pl is running.', Severity=>'green'});

    local $SIG{ALRM} = sub { die "timeout"; };
    foreach my $module (@checks) {
        Uravo::Util::do_sleep($SLEEP_TIME) unless ($nosleep);

        $0 = "$PROGRAM [running $module]";
        print "running $module\n" if ($options->{verbose});

        eval {
            require "Uravo/Agent/$module.pm";
            my $module_obj = "Uravo::Agent::$module"->new();
            $module_obj->run();
        };
        if ($@) {
            print "ERROR running $module: $@\n" if ($options->{verbose});
        }
        $0 = "$PROGRAM [done $module]";
    }

    print "done\n" if ($options->{verbose});

    return;
}

