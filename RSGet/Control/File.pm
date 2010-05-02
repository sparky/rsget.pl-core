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
use Scalar::Util qw(max min weaken);

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

=head2 sub _nomatch_parts

return all parts that have data at that position, but it does not match.

In ideal situation should always return empty list;

=cut
sub _nomatch_parts
{
	my $self = shift;
	my $pos_start = shift;
	# data at $_[0]
	
	return () unless length $_[0];

	my $pos_stop = $pos_start + length $_[0];
	my $fh = $self->{handle};
	my @nomatch_parts;

	# If there is some data at that position already make sure it matches.
	foreach my $part ( @{ $self->{parts} } ) {

		# Check whether this part and new data intersects.
		# There is '=' in comparisions because without it intersection
		# length could be 0. It would detect itself.
		next if $part->{start} >= $pos_stop;
		next if $part->{stop} <= $pos_start;

		# Boundries of the intersection.
		my $cmp_start = max $pos_start, $part->{start};
		my $cmp_stop = min $pos_stop, $part->{stop};
		my $cml_len = $cmp_stop - $cmp_start;

		# Extract intersection data from new data.
		my $data_new = substr $_[0], ($cmp_start - $pos_start), $cmp_len;

		# Extract intersection data from file.
		my $data_file;
		seek $fh, $cmp_start, SEEK_SET;
		read $fh, $data_file, $cmp_len;

		# If data matches then it's all ok.
		next if $data_new eq $data_file;

		push @nomatch_part, $part;
	}

	return @nomatch_parts;
}

sub pushdata
{
	my $self = shift;
	my $part = shift;
	my $pos_start = $part->{start};
	#my $data = shift;

	if ( my @nomatch_parts = $self->_nomatch_parts( $pos_start, $_[0] ) ) {
		my $extract_old = 1;
		$extract_old = 0 if scalar @nomatch_parts > 1;

		if ( $extract_old ) {
			my @active = grep { $_->{active} } @nomatch_parts;
			$extract_old = 0 if @active;
		}

		# XXX: extraction can take a lot of time, must think up some way
		# to do it asynchronously
		if ( $extract_old ) {
			# extract old parts (saving to new file)
			# later will continue saving in this file
			#XXX
		} else {
			# extract this part to new file and continue saving there
			#XXX
			$self = newfile();
		}
	}

	# now that we can, write new data to file
	my $fh = $self->{handle};
	seek $fh, $pos_start, SEEK_SET;
	print $fh $_[0];

	return $part->{start} = $pos_start + length $_[0];
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
	my $inode = (lstat $fh)[1];
}


1;

# vim: ts=4:sw=4:fdm=marker
