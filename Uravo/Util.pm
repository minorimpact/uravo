package Uravo::Util;

use strict;

use Uravo;
use MinorImpact;

use Fcntl qw(:flock);
use POSIX qw(floor);
my %REGEXP = (
    url_encode    => qr/([^a-zA-Z0-9_\-. ])/,
    url_decode    => qr/%([0-9a-zA-Z]{2})/,
);
my $uravo;


=item C<send_email>

Example: Uravo::Util::send_email( to => 'me@my.host.org', from => 'free.pron@the.inter.net', subject => 'Get me now!', msg => 'go to http://some.site.on.the.web/' );

Args:
  to            Email addess (comma delimited) *
  from          From email address *
  subject       Subject for email
  return_path   Return-Path header
  reply_to      Reply to address (defaults to from address)
  msg           Text body for email
  to_file       Append to file instead of emailing
  type          Content-type of msg.  default is text/plain
  * = required

=cut

sub send_email {
    my %options = @_;

    print STDERR "COMMON::Util::send_email requires to and from!\n" and return unless defined $options{to} && defined $options{from};

    my %mime_opts = ();
    $mime_opts{To}   = $options{to};
    $mime_opts{From} = $options{from};
    $mime_opts{Subject}       = $options{subject} || 'No Subject';
    $mime_opts{'Return-Path'} = $options{return_path} if defined $options{return_path};
    $mime_opts{'Reply-To'}    = defined $options{reply_to} ? $options{reply_to} : $mime_opts{From};
    $mime_opts{Data}          = $options{msg};
    $mime_opts{Type}          = $options{type} if defined $options{type};

    require COMMON::Email::MIMELite;
    my $email = COMMON::Email::MIMELite->new(%mime_opts);

    if (defined $options{to_file}) {
        if (open my $fh,">>$options{to_file}") {
            $email->print(\$fh);
            close $fh;
            return 1;
        } else {
            print STDERR "FAILED TO PRINT EMAIL TO $options{to_file}: $!\n";
            return 0;
        }
    } else {
        $email->send;
    }
}

=item C<URLEncode>

Takes a string and encodes it for a URL

=cut

sub URLEncode {
    my ($toEncode) = @_;

    $toEncode =~ s/$REGEXP{url_encode}/uc sprintf("%%%02x",ord($1))/eg;
    $toEncode =~ tr/ /+/;

    return $toEncode;
}

=item C<URLDecode>

Takes a URL encoded string and decodes the escape characters

=cut

sub URLDecode {
    my ($data) = @_;

    $data =~ tr/+/ /;
    while ($data =~ s/$REGEXP{url_decode}/chr(hex($1))/eg) {};

    return $data;
}

=item C<hash_to_url>

Take a hash and encodes it to a URL encoded string

=cut

sub hash_to_url {
    my $hash = shift;

    return '' if !$hash;

    my $str;
    foreach my $key (keys %$hash) {
        $str .= '&' if $str ne '';

        my $val;
        if (ref($hash->{$key}) eq 'ARRAY') {
            $val = join(',', \@{$hash->{$key}});
        } else {
            $val = $hash->{$key};
        }

        $str .= &URLEncode($key).'='.&URLEncode($val);
    }

    return $str;
}

=item C<url_to_hash>

Takes a URL encoded string of key/value pairs and returns a hashref

=cut

sub url_to_hash {
    my $str = shift;

    my $hash = {};
    foreach my $kv (split('&', $str)) {
        my ($k, $v) = split('=', $kv, 2);
        $k = &URLDecode($k);
        $v = &URLDecode($v);
        $hash->{$k} = $v;
    }

    return $hash;
}

=item C<format_size>

Returns the byte size string for a value.  Example, COMMON::Util::format_size(1024) returns "1.00kb".

=cut

