package Uravo::Serverroles::Interface;

use strict;
use Uravo;
use Uravo::Serverroles::Netblock;
use Data::Dumper;

my $uravo;

sub new {
    my $self = {};
    my $package = shift || return;
    my $interface_id = shift || return;

    $uravo ||= new Uravo;
    my $interface_data;
    $interface_data = $uravo->{db}->selectrow_hashref("SELECT * FROM interface WHERE interface_id=?", undef, ( $interface_id ));
    return unless ($interface_data);

    foreach my $key (keys %{$interface_data}) {
        $self->{db_fields}  .= "$key ";
        $self->{$key} = $interface_data->{$key};
    }

    $self->{object_type} = 'interface';

    bless $self;
    return $self;
}

sub _list {
    $uravo ||= new Uravo;
    $uravo->log("Uravo::Serverroles::Interface::_list()", 9);
    my $params  = shift;

    my $where   = "where interface_id is not null";
    if ($params->{network}) { $where .= " and network='$params->{network}'"; }
    if ($params->{server}) { $where .= " and server_id='$params->{server}'"; }
    if ($params->{server_id}) { $where .= " and server_id='$params->{server_id}'"; }
    if ($params->{icmp}) { $where .= " AND icmp = '$params->{icmp}'"; }

    my $sql = "select distinct(interface_id) as interface_id from interface $where";
    my %list    = ();
    my $interfaces = $uravo->{db}->selectall_arrayref($sql, {Slice=>{}}) || die("Can't select interface:" . $uravo->{db}->errstr);
    foreach my $interface (@$interfaces) { $list{$interface->{interface_id}}++; }

    return grep { $_; } keys %list;
}

sub add {
    $uravo ||= new Uravo;
    $uravo->log("Uravo::Serverroles::Interface::add()", 5);

    my $params = shift || return;
    my $changelog = shift || {note=>"Uravo::Serverroles::Interface::add()", user=>$0};

    my $server_id = $params->{server_id} || return;
    my $ip = $params->{ip};
    my $network = $params->{network};
    my $netblock_id = $params->{netblock_id};
    my $mac = $params->{mac};
    my $name = $params->{name};
    my $main = $params->{main};
    my $icmp = $params->{icmp};
    my $interface_alias = $params->{interface_alias};

    return unless ($network || $netblock_id);
    if ($main eq 'on') { $main = 1; }
    if ($icmp eq 'on') { $icmp = 1; }

    # Check to see if there are any other interfaces on this network.  If not, set this new interface as main.
    my $main_count = $uravo->{db}->selectrow_hashref("SELECT COUNT(*) as main_count FROM interface WHERE server_id=? and network=? and main=1", undef, ($server_id, $network));
    if ($main_count && $main_count->{main_count} < 1) {
        $main = 1;
    }

    if ($ip && !$netblock_id) {
        my $netblock = Uravo::Serverroles::Netblock->getNetblockFromIp($ip);
        if ($netblock) {
            $netblock_id = $netblock->id();
            $network = $netblock->get('network');
        }
    }

    $uravo->{db}->do("insert into interface (server_id, ip, netblock_id, network, mac, name, main, icmp, create_date) values (?, ?, ?, ?, ?, ?, ?, ?, now())", undef, ($server_id, $ip, $netblock_id, $network, $mac, $name, $main, $icmp)) || die("Can't add new interface:" . $uravo->{db}->errstr);
    my $interface_id = $uravo->{db}->{mysql_insertid};

    if ($interface_alias && $interface_id) {
        foreach my $alias (@$interface_alias) {
            next unless ($alias);
            $uravo->{db}->do("INSERT INTO interface_alias (interface_id, alias, create_date, mod_date) VALUES (?, ?, NOW(), NOW())", undef, ($interface_id, $alias)) || die("Can't add interface alias for $server_id:" . $uravo->{db}->errstr);;
        }
    }

    if ($changelog) {
        $uravo->changelog({object_type=>'server', object_id=>$server_id,field_name=>"New $network interface", new_value=>"$network-$ip"},$changelog);
    }

    return new Uravo::Serverroles::Interface($interface_id);
}

