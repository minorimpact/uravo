# Uravo

1. [Overview](#overview)
2. [Installation](#installation)
3. [Configuration](#configuration)
4. [Updating](#updating)
5. [Database](Docs/Database.md)
 
## Overview

### Components

Despite the various moving parts, Uravo is designed to be simple to install and configure, consisting of one RPM, one config file, and a handful of crontab entries. In addition to mysql, to store the all the data, and apache, to provide an interface, Uravo has the following major components:

#### outpost.pl

A single process that serves as a bridge between the agents and the database. Only the outpost process talks to the database; all the other processes talk to the outpost. The outpost process also serves as a simple caching server, so any scripts using the Uravo API can access some or all of their data without having to issue a database query. This process can be run on any server that can connect to the database.

#### control.pl

A single process that performs pre- and post- processing actions on the alerts generated by the various agents. This can run on any server that can talk directory to the databae, but is usually run on a server that's also running outpost.pl.

#### agent.pl

The main data collection script, this gets run on all servers with Uravo installed, and generates alerts for the local server.

#### remote_agent.pl

Collects all 'remote,' or 'external' data, including ICMP and SNMP data. This is usually run on one or two dedicated data collection servers, but can be executed from any number of machines, as it automatically load balances among the various instances in the same silo.

### Concepts

Uravo is a tool for both generating alerts and maintaining and organizing your devices. To that end, there a number of organizational concepts that should be understood.

#### Servers

The heart of Uravo is the 'server', which can be any kind of device. For the most part, these will be actual servers, but it can also be a switch, a power supply, a chassis, a network vserver, or even a website. A good rule of thumb is _if it's got an IP, it's a server._

#### Clusters

A cluster is just a collection of servers. A cluster could be all the servers that serve a particular website, or all the servers that belong to a particular group. How you define a cluster is up to you, but a server can only exist in a single cluster.

#### Types

If a cluster tells you where a server is, then type tells you _what_ a server is. A type definition includes information about how to monitor a server, including which processes should be running, what local and remote checks it should respond to, and what the thresholds are for those checks. Multiple types can be assigned to each server.

#### Silos

Essentially, a silo is a collection of clusters, but Uravo assumes that servers in different silos cannot talk to one another. Therefore, each silo should have at least one Outpost server and at least one server running remote_agent.pl.

#### Business Units

Strictly an organizational tool, a Business Unit (or BU) is simply a collection of silos.

#### Netblocks

#### Cage/Rack

Each server can and should be assigned to a rack, which in turn is assigned to a cage. This represents the physical location of the server. This is mostly for reporting purposes, but can help with consolidating outages.

## Installation

### Package Installation

Things are not far enough along yet to start building packages.

### Manual Installation

#### Centos
```
    [~]$ sudo yum install -y mysql-client libmysqlclient-dev cpanminus
```
#### Debian
```
    [~]$ sudo apt install -y mysql-client libmysqlclient-dev cpanminus
```
**or**
```
    [~]$ sudo apt install -y mariadb-client libmariadbclient-dev cpanminus
```
#### MacOS  
```
    [~]$ brew install mysql-client cpanminus
```
Honestly, getting this installed on a mac is kind of a pain in the ass.  The main issue is DBD::mysql, which complains that it can't find a particular header.  The solution was, vaguely, to find the location of files my system, set $PASTHRU_INC to "-I&lt;dir that contained one header> -I&lt;dir that contained the second header>", then recompile and reinstall DBI and DBD::mysql by hand.

#### Linux General

For the time being, it's not assumed Uravo will be running as any particular user -- though several non-vital monitoring bits require root access. Future updates should hopefully address this. 

##### Client
```
    [~]$ mkdir dev
    [~]$ cd dev
    [~/dev]$ git clone git@github.com:minorimpact/uravo
    Cloning into 'uravo'...
    [~/dev]$ git clone git@github.com:minorimpact/perl-minorimpact
    Cloning into 'perl-minorimpact'...
    [~/dev]$ cat uravo/requirments.txt | sudo cpanm
    [~/dev]$ cd ..
    [~]$ cat << EOF >> uravo.conf
[agent]
cmd_timeout = 30
uravo_log = /tmp/uravo.log
outpost_server = 127.0.0.1
outpost_db_port = 3307
db_user = uravo
db_password = uravo

[remote_agent]
batch_count = 5
batch_size = 20

[outpost]
db_server = db.example.com
db_port = 3306
cache_server_port = 14546
EOF
    [~]$ sudo mv uravo.conf /etc/

    [~]$ mkdir lib
    [~]$ cd lib
    [~/lib]$ ln -s $HOME/dev/uravo/Uravo.pm
    [~/lib]$ ln -s $HOME/dev/uravo/Uravo
    [~/lib]$ ln -s $HOME/dev/perl-minorimpact/MinorImpact.pm
    [~/lib]$ ln -s $HOME/dev/perl-minorimpact/MinorImpact
    [~/lib]$ cd ..
```
Create the '/opt/uravo' directory and create symlinks to $HOME/dev/uravo.  This is where the package will ultimately install everything, so things shouldn't have to be adjusted too much once we get there.
```
    [~]$ sudo mkdir /opt/uravo
    [~]$ sudo chown $USER /opt/uravo
    [~]$ mkdir /opt/uravo/run
    [~]$ ln -s $HOME/dev/uravo/bin /opt/uravo/bin
    [~]$ ln -s $HOME/dev/uravo/config /opt/uravo/config
```
Add /opt/uravo/bin and $HOME/lib to your PATH and PERL5LIB variabled, respectively:
```
    [~]$ cat << EOF >> $HOME/.bashrc
PERL5LIB=\$HOME/lib:\$PERL5LIB; export PERL5LIB
PATH=/opt/uravo/bin:\$PATH; export PATH
EOF
    [~]$ . .bashrc
```
If this machine can't connect directly to the database, create an ssh tunnel, or something (this will be very specific to your installation setup):
```
    [~]$ ssh -nNT -L 3306:127.0.0.1:3306 db.example.com &
```
Start the outpost and try running the scripts manually and see if anything's working:
```
    [~]$ outpost.pl &
    [~]$ update_uravo.pl --verbose
    [~]$ agent.pl --verbose --nosleep
```
Add the appropriate crontab entries to make sure they run continuosly:
```
    [~]$ (crontab -l; cat /opt/uravo/config/agent.cron ) | crontab -
    [~]$ (crontab -l; cat /opt/uravo/config/outpost.cron ) | crontab -
```

### Database
The MySQL server that will store the Uravo data. After installing the Uravo RPM, install and configure MySQL, then execute the statements in the db-schema.sql and db-data.sql files.  
```
    [~]# yum install mysql-server 
    [~]# service mysql start 
    [~]# cat /opt/uravo/config/db-schema.sql | mysql 
    [~]# cat /opt/uravo/config/db-data.sql | mysql
```

The script will create a 'uravo' user with the password 'uravo'. If you want to change this, be sure you also update the configuration.

#### Outpost

The outpost.pl script provides all database connectivity to the various uravo scripts, as well as a rudimentary caching service. Each server with Uravo installed needs to be able to connect to an Outpost server, and each outpost server needs to be able to connect directly to the Uravo database. Aside from those requirements, any server with Uravo installed can be an outpost server. Set up a cron to launch the outpost.pl process.  
```
    [~]$ (crontab -l; cat /opt/uravo/config/outpost.cron ) | crontab -
```

outpost.pl is designed to exit cleanly if a process is already running, so this ensures the process runs almost continuously. You can run any number of outpost servers, but each server can only be configured to talk to one of them.

#### Control
control.pl does pre- and post-processing on new alerts, general cleanup, and maintains the alert history. This is usually run on the same server with outpost.pl.  
```
    [~]$ (crontab -l; cat /opt/uravo/config/control.cron ) | crontab -
```
Like outpost.pl, control.pl is designed to exit cleanly if a process is already running, so this ensures the process runs almost continuously. You should only have a single control server in your Uravo environment.

#### remote_agent.pl
By default the remote agent will run on the outpost server (it's included in the [outpost cron file](config/outpost.cron), but you can run it on any server with Uravo installed by adding it to the crontab:
```
    [~]# (crontab -l; echo "* * * * * /opt/uravo/bin/remote_agent.pl") | crontab -
```
Remote agents automatically load balance within a silo, so there's not danger running it on multiple servers.

## Configuration

There's only one configuration file for uravo: /etc/uravo.conf. Below are a
few of the key settings.

 - **uravo_log**:  The location of the uravo logfile.  
 - **outpost_server**: The outpost server this installation should communicate with.  
 - **outpost\_db\_port**: On which port to connect to the outpost for database queries.  
 - **db_user**: A mysql user that has access to the "uravo" database.  
 - **db_passwd**: The correspond password for the "uravo" user.  
 - **db_server**:  The actual server hosting the uravo database.  
 - **db_port**: The port number of the uravo database.  

## Updating

Make a note of the Uravo version before the update:  
```
    [~]# cat /opt/uravo/config/version.txt 
    0.0.4  
```
Update the RPM to the latest
version, and make a note of the new version:  
```
    [~]# yum update http://uravo.org/uravo-latest.noarch.rpm
    [~]# cat /usr/local/uravo/config/version.txt 
    0.0.7
```
The config directory contains database update files with the changes that need to be applied for each RPM
upgrade:  [~]
```
    [~]# ls -la /opt/uravo/config/db-update*
    /opt/uravo/config/db-update-0.0.3.sql 
    /opt/uravo/config/db-update-0.0.4.sql 
    /opt/uravo/config/db-update-0.0.5.sql
    /opt/uravo/config/db-update-0.0.6.sql  
```

As you can see, some versions did not include database updates. For this example, since we've gone from version 0.0.4 to version 0.0.7, only the updates for versions 0.0.5 and 0.0.6 need to be applied (presumably, the 0.0.4 changes were applied previously, and there were no database updates required specifically for version 0.0.7). Apply the changes by piping the contents of the files to mysql:
```
    [~]# cat /opt/uravo/config/db-update-0.0.5.sql | mysql
    [~]# cat /opt/uravo/config/db-update-0.0.7.sql | mysql
```
Kill the control and outpost processes on the appropriate servers:  
```
    [~]# killall outpost.pl 
    [~]# killall control.pl  
```

The cron should restart these services automatically within a minute.


