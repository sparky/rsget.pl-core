BEGIN { die "Not a real code !"; }

sub start(&) {}
sub error {}
sub get {}
sub assert {}
sub info {}
sub click {}
sub download {}
sub sleep($$) {}

=head1 NAME

Programming interface for rsget.pl plugins.

=head1 CURRENT

Plugin programming interface in current rsget.pl is, I must admit, idiotic.
It has lots of rectrictions and prevents from writing real code. The new one
will try to give as much perl-freedom as possible.

=head1 REASON

Why special interface is needed ?

rsget.pl runns all downloads in just 1 thread, which has many advantages, but
it complicates plugins somewhat. They must be executed in short "bursts", that
is, they must exit for each major operation (download, wait, or wait for human
interaction). The only way I see this is to divide each plugin in many
functions, one function for each stage.

=head2 One Thread per download ?

If we were using one thread per download the following code could be a valid
downloader:
=cut

start {
	my $uri = shift;
	
	get $uri;

	error "file not found: $1"
		if m#<span class="fail_info">\s*(.*?)\s*</span>#s;

	assert m#<h1>(.+?)</h1>#;
	my $fname = de_ml $1;

	assert m#<strong>($STDSIZE)</strong>#o;
	info name => $fname, asize => $1;

	click "", post => { downloadLink => "wait" };

	sleep 30, "waiting for download link";

	click "", post => { downloadLink => "show" };

	download $uri, post => { download => "normal" };

	restart $1, "free limit reached"
		if m#You need to wait (\d+) seconds to start another download\.#;
};

=head2 One thread for all

In out case every get(), download(), wait() has to stop execution of this
function. This can be easily acomplished by using eval wrapper while calling
the function and die "All OK!" after setting up all information needed in
those functions.

The problem is that we have no means to return to the eariler stage after
performing those tasks. That's why we need a separate function for each stage.
=cut


start {
	my $uri = shift;
	
	get $uri,
	sub {

		error "file not found: $1"
			if m#<span class="fail_info">\s*(.*?)\s*</span>#s;

		assert m#<h1>(.+?)</h1>#;
		my $fname = de_ml $1;

		assert m#<strong>($STDSIZE)</strong>#o;
		info name => $fname, asize => $1;

		click "", post => { downloadLink => "wait" },
		sub {

			sleep 30, "waiting for download link",
			sub {

				click "", post => { downloadLink => "show" },
				sub {

					download $uri, post => { download => "normal" },
					sub {

						restart $1, "free limit reached"
							if m#You need to wait (\d+) seconds to start another download\.#;
					};
				};
			};
		};
	};
};

=head3 Continuation

This code doesn't require any preprocessing to run. Nested functions allow
access to variables from their parents. The only change is that each of those
methods gets a sub which they should call after performing the task.

However, the deep nesting eats all our horizontal space.

=head2 Same code without tabulation

Makes it very hard to count how many sub {} we have to close.
=cut

start {
	my $uri = shift;
	
	get $uri,
	sub {

	error "file not found: $1"
		if m#<span class="fail_info">\s*(.*?)\s*</span>#s;

	assert m#<h1>(.+?)</h1>#;
	my $fname = de_ml $1;

	assert m#<strong>($STDSIZE)</strong>#o;
	info name => $fname, asize => $1;

	click "", post => { downloadLink => "wait" },
	sub {

	sleep 30, "waiting for download link",
	sub {

	click "", post => { downloadLink => "show" },
	sub {

	download $uri, post => { download => "normal" },
	sub {

	restart $1, "free limit reached"
		if m#You need to wait (\d+) seconds to start another download\.#;

	};
	};
	};
	};
	};
};


=head2 Automatic subs

We can preprocess the code, the preprocessor will automatically generate sub
blocks for us. Each block spans between automatic sub marker and the end of the
code block.

=cut

start {
	my $uri = shift;
	
	get $uri, sub;

	error "file not found: $1"
		if m#<span class="fail_info">\s*(.*?)\s*</span>#s;

	assert m#<h1>(.+?)</h1>#;
	my $fname = de_ml $1;

	assert m#<strong>($STDSIZE)</strong>#o;
	info name => $fname, asize => $1;

	click "", post => { downloadLink => "wait" }, sub;

	sleep 30, "waiting for download link", sub;

	click "", post => { downloadLink => "show" }, sub;

	download $uri, post => { download => "normal" }, sub;

	restart $1, "free limit reached"
		if m#You need to wait (\d+) seconds to start another download\.#;

};

=head3 Continuation

Looks almost like the first one !

Are autosub markers really necessary ?

I think yes. In more complex code we will have to use explicit subs or sub
names (\&sub_name). Some function may allow additional sub to be passed.
Without the marker we couldn't tell whether there already is a "continuation
function" or just the one with special meaning.

For instance:

