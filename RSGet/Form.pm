package RSGet::Form;

use strict;
use warnings;
use RSGet::Tools;
use URI::Escape;
set_rev qq$Id$;

sub new
{
	my $class = shift;
	my $html = shift;
	my %opts = @_;

	if ( $opts{source} ) {
		$html = $opts{source};
		$opts{num} ||= 0;
	}
	my @forms;
	while ( $html =~ s{^.*?<form\s*(.*?)>(.*?)</form>}{}si ) {
		my $attr = $1;
		my $fbody = $2;
		my %attr = map {
			/^(.*?)=(["'])(.*)\2$/
				? ( lc $1, $3 )
				: ( $_, undef )
			} split /\s+/, $attr;
		push @forms, [ \%attr, $fbody ];
	}
	unless ( @forms ) {
		warn "No forms found\n" if verbose( 2 );
		dump_to_file( $html, "html" ) if setting( "debug" );
		return undef unless $opts{fallback};
		push @forms, [ {}, '' ];
	}

	my $found;
	foreach my $attr ( qw(id name) ) {
		if ( not $found and $opts{ $attr } ) {
			foreach my $form ( @forms ) {
				if ( $form->[0]->{$attr} and $form->[0]->{$attr} eq $opts{$attr} ) {
					$found = $form;
					last;
				}
			}
			warn "Can't find form with $attr '$opts{$attr}'\n"
				if verbose( 2 ) and not $found;
		}
	}
	if ( not $found and $opts{match} ) {
		my $m = $opts{match};
		EACH_FORM:
		foreach my $form ( @forms ) {
			foreach my $k ( keys %$m ) {
				my $match = $m->{$k};
				if ( $k eq "body" ) {
					next EACH_FORM unless $form->[1] =~ m{$match};
				} else {
					next EACH_FORM unless exists $form->[0]->{$k};
					next EACH_FORM unless $form->[0]->{$k} =~ m{$match};
				}
			}
			$found = $form;
			last;
		}
		if ( verbose( 2 ) and not $found ) {
			my $all = join ", ", map { "$_ => $m->{$_}" } sort keys %$m;
			warn "Can't find form whitch matches: $all\n";
		}
	}
	if ( not $found and exists $opts{num} ) {
		if ( $opts{num} >= 0 and $opts{num} < scalar @forms ) {
			$found = $forms[ $opts{num} ];
		}
		warn "Can't find form number $opts{num}\n"
			if verbose( 2 ) and not $found;
	}
	if ( not $found and $opts{fallback} ) {
		$found = $forms[ 0 ];
	}
	return undef unless $found;

	my ( $attr, $fbody ) = @$found;

	my $self = {};
	$self->{action} = $attr->{action} || "";
	$self->{post} = 1 if $attr->{method} and lc $attr->{method} eq "post";
	my @order;
	my %values;
	my $formelements = join "|",
		qw(input button select optgroup option textarea isindex);
	while ( $fbody =~ s{^.*?<($formelements)(\s+.*?)?\s*/?\s*>}{}si ) {
		my $el = lc $1;
		my $attr = $2;
		my %attr = map {
			/^(.*?)=(["'])(.*)\2$/
				? ( lc $1, $3 )
				: ( $_, undef )
			} split /\s+/, $attr;
		my $name = $attr{name};
		next unless $name;

		unless ( exists $values{ $name } ) {
			push @order, $name;
			$values{ $name } = undef;
		}
		if ( $el eq "input" and lc $attr{type} eq "hidden" ) {
			$values{ $name } = $attr{value} || "";
		}
	}
	$self->{order} = \@order;
	$self->{values} = \%values;

	return bless $self, $class;
}

sub set
{
	my $self = shift;
	my $key = shift;
	my $value = shift;

	unless ( exists $self->{values}->{$key} ) {
		warn "'$key' does not exist\n" if verbose( 1 );
		push @{$self->{order}}, $key;
	}

	$self->{values}->{$key} = $value;
}

sub get
{
	my $self = shift;
	my $key = shift;

	if ( $self->{values}->{$key} ) {
		return $self->{values}->{$key};
	} else {
		warn "'$key' does not exist\n";
		return undef;
	}
}

sub dump
{
	my $self = shift;
	my $p = "action: $self->{action}\n";
	$p .= "method: " . ( $self->{post} ? "post" : "get" ) . "\n";
	$p .= "values:\n";
	my $vs = $self->{values};
	foreach my $k ( @{$self->{order}} ) {
		my $v = $vs->{$k};
		$v = "undef" unless defined $v;
		$p .= "  $k => $v\n";
	}

	dump_to_file( $p, "post" );
}

sub post
{
	my $self = shift;

	my $vs = $self->{values};
	my $post = join "&",
		map { uri_escape( $_ ) . "=" . uri_escape( $vs->{ $_ } ) }
		grep { defined $vs->{ $_ } }
		@{$self->{order}};

	if ( $self->{post} ) {
		return $self->{action}, post => $post;
	} else {
		return $self->{action} . "?" . $post;
	}
}

1;

# vim:ts=4:sw=4
