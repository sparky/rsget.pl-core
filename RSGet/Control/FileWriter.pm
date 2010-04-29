package RSGet::Control::FileWriter;
# This file is an integral part of rsget.pl downloader.
#
# 2010 (c) Przemysław Iskra <sparky@pld-linux.org>
#		This program is free software,
# you may distribute it under GPL v2 or newer.

use strict;
use warnings;
#use RSGet::Common;
use RSGet::SQL;
use File::Copy;
use File::Path;
use Fcntl qw(SEEK_SET);

my %files;

sub file_get
{
	my $name = shift;
	my $size = shift;


}

sub file_create
{
	my $name = shift;
	my $size = shift;

	open my $fh, "+>:raw", $name;
	seek $fh, $size - 1, SEEK_SET;
	print $fh "\0";

	return $fh;
}

sub file_reopen
{
	my $name = shift;
	my $size = shift;

	open my $fh, "+<:raw", $name;
	return $fh;
}

# return new FileWriter
# multiple file-writers can be connected to the same file
# my $fw = new FileWriter $name, $size, $position;
sub new
{
	my $class = shift;
	my $name = shift;
	my $size = shift;
	my $position = shift;
	#my $file = file_get( $name, $size );

	my $self = {
	};

	return bless $self, $class;
}

sub start
{
	my $self = shift;

	open my $handle, "+<:raw", $file_name;
	my $file = {
		handle => $handle,
		users => 1,
		id => $file_name,
	};
	$files{ $file->{id} } = $file;
}

sub seek
{
	my $self = shift;
	$self->{position} = shift;
}

sub push
{
	my $self = shift;

	my $fh = $self->{file}->{handle};
	seek $fh, $self->{position}, SEEK_SET;
	print $fh $_[0];

	$self->{position} += length $_[0];
}

sub end
{
	my $self = shift;

	if ( --$self->{file}->{users} ) {
		return;
	}

	close $self->{file}->{handle};
	delete $files{ $self->{file}->{id} };
}

sub DESTROY
{
	my $self = shift;
	$self->end();
}


1;

# vim: ts=4:sw=4:fdm=marker
