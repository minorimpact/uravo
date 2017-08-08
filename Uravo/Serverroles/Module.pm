package Uravo::Serverroles::Module;

use strict;

use Uravo;

my $uravo;

sub new {
    my $self	    = {};
    my $package	    = shift || return;
    my $module_id     = shift || return;

    $uravo ||= new Uravo;

    my $module_data = $uravo->{db}->selectrow_hashref("SELECT * FROM module WHERE module_id=?", undef, ( $module_id )) || return;
    return unless ($module_data);

    foreach my $key (keys %{$module_data}) {
        $self->{module_fields}  .= "$key ";
        $self->{$key} = $module_data->{$key};
    }

    bless $self;
    return $self;
}

sub add {
    # Disable the add() function for now, until I decide how modules will get added to the system.
    return;
    my $params = shift || return;
    my $changelog = shift || {user=>'unknown', note=>'Uravo::Serverroles::Module::add()'};

    my $module_id = $params->{module_id} || return;

    $uravo ||= new Uravo;
    my $insert_module = $uravo->{db}->do("insert into module (module_id, create_date) values (?, now())",undef, ($module_id)) || die($uravo->{db}->errstr);
    if ($changelog) {
        $uravo->changelog({object_type=>'module',object_id=>$module_id,field_name=>'New module.',new_value=>$module_id},$changelog);
    }

    return new Uravo::Serverroles::Module($module_id);
}

sub getServers {
    my $self    = shift || return;
    my $params  = shift;


    my $tmp_params;
    map { $tmp_params->{$_}   = $params->{$_} } keys %{$params};
    $tmp_params->{module_id} = $self->id();
    $tmp_params->{all_silos} = 1;
    return $uravo->getServers($tmp_params);
}

sub _list {
    my $params = shift || {};

    $uravo ||= new Uravo;
    $uravo->log("Uravo::Serverroles::Module::_list(" . join(",", map {"$_=$params->{$_}"} keys %$params) . ")",9);

    my $select = "SELECT distinct(m.module_id) FROM module m LEFT JOIN type_module tm ON (m.module_id=tm.module_id) left join server_type st on (tm.type_id=st.type_id) left join server s on (s.server_id=st.server_id)";
    my $where = "WHERE m.module_id IS NOT NULL";

    my $module_id = ($params->{module_id} || $params->{module});
    my $server_id = ($params->{server_id} || $params->{server});
    my $remote = $params->{remote};
    my $type_id = ($params->{type_id} || $params->{type});
    my $enabled = $params->{enabled};

    if ($module_id) { $where .= " and m.module_id='$module_id'"; }

    if ($remote ne '') {
        $remote = 1 unless ($remote == 0);
        $where .= " and m.remote = $remote";
    }

    if ($type_id) { $where .= " and tm.type_id='$type_id'"; }
    if ($server_id) { $where .= " AND s.server_id='$server_id'"; }

    my %list = ();
    my $sql = "$select $where";
    $uravo->log($sql, 9);
    my $m = $uravo->{db}->selectall_arrayref($sql, {Slice=>{}}) || die ($uravo->{db}->errstr);
    foreach my $module (@$m) {
        $list{$module->{module_id}}++;
    }

    if ($enabled) { $sql .= " AND tm.enabled=0"; 
        $uravo->log($sql, 9);
        my $m = $uravo->{db}->selectall_arrayref($sql, {Slice=>{}}) || die ($uravo->{db}->errstr);
        foreach my $module (@$m) {
            delete $list{$module->{module_id}};
        }
    }

    return keys %list;
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
        $changelog = { user=>'unknown', note=>'Uravo::Serverroles::Module::update()'};
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

    $uravo->{db}->do("UPDATE module SET $field=? WHERE module_id=?", undef, ( $value, $self->id() )) || die($uravo->{db}->errstr);
    $self->{$field} = $value;
    return $changelog;
}

sub link {
    my $self        = shift || return;
    my $links       = shift || 'default';
    my $ret;
    my $image_base  = '/images';

    $links          = " $links ";
    $links          =~s/\s+default\s+/ config /;

    while ($links =~/\s?-(\w+)\s?/g) {
        $links          =~s/\s?-?$1\s?/ /g;
    }

    foreach my $link (split(/\s+/, $links)) {
        if ($link eq 'config') {
            $ret    .= "<a href='/cgi-bin/editmodule.cgi?module_id=${\ $self->id(); }' title='Configure ${\ $self->id(); }'><img name='${\ $self->id(); }-$link' src=$image_base/config-button.gif width=15 height=15 border=0></a>\n";
        }
    }
    return $ret || $self->link();
}

sub get {
    my ($self, $name) = @_;

    return $self->{$name};
}

sub changelog {
    my $self = shift || return;

    return $uravo->changelog({object_id=>$self->id(), object_type=>$self->type()});
}

sub delete {
    my $params = shift || return;
    my $changelog = shift || {user=>'unknown', note=>'Uravo::Serverroles::Module::delete()'};

    my $module_id = $params->{module_id} || return;

    $uravo ||= new Uravo;

    $uravo->{db}->do("delete from type_module where module_id=?", undef, ($module_id)) || die($uravo->{db}->errstr);
    $uravo->{db}->do("delete from changelog, changelog_detail using changelog inner join changelog_detail where changelog.object_id=? and changelog.object_type='module' and changelog.id=changelog_detail.changelog_id", undef, ($module_id)) || die($uravo->{db}->errstr);
    $uravo->{db}->do("delete from changelog where object_id=? and object_type='module'", undef, ($module_id)) || die($uravo->{db}->errstr);
    $uravo->{db}->do("delete from module where module_id=?", undef, ($module_id)) || die($uravo->{db}->errstr);

    return;
}

sub data {
    my $self = shift || return;
    my $data = {};

    foreach my $field (split(/ /, $self->{module_fields})) {
        $data->{$field} = $self->{$field};
    }
    return $data;
}

sub enabled {
    my $self = shift || return;
    my $type_id = shift || return;

    return $uravo->{db}->selectrow_hashref("SELECT enabled FROM type_module WHERE module_id=? and type_id=?", undef, ($self->id(), $type_id))->{enabled};
}

# Misc info functions.
sub id		{ my ($self) = @_; return $self->{module_id}; }
sub name	{ my ($self) = @_; return $self->{name} || $self->id(); }
sub type    { my ($self) = @_; return $self->{object_type}; }

1;
