#!/usr/bin/perl

use Carp;
use Getopt::Long;
use Socket;
use Data::Dumper;
use POE qw(Wheel::ReadWrite Wheel::SocketFactory Filter::Stream Component::Server::TCP);

use Uravo::Config;
use Uravo::Util;

my $config = new Uravo::Config;
my $options = {};

my $rc = GetOptions($options, qw/help verbose force debug/);

if (! $rc || $options->{help}) {
    print "Usage: $0 <options/values>\n";
    print "  --help       - this screen\n";
    print "  --verbose    - turn on debugging\n";
    print "  --force      - run even if one is already running\n";
    return;
}

my $debug = $options->{debug};

if (! $options->{force} && Uravo::Util::CheckForDuplicates(1, 0, 0, 0, $config->{run_dir})) {
    print "Already running one of these\n" if ($options->{verbose});
    exit;
}

my $cache_data = {};

my %redirects = ("$config->{outpost_server}:$config->{outpost_db_port}","$config->{db_server}:$config->{db_port}", 
                 "$config->{outpost_server}:$config->{outpost_pylon_port}","$config->{pylon_server}:$config->{pylon_port}");

# Create a session that will forward data between two sockets.

sub forwarder_create {
  my ($handle, $peer_host, $peer_port, $remote_addr, $remote_port) = @_;

  POE::Session->create(
    inline_states => {
      _start         => \&forwarder_start,
      _stop          => \&forwarder_stop,
      client_input   => \&forwarder_client_input,      # Client sent something.
      client_error   => \&forwarder_client_error,      # Error on client socket.
      server_connect => \&forwarder_server_connect,    # Connected to server.
      server_input   => \&forwarder_server_input,      # Server sent something.
      server_error   => \&forwarder_server_error,      # Error on server socket.
    },

    # Pass some things to forwarder_start():
    #         ARG0,    ARG1,       ARG2,       ARG3,         ARG4
    args => [$handle, $peer_host, $peer_port, $remote_addr, $remote_port]
  );
}

=for cookbook

The forwarder has been created.  This function sets up its initial
state.  Every Session instance has its own HEAP.  This function stores
information about the ports being redirected in its instance's heap.

It then logs the redirection to STDOUT and begins two wheels.  The
first wheel, an instance of POE::Wheel::ReadWrite, is used to interact
with the client.  The second wheel is a POE::Wheel::SocketFactory
instance.  It's used to connect to the server.

=cut

sub forwarder_start {
  my ($heap, $session, $socket, $peer_host, $peer_port, $remote_addr,
    $remote_port)
    = @_[HEAP, SESSION, ARG0, ARG1, ARG2, ARG3, ARG4];

  $heap->{log}         = $session->ID;
  $peer_host           = inet_ntoa($peer_host);
  $heap->{peer_host}   = $peer_host;
  $heap->{peer_port}   = $peer_port;
  $heap->{remote_addr} = $remote_addr;
  $heap->{remote_port} = $remote_port;

    #print "[$heap->{log}] Accepted connection from $peer_host:$peer_port\n";

  $heap->{state} = 'connecting';
  $heap->{queue} = [];

  $heap->{wheel_client} = POE::Wheel::ReadWrite->new(
    Handle     => $socket,
    Driver     => POE::Driver::SysRW->new,
    Filter     => POE::Filter::Stream->new,
    InputEvent => 'client_input',
    ErrorEvent => 'client_error',
  );

  $heap->{wheel_server} = POE::Wheel::SocketFactory->new(
    RemoteAddress => $remote_addr,
    RemotePort    => $remote_port,
    SuccessEvent  => 'server_connect',
    FailureEvent  => 'server_error',
  );
}

# The forwarder has stopped.  Log that it's done.

sub forwarder_stop {
    my $heap = $_[HEAP];
    #print "[$heap->{log}] Closing redirection session\n";
}

# The forwarder has received data from its client side.  Pass the data
# through to the server if it's connected.  Otherwise hold the data in
# a queue until the server connects.

sub forwarder_client_input {
  my ($heap, $input) = @_[HEAP, ARG0];

  if ($heap->{state} eq 'connecting') {
    push @{$heap->{queue}}, $input;
  }
  else {
    (exists $heap->{wheel_server}) and $heap->{wheel_server}->put($input);
  }
}

# The forwarder has received an error from the client.  Shut down both
# sides of the connection.  Log the error in a manner appropriate to
# its type.

sub forwarder_client_error {
  my ($kernel, $heap, $operation, $errnum, $errstr) =
    @_[KERNEL, HEAP, ARG0, ARG1, ARG2];

  if ($errnum) {
    #print("[$heap->{log}] Client connection encountered ", "$operation error $errnum: $errstr\n");
  }
  else {
    #print "[$heap->{log}] Client closed connection.\n";
  }

  delete $heap->{wheel_client};
  delete $heap->{wheel_server};
}

# The forwarder's SocketFactory has successfully connected to the
# server.  Log the success, and create a ReadWrite wheel to interact
# with the server socket.  If the client sent anything during the
# connection process, pass it through to the server now.

sub forwarder_server_connect {
  my ($kernel, $session, $heap, $socket) = @_[KERNEL, SESSION, HEAP, ARG0];

  my ($local_port, $local_addr) = unpack_sockaddr_in(getsockname($socket));
  $local_addr = inet_ntoa($local_addr);
    #print(
    #"[$heap->{log}] Established forward from local ",
    #"$local_addr:$local_port to remote ",
    #$heap->{remote_addr}, ':', $heap->{remote_port}, "\n"
    #);

  # Replace the SocketFactory wheel with a ReadWrite wheel.

  $heap->{wheel_server} = POE::Wheel::ReadWrite->new(
    Handle     => $socket,
    Driver     => POE::Driver::SysRW->new,
    Filter     => POE::Filter::Stream->new,
    InputEvent => 'server_input',
    ErrorEvent => 'server_error',
  );

  $heap->{state} = 'connected';
  foreach my $pending (@{$heap->{queue}}) {
    $kernel->call($session, 'client_input', $pending);
  }
  $heap->{queue} = [];
}

