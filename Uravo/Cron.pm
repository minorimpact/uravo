package Uravo::Cron;

=head1 NAME

Uravo::Cron - a library for cron scripts.

=head1 SYNOPSIS

A library to provide a standard execution logging mechanism for cron scripts.

=head1 EXAMPLE

    use Uravo::Cron;

    Uravo::Cron::execCron(\&main, { eta=>1, sleep=>2, mainarg=>{ arg1=>1, arg2=>'fff' } });

    sub main {
        # Doing cron stuff...
        if ($failure) {
            return -1;
        }
        return 0;
    }
    

=head1 METHODS

=cut

use Uravo;
use Time::Local;
use Data::Dumper;


=head2 Uravo::Cron::execCron($main, $args)

 A wrapper function for the main() function of a cron script.  If the script is called from the crontab,
 will write execution information to the cff/cron_log.cron_log table.  The main function passed to
 execCron should return an exit status of 0 for a proper completion, or non-zero for an abnormal completion.
 If main calls 'die', this output will get stored in the 'error_output' field.  

 Syntax:
 Uravo::Cron::execCron(\&main, { eta=>1, sleep=>2, mainarg=>{ arg1=>1, arg2=>'fff' } });

 Parameters:
 $main   a reference to the main subroutine
 $args   a harshref of options:
         no_log   Turn off database logging.  This will also prevent the database from redirecting
                  STDOUT while the script is running.
         eta      The estimated time it will take the script to run, in minutes (default = 180).
                  This is used to determine the time after which to alarm if the script is not
                  running by adding this value to the time the script started exectuing, along
                  with the random time generated by the sleep command.  If this value is not set,
                  the default from the cff/cron_log.cron_eta table will be used instead.  If that
                  value is also not set, then script time monitoring will be disabled, and long
                  running scripts won't generate an alarm.  UNLESS YOU HAVE A GOOD METHOD FOR
                  DYNAMICALLY DETERMINING AN ETA, USE THE DATABASE TO CONTROL THIS VALUE INSTEAD.  
                  See below for more information.
         sleep    The upper boundary of a random amount of time to sleep, in minutes (default = 0).
         debug    If TRUE, display debug output fron this function on STDOUT (default = FALSE).
                  This will also print a complete set of db queries to standard 
                  out, the output status of main, and the value of several other variables usefull for 
                  debugging when the wrapper is first implemented.
         mainarg  An optional hash reference to be passed to $main (default = none).
    

 USING THE 'ETA' VALUE

 The 'ETA' value, or 'Estimated Time of Arrival (completion)', specifies, in minutes, how long the script should run before an alert is generated.  By default, the value is 180 minutes.
 This value should be set in the database, NOT hardcoded in the script.  This allows us to make adjustments to the value without having to modify the code.

 Once the cron has gone into production, an entry is automatically added to the cff_cron_log.cron_eta for each distinct cron script name and parameter 
 list (ie, "/site/bin/email/fill_newsletter_stats.pl --site=ffadult").  To change the eta value from the default of 180 minutes, you can update the 'eta' field. For example, if
 the fill_newsletter_stats.pl script shoudln't run for more than an hour, update the eta value to '60':

 [master][cff] cron_log> update cron_eta set eta=60 where name ="/site/bin/email/fill_newsletter_stats.pl --site=ffadult";


=cut