captcha qr/[VALID CHARS]+/, solver => \&our_solver, sub;

Without the marker preprocessor could assume execution would continue in
&our_solver and not create the necessary sub.

=cut



=head1 CODE COVERAGE

To keep a large number of plugins up-to-date I need some efficient and reliable
way to track most common problems and most common uses. That's why I'm going to
introduce "voluntary distributed code coverage analysis".
Each rsget.pl client will have the ability to gather information about plugin
functions being executed and upload those statistics anonymously to our
servers. This will help us catch uncommon problems and problems that we didn't
think of while writing the plugin. Moreover, after page update some error
handlers are no longer used, but we can't know that without checking a very
large number of links. With the coverage information we will be able to
efficiently detect the dead code and remove it, keeping the plugin clean and
always up-to-date.

Each special function will generate coverage information if executed.
There will be one function which purpose will be solely to gather coverage
information. This will be useful for blocks that don't call special functions
(directly).

For instance, if we've got two separate matches and we would like to know
which one does match, the code could look something like this:

=cut

	if (
		expect( /foo string/ )
			or
		expect( /bar string/ )
	) {
		...
		checkpoint;
		...
	}

=head2 Continuation

Do you think this would be an invasion of someone's privacy ?
Those statistics will be strictly voluntary and anonymous.




=head1 COMPLETE PLUGIN

=cut

# unique package name corresponding to the Plugin/Dir/File
package Plugin::Type::Name;

# Require plugin interface version 0.10
# If users rsget.pl does not provide that interface plugin won't be loaded.
# Also load optional extensions.
use RSGet::Plugin 0.10 qw(cookie captcha form);

# Register new plugin
plugin
	name => "Name",
	short => "N",
	web => "http://name.com/",
	tos => "http://name.com/tos";

# Register uris supported by that plugin
uri qr{name\.com/file/\d+};
uri qr{name\.org/file/\d+};
uri_exact qr{https?://f\d+\.name\.org};

# Register uri unification method
# $_ is the input
# return new value or edit $_ in place
unify
{
	s{#.*}{};
	s{/+$}{};
};

# Register downloader
start
{
	my $uri = shift;
	get $uri, sub;

	assert /find link="(.*?)"/;

	click $1, sub named_sub;

	if ( $need_captcha ) {
		captcha result => fail;

		get "/image", sub;

		captcha
			qr/[allowed]/,
			process => \&process_captcha,
			sub;

		click "/check", post => { captcha => $_ },
			\&named_sub;
	} else {
		captcha result => ok;
	}

	sleep 30, "waiting", sub;

	get $link, sub;

	download $file, sub;

	restart $time, $message
		if /Must wait/;
};

# Disable plugin preprocessing (no more autosubs)
no RSGet::Plugin;

# Do anything you want here
sub process_captcha
{
	my $img = shift;

	return $img->ocr;
}

=head1 DETAILED

	package Plugin::Type::Name;

package must be a unique name corresponding to the Plugin/Dir/File

	use RSGet::Plugin 0.10 qw(cookie captcha form);

Require plugin interface version 0.10
If users rsget.pl does not provide that interface plugin won't be loaded.
Each time any addition required by some plugin is made interface version
number will be increased. Also support for older interfaces may be dropped
from time to time.
It also loads optional extensions.
 - ask - plugin will be able to ask some additional questions (video size)
 - captcha - web uses captcha
 - cookie - web requires cookie support
 - !cookie - web requires cookie support while checking links
 - form - automatic form extraction
 - https, ftp, rtmp, rtsp - non-standard protocols


	plugin
		name => "Name",
		short => "N",
		web => "http://name.com/",
		tos => "http://name.com/tos";

Register this new plugin.
 - name (required) - full name
 - short (required) - short name
 - web (required) - uri to main web page
 - tos - uri to terms of service
 - cookie - template for cookie file name

# Register uris supported by that plugin
uri qr{name\.com/file/\d+};
uri qr{name\.org/file/\d+};
uri_exact qr{https?://f\d+\.name\.org};

# Register uri unification method
# $_ is the input
# return new value or edit $_ in place
unify
{
	s{#.*}{};
	s{/+$}{};
};

# Register downloader
start
{
	my $uri = shift;
	get $uri, sub;

	assert /find link="(.*?)"/;

	click $1, sub named_sub;

	if ( $need_captcha ) {
		captcha result => fail;

		get "/image", sub;

		captcha
			qr/[allowed]/,
			process => \&process_captcha,
			sub;

		click "/check", post => { captcha => $_ },
			\&named_sub;
	} else {
		captcha result => ok;
	}

	sleep 30, "waiting", sub;

	get $link, sub;

	download $file, sub;

	restart $time, $message
		if /Must wait/;
};

# Disable plugin preprocessing (no more autosubs)
no RSGet::Plugin;

=cut


