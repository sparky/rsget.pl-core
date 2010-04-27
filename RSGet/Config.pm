package RSGet::Config;
# This file is an integral part of rsget.pl downloader.
#
# 2010 (c) Przemysław Iskra <sparky@pld-linux.org>
#		This program is free software,
# you may distribute it under GPL v2 or newer.

use strict;
use warnings;

RSGet::Config::register_settings(
	core_config_dir => {
		desc => "Main config directory.",
		default => "$ENV{HOME}/.rsget.pl",
	},
	core_config_file => {
		desc => "Main config file.",
		default => "%{core_config_dir}/config",
	},
	# escape secuences
	p => {
		default => "%",
	},
	s => {
		default => "\$",
	},
	n => {
		default => "\n",
	},
	nil => {
		default => "",
	},
);

# initalized ?
my $init = 0;

# registered settings
my %registered;

# most actual options possible
my %options;

use constant {
	OPT_USER	=> 0,
	OPT_KEY		=> 1,
	OPT_VALUE	=> 2,
	OPT_PRIO	=> 3,
	OPT_ORIGIN	=> 4,
};

# prioroty (from highest to lowest)
use constant {
	PRIO_RUNTIME	=> 0,	# runtime changed
	PRIO_ARGS		=> 1,	# commandline arguments
	PRIO_DYNAMIC	=> 2,	# dynamic config
	PRIO_STATIC		=> 3,	# static config file
	PRIO_DEFAULT	=> 4,	# default value
};

# {{{ sub register_settings: add settings to register hash
use constant _regdata => {
	desc	=> "Setting description.",
	default	=> "Default value.",
	allowed	=> "RegExp that defines allowed values.",
	dynamic	=> "May be changed after start.",
	type	=> "Type of the setting.",
	user	=> "May be modified by user.",
	novalue	=> "Option is set to this value if no argument is specified.",
};

sub register_settings
{
	while ( my ($k, $v) = splice @_, 0, 2 ) {
		die "Setting for '$k' is not a HASH\n"
			unless ref $v eq "HASH";
		foreach ( keys %$v ) {
			die "Setting '$k' has unknown option: $_\n"
				unless exists _regdata->{ $_ };
		}

		$registered{ $k } = $v;

		_set( undef, $k, $v->{default}, PRIO_DEFAULT,
			"default setting" );
	}
}
# }}}

# {{{ sub reqister_dynaconfig: register object used to read and write config
# $dynaconfig object must have 2 methods:
#	->set( $user, $key, $value );
#	->getall();
my $dynaconfig;
sub reqister_dynaconfig
{
	$dynaconfig = shift;
	_init_dynaconfig()
		if $init;
}
# }}}

# {{{ sub get: get and expand one macro
sub get
{
	my $user = shift;
	my $key = shift;
	my $local = shift;

	my $value;
	if ( $local ) {
		$value = $local->{ $key };
	}
	if ( not defined $value ) {
		my $macro = undef;
		if ( $user ) {
			my $ukey = $user . ":" . $key;
			$macro = $options{ $ukey };
		}
		$macro = $options{ $key }
			unless $macro;
	
		$value = $macro->[OPT_VALUE];
	}

	return undef unless defined $value;
	return expand( $user, $value, $local );
}
# }}}

# {{{ sub expand: expand string containing some macros
sub _expand_exec
{
	my $type = shift;
	my $user = shift;
	my $term = shift;
	my $local = shift;

	if ( $user ) {
		warn "Users are not permited to execute code.\n";
		return "";
	}
	$term = expand( $user, $term, $local );
	if ( $type eq "%" ) {
		warn "Executing perl '$term'.\n";
		my $ret = eval $term;
		warn "Failed: $@"
			if $@;
		$ret = "" unless defined $ret;
		return $ret;
	} elsif ( $type eq "\$" ) {
		warn "Executing command '$term'.\n";
		open my $read, $term ." |";
		my $value = "";
		while ( <$read> ) {
			$value .= $_;
		}
		close $read;
		chomp $value;
		warn "Failed: $?"
			if $?;
		return $value;
	} else {
		die "_expand_exec type is '$type'.\n";
	}

}

sub _expand_term
{
	my $type = shift;
	if ( $type eq "%" ) {
		goto &get;
	} elsif ( $type eq "\$" ) {
		my $user = shift;
		my $term = shift;
		my $local = shift;
		return expand( $user, $ENV{ $term }, $local )
			if exists $ENV{ $term };
		warn "Environment variable $term is not set.\n";
		return "";
	} else {
		die "_expand_term type is '$type'.\n";
	}
}

