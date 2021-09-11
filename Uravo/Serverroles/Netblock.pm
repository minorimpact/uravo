package Uravo::Serverroles::Netblock;

use strict;
use Uravo;
use NetAddr::IP;
use Net::CIDR;
use Data::Dumper;

my $uravo;

sub new {
    my $self = {};
    my $package = shift || return;
    my $netblock_id = shift || return;

    $uravo ||= new Uravo;
    my $netblock_data;
    $netblock_data = $uravo->{db}->selectrow_hashref("SELECT * FROM netblock WHERE netblock_id=?", undef, ( $netblock_id )) || return;

    foreach my $key (keys %{$netblock_data}) {
        $self->{netblock_fields}  .= "$key ";
        $self->{$key} = $netblock_data->{$key};
    }

    $self->{object_type} = 'netblock';

    bless $self;
    return $self;
}

sub getNetblockFromIp {
    my $package = shift;
    my $ip = shift || return;
    return unless (Net::CIDR::cidrvalidate($ip));
    $ip = NetAddr::IP->new($ip . "/32");

    $uravo ||= new Uravo;
    my $results = $uravo->{db}->selectall_arrayref("SELECT netblock_id, address FROM netblock", {Slice=>{}});
    foreach my $result (@$results) {
        my $netblock_id = $result->{netblock_id};
        my $address = $result->{address};
        if ($ip->within(NetAddr::IP->new($address))) {
            return new Uravo::Serverroles::Netblock($netblock_id);
        }
    }
}

sub info {
    my $self = shift || die;
    
    my $output = "";

    $output .= "id:" . $self->id() . "\n";
    $output .= "address:" . $self->get('address') . "\n";
    $output .= "discovery:" . ($self->get('discovery')?"yes":"no") . "\n";
    $output .= "network:" . $self->get('network') . "\n";
    $output .= "silo_id:" . $self->getSilo()->id() . "\n";
    print $output;
    return;
}

sub _list {
    my $params  = shift || {};

    $uravo ||= new Uravo;
    $uravo->log("Uravo::Serverroles::Netblock::_list()", 5);

    my $network = $params->{network};
    my $address = $params->{address};
    my $server_id = $params->{server_id};
    my $silo_id = $params->{silo} || $params->{silo_id};
    my $cluster_id = $params->{cluster} || $params->{cluster_id};

    # Do some crazy maneuvering to pull netblocks available to a server rather than netblocks used by a server.
    if ($server_id && $params->{available}) {
        my $server = $uravo->getServer($server_id);
        if ($server) {
            my $local_params = {};
                    
            foreach my $key (keys %$params) {
                $local_params->{$key} = $params->{$key};
            }   
            delete $local_params->{available};
            delete $local_params->{server_id};
            $local_params->{id_only} = 1;
            return $server->getAvailableNetblocks($local_params);
        }
        return;
    }

    my $select = "select n.netblock_id from netblock n";
    my $where = "where n.netblock_id is not null";
    if ($server_id) { 
        $select .= ", interface i";
        $where .= " and i.netblock_id=n.netblock_id and i.server_id='$server_id'";
    }
    if ($network) { $where .= " and n.network='$network'"; }
    if ($address) { $where .= " and n.address='$address'"; }
    if ($silo_id) { $where .= " and n.silo_id='$silo_id'"; }
    if ($cluster_id) {
        $select .= ", cluster_netblock cn";
        $where .= " and cn.netblock_id=n.netblock_id and cn.cluster_id='$cluster_id'";
    }

    my $sql         = "$select $where";
    $uravo->log($sql, 8);
    my %list    = ();
    my $netblocks    = $uravo->{db}->selectall_arrayref($sql, {Slice=>{}}) || die($uravo->{db}->errstr); 
    foreach my $netblock (@$netblocks) { $list{$netblock->{netblock_id}}++; }

    return grep { $_; } keys %list;
}

