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
	my $dataref = shift;
	
	return undef unless length $$dataref;

	my $pos_stop = $pos_start + length $$dataref;
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
		my $data_new = substr $$dataref, ($cmp_start - $pos_start), $cmp_len;

		# Extract intersection data from file.
		my $data_file;
		seek $fh, $cmp_start, SEEK_SET;
		read $fh, $data_file, $cmp_len;

		# If data matches then it's all ok.
		next if $data_new eq $data_file;

		push @nomatch_part, $part;
	}

	return \@nomatch_parts;
}

=head2 sub _nomatch_dbchunks

return all parts that have data at that position, but it does not match.

In ideal situation should always return empty list;

=cut
sub _nomatch_dbchunks
{
	my $self = shift;
	my $pos_start = shift;
	my $dataref = shift;
	
	return undef unless length $$dataref;

	my $pos_stop = $pos_start + length $$dataref;
	my %nomatch_parts;

	my $sth = RSGet::SQL::prepare(
		"SELECT start, stop, file_part_id, file_id, data " .
		"FROM file_part_chunk, file_part " .
		"WHERE file_part_chunk.file_part_id = file_part.id AND file_part.file_id = ? " .
		"AND file_part_chunk.start < ? AND file_part_chunk.stop > ?"
	);
	$sth->execute( $self->{id}, $pos_stop, $pos_start );

	# If there is some data at that position already make sure it matches.
	foreach my $chunk ( $sth->fetchrow_hashref() ) {

		# Check whether this part and new data intersects.
		# There is '=' in comparisions because without it intersection
		# length could be 0. It would detect itself.
		next if $chunk->{start} >= $pos_stop;
		next if $chunk->{stop} <= $pos_start;

		# Boundries of the intersection.
		my $cmp_start = max $pos_start, $chunk->{start};
		my $cmp_stop = min $pos_stop, $chunk->{stop};
		my $cml_len = $cmp_stop - $cmp_start;

		# Extract intersection data from new data.
		my $data_new = substr $$dataref,
			($cmp_start - $pos_start), $cmp_len;

		# Extract chunk of data chunk
		my $data_chunk = substr $chunk->{data},
			($chunk->{start} - $pos_start), $cmp_len;

		# If data matches then it's all ok.
		next if $data_new eq $data_chunk;

		$nomatch_part{ $chunk->{file_part_id} } = 1;
	}
	$sth->finish();

	return keys %nomatch_parts;
}


sub push
{
	my $self = shift;
	my $part = shift;
	my $dataref = shift;
	my $pos_start = $part->{start};

	my $fh = $self->{handle};

	# dump to database if we can't write to file
	if ( not $fh or $self->{shunt} ) {
		return $self->dbdump( $part, $dataref );
	}

	if ( my $nomatch_parts = $self->_nomatch_parts( $pos_start, $dataref ) ) {
		# there was error, start dumping everything to database
		$self->{shunt} = 1;

		my $stop = $self->dbdump( $part, $dataref );

		# start fixer process
		$self->fixer( 
			failed => $part,
			nomatch => $nomatch_parts,
		);

		return $stop;
	}

	# now that we can, write new data to file
	seek $fh, $pos_start, SEEK_SET;
	print $fh $$dataref;

	return $part->{start} = $pos_start + length $$dataref;
}

sub dbdump
{
	my $self = shift;
	my $part = shift;
	my $dataref = shift;
	my $pos_start = $part->{start};
	my $pos_stop = $part->{start} = $pos_start + length $$dataref;

	my $sth = RSGet::SQL::prepare(
		"INSERT INTO ${RSGet::SQL::prefix}file_part_chunk" .
		"(file_part_id, start, stop, data) " .
		"VALUES(?, ?, ?, ?)"
	);
	$sth->execute( $part->{id}, $pos_start, $pos_stop, $$dataref );
	$sth->finish();

	return $pos_stop;
}

sub fixer
{
	my $self = shift;
	my %info = @_;

	# XXX: unimplemented
	#
	# 1. prevent this process from doing anything to the file
	# 2. start fixer process which will do what should be done
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
