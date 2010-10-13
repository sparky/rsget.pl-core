package RSGet::Processor;
# This file is an integral part of rsget.pl downloader.
#
# 2009-2010 (c) Przemysław Iskra <sparky@pld-linux.org>
#		This program is free software,
# you may distribute it under GPL v2 or newer.

use strict;
use warnings;
use RSGet::Tools;
set_rev qq$Id$;

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
	if ( $last_cmd and $last_cmd =~ /(?:click_)?download/ ) {
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


sub compile
{
	my $opts = shift;
	my $parts = shift;

	$processed = "";
	$space = "";
	$last_cmd = undef;
	$is_sub = 0;

	my $unify_body = ( join "\n", @{ $parts->{unify} } ) || 's/#.*//; s{/$}{};';

	pr "package $opts->{pkg};\n\n";
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

	pr join "\n", @{$parts->{pre}}, "\n";

	my $stage = 0;
	p_sub( "stage0" );
	my @machine = @{ $parts->{start} };
	while ( $_ = shift @machine ) {
		$space = "";
		$space = $1 if s/^(\s+)//;

		if ( s/^(GET|WAIT|CAPTCHA|(?:CLICK_)?DOWNLOAD|CLICK)\s*\(// ) {
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
		} elsif ( s/^(GET|WAIT|CAPTCHA|CLICK)_NEXT\s*\(\s*(.*?)\s*,// ) {
			my $cmd = lc $1;
			my $next_stage = $2;
			p_ret( $cmd, "\\&$next_stage" );
			p_line();
		} elsif ( s/^GOTO\s+(stage_[a-z0-9_]+)// ) {
			p_ret( $1 );
			pr ')';
			p_line();
		} elsif ( s/^(stage_[a-z0-9_]+)\s*:\s*(.*)$// ) {
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
			pr $space . 'return "info" if ${self}->info( ';
			p_line();
		} elsif ( s/^SEARCH\s*\(// ) {
			pr $space . 'return if ${self}->search( ';
			p_line();
		} elsif ( s/^(PRINT|LOG|COOKIE|CAPTCHA_RESULT)\s*\(// ) {
			p_func( lc $1 );
			p_line();
		} elsif ( s/^!\s+// ) {
			my $line = quotemeta $_;
			pr $space . 'return ${self}->problem( "'. $line .'" ) unless ';
			p_line();
		} else {
			pr $space;
			p_line();
		}
	}
	p_subend();

	pr @{$parts->{perl}};

	pr "\npackage $opts->{pkg};\n";
	pr "sub unify { local \$_ = shift; $unify_body;\nreturn \$_;\n};\n";
	pr '\&unify;';

	my $unify = eval_it( $processed );

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
	return $unify;
}

sub eval_it
{
	local $SIG{__DIE__};
	delete $SIG{__DIE__};
	return eval shift;
}

1;

# vim: ts=4:sw=4:fdm=marker