sub execCron {
    my $main    = shift || return;
    my $args    = shift;

    my $uravo = new Uravo;

    my $mainarg = $args->{mainarg};
    
    my $pid = $$;
    my $output;
    my $output_error;
    my $exit_status;
    my $output_file = "/tmp/cron.$pid.output";
    my $script_name;
    if ($^O eq 'darwin') {
        $script_name = `/bin/ps -p $pid -o command`;
        $script_name =~s#^COMMAND\n##i;
    }
    else {
        $script_name = `/bin/ps -p $pid -o cmd`;
        $script_name =~s#^CMD\n##i;
    }
    $script_name =~s#^/usr/bin/perl\s+(-[a-zA-Z\/]+\s+)?##;
    $script_name =~s#^/usr/local/bin/perl\s+(-[a-zA-Z\/]+\s+)?##;
    $script_name =~s#^/bin/sh -c\s+##;
    $script_name =~s#\*#\\\*#g;
    chomp($script_name);

    if (length($script_name) > 255) {
        # cron_log.name is a varchar(255).
        $script_name = substr($script_name, 0, 255);
    }
    

    my $in_cron = ($ENV{SSH_TTY} || $ENV{SUDO_UID})?0:1;
    my $sleep = 0;
    if (defined($args->{sleep}) && $in_cron) {
        $sleep = $args->{sleep};
    }
    $sleep   = int(rand()*($sleep * 60));

    my $eta = 0;
    if (defined($args->{eta})) {
        $eta = ($args->{eta} * 60);
        $eta += $sleep;
    }

    open(OLDOUT, ">&STDOUT");

    my $start_time  = time();
    my $server = $uravo->getServer();
    if (!$args->{no_log} && $server) {
        if ($eta) {
            $uravo->{db}->do('INSERT INTO cron_log (server_id, start_date, sleep, pid, name, eta_date) VALUES (?, FROM_UNIXTIME(?), ?, ?, ?, FROM_UNIXTIME(?))', undef, ($server->id(), $start_time, $sleep, $pid, $script_name, ($start_time + $eta))) || carp("Can't insert into cron_log:" . $uravo->{db}->errstr);
        } else {
            $uravo->{db}->do('INSERT INTO cron_log (server_id, start_date, sleep, pid, name, eta_date) VALUES (?, FROM_UNIXTIME(?), ?, ?, ?, NULL)', undef, ($server->id(), $start_time, $sleep, $pid, $script_name)) || carp("Can't insert into cron_log:" . $uravo->{db}->errstr);
        }
        sleep $sleep;

        open(STDOUT, "> $output_file");
        select STDOUT; $| = 1;
    }

    eval {
        $exit_status = $main->( $mainarg );
        $exit_status = 0 if (!defined($exit_status) || $exit_status eq '');
    };
    $error_output = $@ || undef;
    if ($error_output) {
        $exit_status = -1;
    }

    if ($exit_status && !($exit_status =~/^-?[0-9]+$/)) {
        $error_output = $exit_status;
        $exit_status = -1;
    }

    if ($args->{no_log}) {
        print STDERR $error_output;
    } elsif ($server) {
        my $end_time = time();
        close(STDOUT);
        open(OUTFILE, "<$output_file");
        while (<OUTFILE>) {
            $output .= $_;
        }
        close(OUTFILE);
        unlink($output_file);
        open(STDOUT, ">&OLDOUT");
        select STDOUT; $| = 1;
        
        print $output;
        print STDERR $error_output;

        if ($exit_status && !$error_output) {
            $error_output = $output;
        }

        $uravo->{db}->do('UPDATE cron_log SET end_date=FROM_UNIXTIME(?), exit_status=?, error_output=? WHERE server_id=? AND start_date=FROM_UNIXTIME(?) AND name=? AND pid=?', undef, ($end_time, $exit_status, $error_output, $server->id(), $start_time, $script_name, $pid)) || carp("Can't udpate cron_log:" . $uravo->{db}->errstr);
    }
}

=head2 Uravo::Cron::in_array($needle, @haystack)

 Search for the existence of a variable within an array.

 Parameters:
   $needle    An arbitrary value.
   @haystack  The array of values in which we want to check to see if $needle exists.

 Returns:
    TRUE or FALSE depending on whether @haystack contains $needle.

=cut

sub in_array {
    my $needle = shift;
    my @haystack = @_;

    return unless (scalar(@haystack) > 0);

    foreach my $hay (@haystack) {
        return 1 if ($needle eq $hay || $needle == $hay);
    }
    return;
}

=head2 Uravo::Cron::last_run_time($cron_entry[, $current_time])

 Parses a cron entry and determines the last time it should have run prior to $current_time.

 Parameters:
   $cron_entry      A standard cron entry.
   $current_time    An optional, arbitrary unixtime value to use as a comparison. Defaults to time().

 Returns:
   unixtime value (seconds send time epoch).

=cut

