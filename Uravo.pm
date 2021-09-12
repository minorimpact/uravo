package Uravo;

use strict;

use Data::Dumper;
use DBI;
use Digest::MD5 qw(md5_hex);
use JSON;
use Uravo::Config;
use Uravo::Event;
use Uravo::Serverroles::Server;
use Uravo::Serverroles::Cluster;
use Uravo::Serverroles::Type;
use Uravo::Serverroles::BU;
use Uravo::Serverroles::Silo;
use Uravo::Serverroles::Rack;
use Uravo::Serverroles::Netblock;
use Uravo::Serverroles::Cage;
use Uravo::Serverroles::Module;
use Uravo::Util;
use Socket;

my $uravo;


#$SIG{__DIE__} = sub {
#    my $message = shift;
#    $uravo ||= new Uravo;
#    $uravo->log($message, 1);
#};

our $VERSION = "0.0.14";

sub new {
    my $class = shift || return;;
    my $params = shift;

    if ($uravo && !$params->{force}) {
        return $uravo;
    } 

    $uravo ||= bless({}, $class);
    my $default_base_dir = "/opt/uravo";
    $uravo->{config} = new Uravo::Config;
    $uravo->{log_level} = $params->{log_level} || $uravo->{config}->{log_level} || 4;
    local *LOG;
    open(LOG,">>". ( $uravo->{config}->{uravo_log} || "$default_base_dir/run/uravo.log"));
    $uravo->{LOG} = *LOG;
    #$uravo->{alert} = new Uravo::Alert;
    $uravo->{options} = {};
    $uravo->{pid} = $$;
    $uravo->log("pid=$uravo->{pid}");
    $uravo->log("Creating DB object");
    my $dsn = "DBI:mysql:database=uravo;host=$uravo->{config}->{outpost_server};port=$uravo->{config}->{outpost_db_port}";
    $uravo->{db} = DBI->connect($dsn, $uravo->{config}->{db_user}, $uravo->{config}->{db_password}, {RaiseError=>1, mysql_auto_reconnect=>1});

    $0 =~/([^\/]+)$/;
    $uravo->{script_name} = $1;
    $uravo->{script_name} =~s/ \[[^]]+\]$//;
    $uravo->{version} = $VERSION;

    foreach my $setting (@{$uravo->{db}->selectall_arrayref("SELECT * FROM settings", {Slice=>{}})}) {
        $uravo->{settings}->{$setting->{name}} = $setting->{value};
    }

    my $local_server = $uravo->getServer();
    if ($local_server) {
        $uravo->{server_id} = $local_server->id();
    }
    return $uravo;
}

sub reload {
    my $self = shift || return;
    $self->log("Uravo::reload()", 5);

    $self->{config} = new Uravo::Config;
    my $dsn = "DBI:mysql:database=uravo;host=$self->{config}->{outpost_server};port=$self->{config}->{outpost_db_port}";
    $self->{db} = DBI->connect($dsn, $self->{config}->{db_user}, $self->{config}->{db_password}, {RaiseError=>1, mysql_auto_reconnect=>1});
    delete($self->{settings});
    foreach my $setting (@{$self->{db}->selectall_arrayref("SELECT * FROM settings", {Slice=>{}})}) {
        $self->{settings}->{$setting->{name}} = $setting->{value};
    }
}


my $COLOR   = { default=> { page=>'FFFFFF',
                            menu=>'F3F3F3',
                            header=>'AACCFF',
                            subheader=>'CCEEFF',
                            row1=>'EEF7FF',
                            row2=>'FFFFFF',
                            font=>'000000'
                        } 
               };

sub deleteThreshold {
    my $self = shift || return;
    my $params = shift || return;

    my $AlertGroup = $params->{AlertGroup} || return;
    my $AlertKey = $params->{AlertKey} || "";
    my $server_id = $params->{server_id} || "";
    my $cluster_id = $params->{cluster_id} || "";
    my $type_id = $params->{type_id} || "";
    my $default = (($server_id eq "" and $cluster_id eq "" and $type_id eq "") or (defined($params->{default}) and MinorImpact::isTrue($params->{default})))?1:0;

    if ($default) {
        my $sql = "DELETE FROM monitoring_default_values WHERE AlertGroup=? and AlertKey=?";
        my @values = ($AlertGroup, $AlertKey);
        $self->{db}->do($sql, undef, @values);
    } else {
        my $sql = "DELETE FROM monitoring_values WHERE AlertGroup=? and AlertKey=? AND cluster_id=? AND type_id=? AND server_id=?";
        my @values = ($AlertGroup, $AlertKey, $cluster_id, $type_id, $server_id);
        $self->{db}->do($sql, undef, @values);
    }
}

