package RSGet::Get;
# This file is an integral part of rsget.pl downloader.
#
# 2009 (c) Przemysław Iskra <sparky@pld-linux.org>
#		This program is free software,
# you may distribute it under GPL v2 or newer.

use strict;
use warnings;
use RSGet::Tools;
use RSGet::Captcha;
use RSGet::Form;
use RSGet::Wait;
use URI;
set_rev qq$Id$;

def_settings(
	debug => {
		desc => "Save errors.",
		default => 0,
		allowed => qr/\d/,
		dynamic => "NUMBER",
	},
);

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
		_id => (sprintf "%.6x", int rand 1 << 24),
		_last_dump => 0,
		make_cookie( $getter->{cookie}, $cmd ),
	};
	bless $self, $pkg;
	$self->bestinfo();

	if ( verbose( 2 ) or $cmd eq "get" ) {
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

sub form
{
	my $self = shift;
	return new RSGet::Form( $self->{body}, @_ );
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

sub cookie
{
	my $self = shift;

	return unless $self->{_cookie};
	return if -r $self->{_cookie};

	open my $c, ">", $self->{_cookie};
	foreach my $line ( @_ ) {
		print $c join( "\t", @$line ), "\n";
	}
	close $c;
}

sub click
{
	my $self = shift;
	my @opts = @_;
	$self->{_click_opts} = \@opts;
	return $self->wait( \&click_start_get, 3 + int rand 10,
		"clicking link", "delay" );
}

sub click_start_get
{
	my $self = shift;
	my @opts = @{ $self->{_click_opts} };
	delete $self->{_click_opts};
	return $self->get( @opts );
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
	my $ref = shift;
	my $keep_ref = shift;
	$self->{_referer} = $ref unless $keep_ref;

	$self->dump() if setting( "debug" ) >= 2;

	my $func = $self->{after_curl};
	unless ( $func ) {
		$self->log( "WARNING: no after_curl" );
		return;
	}
	$_ = $self->{body};
	&$func( $self );
}

sub click_download
{
	my $self = shift;
	my @opts = @_;
	$self->{_click_opts} = \@opts;
	return $self->wait( \&click_start_download, 3 + int rand 10,
		"clicking download link", "delay" );
}

sub click_start_download
{
	my $self = shift;
	my @opts = @{ $self->{_click_opts} };
	delete $self->{_click_opts};
	return $self->download( @opts );
}

sub download
{
	my $self = shift;
	$self->{stage_is_html} = shift;
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
	my $msg = shift || "multi-download not allowed";
	return $self->wait( \&start, -60 - 240 * rand, $msg, "multi" );
}

sub finish
{
	my $self = shift;

	if ( $self->{is_html} ) {
		$self->print( "is HTML" );
		$_ = $self->{body};
		my $func = $self->{stage_is_html};
		return &$func( $self );
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
	if ( $self->{body} and setting( "debug" ) ) {
		$self->dump();
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

sub dump
{
	my $self = shift;
	my $ct = $self->{content_type};

	my $ext = "txt";
	if ( $ct =~ /javascript/ ) {
		$ext = "js";
	} elsif ( $ct =~ /(ht|x)ml/ ) {
		$ext = "html";
	} elsif ( $ct =~ m{image/(.*)} ) {
		$ext = $1;
	}
	my $file = sprintf "dump.$self->{_id}.%.4d.$ext",
		++$self->{_last_dump};

	open my $f_out, '>', $file;
	print $f_out $self->{body};
	close $f_out;

	$self->log( "dumped to file: $file ($ct)" );
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
		if verbose( 1 );
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

sub started_download
{
	my $self = shift;
	my %opts = @_;
	my $fname = $opts{fname};
	my $fsize = $opts{fsize};

	my $o = $self->{_opts};
	$o->{fname} = $fname;
	$o->{fsize} = $fsize;
	$self->bestinfo();

	my @osize;
	@osize = ( fsize => $fsize ) if $fsize > 0;

	RSGet::FileList::save( $self->{_uri},
		globals => { fname => $fname, fsize => $fsize },
		options => { fname => $fname, @osize } );
	RSGet::FileList::update();

	$self->captcha_result( "ok" );
}

1;

# vim: ts=4:sw=4
