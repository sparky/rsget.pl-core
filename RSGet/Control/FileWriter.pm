package RSGet::Control::FileWriter;
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

my %files;

sub file_get
{
	my $name = shift;
	my $size = shift;

	my $file = $files{ $name };
	return $file if $file and $file->{size} == $size;

	$file = {
		name => $name,
		size => $size,
		id => $name,
	};

	return $file;
}

sub _file_create
{
	my $name = shift;
	my $size = shift;

	open my $fh, "+>:raw", $name;
	if ( $size > 0 ) {
		seek $fh, $size - 1, SEEK_SET;
		print $fh "\0";
	}

	return $fh;
}

sub _file_open
{
	my $file = shift;
	my $name = $file->{name};

	my $fh;
	if ( -r $name ) {
		open \$fh, "+<:raw", $name;
	} else {
		$fh = _file_create( $name, $file->{size} );
	}

	$file->{handle} = $fh;

	return;
}

sub _file_register
{
	my $file = shift;

	unless ( $file->{users} ) {
		_file_open( $file );
	}

	++$file->{users};
	$files{ $file->{id} } = $file;

	return $file;
}

sub _file_unregister
{
	my $file = shift;

	return if --$file->{users};

	close $file->{handle};
	delete $files{ $file->{id} };

	return;
}

# return new FileWriter
# multiple file-writers can be connected to the same file
# my $fw = new FileWriter $file, $position;
sub new
{
	my $class = shift;
	my $file = shift;
	my $position = shift;

	my $self = {
		file => _file_register( $file ),
		position => $position,
	};

	return bless $self, $class;
}


# add new data to file
sub push
{
	my $self = shift;

	my $fh = $self->{file}->{handle};
	seek $fh, $self->{position}, SEEK_SET;
	print $fh $_[0];

	my $l = length $_[0];
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
