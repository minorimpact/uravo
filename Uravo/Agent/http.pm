package Uravo::Agent::http;

use strict;
use Uravo;
use Time::HiRes qw(gettimeofday tv_interval);
use Uravo::Util;
use LWP::UserAgent;
use parent 'Uravo::Agent::Module';



sub run {
    my $self = shift || die;
    my $server = shift || die;

    my $local_server = $self->{server};

    my $options = $self->{options};
    my $UA = LWP::UserAgent->new(ssl_opts => { verify_hostname => 0 });
    $UA->agent("Mozilla");
    $UA->use_alarm(0);
    push @{ $UA->requests_redirectable }, 'POST';
    $UA->cookie_jar({});
    my $HEADERS = HTTP::Headers->new;

    my $server_id = $server->id();
    my $server_name = $server->name();

    my $timeout_time = ($load_time_red ? $load_time_red + 1 : 10);
    $UA->timeout($timeout_time);

    my $url = "http://" . ($server->hostname() || $server_id) . "/";
    my $req = HTTP::Request->new(GET=>$url);
    my $res;

    my ($load_time, $is_timeout, $return_code, $status_line, $content);
    foreach my $try (1 .. 3) {
        $is_timeout = 0;
        $return_code = 0;
        $status_line = '';
        $content = '';

        eval {
            local $SIG{ALRM} = sub { $is_timeout = 1; $status_line = ''; die; };
            my $t0 = [gettimeofday];

            alarm($timeout_time + 2); # just in case
            $res = $UA->request($req);
            alarm(0);

            $return_code = $res->code;
            $status_line = $res->status_line;

            if ($status_line =~ /timeout/i) {
                $is_timeout = 1;
                die;
            }
            die if ($return_code >= 400);

            $load_time = tv_interval($t0);
            $content = $res->content;
        };
        last if (! $is_timeout && $return_code > 0 && $return_code < 400);
        sleep(1);
    }

    my $Severity;
    my $Summary;
    if ($is_timeout || $return_code >= 400) {
        $Severity = 'red';
        if ($is_timeout) {
            $Summary = "$url timeout: $timeout_time sec.";
            $server->alert({Summary=>$Summary, Severity=>$Severity, AlertGroup=>'http_timeout'}) unless ($options->{dryrun});
        } elsif ($return_code >= 400) {
            $Summary = "$url return code: $return_code";
            $server->alert({Summary=>$Summary, Severity=>$Severity, AlertGroup=>'http_return_code'}) unless ($options->{dryrun});
        }
    } else {
        $server->alert({Summary=>"$url connected", Severity=>'green', AlertGroup=>'http_timeout'}) unless ($options->{dryrun});
        $server->alert({Summary=>"$url return code: $return_code", Severity=>'green', AlertGroup=>'http_return_code'}) unless ($options->{dryrun});
        $server->graph('http', $load_time);

        $Severity = $self->getSeverity('http_load_time', undef, $load_time);
        $Summary = "$url load time: $load_time";
        $server->alert({Summary=>$Summary, Severity=>$Severity, AlertGroup=>'http_load_time'}) unless ($options->{dryrun});
    }
}

1;
