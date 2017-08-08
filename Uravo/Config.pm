package Uravo::Config;

my $config_file;
if (-f $ENV{URAVO_CONFIG}) {
    $config_file = $ENV{URAVO_CONFIG};
} elsif (-f $ENV{HOME} . "/uravo.conf") {
    $config_file = $ENV{HOME} . "/uravo.conf";
} else {
    $config_file = "/etc/uravo.conf";
}

sub new {
    my $self = {};

    open(CONFIG, $config_file);
    while(<CONFIG>) {
        chomp($_);
        next if ($_ eq '');
        next if (/^\s?#/);
        if (my ($key, $value) = (/^([^=]+)=(.*)$/)) {
            $key =~s/^\s+//;
            $key =~s/\s+$//;
            $value =~s/^\s+//;
            $value =~s/\s+$//;
            if ($value =~/^"(.+)"$/) {
                $value = $1;
            }
            my @values = split(/,/, $value);
            $self->{$key} = $values[int(rand(scalar(@values)))] || $value;
        }
    }

    $self->{run_dir} ||= "/opt/uravo/run";
    $self->{uravo_log} ||= "/opt/uravo/run/uravo.log";
    $self->{log_dir} ||= $self->{uravo_log};

    bless($self);
    return $self;
}



