#!/usr/bin/perl
#
use RSGet::IO;

my @send = (
	"one",
	"two\n",
	"three\nfour",
	"\nfive\nsix\nseven",
	"\n",
	"\n",
	".",
	".",
	".",
	"\n",
	"end"
);

pipe my $RH, my $WH;
my $rh = RSGet::IO->new( $RH );

sub rdata
{
	for (;;) {
		my $line;
		eval {
			$line = $rh->readline();
		};
		if ( $@ ) {
			warn "readline() $@\n";
			return;
		}

		if ( defined $line ) {
			print "LINE: [$line]\n";
		} else {
			print "NO DATA !\n";
			return;
		}
	}
}

foreach my $line ( @send ) {
	rdata();

	$WH->print( $line );
	$WH->flush();
}

rdata();

print "close WH\n";
close $WH;

rdata();

print "close RH\n";
close $RH;

rdata();

# vim: ts=4:sw=4
