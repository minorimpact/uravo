#!/usr/bin/perl

use strict;

use Config;
use Data::Dumper;
use Getopt::Long;
use Net::CIDR;

use Uravo;
use Uravo::Cron;
use Uravo::Util;

my $verbose;
my $force;
my $firstboot;

GetOptions( "help", sub { usage(); },
            "verbose", \$verbose,
            "firstboot", \$firstboot,
            "force", \$force
            ) || usage();



my $uravo = new Uravo;
if (! $force && Uravo::Util::CheckForDuplicates(1,0,0,290, $uravo->{config}{run_dir})) {
    print "Already running one of these\n" if ($verbose);
    exit;
}


my $sleep = ($firstboot || $force || $verbose)?0:5;
Uravo::Cron::execCron(\&main, { sleep=>$sleep, no_log=>$verbose});
exit;

sub main {
    my $changelog = {user=>$0, note=>'Automated updates.'};

    my %server_data = collect_server_data();
    $server_data{'server_model'} =~s/ -\[[0-9A-Z]+\]-//;

    my $diskinfo = $server_data{diskinfo};
    delete($server_data{diskinfo});
    my $ifconfig = $server_data{ifconfig};
    delete($server_data{ifconfig});

    foreach my $int (keys %$ifconfig) {
        my $ip = $ifconfig->{$int}{ip};
        my $mask = $ifconfig->{$int}{mask};
        next unless ($ip && $mask);
        my $address = Net::CIDR::addrandmask2cidr("$ip","$mask");
        #print "CIDR ($ip/$mask): " . join(",",  Net::CIDR::addr2cidr("$ip/$mask")) . "\n";
        my @netblocks = $uravo->getNetblocks({address=>$address, id_only=>1});
        unless (scalar(@netblocks)) {
            my $netblock_id = $address;
            $netblock_id =~s/[\.\/]/_/g;
            print "Adding new netblock $netblock_id for $address\n" if ($verbose);
            my $netblock = Uravo::Serverroles::Netblock::add({netblock_id=>$netblock_id});
            my $network = ($uravo->getNetworks({default_interface_name=>$int}))[0];
            $netblock->update({address=>$address, silo_id=>'unknown', network=>$network->{network}});
        }
    }

    my @types = getLocalTypes();
    my $server = $uravo->getServer();
    if (!$server) {
        my $hostname = `/bin/hostname`;
        chomp($hostname);
        my $server_id = `/bin/hostname -s`;
        chomp($server_id);

        print "No existing server object for $server_id. Will try to create one.\n" if ($verbose);

        if ($ifconfig) {
            my $ip;
            my $netblock;
            foreach my $name (keys %$ifconfig) {
                next if ($ip && $netblock);
                $ip =  $ifconfig->{$name}{ip};
                if ($ip) {
                    print "looking for a netblock for $ip\n" if ($verbose);
                    $netblock = Uravo::Serverroles::Netblock->getNetblockFromIp($ip);
                }
            }
            if ($netblock) {
                print "found netblock ". $netblock->id() . "\n" if ($verbose);
                my $silo = $netblock->getSilo();
                if ($silo) {
                    print "found silo " . $silo->id() . "\n" if ($verbose);
                    my $cluster = $silo->getDefaultCluster();
                    if ($cluster) {
                        print "found cluster " . $cluster->id() . "\n" if ($verbose);

                        @types = ('unknown') unless (scalar(@types));
                        print "matched the following type(s): " . join(',', @types) . "\n" if ($verbose);
                        $server = Uravo::Serverroles::Server::add({server_id=>$server_id, hostname=>$hostname, cluster_id=>$cluster->id(), type_id=>\@types}, $changelog) || die ("Can't create new server object.");
                    } else {
                        print "could not find a cluster for $server_id\n" if ($verbose);
                    }
                } else {
                    print "could not find a silo for $server_id\n" if ($verbose);
                }
            } else {
                print "could not find a netblock for $server_id\n" if ($verbose);
            }
        }
    } else {
        my @server_types = $server->getTypes({id_only=>1});
        my %types = map {$_ => 1; } (@server_types, @types);
        @types = keys %types;
    }

    die("Can't retrieve server object.") unless ($server);

    print "  types:\n" if ($verbose);
    foreach my $type (@types) {
        print "    $type\n" if ($verbose);
    }
    $server_data{'type_id'} = \@types;
    $server_data{'uravo_version'} = $uravo->{version};
    $server->update(\%server_data,$changelog);

    if ($ifconfig) {
        print "  analyzing nterfaces...\n" if ($verbose);
        my @interfaces = $server->getInterfaces();
        # Process each interface collected from the server.
        foreach my $name (keys %$ifconfig) {
            my $interface;

            # Try to match the interface to one in serverroles.
            foreach my $i ( @interfaces) {
                if ( $name eq 'mgmt') {
                    if ($i->get('ip') eq $ifconfig->{$name}{'ip'}) {
                        $interface = $i;
                        last;
                    }
                } else {
                    # If any two peices of info match (ip, mac or name), then we'll assume this is the same interface.
                    if ($i->get('mac') eq $ifconfig->{$name}{'mac'} && $i->get('ip') eq $ifconfig->{$name}{'ip'} && $i->get('name') eq $ifconfig->{$name}{'name'}) {
                        $interface = $i;
                        last;
                    } elsif ($i->get('mac') eq $ifconfig->{$name}{'mac'} && $i->get('ip') eq $ifconfig->{$name}{'ip'}) {
                        $interface = $i;
                        last;
                    } elsif ($i->get('mac') eq $ifconfig->{$name}{'mac'} && $i->get('name') eq $ifconfig->{$name}{'name'}) {
                        $interface = $i;
                        last;
                    } elsif ($i->get('ip') eq $ifconfig->{$name}{'ip'} && $i->get('name') eq $ifconfig->{$name}{'name'}) {
                        $interface = $i;
                        last;
                    }
                }
            }
            my $network;
            if ($name =~/^eth0/) {
                $network = 'frontnet';
            } elsif ($name =~/^eth1/ || $name =~/^bond/) {
                $network = 'backnet';
            } elsif ($name eq 'mgmt') {
                $network = 'mgmt';
            }
            if ($network) {
                if ($interface) {
                    print "    interface ${\ $interface->id(); }:$name, " . $ifconfig->{$name}{'ip'} . ", " . $ifconfig->{$name}{'mac'} . "\n" if ($verbose);
                    $interface->update({'ip'=>$ifconfig->{$name}{'ip'}, 'name'=> $ifconfig->{$name}{'name'}, 'mac'=> $ifconfig->{$name}{'mac'}}, $changelog);
                } else {
                    print "    new $network interface: $name, " . $ifconfig->{$name}{'ip'} . ", " . $ifconfig->{$name}{'mac'} . "\n" if ($verbose);
                    $server->addInterface({ip=>$ifconfig->{$name}{'ip'}, network=>$network, mac=>$ifconfig->{$name}{'mac'},name=>$ifconfig->{$name}{'name'},changelog=>$changelog});
                }
            }
        }
    }

    if ($diskinfo) {
        print "  disk info...\n" if ($verbose);
        $server->update_diskinfo($diskinfo, $changelog);
    }
    
    # Add specific code here for any tasks that need to be called during firstboot.
    if ($firstboot) {
    }
    return;
}

