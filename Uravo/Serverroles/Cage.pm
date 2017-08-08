package Uravo::Serverroles::Cage;

use strict;

use Uravo;

my $uravo;

sub new {
    my $self = {};
    my $package = shift || return;
    my $cage_id = shift;

    $uravo ||= new Uravo;
    my $cage_data;
    $cage_data = $uravo->{db}->selectrow_hashref("SELECT * FROM cage WHERE cage_id=?", undef, ( $cage_id )) || return;

    foreach my $key (keys %{$cage_data}) {
        $self->{db_fields}  .= "$key ";
        $self->{$key} = $cage_data->{$key};
    }

    $self->{object_type} = 'cage';

    bless $self;
    return $self;
}

sub _list {
    my $params  = shift;

    $uravo ||= new Uravo;
    my $where   = "where cage_id is not null";

    my $sql         = "select cage_id from cage $where";
    my %list    = ();
    my $cages    = $uravo->{db}->selectall_arrayref($sql, {Slice=>{}}) || carp($uravo->{db}->errstr);
    foreach my $cage (@$cages) { $list{$cage->{cage_id}}++; }

    return grep { $_; } keys %list;
}

sub add {
    my $params = shift || return;
    my $changelog = shift || {};

    $uravo ||= new Uravo;
    my $cage_id = $params->{cage_id} || die("No cage_id specified.");
    $uravo->{db}->do("insert into cage (cage_id, create_date) values (?, now())", undef, ($cage_id)) || die($uravo->{db}->errstr);
    if ($changelog) {
        $uravo->changelog({object_type=>'cage',object_id=>$cage_id,field_name=>'New type.',new_value=>$cage_id},$changelog);
    }

    return $cage_id;
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

    $uravo->{db}->do("UPDATE cage SET $field=? WHERE cage_id=?", undef, ( $value, $self->id() )) || die($uravo->{db}->errstr);
    $self->{$field} = $value;
    return $changelog;
}


sub link {
    my $self = shift || return;
    my $links = shift || 'default';
    my $ret;
    my $image_base = '/images';
    $links = " $links ";
    $links =~s/\s+default\s+/ info config graphs /;

    while ($links =~/\s?-(\w+)\s?/g) {
        $links          =~s/\s-?$1\s/ /g;    
    }
    foreach my $link (split(/\s+/, $links)) {
        if ($link eq 'config') {
            $ret    .= "<a href='/cgi-bin/editcage.cgi?cage_id=${\ $self->id(); }' title='Configure ${\ $self->name(); }'><img name='${\ $self->id(); }-$link' src=$image_base/config-button.gif width=15 height=15 border=0></a>";
        }
        if ($link eq 'info') {
            $ret    .= "<a href='/cgi-bin/cage.cgi?cage_id=${\ $self->id(); }' title='Info: ${\ $self->name(); }'><img name='${\ $self->id(); }-$link' src=$image_base/info-button.gif width=15 height=15 border=0></a>";
        }
    }
    return $ret || $self->link();
}

sub getServers {
    my $self = shift || return;
    my $params = shift;

    $params->{cage} = $self->id();
    $params->{all_silos} = 1;
    $uravo ||= new Uravo;
    return $uravo->getServers($params);
}

sub getRacks {
    my $self = shift || return;
    my $params = shift;

    $params->{cage} = $self->id();
    $uravo ||= new Uravo;
    return $uravo->getRacks($params);
}

sub cost {
    my $self = shift || return;
    my $params = shift;

    my $cost = 0;
    my @servers = $self->getServers();
    foreach my $server (@servers) {
        $cost += $server->cost($params);
    }
    return $cost;
}

sub delete {
    $uravo ||= new Uravo;
    $uravo->log("Uravo::Serverroles::Cage::delete()", 5);
    my $params = shift || return;
    my $changelog = shift || {note=>'Uravo::Serverroles::Cage::delete()', user=>$0};

    my $cage_id = $params->{cage_id} || return;
    return if ($cage_id eq 'unknown');

    foreach my $rack ($uravo->getRacks({cage_id=>$cage_id})) {
        $rack->update({cage_id=>'unknown'},$changelog);
    }

    $uravo->{db}->do("delete from changelog, changelog_detail using changelog inner join changelog_detail where changelog.object_id=? and changelog.object_type='cage' and changelog.id=changelog_detail.changelog_id", undef, ($cage_id));
    $uravo->{db}->do("delete from changelog where object_id=? and object_type='cage'", undef, ($cage_id));
    $uravo->{db}->do("delete from cage where cage_id=?", undef, ($cage_id));
    return;
}

sub id { my ($self) = @_; return $self->{'cage_id'}; }
sub name { my ($self) = @_; return $self->{'name'} || $self->{'cage_id'}; }
sub get { my ($self, $name) = @_; return $self->{$name}; }

1;
