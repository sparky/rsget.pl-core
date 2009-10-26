package RSGet::Line;
# This file is an integral part of rsget.pl downloader.
#
# 2009 (c) Przemysław Iskra <sparky@pld-linux.org>
#		This program is free software,
# you may distribute it under GPL v2 or newer.

use strict;
use warnings;
use RSGet::Tools;
use Term::Size;
set_rev qq$Id$;

our %active;
my %dead;
our @dead;
our $dead_change = 0;
our %status;
my $last_line = 0;

my $last_day = -1;
sub print_dead_lines
{
	my @l = localtime;
	my $time = sprintf "[%.2d:%.2d:%.2d] ", @l[(2,1,0)];

	my @print;
	my @newdead;

	if ( $last_day != $l[3] ) {
		$last_day = $l[3];
		my $date = sprintf "[Actual date: %d-%.2d-%.2d]", $l[5] + 1900, $l[4] + 1, $l[3];
		push @print, "\r" . $date . "\033[J\n";
		push @newdead, $date;
	}

	foreach my $key ( sort { $a <=> $b } keys %dead ) {
		my $text = $dead{$key};
		$text = $time . $text if $text =~ /\S/;

		push @print, "\r" . $text . "\033[J\n";
		push @newdead, $text;
	}

	print @print;
	if ( @newdead ) {
		push @dead, @newdead;
		$dead_change++;

		my $max = 1000;
		if ( scalar @dead > $max ) {
			splice @dead, 0, $max - scalar @dead;
		}
	}

	%dead = ();
}

sub print_status_lines
{
    my $columns = shift();
	my $horiz = "-" x ($columns - 4);

	my $date = "< ".isotime()." >";
	my $date_l = length $date;
	my $h = $horiz;
	substr $h, int( (length($horiz) - $date_l ) / 2 ), $date_l, $date;

	my @status = ( "rsget.pl -- " );
	foreach my $name ( sort keys %status ) {
		my $value = $status{$name};
		next unless $value;
		my $s = "$name: $value; ";
		if ( length $status[ $#status ] . $s > $columns - 5 ) {
			push @status, $s;
		} else {
			$status[ $#status ] .= $s;
		}
	}
	my @print = ( " \\$h/ " );
	foreach ( @status ) {
		my $l = " |" . ( " " x ($columns - 4 - length $_ )) . $_ . "| ";
		push @print, $l;
	}
	push @print, " /$horiz\\ ";
	print map { "\r\n$_\033[K" } @print;
	return scalar @print;
}


sub print_active_lines
{
    my $columns = shift;
	my @print;

	foreach my $key ( sort { $a <=> $b } keys %active ) {
		my $line = $active{$key};

		my $text = $line->[1];
		my $tl = length $line->[0] . $text;
		substr $text, 4, $tl - $columns + 3, '...'
			if $tl > $columns;
		push @print, "\r\n\033[K" . $line->[0] . $text;
	}

	print @print;
	return scalar @print;
}

sub print_all_lines
{
	my ( $columns, $rows ) = Term::Size::chars;
	my $added = 0;
	print_dead_lines();
	$added += print_status_lines( $columns );
	$added += print_active_lines( $columns );
	return $added;
}

sub update
{
	my $added = print_all_lines();
	print "\033[J\033[" . $added . "A\r" if $added;
}

sub new
{
    my $class = shift;
	my $head = shift;
	my $text = shift;
	my $assoc = shift;
	$head = "" unless defined $head;

	my $line = "" . ($last_line++);
	$active{ $line } = [ $head, "", $assoc ];

	my $self = \$line;
	bless $self, $class;
	$self->print( $text );

	return $self;
}

sub print
{
	my $self = shift;
	my $line = $$self;
	my $text = shift;
	$text = "" unless defined $text;
	$text =~ s/\n+$//sg;
	$text =~ s/\n/ /sg;
	$text =~ s/\0/***/g;
	$active{ $line }->[1] = $text;

	return length $text;
}

sub linedata
{
	my $self = shift;
	my $data = shift;
	$active{ $$self }->[2] = $data;
}


sub DESTROY
{
	my $self = shift;
	my $line = $$self;
	my $l = $active{ $line };
	$dead{ $line } = $l->[0] . $l->[1];
	delete $active{ $line };
}

sub status
{
	hadd( \%status, @_ );
}

sub init
{
	$| = 1;

	$SIG{INT} = sub {
		print_all_lines();
		print "\nTERMINATED\n";
		exit 0;
	};

	$SIG{WINCH} = sub {
		print "\033[2J\033[1;1H\n";
		my ( $columns, $rows ) = Term::Size::chars;
		my $start = $#dead - $rows;
		$start = 0 if $start < 0;
		print join( "\n", @dead[($start..$#dead)] ), "\n";
		update();
	};

	$SIG{__WARN__} = sub {
		new RSGet::Line( "WARNING: ", shift );
		update();
	};

	$SIG{__DIE__} = sub {
		print_all_lines();
		print "\n";
		print "DIED: ", shift, "\n\n";
		exit 1;
	};
}

1;

# vim: ts=4:sw=4
