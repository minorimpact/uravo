package Uravo::Serverroles::Server;

use strict;

use Data::Dumper;

use MinorImpact::InfluxDB;

use Uravo::Serverroles::Interface;
use Uravo::Pylon;

my $uravo;
my $ranges      = {'2d'=>'hourly', '1w'=>'daily', '1m'=>'weekly', '3m'=>'weekly', '2y'=>'monthly'};
my $bb_ranges   = {'2d'=>'hourly', '1w'=>'daily', '1m'=>'weekly', '3m'=>'weekly', '2y'=>'monthly'};

sub new {
    my $package	    = shift || return;
    my $server_id   = shift || return;
    my $params      = shift;
    my $self	    = bless({}, $package);

    $uravo = new Uravo;
    $uravo->log("Uravo::Serverroles::Server::new()", 5);
    my $db_data = $uravo->getCache("server:$server_id");
    unless ($db_data) {
        $db_data = $uravo->{db}->selectrow_hashref("SELECT * FROM server WHERE server_id=?", undef, ( $server_id )) ;
    }

    unless ($db_data) {
        if (!$params->{exactmatch}) {
            $db_data = _searchServers($server_id, $params);
        }
        $uravo->log("server_id='$server_id'", 9);
    }

    return unless ($db_data);
    $uravo->setCache("server:$server_id", $db_data);
    
    # The serch can turn up a server with a slightly different server_id (ie, ID.example.com vs. ID), so reset the server_id
    # we were looking for to match the one we found.
    if ($server_id ne $db_data->{'server_id'}) {
        $server_id = $db_data->{'server_id'};
    }
    foreach my $key (keys %$db_data) {
        $self->{server_fields} .= "$key ";
    	$self->{$key} = $db_data->{$key};
    }

    $self->{type_ids} = ();
    my $types = $uravo->{db}->selectall_arrayref("SELECT type_id FROM server_type WHERE server_id=?", {Slice=>{}}, ( $server_id )) || die("Can't get types for $server_id:" . $uravo->{db}->errstr);
    foreach my $t (@$types) {
        push(@{$self->{type_ids}}, $t->{type_id});
    }

    my $cluster_info = $uravo->{db}->selectrow_hashref("SELECT silo_id FROM cluster WHERE cluster_id=?", undef, ( $self->{cluster_id} )) || die("Can't get silo value:" . $uravo->{db}->errstr);
    $self->{silo_id} = $cluster_info->{silo_id};

    $self->{object_type} =  'server';
    return $self;
}

sub addInterface {
    $uravo->log("Uravo::Serverroles::Interface::addInterface()", 5);
    my $self = shift || return;
    my $params = shift || return;
    my $changelog = shift || { note=>"Uravo::Serverroles::Interface::addInterface()", user=>$0};

    $params->{server_id} = $self->id();
 
    return Uravo::Serverroles::Interface::add($params, $changelog);
}

sub deleteInterface {
    $uravo->log("Uravo::Serverroles::Interface::deleteInterface()", 5);

    my $self = shift || return;
    my $params = shift || return;
    my $changelog = shift || { note=>"Uravo::Serverroles::Interface::deleteInterface()", user=>$0};

    return Uravo::Serverroles::Interface::delete($params, $changelog);
}
 
sub getInterfaces {
    my $self        = shift || return;
    my $params      = shift;

    $params->{'server'} = $self->id();
    my @list        = ();
    foreach my $interface_id (Uravo::Serverroles::Interface::_list($params)) {
        if ($params->{'id_only'}) {
            push @list, $interface_id; 
        } else { 
            push @list, $self->getInterface($interface_id); 
        }
    }
    if ($params->{'pre_sort'} && $params->{'id_only'}) {
         return sort @list;
    } elsif ($params->{'pre_sort'}) {
         return sort { $a->id() cmp $b->id(); } @list;
    }
    return @list;
}
 
sub getInterface {
    my $self = shift || return;
    my $interface_id = shift || return;

    return new Uravo::Serverroles::Interface($interface_id);
}
 
sub getProcs {
    $uravo->log("Uravo::Serverroles::Server::getProcs()", 5);
    my $self    = shift || return;

    my $proc_list;

    foreach my $type_id ( @{$self->{type_ids}}) {
       my $pl   = ($uravo->getType($type_id))->getProcs();
       foreach my $proc (keys %$pl) {
           if ($proc_list->{$proc}) {
               $proc_list->{$proc}  = $pl->{$proc} if ($proc_list->{$proc} lt $pl->{$proc});
           } else {
               $proc_list->{$proc}  = $pl->{$proc};
           }
       }
   }
   return $proc_list;
}

