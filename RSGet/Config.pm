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

=head2 cron SUB, PERIOD, [DELAY]

Register a function executed periodically.

 # run at midnight (UTC)
 cron sub { print "It is tomorrow!\n"; }, 24 * 60 * 60;

 # run half past every hour
 cron sub { printf "Half past %d\n", (localtime)[2]; }, 60 * 60, 30 * 60;

=cut
sub cron(&$;$)
{
	#goto &RSGet::Cron::add;
	my $code = shift;
	my $period = shift;
	my $delay = shift || 0;

	warn "Adding $code to cron, run every $period, with $delay delay\n";
}

1;

# vim: ts=4:sw=4:fdm=marker
