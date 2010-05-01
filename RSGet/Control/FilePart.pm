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

	my $pos = $self->{position};
	my $len = length $_[0];

	my $file = $self->{file};

	# find intersection with existing data
	if ( my ( $ipos, $ilen ) = $file->isdata( $pos, $len ) ) {

		my $data_new = substr $_[0], ($ipos - $pos), $ilen;

		my $data_file;
		seek $fh, $ipos, SEEK_SET;
		read $fh, $data, $ilen;

		if ( $data_new ne $data_file ) {
			# data doesn't match - remove one of those non-matching parts
			# XXX: extract
			#$file->extract();
		}
	}

	my $fh = $self->{file}->{handle};
	seek $fh, $self->{position}, SEEK_SET;
	print $fh $_[0];

	$self->{position} += $l;

	return $l;
}

sub DESTROY
{
	my $self = shift;
	_file_unregister( $self->{file} );
}


1;

# vim: ts=4:sw=4:fdm=marker