# The forwarder has received data from its server side.  Pass that
# through to the client.

sub forwarder_server_input {
  my ($heap, $input) = @_[HEAP, ARG0];

  exists($heap->{wheel_client}) and $heap->{wheel_client}->put($input);
}

# The forwarder has received an error from the server.  Shut down both
# sides of the connection.  Log the error in a manner appropriate to
# its type.

sub forwarder_server_error {
  my ($kernel, $heap, $operation, $errnum, $errstr) =
    @_[KERNEL, HEAP, ARG0, ARG1, ARG2];

  if ($errnum) {
    #print("[$heap->{log}] Server connection encountered ", "$operation error $errnum: $errstr\n");
  }
  else {
    #print "[$heap->{log}] Server closed connection.\n";
  }

  delete $heap->{wheel_client};
  delete $heap->{wheel_server};
}

### This is a stream-based forwarder server.  It listens on TCP ports,
### and it spawns new forwarders to redirect incoming connections.

# Create a session that acts as the forwarder server.

sub server_create {
  my ($local_address, $local_port, $remote_address, $remote_port) = @_;

  POE::Session->create(
    inline_states => {
      _start         => \&server_start,
      _stop          => \&server_stop,
      accept_success => \&server_accept_success,
      accept_failure => \&server_accept_failure,
    },

    # Pass this function's parameters to the server_start().
    #         ARG0,            ARG1,        ARG2,            ARG3
    args => [$local_address, $local_port, $remote_address, $remote_port]
  );
}

# Start the server.  This records where the server should connect, and
# it creates the listening socket factory.

sub server_start {
  my ($heap, $local_addr, $local_port, $remote_addr, $remote_port) =
    @_[HEAP, ARG0, ARG1, ARG2, ARG3];

#print "+ Redirecting $local_addr:$local_port to $remote_addr:$remote_port\n";

  $heap->{local_addr}  = $local_addr;
  $heap->{local_port}  = $local_port;
  $heap->{remote_addr} = $remote_addr;
  $heap->{remote_port} = $remote_port;

  $heap->{server_wheel} = POE::Wheel::SocketFactory->new(
    BindAddress  => $local_addr,         # bind to this address
    BindPort     => $local_port,         # and bind to this port
    Reuse        => 'yes',               # reuse immediately
    SuccessEvent => 'accept_success',    # generate this event on connection
    FailureEvent => 'accept_failure',    # generate this event on error
  );
}

# The server is stopping.  Log that fact.

sub server_stop {
  my $heap = $_[HEAP];
    #print(
    #"- Redirection from $heap->{local_addr}:$heap->{local_port} to ",
    #"$heap->{remote_addr}:$heap->{remote_port} has stopped.\n"
    #);
}

# The server has accepted a client connection.  Pass the details about
# it to the function that creates a new forwarder.  This is as
# unnecessary step.  The contents of forwarder_create() could have
# been placed directly into server_accept_success().

sub server_accept_success {
  my ($heap, $socket, $peer_addr, $peer_port) = @_[HEAP, ARG0, ARG1, ARG2];
  forwarder_create($socket, $peer_addr, $peer_port, $heap->{remote_addr},
    $heap->{remote_port});
}

# The server encountered an error.  Log the error.  If we've run out
# of file descriptors, we'll have to shut down the server.  A serious
# port redirector should just restart the server here.

sub server_accept_failure {
  my ($heap, $operation, $errnum, $errstr) = @_[HEAP, ARG0, ARG1, ARG2];

    #print(
    #"! Redirection from $heap->{local_addr}:$heap->{local_port} to ",
    #"$heap->{remote_addr}:$heap->{remote_port} encountered $operation ",
    #"error $errnum: $errstr\n"
    #);

  delete $heap->{server_wheel} if $errnum == ENFILE or $errnum == EMFILE;
}

### Main loop.  Create a new server for each record in %redirects.
### Run POE until all the servers (and their forwarders) shut down.

while (my ($from, $to) = each %redirects) {
  my ($from_address, $from_port) = split(/:/, $from);
  my ($to_address,   $to_port)   = split(/:/, $to);

  server_create($from_address, $from_port, $to_address, $to_port);
}

sub cache {
    my ($heap, $input) = @_[HEAP, ARG0];
    return unless ($input);

    my @fields = split(/\|/, $input);
    my ($action, $key, $value) = @fields[0..2];
    if ($action eq 'set') {
        $cache_data->{$key}{value} = $value;
        $cache_data->{$key}{expire} = time() + 600;
    } elsif ($action eq 'get') {
        $heap->{client}->put($cache_data->{$key}{value});
    } elsif ($action eq 'clear' && $key) {
        delete($cache_data->{$key});
    } elsif ($action eq 'clear') { 
        $cache_data = {};
    }
}

POE::Session->create(
    inline_states => {
        _start => sub {
            $_[KERNEL]->alarm(clean_cache => time() + 60);
        },
        clean_cache => sub {
            my $now = time();
            foreach my $key (keys %$cache_data) {
                if ($cache_data->{$key}{expire} <= $now) {
                    delete($cache_data->{$key});
                }
            }
            $_[KERNEL]->alarm(clean_cache => time() + 60);
        }
    }
);


POE::Component::Server::TCP->new(
    Port        => $config->{cache_server_port} || 14546,
    ClientInput => \&cache
);

POE::Kernel->run();
exit;

