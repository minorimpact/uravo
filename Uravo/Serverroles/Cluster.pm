package Uravo::Serverroles::Cluster;

use strict;

use Uravo;

our $uravo = $Uravo::uravo;

sub new {
    my $self	    = {};
    my $package	    = shift || return;
    my $cluster_id     = shift || return;

    $self->{cluster_id} = $cluster_id;
    $uravo ||= new Uravo;

    my $cluster_data;
    $cluster_data = $uravo->{db}->selectrow_hashref("SELECT * FROM cluster WHERE cluster_id=?", undef, ( $cluster_id )) || return;

    foreach my $key (keys %{$cluster_data}) {
        $self->{cluster_fields}  .= "$key ";
        $self->{$key} = $cluster_data->{$key};
    }

    $self->{object_type} =  'cluster';
    bless $self;
    return $self;
}

sub getServers {
    $uravo->log("Uravo::Serverroles::Cluster::getServers()", 5);
    my $self    = shift || return;
    my $params  = shift || {};

    my $local_params = {};
    map { $local_params->{$_}   = $params->{$_} } keys %{$params};
    $local_params->{cluster} = $self->id();
    $local_params->{all_silos} = 1;
    return $uravo->getServers($local_params);
}

sub getTypes {
    $uravo->log("Uravo::Serverroles::Cluster::getTypes()", 5);
    my $self    = shift || return;
    my $params  = shift;

    my $local_params = {};
    map { $local_params->{$_}   = $params->{$_} } keys %{$params};
    $local_params->{cluster} = $self->id();
    $local_params->{all_silos} = 1;
    return $uravo->getTypes($local_params);
}

sub _list {
    my $params = shift;

    $uravo ||= new Uravo;
    $uravo->log("Uravo::Serverroles::Cluster::_list()",9);

    my $cluster_id = ($params->{cluster} || $params->{cluster_id});
    my $type_id = ($params->{type} || $params->{type_id});
    my $silo_id = ($params->{silo} || $params->{silo_id});
    my $bu_id = ($params->{bu} || $params->{bu_id});

    my $list = $uravo->getCache("Cluster:_list:$cluster_id:$type_id:$silo_id:$bu_id");
    return keys %$list if ($list);

    my $select = "select distinct(cluster.cluster_id) as cluster_id from cluster, silo, bu";
    my $where = "where silo.silo_id = cluster.silo_id and silo.bu_id=bu.bu_id";

    if ($cluster_id) { $where .= " and cluster.cluster_id='$cluster_id'"; }
    if ($silo_id) { $where .= " and silo.silo_id='$silo_id'"; }
    if ($bu_id) { $where .= " and bu.bu_id='$bu_id'"; }

    my $sql = "$select $where";
    $uravo->log("$sql",8);

    my $clusters    = $uravo->{db}->selectall_arrayref($sql, {Slice=>{}}) || die("Can't get a list of clusters:" . $uravo->{db}->errstr);
    foreach my $cluster (@$clusters) { 
        my $id = $cluster->{cluster_id};
        next unless ($id);
        $list->{$id}++; 
    }

    $uravo->setCache("Cluster:_list:$cluster_id:$type_id:$silo_id:$bu_id", $list);
    return keys %$list;
}

sub getSilo {
    my $self = shift || return;

    return $uravo->getSilo($self->get("silo_id"));
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

    if ($field eq 'netblock_id') {
        $uravo->{db}->do("DELETE FROM cluster_netblock WHERE cluster_id=?", undef, ($self->id())) || die($uravo->{db}->errstr);
        foreach my $netblock_id (@$value) {
            $uravo->{db}->do("INSERT INTO cluster_netblock (cluster_id, netblock_id, create_date) VALUES (?,?,NOW())", undef, ($self->id(), $netblock_id));
        }

        return $changelog;
    }

    my $old_value =  $self->{$field};
    if ($old_value ne $value) {
        $uravo->changelog({object_type=>$self->{object_type}, object_id=>$self->id(), field_name=>$field, old_value=>$old_value, new_value=>$value},$changelog);
    }

    $uravo->{db}->do("UPDATE cluster SET $field=? WHERE cluster_id=?", undef, ( $value, $self->id() ));
    die "Content-type: text/html\n\n" . $uravo->{db}->errstr if ($uravo->{db}->errstr);
    $self->{$field} = $value;
    return $changelog;
}

