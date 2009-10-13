package RSGet::Curl;

use strict;
use warnings;
use RSGet::Tools;
use RSGet::Line;
use WWW::Curl::Easy;
use WWW::Curl::Multi;
use URI::Escape;
use File::Copy;
use File::Path;
use Fcntl qw(SEEK_SET);
set_rev qq$Id$;

def_settings(
	backup => {
		desc => "Make backups if downloaded file exists.",
		default => "done,continue,scratch",
		allowed => qr/(no|(done|continue|scratch)(?:,(done|continue|scratch))*)/,
		dynamic => {
			'done,continue,scratch' => "Always.",
			done => "Only if it would replace file in outdir.",
			'continue,scratch' => "Only if it whould replace file in workdir.",
			no => "Never.",
		},
		user => 1,
	},
	backup_suf => {
		desc => "Rename backup files with specified suffix. " .
			"If none defined -N will be added to file name, without disrupting file extension.",
		allowed => qr/\S*/,
		dynamic => "STRING",
		user => 1,
	},
	outdir => {
		desc => "Output directory; where finished files are moved to.",
		default => '.',
		dynamic => "STRING",
		user => 1,
	},
	workdir => {
		desc => "Work directory; where unfinished files are stored.",
		default => '.',
		dynamic => "STRING",
		user => 1,
	},
);


my $curl_multi = new WWW::Curl::Multi;

my $curl_headers = [
	'User-Agent: Mozilla/5.0 (Windows; U; Windows NT 5.1; en-US; rv:1.9.0.10) Gecko/2009042316 Firefox/3.0.10',
	'Accept: text/xml,application/xml,application/xhtml+xml,text/html;q=0.9,text/plain;q=0.8,image/png,*/*;q=0.5',
	'Accept-Charset: ISO-8859-1,utf-8;q=0.7,*;q=0.7',
	'Accept-Language: en-us,en;q=0.5',
	];

# X-Forwarded-For: XX.XX.XXX.XXX
# Cache-Control: bypass-client=XX.XX.XX.XXX

my %active_curl;

sub new
{
	my $uri = shift;
	my $get_obj = shift;
	my %opts = @_;

	my $curl = new WWW::Curl::Easy;

	my $id = 1;
	++$id while exists $active_curl{ $id };

	my $supercurl = {
		curl => $curl,
		id => $id,
		get_obj => $get_obj,
		got => 0,
		head => "",
		body => "",
	};

	$curl->setopt( CURLOPT_PRIVATE, $id );
	$curl->setopt( CURLOPT_INTERFACE, $get_obj->{_outif} )
		if $get_obj->{_outif};

	if ( defined $get_obj->{_cookie} ) {
		$curl->setopt( CURLOPT_COOKIEJAR, $get_obj->{_cookie} );
		$curl->setopt( CURLOPT_COOKIEFILE, $get_obj->{_cookie} );
	}
	$curl->setopt( CURLOPT_HEADERFUNCTION, \&body_scalar );
	$curl->setopt( CURLOPT_WRITEHEADER, \$supercurl->{head} );
	$curl->setopt( CURLOPT_MAXREDIRS, 10 );
	$curl->setopt( CURLOPT_FOLLOWLOCATION, 1 );
	if ( $opts{headers} ) {
		my @h = @$curl_headers;
		push @h, @{ $opts{headers} };
		$curl->setopt( CURLOPT_HTTPHEADER, \@h );
	} else {
		$curl->setopt( CURLOPT_HTTPHEADER, $curl_headers );
	}
	$curl->setopt( CURLOPT_URL, $uri );
	$curl->setopt( CURLOPT_REFERER, $get_obj->{_referer} )
		if defined $get_obj->{_referer};
	$curl->setopt( CURLOPT_ENCODING, 'gzip,deflate' );
	$curl->setopt( CURLOPT_CONNECTTIMEOUT, 20 );
	$curl->setopt( CURLOPT_SSL_VERIFYPEER, 0 );

	if ( $opts{post} ) {
		my $post = $opts{post};
		$curl->setopt( CURLOPT_POST, 1 );
		if ( ref $post and ref $post eq "HASH" ) {
			$post = join "&",
				map { uri_escape( $_ ) . "=" . uri_escape( $post->{$_} ) }
				sort keys %$post;
		}
		$get_obj->log( "POST( $uri ): $post\n" ) if verbose( 3 );
		$curl->setopt( CURLOPT_POSTFIELDS, $post );
		$curl->setopt( CURLOPT_POSTFIELDSIZE, length $post );
	} else {
		$get_obj->log( "GET( $uri )\n" ) if verbose( 4 );
	}

	if ( $opts{save} ) {
		$curl->setopt( CURLOPT_WRITEFUNCTION, \&body_file );
		$curl->setopt( CURLOPT_WRITEDATA, $supercurl );

		$supercurl->{force_name} = $opts{fname} if $opts{fname};

		# if file exists try to continue
		my $fn = $get_obj->{_opts}->{fname};
		if ( $fn ) {
			my $fp = filepath( setting("workdir"), $get_obj->{_opts}->{dir}, $fn );
			if ( -r $fp ) {
				my $got = (stat(_))[7];
				#p "File '$fn' already exists, trying to continue at $got";
				$curl->setopt( CURLOPT_RANGE, "$got-" );

				$get_obj->log( "trying to continue at $got\n" ) if verbose( 4 );
				$supercurl->{fname} = $fn;
				$supercurl->{filepath} = $fp
			}
		}

		my $fs = $get_obj->{_opts}->{fsize};
		$supercurl->{fsize} = $fs if $fs;

		delete $get_obj->{is_html};
	} else {
		$get_obj->{is_html} = 1;
		$curl->setopt( CURLOPT_WRITEFUNCTION, \&body_scalar );
		$curl->setopt( CURLOPT_WRITEDATA, \$supercurl->{body} );
	}
	if ( $opts{keep_referer} or $opts{keep_ref} ) {
		$supercurl->{keep_referer} = 1;
	}

	$active_curl{ $id } = $supercurl;
	$curl_multi->add_handle( $curl );
}