sub _searchServers {
    $uravo ||= new Uravo;
    $uravo->log("Uravo::Serverroles::Server::_searchServers()", 5);
    my $unknown_id  = shift || return;
    my $params      = shift;
    
    my $data        = $unknown_id;
    my $db_data;
    $data           =~s/,/\./g;
    my $short_data  = $1 if ($data =~/^([^\.]+)\./ && ! $params->{exact});

    if ( $data =~/^\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}$/) {
        $db_data	    = $uravo->{db}->selectrow_hashref("SELECT s.* FROM server s, interface i WHERE s.server_id=i.server_id AND i.ip=?", undef, ( $data ));
        return $db_data if ($db_data);
    }

    $uravo->log("data='$data'",9);
    $db_data	    = $uravo->{db}->selectrow_hashref("SELECT * FROM server WHERE server_id=?", undef, ( $data ));
    return $db_data if ($db_data);
    $db_data	    = $uravo->{db}->selectrow_hashref("SELECT * FROM server WHERE server_id=?", undef, ( $short_data )) if ($short_data); 
    return $db_data if ($db_data);
    $db_data	    = $uravo->{db}->selectrow_hashref("SELECT * FROM server WHERE hostname=?", undef, ( $data )); 
    return $db_data if ($db_data);
    $db_data	    = $uravo->{db}->selectrow_hashref("SELECT * FROM server WHERE hostname=?", undef, ( $short_data )) if ($short_data); 
    return $db_data if ($db_data);

    if ($data =~ /^([a-z])e([0-9]+)\-([0-9]+)$/) {
        my $cage_letter = $1;
        my $rack_number = $2;
        my $pos = $3;
        my $new_hostname = "${cage_letter}i${rack_number}-$pos";
        $db_data	    = $uravo->{db}->selectrow_hashref("SELECT * FROM server WHERE server_id=?", undef, ( $new_hostname )); 
        return $db_data if ($db_data);
    }
    if ($short_data && $short_data =~ /^([a-z])e([0-9]+)\-([0-9]+)$/) {
        my $cage_letter = $1;
        my $rack_number = $2;
        my $pos = $3;
        my $new_hostname = "${cage_letter}i${rack_number}-$pos";
        $db_data	    = $uravo->{db}->selectrow_hashref("SELECT * FROM server WHERE server_id=?", undef, ( $new_hostname )); 
        return $db_data if ($db_data);
    }
}

