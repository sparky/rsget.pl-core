package RSGet::Plugin;
# This file is an integral part of rsget.pl downloader.
#
# 2009-2010 (c) Przemysław Iskra <sparky@pld-linux.org>
#		This program is free software,
# you may distribute it under GPL v2 or newer.

use strict;
use warnings;
use RSGet::Processor;
use RSGet::Tools;
set_rev qq$Id$;

my %getters;

sub read_file($)
{
	my $self = shift;
	my $file = $self->{file};

	open F_IN, '<', $file or return;

	my %opts = (
		uri => [],
		map { $_ => undef } qw(name short slots cookie status web tos),
	);
	my $opts = join "|", keys %opts;

	my %parts = (
		map { $_ => [] } qw(unify pre start perl),
	);
	my $parts = join "|", keys %parts;

	my $part;
	while ( <F_IN> ) {
		chomp;
		next if /^\s*#/;
		next if /^\s*$/;

		if ( /^($parts)\s*:/ ) {
			$part = $1;
			last;
		}

		my ( $key, $value );
		unless ( ($key, $value) = /^($opts)\s*:\s+(.*)$/ ) {
			warn "$file: unrecognized line: $_\n";
			next;
		}

		if ( ref $opts{ $key } ) {
			push @{ $opts{ $key } }, $value;
		} else {
			warn "$file: $key overwritten (changed from '$opts{ $key }' to '$value')\n"
				if defined $opts{ $key };
			$opts{ $key } = $value;
		}
	}

	while ( <F_IN> ) {
		chomp;
		next if /^\s*#/;
		next if /^\s*$/;

		if ( /^($parts)\s*:/ ) {
			$part = $1;
			if ( $part eq "perl" ) {
				my @perl = <F_IN>;
				$parts{perl} = \@perl;
			}
			next;
		}

		push @{ $parts{ $part } }, $_;
	}

	close F_IN;

	foreach my $k ( keys %opts ) {
		$self->{ $k } = $opts{ $k };
	}

	return \%parts;
}

sub check_opts
{
	my $self = shift;
	my $file = shift;
	my $plugin_class = shift;

	unless ( @{$self->{uri}} ) {
		return "Can't find 'uri:'\n";
	}

	foreach ( qw(name short) ) {
		next if $self->{$_};
		return "Can't find '$_:'\n";
	}

	$file =~ m{.*/(.*?)$};
	my $fname = $1;
	if ( $fname eq $self->{name} ) {
		$self->{pkg} = $plugin_class."::". $self->{name};
	} else {
		return "Name field: '$self->{name}' differs from file name\n";
	}

	if ( $self->{status} and $self->{status} =~ /^OK(\s+.*)?$/ ) {
		return "";
	}

	return "Incorrect status\n";
}

sub check_parts
{
	my $class = shift;
	my $parts = shift;

	unless ( @{ $parts->{start} } ) {
		return "Can't find start\n";
	}

	return "";
}

sub eval_uris
{
	my $self = shift;
	my $in = $self->{uri};
	my @out;

	local $SIG{__DIE__};
	delete $SIG{__DIE__};

	foreach my $uri_text ( @$in ) {
		my $re = eval $uri_text;
		if ( $@ ) {
			warn "Problem with uri $uri_text: $@\n";
		} elsif ( not $re ) {
			warn "Problem with uri $uri_text\n";
		} elsif ( not ref $re or ref $re ne "Regexp" ) {
			warn "URI $uri_text is not a regular expression\n";
		} else {
			push @out, $re;
		}
	}

	$self->{urire} = \@out;
}

sub new
{
	my $class = shift;
	my $type = shift;
	my $file = shift;

	my $self = {
		file => $file,
		class => $type,
	};
	bless $self, $class;

	my $parts = $self->read_file();
	return undef unless $parts;
	my $error = "";
	$error .= $self->check_opts( $file, $type );
	$error .= $self->check_parts( $parts );

	$self->eval_uris();
	return undef unless @{ $self->{urire} };

	$self->{error} = "$self->{pkg} plugin error: $error" if $error;
	p $file . ": " . $self->{error} if $error;

	$self->compile if setting( "debug" );

	return $self;
}

sub compile
{
	my $self = shift;
	$self->{compiled} = 1;
	return if $self->{error};
	p "Compiling $self->{pkg} plugin ($self->{web})";
	p "$self->{pkg}: make sure you agree with $self->{tos}" if $self->{tos};

	my $parts = $self->read_file();
	unless ( $parts ) {
		$self->{error} = "$self->{pkg} compilation error: cannot read file $self->{file}";
		p "Compilation failed";
	}

	my $unify = RSGet::Processor::compile( $self, $parts );

	if ( ref $unify and ref $unify eq "CODE" ) {
		$self->{unify} = $unify;
		p "Compilation successful";
	} else {
		$self->{error} = "$self->{pkg} compilation error";
		p "Compilation failed";
	}
}

sub can_do
{
	my $self = shift;
	my $uri = shift;

	foreach my $re ( @{ $self->{urire} } ) {
		return 1 if $uri =~ m{^http://(?:www\.)?$re};
	}
	return 0;
}

sub unify
{
	my $self = shift;
	my $uri = shift;

	$self->compile() unless $self->{compiled};
	return $uri if $self->{error};

	my $func = $self->{unify};
	return $uri unless $func;

	return &$func( $uri );
}

sub start
{
	my $self = shift;
	my @args = @_;

	$self->compile() unless $self->{compiled};
	return undef if $self->{error};

	return RSGet::Get::new( $self, @args );
}


sub add
{
	my $type = shift;
	local $_ = shift;
	return 0 if /~$/;
	return 0 if m{/\.[^/]*$};
	( my $file = $_ ) =~ s#.*/##;
	return 0 if exists $getters{ $type . "::" . $file };
	my $plugin = new RSGet::Plugin( $type, $_ );
	if ( $plugin ) {
		my $pkg = $plugin->{pkg};
		$getters{ $pkg } = $plugin;
		new RSGet::Line( "INIT: ", "$pkg: added" )
			if verbose( 1 );
		return 1;
	} else {
		warn "${type}/$file: failed\n";
		return 0;
	}
}


my $from_uri_last;
sub from_uri
{
	my $uri = shift;
	if ( $from_uri_last ) {
		return $from_uri_last if $from_uri_last->can_do( $uri );
	}
	foreach my $getter ( values %getters ) {
		if ( $getter->can_do( $uri ) ) {
			$from_uri_last = $getter;
			return $getter;
		}
	}
	return undef;
}

sub from_pkg
{
	my $pkg = shift;

	return $getters{ $pkg } || undef;
}

1;

# vim: ts=4:sw=4
