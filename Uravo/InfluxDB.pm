package Uravo::InfluxDB;

use Data::Dumper;
use HTTP::Request;
use LWP::UserAgent;
use Socket;

sub influxdb {
    my $params = shift || return;

    my $db = $params->{db} || return;
    my $metric = $params->{metric} || return;
    my $value = $params->{value};
    return unless (defined($value));
    my $remote = $params->{remote} || "influxdb";
    my $port = $params->{port} || 8086;

    $metric =~s/^([^,]+),([^,=]+),/$1.$2,/;
    my $data = "$metric value=$value";
    #print "\$data='$data'\n";
    my $UA = new LWP::UserAgent();
    my $req = HTTP::Request->new(POST => "http://$remote:$port/write?db=$db");
    $req->content($data);
 
    my $resp = $UA->request($req);
    return $resp->code . ":" . $resp->message . "\n";
}

1;