sub updateThreshold {
    my $self = shift || return;
    my $params = shift || return;

    my $AlertGroup = $params->{AlertGroup} || return;
    my $AlertKey = $params->{AlertKey} || "";
    my $red = $params->{red} || return;
    my $yellow = $params->{yellow};
    my $disabled = MinorImpact::isTrue($params->{disbled}) ? 1 : 0;
    my $server_id = $params->{server_id} || "";
    my $cluster_id = $params->{cluster_id} || "";
    my $type_id = $params->{type_id} || "";
    my $default = (($server_id eq "" and $cluster_id eq "" and $type_id eq ""))?1:0;

    if ($default) {
        my $sql = "INSERT INTO monitoring_default_values (AlertGroup, AlertKey, red, yellow, disabled, create_date) VALUES (?, ?, ?, ?, ?, NOW()) ON DUPLICATE KEY UPDATE red=?, yellow=?, disabled=?, mod_date=NOW()";
        my @values = ($AlertGroup, $AlertKey, $red, $yellow, $disabled, $red, $yellow, $disabled);
        $self->{db}->do($sql, undef, @values);
    } else {
        my $sql = "INSERT INTO monitoring_values (AlertGroup, AlertKey, cluster_id, type_id, server_id, red, yellow, disabled, create_date) VALUES (?, ?, ?, ?, ?, ?, ?, ?, NOW()) ON DUPLICATE KEY UPDATE red=?, yellow=?, disabled=?, mod_date=NOW()";
        my @values = ($AlertGroup, $AlertKey, $cluster_id, $type_id, $server_id, $red, $yellow, $disabled, $red, $yellow, $disabled);
        $self->{db}->do($sql, undef, @values);
    }
}

sub getCages {
    my $self = shift || return;
    my $params = shift;

    my @list	    = ();
    foreach my $cage_id (Uravo::Serverroles::Cage::_list($params)) {
        if ($params->{'id_only'}) { push @list, $cage_id; }
        else { push @list, $self->getCage($cage_id); }
    }
    if ($params->{'pre_sort'} && $params->{'id_only'}) {
        return sort @list;
    } elsif ($params->{pre_sort}) {
        return sort { $a->id() cmp $b->id(); } @list;
    }
    return @list;
}

sub getCage {
    my $self = shift || return;
    my $cage_id = shift || return;
    my $params = shift;

    $self->log("Uravo::getCage()", 5);
    return new Uravo::Serverroles::Cage($cage_id, $params);
}

sub getEvent {
    my $self = shift || return;
    my $id = shift || return;

    $self->log("Uravo::getEvent()", 5);
    return new Uravo::Event($id);
}

sub getEvents {
    my $self = shift || return;
    my $params = shift || {};

    $self->log("Uravo::getEvents()", 5);
    return Uravo::Event::list($params);
}

sub getNetblocks {
    my $self	    = shift || return;
    my $params	    = shift;
    $self->log("Uravo::getNetblocks()", 5);

    # Not sure if this is the right idea here.  How often do we really grab all netblocks and do something random
    # with them?
    #if (!defined($params->{silo_id}) && !defined($params->{silo}) && $params->{all_silos} != 1) {
    #    # Figure out who I am, then I can use my info to limit my queries to my own silo.
    #    my $server      = $self->getServer();
    #    $params->{silo_id} = $server->get('silo_id');
    #}

    my @list	    = ();
    foreach my $netblock_id (Uravo::Serverroles::Netblock::_list($params)) {
        if ($params->{'id_only'}) { push @list, $netblock_id; }
        else { push @list, $self->getNetblock($netblock_id); }
    }
    if ($params->{'pre_sort'} && $params->{'id_only'}) {
        return sort @list;
    } elsif ($params->{pre_sort}) {
        return sort { $a->id() cmp $b->id(); } @list;
    }
    return @list;
}

