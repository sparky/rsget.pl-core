package RSGet::Get;

use strict;
use warnings;
use RSGet::Tools;
use URI;

my %cookies;
sub make_cookie
{
	my $c = shift;
	return () unless $c;
	$cookies{ $c } = 1 unless $cookies{ $c };
	my $n = $cookies{ $c }++;

	local $_ = ".cookie.$c.$n.txt";
	unlink $_ if -e $_;
	return _cookie => $_;
}


sub new
{
	my ( $pkg, $cmd, $uri, $options, $outif ) = @_;
	my $getter = $getters{ $pkg };

	my $self = {
		_uri => $uri,
		_opts => $options,
		_try => 0,
		_cmd => $cmd,
		_pkg => $pkg,
		_outif => $outif,
		make_cookie( $getter->{cookie} ),
	};
	bless $self, $pkg;

	if ( $cmd eq "get" ) {
		my $outifstr = $outif ? "[$outif]" :  "";
		hadd $self,
			_line => new RSGet::Line( "[$getter->{short}]$outifstr " ),
			_name => $options->{fname} || ($uri =~ m{([^/]+)/*$})[0];
		$self->print( "start" );
	}

	$self->start();
	return $self;
}

sub DESTROY
{
	my $self = shift;
	if ( my $c = $self->{_cookie} ) {
		unlink $c;
	}
}

sub log
{
	my $self = shift;
	my $text = shift;
	my $line = $self->{_line};
	return unless $line;

	my $outifstr = $self->{_outif} ? "[$self->{_outif}]" :  "";
	my $getter = $getters{ $self->{_pkg} };
	new RSGet::Line( "[$getter->{short}]$outifstr ", $self->{_name} . ": " . $text );
}


sub print
{
	my $self = shift;
	my $text = shift;
	my $line = $self->{_line};
	return unless $line;
	$line->print( $self->{_name} . ": " . $text );
}

sub get
{
	my $self = shift;
	$self->{after_curl} = shift;
	my $uri = shift;

	$uri = URI->new( $uri )->abs( $self->{_referer} )->as_string
		if $self->{_referer};

	RSGet::Curl::new( $uri, $self, @_ );
}

sub get_finish
{
	my $self = shift;
	$self->{_referer} = shift;

	my $func = $self->{after_curl};
	$_ = $self->{body};
	&$func( $self );
}

sub download
{
	my $self = shift;
	my $uri = shift;
	$self->print("starting download");
	$self->get( \&finish, $uri, save => 1, @_ );
}

sub restart
{
	my $self = shift;
	my $time = shift || 1;
	my $msg = shift || "restarting";

	return $self->wait( \&start, $time, $msg );
}

sub multi
{
	my $self = shift;
	return $self->wait( 60 + 240 * rand, \&start, "multi-download not allowed, waiting" );
}

sub finish
{
	my $self = shift;

	if ( $self->{is_html} ) {
		$self->print( "is HTML" );
		$_ = $self->{body};
		return $self->stage_is_html();
	}

	RSGet::Dispatch::mark_used( $self );
	RSGet::Dispatch::finished( $self, $self->{dlinfo} );
}

sub abort
{
	my $self = shift;
	$self->print( $self->{_abort} || "aborted" );
	RSGet::Dispatch::finished( $self );
}

sub error
{
	my $self = shift;
	my $msg = shift;
	if ( $self->{body} ) {
		my $n = 0;
		my $name;
		do {
			$name = "errorlog." . (++$n) . ".html";
		} while ( -r $name );
		open ERR_OUT, '>', $name;
		print ERR_OUT $self->{body};
		close ERR_OUT;

		$msg .= "; saved $name";
	}

	$self->print( $msg );
	RSGet::Dispatch::finished( $self, $msg );
}

sub start
{
	my $self = shift;
	$self->clean();
	return $self->stage0();
}

sub problem
{
	my $self = shift;
	my $line = shift;
	my $msg = $line ? "problem at line: $line" : "unknown problem";
	if ( ++$self->{_try} < 8 ) {
		return $self->wait( \&start, 2 ** $self->{_try}, $msg . ", waiting" );
	} else {
		return $self->error( $msg . ", aborting" );
	}
}

sub clean
{
	my $self = shift;
	foreach ( keys %$self ) {
		delete $self->{$_} unless /^_/;
	}
	delete $self->{_referer};
}

sub info
{
	my $self = shift;
	my %info = @_;
	$info{name} = de_ml( $info{name} );
	$info{kilo} ||= 1024;

	$self->{_name} = $self->{_opts}->{fname} || $info{name};
	return 0 unless $self->{_cmd} eq "check";
	#p "info( $self->{_uri} ): $info{name}, $info{size}\n";
	RSGet::Dispatch::finished( $self, \%info );
	return 1;
}

sub search
{
	my $self = shift;
	my %search = @_;

	foreach my $name ( keys %search ) {
		my $search = $search{$name};
		if ( m/$search/ ) {
			$self->{$name} = $1;
		} else {
			$self->problem( "Can't find '$name': $search" );
			return 1;
		}
	}
	return 0;
}

sub link
{
	my $self = shift;
	my $links = [ @_ ];
	RSGet::Dispatch::finished( $self, $links );
	return 1;
}

sub set_fname
{
	my $self = shift;
	my $fname = shift;
	$self->{_name} = $fname;

	my $opts = $RSGet::FileList::uri_options{ $self->{_uri} } ||= {};
	hadd $opts,
		fname => $fname;

	$RSGet::FileList::reread = 1;
}

my %waiting;
sub wait
{
	my $self = shift;
	my $next_stage = shift;
	my $wait = shift() + int rand 10;
	my $msg = shift || "???";

	my $time = time;
	delete $self->{wait_until_should};

	my $rnd_wait = int rand ( 5 * 60 ) + 2 * 60;
	if ( $wait > $rnd_wait + 1 * 60 ) {
		$self->{wait_until_should} = $time + $wait;
		$wait = $rnd_wait;
	}

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

# vim:ts=4:sw=4