sub file_backup
{
	my $fn = shift;
	my $type = shift;
	return undef unless setting("backup") =~ /$type/;
	return undef unless -r $fn;

	if ( my $s = setting("backup_suf") ) {
		my $i = 1;
		++$i while -r $fn . $s . $i;
		return $fn . $s . $i;
	}

	my $ext = "";
	$ext = $1 if $fn =~ s/(\..{3,5})$//;
	my $i = 1;
	++$i while -r "$fn-$i$ext";

	return "$fn-$i$ext";
}

sub file_init
{
	my $supercurl = shift;
	my $curl = $supercurl->{curl};
	my $get_obj = $supercurl->{get_obj};
	my $time = time;

	hadd $supercurl,
		time_start => $time,
		time_stamp => [ $time, 0, $time, 0, $time, 0 ],
		size_start => 0,
		size_got => 0;

	{
		my $mime = $curl->getinfo( CURLINFO_CONTENT_TYPE );
		if ( $mime =~ m#^text/html# ) {
			$get_obj->{is_html} = 1;
			$supercurl->{size_total} = 0;
			return;
		}
	}

	if ( my $f_len = $curl->getinfo( CURLINFO_CONTENT_LENGTH_DOWNLOAD ) ) {
		$supercurl->{size_total} = $f_len;
	}

	dump_to_file( $supercurl->{head}, "head" ) if verbose( 5 );
	my $fname;
	if ( $supercurl->{force_name} ) {
		$fname = $supercurl->{force_name};
	} elsif ( $supercurl->{head} =~
			/^Content-Disposition:\s*attachment;\s*filename\*=UTF-8''(.+?);?\s*$/mi ) {
		$fname = de_ml( uri_unescape( $1 ) );
	} elsif ( $supercurl->{head} =~
			/^Content-Disposition:\s*attachment;\s*filename\s*=\s*"?(.+?)"?;?\s*$/mi ) {
		$fname = de_ml( uri_unescape( $1 ) );
	} else {
		my $eurl = $curl->getinfo( CURLINFO_EFFECTIVE_URL );
		$eurl =~ s#^.*/##;
		$eurl =~ s/\?.*$//;
		$fname = de_ml( uri_unescape( $eurl ) );
	}

	if ( my $fn = $supercurl->{fname} ) {
		if ( $fname ne $fn ) {
			$get_obj->log( "WARNING: Name mismatch, shoud be '$fname'" );
		}
		$fname = $supercurl->{fname};
		if ( $supercurl->{head} =~ m{^Content-Range:\s*bytes\s*(\d+)-(\d+)(/(\d+))?\s*$}im ) {
			my ( $start, $stop ) = ( +$1, +$2 );
			$supercurl->{size_total} = +$4 if $3;

			$get_obj->log( "ERROR: Size mismatch: $supercurl->{fsize} != $supercurl->{size_total}" )
				if $supercurl->{fsize} != $supercurl->{size_total};

			my $fp = $supercurl->{filepath};
			my $old = file_backup( $fp, "continue" );
			my $old_msg = "";
			if ( $old ) {
				rename $fp, $old;
				copy( $old, $fp ) || die "Cannot create backup file: $!";
				$old =~ s#.*/##;
				$old_msg = ", backup saved as '$old'";
			}

			open my $f_out, '+<', $fp;
			seek $f_out, $start, SEEK_SET;
			$get_obj->log( "Continuing at " . bignum( $start ) . $old_msg );

			hadd $supercurl,
				file => $f_out,
				size_start => $start,
				size_got => $start,
				time_stamp => [ $time, $start, $time, $start, $time, $start ];

			RSGet::FileList::update(); # to update statistics
			return;
		}
	} else {
		$supercurl->{fname} = $fname;
	}

	$get_obj->set_finfo( $supercurl->{fname}, $supercurl->{size_total} );

	{
		my $fn = $supercurl->{filepath} =
			filepath( setting("workdir"), $get_obj->{_opts}->{dir}, $supercurl->{fname} );
		my $old = file_backup( $fn, "scratch" );
		if ( $old ) {
			rename $fn, $old;
			$old =~ s#.*/##;
			$get_obj->log( "Old renamed to '$old'" );
		}
		open my $f_out, '>', $fn;
		$supercurl->{file} = $f_out;
	}
}

