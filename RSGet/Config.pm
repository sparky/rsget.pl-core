package RSGet::Config;
# This file is an integral part of rsget.pl downloader.
#
# 2010 (c) Przemysław Iskra <sparky@pld-linux.org>
#		This program is free software,
# you may distribute it under GPL v2 or newer.

use strict;
use warnings;

# options registered with import
our %registered;

# options set in config file
our %values;


=head1 package RSGet::Config

Handles configuration file and option expansion.

=head2 use RSGet::Config LIST;

Register new option:

 use RSGet::Config option_name => "option description",
 		option2_name => "option2 description";

=cut
sub import
{
	my $class = shift;

	my $defined = sprintf "Defined at %s, line %d", (caller)[1, 2];

	while ( my ( $name, $desc, $default ) = splice @_, 0, 3 ) {
		die "use RSGet::Config: option name '$name' is not valid\n"
			unless $name =~ /^[a-z][a-z_]*[a-z]$/;

		die "use RSGet::Config: option '$name' registered already\n"
			if exists $registered{ $name };

		die "use RSGet::Config: option name '$name' cannot be used (it is an internal function)\n"
			if RSGet::Config->can( $name ) or RSGet::Config::File->can( $name );

		$registered{ $name } = [ $default, $desc, $defined ];
	}
}

=head2 load_config_file( DIR );

Load config file named "config" from directory DIR.

 load_config_file( $ENV{HOME} . "/.rsget.pl" );

=cut
sub load_config_file($)
{
	my $dir = shift;

	my $file = $dir . "/config";
	unless ( -r $file ) {
		warn "Config file $file does not exist\n";
		return;
	}

	{
		package RSGet::Config::File;
		require RSGet::Common;
		RSGet::Common->import();
		local $_ = "RSGet::Config::File";
		do $file;

		if ( $@ ) {
			warn "Failed to load '$file': $@\n";
		}
	}
}


=head2 RSGet::Config->OPTION_NAME;

Return value of option named OPTION_NAME.

 my $val = RSGet::Config->something;

If option value is a coderef it will be executed and all arguments will
be passed to that function.

 my $val = RSGet::Config->some_sub( arg1 => 1 );

=cut
our $AUTOLOAD;
sub AUTOLOAD()
{
	my $class = shift;
	( my $name = $AUTOLOAD ) =~ s/.*:://;

	# warn "Requested option $name\n";

	my $val = $RSGet::Config::values{ $name };
	while ( ref $val and ref $val eq "CODE" ) {
		$val = &$val( @_ );
	}
	return $val;
}



package RSGet::Config::File;

=head1 config file context

Functions with special meaning inside config file.

=head2 $_->OPTION_NAME = VALUE;

Set option named OPTION_NAME to VALUE.

 $_->something = 2;
 $_->something = sub { time % 2 };

=cut
our $AUTOLOAD;
sub AUTOLOAD() : lvalue
{
	( my $name = $AUTOLOAD ) =~ s/.*:://;

	#warn "Requested option $name\n";

	$RSGet::Config::values{ $name };
}


=head2 $var = sub_cache { BODY } TIMEOUT, [GLOBALS];

Cache sub output for specified amount of seconds.

Usage:

Instead of writing:
 $myvar = sub { [sub body here] };

You can use:
 $myvar = sub_cache { [sub body here] } $seconds;
 $myvar = sub_cache { [sub body here, uses global variable $global] }
   $seconds, $global;

It can be used if sub call is expensive and you don't need it to be
updated as often as rsget.pl normally does. With sub_cache the body
will be called only if cache expires. Cache is stored separatelly for
each set of global variables. You must specify what global variables
that sub is using, if any.

Warning: it does not check function arguments. If you need argument
checking use Memoize instead.
=cut
sub sub_cache(&$;\$\$\$\$\$\$\$)
{
	my $sub = shift;
	my $timeout = shift;
	my @globals = @_;

	my %lasttime;
	my %cache;
	return sub {
		# stringize globals, let's hope they do it nicely
		my $glob = join "\017", map { $$_ } @globals;

		my $time = time;
		my $lt_min = $time - $timeout;

		# remove all outdated caches
		while ( my ( $g, $lt ) = each %lasttime ) {
			if ( $lt < $lt_min ) {
				delete $lasttime{ $g };
				delete $cache{ $g };
			}
		}

		# return cached value, if there is one
		if ( $lasttime{$glob} ) {
			return $cache{$glob};
		} else {
			# finally, execute and cache
			$lasttime{ $glob } = $time;
			return $cache{ $glob } = &$sub;
		}
	};
}

=head2 $var = by_var $GLOBAL, OPT1 => VAL1, [..., "" => DEFAULT_VAL];

Select returned value based on $GLOBAL variable.

 # set $val to 3 is user is root, 1 otherwise
 $val = by_var $user, root => 3, "" => 1;

=cut
sub by_var(\$@)
{
	my $varref = shift;
	my %opts = @_;

	return sub {
		# force string
		my $var = defined $$varref ? "$$varref" : "";

		return exists $opts{ $var } ? $opts{ $var } : $opts{ "" };
	};
}


=head2 cron SUB, PERIOD, [DELAY]

Register a function executed periodically.

 # run at midnight (UTC)
 cron sub { print "It is tomorrow!\n"; }, 24 * 60 * 60;

 # run half past every hour
 cron { printf "Half past %d\n", (localtime)[2]; } 60 * 60, 30 * 60;

=cut
sub cron(&$;$)
{
	require RSGet::Cron;
	goto &RSGet::Cron::add;
}

1;

# vim: ts=4:sw=4:fdm=marker
