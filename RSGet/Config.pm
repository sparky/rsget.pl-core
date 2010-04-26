package RSGet::Config;
# This file is an integral part of rsget.pl downloader.
#
# 2010 (c) Przemysław Iskra <sparky@pld-linux.org>
#		This program is free software,
# you may distribute it under GPL v2 or newer.

use strict;
use warnings;
#use RSGet::Common;
require RSGet::SQL;

RSGet::Config::register_settings(
	core_config_dir => {
		desc => "Main config directory.",
		default => "$ENV{HOME}/.rsget.pl",
	},
	core_config_file => {
		desc => "Main config file.",
		default => "%{core_config_dir}/config",
	},
);

# registered settings
my %registered;

# options default, set, reset
my %options;

# add settings to default hash
{
	my %options = (
		desc => "Setting description.",
		default => "Default value.",
		allowed => "RegExp that defines allowed values.",
		dynamic => "May be changed after start.",
		type => "Type of the setting.",
		user => "May be modified by user.",
		novalue => "Option is set to this value if no argument is specified.",
	);

	sub register_settings
	{
		while ( my ($k, $v ) = splice @_, 0, 2 ) {
			die "Setting '$k' is not a HASH\n"
				unless ref $v eq "HASH";
			foreach ( keys %$v ) {
				die "Setting '$k' has unknown option: $_\n"
					unless exists $options{ $_ };
			}

			$registered{ $k } = $v;

			_set( $k, $v->{default}, 10, "default setting" )
				if defined $v->{default};
		}
	}
}


# get value of one macro
sub _get_raw
{
	my $name = shift;
	my $user = shift;

	my $macro = undef;
	if ( $user ) {
		my $mname = "$user:$name";
		$macro = $options{ $mname };
	}
	$macro = $options{ $name }
		unless $macro;

	return $macro;
}

# get and expand one macro
sub get
{
	my $name = shift;
	my $user = shift;
	my $local = shift;

	my $value;
	if ( $local ) {
		$value = $local->{ $name };
	}
	if ( not defined $value ) {
		$value = _get_raw( $name, $user );
	}

	return undef unless defined $value;
	return expand( $value, $user, $local );
}


# expand string containing some macros
sub expand
{
	my $term = shift;
	my $user = shift;
	my $local = shift;

	$term =~ s/%{([a-zA-Z0-9_-]+)}/get( $1, $user, $local )/eg;

	return $term;
}

# interpret string as list and expand each term
sub expand_list
{
	my $term = shift;
	my $user = shift;
	my $local = shift;

	my @list = map {
			expand( $_, $user, $local )
		} split /\s*,\s*/, $term;

	return \@list unless wantarray;
	return @list;
}

# set variable, with all additional information
sub _set_arg
{
	my ( $key, $value, $priority, $origin ) = @_;

	if ( $options{ $key } and $options{ $key }->[2] < $priority ) {
		return;
	}
	$options{ $key } = [ $key, $value, $priority, $origin ];
}

# change variable at runtime, new value will be saved in SQL
sub set
{
	my ( $key, $value, $user ) = @_;

	_set_arg( $key, $value, -1, "changed at runtime; " . localtime )
		or return;
	
	RSGet::SQL::set( "config",
		{ name => $key, user => $user },
		{ value => $value } );
}

sub _init_parse_args
{
	my @args = @_;
	my $argnum = 0;
	my $help;
	while ( my $arg = shift @args ) {
		$argnum++;
		if ( $arg =~ /^-?-h(elp)?$/ ) {
			$help = 1;
		} elsif ( $arg =~ s/^--(.*?)=// ) {
			_set_arg( $1, $arg, 0, "command line, argument $argnum" );
		} elsif ( $arg =~ s/^--// ) {
			my $key = $arg;
			my $var = shift @args;
			die "value missing for '$key'" unless defined $var;
			my $a = $argnum++;
			_set_arg( $key, $var, 0, "command line, argument $a-$argnum" );
		} else {
			_set_arg( "list_file", $arg, 0, "command line, argument $argnum" );
		}
	}
}

sub read_config
{
	my $cfg = shift;
	return unless -r $cfg;

	my $line = 0;
	open my $F_IN, "<", $cfg;
	while ( <$F_IN> ) {
		$line++;
		next if /^\s*(?:#.*)?$/;
		chomp;
		if ( my ( $key, $value ) = /^\s*([a-z_]+)\s*=\s*(.*?)\s*$/ ) {
			$value =~ s/\${([a-zA-Z0-9_]+)}/exists $ENV{$1} ? $ENV{$1} : ""/eg;
			_set_arg( $key, $value, 1, "config file $cfg, line $line" );
			next;
		}
		warn "Incorrect config line: $_\n";
	}
	close $F_IN;
}

sub init
{
	_init_parse_args( @_ );
	_init_parse_config();
	RSGet::SQL::init();
	_init_sql_config();
}

1;

# vim: ts=4:sw=4:fdm=marker
