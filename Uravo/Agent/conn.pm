package Uravo::Agent::conn;

use strict;

use Time::HiRes;
use Net::Ping;

use Uravo;

my $uravo;
my $conn;
my $PING;

sub new {
    my $class = shift || return;

    if ($conn) {
        return $conn;
    }

    $conn ||= bless({}, $class);
    $uravo ||= new Uravo;
    $PING ||= Net::Ping->new("tcp", 2, 56);
    $PING->hires();

    return $conn;
}

sub run {
    my $self = shift || return;
    my $server = shift || return;
    my $server_id = $server->id();

    my $options = $uravo->{options};
    my $local_server = $uravo->getServer();

    foreach my $interface ($server->getInterfaces({icmp=>1})) {
        my $ping_target = $interface->get('ip');
        next unless ($ping_target =~/^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$/);
        my ($ret, $duration, $ip) = $PING->ping($ping_target);
        if ($ret && ($duration > 1 && $duration < 2)) {
            # I'm getting a weird one second pause, occasionally.  I don't know what it is, but it feels like
            #   a 1s timeout and then retry (though the default timeout is 5s, and there's nothing in the
            #   documentation about retries).  I don't feel like fixing it, so I increased the timeout by a second, 
            #   and if if comes back with a duration of greater than 1s, I'm just going to disregard the excess.
            $duration -= 1;
        }
        $duration = sprintf("%.5f", $duration);
        if ($ret) {
            my $Summary = "$server_id ($ping_target) responded to ping in $duration seconds";
            $server->alert({AlertGroup=>'conn', AlertKey=>$ping_target, Severity=>'green', Summary=>$Summary});
            $server->graph('conn', $duration);
        } else {
            my $Summary = "$server_id ($ping_target) is not responding to ping";
            $server->alert({AlertGroup=>'conn', AlertKey=>$ping_target,  Severity=>'red', Summary=>$Summary});
        }
    }
}

1;

