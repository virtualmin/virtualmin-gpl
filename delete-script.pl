#!/usr/local/bin/perl

=head1 delete-script.pl

Un-install one script from a virtual server

This program completely removes a third-party script from a server. It
takes the usual C<--domain> parameter to identifiy the server, and either
C<--id> followed by the install ID, or C<--type> followed by the script's short
name. The latter option is more convenient, but only works if there is only
one instance of the script in the virtual server. If multiple different versions
are installed, you can also use C<--version> to select a specific one to remove.

Be careful using this program, as it removes all data files, web pages and
database tables for the script, without asking for confirmation.

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
	$0 = "$pwd/delete-script.pl";
	require './virtual-server-lib.pl';
	$< == 0 || die "delete-script.pl must be run as root";
	}
@OLDARGV = @ARGV;
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
	elsif ($a eq "--version") {
		$ver = shift(@ARGV);
		}
	elsif ($a eq "--id") {
		$id = shift(@ARGV);
		}
	elsif ($a eq "--multiline") {
		$multiline = 1;
		}
	else {
		&usage("Unknown parameter $a");
		}
	}

# Validate args
$domain || &usage("No domain specified");
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
	if ($ver) {
		@matches = grep { $_->{'version'} eq $ver } @matches;
		}
	@matches || &usage("No script install for $sname was found for this virtual server");
	@matches == 1 || &usage("More than one script install for $sname was found for this virtual server. Use the --id option to specify the exact install, or --version to select a version");
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
	&virtualmin_api_log(\@OLDARGV, $d);
	}
else {
	&$second_print($text{'scripts_failed'});
	}

sub usage
{
print "$_[0]\n\n" if ($_[0]);
print "Un-installs a third-party script from some virtual server.\n";
print "\n";
print "virtualmin delete-script --domain domain.name\n";
print "                        [--type name --version number] |\n";
print "                        [--id number]\n";
exit(1);
}

