#!/usr/local/bin/perl
# Create, update or delete a website redirect

require './virtual-server-lib.pl';
&ReadParse();
&licence_status();
$d = &get_domain($in{'dom'});
&can_edit_domain($d) && &can_edit_redirect() ||
	&error($text{'redirects_ecannot'});
&has_web_redirects($d) || &error($text{'redirects_eweb'});
&error_setup($text{'redirect_err'});
&obtain_lock_web($d);
if (!$in{'new'}) {
	($r) = grep { $_->{'id'} eq $in{'old'} } &list_redirects($d);
	$r || &error($text{'redirect_egone'});
	$oldr = { %$r };
	}

if ($in{'delete'}) {
	# Just delete it
	$err = &delete_redirect($d, $r);
	&error($err) if ($err);
	}
else {
	# Parse destination input into one of the existing redirect modes
	$in{'dest'} =~ s/^\s+//; $in{'dest'} =~ s/\s+$//;
	$in{'dest'} =~ /\S/ || &error($text{'redirect_edest'});

	# Be tolerant of existing redirects set without a leading / (like pma/
	# instead of /pma/)
	if ($in{'dest'} =~ /^\S+$/ &&
		$in{'dest'} !~ /^\// &&
		$in{'dest'} !~ /^(http|https):\/\//) {
		$in{'dest'} = "/".$in{'dest'};
		}

	if ($in{'dest'} =~ /^(http|https):\/\/%\{HTTP_HOST\}(\/\S*)?$/) {
		$in{'mode'} = 2;
		$in{'dproto'} = $1;
		$in{'dpath'} = $2 || "/";
		}
	elsif ($in{'dest'} =~ /^(http|https):\/\/\S+$/) {
		$in{'mode'} = 0;
		}
	elsif ($in{'dest'} =~ /^\/\S*$/) {
		my $rroot = &get_redirect_root($d);
		my $actualdir = $in{'dest'};
		if ($actualdir =~ s/\$.*$//) {
			# If path contains $1, reduce to parent dir
			$actualdir =~ s/\/[^\/]*$//;
			}
		my $looks_dir = 0;
		# Treat paths under domain home/redirect root as filesystem
		# alias intent
		if ($d->{'home'} &&
			($in{'dest'} eq $d->{'home'} ||
			$in{'dest'} =~ /^\Q$d->{'home'}\E\//)) {
			$looks_dir = 1;
			}
		elsif ($rroot && $rroot ne "/" &&
			($in{'dest'} eq $rroot ||
			$in{'dest'} =~ /^\Q$rroot\E\//)) {
			$looks_dir = 1;
			}
		# Treat as directory alias only if it really exists on disk
		if ($actualdir && -d $actualdir &&
			(!$rroot || &is_under_directory($rroot, $in{'dest'}))) {
			$in{'mode'} = 1;
			$in{'dir'} = $in{'dest'};
			}
		elsif ($looks_dir) {
			# Looks like a filesystem alias path, so fail fast
			# if the destination directory is invalid/missing
			!$actualdir || -d $actualdir ||
				&error(&text('redirect_edir3', $actualdir));
			!$rroot || &is_under_directory($rroot, $in{'dest'}) ||
				&error(&text('redirect_edir2', $rroot));
			}
		else {
			$in{'mode'} = 3;
			$in{'urlpath'} = $in{'dest'};
			}
		}

	# Parse protocols selector
	if (defined($in{'proto_mode'})) {
		if ($in{'proto_mode'} eq 'both') {
			$in{'http'} = 1;
			$in{'https'} = 1;
			}
		elsif ($in{'proto_mode'} eq 'http') {
			$in{'http'} = 1;
			$in{'https'} = 0;
			}
		elsif ($in{'proto_mode'} eq 'https') {
			$in{'http'} = 0;
			$in{'https'} = 1;
			}
		else {
			&error($text{'redirect_eproto'});
			}
		}

	# Validate inputs
	if ($in{'path'} =~ /^(http|https):\/\/([^\/]+)(\/\S*)$/) {
		# URL, check the domain and save the path
		lc($2) eq $d->{'dom'} ||
		   lc($2) eq "www.".$d->{'dom'} ||
		     &error(&text('redirect_epath2', $d->{'dom'}));
		$r->{'path'} = $3;
		}
	elsif ($in{'path'} =~ /^\/\S*$/ || $in{'path'} =~ /^\^\S*/) {
		# Just a path or a regexp
		$r->{'path'} = $in{'path'};
		}
	else {
		&error($text{'redirect_epath'});
		}
	if ($in{'mode'} == 0) {
		# Redirect to a URL on another host
		$in{'dest'} =~ /^(http|https):\/\/\S+$/ ||
			&error($text{'redirect_eurl'});
		# Normalize IDN hostname to ASCII/punycode if needed
		my ($phost) = &parse_http_url($in{'dest'});
		$phost || &error($text{'redirect_eurl'});
		my $ahost = &parse_domain_name($phost);
		if ($ahost && $ahost ne $phost) {
			$in{'dest'} =~ s/\Q$phost\E/$ahost/;
			}
		$r->{'dest'} = $in{'dest'};
		$r->{'alias'} = 0;
		}
	elsif ($in{'mode'} == 3) {
		# Redirect to a URL path on this host
		$in{'urlpath'} =~ /^\/\S*$/ ||
			&error($text{'redirect_eurlpath'});
		$r->{'dest'} = $in{'urlpath'};
		$r->{'alias'} = 0;
		if ($in{'path'} eq '/' && $in{'regexp'} != 2 &&
		    $in{'http'} && $in{'https'}) {
			&error($text{'redirect_eurlpath2'});
			}
		}
	elsif ($in{'mode'} == 2) {
		# Redirect to a URL on this host
		$in{'dpath'} =~ /^\/\S*$/ || &error($text{'redirect_eurl'});
		$r->{'dest'} = $in{'dproto'}.'://%{HTTP_HOST}'.$in{'dpath'};
		$r->{'alias'} = 0;
		}
	else {
		# Alias to a directory
		$in{'dir'} =~ /^\/\S+$/ ||
			&error($text{'redirect_edir'});
		$actualdir = $in{'dir'};
		if ($actualdir =~ s/\$.*$//) {
			# If path contains $1, reduce to parent dir
			$actualdir =~ s/\/[^\/]*$//;
			}
		!$actualdir || -d $actualdir ||
			&error(&text('redirect_edir3', $actualdir));

		# For directory aliases, mirror source path slash style, i.e.
		# when source ends with /, destination should also end with /
		# to avoid path-join issues in Alias mappings.
		my $normdir = $in{'dir'};
		if ($normdir !~ /\/$/ && $normdir !~ /\$/ &&
		    $actualdir && -d $actualdir && $r->{'path'} =~ /\/$/) {
			$normdir .= "/";
			}

		if ($in{'new'} || $r->{'dest'} ne $normdir) {
			$rroot = &get_redirect_root($d);
			&is_under_directory($rroot, $normdir) ||
				&error(&text('redirect_edir2', $rroot));
			}
		$r->{'dest'} = $normdir;
		$r->{'alias'} = 1;
		}
	if ($in{'mode'} == 0 || $in{'mode'} == 2 || $in{'mode'} == 3) {
		# Save redirect code for URL redirects
		$in{'code'} ||= 302;
		$r->{'code'} = $in{'code'};
		$in{'code'} =~ /^\d{3}$/ &&
		    $in{'code'} >= 300 && $in{'code'} < 400 ||
			&error($text{'redirect_ecode'});
		}
	else {
		# Aliases do not use HTTP redirect status codes
		delete($r->{'code'});
		}
	$r->{'regexp'} = $in{'regexp'} == 1 ? 1 : 0;
	$r->{'exact'} = $in{'regexp'} == 2 ? 1 : 0;
	$r->{'http'} = $in{'http'};
	$r->{'https'} = $in{'https'};

	# Hostname filter mode
	# 0 = any hostname, 1 = selected hostname, 2 = manually specified
	if (&has_web_host_redirects($d)) {
		my $hmode = int($in{'host_mode'});

		if ($hmode == 0) {
			delete($r->{'host'});
			delete($r->{'hostregexp'});
			}
		elsif ($hmode == 1) {
			my $host = $in{'host_pick'};
			$host =~ s/^\s+// if (defined($host));
			$host =~ s/\s+$// if (defined($host));
			$host =~ /^\S+$/ || &error($text{'redirect_ehost'});
			# Selected hostnames are always exact matches
			$r->{'host'} = $host;
			$r->{'hostregexp'} = 0;
			}
		elsif ($hmode == 2) {
			my $host = $in{'host'};
			$host =~ /\S/ || &error($text{'redirect_ehost'});
			$host =~ s/^\s+//;
			$host =~ s/\s+$//;
			if ($host !~ /[\*\?\[\]\(\)\{\}\+\^\$\|\\]/) {
				# Normalize unicode hostnames to ASCII/punycode.
				$host = &parse_domain_name($host);
				$host =~ /^[a-z0-9\.\_\-]+$/i ||
					&error($text{'redirect_ehost'});
				}
			if ($host =~ /^[a-z0-9\.\_\-]+$/i) {
				# Plain hostname with exact host match
				$r->{'host'} = $host;
				$r->{'hostregexp'} = 0;
				}
			elsif ($host =~ /^[a-z0-9\.\_\-\*\?]+$/i) {
				# Shell-like wildcard hostname from ServerAlias
				# is converted to a safe anchored regex
				my $re = quotemeta($host);
				$re =~ s/\\\*/.*/g;
				$re =~ s/\\\?/./g;
				$r->{'host'} = "^".$re."\$";
				$r->{'hostregexp'} = 1;
				}
			else {
				# Non-plain, no whitespace so treat as regex
				# pattern
				$host =~ /^\S+$/ ||
					&error($text{'redirect_ehost'});
				$r->{'host'} = $host;
				$r->{'hostregexp'} = 1;
				}
			}
		else {
			&error($text{'redirect_ehost'});
			}
		}
	$r = &add_wellknown_redirect($r);

	# Create or update
	if ($in{'new'}) {
		$err = &create_redirect($d, $r);
		}
	else {
		$err = &modify_redirect($d, $r, $oldr);
		}
	&error($err) if ($err);
	}

# Restart Apache and log
&release_lock_web($d);
&set_all_null_print();
&run_post_actions();
&webmin_log($in{'new'} ? 'create' : $in{'delete'} ? 'delete' : 'modify',
	    "redirect", $r->{'path'}, { 'dom' => $d->{'dom'} });

&redirect("list_redirects.cgi?dom=$in{'dom'}");