sub collect_server_data {
    my %server_data = ();
    print "collecting data...\n" if ($verbose);
    if (-f "/etc/redhat-release") {
        print "  OS information...\n" if ($verbose);
        my $release = `/usr/bin/head -n 1 /etc/redhat-release`;
        chomp($release);
        if ($release =~/^(.*) release ([0-9.]+) /) {
            $server_data{'os_vendor'} = $1;
            print "    os_vendor: $1\n" if ($verbose);
            $server_data{'os_version'} = $2;
            print "    os_version: $2\n" if ($verbose);
        }
    }

    print "  ip addresses...\n" if ($verbose);
    my $IFCONFIG = "/sbin/ifconfig";
    my %if = ();
    my $i = '';
    open(FILE, "$IFCONFIG |") or die "can't open $@\n";
    while(my $line = <FILE>){
        chomp($line);
        if ($line =~ /^lo:?\s/) {
            $i = '';
            next;
        }
#eth0: flags=4163<UP,BROADCAST,RUNNING,MULTICAST>  mtu 1500
#        inet 165.227.30.221  netmask 255.255.240.0  broadcast 165.227.31.255
        if ($line =~ /^((eth|bond|br)\d(\.\d)?:?\d*)\s/) {
            $i = $1;
            $i =~s/:$//;
        }
        next unless ($i ne "");
        $if{$i}->{name} = $i;
        $if{$i}->{ip} = $2 if ($line =~ /inet (addr:|)(\S+)/);
        $if{$i}->{mac} = $2 if ($line =~ /(HWaddr|ether) (\S+)/);
        $if{$i}->{mask} = $2 if ($line =~ /(Mask:|netmask )(\S+)/);
    }
    close FILE;

    # Bonded nics create an interface called "bond0" which takes the attributes of the active interface 
    # (usually eth0).  eth0 and eth1 are listed with no ip, and they both have the mac of the active interface.
    # To get the actual mac addresses of the slave interfaces, we need to read the info from /proc/net/bonding/bond0
    # instead.
    if (exists($if{'bond0'})) {
        delete($if{'eth0'});
        delete($if{'eth1'});
        if (-f "/proc/net/bonding/bond0") {
            my $bond0 = `cat /proc/net/bonding/bond0`;
            my $current_interface;
            foreach my $line (split(/\n/, $bond0)) {
                if ($line =~/^Slave Interface: (\w+)$/) {
                    $current_interface = $1;
                    $if{$current_interface}->{name} = $current_interface;
                    $if{$current_interface}->{main} = 0;
                }
                if ($current_interface && $line =~/^Permanent HW addr: ([0-9a-f:]+)$/) {
                    $if{$current_interface}->{mac} = uc($1);
                }
            }
        }
    }
    $server_data{'ifconfig'} = \%if;

    if (-x "/usr/sbin/racadm" && 0) {
        print "  mgmt nic info...\n" if ($verbose);
        my $mgmtmac = `/usr/sbin/racadm getconfig -g cfgLanNetworking -o cfgNicMacAddress`;
        chomp($mgmtmac);
        $mgmtmac = uc($mgmtmac);
        my $mgmtip = `/usr/sbin/racadm getconfig -g cfgLanNetworking -o cfgNicIpAddress`;
        chomp($mgmtip);
        if ($mgmtmac =~/^(\w\w:?){6}$/ && $mgmtip =~/^([0-9]+\.?){4}$/) {
            $server_data{'ifconfig'}->{'mgmt'}->{name} = 'mgmt';
            $server_data{'ifconfig'}->{'mgmt'}->{ip} = $mgmtip;
            $server_data{'ifconfig'}->{'mgmt'}->{mac} = $mgmtmac;
        }
    }

    print "  perl...\n" if ($verbose);
    $server_data{'perl_version'} = $Config{'version'};
    print "    perl_version:" . $Config{'version'} . "\n" if ($verbose);
    $server_data{'perl_arch'}    = $Config{'archname'};
    print "    perl_arch:" . $Config{'archname'} . "\n" if ($verbose);

    if (-x "/bin/uname") {
        print "  kernel version...\n" if ($verbose);
        my $uname = `/bin/uname -a`;
        if ($uname =~/\S+ \S+ (\S+)/) {
            $server_data{'os_kernel'} = $1;
            print "    os_kernel:$1\n" if ($verbose);
        }
    }

    if (-f "/proc/meminfo") {
        print "  memory...\n" if ($verbose);
        my $meminfo = `cat /proc/meminfo`;
        if ($meminfo =~ /MemTotal:\s+([0-9]+) kB/m) {
            $server_data{'mem'} = $1;
            print "    mem:$1\n" if ($verbose);
        }
    }

    if (-f "/proc/cpuinfo") {
        print "  CPU info...\n" if ($verbose);
        my $cpuinfo = `cat /proc/cpuinfo`;
        $server_data{'cpu_name'} = $1 if ($cpuinfo =~/model name\s+:\s+(.*)/);
        $server_data{'cpu_name'} =~s/ +/ /g;
        print "    cpu_name:" . $server_data{'cpu_name'} . "\n" if ($verbose);
        if ($cpuinfo =~/cpu cores\s+:\s+(.*)/) {
            $server_data{'cpu_cores'} = $1;
            print "    cpu_cores:$1\n" if ($verbose);
        } else {
            $server_data{'cpu_cores'} = 1;
            print "    cpu_cores:1\n" if ($verbose);
        }
        if ($cpuinfo =~/cpu MHz\s+: (.*)/) {
            $server_data{'cpu_mhz'} = sprintf("%.2f",$1);
            $server_data{'cpu_mhz'} +=0;
            print "    cpu_mhz:" . $server_data{'cpu_mhz'} . "\n" if ($verbose);
        }
        if ( $cpuinfo =~/bogomips\s+: (.*)/) {
            $server_data{'cpu_bogomips'} = $1;
            $server_data{'cpu_bogomips'} += 0;
            print "    cpu_bogomips:$server_data{'cpu_bogomips'}\n" if ($verbose);
        }
        if ($cpuinfo =~/cache size\s: ([0-9]+)/) {
            $server_data{'cpu_cache_kb'} = $1;
            print "    cpu_cache_kb:$1\n" if ($verbose);
        }

        my $cpu_count = 0;
        my %cpu_cores = ();
        foreach my $line (split(/\n/, $cpuinfo)) {
            if ($line =~ /processor/) {
                $cpu_count++;
            }
            if ($line =~ /physical id\s+:\s+(.*)/) {
                $cpu_cores{$1}++;
            }
        }
        $server_data{'cpu_count'} = $cpu_count;
        print "    cpu_count:$cpu_count\n" if ($verbose);
        $server_data{'cpu_physical_count'} = scalar(keys(%cpu_cores));
        print "    cpu_physical_count:" . $server_data{'cpu_physical_count'} . "\n" if ($verbose);
    }

    if ( -x "/bin/df") {
        print "  disk info...\n" if ($verbose);
        my $df = `/bin/df`;
        my @fields = ();
        my $loop = '';
        foreach my $line (split(/\n/, $df)) {
            @fields = split(/ +/, $line);
            if ($loop && scalar(@fields) == 6) {
                $fields[0] = $loop;
                $loop = '';
            } elsif (scalar(@fields) == 1) {
                $loop = $fields[0];
                next;
            }
            next unless ($fields[0] =~/^\/dev\//);
            my $name = $fields[0];
            my $mounted_on = $fields[5];

            my $pvdisplay;
            if (-x "/usr/sbin/pvdisplay") {
                $pvdisplay = "/usr/sbin/pvdisplay";
            } elsif ( -x "/sbin/pvdisplay") {
                $pvdisplay = "/sbin/pvdisplay";
            }

            if ($name =~/\/mapper\/([^\-]+)-/ && $pvdisplay) {
                my $vg = $1;
                my @pvdisplay = split(/\n/, `$pvdisplay -c | grep ':$vg:'`);
                foreach my $pv (@pvdisplay) {
                    my @p = split(/:/, $pv);
                    my $name = $p[0];
                    $name =~s/^ *//;

                    my $size = int((($p[7] * $p[8])/ (1024*1024)) + .5);
                    $server_data{diskinfo}{$name}{size} = $size;
                    $server_data{diskinfo}{$name}{mounted_on} = $mounted_on;
                    printf("    %-25s %4d\GB %s\n", $name, $size, $mounted_on) if ($verbose);
                }
            } else {
                my $size = int(($fields[1] / (1024*1024)) + .5);
                $server_data{diskinfo}{$name}{size} = $size;
                $server_data{diskinfo}{$name}{mounted_on} = $mounted_on;
                printf("    %-25s %4d\GB %s\n", $name, $size, $mounted_on) if ($verbose);
            }
        }
    }

    if (-x "/usr/bin/omreport") {
        print "  OpenManage information...\n" if ($verbose);
        #BMC Version                              : 1.23
        #Primary BP Version                       : 1.00
        #Chassis Model                            : PowerEdge 1850
        #Chassis Service Tag                      : 79KL171
        #Chassis Asset Tag                        : 
        my $chassis_info = `/usr/bin/omreport chassis info`;
        if ($chassis_info =~/Server Module Service Tag/) {
            if ($chassis_info =~/Server Module Service Tag\s+:\s?(.*)/m) {
                $server_data{'service_tag'} = $1;
                print "    service_tag:$1\n" if ($verbose);
            }
        } else {
            if ($chassis_info =~/Chassis Service Tag\s+:\s?(.*)$/m) {
                $server_data{'service_tag'} = $1;
                print "    service_tag:$1\n" if ($verbose);
            }
        }
        if ($chassis_info =~/Chassis Asset Tag\s+:\s?(\S*)$/m) {
            $server_data{'asset_tag'} = $1 ;
            print "    asset_tag:$1\n" if ($verbose);
        }
    }

    if ( -x "/usr/sbin/dmidecode") {
        print "  dmidecode info...\n" if ($verbose);
        if (!$server_data{'serial_number'}) {
            my $serial_number = `/usr/sbin/dmidecode -s system-serial-number`;
            chomp($serial_number);
            $server_data{'serial_number'} = $serial_number;
            print "    serial_number:$serial_number\n" if ($verbose);
        }
        if (!$server_data{'server_model'}) {
            my $server_model = `/usr/sbin/dmidecode -s system-product-name`;
            chomp($server_model);
            $server_data{'server_model'} = $server_model;
            print "    server_model:$server_model\n" if ($verbose);
        }
    }

    if (-x "/bin/hostname") {
        print "  hostname...\n" if ($verbose);
        my $hostname = `/bin/hostname`;
        chomp($hostname);
        $server_data{'hostname'} = $hostname;
        print "    hostname:$hostname\n" if ($verbose);
    }

    if (-x '/bin/arch') {
        print "  arch...\n" if ($verbose);
        my $arch = `/bin/arch`;
        chomp($arch);
        if ($arch) {
            $server_data{'os_arch'} = $arch;
            print "    os_arch:$arch\n" if ($verbose);
        }
    }

    return %server_data;
}

sub usage {
    print "usage...\n";
    exit;
}

sub getLocalTypes {
    my @types = ();
    foreach my $type ($uravo->getTypes()) {
        my $type_id = $type->id();
        next if ($type_id eq "unknown");
        my $auto_id_type = $type->get('auto_id_type');
        my $auto_id_source = $type->get('auto_id_source');
        my $auto_id_text = $type->get('auto_id_text');

        if ( $auto_id_type eq 'file' && -f $auto_id_source) {
            if ($auto_id_text) {
                open(FILE, "<$auto_id_source");
                while (<FILE>) {
                    if (/$auto_id_text/) {
                        push(@types, $type_id);
                        last;
                    }
                }
                close(FILE);
            } 
            else {
                push(@types, $type_id);
            }
        }
    }

    if (scalar(@types) == 0) {
        push(@types, "unknown");
    }
    return @types;
}

