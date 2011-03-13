#!/usr/bin/perl
#

while ( <> ) {
	if ( /^use\s+(\S+)\s*\(\);/ ) {
		print "#$_";
		eval "require $1;";
		die "require failed: $@\n"
			if $@;
		next;
	}
	if ( /^use\s+constant\s+{/ .. /};/ ) {
		if ( /=>\s*(\S+),/ ) {
			my $cnt = $1;
			my $val;
			eval '$val = ' . $cnt;
			die "constant failed: $@\n"
				if $@;
			s/=>\s*\S+,/=> ($val),/;
		}
	}
	print $_;
}