sub body_file
{
	my ($chunk, $supercurl) = @_;

	file_init( $supercurl ) unless exists $supercurl->{size_total};

	my $len = length $chunk;
	$supercurl->{size_got} += $len;

	if ( my $file = $supercurl->{file} ) {
		my $p = print $file $chunk;
		die "\nCannot write data: $!\n" unless $p;
	} else {
		$supercurl->{body} .= $chunk;
	}

	return $len;
}

sub body_scalar
{
	my ($chunk, $scalar) = @_;
	$$scalar .= $chunk;
	return length $chunk;
}

sub filepath
{
	my $outdir = shift || '.';
	my $subdir = shift;
	my $fname = shift;

	$outdir .= '/' . $subdir if $subdir;
	unless ( -d $outdir ) {
		unless ( mkpath( $outdir ) ) {
			$outdir = '.';
		}
	}
	return $outdir . '/' . $fname;
}

sub finish
{
	my $id = shift;
	my $err = shift;

	my $supercurl = $active_curl{ $id };
	delete $active_curl{ $id };

	my $curl = $supercurl->{curl};
	delete $supercurl->{curl}; # remove circular dep

	my $get_obj = $supercurl->{get_obj};
	delete $supercurl->{get_obj};

	if ( $supercurl->{file} ) {
		close $supercurl->{file};
		$get_obj->print( "DONE " . donemsg( $supercurl ) );
	}

	$get_obj->linedata();

	my $eurl = $curl->getinfo( CURLINFO_EFFECTIVE_URL );
	my $error = $curl->errbuf;
	$curl = undef; # destroy curl before destroying getter

	if ( $err ) {
		#warn "error($err): $error\n";
		$get_obj->print( "ERROR($err): $error" ) if $err ne "aborted";
		if ( $error =~ /Couldn't bind to '(.*)'/ ) {
			my $if = $1;
			RSGet::Dispatch::remove_interface( $if, "Interface $if is dead" );
			$get_obj->{_abort} = "Interface $if is dead";
		} elsif ( $error =~ /transfer closed with (\d+) bytes remaining to read/ ) {
			RSGet::Dispatch::mark_used( $get_obj );
			$get_obj->{_abort} = "PARTIAL " . donemsg( $supercurl );
		} elsif ( $err eq "aborted" ) {

		} else {
			$get_obj->log( "ERROR($err): $error" );
		}
		$get_obj->problem();
		return undef;
	}

	return unless $get_obj->{after_curl};

	my $func = $get_obj->{after_curl};
	if ( $supercurl->{file} ) {
		rename_done: {
			my $infile = $supercurl->{filepath};
			my $outfile = filepath( setting("outdir"), $get_obj->{_opts}->{dir}, $supercurl->{fname} );
			if ( -e $outfile ) {
				my @si = stat $infile;
				my @so = stat $outfile;
				if ( $si[0] == $so[0] and $si[1] == $so[1] ) {
					p "$infile and $outfile are the same file, not renaming"
						if verbose( 2 );
					last rename_done;
				}

				my $out_rename = file_backup( $outfile, "done" );
				rename $outfile, $out_rename if $out_rename;
				p "backing up $outfile as $out_rename" if verbose( 1 );
			}
			p "renaming $infile to $outfile" if verbose( 2 );
			$! = undef;
			rename $infile, $outfile;
			if ( $! ) {
				warn "Cannot rename $infile to $outfile ($!), copying instead\n"
					if verbose( 1 );
				copy( $infile, $outfile ) || die "Cannot copy $infile to $outfile: $!";
				unlink $infile;
			}
		}

		$get_obj->{dlinfo} = sprintf 'DONE %s %s / %s',
			$supercurl->{fname},
			bignum( $supercurl->{size_got} ),
			bignum( $supercurl->{size_total} );
	} else {
		$get_obj->{body} = $supercurl->{body};
	}

	$get_obj->get_finish( $eurl, $supercurl->{keep_referer} || 0 );
}

