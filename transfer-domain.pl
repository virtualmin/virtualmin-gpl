#!/usr/local/bin/perl

=head1 transfer-domain.pl

Move a virtual server to another system.

XXX

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
	$0 = "$pwd/transfer-domain.pl";
	require './virtual-server-lib.pl';
	$< == 0 || die "transfer-domain.pl must be run as root";
	}
@OLDARGV = @ARGV;
&set_all_text_print();

# Parse command-line args
while(@ARGV > 0) {
	local $a = shift(@ARGV);
	if ($a eq "--domain") {
		$domain = lc(shift(@ARGV));
		}
	elsif ($a eq "--host") {
		$desthost = shift(@ARGV);
		&to_ipaddress($desthost) || &to_ip6address($desthost) ||
			&usage("Destination system cannot be resolved");
		}
	elsif ($a eq "--pass") {
		$destpass = shift(@ARGV);
		}
	elsif ($a eq "--delete") {
		$delete = 1;
		}
	elsif ($a eq "--disable") {
		$disable = 1;
		}
	elsif ($a eq "--multiline") {
		$multiline = 1;
		}
	else {
		&usage("Unknown parameter $a");
		}
	}

# Validate params
$domain || &usage("No domain to move specified");
$desthost || &usage("No destination hostname specified");
$disable && $delete && &usage("Only one of --disable or --delete can be given");
$d = &get_domain_by("dom", $domain);
$d || usage("Virtual server $domain does not exist.");

# Validate transfer target
$err = &validate_transfer_host($d, $desthost, $destpass);
&usage($err) if ($err);

# Call the transfer function
&$first_print(&text('transfer_doing', $d->{'dom'}, $desthost));
&$indent_print();
$ok = &transfer_virtual_server($d, $desthost, $destpass,
			       $delete ? 2 : $disable ? 1 : 0);
&$outdent_print();
if ($ok) {
	&$second_print($text{'setup_done'});
	&run_post_actions();
	&virtualmin_api_log(\@OLDARGV, $d);
	}
else {
	&$second_print($text{'move_failed'});
	}

sub usage
{
print $_[0],"\n\n" if ($_[0]);
print "Move a virtual server to another system.\n";
print "\n";
print "virtualmin transfer-domain --domain domain.name\n";
print "                           --desthost hostname\n";
print "                          [--destpass password]\n";
print "                          [--disable | --delete]\n";
exit(1);
}


