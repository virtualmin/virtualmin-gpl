#!/usr/local/bin/perl

=head1 modify-web.pl

Change a virtual server's web configuration

This script can update the PHP and web forwarding settings for one or more
virtual servers. Like other scripts, the servers to change are selecting
using the C<--domain> or C<--all-domains> parameters.

To change the method Virtualmin uses to run CGI scripts, use the C<--mode>
parameter followed by one of C<none>, C<mod_php>, C<cgi>, C<fcgid> or C<fpm>.
Or you can use C<--default-mode> to switch to the default defined in the 
domain's template.

When using FPM mode, you can configure process manager mode, like C<dynamic>,
C<static> or C<ondemand> with the C<--php-fpm-mode> flag.

Additionally, when using FPM mode, you can configure webserver to use a socket file
for communication with the FPM server with the C<--php-fpm-socket> flag.
Or switch back to using a TCP port with the C<--php-fpm-port> flag.

If your system has more than one version of PHP installed, the version to use
for a domain can be set with the C<--php-version> parameter, followed by a
number (7.4 or 8.2).

If Virtualmin runs PHP via FastCGI, you can set the number of PHP sub-processes
with the C<--php-children> parameter or using C<--php-children-no-check> parameter
to skip recommended checks, or turn off the automatic startup of
sub-processes with C<--no-php-children>. Similarly, the maximum run-time of 
a PHP script can be set with C<--php-timeout>, or set to unlimited with
C<--no-php-timeout>.

PHP error logging can be enabled with the C<--php-log> flag, followed by
a path like C<logs/php.log>. Alternately you can opt to use the default
path with the C<--default-php-log> flag, or turn logging off with the flag
C<--no-php-log>.

By default PHP scripts can send email, but you can prevent this with the 
C<--no-php-mail> flag. This can provide some protection against a PHP script
vulnerability being used to send spam. Or to re-enable email again, use the
C<--php-mail> flag.

If your Apache configuration contains unsupported C<mod_php> directives,
the C<--cleanup-mod-php> flag can be used to remove them from a virtual server.
This is primarily useful if the Apache module has been disabled, but not all
directives have been cleaned up.

The C<--proxy> parameter can be used to have the website proxy all requests
to another URL, which must follow C<--proxy>. To disable this, the
C<--no-proxy> parameter must be given.

The C<--framefwd> parameter similarly can be used to forward requests to the
virtual server to another URL, using a hidden frame rather than proxying. To
turn it off, using the C<--no-framefwd> option. To specify a title for the
forwarding frame page, use C<--frametitle>.

If Ruby is installed, the execution mode for scripts in that language can be
set with the C<--ruby-mode> flag, followed by either C<--mod_ruby>, C<--cgi> or
C<--fcgid>. This has no effect on scripts using the Rails framework though,
as they always run via a Mongrel proxy.

To replace the website's default page, use the C<--content> parameter, followed
by the path to a file containing the HTML content or the content itself. If no
content is provided, a Virtualmin default website page will be created.

To enable the webmail and admin DNS entries for the selected domains
(which redirect to Usermin and Webmin by default), the C<--webmail> flag
can be used. This will make both the DNS and Apache configuration changes
needed. To turn them off, use the C<--no-webmail> flag.

To have Apache configured to accept requests for any sub-domain, use the
C<--matchall> command-line flag. This will also add a C<*> DNS entry if needed.
To turn this feature off, use the C<--no-matchall> flag.

To enable server-side includes for this virtual server, use the C<--includes>
flag followed by an extension like C<.html> or C<.shtml>. To disable includes,
use the C<--no-includes> flag.

To make a virtual server the default served by Apache for its IP address,
use the C<--default-website> flag. This lets you control which domain's
contents appear if someone accesses your system via a URL with only an IP
address, rather than a domain name.

To change the HTTP port the selected virtual servers listen on, use the 
C<--port> flag followed by a port number. For SSL websites, you can also use
the C<--ssl-port> flag.

Alternately, you can change the HTTP port that Virtualmin uses in URLs
referencing this domain with the C<--url-port> flag. For SSL websites, you can
also use the C<--ssl-url-port> flag.

If the domain's SSL certificate was requested from Let's Encrypt, you can
turn on automatic renewal when close to expiry with the C<--letsencrypt-renew>
flag. Alternately, renewal can be disabled with the C<--no-letsencrypt-renew>
parameter.

If the domain is sharing an SSL certificate with another domain (because it's
CN matches both of them), you can use the C<--break-ssl-cert> flag to stop
sharing and allow this domain's cert to be re-generated. Conversely, if the
server isn't sharing a cert but could, the C<--link-ssl-cert> flag can be used
to enable sharing.

To move the SSL cert, key or CA cert files to a new location, use the
C<--ssl-cert>, C<--ssl-key> or C<--ssl-ca> flags respectively, followed
by an absolute or relative path. To switch to the default locations set in the
server's template, use the C<--default-ssl-cert>, C<--default-ssl-key> or
C<--default-ssl-ca> flags. Or to switch all SSL paths to match the template,
simply use C<--default-ssl-paths>.

To change the domain's HTML directory, use the C<--document-dir> flag followed
by a path relative to the domain's home. Alternately, if the Apache config has
been modified outside of Virtualmin and you just want to detect the new path,
use the C<--fix-document-dir> flag. If you want the directory to be renamed
as well as updated in the webserver configuration, use the
C<--move-document-dir> flag. Note that this flag cannot be used for sub-domains,
as their HTML directory is under the parent's HTML dir.