sub link {
    my $self        = shift || return;
    my $links       = shift || 'default';
    my $ret;
    my $image_base  = '/images';

    $links          = " $links ";
    $links          =~s/\s+default\s+/ config graphs /;

    while ($links =~/\s?-(\w+)\s?/g) {
            $links          =~s/\s?-?$1\s?/ /g;
    }

    foreach my $link (split(/\s+/, $links)) {
        if ($link eq 'config') {
            $ret    .= "<a href='/cgi-bin/editcluster.cgi?cluster_id=${\ $self->id(); }' title='Configure ${\ $self->name(); }'><img name='${\ $self->id(); }-$link' src=$image_base/config-button.gif width=15 height=15 border=0></a>\n";
        }
        if ($link eq 'graphs') {
            $ret    .= "<a href='/cgi-bin/graph.cgi?cluster_id=${\ $self->id(); }&server_id=all' title='View graphs for ${\ $self->name(); }'><img src=$image_base/graph-button.gif width=15 height=15 border=0></a>\n";
        }
    }
    return $ret || $self->link();
}

sub changelog {
    my $self = shift || return;

    my $data = $uravo->{db}->selectall_arrayref("SELECT cl.id, cl.user, cl.ticket, cl.note, cl.create_date FROM changelog cl WHERE cl.object_id=? AND cl.object_type=? ORDER BY cl.create_date desc", {Slice=>{}}, ($self->id(), $self->type()));
    my @changelogs = ();
    foreach my $changelog (@$data) {
        my $data2 = $uravo->{db}->selectall_arrayref("SELECT field_name, old_value, new_value FROM changelog_detail WHERE changelog_id=?", {Slice=>{}}, ($changelog->{id}));
        my @changelog_details = ();
        foreach my $changelog_detail (@$data2) {
            push(@changelog_details, $changelog_detail);
        }
        $changelog->{details} = \@changelog_details;
        push(@changelogs, $changelog);
    }
    return @changelogs;
}

sub add {
    my $params  = shift || return;
    my $changelog = shift;

    my $cluster_id = $params->{cluster_id} || return;
    my $silo_id = $params->{silo_id} || return;

    $uravo->{db}->do("INSERT INTO cluster (cluster_id, silo_id, create_date) VALUES (?, ?, now())", undef, ($cluster_id, $silo_id)) || die ($uravo->{db}->errstr);

    if ($changelog) {
        $uravo->changelog({object_type=>'cluster', object_id=>$cluster_id, field_name=>'New cluster', new_value=>$cluster_id},$changelog);
    }
    
    return new Uravo::Serverroles::Cluster($cluster_id);
}

sub delete {
    my $params = shift || return;
    my $changelog = shift || {};

    my $cluster_id = $params->{cluster_id} || return;

    $uravo ||= new Uravo;
    foreach my $server ($uravo->getServers({cluster=>$cluster_id})) {
        $server->update({cluster_id=>'unknown'},$changelog);
    }

    $uravo->{db}->do("delete from changelog, changelog_detail using changelog inner join changelog_detail where changelog.object_id=? and changelog.object_type='cluster' and changelog.id=changelog_detail.changelog_id", undef, ($cluster_id)) || die($uravo->{db}->errstr);
    $uravo->{db}->do("delete from changelog where object_id=? and object_type='cluster'", undef, ($cluster_id)) || die($uravo->{db}->errstr);
    $uravo->{db}->do("delete from cluster where cluster_id=?",undef, ($cluster_id)) || die($uravo->{db}->errstr);
    return;
}

sub data {
    my $self = shift || return;
    my $data = {};

    foreach my $field (split(/ /, $self->{cluster_fields})) {
        $data->{$field} = $self->{$field};
    }
    return $data;
}

sub getNetblocks {
    my $self = shift || return;
    my $params = shift || {};

    my $local_params = {};
    foreach my $key (keys %$params) {
        $local_params->{$key} = $params->{$key};
    }
    $local_params->{cluster_id} = $self->id();

    return $uravo->getNetblocks($local_params);
}

# Misc info functions.
sub id		{ my ($self) = @_; return $self->{cluster_id}; }
sub name	{ my ($self) = @_; return $self->{name} || $self->id(); }
sub version { my ($self) = @_; return $self->{version}; }
sub type    { my ($self) = @_; return $self->{object_type}; }
sub get     { my ($self, $name) = @_; return $self->{$name}; }


1;
