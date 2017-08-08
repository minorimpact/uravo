package Uravo::Serverroles::BU;

use strict;

use Uravo;
use Data::Dumper;

my $uravo;

sub new {
    my $self	    = {};
    my $package	    = shift || return;
    my $bu_id       = shift || return;

    $self->{bu_id}  = $bu_id;

    $uravo ||= new Uravo;
    my $bu_data;
    $bu_data = $uravo->{db}->selectrow_hashref("SELECT * FROM bu WHERE bu_id=?", undef, ( $bu_id )) || return;

    foreach my $key (keys %{$bu_data}) {
        $self->{bu_fields}  .= "$key ";
        $self->{$key} = $bu_data->{$key};
    }

    $self->{object_type} =  'bu';
    bless $self;
    return $self;
}

sub getSilos {
    my $self    = shift || return;
    my $params  = shift;

    my $tmp_params;
    map { $tmp_params->{$_}   = $params->{$_} } keys %{$params};
    $tmp_params->{bu} = $self->id();
    $tmp_params->{all_silos} = 1;
    return $uravo->getSilos($tmp_params);
}

sub getServers {
    my $self    = shift || return;
    my $params  = shift;

    my $tmp_params;
    map { $tmp_params->{$_}   = $params->{$_} } keys %{$params};
    $tmp_params->{bu} = $self->id();
    $tmp_params->{all_silos} = 1;
    return $uravo->getServers($tmp_params);
}

sub _list {
    my $params = shift;

    $uravo ||= new Uravo;
    my $where   = "where bu.bu_id is not null";
    if ($params->{bu} || $params->{bu_id}) { $where .= " and bu.bu='" . ($params->{bu} || $params->{bu_id}) . "'"; }
    if ($params->{silo} || $params->{silo_id}) { $where .= " and silo.silo='" . ($params->{silo} || $params->{silo_id}) . "'"; }
    if ($params->{name}) { $where .= " and b.name='" . ($params->{name}) . "'"; }

    my $sql         = "select distinct(bu.bu_id) from bu left join silo on (silo.bu_id=bu.bu_id) $where";
    #print "$sql\n";
    my %list    = ();
    my $bus    = $uravo->{db}->selectall_arrayref($sql, {Slice=>{}}); 
    die $uravo->{db}->errstr if ($uravo->{db}->errstr);
    foreach my $bu (@$bus) { $list{$bu->{bu_id}}++; }

    return grep { $_; } keys %list;
}

sub set {
    my $self        = shift || return;
    my $field       = shift || return;
    my $value       = shift;

    return $self->update($field, $value);
}


sub update {
    my $self            = shift || return;
    my $field           = shift || return;
    my $value           = shift;
    my $changelog       = shift;

    if (!$changelog && ref($value) eq 'HASH' && ref($field) eq 'HASH') {
        $changelog = $value;
    } elsif (!$changelog) {
        $changelog = { note=>'Uravo::Serverroles::BU::update()', user=>'unknown'};
    }

    if (ref($field) eq 'HASH') {
        foreach my $f (keys %$field) {
            $self->update($f, $field->{$f}, $changelog);
        }
        return $changelog;
    }

    my $old_value =  $self->{$field};
    if ($old_value ne $value) {
        $uravo->changelog({object_type=>$self->{object_type}, object_id=>$self->id(), field_name=>$field, old_value=>$old_value, new_value=>$value},$changelog);
    }

    $uravo->{db}->do("UPDATE bu SET $field=? WHERE bu_id=?", undef, ( $value, $self->id() )) || die($uravo->{db}->errstr);
    $self->{$field} = $value;
    return $changelog;
}

sub link {
    my $self        = shift || return;
    my $links       = shift || 'default';
    my $ret;
    my $image_base  = '/images';

    $links          = " $links ";
    $links          =~s/\s+default\s+/ info config /;

    while ($links =~/\s?-(\w+)\s?/g) {
            $links          =~s/\s?-?$1\s?/ /g;
    }

    foreach my $link (split(/\s+/, $links)) {
        if ($link eq 'config') {
            $ret    .= "<a href='/cgi-bin/editbu.cgi?bu_id=${\ $self->id(); }' title='Configure ${\ $self->id(); }'><img name='${\ $self->id(); }-$link' src=$image_base/config-button.gif width=15 height=15 border=0></a>\n";
        }
        if ($link eq 'info') {
            $ret    .= "<a href='/cgi-bin/bu.cgi?bu_id=${\ $self->id(); }' title='Info ${\ $self->id(); }'><img name='${\ $self->id(); }-$link' src=$image_base/info-button.gif width=15 height=15 border=0></a>\n";
         }
    }
    return $ret || $self->link();
}

sub changelog {
    my $self = shift || return;

    return $uravo->changelog({object_id=>$self->id(), object_type=>$self->type()});
}

sub add {
    $uravo ||= new Uravo;
    $uravo->log("Uravo::Serverroles::BU::add()", 5);

    my $params  = shift || return;
    my $changelog = shift || {note=>'Uravo::Serverroles::BU::add()', user=>$0};

    my $bu_id = $params->{bu_id} || return;

    $uravo->{db}->do("insert into bu (bu_id, name, create_date) values (?, ?, now())", undef, ($bu_id, $bu_id));
    die "Content-type: text/html\n\n" . $uravo->{db}->errstr if ($uravo->{db}->errstr);

    $uravo->changelog({object_type=>'bu', object_id=>$bu_id, field_name=>'New BU', new_value=>$bu_id},$changelog);
    
    return new Uravo::Serverroles::BU($bu_id);
}

sub delete {
    $uravo ||= new Uravo;
    $uravo->log("Uravo::Serverroles::BU::delete()", 5);
    my $params = shift || return;
    my $changelog = shift || {note=>'Uravo::Serverroles::BU::delete()', user=>'unknown'};

    my $bu_id = $params->{bu_id} || return;

    foreach my $silo ($uravo->getSilos({bu=>$bu_id})) {
        $silo->update({bu_id=>'core'},$changelog);
    }

    $uravo->{db}->do("delete from changelog, changelog_detail using changelog inner join changelog_detail where changelog.object_id=? and changelog.object_type='bu' and changelog.id=changelog_detail.changelog_id", undef, ($bu_id));
    $uravo->{db}->do("delete from changelog where object_id=? and object_type='bu'", undef, ($bu_id));
    $uravo->{db}->do("delete from bu where bu_id=?", undef, ($bu_id));
    return;
}

sub data {
    my $self = shift || return;
    my $data = {};

    foreach my $field (split(/ /, $self->{bu_fields})) {
        $data->{$field} = $self->{$field};
    }
    return $data;
}



# Misc info functions.
sub id		{ my ($self) = @_; return $self->{bu_id}; }
sub name	{ my ($self) = @_; return $self->{name} || $self->id(); }
sub type    { my ($self) = @_; return $self->{object_type}; }
sub get     { my ($self, $name) = @_; return $self->{$name}; }


1;