sub getNetblock {
    my $self = shift || return;
    $self->log("Uravo::getNetblock()", 5);
    my $netblock_id = shift || return;
    my $params = shift;

    return new Uravo::Serverroles::Netblock($netblock_id, $params);
}

sub getRacks {
    my $self	    = shift || return;
    my $params	    = shift;

    my @list	    = ();
    foreach my $rack_id (Uravo::Serverroles::Rack::_list($params)) {
        if ($params->{'id_only'}) { push @list, $rack_id; }
        else { push @list, $self->getRack($rack_id); }
    }
    if ($params->{'pre_sort'} && $params->{'id_only'}) {
        return sort @list;
    } elsif ($params->{pre_sort}) {
        return sort { $a->id() cmp $b->id(); } @list;
    }
    return @list;
}

sub getRack {
    my $self = shift || return;
    my $rack_id = shift || return;
    my $params = shift;

    $self->log("Uravo::getRack()",5);
    return new Uravo::Serverroles::Rack($rack_id, $params);
}

sub getServers {
    my $self	    = shift || die;
    my $params	    = shift || {};
    $params = Uravo::Util::clean_params($params);

    $self->log("Uravo::getServers()",5);
    if (!defined($params->{silo_id}) && $params->{all_silos} != 1) {
        # Figure out who I am, then I can use my info to limit my queries to my own silo.
        my $server      = $self->getServer();
        $params->{silo_id} = $server->get('silo_id');
    }

    my @list	    = ();
    foreach my $server_id (Uravo::Serverroles::Server::_list($params)) {
        if ($params->{id_only}) { push @list, $server_id; }
        else { push @list, $self->getServer($server_id); }
    }
    if ($params->{pre_sort} && $params->{id_only}) {
        return sort @list;
    } elsif ($params->{pre_sort}) {
        return sort { $a->id() cmp $b->id(); } @list;
    }
    return @list;
}

sub getServer {
    my $self	    = shift || return;
    my $server_id   = shift || `hostname -s`;

    $self->log("Uravo::getServer()",5);
    chomp($server_id);
    return new Uravo::Serverroles::Server($server_id);
}

sub getModules {
    my $self	    = shift || return;
    my $params	    = shift || {};

    $self->log("Uravo::getModules(" . join(",", map {"$_=$params->{$_}"} keys %$params) . ")",9);
    my @list	    = ();
    foreach my $module_id (Uravo::Serverroles::Module::_list($params)) {
        if ($params->{id_only}) { push @list, $module_id; }
        else { push @list, $self->getModule($module_id); }
    }
    if ($params->{pre_sort} && $params->{id_only}) {
        return sort @list;
    } elsif ($params->{pre_sort}) {
        return sort { $a->id() cmp $b->id(); } @list;
    }
    return @list;
}

sub getModule {
    my $self = shift || return;
    my $module_id = shift || return;

    return new Uravo::Serverroles::Module($module_id);
}

sub getClusters {
    my $self	    = shift || return;
    my $params	    = shift;

    $self->log("Uravo::getClusters()",5);
    my @list	    = ();
    foreach my $cluster_id (Uravo::Serverroles::Cluster::_list($params)) {
        if ($params->{id_only}) { push @list, $cluster_id; }
        else { push @list, $self->getCluster($cluster_id); }
    }
    if ($params->{pre_sort} && $params->{id_only}) {
        return sort @list;
    } elsif ($params->{pre_sort}) {
        return sort { $a->id() cmp $b->id(); } @list;
    }
    return @list;
}

sub getCluster {
    my $self	    = shift || return;
    my $cluster_id     = shift || return;

    return new Uravo::Serverroles::Cluster($cluster_id);
}

sub getTypes {
    my $self	    = shift || return;
    my $params	    = shift;

    $self->log("Uravo::getTypes()",5);
    my @list	    = ();
    foreach my $type_id (Uravo::Serverroles::Type::_list($params)) {
        if ($params->{id_only}) { push @list, $type_id; }
        else { push @list, $self->getType($type_id); }
    }
    if ($params->{pre_sort} && $params->{id_only}) {
        return sort @list;
    } elsif ($params->{pre_sort}) {
        return sort { $a->id() cmp $b->id(); } @list;
    }
    return @list;
}