sub expand
{
	my $user = shift;
	my $term = shift;
	my $local = shift;

	$term =~ s/([%\$])\((.*?)\)/_expand_exec( $1, $user, $2, $local )/eg;
	$term =~ s/([%\$]){([a-zA-Z0-9_]+)}/_expand_term( $1, $user, $2, $local )/eg;

	return $term;
}
# }}}

# {{{ sub expand_list: interpret string as list and expand each term
sub expand_list
{
	my $term = shift;
	my $user = shift;
	my $local = shift;

	my @list = map {
			expand( $user, $_, $local )
		} split /\s*,\s*/, $term;

	return \@list unless wantarray;
	return @list;
}
# }}}

# {{{ sub _set: set variable, with all additional information
sub _set
{
	my ( $user, $key, $value, $priority, $origin ) = @_;

	my $reg = $registered{ $key };

	# set only if priority is same or higher
	if ( $options{ $key } and $options{ $key }->[OPT_PRIO] < $priority ) {
		return;
	}

	# those may someday become keywords
	if ( not $reg and not $key =~ m/^_/ ) {
		warn "Configuration option $key is not registered."
			. " Prefix your own variables with _.\n";
	}

	if ( $user and $reg and not $reg->{user} ) {
		die "Configuration option $key may not be changed for user.\n";
	}

	$options{ $key } = [ $user, $key, $value, $priority, $origin ];

	return 1;
}
# }}}

# {{{ sub set: change variable at runtime, new value will be saved in SQL
sub set
{
	my ( $user, $key, $value ) = @_;

	_set( $user, $key, $value, PRIO_RUNTIME,
		"changed at runtime; " . localtime )
			or return;
	
	unless ( $dynaconfig ) {
		warn "dynaconfig not registered, cannot save configuration\n";
		return;
	}

	$dynaconfig->set( $user, $key, $value );
}
# }}}

# {{{ sub _init_parse_args
sub _init_parse_args
{
	while ( my $arg = shift @_ ) {
		my ( $key, $value, $origin ) = @$arg;
		my $user = ( $key =~ s/^(\S+?):// );
		$key =~ tr/-/_/;

		_set( $user, $key, $value, PRIO_ARGS, $origin );
	}
}
# }}}

sub _read_config # {{{
{
	my $file = shift;
	die "Config file $file is not readable.\n" unless -r $file;

	my $line = 0;
	open my $F_IN, "<", $file;
	while ( <$F_IN> ) {
		$line++;

		# remove useless lines
		next if /^\s*(?:#.*)?$/;
		chomp;

		# starts with expand ?
		my $expand = 0;
		$expand = 1 if s/^\s*expand\s+//;

		if ( my ( $key, $value ) = /^\s*(\S+)\s*=\s*(.*?)\s*$/ ) {
			# set variable
			my $user = ( $key =~ s/^(\S+):// );
			$value = expand( undef, $value )
				if $expand;

			_set( $user, $key, $value, 	PRIO_STATIC,
				"config file $file, line $line" );

			next;
		} elsif ( /^include\s*(.*?)\s*$/ ) {
			# include another file
			my $file = $1;
			$file = expand( undef, $file )
				if $expand;

			# if file doesn't start with / prepend %{config_dir}
			unless ( $file =~ m#^/# ) {
				$file = RSGet::Config::get( undef, "core_config_dir" )
					. "/" . $file;
			}

			# let's do it, will die if file does not exist
			_read_config( $file );

			next;
		}
		warn "$file: Incorrect config line: $_\n";
	}
	close $F_IN;
}
# }}}

sub _init_parse_config # {{{
{
	my $file = RSGet::Config::get( undef, "core_config_file" );
	if ( -r $file ) {
		_read_config( $file );
	} else {
		warn "Config file $file is not readable.\n";
		return;
	}
}
# }}}

sub _init_dynaconfig # {{{
{
	my $all = $dynaconfig->getall();

	foreach my $conf ( @$all ) {
		# $conf -> $user, $key, $value, $origin
		my @conf = @$conf;
		splice @conf, OPT_PRIO, 0, PRIO_DYNAMIC; # set priority to 1
		_set( @conf );
	}
} # }}}

sub init # {{{
{
	return if $init;
	_init_parse_args( @_ );
	_init_parse_config();
	_init_dynaconfig()
		if $dynaconfig;
	$init = 1;
} # }}}

1;

# vim: ts=4:sw=4:fdm=marker