However, for sub-domains you can adjust the HTML sub-directory with the 
C<--subprefix> path followed by a directory relative to the parent's
C<public_html> dir. Or use C<--move-subprefix> to actually move the directory
as well.

To force re-generated of TLSA DNS records after the SSL cert is manually
modified, use the C<--sync-tlsa> flag.

You can select which mode is used for running CGI scripts with one of the
flags C<--enable-fcgiwrap> or C<--enable-suexec>. Or you can turn off CGIs
entirely (not recommended) with C<--disable-cgi>.

If your webserver supports multiple HTTP protocols, you can use the 
C<--protocols> flag to choose which are enabled for the website. This flag must
be followed by some combination of C<http/1.1>, C<h2> and C<h2c>. To revert to
the default protocols for your webserver, use the C<--default-protocols> flag.

Although the C<create-redirect> API command can be used to create arbitrary
redirects, you can use this command to setup some canonical domain redirects.
To redirect all requests from www.domain.com to domain.com, use the 
C<--www-to-domain> flag. Or to go in the other direction, use the flag
C<--domain-to-www>. Or to redirect all sub-domains to domain.com you can use
C<--subdomain-to-domain>. Finally to turn off canonical domain redirects,
use C<--no-redirect>.

=cut

package virtual_server;
if (!$module_name) {
	$main::no_acl_check++;
	$ENV{'WEBMIN_CONFIG'} ||= "/etc/webmin";
	$ENV{'WEBMIN_VAR'} ||= "/var/webmin";
	if ($0 =~ /^(.*)\/[^\/]+$/) {
		chdir($pwd = $1);
		}
	else {
		chop($pwd = `pwd`);
		}
	$0 = "$pwd/modify-web.pl";
	require './virtual-server-lib.pl';
	$< == 0 || die "modify-web.pl must be run as root";
	}
&licence_status();
@OLDARGV = @ARGV;
&set_all_text_print();