sub getType {
    my $self	    = shift || return;
    my $type_id     = shift || return;

    $self->log("Uravo::getType()",5);
    return new Uravo::Serverroles::Type($type_id);
}

sub getBUs {
    my $self	    = shift || return;
    my $params	    = shift;

    my @list	    = ();
    foreach my $bu_id (Uravo::Serverroles::BU::_list($params)) {
        if ($params->{id_only}) { push @list, $bu_id; }
        else { push @list, $self->getBU($bu_id); }
    }
    if ($params->{pre_sort} && $params->{id_only}) {
        return sort @list;
    } elsif ($params->{pre_sort}) {
        return sort { $a->id() cmp $b->id(); } @list;
    }
    return @list;
}

sub getBU {
    my $self	  = shift || return;
    my $bu_id     = shift || return;

    return new Uravo::Serverroles::BU($bu_id);
}

sub getSilos {
    my $self	    = shift || return;
    my $params	    = shift;

    my @list	    = ();
    foreach my $silo_id (Uravo::Serverroles::Silo::_list($params)) {
        if ($params->{id_only}) { push @list, $silo_id; }
        else { push @list, $self->getSilo($silo_id); }
    }
    if ($params->{pre_sort} && $params->{id_only}) {
        return sort @list;
    } elsif ($params->{pre_sort}) {
        return sort { $a->id() cmp $b->id(); } @list;
    }
    return @list;
}

sub getSilo {
    my $self	  = shift || return;
    my $silo_id     = shift || return;

    return new Uravo::Serverroles::Silo($silo_id);
}

sub getObject {
    my $self    = shift || return;
    my $item    = shift || return;

    my ($type, $id) = split(/,/, $item);
    if ($type eq 'server') { return $self->getServer($id); }
    if ($type eq 'cluster') { return $self->getCluster($id); }
    if ($type eq 'type') { return $self->getType($id); }
    if ($type eq 'bu') { return $self->getBU($id); }
    if ($type eq 'silo') { return $self->getSilo($id); }
    return;
}

sub color {
    my $self    = shift || return;
    my $cat     = shift || 'page';
    my $style   = shift || 'default';

    return "#" . ($COLOR->{$style}->{$cat} || $COLOR->{'default'}->{$cat} || 'FFFFFF');
}

sub link {
    my $self        = shift || return;
    my $links       = shift || 'sr graphs alerts history config info help';
    my $ret;
    my $image_base  = '/images';

    foreach my $link (split(/\s+/, $links)) {
        if ($link eq 'sr') {    
            $ret    .= "<a href='/cgi-bin/index.cgi' title='Serverroles'><img src=$image_base/sr-button.gif width=15 height=15 border=0></a>";
        }
        if ($link eq 'alerts') {    
            $ret    .= "<a href='/cgi-bin/alerts.cgi' title='Alerts'><img src=$image_base/bb-button.gif width=15 height=15 border=0></a>";
        }
        if ($link eq 'graphs') {    
            $ret    .= "<a href='/cgi-bin/graph_picker.cgi' title='Graphs'><img src=$image_base/graph-button.gif width=15 height=15 border=0></a>";
        }
        if ($link eq 'history') {
            $ret    .= "<a href='/cgi-bin/historical_report.cgi' title='Historical Report'><img src=$image_base/history-button.gif width=15 height=15 border=0></a>";
        }
        if ($link eq 'config') {
            $ret    .= "<a href='/cgi-bin/config.cgi' title='Config'><img src=$image_base/config-button.gif width=15 height=15 border=0></a>";
        }
        if ($link eq 'info') {
            $ret    .= "<a href='/cgi-bin/info.cgi' title='Server Info'><img src=$image_base/info-button.gif width=15 height=15 border=0></a>";
        }
        if ($link eq 'help') {
            $ret    .= "<a href='/docs/' title='Documentation' target=_new><img src=$image_base/help-button.png width=15 height=15 border=0></a>";
        }
    }   
    return $ret || $self->link('sr');
}       