sub format_size {
    my ($size) = @_;
    return $size unless $size;
    # unit => 1024^X
    my @r = (
            [ 'Yb', 8 ], # yottabytes   Greek or Latin octo "eight"
            [ 'Zb', 7 ], # zettabytes   Latin septem "seven"
            [ 'Eb', 6 ], # exabytes     Greek hex "six"
            [ 'Pb', 5 ], # petabytes    Greek penta "five"
            [ 'Tb', 4 ], # terabytes    Greek teras "monster"
            [ 'Gb', 3 ], # gigabytes    Greek gigas "giant"
            [ 'Mb', 2 ], # megabytes    Greek megas "large"
            [ 'kb', 1 ], # kilobytes    Greek chilioi "thousand"
        );
    foreach my $c ( @r ) {
        my $s = 1024 ** $c->[1];
        if ( $size >= $s ) {
            return sprintf('%0.2f%s', ($size/$s), $c->[0]);
        }
    }
    return $size.'b';
}

=item C<CheckForDuplicates>

Check to see if a process is already running or do fancy things like same process name but
different prefix and if it runs to long to kill the previous running version.

Example: COMMON::Util::CheckForDuplicates(<num_processes>,<prefix>,<return_mtime_of_pid_file>,<seconds_to_kill_previous_running_script>);

Returns true/false normally.  All arguments are optional.

=cut

sub CheckForDuplicates {
    my $maximumNumberOfProcesses = shift || 1;
    my $extra_prefix = shift || 0;
    my $want_mtime = shift || 0;
    my $seconds_expire = shift || 0;
    my $run_dir = shift || "/opt/uravo/run";

    $0 =~ m|([^/]+)$|;
    my $proc = $1;

    my $pidFile = "$run_dir/$proc.pid";
    $pidFile = "$run_dir/$extra_prefix" . "_$proc.pid" if ($extra_prefix);
    my $origPIDFile = $pidFile;

    # Check for stale processes first, so new processes can run immediately if $maxiumumNumberofProccesses permits.
    if ($seconds_expire) { # added looping thru older process so it kills older processes, not just the last one to run.
        my $mult_pidFile = $origPIDFile;                                                             
        for (my $i = 1; $i <= $maximumNumberOfProcesses; $i++) {                                          
            my $ending = ($i == 1) ? '' : $i;                                                          
            $mult_pidFile = "${mult_pidFile}$ending";                                                  
            my @stat = stat($mult_pidFile);                                                            
            if ( -e $mult_pidFile && ( $stat[9]+$seconds_expire ) < time() ) {                         
                unless (open(PID, "$mult_pidFile")) { die "Couldn't open pid file $mult_pidFile"; }    
                my $PidID = <PID>;                                                                     
                chomp($PidID);                                                                         
                kill 9,$PidID;                                                                         
                close(PID);                                                                            
            }                                                                                          
        }                                                                                              
    }

    if (-e $pidFile) {
        unless (open(PID, "+<$pidFile")) { die "Couldn't open pid file $pidFile"; }
    } else {
        unless (open(PID, "+>$pidFile")) { die "Couldn't open pid file $pidFile"; }
    }

    my $found = 0;

    ### fix bug bcst-421
    if (flock(PID, LOCK_NB | LOCK_EX)) {
        $found = 1;
    } else {
        close(PID);
        my $i;
        for ($i = 2; $i <= $maximumNumberOfProcesses; $i++) {
            $pidFile = "${pidFile}$i";
            if (-e $pidFile) {
                unless (open(PID, "+<$pidFile")) { die "Couldn't open pid file $pidFile"; }
            } else {
                unless (open(PID, "+>$pidFile")) { die "Couldn't open pid file $pidFile"; }
            }
            unless (flock(PID, &LOCK_NB | &LOCK_EX)) {
                close(PID);
                next;
            }
            $found = 1;
            last;
        }
    }

    if ($found) {
        select((select(PID), $| = 1)[0]);
        print PID "$$\n$0\n";
        return 0;
    }
    # return file last modified time to determine how long the process has been run
    return (-M $pidFile) if ($want_mtime);

    return 1;
}

sub add_commas {      
  my $val =  shift;
  my $euro = shift;
  my $sep = ",";
  my $point = ".";
  my $text = reverse $val;
  $text =~ s/(\d\d\d)(?=\d)(?=\d)(?!\d*\$point)/$1$sep/g;
  my $new_val = scalar reverse $text;
  return $new_val;
}

