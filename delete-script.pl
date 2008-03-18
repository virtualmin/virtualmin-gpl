#!/usr/local/bin/perl
# Removes a script from a virtual server

package virtual_server;
if (!$module_name) {
	$main::no_acl_check++;
	$ENV{'WEBMIN_CONFIG'} ||= "/etc/webmin";
	$ENV{'WEBMIN_VAR'} ||= "/var/webmin";
	if ($0 =~ /^(.*\/)[^\/]+$/) {
		chdir($1);
		}
	chop($pwd = `pwd`);
	$0 = "$pwd/delete-script.pl";
	require './virtual-server-lib.pl';
	$< == 0 || die "delete-script.pl must be run as root";
	}
&foreign_require("mailboxes", "mailboxes-lib.pl");

$first_print = \&first_text_print;
$second_print = \&second_text_print;

# Parse command-line args
while(@ARGV > 0) {
	local $a = shift(@ARGV);
	if ($a eq "--domain") {
		$domain = shift(@ARGV);
		}
	elsif ($a eq "--type") {
		$sname = shift(@ARGV);
		}
	elsif ($a eq "--id") {
		$id = shift(@ARGV);
		}
	else {
		&usage();
		}
	}

# Validate args
$domain || &usage();
$d = &get_domain_by("dom", $domain);
$d || usage("Virtual server $domain does not exist");

# Find the script
$id || $sname || usage("Either the --id or --type parameters must be given");
@scripts = &list_domain_scripts($d);
if ($id) {
	($sinfo) = grep { $_->{'id'} eq $id } @scripts;
	$sinfo || &usage("No script install with ID $id was found for this virtual server");
	}
else {
	@matches = grep { $_->{'name'} eq $sname } @scripts;
	@matches || &usage("No script install for $sname was found for this virtual server");
	@matches == 1 || &usage("More than one script install for $sname was found for this virtual server. Use the --id option to specify the exact install");
	$sinfo = $matches[0];
	}

# Remove it
$script = &get_script($sinfo->{'name'});
&$first_print(&text('scripts_uninstalling', $script->{'desc'},
					    $sinfo->{'version'}));
($ok, $msg) = &{$script->{'uninstall_func'}}($d, $sinfo->{'version'},
						 $sinfo->{'opts'});
if ($msg =~ /</) {
	$msg = &mailboxes::html_to_text($msg);
	$msg =~ s/^\s+//;
	$msg =~ s/\s+$//;
	}
print "$msg\n";
if ($ok) {
	&$second_print($text{'setup_done'});

	# Remove any custom PHP directory
	&clear_php_version($d, $sinfo);

	# Remove custom proxy path
	&delete_noproxy_path($d, $script, $sinfo->{'version'},
			     $sinfo->{'opts'});

	# Record script un-install in domain
	&remove_domain_script($d, $sinfo);

	&run_post_actions();
	}
else {
	&$second_print($text{'scripts_failed'});
	}

sub usage
{
print "$_[0]\n\n" if ($_[0]);
print "Un-installs a third-party script from some virtual server.\n";
print "\n";
print "usage: delete-script.pl --domain domain.name\n";
print "                        [--type name] | [--id number]\n";
exit(1);
}

