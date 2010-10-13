package RSGet::ConfigFile;
# This file is an integral part of rsget.pl downloader.
#
# 2010 (c) Przemysław Iskra <sparky@pld-linux.org>
#		This program is free software,
# you may distribute it under GPL v2 or newer.

use strict;
use warnings;
use RSGet::Config;

RSGet::Config::register_settings(
	dynaconfig_file => {
		desc => "Additional config file.",
		default => '%{config_dir}/config.dyn',
	},
);

sub new
{
	my $class = shift;
	my $file = shift || RSGet::Config::get( undef, "dynaconfig_file" );

	my $self = {
		file => $file,
		cache => {},
		updates => 0,
	};

	return bless $self, $class;
}

sub set
{
	my $self = shift;
	my ( $user, $key, $value ) = @_;

	$value =~ s/\n/%{n}/g;

	$key = $user . ":" . $key if defined $user;

	$self->{cache}->{$key} = $value;

	if ( ++$self->{updates} > 100 ) {
		_rewrite( $self );
	} else {
		open my $f_out, ">>", $self->{file};
		print $f_out "$key = $value\n";
		close $f_out;
	}
}

sub get
{
	my $self = shift;
	my ( $user, $key ) = @_;

	$key = $user . ":" . $key if defined $user;

	return $self->{cache}->{$key};
}

sub _rewrite
{
	my $self = shift;

	$self->{updates} = 0;
	my $cache = $self->{cache};

	my $file = $self->{file};
	warn "Rewritting file $file\n";
	open my $f_out, ">", $file;

	print $f_out "# Rewritten " . (localtime) . "\n";
	foreach my $k ( sort keys %$cache ) {
		print $f_out "$k = $cache->{$k}\n";
	}
	close $f_out;
}

sub DESTROY
{
	goto &_rewrite;
}

sub getall
{
	my $self = shift;

	local $_;

	my @lines;
	my $line = 0;
	my $cache = $self->{cache};

	my $file = $self->{file};
	open my $f_in, "<", $file
		or return [];
	while ( <$f_in> ) {
		$line++;
		next if /^#/;
		if ( my ( $key, $value ) = /^\s*(\S+)\s*=\s*(.*?)\s*$/ ) {
			$cache->{$key} = $value;
			my $user = ( $key =~ s/^(\S+):// );
			push @lines, [ $user, $key, $value, "dynaconfig $file, line $line" ];
		}
	}
	close $f_in;

	return \@lines;
}

1;

# vim: ts=4:sw=4:fdm=marker
