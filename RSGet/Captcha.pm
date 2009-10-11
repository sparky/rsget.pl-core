package RSGet::Captcha;

use strict;
use warnings;
use Digest::MD5 qw(md5_hex);
use RSGet::Tools;
set_rev qq$Id$;

our %needed;
our %solved;

my %waiting;
sub captcha
{
	my $self = shift;
	my $next_stage = shift;
	my $ct = shift;

	my $md5 = md5_hex( $self->{body} );

	$needed{ $md5 } = [ $ct, $self->{body} ];

	$self->linedata( captcha => $md5 );

	$self->{captcha_md5} = $md5;
	$self->{captcha_next} = $next_stage;
	$self->{captcha_until} = time + 200;

	my $id = 0;
	++$id while exists $waiting{ $id };
	$waiting{ $id } = $self;
}

sub solved
{
	my $self = shift;
	my $captcha = shift;

	$self->{body} = $captcha;
	$_ = $captcha;

	$self->linedata();
	my $func = $self->{captcha_next};
	&$func( $self );
}

sub unsolved
{
	my $self = shift;;

	delete $self->{body};
	$_ = undef;

	$self->linedata();
	$self->start();
}

sub captcha_update
{
	my $time = time;

	foreach my $id ( keys %waiting ) {
		my $obj = $waiting{ $id };
		my $left = $obj->{captcha_until} - $time;
		my $md5 = $obj->{captcha_md5};
		if ( $left <= 0 ) {
			$obj->print( "captcha not solved" );
			unsolved( $obj );
		} elsif ( $obj->{_abort} ) {
			$obj->abort();
		} elsif ( my $s = $solved{ $md5 } ) {
			solved( $obj, $s );
		} else {
			$obj->print( "solve captcha " . s2string( $left ) );
			next;
		}
		delete $waiting{ $id };
		delete $needed{ $md5 };
	}
	RSGet::Line::status( 'captcha' => scalar keys %waiting );
}

1;

# vim:ts=4:sw=4
