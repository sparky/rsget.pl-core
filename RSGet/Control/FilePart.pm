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
#use File::Copy;
#use File::Path;
use Fcntl qw(SEEK_SET);

# create new file part
sub new
{
	my $class = shift;
	my $file_id = shift;
	my $pos = shift;

}

# get old file part
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
	_file_unregister( $self->{file} );
}


1;

# vim: ts=4:sw=4:fdm=marker
