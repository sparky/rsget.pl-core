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

my @palette;
sub make_base
{
	foreach my $c ( 0..7 ) {
		push @palette, [ ($c & 1 ? 255 : 0), ($c & 2 ? 255 : 0), ($c & 4 ? 255 : 0) ];
	}
}

sub make_colors
{
	my @c = map $_ * 51, 0..5;
	foreach my $R ( @c ) {
		foreach my $G ( @c ) {
			foreach my $B ( @c ) {
				push @palette, [ $R, $G, $B ];
			}
		}
	}
}

sub make_grey
{
	foreach my $G ( map $_ * 11, 0..23 ) {
		push @palette, [ $G, $G, $G ];
	}
}

make_base();
make_base();
make_colors();
make_grey();
die "Last index must be 255\n" unless $#palette == 255;

sub showfile
{
	my $file = shift;
	my $width = shift;
	my $height = 2 * shift;
	$height-=4;

	my $img = GD::Image->new( $file );
	return unless $img;

	my $w = $img->width;
	my $h = $img->height;

	$height = $h if $h < $height;
	$width = $w if $w < $width;

	my $pimg = GD::Image->newPalette( $width, $height );
	foreach my $c ( @palette ) {
		$pimg->colorAllocate( @$c );
	}

	$pimg->filledRectangle( 0, 0, $width, $height, 7 );
	$pimg->copyResampled( $img, 0, 0, 0, 0, $width, $height, $w, $h );

	my $print = "\033[0;0f$file:\033[0K\n";
	foreach ( my $y = 0; $y < $height; $y += 2 ) {
		my $lastc1 = -1;
		my $lastc2 = -1;
		foreach my $x ( 0..($width-1) ) {
			my $c1 = $pimg->getPixel( $x, $y + 0 ) || 0;
			my $c2 = $pimg->getPixel( $x, $y + 1 ) || 0;
			if ( $lastc1 != $c1 ) {
				$lastc1 = $c1;
				$print .= "\033[48;5;${c1}m";
			}
			if ( $c1 == $c2 ) {
				$print .= " ";
			} else {
				if ( $lastc2 != $c2 ) {
					$lastc2 = $c2;
					$print .= "\033[38;5;${c2}m";
				}
				$print .= "\342\226\205";
			}
		}
		$print .= "\033[0m\033[0K\n";
	}
	chop $print;
	$print .= "\033[0J\n";
	print $print;
}

foreach my $file ( @ARGV ) {
	showfile( $file, Term::Size::chars() );

	sleep 1;
}