sub _list {
    $uravo ||= new Uravo;
    $uravo->log("Uravo::Serverroles::Server::_list()", 5);

    my $params  = shift;

    my $cluster_id = ($params->{cluster} || $params->{cluster_id});
    my $type_id = ($params->{type} || $params->{type_id});
    my $silo_id = ($params->{silo} || $params->{silo_id});
    my $bu_id = ($params->{bu} || $params->{bu_id});
    my $rack_id = ($params->{rack} || $params->{rack_id});
    my $cage_id = ($params->{cage} || $params->{cage_id});
    my $netblock_id = ($params->{netblock} || $params->{netblock_id});
    my $remote = $params->{remote};
    my $ip = $params->{ip};
    my $hostname = $params->{hostname};
    my $text_string = $params->{text_string};

    my $list = $uravo->getCache("Serer:_list:$cluster_id:$type_id:$silo_id:$bu_id:$rack_id:$cage_id:$netblock_id:$remote:$ip:$hostname:$text_string");
    #return keys %$list if ($list);

    my $select = "SELECT DISTINCT(s.server_id) AS server_id FROM server s left join interface i on (s.server_id=i.server_id) left join server_type st on (st.server_id=s.server_id), cluster c, silo, bu";
    my $where = "where s.cluster_id=c.cluster_id and silo.silo_id=c.silo_id and bu.bu_id=silo.bu_id";

    if ($cluster_id =~/(.+)\.(.+)/) {
        $cluster_id = $1;
        $type_id = $2;
    }
    
    if ($type_id) { 
        if ($type_id =~/,/) {
            my @types = split(",",$type_id);
            $where .= " and (" . join(" or ", map { "sr.type_id = '$_'" } @types) . ")";
        } elsif ($type_id =~/^!(\w+)$/) {
            $where .= " and st.type_id != '$1'";
        } else {
            $where .= " and st.type_id = '$type_id'"; 
        }
    }
    
    if ($silo_id) {
        if ($silo_id =~/^!(\w+)$/) {
            $where .= " and silo.silo_id != '$1'";
        } else {
            $where .= " and silo.silo_id = '$silo_id'"; 
        }
    }

    if ($cluster_id) {
        if ($cluster_id =~/,/) {
            my @clusters = split(",",$cluster_id);
            $where .= " and (" . join(" or ", map { "s.cluster_id = '$_'" } @clusters) . ")";
        } elsif ($cluster_id =~/^!(\w+)$/) {
            $where .= " and s.cluster_id != '$1'";
        } else {
            $where .= " and s.cluster_id='$cluster_id'"; 
        }
    }

    if ($bu_id) {
        if ($bu_id =~/,/) {
            my @bu_ids = split(",",$bu_id);
            $where .= " and (" . join(" or ", map { "bu.bu_id = '$_'" } @bu_ids) . ")";
        } elsif ($bu_id =~/^!(\w+)$/) {
            $where .= " and bu.bu_id != '$1'";
        } else {
            $where .= " and bu.bu_id = '$bu_id'"; 
        }
    }

    if ($rack_id) {
        $select .= ", rack";
        $where .= " and rack.rack_id = s.rack_id";
        if ($rack_id =~/,/) {
            my @racks = split(",",$rack_id);
            $where .= " and (" . join(" or ", map { "s.rack_id = '$_'" } @racks) . ")";
        } elsif ($rack_id =~/^!(\w+)$/) {
            $where .= " and s.rack_id != '$1'";
        } else {
            $where .= " and s.rack_id = '$rack_id'"; 
        }
    }

    if ($cage_id) {
        unless ($rack_id) {
            $select .= ", rack";
            $where .= " and rack.rack_id = s.rack_id";
        }
        if ($cage_id =~/,/) {
            my @cages = split(",",$cage_id);
            $where .= " and (" . join(" or ", map { "rack.cage_id = '$_'" } @cages) . ")";
        } elsif ($cage_id =~/^!(\w+)$/) {
            $where .= " and rack.cage_id != '$1'";
        } else {
            $where .= " and rack.cage_id = '$cage_id'"; 
        }
    }

    if ($netblock_id) {
        if ($netblock_id =~/,/) {
            my @netblocks = split(",",$netblock_id);
            $where .= " and (" . join(" or ", map { "i.netblock_id = '$_'" } @netblocks) . ")";
        } elsif ($netblock_id =~/^!(\w+)$/) {
            $where .= " and i.netblock_id != '$1'";
        } else {
            $where .= " and i.netblock_id='$netblock_id'"; 
        }
    }

    if ($ip) { $where .= " and i.ip LIKE '$ip%'"; }
    if ($hostname) { $where .= " and s.hostname LIKE '$hostname%'"; }

    if ($remote) {
        $select .= ", type_module, module";
        $where .= " and st.type_id=type_module.type_id and type_module.module_id=module.module_id and module.remote=1";
    }

    if ($text_string) {
        $where .= " and (s.server_id like '\%$text_string\%' or sr.cluster_id like '\%$text_string\%' or sr.type_id like '\%$text_string\%')";
    }

    my $sql = "$select $where";
    $uravo->log($sql, 7);
    my $servers = $uravo->{db}->selectall_arrayref($sql, {Slice=>{}}, ()) || die("Can't select servers: " . $uravo->{db}->errstr);
  
    foreach my $server (@$servers) {
        my $id = $server->{server_id};
        next unless ($id);
        $list->{$id}++;
    }

    $uravo->setCache("Serer:_list:$cluster_id:$type_id:$silo_id:$bu_id:$rack_id:$cage_id:$netblock_id:$remote:$ip:$hostname:$text_string", $list);
    return keys %$list;
}

sub getTypes {
    $uravo->log("Uravo::Serverroles::Server::getTypes()", 5);
    my $self = shift || return;
    my $params = shift;
    
    my @types   = ();

    foreach my $type_id (@{$self->{type_ids}}) {
        if ($params->{id_only}) {
            push(@types, $type_id);
        } else {
            my $t = $uravo->getType($type_id);
            push(@types, $t);
        }
    }

    return @types;
}

sub getCluster {
    my $self = shift || return;

    return $uravo->getCluster($self->{cluster_id});
}

sub getSilo {
    my $self = shift || return;

    return $self->getCluster()->getSilo();
}

sub equals {
    my $self	= shift || return;
    my $server	= shift || return;

    return $self->id() eq $server->id();
}

sub graph {
    my $self        = shift || return;
    my $graph_id    = shift || return;
    my $value       = shift;
    my $type        = shift;

    chomp($graph_id);
    eval {
        if ($uravo->{config}->{influxdb_server}) {
            my $metric = "$graph_id,server_id=" . $self->id() . ",cluster_id=" . $self->cluster_id();
            MinorImpact::InfluxDB::influxdb({ db => 'uravo',       metric => $metric, remote => $uravo->{config}->{influxdb_server}, value => $value });
        }
    };
    #eval {
    #    if ($uravo->{config}{pylon_server}) {
    #        #Uravo::Pylon::pylon({remote=>$uravo->{config}->{outpost_server}, command=>"add|$graph_id|" . $self->id(). "|$value" . (($type eq 'COUNTER')?'|counter':''), port=>$uravo->{config}->{outpost_pylon_port}});
    #    }
    #};
}