sub delete {
    $uravo ||= new Uravo;
    $uravo->log("Uravo::Serverroles::Interface::delete()", 5);
    my $params = shift || return;
    my $changelog = shift || { note=>"Uravo::Serverroles::Interface::delete()", user=>$0};

    my $interface_id = $params->{interface_id} || return;

    my $interface_data = $uravo->{db}->selectrow_hashref("SELECT * FROM interface WHERE interface_id=?", undef, ($interface_id));
    
    if ($interface_data && $interface_data->{'main'}) {
        # Before we delete this main interface, we need to know if there are any other interfaces that we can designate as main.
        my $other_interfaces = $uravo->{db}->selectall_arrayref("SELECT * FROM interface WHERE server_id=? AND network=? AND interface_id != ? order by main desc", {Slice=>{}}, ($interface_data->{'server_id'}, $interface_data->{'network'}, $interface_id));
        if ($other_interfaces && scalar(@$other_interfaces) > 0) {
            my $new_main = new Uravo::Serverroles::Interface($other_interfaces->[0]->{interface_id});
            $new_main->update('main', 1);
        }
    }

    if ($changelog) {
        $uravo->changelog({object_type=>'server',object_id=>$interface_data->{'server_id'},field_name=>"Deleted " . $interface_data->{'network'} . " interface", old_value=>$interface_data->{'network'} . '-' . $interface_data->{'ip'}},$changelog);
    }

    $uravo->{db}->do("DELETE FROM interface_alias WHERE interface_id=?", undef, ($interface_id)) || die("Can't delete interface_alias:" . $uravo->{db}->errstr);
    $uravo->{db}->do("DELETE FROM interface WHERE interface_id=?", undef, ($interface_id)) || die("Can't delete interface:" . $uravo->{db}->errstr);
    return 1;
}

sub set {
    my $self        = shift || return;
    my $field       = shift || return;
    my $value       = shift;

    return $self->update($field, $value);
}

sub update {
    $uravo->log("Uravo::Serverroles::Interface::update()", 5);
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

    if ($field eq 'interface_alias') {
        $uravo->log("interface_alias:" . join(',', @$value), 9);
        my @db_value = $self->interface_alias();
        my $old_value = '';
        my $new_value = '';

        foreach my $db_alias (@db_value) {
            unless (grep { /^$db_alias$/ } @$value) {
                $uravo->{db}->do("DELETE FROM interface_alias WHERE interface_id=? AND alias=?", undef, ($self->id(), $db_alias)) || die("Can't delete interface_alias:" . $uravo->{db}->errstr);
                $old_value .= "$db_alias,";
            }
        }

        foreach my $alias (@$value) {
            next unless ($alias);
            unless (grep { /^$alias$/ } @db_value) {
                $uravo->{db}->do("INSERT INTO interface_alias (interface_id, alias, create_date, mod_date) VALUES (?, ?, NOW(), NOW())", undef, ($self->id(), $alias)) || die("Can't insert into interface_alias:" . $uravo->{db}->errstr);
                $new_value .= "$alias,";
            }
        }

        $old_value =~s/,$//;
        $new_value =~s/,$//;
        if ($old_value || $new_value) {
            $uravo->changelog({object_type=>'server', object_id=>$self->get('server_id'), field_name=>'interface_alias', old_value=>$old_value, new_value=>$new_value}, $changelog);
        }
        return $changelog;
    }

    if (($field eq 'icmp' || $field eq 'main') && $value eq 'on') { $value = 1; }

    my $old_value = $self->{$field};
    if ($old_value ne $value) {
        # Kind of a hack; this should technically be a log for the interface object itself, but since an interface can't exist on its own without a server object,
        # I'm attaching the changelog to the server object that owns the interface.
        $uravo->changelog({object_type=>'server', object_id=>$self->get('server_id'),field_name=>($field eq 'network'?$self->get('ip') ."-".$field:$self->get('network') ."-". $field),old_value=>$old_value, new_value=>$value},$changelog);
    }

    if ($field eq 'ip' && $value) {
        my $netblock = Uravo::Serverroles::Netblock->getNetblockFromIp($value);
        if ($netblock) {
            $uravo->{db}->do("UPDATE interface SET netblock_id=? WHERE interface_id=?", undef, ( $netblock->id(), $self->id() ));
        }
    }
    $uravo->{db}->do("UPDATE interface SET $field=? WHERE interface_id=?", undef, ( $value, $self->id() ));
    $self->{$field} = $value;

    return $changelog;
}

sub interface_alias {
    my $self = shift || return;
    my $interface_alias = $uravo->{db}->selectall_arrayref("SELECT * FROM interface_alias where interface_id=?", {Slice=>{}}, ( $self->id() ));

    my @interface_alias = ();
    foreach my $data ( @$interface_alias ) {
        push(@interface_alias, $data->{alias}) if ($data->{alias});
    }
    return @interface_alias;
}

sub getServer {
    my $self = shift || return;

    return $uravo->getServer($self->get('server_id'));
}

sub id { my ($self) = @_; return $self->{'interface_id'}; }
sub name { my ($self) = @_; return ($self->{'name'}?$self->{'name'}:$self->{'interface_id'}); }
sub get { my ($self, $name) = @_; return $self->{$name}; }
sub isMain { my ($self) = @_; return (($self->get('main'))?1:0); }

1;
