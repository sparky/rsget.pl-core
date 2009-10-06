package RSGet::Tools;

use strict;
use warnings;
use vars qw(@ISA @EXPORT @EXPORT_OK);

require Exporter;
@ISA = qw(Exporter);
@EXPORT = qw(set_rev s2string bignum de_ml hadd hprint p isotime require_prog
	jstime def_settings setting verbose
	data_file dump_to_file randomize %getters);
@EXPORT_OK = qw();

our %getters;
our %revisions;

sub set_rev($)
{
	my @id = split /\s+/, shift;
	my $pm = $id[1];
	my $rev = $id[2];
	$pm =~ s/\.pm$//;
	$revisions{ $pm } = 0 | $rev;
}
set_rev qq$Id$;

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

sub bignum($)
{
	local $_ = shift;
	return $_ if /[^\d]/;
	s/(..?.?)(?=(...)+$)/$1_/g;
	return $_;
}

sub hadd(%@)
{
	my $h = shift;
	my %new = @_;
	foreach ( keys %new ) {
		$h->{$_} = $new{$_};
	}
}


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

sub randomize
{
	# not really good, but works
	return sort { 0.5 <=> rand } @_;
}


sub isotime()
{
	my @l = localtime;
	return sprintf "%d-%.2d-%.2d %2d:%.2d:%.2d", $l[5] + 1900, $l[4] + 1, @l[(3,2,1,0)];
}

sub jstime()
{
	return time * 1000 + int rand 1000;
}

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

sub require_prog
{
	my $prog = shift;
	foreach my $dir ( split /:+/, $ENV{PATH} ) {
		my $full = "$dir/$prog";
		return $full if -x $full;
	}
	return undef;
}

sub data_file
{
	my $file = shift;
	my $f = "$main::local_path/data/$file";
	return $f if -r $f;
	$f = "$main::install_path/data/$file";
	return $f if -r $f;
	return undef;
}

sub def_settings
{
	my %s = @_;
	foreach my $k ( keys %s ) {
		my $v = $s{ $k };
		die "Incorrect setting '$k' declaration\n"
			if ref $v ne "ARRAY" or scalar @$v != 3;
		$main::def_settings{ $k } = $v;
	}
}

sub setting
{
	my $name = shift;
	die "Setting '$name' is not defined\n" unless exists $main::def_settings{ $name };
	return $main::settings{ $name }->[0] if exists $main::settings{ $name };
	return $main::def_settings{ $name }->[1];
}

sub verbose
{
	my $min = shift;
	return 1 if setting( "verbose" ) >= $min;
	return 0;
}

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

1;
# vim:ts=4:sw=4
