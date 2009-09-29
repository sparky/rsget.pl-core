package RSGet::Wait;

use strict;
use warnings;
use RSGet::Tools;
set_rev qq$Id$;

my %waiting;
sub wait
{
	my $self = shift;
	my $next_stage = shift;
	my $wait = shift;
	my $msg = shift || "???";
	my $reason = shift || "wait";

	$self->linedata( wait => $reason );

	my $time = time;
	delete $self->{wait_until_should};

	my $rnd_wait = int rand ( 5 * 60 ) + 2 * 60;
	if ( $wait > $rnd_wait + 1 * 60 ) {
		$self->{wait_until_should} = $time + $wait;
		$wait = $rnd_wait;
	}
	$wait = - $wait if $wait < 0;
	$wait += int rand 10;

	$self->{wait_next} = $next_stage;
	$self->{wait_msg} = $msg;
	$self->{wait_until} = $time + $wait;

	my $id = 0;
	++$id while exists $waiting{ $id };
	$waiting{ $id } = $self;
}

sub wait_finish
{
	my $self = shift;;

	delete $self->{body};
	$_ = undef;

	$self->linedata();
	my $func = $self->{wait_next};
	&$func( $self );
}

sub wait_update
{
	my $time = time;

	foreach my $id ( keys %waiting ) {
		my $obj = $waiting{ $id };
		my $left = $obj->{wait_until} - $time;
		if ( $left <= 0 ) {
			delete $waiting{ $id };
			$obj->print( $obj->{wait_msg} . "; done waiting" );
			wait_finish( $obj );
		} elsif ( $obj->{_abort} ) {
			delete $waiting{ $id };
			$obj->abort();
		} else {
			if ( $obj->{wait_until_should} ) {
				$obj->print( sprintf "%s; should wait %s, retrying in %s",
					$obj->{wait_msg},
					s2string( $obj->{wait_until_should} - $time),
					s2string( $left ) );
			} else {
				$obj->print( $obj->{wait_msg} . "; waiting " . s2string( $left ) );
			}
		}
	}
	RSGet::Line::status( 'waiting' => scalar keys %waiting );
}

1;