# Parse command-line args
$supports_ruby = defined(&supported_ruby_modes);
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
	elsif ($a eq "--default-mode") {
		$defmode = 1;
		}
	elsif ($a =~ /--php-children/) {
		$children = shift(@ARGV);
		$children_no_check = 1 if ($a =~ /no-check/);
		$children > 0 || &usage("Invalid number of PHP sub-processes");
		(!$children_no_check && $children > $max_php_fcgid_children) && &usage("Too many PHP sub-processes -  maximum recommended is $max_php_fcgid_children");
		}
	elsif ($a eq "--no-php-children") {
		$children = 0;
		}
	elsif ($a eq "--php-timeout") {
		$timeout = shift(@ARGV);
		$timeout =~ /^[1-9]\d*$/ && $timeout <= 86400 ||
			&usage("Invalid PHP script timeout in seconds");
		}
	elsif ($a eq "--no-php-timeout") {
		$timeout = 0;
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
	elsif ($a eq "--ruby-mode" && $supports_ruby) {
		$rubymode = shift(@ARGV);
		}
	elsif ($a eq "--content") {
		$content = shift(@ARGV);
		}
	elsif ($a eq "--webmail") {
		$webmail = 1;
		}
	elsif ($a eq "--no-webmail") {
		$webmail = 0;
		}
	elsif ($a eq "--matchall") {
		$matchall = 1;
		}
	elsif ($a eq "--no-matchall") {
		$matchall = 0;
		}
	elsif ($a eq "--includes") {
		$includes = shift(@ARGV);
		}
	elsif ($a eq "--no-includes") {
		$includes = "";
		}
	elsif ($a eq "--default-website") {
		$defwebsite = 1;
		}
	elsif ($a eq "--access-log") {
		$accesslog = shift(@ARGV);
		}
	elsif ($a eq "--error-log") {
		$errorlog = shift(@ARGV);
		}
	elsif ($a eq "--document-dir") {
		$htmldir = shift(@ARGV);
		}
	elsif ($a eq "--move-document-dir") {
		$htmldir = shift(@ARGV);
		$htmldirmove = 1;
		}
	elsif ($a eq "--subprefix") {
		$subprefix = shift(@ARGV);
		}
	elsif ($a eq "--move-subprefix") {
		$subprefix = shift(@ARGV);
		$htmldirmove = 1;
		}
	elsif ($a eq "--fix-document-dir") {
		$fixhtmldir = 1;
		}
	elsif ($a eq "--port") {
		$port = shift(@ARGV);
		$port =~ /^\d+$/ && $port > 0 && $port < 65536 ||
			&usage("--port must be followed by a number");
		}
	elsif ($a eq "--ssl-port") {
		$sslport = shift(@ARGV);
		$sslport =~ /^\d+$/ && $sslport > 0 && $sslport < 65536 ||
			&usage("--ssl-port must be followed by a number");
		}
	elsif ($a eq "--url-port") {
		$urlport = shift(@ARGV);
		$urlport =~ /^\d+$/ && $urlport > 0 && $urlport < 65536 ||
			&usage("--url-port must be followed by a number");
		}
	elsif ($a eq "--ssl-url-port") {
		$sslurlport = shift(@ARGV);
		$sslurlport =~ /^\d+$/ && $sslport > 0 && $sslport < 65536 ||
			&usage("--ssl-url-port must be followed by a number");
		}
	elsif ($a eq "--fix-options") {
		$fixoptions = 1;
		}
	elsif ($a eq "--multiline") {
		$multiline = 1;
		}
	elsif ($a eq "--letsencrypt-renew") {
		if ($ARGV[0] =~ /^\d+(\.\d+)?$/) {
			# Followed by a number of months, which is no longer
			# needed
			shift(@ARGV);
			}
		$renew = 1;
		}
	elsif ($a eq "--no-letsencrypt-renew") {
		$renew = 0;
		}
	elsif ($a eq "--break-ssl-cert") {
		$breakcert = 1;
		}
	elsif ($a eq "--link-ssl-cert") {
		$linkcert = 1;
		}
	elsif ($a eq "--ssl-cert") {
		$ssl_cert = shift(@ARGV);
		}
	elsif ($a eq "--default-ssl-cert") {
		$ssl_cert = "default";
		}
	elsif ($a eq "--ssl-key") {
		$ssl_key = shift(@ARGV);
		}
	elsif ($a eq "--default-ssl-key") {
		$ssl_key = "default";
		}
	elsif ($a eq "--ssl-ca") {
		$ssl_ca = shift(@ARGV);
		}
	elsif ($a eq "--default-ssl-ca") {
		$ssl_ca = "default";
		}
	elsif ($a eq "--default-ssl-paths") {
		$ssl_cert = $ssl_key = $ssl_ca = "default";
		}
	elsif ($a eq "--sync-tlsa") {
		$tlsa = 1;
		}
	elsif ($a eq "--php-fpm-port") {
		$fpmport = 1;
		}
	elsif ($a eq "--php-fpm-socket") {
		$fpmsock = 1;
		}
	elsif ($a eq "--php-fpm-mode") {
		$fpmtype = shift(@ARGV);
		}
	elsif ($a eq "--enable-fcgiwrap") {
		$cgimode = 'fcgiwrap';
		}
	elsif ($a eq "--disable-fcgiwrap" || $a eq "--enable-suexec") {
		$cgimode = 'suexec';
		}
	elsif ($a eq "--disable-cgi") {
		$cgimode = '';
		}
	elsif ($a eq "--add-directive") {
		my ($n, $v) = split(/\s+/, shift(@ARGV));
		$n ne "" && $n ne "" ||
			&usage("--add-directive must be followed by a ".
			       "directive name and value");
		push(@add_dirs, [ $n, $v ]);
		}
	elsif ($a eq "--remove-directive") {
		my ($n, $v) = split(/\s+/, shift(@ARGV));
		$n ne "" || &usage("--remove-directive must be followed by a ".
			           "directive name and optional value");
		push(@remove_dirs, [ $n, $v ]);
		}
	elsif ($a eq "--protocols") {
		$protocols = [ split(/\s+/, shift(@ARGV)) ];
		}
	elsif ($a eq "--default-protocols") {
		$protocols = [ ];
		}
	elsif ($a eq "--cleanup-mod-php") {
		$fix_mod_php = 1;
		}
	elsif ($a eq "--php-log") {
		$phplog = shift(@ARGV);
		$phplog =~ /^\S+$/ || &usage("--php-log must be followed by ".
					     "a filename");
		}
	elsif ($a eq "--default-php-log") {
		$phplog = "default";
		}
	elsif ($a eq "--no-php-log") {
		$phplog = "";
		}
	elsif ($a eq "--no-php-mail") {
		$phpmail = 0;
		}
	elsif ($a eq "--php-mail") {
		$phpmail = 1;
		}
	elsif ($a eq "--no-redirect") {
		$wwwredir = 0;
		}
	elsif ($a eq "--www-to-domain") {
		$wwwredir = 1;
		}
	elsif ($a eq "--domain-to-www") {
		$wwwredir = 2;
		}
	elsif ($a eq "--subdomain-to-domain") {
		$wwwredir = 3;
		}
	elsif ($a eq "--help") {
		&usage();
		}
	else {
		&usage("Unknown parameter $a");
		}
	}
@dnames || $all_doms || usage("No domains to modify specified");
$mode || defined($proxy) || defined($framefwd) || $tlsa || $rubymode ||
  defined($content) || defined($children) || defined($phplog) ||
  $version || defined($webmail) || defined($matchall) || defined($timeout) ||
  $defwebsite || $accesslog || $errorlog || $htmldir || $port || $sslport ||
  $urlport || $sslurlport || defined($includes) || defined($fixoptions) ||
  defined($renew) || $fixhtmldir || $breakcert || $linkcert || $fpmport ||
  $fpmsock || $fpmtype || $defmode || defined($cgimode) || $subprefix ||
  @add_dirs || @remove_dirs || $protocols || $fix_mod_php ||
  $ssl_cert || $ssl_key || $ssl_ca || defined($phpmail) || defined($wwwredir) ||
	&usage("Nothing to do");
$proxy && $framefwd && &usage("Both proxying and frame forwarding cannot be enabled at once");

# Validate FastCGI options
@modes = &supported_php_modes();
if (defined($timeout)) {
	grep(/^fcgid|fpm$/, @modes) ||
		&usage("The PHP script timeout can only be set on systems ".
		       "that support FCGId or FPM");
	}

