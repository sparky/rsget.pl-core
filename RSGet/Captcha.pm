package RSGet::Captcha;
# This file is an integral part of rsget.pl downloader.
#
# 2009 (c) Przemysław Iskra <sparky@pld-linux.org>
#		This program is free software,
# you may distribute it under GPL v2 or newer.

use strict;
use warnings;
use Digest::MD5 qw(md5_hex);
use File::Path;
use RSGet::Tools;
use RSGet::CaptchaImage;
set_rev qq$Id$;

def_settings(
	captcha_save_results => {
		desc => "Save captcha results, for captcha debugging.",
		type => "PATH",
	},
);

our %needed;
our %solved;

my %waiting;
sub captcha
{
	my $self = shift;
	my $next_stage = shift;
	my $check = shift;
	my %opts = @_;

	die "Getter error, captcha argument is not a regexp\n"
		if not $check or ref $check ne "Regexp";

	my $data = $self->{body};
	my $md5 = md5_hex( $data );
	$self->{captcha_md5} = $md5;
	$self->{captcha_next} = $next_stage;
	$self->{captcha_data} = \$data;

	$self->{captcha_until} = time + 200;
	delete $self->{captcha_response};

	my $id = 0;
	++$id while exists $waiting{ $id };
	$waiting{ $id } = $self;

	if ( my $solver = $opts{solver} ) {
		my $text;
		local $SIG{__DIE__};
		delete $SIG{__DIE__};
		eval {
			$text = &$solver( $self->{captcha_data} );
		};
		if ( $@ ) {
			warn "Captcha solver problem: $@\n";
		} else {
			p "Captcha solver returned: " . $text
				if verbose( 2 );
			$text = undef unless $text =~ /^$check$/;
			return $self->solved_delay( $text );
		}
	}
	if ( my $process = $opts{process} ) {
		my $text;
		local $SIG{__DIE__};
		delete $SIG{__DIE__};
		eval {
			die "tesseract not found\n" unless require_prog( "tesseract" );
			my $image = new RSGet::CaptchaImage( $self->{captcha_data} );
			$text = &$process( $image );
		};
		if ( $@ ) {
			warn "Captcha process problem: $@\n";
		} else {
			p "Captcha process returned: " . ( defined $text ? $text : "undef" )
				if verbose( 2 );
			if ( defined $text ) {
				$text = undef unless $text =~ /^$check$/;
			}
			return $self->solved_delay( $text );
		}
	}

	# add to ask list
	$needed{ $md5 } = [ $self->{content_type}, $self->{captcha_data} ];
	$self->linedata( captcha => $md5 );
}

sub captcha_result
{
	my $self = shift;
	my $result = shift;

	my $name = $self->{captcha_md5};
	delete $self->{captcha_md5};

	return unless $name;
	my $capdir = setting( "captcha_save_results" );
	return unless $capdir;

	my $subdir;
	if ( not defined $result ) {
		$subdir = "unsolved";
	} elsif ( $result =~ /^(ok|fail)$/i ) {
		$subdir = lc $result;
		$name .= "_" . $self->{captcha_response};
	} else {
		warn "Captcha Result is not OK or FAIL: $result\n";
		return;
	}

	my $getter = RSGet::Plugin::from_pkg( $self->{_pkg} );
	my $dir = "$capdir/captcha/$getter->{short}/$subdir";
	mkpath( $dir ) unless -d $dir;

	my $file = "$dir/$name";
	open my $f, ">", $file;
	print $f ${$self->{captcha_data}};
	close $f;

	$self->log( "Saved $file" )
		if verbose( 1 );
}

sub solved_delay
{
	my $self = shift;
	my $captcha = shift;

	$self->linedata( wait => "delay" );
	$self->{captcha_response} = $captcha;
	my $wait = irand 5, 15;
	unless ( defined $captcha ) {
		$wait /= 4;
		$self->captcha_result( undef );
	}
	$self->{captcha_until} = time + $wait;
}

sub solved
{
	my $self = shift;
	my $captcha = shift;

	$self->{captcha_response} = $captcha;
	$self->{body} = $captcha;
	$_ = $captcha;

	$self->linedata();
	my $func = $self->{captcha_next};
	&$func( $self );
}

sub unsolved
{
	my $self = shift;;

	$self->captcha_result( undef );
	delete $self->{body};
	$_ = undef;

	$self->linedata();
	my $func = $self->{captcha_next};
	&$func( $self );
}

sub captcha_update
{
	my $time = time;

	foreach my $id ( keys %waiting ) {
		my $obj = $waiting{ $id };
		my $left = $obj->{captcha_until} - $time;
		my $md5 = $obj->{captcha_md5} || "";
		my $captcha = $obj->{captcha_response};
		if ( $left <= 0 ) {
			if ( $captcha ) {
				solved( $obj, $captcha );
			} else {
				$obj->print( "captcha not solved" );
				unsolved( $obj );
			}
		} elsif ( $obj->{_abort} ) {
			$obj->abort();
		} elsif ( my $s = $solved{ $md5 } ) {
			solved( $obj, $s );
		} else {
			$obj->print(
				( $captcha ? "captcha solved: $captcha, delaying " : "solve captcha " )
				. s2string( $left )
			);
			next;
		}
		delete $waiting{ $id };
		delete $needed{ $md5 };
	}
	RSGet::Line::status( 'captcha' => scalar keys %waiting );
}

1;

# vim: ts=4:sw=4:fdm=marker
