#!/usr/bin/perl

$| = 42;
use strict;
use lib "/usr/local/uravo/lib";
use Getopt::Long;
use Uravo;
use POSIX qw(setsid getcwd);
use Uravo::Util;
use Net::Ping;
use Time::Local;
use Uravo::Cron;
use Data::Dumper;

my $uravo = new Uravo();
my $options  = $uravo->{options};

$options->{check} = [];

my $rc = GetOptions($options, qw/help verbose force check=s dryrun debug log_level=i/);

if (! $rc || $options->{help}) {
    print "Usage: $0 <options/values>\n";
    print "  --help       - this screen\n";
    print "  --verbose    - turn on debugging\n";
    print "  --force      - run even if one is already running\n";
    print "  --check s    - run these checks only\n";
    print "  --dryrun     - Do not update Uravo.\n";
    print "  --debug      - Turn debugging output ON.\n";
    return;
}

if (! $options->{force} && Uravo::Util::CheckForDuplicates(1,0,0,290, $uravo->{config}{run_dir})) {
    print "Already running one of these\n" if ($options->{verbose});
    exit;
}

$uravo->{log_level} = $options->{log_level} if ($options->{log_level});
Uravo::Cron::execCron(\&main, {no_log=>$options->{verbose}});
exit;

sub main {
    my $local_server = $uravo->getServer() || die("Can't create server object");
    $local_server->alert({Recurring=>1, AlertGroup=>'agent', AlertKey=>'remote_agent.pl', Summary=>'remote_agent.pl is running.', Severity=>'green'});

    my @batches = ([]);
    my $batch_count = $uravo->{config}->{batch_count} || 5;
    my $batch_size = $uravo->{config}->{batch_size} || 20;
    foreach my $server (sort { rand() cmp rand(); } $uravo->getServers({remote=>1})){
        next if ($server->getLast('agent','remote_time') > (time() - 300) && !$options->{force});
        if (scalar(@{$batches[0]}) >= $batch_size) {
            unshift(@batches, []);
        }
        push(@{$batches[0]}, $server);
    }

    my %children;
    foreach my $batch (@batches) {
        defined (my $pid = fork()) || die "Can't fork\n";

        if ($pid) {
            $children{$pid} = 1;
            if (scalar(keys(%children)) >= $batch_count) {
                my $done = wait();
                delete $children{$done};
            }
        } else {
            $uravo->reload();
            check_server($batch);
            exit;
        }
    }
    while (wait() > 0) {}
    return;
}

sub check_server {
    my $server = shift || return;
    if (ref($server) eq 'ARRAY') {
        foreach my $s (@$server) {
            check_server($s);
        }
        return;
    }
        
    $server->setLast('agent','remote_time', time());
    my $server_id = $server->id();
    print "$server_id:starting ($$)\n" if ($options->{verbose});

    my $monitoringValues = $server->getMonitoringValues();

    my @checks = ();
    my @modules = $server->getModules({remote=>1, id_only=>1, enabled=>1});

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

    local $SIG{ALRM} = sub { die "timeout"; };
    foreach my $module (@checks) {
        print "  $server_id:checking $module\n" if ($options->{verbose});

        eval {
            require "Uravo/Agent/$module.pm";
            my $module_obj = "Uravo::Agent::$module"->new();
            $module_obj->run($server);
        };
        if ($@) {
            print "ERROR running $module: $@\n" if ($options->{verbose});
        }
    }

    print "$server_id:done ($$)\n" if ($options->{verbose});

    return;
}

