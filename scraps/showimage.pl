#!/usr/bin/perl
#
# 2010 (c) Przemysław Iskra <sparky@pld-linux.org>
#
# In future this code may be used to display captcha images on console.
#
# Requires: 256 color terminal with UTF-8 char coding.
#
use strict;
use warnings;
use GD;
use Term::Size;


my $pimg = GD::Image->newPalette( 4, 4 );
my $index;
sub addc
{
	$index = $pimg->colorAllocate( @_ );
}
sub make_base
{
	foreach my $c ( 0..7 ) {
		addc( ($c & 1 ? 255 : 0), ($c & 2 ? 255 : 0), ($c & 4 ? 255 : 0) );
	}
}

sub make_colors
{
	my @c = map $_ * 51, 0..5;
	foreach my $R ( @c ) {
		foreach my $G ( @c ) {
			foreach my $B ( @c ) {
				addc( $R, $G, $B );
			}
		}
	}
}

sub make_grey
{
	foreach my $G ( map $_ * 11, 0..23 ) {
		addc( $G, $G, $G );
	}
}

make_base();
make_base();
make_colors();
make_grey();
die "Last index must be 255\n" unless $index == 255;

sub rgb
{
	my $img = shift;

	my @rgb = $img->rgb( $img->getPixel( @_ ) );
	return \@rgb;
}

sub avg_rgb_color
{
	my $pix = shift;
	return 0 unless $pix;

	my $r = 0;
	my $g = 0;
	my $b = 0;
	foreach my $c ( @$pix ) {
		$r += $c->[ 0 ];
		$g += $c->[ 1 ];
		$b += $c->[ 2 ];
	}

	my $n = scalar @$pix;
	return $pimg->colorClosest( $r / $n, $g / $n, $b / $n );
}

sub showfile
{
	my $file = shift;
	my $width = shift;
	my $height = 2 * shift;

	print "\n\n$file:\n";
	my $img = GD::Image->new( $file );
	return unless $img;

	my $w = $img->width;
	my $h = $img->height;

	$height = $h if $h < $height;
	$width = $w if $w < $width;
	my $moveh = $height / $h;
	my $movew = $width / $w;

	my @rgb;

	foreach my $y ( 0..($h-1) ) {
		my $outy = int $moveh * $y;
		my $line = $rgb[ $outy ] //= [];
		foreach my $x ( 0..($w-1) ) {
			my $outx = int $movew * $x;
			my $pix = $line->[ $outx ] //= [];
			push @$pix, rgb( $img, $x, $y );
		}
	}

	foreach ( my $y = 0; $y < $height; $y += 2 ) {
		my $line1 = $rgb[ $y ];
		my $line2 = $rgb[ $y + 1 ];
		foreach my $x ( 0..($width-1) ) {
			printf "\033[48;5;%dm\033[38;5;%dm\342\226\205",
				avg_rgb_color( $line1->[ $x ] ),
				avg_rgb_color( $line2->[ $x ] );
		}
		print "\033[0m\n";
	}
}

foreach my $file ( @ARGV ) {
	showfile( $file, Term::Size::chars() );
}
