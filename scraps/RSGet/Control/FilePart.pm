package RSGet::Control::FilePart;
# This file is an integral part of rsget.pl downloader.
#
# 2010 (c) Przemysław Iskra <sparky@pld-linux.org>
#		This program is free software,
# you may distribute it under GPL v2 or newer.

use strict;
use warnings;
#use RSGet::Common;
#use RSGet::SQL;

=head2 sub new

create new file part

=cut
sub new
{
	my $class = shift;
	my $file_id = shift;

	# name of the file
	my $name = shift;

	# total file size (optional?)
	my $size = shift;

	# start position of this part
	my $position = shift;

	# probable end of this part (optional)
	my $probable_stop = shift;

}

=head2 sub old

get old file part

=cut
sub old
{
	my $class = shift;
	my $id = shift;

}


# add new data to file
sub push
{
	my $self = shift;

	return $self->{file}->push( $self, $_[0] );
}

sub DESTROY
{
	my $self = shift;
	$self-{file}->finishpart( $self );
}


1;

# vim: ts=4:sw=4:fdm=marker
