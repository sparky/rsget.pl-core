package RSGet::Processor;

use strict;
use warnings;
use RSGet::Tools;
set_rev qq$Id$;

my $options = "name|short|slots|cookie|status|min_ver";

my $processed = "";
sub pr(@)
{
	my $line = join "", @_;
	$processed .= $line;
	return length $line;
}

my $is_sub = 0;
my $last_cmd = undef;
sub p_sub
{
	my $sub = shift;
	pr "sub $sub {\n";
	pr "\tmy \$self = shift;\n";
	foreach ( @_ ) {
		pr "\t$_;\n";
	}
	$is_sub++;
}
sub p_subend
{
	return unless $is_sub;
	$is_sub--;

	my $error = 'unexpected end of script';
	if ( $last_cmd and $last_cmd eq "download" ) {
		$error = 'download is a HTML page';
	}
	$last_cmd = undef;
	pr "\treturn \${self}->error( '$error' );\n}\n";
}

my $space;
sub p_ret
{
	my $ret = shift;
	my @opts = @_;
	pr $space . "return \${self}->${ret}( ";
	pr join( ", ", @opts ) . ", " if @opts;
}

sub p_func
{
	my $f = shift;
	pr $space . "\${self}->$f(";
}

sub p_line
{
	s/\$-{/\$self->{/g;
	pr $_ . "\n";
}


sub read_file
{
	my $class = shift;
	my $file = shift;

	open F_IN, '<', $file;

	my %opts = (
		uri => [],
	);
	my %parts = (
		unify => [],
		pre => [],
		start => [],
		perl => [],
	);
	my $parts = join "|", keys %parts;

	my $part = undef;
	while ( <F_IN> ) {
		chomp;
		next unless length;
		next if /^\s*#/;

		if ( $part ) {
			unless ( /^\S+/ ) {
				push @{$parts{$part}}, $_;
				next;
			}
			if ( $part eq "perl" ) {
				push @{$parts{perl}}, $_, <F_IN>;
				last;
			} elsif ( $part eq "start" and /^stage_.*?:/ ) {
				push @{$parts{start}}, $_;
				next;
			}
			$part = undef;
		}

		if ( /^($parts)\s*:/ ) {
			$part = $1;
		} elsif ( /^uri\s*:\s+(.*)$/ ) {
			push @{$opts{uri}}, $1;
		} elsif ( /^($options)\s*:\s+(.*)$/ ) {
			$opts{$1} = $2;
		}
	}

	close F_IN;
	unless ( scalar @{$parts{start}} ) {
		p "Can't find 'start:'\n";
		return undef;
	}
	unless ( @{$opts{uri}} ) {
		p "Can't find 'uri:'\n";
		return undef;
	}
	foreach ( qw(name short) ) {
		next if $opts{$_};
		p "Can't find '$_:'\n";
		return undef;
	}
	$file =~ m{.*/(.*?)$};
	my $fname = $1;
	if ( $fname ne $opts{name} ) {
		p "Name field: '$opts{name}' differs from file name: '$fname'\n";
		return undef;
	}
	if ( $opts{status} and $opts{status} !~ /^OK(\s+.*)?$/ ) {
		p "Marked as '$opts{status}'\n";
		return undef;
	}

	$processed = "";
	$space = "";
	$last_cmd = undef;
	$is_sub = 0;

	$opts{uri} = [ map { eval $_ } @{$opts{uri}} ];
	$opts{class} = ${class};
	$opts{pkg} = "${class}::$opts{name}";
	$opts{unify} = join "\n", @{ $parts{unify} };
	$opts{unify} ||= 's/#.*//; s{/$}{};';

	pr "package $opts{pkg};\n\n";
	pr <<'EOF';
	use strict;
	use warnings;
	use RSGet::Get;
	use RSGet::Tools;
	use URI::Escape;

	BEGIN {
		our @ISA;
		@ISA = qw(RSGet::Get);
	}

	my $STDSIZE = qr/\d+(?:\.\d+)?\s*[kmg]?b/i;
EOF

	pr join "\n", @{$parts{pre}}, "\n";

	my $stage = 0;
	p_sub( "stage0" );
	my @machine = @{$parts{start}};
	while ( $_ = shift @machine ) {
		$space = "";
		$space = $1 if s/^(\s+)//;

		if ( s/^(GET|WAIT|CAPTCHA|DOWNLOAD)\s*\(// ) {
			my $cmd = lc $1;
			my $next_stage = "stage" . ++$stage;
			my @skip;
			push @skip, $_;
			until ( /;\s*$/ ) {
				$_ = shift @machine;
				push @skip, $_;
			}
			p_ret( $cmd, "\\&$next_stage" );
			foreach ( @skip ) {
				p_line();
			}
			p_subend();
			$last_cmd = $cmd;
			p_sub( $next_stage );
		} elsif ( s/^(GET|WAIT|CAPTCHA)_NEXT\s*\(\s*(.*?)\s*,// ) {
			my $cmd = lc $1;
			my $next_stage = $2;
			p_ret( $cmd, "\\&$next_stage" );
			p_line();
		} elsif ( s/^GOTO\s+(stage_\S+)// ) {
			p_ret( $1 );
			pr ')';
			p_line();
		} elsif ( s/^(stage_\S+)\s*:\s*(.*)$// ) {
			my $next_stage = $1;
			my $left = $_;
			p_ret( $next_stage );
			pr ');';
			p_subend();
			p_sub( $next_stage );
			$_ = $left;
			redo if /\S/;
		} elsif ( s/^(ERROR|RESTART|LINK|MULTI)\s*\(// ) {
			p_ret( lc $1 );
			p_line();
		} elsif ( s/^INFO\s*\(// ) {
			pr $space . 'return "info" if $self->info( ';
			p_line();
		} elsif ( s/^SEARCH\s*\(// ) {
			pr $space . 'return if $self->search( ';
			p_line();
		} elsif ( s/^(PRINT|LOG|COOKIE)\s*\(// ) {
			p_func( lc $1 );
			p_line();
		} elsif ( s/^!\s+// ) {
			my $line = quotemeta $_;
			pr $space . 'return $self->problem( "'. $line .'" ) unless ';
			p_line();
		} else {
			pr $space;
			p_line();
		}
	}
	p_subend();

	pr @{$parts{perl}};

	pr "\npackage $opts{pkg};\n";
	pr "sub unify { local \$_ = shift; $opts{unify};\nreturn \$_;\n};\n";
	pr '\&unify;';

	my $unify;
	{
		local $SIG{__DIE__};
		delete $SIG{__DIE__};
		$unify = eval $processed;
	}

	if ( $@ ) {
		p "Error(s): $@";
		return undef unless verbose( 1 );
		my $err = $@;
		return undef unless $err =~ /line \d+/;
		my @p = split /\n/, $processed;
		for ( my $i = 0; $i < scalar @p; $i++ ) {
			my $n = $i + 1;
			p sprintf "%s%4d: %s\n",
				($err =~ /line $n[^\d]/ ? "!" : " "),
				$n,
				$p[ $i ];
		}
		return undef;
	}
	if ( not $unify or not ref $unify or ref $unify ne "CODE" ) {
		my $ru = ref $unify || "undef";
		p "Error: invalid, unify returned '$ru'";
		return undef;
	}
	$opts{unify} = $unify;

	return $opts{pkg} => \%opts;
	return ();
}

1;
# vim:ts=4:sw=4
