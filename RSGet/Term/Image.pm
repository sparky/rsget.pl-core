package RSGet::Term::Image;
# This file is an integral part of rsget.pl downloader.
#
# 2010 (c) Przemysław Iskra <sparky@pld-linux.org>
#		This program is free software,
# you may distribute it under GPL v2 or newer.

use strict;
use warnings;
use GD;

=head1 RSGet::Term::Image

This code may be used to display captcha images on console.

Requires: 256 color terminal with UTF-8 char coding.
=cut

# TODO 1: convert encoding to terminal output enc
# TODO 2: consider replacing with some ASCII char if pixel not available
# 	(perhaps ,)
my $charpixel = "\342\226\205";

my @palette;

sub _palette_base
{
	foreach my $c ( 0..7 ) {
		push @palette, [ ($c & 1 ? 255 : 0), ($c & 2 ? 255 : 0), ($c & 4 ? 255 : 0) ];
	}
}

sub _palette_colors
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

sub _palette_grey
{
	foreach my $G ( map $_ * 11, 0..23 ) {
		push @palette, [ $G, $G, $G ];
	}
}

sub _make_palette
{
	@palette = ();
	_palette_base();
	_palette_base();
	_palette_colors();
	_palette_grey();
	die "Last index must be 255\n" unless $#palette == 255;
}

=head2 RSGet::Term::Image::img2lines( DATA, WIDTH, HEIGHT, PRESERVE_ASPECT )

Converts image data to 256-color ANSI lines.

DATA may be a filehandle, file data or a file name (anything GD::Image->new
can handle)

WIDTH and HEIGHT are numeric, to limit maximum output size. Image will be
scaled down if needed, but won't be scaled up.

PRESERVE_ASPECT is a bool, tells to keep image aspect when scaling.

  my ( $w, $h ) = Term::Size::chars();
  my $lines = img2lines( $file, $w, $h, 0 );
  print join "\n", @$lines;
=cut
sub img2lines
{
	my $file = shift;
	my $scrw = shift;
	my $scrh = 2 * shift;
	my $aspect = shift;

	_make_palette() unless @palette;

	my $img = GD::Image->new( $file );
	return unless $img;

	my $width = $img->width;
	my $height = $img->height;

	if ( $aspect ) {
		if ( $width > $scrw ) {
			my $fix = $scrw / $width;
			$width = $scrw;
			$height = int ($img->height * $fix);
			$height++ if $height % 2;
		}
		if ( $height > $scrh ) {
			my $fix = $scrh / $img->height;
			$width = int ( 0.5 + $fix * $img->width );
			$height = $scrh;
		}
	} else{
		$width = $scrw if $width > $scrw;
		$height = $scrh if $height > $scrh;
	}

	my $pimg = GD::Image->newPalette( $width, $height );
	foreach my $c ( @palette ) {
		$pimg->colorAllocate( @$c );
	}

	$pimg->filledRectangle( 0, 0, $width, $height, 7 );
	$pimg->copyResampled( $img, 0, 0, 0, 0, $width, $height,
		$img->width, $img->height );

	my @lines;
	foreach ( my $y = 0; $y < $height; $y += 2 ) {
		my $lastc1 = -1;
		my $lastc2 = -1;
		my $line = "";
		foreach my $x ( 0..($width-1) ) {
			my $c1 = $pimg->getPixel( $x, $y + 0 ) || 0;
			my $c2 = $pimg->getPixel( $x, $y + 1 ) || 0;
			if ( $lastc1 != $c1 ) {
				$lastc1 = $c1;
				$line .= "\033[48;5;${c1}m";
			}
			if ( $c1 == $c2 ) {
				$line .= " ";
			} else {
				if ( $lastc2 != $c2 ) {
					$lastc2 = $c2;
					$line .= "\033[38;5;${c2}m";
				}
				$line .= $charpixel;
			}
		}
		$line .= "\033[0m";
		push @lines, $line;
	}

	return \@lines;
}

1;

# vim: ts=4:sw=4:fdm=marker
