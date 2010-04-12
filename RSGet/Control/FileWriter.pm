package RSGet::FileWriter;
# This file is an integral part of rsget.pl downloader.
#
# 2010 (c) Przemysław Iskra <sparky@pld-linux.org>
#		This program is free software,
# you may distribute it under GPL v2 or newer.

use strict;
use warnings;
use RSGet::Common;
use RSGet::DB;
use File::Copy;
use File::Path;
use Fcntl qw(SEEK_SET);

my %files;

sub new
{
	my $class = shift;

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
