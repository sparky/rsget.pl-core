package RSGet::Common;
# This file is an integral part of rsget.pl downloader.
#
# 2009-2010 (c) Przemysław Iskra <sparky@pld-linux.org>
#		This program is free software,
# you may distribute it under GPL v2 or newer.

use strict;
use warnings;
use vars qw(@ISA @EXPORT @EXPORT_OK);

require Exporter;
@ISA = qw(Exporter);
@EXPORT = qw($user
	cat
	s2string bignum de_ml hadd hprint p isotime require_prog
	irand randid jstime def_settings setting verbose
	data_file dump_to_file randomize);
@EXPORT_OK = qw();

# user that is actually downloading
our $user;

# return number of seconds as string
sub s2string($)
{
	my $s = shift;
	my $minutes = int( $s / 60 );
	my $seconds = $s % 60;

	if ( $minutes >= 60 ) {
		my $hours = int( $minutes / 60 );
		$minutes %= 60;
		return sprintf '%d:%.2d:%.2d', $hours, $minutes, $seconds;
	} else {
		return sprintf '%d:%.2d', $minutes, $seconds;
	}
}

# return NNNNNNNN number as NN_NNN_NNN
sub bignum($)
{
	local $_ = shift;
	return $_ if /[^\d]/;
	s/(..?.?)(?=(...)+$)/$1_/g;
	return $_;
}

# add new values to hash
sub hadd(%@)
{
	my $h = shift;
	my %new = @_;
	$h->{ keys %new } = values %new;
}

# XXX: rewrite
sub p($)
{
	require RSGet::Line;
	new RSGet::Line( "INFO: ", shift );
}

sub hprint(%)
{
	my $h = shift;
	foreach my $k ( keys %$h ) {
		my $v = $h->{ $k };
		if ( not defined $v ) {
			$v = "undef";
		} elsif ( $v =~ /^\d+$/ ) {
		} else {
			$v = '"' . $v . '"';
		}
		p "$k => $v";
	}
}

# randomize order of an array
sub randomize
{
	# not really good, but works
	# violates qsort requirements for stable comparator
	return sort { 0.5 <=> rand } @_;
}

# return some random integer from interval $_[0]..$_[1]
# or 0..$_[0] if there is no $_[1]
sub irand($;$)
{
	my $arg = shift;
	return int rand $arg unless @_;

	return int ( $arg + rand ( (shift) - $arg ) );
}

# random 16 byte hex number
sub randid()
{
	return join "", map { sprintf "%.4x", int rand 1 << 16 } (0..7);
}

# actual date and time in iso format (YYYY-MM-DD HH:MM:SS)
sub isotime()
{
	my @l = localtime;
	return sprintf "%d-%.2d-%.2d %2d:%.2d:%.2d", $l[5] + 1900, $l[4] + 1, @l[(3,2,1,0)];
}

# actual time in JavaScript format
sub jstime()
{
	return time * 1000 + irand 1000;
}

# remove sgml entities
sub de_ml
{
	local $_ = shift;
	s/&le;/</g;
	s/&ge;/>/g;
	s/&quot;/"/g;
	s/&#(\d+);/chr $1/eg;
	s/&amp;/&/g;
	return $_;
}

# find program in $PATH
sub require_prog
{
	my $prog = shift;
	foreach my $dir ( split /:+/, $ENV{PATH} ) {
		my $full = "$dir/$prog";
		return $full if -x $full;
	}
	return undef;
}

# XXX: likely depreciated
sub data_file
{
	my $file = shift;
	my $f = "$main::local_path/data/$file";
	return $f if -r $f;
	$f = "$main::install_path/data/$file";
	return $f if -r $f;
	return undef;
}

# add settings to default hash
sub def_settings
{
	my %s = @_;
	my %options = (
		desc => "Setting description.",
		default => "Default value.",
		allowed => "RegExp that defines allowed values.",
		dynamic => "May be changed after start.",
		type => "Type of the setting.",
		user => "May be modified by user.",
	);
	foreach my $k ( keys %s ) {
		my $v = $s{ $k };
		if ( ref $v ne "HASH" ) {
			die "Setting '$k' is not a HASH\n";
		}
		if ( not $v->{desc} ) {
			die "Setting '$k' is missing description\n";
		}
		foreach ( keys %$v ) {
			die "Setting '$k' has unknown option: $_\n"
				unless exists $options{ $_ };
		}
		$main::def_settings{ $k } = $v;
	}
}

# retrieve global setting
sub setting
{
	my $name = shift;
	die "Setting '$name' is not defined\n" unless exists $main::def_settings{ $name };
	return $main::settings{ $name }->[0] if exists $main::settings{ $name };
	return $main::def_settings{ $name }->{default};
}

# indicate wether additional information should be printed
sub verbose
{
	my $min = shift;
	return 1 if setting( "debug" );
	return 1 if setting( "verbose" ) >= $min;
	return 0;
}

# XXX: dump to database instead
sub dump_to_file
{
	my $data = shift;
	my $ext = shift || "txt";
	my $i = 0;
	my $file;
	do {
		$i++;
		$file = "dump.$i.$ext";
	} while ( -e $file );

	open my $f_out, '>', $file;
	print $f_out $data;
	close $f_out;

	warn "data dumped to file: $file\n";
}


# return contents of given file
sub cat
{
	my $name = shift;
	open my $fin, "<", $name
		or return undef;

	local $/ = undef;
	return <$fin>;
}

1;

# vim: ts=4:sw=4:fdm=marker