sub graph_data {
    my $self = shift || return;
    my $graph_id = shift || return;
    my $range = shift || 'e-48h';
    my $remote = shift;
    my $offset = time;
    my $source = 'rrd';

    if (ref($graph_id) eq 'HASH') {
        my $args = $graph_id;
        $graph_id = $args->{graph_id} || return;
        $range = $args->{range} || 'e-48h';
        $remote = $args->{remote};
        $offset = $args->{offset} || time;
        $source = $args->{source} || 'rrd';
    }

    my $server_id = $self->id();

    my $sub_limit = $1 if ($graph_id =~s/,(.+)$//);
    my $now = time();

    my $data;

    $range =~s/^e-//;
    if ($range =~/([0-9]+)h$/) {
        $range = time() - ($1 * 3600) + 300;
    } elsif ($range =~/([0-9]+)d$/) {
        $range = time() - ($1 * 3600 * 24) + 300;
    }

    foreach my $check_id (grep { /^($graph_id,|$graph_id$)/; } split(/\|/, Uravo::Pylon::pylon({remote=>$uravo->{config}->{outpost_server}, command=>"checks|$server_id", port=>$uravo->{config}->{outpost_pylon_port}}))) {
        my $sub_id = $graph_id;
        if ($check_id =~/$graph_id,(.+)/) {
            $sub_id = $1;
        }
        next if ($sub_limit && $sub_limit ne $sub_id);

        my $pylon = Uravo::Pylon::pylon({remote=>$uravo->{config}->{outpost_server}, command=>"get|$check_id|$range|$server_id", port=>$uravo->{config}->{outpost_pylon_port}});
        #print STDERR "get|$check_id|$range|$server_id='$pylon'\n";
        my @data = split(/\|/,$pylon);
        my $time = shift @data;
        my $size = shift @data;
        my $step = shift @data;

        foreach my $val (@data) {
            last if ($time > $now);
            if ($val =~/nan/) { 
                $data->{$time}{$sub_id} = undef;
            } else {
                $data->{$time}{$sub_id} = $val;
            }
            $time += $step;
        }
    }
    return $data; 
}

sub alert {
    my $self = shift || return;
    my $params = shift || return;

    $params->{server_id} = $self->id();
    $uravo->alert($params);
}

sub setLast {
    my $self        = shift || return;
    my $key         = shift || return;
    my $name        = shift || return;
    my $value       = shift;

    $uravo ||= new Uravo;
    if (!$value) {
        $uravo->{db}->do("DELETE FROM check_data WHERE server_id=? AND AlertGroup=? AND AlertKey=?", undef, ( $self->id(), $key, $name )) || die("Can't delete from check_data:" . $uravo->{db}->errstr);
    } else {
        my $replace     = "REPLACE INTO check_data (server_id, AlertGroup, AlertKey, value, create_date) VALUES (?, ?, ?, ?, NOW())";
        $uravo->{db}->do($replace, undef, ($self->id(), $key, $name, $value )) || die("Can't insert into check_data:" .  $uravo->{db}->errstr);
    }
}

sub getLast {
    my $self = shift || return;
    $uravo ||= new Uravo;
    $uravo->log("Uravo::Serverroles::Server::getLast()", 5);
    my $key = shift || return;
    my $name = shift || return;

    my $res = $uravo->{db}->selectrow_hashref("SELECT value FROM check_data WHERE server_id=? AND AlertGroup=? AND AlertKey=?", undef, ($self->id(), $key, $name));
    return $res->{value} if ($res);
    return;
}

sub set {
    my $self        = shift || return;
    my $field       = shift || return;
    my $value       = shift;

    return $self->update($field, $value);
}

sub update {
    $uravo->log("Uravo::Serverroles::Server::update()", 5);
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

    if ($field eq 'type_id' || $field eq 'type') {
        #if ($value ne $self->type_id()) {
            #$uravo->changelog({object_type=>$self->{object_type}, object_id=>$self->id(),field_name=>'type_id',old_value=>$self->type_id(), new_value=>$value},$changelog);
            $uravo->{db}->do("DELETE FROM server_type WHERE server_id=?", undef, ($self->id())) || die($uravo->{db}->errstr);
            if (ref($value) eq "ARRAY") {
                foreach my $t (@$value) {
                    next if (!$t || $t eq 'none');
                    $uravo->{db}->do("INSERT INTO server_type (server_id, type_id, create_date) values (?, ?, NOW())", undef, ($self->id(), $t)) || die ($uravo->{db}->errstr);
                }
                $self->{type_ids} = $value;
            } else {
                $uravo->{db}->do("INSERT INTO server_type (server_id, type_id, create_date) values (?, ?, NOW())", undef, ($self->id(), $value)) || die ($uravo->{db}->errstr);
            }
        #}
        return $changelog;
    }

    my $old_value =  $self->{$field};
    if ($old_value ne $value) {
        $uravo->changelog({object_type=>$self->{object_type}, object_id=>$self->id(),field_name=>$field,old_value=>$old_value, new_value=>$value},$changelog);
    }

    $uravo->{db}->do("UPDATE server SET $field=? WHERE server_id=?", undef, ( $value, $self->id() ));
    $self->{$field} = $value;

    $uravo->clearCache();
    return $changelog;
}


sub link {
    my $self        = shift || return;
    my $links       = shift || 'default';
    my $ret;
    my $image_base  = '/images';

    $links          = " $links ";
    $links          =~s/\s+default\s+/ info config db graphs /;

    while ($links =~/\s?-(\w+)\s?/g) {
        $links          =~s/\s-?$1\s/ /g;
    }
    foreach my $link (split(/\s+/, $links)) { 
        if ($link eq 'config') { 
            $ret    .= "<a href='/cgi-bin/editserver.cgi?server_id=${\ $self->id(); }' title='Configure ${\ $self->name(); }'><img name='${\ $self->id(); }-$link' src=$image_base/config-button.gif width=15 height=15 border=0></a>\n";
        }
        if ($link eq 'info') { 
            $ret    .= "<a href='/cgi-bin/server.cgi?server_id=${\ $self->id(); }' title='Info ${\ $self->name(); }'><img name='${\ $self->id(); }-$link' src=$image_base/info-button.gif width=15 height=15 border=0></a>\n";
        }
        if ($link eq 'graphs') {
            $ret    .= "<a href='/cgi-bin/graph.cgi?server_id=${\ $self->id(); }&graph_id=all' title='View graphs for ${\ $self->name(); }'><img src=$image_base/graph-button.gif width=15 height=15 border=0></a>\n";
        }
    }

    return $ret || $self->link();
}

sub add {
    my $params = shift || return;
    my $changelog = shift || {note=>'Uravo::Serverroles::Server::add()', user=>$0};

    $uravo ||= new Uravo;

    $uravo->log("Uravo::Serverroles::Server::add()", 5);
    my $server_id = $params->{server_id} || die "No server_id specified.\n";
    my $rack_id = $params->{rack_id} || "unknown";
    my $cluster_id = $params->{cluster_id} || "unknown";
    my $hostname = $params->{hostname} || $server_id;
    my $types = $params->{type_id} || [ "unknown" ];

    $uravo->{db}->do("delete from interface where server_id=?", undef, ($server_id)) || die($uravo->{db}->errstr);
    $uravo->{db}->do("INSERT INTO server (server_id, cluster_id, rack_id, create_date, hostname) values (?, ?, ?, NOW(), ?)", undef, ($server_id, $cluster_id, $rack_id, $hostname)) || die($uravo->{db}->errstr);
    foreach my $type_id (@$types) {
        $uravo->{db}->do("INSERT INTO server_type (server_id, type_id, create_date) values(?, ?, NOW())", undef, ($server_id, $type_id)) || die($uravo->{db}->errstr);
    }

    $uravo->changelog({object_type=>'server', object_id=>$server_id, field_name=>'New server.', new_value=>$server_id}, $changelog);

    $uravo->clearCache();
    return new Uravo::Serverroles::Server($server_id);
}

sub delete {
    my $params = shift || return;

    my $server_id = $params->{server_id} || return;
    my $changelog = $params->{changelog};

    $uravo ||= new Uravo;
    $uravo->changelog({object_type=>'server',object_id=>'global',field_name=>'Deleted server.',old_value=>$server_id},$changelog);

    $uravo->{db}->do("delete from server_type where server_id=?", undef, ($server_id));
    $uravo->{db}->do("delete from interface where server_id=?", undef, ($server_id));
    $uravo->{db}->do("delete from changelog, changelog_detail using changelog inner join changelog_detail where changelog.object_id=? and changelog.object_type='server' and changelog.id=changelog_detail.changelog_id", undef, ($server_id));
    $uravo->{db}->do("delete from changelog where object_id=? and object_type='server'", undef, ($server_id));
    $uravo->{db}->do("delete from server where server_id=?", undef, ($server_id));
    $uravo->{db}->do("DELETE FROM alert WHERE server_id=?", undef, ($server_id));
    $uravo->{db}->do("INSERT INTO deleted_server(server_id, create_date) values (?, now())", undef, ($server_id));
    $uravo->clearCache();

    return;
}


sub _sort {
    my $id_a = $a->get('id');
    my $cage_a = $a->get('cage_id');
    my $rack_a = $a->get('rack_id');
    my $id_b = $b->get('id');
    my $cage_b = $b->get('cage_id');
    my $rack_b = $b->get('rack_id');

    if ($cage_a != $cage_b) {
        return $cage_a <=> $cage_b;
    } elsif ($rack_a != $rack_b) {
        return $rack_a cmp $rack_b;
    } else {
        return $id_a cmp $id_b;
    }
}

sub mod_date {
    my $self = shift || return;

    my $db_data = $uravo->{db}->selectrow_hashref("select UNIX_TIMESTAMP(mod_date) as mod_date from server where server_id = ?", undef, ($self->id()));
    my $server_mod_date = $db_data->{mod_date};
    $db_data = $uravo->{db}->selectrow_hashref("select UNIX_TIMESTAMP(lastupd) as mod_date from serverroles where server_id = ?", undef, ($self->id()));
    my $serverroles_mod_date = $db_data->{mod_date};

    return (($serverroles_mod_date>$server_mod_date)?$serverroles_mod_date:$server_mod_date);
}

sub get {  
    my ($self, $name) = @_; 

    return $self->{$name}; 
}

sub getMonitoringValues {
    my $self = shift || return;
    
    my $monitoringValues;
    my $results;
    my $clustertype_results;
    my $server_results;

    my $server_id = $self->id();
    
    $monitoringValues = $uravo->getCache("monitoringValues:$server_id");
    return $monitoringValues if ($monitoringValues);

    my $default_sql = "select AlertGroup, AlertKey, yellow, red, disabled from monitoring_default_values";
    $results = $uravo->{db}->selectall_arrayref($default_sql, {Slice=>{}});
    foreach my $data (@$results) {
        if ($data->{AlertKey}) {
            $monitoringValues->{$data->{'AlertGroup'}}{$data->{'AlertKey'}}{'yellow'} = $data->{'yellow'};
            $monitoringValues->{$data->{'AlertGroup'}}{$data->{'AlertKey'}}{'red'} = $data->{'red'};
            $monitoringValues->{$data->{'AlertGroup'}}{$data->{'AlertKey'}}{'disabled'} = $data->{'disabled'};
        } else {
            $monitoringValues->{$data->{'AlertGroup'}}{'yellow'} = $data->{'yellow'};
            $monitoringValues->{$data->{'AlertGroup'}}{'red'} = $data->{'red'};
            $monitoringValues->{$data->{'AlertGroup'}}{'disabled'} = $data->{'disabled'};
        }
    }

    my $cluster_id = $self->cluster_id();

    my $sql = "select cluster_id, type_id, AlertGroup, AlertKey, server_id, yellow, red, disabled from monitoring_values";
    foreach my $type_id ($self->getTypes({id_only=>1})) {
        if (($cluster_id && $type_id) || $server_id) {
            $clustertype_results = $uravo->{db}->selectall_arrayref("$sql WHERE cluster_id = ? AND type_id = ? AND server_id IS NULL", {Slice=>{}}, ($cluster_id, $type_id));
            foreach my $data (@$clustertype_results) {
                if ($data->{AlertKey}) {
                    $monitoringValues->{$data->{'AlertGroup'}}{$data->{'AlertKey'}}{'yellow'} = $data->{'yellow'};
                    $monitoringValues->{$data->{'AlertGroup'}}{$data->{'AlertKey'}}{'red'} = $data->{'red'};
                    $monitoringValues->{$data->{'AlertGroup'}}{$data->{'AlertKey'}}{'disabled'} = $data->{'disabled'};
                } else {
                    $monitoringValues->{$data->{'AlertGroup'}}{'yellow'} = $data->{'yellow'};
                    $monitoringValues->{$data->{'AlertGroup'}}{'red'} = $data->{'red'};
                    $monitoringValues->{$data->{'AlertGroup'}}{'disabled'} = $data->{'disabled'};
                }
            }

        }
    }
    $server_results = $uravo->{db}->selectall_arrayref("$sql WHERE server_id = ?", {Slice=>{}}, ($server_id));
    foreach my $data (@$server_results) {
        if ($data->{AlertKey}) {
            $monitoringValues->{$data->{'AlertGroup'}}{$data->{'AlertKey'}}{'yellow'} = $data->{'yellow'};
            $monitoringValues->{$data->{'AlertGroup'}}{$data->{'AlertKey'}}{'red'} = $data->{'red'};
            $monitoringValues->{$data->{'AlertGroup'}}{$data->{'AlertKey'}}{'disabled'} = $data->{'disabled'};
        } else {
            $monitoringValues->{$data->{'AlertGroup'}}{'yellow'} = $data->{'yellow'};
            $monitoringValues->{$data->{'AlertGroup'}}{'red'} = $data->{'red'};
            $monitoringValues->{$data->{'AlertGroup'}}{'disabled'} = $data->{'disabled'};
        }
    }

    $uravo->setCache("monitoringValues:$server_id", $monitoringValues);
    return $monitoringValues;
}

sub getRack {
    my $self = shift || return;

    if ($self->{rack_id}) {
        return $uravo->getRack($self->{rack_id});
    }
}

sub getCage {
    my $self = shift || return;

    return $self->getRack()->getCage();
}

sub getServicegroups {
    my $self = shift || return;

    my $data = $uravo->{db}->selectall_hashref("SELECT DISTINCT scaler_id, servicegroup, port, disabled, weight FROM server_servicegroup WHERE server_id=? OR scaler_id=? ORDER BY scaler_id, servicegroup", undef, ($self->id(), $self->id()));

    my @servicegroups = ();
    foreach my $servicegroup (@$data) {
        push(@servicegroups, $servicegroup);
    }
    return @servicegroups;
}

sub changelog {
    my $self = shift || return;

    return $uravo->changelog({object_id=>$self->id(), object_type=>$self->type()});
}

sub data {
    my $self = shift || return;
    my $data = {};

    foreach my $field (split(/ /, $self->{server_fields})) {
        $data->{$field} = $self->{$field};
    }
    $data->{cluster_id} = $self->cluster_id();
    $data->{type_ids} = $self->{type_ids};
    $data->{diskinfo} = $self->diskinfo();
    my $silo = $self->getSilo();
    $data->{silo_id} = $silo->id();
    my $bu = $silo->getBU();
    $data->{bu_id} = $bu->id();
    return $data;
}

sub diskinfo {
    my $self = shift || return;

    return $uravo->{db}->selectall_hashref("select * from diskinfo where server_id=?", "name", undef, ( $self->id() ));
}

sub update_diskinfo {
    $uravo->log("Uravo::Serverroles::Server::update_diskinfo()", 5);
    my $self = shift || return;
    my $diskinfo = shift || return;
    my $changelog = shift || {note=>"Uravo::Serverroles::Server::update_diskinfo()", user=>$0};


    my $db_diskinfo = $self->diskinfo();
    foreach my $name (keys %$db_diskinfo) {
        my $match;
        foreach my $n (keys %$diskinfo) {
            $match = 1 if ($n eq $name);
        }
        if (!$match) {
            $uravo->changelog({object_type=>'server',object_id=>$self->id(),field_name=>'Removed disk ' . $name, old_value=>$name},$changelog);
            $uravo->{db}->do("DELETE FROM diskinfo WHERE server_id=? and name=?", undef, ($self->id(),$name));
        }
    }

    foreach my $name (keys %$diskinfo) {
        my $match;
        foreach my $n (keys %$db_diskinfo) {
            $match = 1 if ($n eq $name);
        }
        if (!$match) {
            $uravo->changelog({object_type=>'server',object_id=>$self->id(),field_name=>'Added disk ' . $name, new_value=>$name},$changelog);
            $uravo->{db}->do("INSERT INTO diskinfo (server_id, name, mounted_on, size) values (?, ?, ?, ?)", undef, ($self->id(), $name, $diskinfo->{$name}{mounted_on}, $diskinfo->{$name}{size}));
        }
    }
    $uravo->clearCache();

}

sub getNetblocks {
    my $self = shift || return;
    my $params = shift || {};

    $uravo->log("Uravo::Serverroles::Server::getNetblocks()", 5);
    my $local_params = {};

    foreach my $key (keys %$params) {
        $local_params->{$key} = $params->{$key};
    }
    $local_params->{server_id} = $self->id();

    return $uravo->getNetblocks($local_params);
}

sub getAvailableNetblocks {
    my $self = shift || return;
    my $params = shift || {};

    $uravo->log("Uravo::Serverroles::Server::getAvailableNetblocks()", 5);

    my %netblocks = ();

    # Collect netblocks already being used.
    my $local_params = {};
    foreach my $k (keys %$params) {
        $local_params->{$k} = $params->{$k};
    }
    $local_params->{id_only} = 1;
    foreach my $netblock ($self->getNetblocks($local_params)) {
        $netblocks{$netblock}++;
    }

    my %cluster_netblocks = ();
    $local_params = {};
    foreach my $k (keys %$params) {
        $local_params->{$k} = $params->{$k};
    }
    $local_params->{id_only} = 1;
    $local_params->{cluster_id} = $self->getCluster()->id();
    foreach my $netblock ($uravo->getNetblocks($local_params)) {
        $cluster_netblocks{$netblock}++;
        $netblocks{$netblock}++;
    }

    if (scalar(keys %cluster_netblocks) == 0) {
        $local_params = {};
        foreach my $k (keys %$params) {
            $local_params->{$k} = $params->{$k};
        }
        $local_params->{id_only} = 1;
        $local_params->{silo_id} = $self->getSilo()->id();
        foreach my $netblock ($uravo->getNetblocks($local_params)) {
            $netblocks{$netblock}++;
        }
    }

    if ($params->{id_only} == 1) {
        return keys %netblocks;
    } else {
        my @nb = ();
        foreach my $netblock_id (keys %netblocks) {
            push(@nb, new Uravo::Serverroles::Netblock($netblock_id));
        }
        return @nb;
    }
}

sub getModules {
    my $self = shift || return;
    my $params = shift || {};

    my $tmp_params;
    map { $tmp_params->{$_} = $params->{$_} } keys %{$params};
    $tmp_params->{server_id} = $self->id();

    return $uravo->getModules($tmp_params);
}

sub ip {
    $uravo->log("Uravo::Serverroles::Server::ip()", 5);
    my $self = shift || return;
    my $network = shift;

    if (!$network) {
        foreach my $network ($uravo->getNetworks()) {
            my $ip = $self->ip($network->{network});
            return $ip if ($ip);
        }
        return;
    }
    my $ip;
    foreach my $interface ($self->getInterfaces({network=>$network})) {
        $ip = $interface->get('ip');
        if ($interface->isMain()) {
            return $ip;
        }
    }
    return $ip;
}

sub getContactGroup {
    my $self = shift || return;

    $uravo->log("Uravo::Serverroles::Server::get_contact_group()", 5);
    my $escalation_map = $uravo->escalation_map();
    my $cluster_id = $self->cluster_id();
    my @type_ids = $self->getTypes({id_only=>1});
    my $AlertGroup = shift;

    my $contact_group;

    # Crawl the escalation map for anything that matches, from least specific (AlertGroup) to most 
    # specific (cluster).
    $contact_group = $escalation_map->{'*'}{'*'}{'*'};
    if ($escalation_map->{'*'}{'*'}{$AlertGroup}) {
        $contact_group = $escalation_map->{'*'}{'*'}{$AlertGroup};
    }

    foreach my $type_id (@type_ids) {
        if ($escalation_map->{'*'}{$type_id}{'*'}) {
            $contact_group = $escalation_map->{'*'}{$type_id}{'*'};
        }
    }

    if ($escalation_map->{$cluster_id}{'*'}{'*'}) {
        $contact_group = $escalation_map->{$cluster_id}{'*'}{'*'};
    }

    foreach my $type_id (@type_ids) {
        if ($escalation_map->{'*'}{$type_id}{$AlertGroup}) {
            $contact_group = $escalation_map->{'*'}{$type_id}{$AlertGroup};
        }
    }

    if ($escalation_map->{$cluster_id}{'*'}{$AlertGroup}) {
        $contact_group = $escalation_map->{$cluster_id}{'*'}{$AlertGroup};
    }

    foreach my $type_id (@type_ids) {
        if ($escalation_map->{$cluster_id}{$type_id}{'*'}) {
            $contact_group = $escalation_map->{$cluster_id}{$type_id}{'*'};
        }
    }

    foreach my $type_id (@type_ids) {
        if ($escalation_map->{$cluster_id}{$type_id}{$AlertGroup}) {
            $contact_group = $escalation_map->{$cluster_id}{$type_id}{$AlertGroup};
        }
    }

    return $contact_group;
}


# Misc info.
sub id          { my ($self) = @_; return $self->get('server_id'); }
sub hostname    { my ($self) = @_; return $self->get('hostname'); }
sub name        { my ($self) = @_; return $self->hostname() || $self->id(); }
sub type        { my ($self) = @_; return $self->get('object_type'); }
sub vendor      { my ($self) = @_; return $self->get('vendor') || 'blank'; }
sub service_tag { my ($self) = @_; return $self->get('service_tag'); }
sub cluster_id  { my ($self) = @_; return $self->get('cluster_id'); }

1;
