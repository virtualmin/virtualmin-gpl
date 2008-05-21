#!/usr/local/bin/perl
# Change web server settings for some domain

package virtual_server;
if (!$module_name) {
	$main::no_acl_check++;
	$ENV{'WEBMIN_CONFIG'} ||= "/etc/webmin";
	$ENV{'WEBMIN_VAR'} ||= "/var/webmin";
	if ($0 =~ /^(.*\/)[^\/]+$/) {
		chdir($1);
		}
	chop($pwd = `pwd`);
	$0 = "$pwd/modify-web.pl";
	require './virtual-server-lib.pl';
	$< == 0 || die "modify-web.pl must be run as root";
	}
@OLDARGV = @ARGV;
$config{'web'} || &usage("Web serving is not enabled for Virtualmin");

$first_print = \&first_text_print;
$second_print = \&second_text_print;
$indent_print = \&indent_text_print;
$outdent_print = \&outdent_text_print;

# Parse command-line args
while(@ARGV > 0) {
	local $a = shift(@ARGV);
	if ($a eq "--domain") {
		push(@dnames, shift(@ARGV));
		}
	elsif ($a eq "--all-domains") {
		$all_doms = 1;
		}
	elsif ($a eq "--mode") {
		$mode = shift(@ARGV);
		}
	elsif ($a eq "--ruby-mode") {
		$rubymode = shift(@ARGV);
		}
	elsif ($a eq "--php-children") {
		$children = shift(@ARGV);
		$children > 0 || &usage("Invalid number of PHP sub-processes");
		$children > $max_php_fcgid_children && &usage("Too many PHP sub-processes - maximum is $max_php_fcgid_children");
		}
	elsif ($a eq "--no-php-children") {
		$children = 0;
		}
	elsif ($a eq "--php-version") {
		$version = shift(@ARGV);
		}
	elsif ($a eq "--proxy") {
		$proxy = shift(@ARGV);
		$proxy =~ /^(http|https):\/\/\S+$/ ||
			&usage($text{'frame_eurl'});
		}
	elsif ($a eq "--no-proxy") {
		$proxy = "";
		}
	elsif ($a eq "--framefwd") {
		$framefwd = shift(@ARGV);
		$framefwd =~ /^(http|https):\/\/\S+$/ ||
			&usage($text{'frame_eurl'});
		}
	elsif ($a eq "--frametitle") {
		$frametitle = shift(@ARGV);
		}
	elsif ($a eq "--no-framefwd") {
		$framefwd = "";
		}
	elsif ($a eq "--suexec") {
		$suexec = 1;
		}
	elsif ($a eq "--no-suexec") {
		$suexec = 0;
		}
	elsif ($a eq "--style") {
		$stylename = shift(@ARGV);
		}
	elsif ($a eq "--content") {
		$content = shift(@ARGV);
		}
	else {
		&usage();
		}
	}
@dnames || $all_doms || usage();
$mode || $rubymode || defined($proxy) || defined($framefwd) ||
  defined($suexec) || $stylename || defined($children) || $version ||
  &usage("Nothing to do");
$proxy && $framefwd && &error("Both proxying and frame forwarding cannot be enabled at once");

# Validate style
if ($stylename) {
	($style) = grep { $_->{'name'} eq $stylename } &list_content_styles();
	$style || &usage("Style $stylename does not exist");
	$content || &usage("--content followed by some initial text for the website must be specified when using --style");
	if ($content =~ /^\//) {
		$content = &read_file_contents($content);
		$content || &usage("--content file does not exist");
		}
	$content =~ s/\r//g;
	$content =~ s/\\n/\n/g;
	}

# Get domains to update
if ($all_doms) {
	@doms = grep { $_->{'web'} } &list_domains();
	}
else {
	foreach $n (@dnames) {
		$d = &get_domain_by("dom", $n);
		$d || &usage("Domain $n does not exist");
		$d->{'web'} || &usage("Virtual server $n does not have a web site enabled");
		push(@doms, $d);
		}
	}

# Make sure proxy and frame settings don't clash
foreach $d (@doms) {
	if ($framefwd && $d->{'proxy_pass_mode'} == 1) {
		&usage("Frame forwarding cannot be enabled for $d->{'dom'}, as it is currently using proxying");
		}
	if ($proxy && $d->{'proxy_pass_mode'} == 2) {
		&usage("Proxying cannot be enabled for $d->{'dom'}, as it is currently using frame forwarding");
		}
	}

