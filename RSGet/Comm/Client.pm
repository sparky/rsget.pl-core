package RSGet::Comm::Client;
# This file is an integral part of rsget.pl downloader.
#
# 2010 (c) Przemysław Iskra <sparky@pld-linux.org>
#		This program is free software,
# you may distribute it under GPL v2 or newer.

use strict;
use warnings;
use parent qw(RSGet::Comm::PerlData);

=head1 RSGet::Comm::Client

Functions for authenticating clients and communication.

=cut

sub new
{
	my $class = shift;

	my $self = new RSGet::Comm::PerlData;

	return bless $self, $class;
}

sub process
{
	my $self = shift;
	my $o = shift;

	# TODO:
	# that's all we've got so far
	use Data::Dumper;
	print Dumper( $o );

	return $o;
}

1;

# vim: ts=4:sw=4:fdm=marker