sub need_run
{
	return scalar keys %active_curl;
}

sub maybe_abort
{
	my $time = time;
	my $stall_time = $time - 120;
	foreach my $id ( keys %active_curl ) {
		my $supercurl = $active_curl{ $id };
		my $get_obj = $supercurl->{get_obj};
		if ( $get_obj->{_abort} ) {
			my $curl = $supercurl->{curl};
			$curl_multi->remove_handle( $curl );
			finish( $id, "aborted" );
		}
		if ( ( $supercurl->{stalled_since} || $time ) < $stall_time ) {
			my $curl = $supercurl->{curl};
			$curl_multi->remove_handle( $curl );
			finish( $id, "timeout" );
		}
	}
}

sub perform
{
	my $running = scalar keys %active_curl;
	return unless $running;
	my $act = $curl_multi->perform();
	return if $act == $running;

	while ( my ($id, $rv) = $curl_multi->info_read() ) {
		next unless $id;

		finish( $id, $rv );
	}
}

my $avg_speed = 0;
sub update_status
{
	my $time = time;
	my $total_speed = 0;

	foreach my $supercurl ( values %active_curl ) {
		next unless exists $supercurl->{size_total};
		my ($size_got, $size_total, $time_stamp ) =
			@$supercurl{ qw(size_got size_total time_stamp) };

		my $size = bignum( $size_got ) . " / " . bignum( $size_total );
		if ( $size_total > 0 ) {
			my $per = sprintf "%.2f%%", $size_got * 100 / $size_total;
			$size .= " [$per]";
			$supercurl->{get_obj}->linedata( prog => $per );
		}

		if ( $time_stamp->[4] + 30 <= $time ) {
			@$time_stamp[0..3] = @$time_stamp[2..5];
			$time_stamp->[4] = $time;
			$time_stamp->[5] = $size_got;
		}

		my $time_diff = $time - $time_stamp->[0];
		my $size_diff = $size_got - $time_stamp->[1];

		if ( $time_diff > 0 and $size_diff == 0 ) {
			$supercurl->{stalled_since} ||= $time;
			my $stime = s2string( $time - $supercurl->{stalled_since} );
			$supercurl->{get_obj}->print( "$size; STALLED $stime" );
			next;
		}

		my $speed = "???";
		if ( $time_diff > 0 ) {
			my $s = $size_diff / ( $time_diff * 1024 );
			$speed = sprintf "%.2f", $s;
			$total_speed += $s;
		}

		my $eta = "";
		if ( $size_total > 0 and $time_diff > 0 and $size_diff > 0 ) {
			my $tleft = ($size_total - $size_got) * $time_diff / $size_diff;
			$eta = " " . s2string( $tleft );
			delete $supercurl->{stalled_since}
		}

		$supercurl->{get_obj}->print( "$size; ${speed}KB/s$eta" );
	}
	$avg_speed = ($avg_speed * 9 + $total_speed) / 10;

	my $running = scalar keys %active_curl;
	RSGet::Line::status(
		'running cURL' => $running,
		'total speed' => ( sprintf '%.2fKB/s', $avg_speed )
	);
	return;
}

sub donemsg
{
	my $supercurl = shift;

	my $size_diff = $supercurl->{size_got} - $supercurl->{size_start};
	my $time_diff = time() - $supercurl->{time_start};
	$time_diff = 1 unless $time_diff;
	my $eta = s2string( $time_diff );
	my $speed = sprintf "%.2f", $size_diff / ( $time_diff * 1024 );

	return bignum( $supercurl->{size_got} ) . "; ${speed}KB/s $eta";
}


1;

# vim:ts=4:sw=4