sub newip {
    my $self = shift || return;

    $uravo ||= new Uravo;
    my $network = $self->get('network');
    my $n = NetAddr::IP->new($self->get('address'));
    my $bits = $n->bits();
    my %vlans = ();
    my ($octet2,$octet3,$octet4);
    foreach my $i (@{$n->splitref($bits)}) {
        my $ip = $i->addr;
        if ($ip =~/^[0-9]+\.([0-9]+)\.([0-9]+)\./) {
            $octet2 = $1 unless ($octet2);
            $vlans{$2} =  $uravo->{db}->selectall_arrayref("select ip from interface where ip like '10.$octet2.$2.%' order by ip", {Slice=>{}}) unless ($vlans{$2});
        }
    }

    my $next_octet = 45;
    foreach my $vlan (sort keys %vlans) {
        #if (scalar(@$vlan1_ips) || scalar(@$vlan2_ips)) {
        $octet3 = $vlan;
        my $i = $vlans{$vlan};
        foreach (sort { $a->{ip} =~/\.(\d+)$/; my $ip1 = $1; $b->{ip} =~/\.(\d+)$/; my $ip2 = $1; return $ip1 <=> $ip2; } @$i) {
            my $ip = $_->{ip};
            $ip =~ /\.(\d+)$/;
            my $current_octet = $1;
            if ($current_octet < $next_octet) {
                next;
            } elsif ($current_octet == $next_octet) {
                $next_octet++;
                last if ($next_octet > 254);
            } elsif ($current_octet > $next_octet) {
                $octet4 = $next_octet;
                last;
            }
        }
        if (!$octet4 && $next_octet < 255) {
            $octet4 = $next_octet;
        }
        if (!$octet4) {
            $next_octet = 20;
        } else {
            last;
        }
    }
    if (!$octet4) {
        # No available IPs.
        return '';
    }
    return "10.$octet2.$octet3.$octet4";
}

sub add {
    my $params = shift || return;
    my $changelog = shift || {note=>'Uravo::Serverroles::Netblock::add()', user=>$0};

    my $netblock_id = $params->{netblock_id} || return;

    $uravo ||= new Uravo;
    $uravo->{db}->do("insert into netblock (netblock_id, create_date) values (?, now())", undef, ($netblock_id)) || die($uravo->{db}->errstr);
    $uravo->changelog({object_type=>'netblock',object_id=>$netblock_id,field_name=>"New netblock:$netblock_id",new_value=>$netblock_id},$changelog);
    return new Uravo::Serverroles::Netblock($netblock_id);
}

sub delete {
    $uravo ||= new Uravo;
    $uravo->log("Uravo::Serverroles::Netblock::delete()", 5);
    my $netblock_id = shift || return;

    my $data = $uravo->{db}->selectrow_hashref("select count(*) as c from interface where netblock_id =?", undef, ($netblock_id));
    if ($data->{c} > 0) {
        return;
    }

    $uravo->{db}->do("delete from netblock where netblock_id=?", undef, ($netblock_id));
    die "Content-type: text/html\n\n" . $uravo->{db}->errstr if ($uravo->{db}->errstr);
    return 1;
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
        $changelog = { note=>'Uravo::Serverroles::Netblock::update()', user=>$0};
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

    $uravo->{db}->do("UPDATE netblock SET $field=? WHERE netblock_id=?", undef, ( $value, $self->id() )) || die($uravo->{db}->errstr);
    $self->{$field} = $value;
    return $changelog;
}

sub link {
    my $self = shift || return;
    my $links = shift || 'default';
    my $ret;
    my $image_base = '/images';
    $uravo ||= new Uravo;
    $links = " $links ";
    $links =~s/\s+default\s+/ info config graphs /;

    while ($links =~/\s?-(\w+)\s?/g) {
        $links          =~s/\s-?$1\s/ /g;
    }
    foreach my $link (split(/\s+/, $links)) {
        if ($link eq 'config') {
            $ret    .= "<a href='/cgi-bin/editnetblock.cgi?netblock_id=${\ $self->id(); }' title='Configure ${\ $self->id(); }'><img name='${\ $self->id(); }-$link' src=$image_base/config-button.gif width=15 height=15 border=0></a>";   
        }
        if ($link eq 'info') {
            $ret    .= "<a href='/cgi-bin/netblock.cgi?netblock_id=${\ $self->id(); }' title='Info: ${\ $self->id(); }'><img name='${\ $self->id(); }-$link' src=$image_base/info-button.gif width=15 height=15 border=0></a>";
        }
    }
    return $ret || $self->link();
}

sub getServers {
    my $self = shift || return;
    my $params = shift;

    $params->{netblock} = $self->id();
    $params->{all_silos} = 1;
    $uravo ||= new Uravo;
    return $uravo->getServers($params);
}

sub getSilo {
    my $self = shift || return;
    $uravo->log("Uravo::Serverroles::Netblock::getSilo()", 5);

    $uravo ||= new Uravo;
    if ($self->{silo_id}) {
        return $uravo->getSilo($self->{silo_id});
    }
    return;
}

sub data {
    my $self = shift || return;
    my $data = {};

    foreach my $field (split(/ /, $self->{netblock_fields})) {
        $data->{$field} = $self->{$field};
    }
    return $data;
}

sub id { my ($self) = @_; return $self->{'netblock_id'}; }
sub cage_id { my ($self) = @_; return $self->{'cage_id'}; }
sub get { my ($self, $name) = @_; return $self->{$name}; }

1;
