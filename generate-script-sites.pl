#!/usr/local/bin/perl
# Output a list of websites used by all scripts

package virtual_server;
if (!$module_name) {
	$main::no_acl_check++;
	$ENV{'WEBMIN_CONFIG'} ||= "/etc/webmin";
	$ENV{'WEBMIN_VAR'} ||= "/var/webmin";
	if ($0 =~ /^(.*\/)[^\/]+$/) {
		chdir($1);
		}
	chop($pwd = `pwd`);
	$0 = "$pwd/generate-script-sites.pl";
	require './virtual-server-lib.pl';
	$< == 0 || die "generate-script-sites.pl must be run as root";
	}

# Parse command-line args
while(@ARGV) {
	$a = shift(@ARGV);
	if ($a eq "--firewall") {
		$firewall = 1;
		}
	else {
		push(@scripts, $a);
		}
	}

if (!@scripts) {
	@scripts = &list_available_scripts();
	}

@rv = ( );
foreach $s (@scripts) {
	$script = &get_script($s);
	next if (!$script->{'enabled'});

	$d = { 'dom' => 'example.com' };
	foreach $ver (@{$script->{'versions'}}) {
		@files = &{$script->{'files_func'}}($d, $ver, undef, undef);
		foreach $url (map { $_->{'url'} } @files) {
			# Work out URLs
			@urls = ( $url );
			if ($url =~ /^http:\/\/[^\.]+.dl.sourceforge.net\/sourceforge\/([^\/]+)\/(.*)$/ ||
			    $url =~ /^http:\/\/prdownloads.sourceforge.net\/([^\/]+)\/(.*)$/) {
				# OSDN url .. get mirrors
				local ($project, $file) = ($1, $2);
				local @mirrors = &list_osdn_mirrors($project, $file);
				push(@urls, map { $_->{'url'} } @mirrors);
				}

			# Extract hostnames
			foreach $url (@urls) {
				($host) = &parse_http_url($url);
				push(@rv, $host) if ($host);
				}
			}
		}
	}

foreach $h (&unique(@rv)) {
	if ($firewall) {
		print "-A FORWARD -d $h -m tcp --dport 80 -j ACCEPT\n";
		}
	else {
		print $h,"\n";
		}
	}