# Validate HTML dir
if ($htmldir) {
	$htmldir =~ /^[a-z0-9\.\-\_\/]+$/ ||
		&usage("Missing or invalid document directory");
	$htmldir !~ /^\// && $htmldir !~ /\/$/ ||
		&usage("Document directory cannot start with or end with /");
	$htmldir !~ /\.\./ ||
		&usage("Document directory cannot contain ..");
	}

# Get domains to update
if ($all_doms) {
	@doms = grep { &domain_has_website($_) } &list_domains();
	}
else {
	foreach $n (@dnames) {
		$d = &get_domain_by("dom", $n);
		$d || &usage("Domain $n does not exist");
		&domain_has_website($d) ||
		  &usage("Virtual server $n does not have a web site enabled");
		push(@doms, $d);
		}
	}

# Check if webmail is supported
foreach $d (@doms) {
	if (defined($webmail) && !&has_webmail_rewrite($d)) {
		&usage("The domain $d->{'dom'} does not support URL rewriting, needed for webmail redirects");
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

# Make sure suEXEC and PHP / Ruby settings don't clash
foreach $d (@doms) {
	$p = $mode || &get_domain_php_mode($d);
	if (defined(&get_domain_ruby_mode)) {
		$r = $rubymode || &get_domain_ruby_mode($d);
		}
	if ($r eq "cgi" && !$s) {
		&usage("For Ruby to be run as the domain owner in $d->{'dom'}, suEXEC must also be enabled");
		}
	@supp = &supported_php_modes($d);
	!$mode || &indexof($mode, @supp) >= 0 ||
		&usage("The selected PHP execution mode cannot be used with $d->{'dom'}");
	if ($version) {
		$mode eq "mod_php" &&
			&usage("The PHP version cannot be set for $d->{'dom'}, as it is using mod_php");
		@avail = map { $_->[0] } &list_available_php_versions($d);
		&indexof($version, @avail) >= 0 ||
			&usage("Only the following PHP version are available for $d->{'dom'} : ".join(" ", @avail));
		}
	@rubysupp = defined(&supported_ruby_modes) ? &supported_ruby_modes($d)
						   : ( );
	!$rubymode || $rubymode eq "none" ||
	    &indexof($rubymode, @rubysupp) >= 0 ||
		&usage("The selected Ruby execution mode cannot be used with $d->{'dom'}");
	}

if ($defaultwebsite && @doms > 1) {
	&usage("The --default-website flag can only be applied to a single virtual server");
	}

# Validate includes extension
if ($includes ne "") {
	$includes =~ /^\.([a-z0-9\.\_\-]+)$/i ||
	    &usage("--includes must be followed by an extension like .html");
	}

# Validate CGI script mode
if ($cgimode) {
	@cgimodes = &has_cgi_support();
	&indexof($cgimode, @cgimodes) >= 0 ||
	    &usage("CGI script mode $cgimode is not supported on this system");
	}

# Validate SSI change
if (defined($includes) && !&supports_ssi()) {
	&usage("Server-side includes are not supported on this system");
	}

# Lock them all
foreach $d (@doms) {
	&lock_domain($d);
	&obtain_lock_web($d) if ($d->{'web'});
	&obtain_lock_dns($d) if ($d->{'dns'} &&
				 (defined($webmail) || defined($matchall)));
	&obtain_lock_logrotate($d) if ($d->{'logrotate'} &&
				       ($accesslog || $errorlog));
	}

# Do it for all domains
foreach $d (@doms) {
	&$first_print("Updating server $d->{'dom'} ..");
	&$indent_print();
	$tmpl = &get_template($d->{'template'});

	# Use the default mode for this domain
	if ($defmode) {
		$mode = &template_to_php_mode($tmpl);
		}

	# Update PHP mode
	if ($mode && !$d->{'alias'}) {
		&$first_print("Changing PHP execution mode to $mode ..");
		my $err = &save_domain_php_mode($d, $mode);
		&$second_print($err ? ".. failed : $err" : ".. done");
		}

	# Save PHP-FPM process manager mode
	my $curr_phpmode = &get_domain_php_mode($d);
	if ($curr_phpmode eq 'fpm' && $fpmtype) {
		$fpmtype =~ /^(dynamic|static|ondemand)$/ ||
			&usage("Unknown PHP-FPM process manager mode : $fpmtype. Valid modes are dynamic, static and ondemand");
		my $fpmtype_curr = &get_domain_php_fpm_mode($d);
		if ($fpmtype ne $fpmtype_curr) {
			&$first_print(&text('phpmode_fpmtypeing', $fpmtype));
			&save_domain_php_fpm_mode($d, $fpmtype);
			&$second_print($text{'setup_done'});
			}
		}

	# Update PHP fCGId children
	if (defined($children) && !$d->{'alias'}) {
		&$first_print("Updating PHP child processes ..");
		$oldchildren = &get_domain_php_children($d);
		$d->{'phpnosanity_check'} = $children_no_check;
		if ($oldchildren == -2) {
			&$second_print(".. not supported by this PHP mode");
			}
		else {
			my $ok = &save_domain_php_children($d, $children);
			if (!$ok) {
				&$second_print(".. failed");
				}
			else {
				&$second_print(".. done");
				}
			}
		}

	# Update PHP maximum time
	if (defined($timeout) && !$d->{'alias'}) {
		$oldtimeout = &get_fcgid_max_execution_time($d);
		if ($timeout != $oldtimeout) {
			&$first_print("Updating PHP maximum run-time ..");
			&set_fcgid_max_execution_time($d, $timeout);
			&set_php_max_execution_time($d, $timeout);
			&$second_print(".. done");
			}
		}

	# Update PHP version
	if ($version && !$d->{'alias'}) {
		&$first_print("Changing PHP version to $version ..");
		my $err = &save_domain_php_directory($d, &public_html_dir($d),
						     $version);
		if (!$err) {
			my $dommode = $mode || &get_domain_php_mode($d);
			if ($dommode ne "mod_php" && $dommode ne "fpm") {
				$err = &save_domain_php_mode($d, $dommode);
				}
			&clear_links_cache($d);
			}
		&$second_print($err ? ".. failed : $err" : ".. done");
		}

	# Update FPM socket
	if (($fpmport || $fpmsock) && !$d->{'alias'}) {
		my $ps;
		if ($fpmport) {
			$ps = &get_php_fpm_socket_port($d);
			}
		else {
			$ps = &get_php_fpm_socket_file($d);
			}
		&$first_print("Changing FPM ".($fpmport ? "port" : "socket").
			      " to ".$ps." ..");
		my $currmode = $mode || &get_domain_php_mode($d);
		if ($currmode ne "fpm") {
			&$second_print(".. not in FPM mode");
			}
		else {
			my $err = &save_domain_php_fpm_port($d, $ps);
			&$second_print($err ? " .. failed : $err" : ".. done");
			}
		}

	# Update Ruby mode
	if ($rubymode && !$d->{'alias'}) {
		&save_domain_ruby_mode($d,
			$rubymode eq "none" ? undef : $rubymode);
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

	if (!$d->{'alias'} && defined($content)) {
		# Just create index.html page with content
		&$first_print($text{'setup_contenting'});
		&create_index_content($d, 
			$virtualmin_pro ? $content : "", 1);
		&$second_print($text{'setup_done'});
		}

	if (defined($webmail) && &domain_has_website($d)) {
		# Enable or disable webmail redirects
		local @oldwm = &get_webmail_redirect_directives($d);
		if ($webmail && !@oldwm) {
			&$first_print("Adding webmail and admin redirects ..");
			&add_webmail_redirect_directives($d, undef, 1);
			if ($d->{'dns'}) {
				&add_webmail_dns_records($d, 1);
				}
			&$second_print(".. done");
			}
		elsif (!$webmail && @oldwm) {
			&$first_print(
				"Removing webmail and admin redirects ..");
			&remove_webmail_redirect_directives($d);
			if ($d->{'dns'}) {
				&remove_webmail_dns_records($d);
				}
			&$second_print(".. done");
			}
		}

	if (defined($matchall) && &domain_has_website($d)) {
		# Enable or disable *.domain.com serveralias
		local $oldmatchall = &get_domain_web_star($d);
		if ($matchall && !$oldmatchall) {
			&$first_print(
			    "Adding all sub-domains to Apache config ..");
			&save_domain_web_star($d, 1);
			if ($d->{'dns'}) {
				&save_domain_matchall_record($d, 1);
				}
			&$second_print(".. done");
			}
		elsif (!$matchall && $oldmatchall) {
			&$first_print(
			    "Removing all sub-domains from Apache config ..");
			&save_domain_web_star($d, 0);
			if ($d->{'dns'}) {
				&save_domain_matchall_record($d, 0);
				}
			&$second_print(".. done");
			}
		}

	if (defined($includes) && &domain_has_website($d)) {
		# Enable or disable server-side includes
		local ($ok, $oldincludes) = &get_domain_web_ssi($d);
		if ($includes && $includes ne $oldincludes) {
			&$first_print("Enabling server-side includes ..");
			$err = &save_domain_web_ssi($d, $includes);
			&$second_print($err ? ".. failed : $err" : ".. done");
			}
		elsif (!$includes) {
			&$first_print("Disabling server-side includes ..");
			$err = &save_domain_web_ssi($d, undef);
			&$second_print($err ? ".. failed : $err" : ".. done");
			}
		}

	if ($defwebsite) {
		# Make this site the default, by re-ordering the Apache config
		&$first_print("Making website the default ..");
		if (!$d->{'alias'} || $d->{'alias_mode'} != 1) {
			$err = &set_default_website($d);
			if ($err) {
				&$second_print(".. failed : $err");
				}
			else {
				&$second_print(".. done");
				}
			# Clear all left-frame links caches, as links to
			# Apache may no longer be valid
			&clear_links_cache();
			}
		else {
			&$second_print(".. not possible for alias domains");
			}
		}

	if ($accesslog && !$d->{'alias'}) {
		# Change access log file location
		$dom_accesslog = &substitute_domain_template($accesslog, $d);
		&$first_print("Changing access log to $dom_accesslog ..");
		$err = &change_access_log($d, $dom_accesslog);
		&$second_print($err ? ".. failed : $err" : ".. done");
		}
	if ($errorlog && !$d->{'alias'}) {
		# Change error log file location
		$dom_errorlog = &substitute_domain_template($errorlog, $d);
		&$first_print("Changing error log to $dom_errorlog ..");
		$err = &change_error_log($d, $dom_errorlog);
		&$second_print($err ? ".. failed : $err" : ".. done");
		}

	# Update Webmin permissions to cover new log location
	if (($errorlog || $accesslog) && !$d->{'alias'} && !$d->{'parent'}) {
		&refresh_webmin_user($d);
		}

	if ($htmldir && !$d->{'alias'} && !$d->{'subdom'} &&
	    $d->{'public_html_dir'} !~ /\.\./) {
		# Change HTML directory for a regular domain
		&$first_print("Changing documents directory to $htmldir ..");
		$err = &set_public_html_dir($d, $htmldir, $htmldirmove);
		&$second_print($err ? ".. failed : $err" : ".. done");
		}
	elsif ($subprefix && $d->{'subdom'}) {
		# Change HTML directory for a sub-domain
		&$first_print(
		  "Changing sub-domain documents directory to $subprefix ..");
		my $newd = { %$d };
		$newd->{'subprefix'} = $subprefix;
		delete($newd->{'public_html_dir'});
		delete($newd->{'public_html_path'});
		$htmldir = &public_html_dir($newd, 1);
		$err = &set_public_html_dir($d, $htmldir, $htmldirmove);
		if (!$err) {
			$d->{'subprefix'} = $subprefix;
			}
		&$second_print($err ? ".. failed : $err" : ".. done");
		}

	if ($fixhtmldir) {
		# Update HTML directory from actual configs
		&$first_print("Correcting documents directory ..");
		&find_html_cgi_dirs($d);
		&$second_print(".. set to $d->{'public_html_path'}");
		}

	# Change web ports
	foreach my $pd ($d, &get_domain_by("alias", $d->{'id'})) {
		if ($port) {
			$pd->{'web_port'} = $port;
			}
		if ($sslport) {
			$pd->{'web_sslport'} = $sslport;
			}
		if ($urlport) {
			$pd->{'web_urlport'} = $urlport;
			}
		if ($urlsslport) {
			$pd->{'web_urlsslport'} = $urlsslport;
			}
		if ($pd->{'alias'}) {
			&save_domain($pd);
			}
		}

	if (defined($proxy) || defined($framefwd) || $port || $sslport) {
		# Update website feature
		$p = &domain_has_website($d);
		if ($p eq 'web') {
			# Core website feature
			&modify_web($d, $oldd);
			if ($d->{'ssl'}) {
				&modify_ssl($d, $oldd);
				}
			}
		else {
			# Via plugin call
			&plugin_call($p, "feature_modify", $d, $oldd);
			}
		}

	if ($fixoptions) {
		# Fix Options to support Apache 2.4
		foreach my $p ($d->{'web_port'},
			       $d->{'ssl'} ? ($d->{'web_sslport'}) : ()) {
			&$first_print("Fixing Options directives for port $p ..");
			my ($virt, $vconf, $conf) = &get_apache_virtual($d->{'dom'}, $p);
			if ($virt) {
				my $c = &fix_options_directives($vconf, $conf, 1);
				if ($c) {
					&$second_print(".. fixed $c directives");
					}
				else {
					&$second_print(".. no fixes needed");
					}
				}
			else {
				&$second_print(".. no Virtualhost found!");
				}
			}
		}

	if (defined($renew)) {
		# Change let's encrypt renewal period
		$d->{'letsencrypt_renew'} = $renew;
		}

	if (&domain_has_ssl_cert($d) && $breakcert) {
		&$first_print("Breaking SSL certificate sharing ..");
		if (!$d->{'ssl_same'}) {
			&$second_print(".. not using a shared cert");
			}
		else {
			my $same = &get_domain($d->{'ssl_same'});
			if (!$same) {
				&$second_print(".. shared domain not found!");
				}
			else {
				&break_ssl_linkage($d, $same);
				&$second_print(".. done");
				}
			}
		}

	if (&domain_has_ssl_cert($d) && $linkcert) {
		&$first_print("Enabling SSL certificate sharing ..");
		if ($d->{'ssl_same'}) {
			my $same = &get_domain($d->{'ssl_same'});
			&$second_print(".. already sharing a cert with ".
				       &show_domain_name($same));
			}
		else {
			# Find a cert to link with, ideally a parent with the same owner
			my @sames = &find_matching_certificate_domain($d);
			my ($same) = grep { $_->{'user'} eq $d->{'user'} &&
					    !$_->{'parent'} } @sames;
			if (!$same) {
				($same) = grep { $_->{'user'} eq $d->{'user'} } @sames;
				}
			if (!@sames) {
				&$second_print(".. no domain to link with found");
				}
			elsif (!$same) {
				&$second_print(".. no domain with the same owner to link with found");
				}
			else {
				&link_matching_certificate($d, $same, 1);
				&$second_print(".. linked to ".
					&show_domain_name($same));
				}
			}
		}

	# Update SSL cert, key and CA paths
	my $ssl_changed = 0;
	my @beforecerts = &get_all_domain_service_ssl_certs($d);
	if (&domain_has_ssl_cert($d) && $ssl_cert) {
		my $dom_cert = $ssl_cert eq "default" ?
			&default_certificate_file($d, "cert") :
			&absolute_domain_path($d, $ssl_cert);
		&$first_print("Moving SSL cert to $dom_cert ..");
		if ($d->{'ssl_same'}) {
			&$second_print(".. not possible for shared certs");
			}
		elsif (&move_website_ssl_file($d, "cert", $dom_cert)) {
			$ssl_changed = 1;
			&$second_print(".. done");
			}
		else {
			&$second_print(".. no change needed");
			}
		}
	if (&domain_has_ssl_cert($d) && $ssl_key) {
		my $dom_key = $ssl_key eq "default" ?
			&default_certificate_file($d, "key") :
			&absolute_domain_path($d, $ssl_key);
		&$first_print("Moving SSL key to $dom_key ..");
		if ($d->{'ssl_same'}) {
			&$second_print(".. not possible for shared certs");
			}
		elsif (&move_website_ssl_file($d, "key", $dom_key)) {
			&move_website_ssl_file($d, "combined",
				&relative_certificate_file($dom_key, "combined"));
			&move_website_ssl_file($d, "everything",
				&relative_certificate_file($dom_key, "everything"));
			$ssl_changed = 1;
			&$second_print(".. done");
			}
		else {
			&$second_print(".. no change needed");
			}
		}
	if (&domain_has_ssl_cert($d) && $ssl_ca) {
		my $dom_ca = $ssl_ca eq "default" ?
			&default_certificate_file($d, "ca") :
			&absolute_domain_path($d, $ssl_ca);
		&$first_print("Moving SSL CA cert to $dom_ca ..");
		if ($d->{'ssl_same'}) {
			&$second_print(".. not possible for shared certs");
			}
		elsif (&move_website_ssl_file($d, "ca", $dom_ca)) {
			$ssl_changed = 1;
			&$second_print(".. done");
			}
		else {
			&$second_print(".. no change needed");
			}
		}
	if ($ssl_changed) {
		# Update other services using the cert
		&update_all_domain_service_ssl_certs($d, \@beforecerts);
		}

	if ($tlsa && $d->{'dns'}) {
		# Resync TLSA records
		&$first_print("Updating TLSA DNS records ..");
		&sync_domain_tlsa_records($d);
		&$second_print(".. done");
		}

	if (defined($cgimode)) {
		# Switch to fcgiwrap or suexec mode
		if ($cgimode) {
			&$first_print(
				"Switching to $cgimode for CGI scripts ..");
			}
		else {
			&$first_print("Turning off support for CGI scripts ..");
			}
		$err = &save_domain_cgi_mode($d, $cgimode);
		if ($err) {
			&$second_print(".. failed : $err");
			}
		else {
			&$second_print(".. done");
			}
		}

	# Change HTTP protocols
	if ($protocols) {
		if (@$protocols) {
			&$first_print("Updating HTTP protocols to ".
				      join(" ", @$protocols)." ..");
			}
		else {
			&$first_print("Updating HTTP protocols to defaults ..");
			}
		$canprots = &get_domain_supported_http_protocols($d);
		%canprots = map { $_, 1 } @$canprots;
		@cannotprots = grep { !$canprots{$_} } @$protocols;
		if (@cannotprots) {
			&$second_print(".. protocol ".join(" ", @cannotprots).
				       " is not supported");
			}
		elsif ($err = &save_domain_http_protocols($d, $protocols)) {
			&$second_print(".. failed : $err");
			}
		else {
			&$second_print(".. done");
			}
		}

	# Update Apache directives
	if ($d->{'web'} && (@add_dirs || @remove_dirs) && !$d->{'alias'}) {
		&$first_print("Updating Apache directives ..");
		&require_apache();
		my @ports = ( $d->{'web_port'},
			      $d->{'ssl'} ? ( $d->{'web_sslport'} ) : ( ) );
		foreach my $p (@ports) {
			my ($virt, $vconf, $conf) =
				&get_apache_virtual($d->{'dom'}, $p);
			next if (!$virt);
			foreach my $a (@add_dirs) {
				my @old = &apache::find_directive(
					$a->[0], $vconf);
				push(@old, $a->[1]);
				&apache::save_directive(
					$a->[0], \@old, $vconf, $conf);
				}
			foreach my $a (@remove_dirs) {
				my @old;
				if ($a->[1] ne '') {
					@old = &apache::find_directive(
						$a->[0], $vconf);
					@old = grep { $_ ne $a->[1] } @old;
					}
				&apache::save_directive(
					$a->[0], \@old, $vconf, $conf);
				}
			&flush_file_lines($virt->{'file'});
			}
		&register_post_action(\&restart_apache);
		&$second_print(".. added ".scalar(@add_dirs)." and removed ".
			       scalar(@remove_dirs));
		}

	# Remove all mod_php directives
	if ($fix_mod_php && $d->{'web'} && !$d->{'alias'}) {
		&$first_print("Removing mod_php directives ..");
		my $c = &fix_mod_php_directives($d, $d->{'web_port'}, 1);
		if ($d->{'ssl'}) {
			$c += &fix_mod_php_directives($d, $d->{'web_sslport'}, 1);
			}
		&$second_print(".. removed $c");
		}

	# Update PHP log file
	if (defined($phplog)) {
		my $dphplog = $phplog eq "" ? undef : $phplog;
		if ($dphplog eq "default") {
			$dphplog = &get_default_php_error_log($d);
			}
		if ($dphplog && $dphplog !~ /^\//) {
			$dphplog = $d->{'home'}.'/'.$dphplog;
			}
		if ($dphplog) {
			&$first_print("Changing PHP error log to $dphplog ..");
			}
		else {
			&$first_print("Removing PHP error log ..");
			}
		my $err = &save_domain_php_error_log($d, $dphplog);
		if ($err) {
			&$second_print(".. failed : $err");
			}
		else {
			&$second_print(".. done");
			}
		}

	# Update PHP mail setting
	if (defined($phpmail)) {
		if ($phpmail) {
			&$first_print("Allowing PHP scripts to send email ..");
			}
		else {
			&$first_print("Disallowing PHP scripts from sending email ..");
			}
		my $err = &save_php_can_send_mail($d, $phpmail);
		if ($err) {
			&$second_print(".. failed : $err");
			}
		else {
			&$second_print(".. done");
			}
		}

	# Update www redirect
	if (defined($wwwredir)) {
		my @r = grep { &is_www_redirect($d, $_) } &list_redirects($d);
		my $oldredir = @r ? &is_www_redirect($d, $r[0]) : undef;
		if ($oldredir != $wwwredir) {
			&$first_print(
			    $wwwredir == 0 ?
			      "Disabling redirect to canonical domain .." :
			    $wwwredir == 1 ?
			      "Adding redirect to non-www domain .." :
			    $wwwredir == 2 ?
			      "Adding redirect to www domain .." :
			      "Adding redirect from sub-domains to domain ..");
			foreach my $r (@r) {
				$err ||= &delete_redirect($d, $r);
				last if ($err);
				}
			foreach my $r (&get_redirect_by_mode($d, $wwwredir)) {
				$err ||= &create_redirect($d, $r);
				last if ($err);
				}
			&$second_print($err ? ".. failed : $err" : ".. done");
			}
		}

	if (defined($proxy) || defined($framefwd) || $htmldir ||
	    $port || $sslport || $urlport || $sslurlport || $mode || $version ||
	    defined($children_no_check) || defined($renew) || $breakcert ||
	    $linkcert || $fixhtmldir || defined($fcgiwrap) ||
	    defined($phplog) || defined($fcgiwrap) || $ssl_changed) {
		# Save the domain
		&$first_print($text{'save_domain'});
		&save_domain($d);
		&$second_print($text{'setup_done'});
		}

	&$outdent_print();
	&$second_print(".. done");
	}

foreach $d (@doms) {
	&release_lock_logrotate($d) if ($d->{'logrotate'} &&
				        ($accesslog || $errorlog));
	&release_lock_dns($d) if ($d->{'dns'} && 
				  (defined($webmail) || defined($matchall)));
	&release_lock_web($d) if ($d->{'web'});
	&unlock_domain($d);
	}
&run_post_actions();
&virtualmin_api_log(\@OLDARGV);

sub usage
{
print "$_[0]\n\n" if ($_[0]);
print "Changes web server settings for one or more domains.\n";
print "\n";
print "virtualmin modify-web --domain name | --all-domains\n";
print "                     [--mode mod_php|cgi|fcgid|fpm | --default-mode]\n";
print "                     [--php-children|--php-children-no-check number | --no-php-children]\n";
print "                     [--php-version num]\n";
print "                     [--php-timeout seconds | --no-php-timeout]\n";
print "                     [--php-fpm-port | --php-fpm-socket]\n";
print "                     [--php-fpm-mode dynamic|static|ondemand]\n";
print "                     [--php-log filename | --no-php-log | --default-php-log]\n";
print "                     [--php-mail | --no-php-mail]\n";
print "                     [--cleanup-mod-php]\n";
print "                     [--proxy http://... | --no-proxy]\n";
print "                     [--framefwd http://... | --no-framefwd]\n";
print "                     [--frametitle \"title\" ]\n";
if ($supports_ruby) {
	print "                     [--ruby-mode none|mod_ruby|cgi|fcgid]\n";
	}
if ($virtualmin_pro) {
	print "                     [--content text|filename]\n";
	}
if (&has_webmail_rewrite($d)) {
	print "                     [--webmail | --no-webmail]\n";
	}
print "                     [--matchall | --no-matchall]\n";
print "                     [--includes extension | --no-includes]\n";
print "                     [--default-website]\n";
print "                     [--access-log log-path]\n";
print "                     [--error-log log-path]\n";
print "                     [--document-dir subdirectory |\n";
print "                      --move-document-dir subdirectory |\n";
print "                      --subprefix subdirectory |\n";
print "                      --move-subprefix subdirectory |\n";
print "                      --fix-document-dir]\n";
print "                     [--port number] [--ssl-port number]\n";
print "                     [--url-port number] [--ssl-url-port number]\n";
print "                     [--fix-options]\n";
print "                     [--letsencrypt-renew | --no-letsencrypt-renew]\n";
print "                     [--break-ssl-cert | --link-ssl-cert]\n";
print "                     [--enable-fcgiwrap | --enable-suexec |\n";
print "                      --disable-cgi]\n";
print "                     [--sync-tlsa]\n";
print "                     [--add-directive \"name value\"]\n";
print "                     [--remove-directive \"name value\"]\n";
print "                     [--protocols \"proto ..\" | --default-protocols]\n";
print "                     [--ssl-cert file | --default-ssl-cert]\n";
print "                     [--ssl-key file | --default-ssl-key]\n";
print "                     [--ssl-ca file | --default-ssl-ca]\n";
print "                     [--default-ssl-paths]\n";
print "                     [--www-to-domain | --domain-to-www |\n";
print "                      --subdomain-to-domain | --no-redirect]\n";
exit(1);
}