# Make sure suexec and PHP / Ruby settings don't clash
foreach $d (@doms) {
	$p = $mode || &get_domain_php_mode($d);
	$r = $rubymode || &get_domain_ruby_mode($d);
	$s = defined($suexec) ? $suexec : &get_domain_suexec($d);
	if ($p eq "cgi" && !$s) {
		&usage("For PHP to be run as the domain owner in $d->{'dom'}, suexec must also be enabled");
		}
	if ($r eq "cgi" && !$s) {
		&usage("For Ruby to be run as the domain owner in $d->{'dom'}, suexec must also be enabled");
		}
	@supp = &supported_php_modes($d);
	!$mode || &indexof($mode, @supp) >= 0 ||
		&usage("The selected PHP exection mode cannot be used with $d->{'dom'}");
	if ($version) {
		$mode eq "mod_php" &&
			&usage("The PHP version cannot be set for $d->{'dom'}, as it is using mod_php");
		@avail = map { $_->[0] } &list_available_php_versions($d);
		&indexof($version, @avail) >= 0 ||
			&usage("Only the following PHP version are available for $d->{'dom'} : ".join(" ", @avail));
		}
	@rubysupp = &supported_ruby_modes($d);
	!$rubymode || $rubymode eq "none" ||
	    &indexof($rubymode, @rubysupp) >= 0 ||
		&usage("The selected Ruby exection mode cannot be used with $d->{'dom'}");
	}

# Lock them all
foreach $d (@doms) {
	&obtain_lock_web($d);
	}

# Do it for all domains
foreach $d (@doms) {
	&$first_print("Updating server $d->{'dom'} ..");
	&$indent_print();

	# Update PHP mode
	if ($mode && !$d->{'alias'}) {
		&save_domain_php_mode($d, $mode);
		}

	# Update PHP fCGId children
	if (defined($children) && !$d->{'alias'}) {
		&save_domain_php_children($d, $children);
		}

	# Update PHP version
	if ($version && !$d->{'alias'}) {
		&save_domain_php_directory($d,  &public_html_dir($d), $version);
		}

	# Update Ruby mode
	if ($rubymode && !$d->{'alias'}) {
		&save_domain_ruby_mode($d,
			$rubymode eq "none" ? undef : $rubymode);
		}

	# Update suexec setting
	if (defined($suexec) && !$d->{'alias'}) {
		&save_domain_suexec($d, $suexec);
		}

	local $oldd = { %$d };
	if (defined($proxy)) {
		# Update proxy mode
		if ($proxy) {
			$d->{'proxy_pass'} = $proxy;
			$d->{'proxy_pass_mode'} = 1;
			}
		else {
			$d->{'proxy_pass'} = undef;
			$d->{'proxy_pass_mode'} = 0;
			}
		}

	if (defined($framefwd)) {
		# Update frame forwarding mode
		if ($framefwd) {
			$d->{'proxy_pass'} = $framefwd;
			$d->{'proxy_pass_mode'} = 2;
			}
		else {
			$d->{'proxy_pass'} = undef;
			$d->{'proxy_pass_mode'} = 0;
			}
		}
	if (defined($frametitle)) {
		$d->{'proxy_title'} = $frametitle;
		}
	if (defined($frametitle) || $framefwd) {
		&$first_print($text{'frame_gen'});
		&create_framefwd_file($d);
		&$second_print($text{'setup_done'});
		}

	if ($style && !$d->{'alias'}) {
		# Apply content style
		&$first_print(&text('setup_styleing', $style->{'desc'}));
		&apply_content_style($d, $style, $content);
		&$second_print($text{'setup_done'});
		}

	if (defined($proxy) || defined($framefwd)) {
		# Save the domain
		&modify_web($d, $oldd);
		if ($d->{'ssl'}) {
			&modify_ssl($d, $oldd);
			}

		&$first_print($text{'save_domain'});
		&save_domain($d);
		&$second_print($text{'setup_done'});
		}

	&$outdent_print();
	&$second_print(".. done");
	}

foreach $d (@doms) {
	&release_lock_web($d);
	}
&run_post_actions();
&virtualmin_api_log(\@OLDARGV);

sub usage
{
print "$_[0]\n\n" if ($_[0]);
print "Changes web server settings for one or more domains.\n";
print "\n";
print "usage: modify-web.pl [--domain name] | [--all-domains]\n";
print "                     [--mode mod_php | cgi | fcgid]\n";
print "                     [--php-children number | --no-php-children]\n";
print "                     [--php-version num]\n";
print "                     [--ruby-mode none | mod_ruby | cgi | fcgid]\n";
print "                     [--suexec | --no-suexec]\n";
print "                     [--proxy http://... | --no-proxy]\n";
print "                     [--framefwd http://... | --no-framefwd]\n";
print "                     [--framefwd \"title\" ]\n";
print "                     [--style name]\n";
print "                     [--content text|filename]\n";
exit(1);
}