sub int2string {
    my $num       = shift;
    my $morechars = shift || 0;

    my @chars = split(//,$morechars ? $COMMON::Util::SHORT_CHARSET_LONG : $COMMON::Util::SHORT_CHARSET_SHORT);
    my $string = '';
    my $len = scalar( @chars );
    while( $num >= $len ) {
        my $mod = $num % $len;
        $num    = floor( $num / $len );
        $string = $chars[$mod] . $string;
    }
    $string = $chars[$num] . $string;
    return $string;    
}

=item C<seek_to_pos>

COMMON::Util::seek_to_pos($fh,$cb,[$tries]);

Seeks fairly effeciently through very large files to find a position based on a based in subref.  Assumes
that you are parsing text files and will do a <$fh> and then pass the next <$fh> into your subref to get
a full line for comparison.  subref should return like sort, where -1 is seeked too far, 0 is stop seeking
and 1 is need to seek farther.  If you return an array instead of an int it's assumed that the second
value is a seek offset.

It will loop up to 500 tries by default.  If your files are quite large you might need to pass in a bigger number.

Reason: on my 1.2G squid log file on an old slow machine it takes .0174 seconds to seek to any timestamp in the file

B<!!NOTE!!>  In your callback make sure you use sysseek and B<not> seek.

example:

    my $find = 80;
    my $seekcheck = sub {
        my $line = shift;
        my ($num) = $line =~ /^(\d+)/;

        # we're ok with finding numbers that are just smaller than what we're looking for and we'll seek
        # in our own code later
        if ($num > $find - 50 && $num < $find) {
            my $curpos = tell(F);
            sysseek(F,(length($line)+1) * -1,1);
            return 0;
        } elsif ($num > $find) {
            return -1;
        } elsif ($num < $find) {
            return 1;
        } else {
            my $curpos = tell(F);
            sysseek(F,(length($line)+1) * -1,1);
            return 0;
        }
    };

    open F,"<some_file";
    COMMON::Util::seek_to_pos(\*F,$seekcheck);

    my $next_line = <F>; # reads the line that matched my conditions

=cut

sub seek_to_pos {
    my $fh    = shift;
    my $cb    = shift;
    my $maxit = shift || 500;

    unless ((ref($fh) eq 'GLOB' || index(ref($fh),'IO::') == 0) && ref($cb) eq 'CODE') {
        print STDERR "seek_to_pos requires a filehandle and a callback function!\n";
        return;
    }

    # find max then reset to beginning of file
    sysseek($fh,0,2);
    my $end = sysseek($fh, 0, 1);
    sysseek($fh,0,0);

    my ($ret,$tries);
    my $curpos = int($end/2);
    do {
        sysseek($fh,$curpos,0);
        $curpos = sysseek($fh, 0, 1);
        <$fh>;
        my $line = <$fh>;
        $ret = &$cb($line);
        if ($ret == -1) {
            $curpos = int($curpos/2) * -1;
        } elsif ($ret == 1) {
            $curpos = $curpos + int($curpos / 2);
        }
    } until (++$tries == $maxit || $ret == 0);
}

sub format_std_time {
    my $self = shift;
    my $data = shift;
    
    require Date::Parse;
    
    my $output = '';
    my $input_time = &Date::Parse::str2time($data->{time});
    my $difference = time() - $input_time;
    
    my $seconds    =  $difference % 60;            # get part that is sec only
    $difference = ($difference - $seconds) / 60;   # strip off used sec and convert to minutes
    my $minutes    =  $difference % 60;            # get part that is minutes only
    $difference = ($difference - $minutes) / 60;   # strip off used minutes and convert to hours
    my $hours      =  $difference % 24;            # get hours used
    my $days = ($difference - $hours) / 24;        # strip off hours used and convert to days
    my $weeks = int($days / 7);
    my $months = int($days / 28);                  # is this close enough?
    my $year = 0;
    $year = 1 if ( $days > 365);

    my $days_ago = $self->text("global", "days_ago");
    
    my $suffix = '';
    if ($year){
        $output = $self->text("global", "over_a_year_ago");
    }
    elsif ($months){
        if ($months == 1){
             $suffix = $self->text("global", "month_ago");
        } 
        else {
            $suffix = $self->text("global", "months_ago");
        }
        $output =  "$months $suffix";
    }
    elsif ($weeks) {
        if ($weeks == 1){
            $suffix = $self->text("global", "week_ago");
        } 
        else {
            $suffix = $self->text("global", "weeks_ago");
        }
        $output =  "$weeks $suffix";
    }
    elsif ($days){
        if ($days == 1){
             $suffix = $self->text("global", "day_ago");
        }
        else {
            $suffix = $self->text("global", "days_ago");
        }
        $output =  "$days $suffix";
    }
    elsif ($hours) {
        if ($hours == 1){
            $suffix = $self->text("global", "hour_ago");
        }
        else {
            $suffix = $self->text("global", "hours_ago");
        }
        $output =  "$hours $suffix";
    }
    else {
        if ($minutes == 0){
            $suffix =  $self->text("global", "just_now");
            $output =  "$suffix";
        }
        elsif ($minutes == 1){
            $suffix = $self->text("global", "minute_ago");
            $output =  "$minutes $suffix";
        }
        else {
            $suffix = $self->text("global", "minutes_ago");
            $output =  "$minutes $suffix";
        }
    }
    
    return $output;
}

sub do_cmd {
    my $cmd = shift || return;
    my $timeout = shift;

    $uravo ||= new Uravo;
    $timeout ||= $uravo->{config}->{cmd_timeout};

    my @lines = ();

    my $pid = open(CMD, "$cmd |");
    select CMD; $| = 42; select STDOUT;

    local $SIG{ALRM} = sub { die "timeout"; };
    eval {
        alarm($timeout);
        while(<CMD>) {
            chomp;
            push(@lines, $_);
        }
        close CMD;
        alarm(0);
    };
    kill 9 => -$pid if ($pid);
    kill 9 =>  $pid if ($pid);

    return @lines;
}

sub do_sleep {
    my $time = shift || return;
    my $i = $time;
    my $prev = $0;
    while ($i > 0) {
        $0 = "$prev [sleep $i]";
        sleep 1;
        $i--;
    }
    $0 = $prev;
}

sub ps {
    my @ps = split("\n", `ps -A -o pid,state,size,comm,args`);
    shift(@ps);

    # From  'man ps'
    # D    Uninterruptible sleep (usually IO)
    # R    Running or runnable (on run queue)
    # S    Interruptible sleep (waiting for an event to complete)
    # T    Stopped, either by a job control signal or because it is being traced.
    # W    paging (not valid since the 2.6.xx kernel)
    # X    dead (should never be seen)
    # Z    Defunct ("zombie") process, terminated but not reaped by its parent.
    my $status_key = {
        D => 'uninterruptiblesleep',
        R => 'runnable',
        S => 'interruptiblesleep',
        T => 'stopped',
        W => 'paging',
        X => 'dead',
        Z => 'defunt',
    };

    my $ps = {};
    foreach my $proc (@ps) {
        my ($pid, $status, $size, $program, @args) = split(" ", $proc);
        $status = $status_key->{$status} if ($status_key->{$status});
        $ps->{$pid} = {
            command => join(" ", @args),
            size => $size,
            program => $program,
            status => $status,
        };
    }

    return $ps;
}

sub dateDelta {
    my $then = shift || return;
    my $now = shift || time();

    my $difference = $now - $then;

    my $seconds = $difference % 60;
    $difference = ($difference - $seconds) / 60;

    my $minutes = $difference % 60;
    $difference = ($difference - $minutes) / 60;

    my $hours = $difference % 24;
    $difference = ($difference - $hours) / 24;

    my $days = $difference;
    $difference = ($difference - $days) / 30;

    my $months = $difference;
    $difference = ($difference - $months) / 12;

    my $years = $difference;

    return ($years, $months, $days, $hours, $minutes, $seconds);
}

sub clean_params {
	my $params = shift || die;
    my $local_params = MinorImpact::cloneHash($params);
    foreach my $o ('bu', 'cage', 'cluster', 'interface', 'netblock', 'rack', 'server', 'silo', 'type') {
        my $o_id = $o . "_id";
        if (defined($local_params->{$o}) && !defined($local_params->{$o_id})) { $local_params->{$o_id} = $local_params->{$o}; }
    }
    return $local_params;
}


1;
