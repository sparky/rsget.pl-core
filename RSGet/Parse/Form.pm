package RSGet::Form;
# This file is an integral part of rsget.pl downloader.
#
# 2009-2010 (c) Przemysław Iskra <sparky@pld-linux.org>
#		This program is free software,
# you may distribute it under GPL v2 or newer.

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
		my $fbody = $2;
		my $attr = split_attributes( $1 || "" );
		$attr->{body} = $fbody;
		push @forms, $attr;
	}
	unless ( @forms ) {
		warn "No forms found\n" if verbose( 2 );
		dump_to_file( $html, "html" ) if setting( "debug" );
		return undef unless $opts{fallback};
		push @forms, { body => '' };
	}

	my $found;
	foreach my $attr ( qw(id name) ) {
		if ( not $found and $opts{ $attr } ) {
			foreach my $form ( @forms ) {
				if ( $form->{$attr} and $form->{$attr} eq $opts{$attr} ) {
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
				next EACH_FORM unless exists $form->{$k};
				next EACH_FORM unless $form->{$k} =~ m{$match};
			}
			$found = $form;
			last;
		}
		if ( verbose( 2 ) and not $found ) {
			my $all = join ", ", map { "$_ => $m->{$_}" } sort keys %$m;
			warn "Can't find form which matches: $all\n";
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

	my $attr = $found;
	my $fbody = $attr->{body};

	my $self = {};
	$self->{action} = $attr->{action} || "";
	$self->{post} = 1 if $attr->{method} and lc $attr->{method} eq "post";
	my @order;
	my %values;
	my $formelements = join "|",
		qw(input button select optgroup option textarea isindex);
	while ( $fbody =~ s{^.*?<($formelements)\s+(.*?)?\s*/?\s*>}{}si ) {
		my $el = lc $1;
		my $attr = split_attributes( $2 || "" );
		my $name = $attr->{name};
		next unless $name;

		unless ( exists $values{ $name } ) {
			push @order, $name;
			$values{ $name } = undef;
		}
		if ( $el eq "input" ) {
			my $type = lc $attr->{type};
			if  ( $type eq "hidden" ) {
				my $v = $attr->{value};
				$values{ $name } = defined $v ? $v : "";
			} elsif ( $type eq "submit" ) {
				my $v = $attr->{value};
				if ( defined $v ) {
					my $vs = $values{ $name } ||= [];
					push @$vs, $v;
				}
			}
		}
	}
	$self->{order} = \@order;
	$self->{values} = \%values;

	return bless $self, $class;
}

sub split_attributes
{
	local $_ = shift;
	my %attr;
	while ( s/^\s*([a-z0-9_]+)([=\s])//i ) {
		my $name = lc $1;
		my $eq = $2;
		if ( $eq eq "=" ) {
			my $value;
			if ( s/^(["'])// ) {
				my $quot = $1;
				s/^(.*?)$quot//;
				$value = $1;
			} else {
				s/(\S+)//;
				$value = $1;
			}
			$attr{ $name } = defined $value ? de_ml( $value ) : "";
		} else {
			$attr{ $name } = $name;
		}
	}
	return \%attr;
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

sub select
{
	my $self = shift;
	my $key = shift;
	my $num = shift || 0;

	unless ( exists $self->{values}->{$key} ) {
		warn "'$key' does not exist\n" if verbose( 1 );
		return undef;
	}

	my $v = $self->{values}->{$key};
	if ( ref $v ) {
		$v = $v->[ $num ];
		$self->{values}->{$key} = $v;
		return $v;
	}
	return undef;
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

sub action
{
	my $self = shift;
	if ( @_ ) {
		$self->{action} = shift;
	}
	return $self->{action};
}

sub method
{
	my $self = shift;
	if ( @_ ) {
		my $method = shift;
		$self->{post} = $method eq "post" ? 1 : 0;
	}
	return $self->{post} ? "post" : "get";
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
		if ( ref $v and ref $v eq "ARRAY" ) {
			$v = "[ " . ( join "; ", @$v ) . " ]";
		}
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
		grep { defined $vs->{ $_ } and not ref $vs->{ $_ } }
		@{$self->{order}};

	if ( $self->{post} ) {
		return $self->{action}, post => $post;
	} else {
		return $self->{action} . "?" . $post;
	}
}

1;

# vim: ts=4:sw=4:fdm=marker
