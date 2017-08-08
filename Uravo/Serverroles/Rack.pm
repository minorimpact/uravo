package Uravo::Serverroles::Rack;

use strict;
use DBI;

my $uravo;

sub new {
    my $self = {};
    my $package = shift || return;
    my $rack_id = shift || return;

    $uravo ||= new Uravo;

    my $rack_data = $uravo->{db}->selectrow_hashref("SELECT * FROM rack WHERE rack_id=?", undef, ( $rack_id ));
    return unless ($rack_data);

    foreach my $key (keys %{$rack_data}) {
        $self->{db_fields}  .= "$key ";
        $self->{$key} = $rack_data->{$key};
    }

    $self->{object_type} = 'rack';

    bless $self;
    return $self;
}

sub _list {
    my $params  = shift;

    $uravo ||= new Uravo;

    my $cage_id = ($params->{cage_id} || $params->{cage});
    my $select = "select distinct(rack_id) as rack_id from rack";
    my $where = " where rack_id is not null";

    if ($cage_id) { $where .= " and cage_id='$cage_id'"; }

    my $sql         = "$select $where";
    $uravo->log($sql, 8);
    my %list    = ();
    my $racks    = $uravo->{db}->selectall_arrayref($sql, {Slice=>{}}) || die($uravo->{db}->errstr);
    foreach my $rack (@$racks) { $list{$rack->{rack_id}}++; }

    return grep { $_; } keys %list;
}

sub add {
    $uravo ||= new Uravo;
    $uravo->log("Uravo::Serverroles::Rack::add()", 5);
    my $params = shift || return;
    my $changelog = shift || {};

    my $rack_id = $params->{rack_id} || die "No rack_id defined.";
    my $cage_id = $params->{cage_id} || die "No cage_id defined.";

    if ($rack_id =~/^\d+$/) {
        if ($cage_id) {
            my $data = $uravo->{db}->selectrow_hashref("select prefix from cage where cage_id=?", undef, ($cage_id)) || die($uravo->{db}->errstr);
            $rack_id = "$data->{prefix}$rack_id";
        } else {
            die "No cage defined for '$rack_id'.";
        }
    }

    $uravo->{db}->do("insert into rack (rack_id, cage_id, create_date) values (?, ?, now())", undef, ($rack_id, $cage_id)) || die($uravo->{db}->errstr);
    if ($changelog) {
        $uravo->changelog({object_type=>'cage',object_id=>$cage_id,field_name=>'New cage.',new_value=>$cage_id},$changelog);
    }
    return new Uravo::Serverroles::Rack($rack_id);
}

sub delete {
    $uravo ||= new Uravo;
    $uravo->log("Uravo::Serverroles::Rack::delete()", 5);
    my $rack_id = shift || return;

    return if ($uravo->{db}->selectrow_hashref("select count(*) as c from server where rack_id=?", undef, ($rack_id))->{c});

    $uravo->{db}->do("delete from rack where rack_id=?", undef, ($rack_id)) || die($uravo->{db}->errstr);
    return;
}

sub getCage {
    my $self = shift || return;

    $uravo->log("Uravo::Serverroles::Rack::getCage()", 5);
    return $uravo->getCage($self->get('cage_id'));
}

sub update {
    my $self            = shift || return;
    my $field           = shift || return;
    my $value           = shift;
    my $changelog       = shift;

    if (!$changelog && ref($value) eq 'HASH' && ref($field) eq 'HASH') {
        $changelog = $value;
    } elsif (!$changelog) {
        $changelog = { user=>'unknown'};
    }

    if (ref($field) eq 'HASH') {
        foreach my $f (keys %$field) {
            $self->update($f, $field->{$f}, $changelog);
        }
        return $changelog;
    }

    my $old_value =  $self->{$field};
    if ($old_value ne $value) {
        $uravo->changelog({object_type=>$self->{object_type},object_id=>$self->id(),field_name=>$field, old_value=>$old_value,new_value=>$value},$changelog);
    }

    $uravo->{db}->do("UPDATE rack SET $field=? WHERE rack_id=?", undef, ( $value, $self->id() )) || die($uravo->{db}->errstr);
    $self->{$field} = $value;
    return $changelog;
}

sub link {
    my $self = shift || return;
    my $links = shift || 'default';
    my $ret;
    my $image_base = '/images/';
    $links = " $links ";
    $links =~s/\s+default\s+/ info config graphs /;

    while ($links =~/\s?-(\w+)\s?/g) {
        $links          =~s/\s-?$1\s/ /g;
    }
    foreach my $link (split(/\s+/, $links)) {
        if ($link eq 'config') {
            $ret    .= "<a href='/cgi-bin/editrack.cgi?rack_id=${\ $self->id(); }' title='Configure ${\ $self->id(); }'><img name='${\ $self->id(); }-$link' src=$image_base/config-button.gif width=15 height=15 border=0></a>";
        }
        if ($link eq 'info') {
            $ret    .= "<a href='/cgi-bin/rack.cgi?rack_id=${\ $self->id(); }' title='Info: ${\ $self->id(); }'><img name='${\ $self->id(); }-$link' src=$image_base/info-button.gif width=15 height=15 border=0></a>";
        }
    }
    return $ret || $self->link();
}

sub getServers {
    my $self = shift || return;
    my $params = shift;

    $params->{rack} = $self->id();
    $params->{all_silos} = 1;
    $uravo ||= new Uravo;
    return $uravo->getServers($params);
}

sub getNetblocks {
    my $self = shift || return;
    my $params = shift;

    my $local_params = {};
    $uravo ||= new Uravo;
    foreach my $key (keys %$params) {
        $local_params->{$key} = $params->{$key};
    }
    $local_params->{silo_id} = $self->id();
    return $uravo->getNetblock($local_params);
}

sub id { my ($self) = @_; return $self->{'rack_id'}; }
sub cage_id { my ($self) = @_; return $self->{'cage_id'}; }
sub get { my ($self, $name) = @_; return $self->{$name}; }

1;
