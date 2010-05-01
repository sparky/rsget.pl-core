package RSGet::Control::File;
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
use WeakRef;

my %objs;

# get new file handler
sub new
{
	my $class = shift;
	my $id = shift;

	if ( $objs{ $id } ) {
		return $objs{ $id };
	}

	my $self = _makenew( $id );
	bless $self, $class;

	# save object, but don't count as reference
	weaken( $objs{ $id } = $self );

	return $self;
}

sub DESTROY
{
	my $self = shift;

	close $self->{handle}
		if $self->{handle};

	delete $objs{ $self->{id} };
}

# find best start position
sub startat
{
	my $self = shift;

}

# is there any data at that position
sub isdata
{
	my $self = shift;
	my $pos = shift;
	my $len = shift;

}

# set name and size
# if size differs - fatal error
# if only name differs - warn
# nothing differs - ok
# new data set - ok
sub setinfo
{
	my $self = shift;
	my $name = shift;
	my $size = shift;

}


sub _makenew
{
	my $id = shift;

	my %self;
	my $file_sql = RSGet::SQL::get( "file", { id => $id }, "*" );
	
	$self{ keys %$file_sql } = values %$file_sql;

	return \%self;
}

sub _file_create
{
	my $name = shift;
	my $size = shift;

	open my $fh, "+>:raw", $name;
	if ( $size > 0 ) {
		seek $fh, $size - 1, SEEK_SET;
		print $fh "\0";
		seek $fh, 0, SEEK_SET;
	}

	return $fh;
}

sub _file_open
{
	my $self = shift;
	my $name = $self->{name};

	my $fh;
	if ( -r $name ) {
		open $fh, "+<:raw", $name;
	} else {
		$fh = _file_create( $name, $self->{size} );
	}

	$self->{handle} = $fh;

	return;
}

sub _file_register
{
	my $self = shift;

	unless ( $self->{handle} ) {
		_file_open( $self );
	}

	return $self;
}

sub _file_find
{
	my $self = shift;
	my $inode = (stat $fh)[1];
}


1;

# vim: ts=4:sw=4:fdm=marker
