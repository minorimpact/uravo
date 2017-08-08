package Uravo::Serverroles::Graph;

use strict;
use Uravo;
use Uravo::Pylon;
use CGI;
use Digest::MD5;
use Data::Dumper;

my $uravo;

sub new {
    my $self        = {};
    use Data::Dumper;
    my $package     = shift || return;
    my $server_id   = shift || return;
    my $graph_id    = shift || return;
    my $value       = shift;
    my $type        = shift;

    my $server;

    if (ref($server_id) eq "SERVERROLES::Server") {
        $server = $server_id;
        $server_id = $server->id();
        $self->{server} = $server;
    }
    
    $self->{object_type} = 'graph';
    $self->{server_id}   = $server_id;
    $self->{graph_id}    = $graph_id;
    $self->{type}        = $type || "GAUGE";
    bless $self;

    $uravo ||= $uravo;

    if ($value || (!$value && $value eq '0')) {
        $self->add($value);
    }
    return $self;
}

sub _list {
    my $params = shift;

    my %list = ();

    return grep { $_; } keys %list;
}

sub color {
    my $p   = shift;
    my(@color) = qw{0000FF FF0000 00CC00 FF00FF 555555 880000 000088 008800 008888 888888 880088 FFFF00};
    while ($p >= scalar @color) {
        $p-=scalar(@color);
    }
    return $color[$p];
}

sub graph_keys {
    my $self        = shift;
    my $args        = shift;

    my $server_id   = $args->{server_id};
    my @server_ids  = split(/,/, $server_id);
    my %graphs;

    $uravo ||= new Uravo;

    my $output = Uravo::Pylon::pylon({remote=>$uravo->{config}->{outpost_server}, command=>"checks|" . join("|",@server_ids), port=>$uravo->{config}->{outpost_pylon_port}});
    chomp($output);
    foreach my $id (split(/\|/,$output)) {
        $id =~/^([^,.]+)/;
        $graphs{$1 || $id}++;
    }

    return keys %graphs;
}


# Misc info functions.
sub id   { my ($self) = @_; return $self->{graph_id}; }
sub name { my ($self) = @_; return $self->id(); }
sub type { my ($self) = @_; return $self->{object_type}; }

sub array_average {
    @_ == 1 or die ('Sub usage: $average = average(\@array);');
    my ($array_ref) = @_;
    my $sum;
    my $count = scalar @$array_ref;
    foreach (@$array_ref) { $sum += $_; }
    return undef if ($sum == undef);
    return $sum / $count;
}

sub ensmoothen_graph_data {
    my $graph_data = shift || return;
    my $start_time = shift;
    my $interval = shift;

    unless ($start_time && $interval) {
        my @time_list = sort keys %{$graph_data};
        $start_time = $time_list[0] unless($start_time);
        my $end_time = $time_list[scalar(@time_list) - 1];
        $interval = int(($end_time - $start_time ) /250);
    }
    my %avg = ();
    my $smooth_data;
    my %subs = ();

    my $time_mark = $start_time + $interval;
    foreach my $time (sort keys %{$graph_data}) {
        if ($time > $time_mark) {
            #print "$time_mark<br />\n";
            foreach my $sub_id (keys %avg) {
                $smooth_data->{$time_mark}{$sub_id} = array_average($avg{$sub_id});
            }
            %avg = ();
            $time_mark += $interval;
        }
        foreach my $sub_id (sort keys %{$graph_data->{$time}}) {
            push(@{$avg{$sub_id}}, $graph_data->{$time}{$sub_id});
            $subs{$sub_id}++;
        }
    }

    foreach my $sub_id (keys %avg) {
        $smooth_data->{$time_mark}{$sub_id} = array_average($avg{$sub_id});
    }

    foreach my $time (sort keys %{$smooth_data}) {
        foreach my $sub_id (keys %subs) {
            unless (defined($smooth_data->{$time}{$sub_id})) {
                $smooth_data->{$time}{$sub_id} = undef;
            }
        }
    }

    return $smooth_data;
}


1;
