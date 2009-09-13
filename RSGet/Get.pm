package RSGet::Get;

use strict;
use warnings;
use RSGet::Tools;
use RSGet::Captcha;
use RSGet::Wait;
use URI;

BEGIN {
	our @ISA;
	@ISA = qw(RSGet::Wait RSGet::Captcha);
}

my %cookies;
sub make_cookie
{
	my $c = shift;
	my $cmd = shift;
	return () unless $c;
	unless ( $c =~ s/^!// ) {
		return if $cmd eq "check";
	}
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
		make_cookie( $getter->{cookie}, $cmd ),
	};
	bless $self, $pkg;
	$self->bestinfo();

	if ( $settings{logging} > 1 or $cmd eq "get" ) {
		my $outifstr = $outif ? "[$outif]" :  "";

		hadd $self,
			_line => new RSGet::Line( "[$getter->{short}]$outifstr " );
		$self->print( "start" );
		$self->linedata();
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

sub print
{
	my $self = shift;
	my $text = shift;
	my $line = $self->{_line};
	return unless $line;
	$line->print( $self->{_name} . ": " . $text );
}

sub linedata
{
	my $self = shift;
	my @data = @_;
	my $line = $self->{_line};
	return unless $line;

	my %data = (
		name => $self->{bestname},
		size => $self->{bestsize},
		uri => $self->{_uri},
		@data,
	);

	$line->linedata( \%data );
}

sub start
{
	my $self = shift;

	foreach ( keys %$self ) {
		delete $self->{$_} unless /^_/;
	}
	delete $self->{_referer};
	$self->bestinfo();

	return $self->stage0();
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

	return $self->wait( \&start, $time, $msg, "restart" );
}

sub multi
{
	my $self = shift;
	return $self->wait( \&start, -60 - 240 * rand, "multi-download not allowed", "multi" );
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
	RSGet::FileList::save( $self->{_uri}, cmd => "DONE" );
	RSGet::Dispatch::finished( $self );
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
	if ( $self->{body} and $settings{errorlog} ) {
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

	$self->print( $msg ) || $self->log( $msg );
	RSGet::FileList::save( $self->{_uri}, options => { error => $msg } );
	RSGet::Dispatch::finished( $self );
}

sub problem
{
	my $self = shift;
	my $line = shift;
	my $msg = $line ? "problem at line: $line" : "unknown problem";
	my $retry = 8;
	$retry = 3 if $self->{_cmd} eq "check";
	if ( ++$self->{_try} < $retry ) {
		return $self->wait( \&start, -2 ** $self->{_try}, $msg, "problem" );
	} else {
		return $self->error( $msg . ", aborting" );
	}
}

sub bestinfo
{
	my $self = shift;
	my $o = $self->{_opts};
	my $i = $self->{info};

	my $bestname = $o->{fname}
		|| $i->{name} || $i->{iname}
		|| $i->{aname} || $i->{ainame}
		|| $o->{name} || $o->{iname}
		|| $o->{aname} || $o->{ainame};
	unless ( $bestname ) {
		my $uri = $self->{_uri};
		$bestname = ($uri =~ m{([^/]+)/*$})[0] || $uri;
	}
	$self->{bestname} = $bestname;
	$bestname =~ s/\0/(?)/;
	$self->{_name} = $bestname;

	my $bestsize = $o->{fsize}
		|| $i->{size} || $i->{asize}
		|| $o->{size} || $o->{asize}
		|| "?";
	$self->{bestsize} = $bestsize;
}

sub info
{
	my $self = shift;
	my %info = @_;
	$info{asize} =~ s/ //g if $info{asize};
	RSGet::FileList::save( $self->{_uri}, options => \%info );

	$self->{info} = \%info;
	$self->bestinfo();

	return 0 unless $self->{_cmd} eq "check";
	p "info( $self->{_uri} ): $self->{bestname} ($self->{bestsize})\n"
		if $settings{logging} > 0;
	RSGet::Dispatch::finished( $self );
	return 1;
}

sub link
{
	my $self = shift;
	my %links;
	my $i = 0;
	foreach ( @_ ) {
		$links{ "link" . ++$i } = $_;
	}
	RSGet::FileList::save( $self->{_uri}, cmd => "DONE",
		links => [ @_ ], options => \%links );
	RSGet::Dispatch::finished( $self );
	return 1;
}

sub set_finfo
{
	my $self = shift;
	my $fname = shift;
	my $fsize = shift;
	my $o = $self->{_opts};
	$o->{fname} = $fname;
	$o->{fsize} = $fsize;
	$self->bestinfo();

	RSGet::FileList::save( $self->{_uri},
		globals => { fname => $fname, fsize => $fsize } );
	RSGet::FileList::update();
}

1;

# vim:ts=4:sw=4