sub last_run_time {
    my $cron = shift || return;
    my $now = shift || time();

    my @tokens = split(/\s+/, $cron);
    my $c_min = shift(@tokens);
    my $c_hour = shift(@tokens);
    my $c_mday = shift(@tokens);
    my $c_month = shift(@tokens);
    my $c_wday = shift(@tokens);
    my @c_min = convert_cron_time_item_to_list($c_min, 'min');
    my @c_hour = convert_cron_time_item_to_list($c_hour, 'hour');
    my @c_mday = convert_cron_time_item_to_list($c_mday, 'mday');
    my @c_month = convert_cron_time_item_to_list($c_month, 'month');
    my @c_wday = convert_cron_time_item_to_list($c_wday, 'wday');

    my $test_time = $now;
    my ($sec, $min, $hour, $mday, $mon, $year, $wday, $yday, $isdst) = localtime($test_time);

    until ( 
            (in_array($min, @c_min) && in_array($hour, @c_hour) && in_array($mon, @c_month)) &&
            (   
                (   
                    (scalar(@c_mday) < 31 && in_array($mday, @c_mday)) ||
                    (scalar(@c_wday) < 7 && in_array($wday, @c_wday))
                ) || ( scalar(@c_mday) == 31 && scalar(@c_wday) == 7)
            )
        ) {
        $test_time = $test_time - 60;
        ($sec, $min, $hour, $mday, $mon, $year, $wday, $yday, $isdst) = localtime($test_time);

        # Prevent (nearly) infinite loops by exiting out if we have to go back more than a year.
        return -1 if ($test_time < ($now - 31536000));
    }

    my $then = timelocal(0,$min, $hour, $mday, $mon, $year);
    return $then;
}

=head2 Uravo::Cron::convert_cron_time_item_to_list($item, $field_time)

 Internal function that returns a list of all the explicit values of a particular cron item type.
 For example, in a crontab, the month might be represented as */2.  When passed to this function
 as ('*/2','month'), would return "1,3,5,7,9,11".  Handles all the standard methods of specifying
 cron fields, including 'all' ('*'), 'inervals' ('*/3'), 'ranges' ('1-4'), and 'ranged-interval'
 ('1-7/4').

 Parameters:
   $item         A cron field, such as '*', '*/3', or '5-7'.
   $cron_field   Which field this applies to.

 Returns:
   An array of values.


=cut


sub convert_cron_time_item_to_list {
    my $item = shift;
    my $cron_field = shift || return;

    return if ($item eq '');

    if ($cron_field eq 'wday') {
        $item =~s/Sun/0/;
        $item =~s/Mon/1/;
        $item =~s/Tue/2/;
        $item =~s/Wed/3/;
        $item =~s/Thu/4/;
        $item =~s/Fri/5/;
        $item =~s/Sat/6/;
    }

    $item =~s/^0(\d)/$1/;
    $item =~s/^ (\d)/$1/;

    my $max;

    $max = 59 if ($cron_field eq 'min');
    $max = 23 if ($cron_field eq 'hour');
    $max = 30 if ($cron_field eq 'mday');
    $max = 11 if ($cron_field eq 'month');
    $max = 6 if ($cron_field eq 'wday');
    return unless ($max);

    my @list = ();
    if ($item =~/^(.*)\/(\d+)$/) {
        my $sub_item = $1;
        my $step = $2;
        # some crons have minute = "*/60". This gets translated as "0" by crond.
        if ($step > $max) {
            return (0);
        }
        my @sub_list = convert_cron_time_item_to_list($sub_item, $cron_field);

        my $count = $step;
        foreach my $i (@sub_list) {
            if ($count == $step) {
                push(@list, $i);
                $count = 0;
            }
            $count++;
        }
    } elsif ($item eq '*') {
        @list = (0..$max);
        if ($cron_field eq 'mday') {
            @list = map {$_+1 } @list;
        }
    } elsif ($item =~/,/) {
        foreach my $i (split(',', $item)) {
            push(@list,convert_cron_time_item_to_list($i, $cron_field));
        }
    } elsif ($item =~/^(\d+)-(\d+)$/) {
        my $first = $1;
        my $last = $2;
        if ($cron_field eq 'month') {
            $first--;
            $last--;
        }
        @list = ($first..$last);
    } elsif ($item =~/^\d+$/) {
        if ($cron_field eq 'month') {
            $item--;
        }
        if ($cron_field eq 'wday' && $item == 7) {
            $item = 0;
        }
        @list = ($item);
    }

    return @list;
}

1;

