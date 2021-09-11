package Uravo::Serverroles::Silo;

use strict;

use Uravo;
use Uravo::Util;
use Data::Dumper;

my $uravo;

sub new {
    my $self	    = {};
    my $package	    = shift || return;
    my $id          = shift || return;

    $uravo ||= new Uravo;

    if (ref($id) eq "HASH") {
		my $params = $id;
		die "must specify silo_id" unless (defined($params->{silo_id}));
        if (!defined($params->{bu_id})) {
            my $bu = new Uravo::Serverroles::BU() || die "Can't get default BU";
            $params->{bu_id} = $bu->id();
        }
		$uravo->{db}->do("INSERT INTO silo (silo_id, bu_id, `default`, create_date) VALUES (?, ?, ?, now())", undef, ($params->{silo_id}, $params->{bu_id}, $params->{default}||0)) || die ($uravo->{db}->errstr);
    }
	else {
		$self->{silo_id}  = $id;

		my $silo_data;
		$silo_data = $uravo->{db}->selectrow_hashref("SELECT * FROM silo WHERE silo_id=?", undef, ( $self->{silo_id} ))|| return;

		foreach my $key (keys %{$silo_data}) {
			$self->{silo_fields}  .= "$key ";
			$self->{$key} = $silo_data->{$key};
		}
	}
    $self->{object_type} =  'silo';
    bless $self;
    return $self;
}

sub getClusters {
    my $self    = shift || return;
    my $params  = shift;

    my $tmp_params;
    map { $tmp_params->{$_}   = $params->{$_} } keys %{$params};
    $tmp_params->{silo} = $self->id();
    $tmp_params->{all_silos} = 1;
    return $uravo->getClusters($tmp_params);
}

sub getServers {
    my $self    = shift || return;
    my $params  = shift;

    $uravo ||= new Uravo;

    my $tmp_params;
    map { $tmp_params->{$_}   = $params->{$_} } keys %{$params};
    $tmp_params->{silo} = $self->id();
    $tmp_params->{all_silos} = 1;
    return $uravo->getServers($tmp_params);
}

sub getBU {
    my $self = shift || return;

    $uravo ||= new Uravo;

    return $uravo->getBU($self->get('bu_id'));
}

sub _list {
    my $params = shift;
    Uravo::Util::clean_params($params);

    my $where   = "where silo.silo_id is not null and silo.bu_id=bu.bu_id";
    if ($params->{silo_id}) { $where .= " and silo.silo_id = '" . ($params->{silo_id}) . "'"; }
    if ($params->{bu_id}) { $where .= " and bu.bu_id = '" . ($params->{bu_id}) . "'"; }
    if ($params->{name}) { $where .= " and silo.name = '" . ($params->{name}) . "'"; }

    $uravo ||= new Uravo;
    my $sql         = "select distinct(silo.silo_id) from silo,bu $where";
    #print "$sql\n";
    my %list    = ();
    my $silos    = $uravo->{db}->selectall_arrayref($sql, {Slice=>{}}) || die("Can't select from silo:" . $uravo->{db}->errstr); 
    foreach my $silo (@$silos) { $list{$silo->{silo_id}}++; }

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
        $uravo->changelog({object_type=>$self->{object_type}, object_id=>$self->id(), field_name=>$field, old_value=>$old_value, new_value=>$value},$changelog);
    }

    $uravo->{db}->do("UPDATE silo SET $field=? WHERE silo_id=?", undef, ( $value, $self->id() )) || die("Can't update silo:" . $uravo->{db}->errstr);
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
            $ret    .= "<a href='/cgi-bin/editsilo.cgi?silo_id=${\ $self->id(); }' title='Configure ${\ $self->id(); }'><img name='${\ $self->id(); }-$link' src=$image_base/config-button.gif width=15 height=15 border=0></a>\n";
        }
        if ($link eq 'info') {
            $ret    .= "<a href='/cgi-bin/silo.cgi?silo_id=${\ $self->id(); }' title='Info ${\ $self->id(); }'><img name='${\ $self->id(); }-$link' src=$image_base/info-button.gif width=15 height=15 border=0></a>\n";
         }
    }
    return $ret || $self->link();
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

sub changelog {
    my $self = shift || return;

    return $uravo->changelog({object_id=>$self->id(), object_type=>$self->type()});
}

sub add {
    my $params  = shift || return;
    my $changelog = shift || {note=>'Uravo::Serverroles::Silo::add()', user=>$0};

    my $silo_id = $params->{silo_id} || return;
    my $bu_id = $params->{bu_id} || return;

    $uravo->{db}->do("insert into silo (silo_id, bu_id, create_date) values (?, ?, now())", undef, ($silo_id, $bu_id)) || die("can't insert into silo:" . $uravo->{db}->errstr);

    $uravo->changelog({object_type=>'silo', object_id=>$silo_id, field_name=>'New Silo', new_value=>$silo_id},$changelog);
    
    return new Uravo::Serverroles::Silo($silo_id);
}

sub delete {
    my $params = shift || return;
    my $changelog = shift || {note=>'Uravo::Serverroles::Sio::delete()', user=>$0};

    my $silo_id = $params->{silo_id} || return;

    $uravo ||= new Uravo;
    foreach my $cluster ($uravo->getClusters({silo=>$silo_id})) {
        $cluster->update({silo_id=>'unknown'},$changelog);
    }

    $uravo->{db}->do("delete from changelog, changelog_detail using changelog inner join changelog_detail where changelog.object_id=? and changelog.object_type='silo' and changelog.id=changelog_detail.changelog_id", undef, ($silo_id)) || die($uravo->{db}->errstr);
    $uravo->{db}->do("delete from changelog where object_id=? and object_type='silo'", undef, ($silo_id)) || die($uravo->{db}->errstr);
    $uravo->{db}->do("delete from silo where silo_id=?",undef, ($silo_id)) || die($uravo->{db}->errstr);
    return;
}

sub data {
    my $self = shift || return;
    my $data = {};

    foreach my $field (split(/ /, $self->{silo_fields})) {
        $data->{$field} = $self->{$field};
    }
    return $data;
}

sub getNetblocks {
    my $self = shift || return;
    my $params = shift;

    $uravo ||= new Uravo;

    my $local_params = {};
    foreach my $key (keys %$params) {
        $local_params->{$key} = $params->{$key};
    }
    $local_params->{silo_id} = $self->id();
    return $uravo->getNetblocks($local_params);
}

sub getDefaultCluster {
    my $self = shift || return;
    $uravo ||= new Uravo;
    $uravo->log("Uravo::Serverroles::Silo::getDefaultCluster()", 5);

    my $row = $uravo->{db}->selectrow_hashref("SELECT cluster_id FROM cluster WHERE silo_default=1 AND silo_id=?", undef, ($self->id()));
    if ($row && defined($row->{cluster_id})) {
        return $uravo->getCluster($row->{cluster_id});
    }
    return;
}


# Misc info functions.
sub id		{ my ($self) = @_; return $self->{silo_id}; }
sub name	{ my ($self) = @_; return $self->{name} || $self->id(); }
sub type    { my ($self) = @_; return $self->{object_type}; }
sub get     { my ($self, $name) = @_; return $self->{$name}; }

# Non object functions
sub add {
    my $params  = shift || return;
    my $changelog = shift;
    $uravo ||= new Uravo;

    my $silo = new Uravo::Serverroles::Silo($params) || die ("can't add new silo");
    
    if ($changelog) {
        $uravo->changelog({object_type=>'silo', object_id=>$silo->id(), field_name=>'New silo', new_value=>$silo->id()},$changelog);
    }

    return $silo;
}

1;