sub menu {   
    my $self    = shift || return;

    $self->log("Uravo::menu()", 5);
    my $jump_menu = "View <select onChange='if (this.value) { self.document.location=this.value; }'><option>--Jump To--</option><option value='index.cgi'>Servers</option><option value='bus.cgi'>Business Units</option><option value='silos.cgi'>Silos</option><option value='clusters.cgi'>Clusters</option><option value='types.cgi'>Types</option><option value='racks.cgi?cage_id=all'>Racks</option><option value='netblocks.cgi'>Netblocks</option><option value='cages.cgi'>Cages</option><option value='aliases.cgi'>DNS Aliases</option></select>";
    my $ret     = qq(<table cellspacing=0 width=100%><tr bgcolor='${\ $self->color('menu');}'><td align=left valign=middle>${\ $self->link();}</td><td align=right valign=middle>$jump_menu</td></tr></table>);
    return $ret;
}   

sub changelog {
    my $self = shift || return;
    my $params = shift || return;
    my $changelog = shift || {user=>'unknown'};

    my $object_type = $params->{object_type} || return;
    my $object_id = $params->{object_id} || return;

    $changelog->{user} ||= 'unknown';

    if ($params->{field_name} && ($params->{old_value} || $params->{new_value})) {
        if (!$changelog->{changelog_id}) {
            $self->{db}->do("INSERT INTO changelog (object_type, object_id, user, ticket, note) values (?,?,?,?,?)", undef, ($object_type, $object_id, $changelog->{user}, $changelog->{ticket}, $changelog->{note})) || die("Can't insert into changelog:" , $uravo->{db}->errstr);
            #$changelog->{changelog_id} = $self->{db}->{insert_id};
            #$changelog->{changelog_id} = $self->{db}->last_insert_id();
            $changelog->{changelog_id} = $self->{db}->{mysql_insertid};
        }
        $self->{db}->do("insert into changelog_detail (changelog_id, field_name, old_value, new_value) values (?,?,?,?)", undef, ($changelog->{changelog_id}, $params->{field_name}, $params->{old_value}, $params->{new_value})) || die("Can't insert into changelog_detail:" , $uravo->{db}->errstr);
        return $changelog;
    }

    my $data = $uravo->{db}->selectall_arrayref("SELECT cl.id, cl.user, cl.ticket, cl.note, cl.create_date FROM changelog cl WHERE cl.object_id=? AND cl.object_type=? ORDER BY cl.create_date desc", {Slice=>{}}, ($object_id, $object_type));
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

sub log {
    my $self = shift || return;
    my $message = shift || return;
    my $level = shift || 5;

    if ($level <= $self->{log_level}) {
        foreach my $line (split(/\n/, $message)) {
            next unless ($line);
            $line = localtime(time()) . " " . $0 . " $line";
            print {$self->{LOG}} "$line\n";
        }
    }
}

sub getProcesses {
    my $self = shift || return;

    return $self->{db}->selectall_hashref("SELECT * FROM process", "process_id", {Slice=>{}}) || die($self->{db}->errstr);
}

sub getNetworks {
    my $self = shift || return;
    my $params = shift || {};
    $self->log("Uravo::getNetworks",5);

    my $where = "WHERE network IS NOT NULL";
    if ($params->{default_interface_name}) {
        $where .= " AND default_interface_name='" . $params->{default_interface_name} . "'";
    }

    return @{$self->{db}->selectall_arrayref("SELECT * FROM network $where ORDER BY `network_order`", {Slice=>{}})};
}

sub update_settings {
    my $self = shift || return;
    $self->log("Uravo::update_settings()", 5);

    my $settings = shift || return;
    foreach my $name (keys %$settings) {
        my $value = $settings->{$name};
        $value = 1 if ($value eq 'on');
        $value = 0 if ($value eq 'off');
        $self->log("$name=$value");
        $self->{db}->do("UPDATE settings SET value=? WHERE name=?", undef, ($value, $name)) || die($self->{db}->errstr);
        $self->{settings}->{$name} = $value;
    }
}

sub escalation_map {
    my $self = shift || return;
    $self->log("Uravo::escalation_map()", 5);
    my $escalation_map = ();
    my $default_contact_group = 'NONE';
    my $res = $uravo->{db}->selectrow_hashref("SELECT contact_group FROM contacts WHERE default_group=1");
    if ($res && defined($res->{contact_group})) {
        $default_contact_group = $res->{contact_group};
    }
    my $escalations = $uravo->{db}->selectall_arrayref("SELECT * FROM escalations", {Slice=>{}});
    foreach my $data (@$escalations) {
        my $cluster_id = $data->{'cluster_id'} || '*';
        my $type_id = $data->{'type_id'} || '*';
        my $check_id = $data->{'AlertGroup'} || '*';
        $escalation_map->{$cluster_id}{$type_id}{$check_id} = $data->{'contact_group'};
    }
    $escalation_map->{'*'}{'*'}{'*'} = $default_contact_group;

    return $escalation_map;
}

sub getCache {
    my $self = shift || return;
    my $key = shift || return;
    my $json;

    $self->log("Uravo::getCache()", 5);
    $key = md5_hex($key);

    local $SIG{ALRM} = sub { die "timeout"; };
    eval {
        alarm(2);

        my $iaddr   = inet_aton($self->{config}->{outpost_server})               || die "no host: $self->{config}->{outpost_server}";
        my $paddr   = sockaddr_in($self->{config}->{cache_server_port} || 14546, $iaddr);

        my $proto   = getprotobyname('tcp');
        socket(SOCK, PF_INET, SOCK_STREAM, $proto)  || die "socket: $!";
        connect(SOCK, $paddr)    || die "connect: $!";

        my $oldh = select(SOCK);
        $| = 1;
        select($oldh);
        print SOCK "get|$key\n";
        $json = <SOCK>;
        close(SOCK);
        alarm(0);
    };
    print STDERR "$@\n" if ($@);
    chop($json);
    chop($json);

    $json =~s/__CR__/\n/g;
    $json =~s/__PIPE__/\|/g;

    return if ($json eq '');
    my $holder = decode_json($json);

    return $holder->{value};
}

sub setCache {
    my $self = shift || return;
    my $key = shift || return;
    my $value = shift;

    $self->log("Uravo::setCache()", 5);

    return if ($value eq '');
    $key = md5_hex($key);

    my $holder = { value=>$value };
    my $json = encode_json($holder);

    $json =~s/\n/__CR__/g;
    $json =~s/\|/__PIPE__/g;

    local $SIG{ALRM} = sub { die "timeout"; };
    eval {
        alarm(2);

        my $iaddr   = inet_aton($self->{config}->{outpost_server})               || die "no host: $self->{config}->{outpost_server}";
        my $paddr   = sockaddr_in($self->{config}->{cache_server_port} || 14546, $iaddr);

        my $proto   = getprotobyname('tcp');
        socket(SOCK, PF_INET, SOCK_STREAM, $proto)  || die "socket: $!";
        connect(SOCK, $paddr)    || die "connect: $!";

        my $oldh = select(SOCK);
        $| = 1;
        select($oldh);
        print SOCK "set|$key|$json\n";
        close(SOCK);
        alarm(0);
    };
    print STDERR "$@\n" if ($@);
}

sub clearCache {
    my $self = shift || return;
    my $key = shift;

    $self->log("Uravo::setCache()", 5);

    local $SIG{ALRM} = sub { die "timeout"; };
    eval {
        alarm(2);

        my $iaddr   = inet_aton($self->{config}->{outpost_server})               || die "no host: $self->{config}->{outpost_server}";
        my $paddr   = sockaddr_in($self->{config}->{cache_server_port} || 14546, $iaddr);

        my $proto   = getprotobyname('tcp');
        socket(SOCK, PF_INET, SOCK_STREAM, $proto)  || die "socket: $!";
        connect(SOCK, $paddr)    || die "connect: $!";

        my $oldh = select(SOCK);
        $| = 1;
        select($oldh);
        # TODO: Make this support clearning wildcards, like "Type::_list:*"
        if (defined($key) and $key ne "") {
            print SOCK "clear|$key\n";
        } 
        else {
            print SOCK "clear\n";
        }
        close(SOCK);
        alarm(0);
    };
    print STDERR "$@\n" if ($@);
}

sub alert {
    my $self = shift || return;
    my $data = shift || return;

    $self->log("Uravo::alert()", 5);

    return new Uravo::Event($data);
}

sub DESTROY {
    my $self = shift || return;
    $self->log("Uravo::DESTROY()", 5);
    if (defined($self->{db})) {
        $self->{db}->close();
    }
}

1;
