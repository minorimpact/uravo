package Uravo::Agent::Module;

use Uravo;
use Uravo::Util;

my $uravo;

sub new {
    my $class = shift || return;
    my $self = {};

    $uravo = new Uravo;

    $self->{uravo} = $uravo;
    $self->{server} = $uravo->getServer() || die "Can't get server object";
    $self->{monitoringValues} = $self->{server}->getMonitoringValues() || die "can't get monitoringValues()";
    $self->{options} = $uravo->{options};

    bless($self, $class);
    return $self;
}

sub getSeverity {
    my $self = shift || die;
    return $self->getSeverityGT(@_);
}

sub getSeverityGT {
	my $self = shift || die;
    return $self->_getSeverity(@_, "gt");
}

sub getSeverityLT {
    my $self = shift || die;
    return $self->_getSeverity(@_, "lt");
}

sub _getSeverity {
	my $self = shift || die;
	my $AlertGroup = shift || die "must specify AlertGroup";
	my $AlertKey = shift || $AlertGroup;
	my $value = shift || 0;
    my $operator = shift || "gt";

	return "green" unless (defined($self->{monitoringValues}->{$AlertGroup}->{$AlertKey}));
	my $mV = $self->{monitoringValues}->{$AlertGroup}->{$AlertKey};
    return "green" if ($mV->{disabled});
    if ($operator eq "gt") {
        if ($value >= $mV->{'red'}) {
            return "red";
        } elsif ($value >= $mV->{'yellow'}) {
            return "yellow";
        }
    }
    elsif ($operator eq "lt") {
        if ($value <= $mV->{'red'}) {
            return "red";
        } elsif ($value <= $mV->{'yellow'}) {
            return "yellow";
        }
    }
    return "green";
}

sub run {
    my $self = shift || die;


    return;
}

1;
