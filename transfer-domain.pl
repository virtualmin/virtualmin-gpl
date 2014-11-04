#!/usr/local/bin/perl

=head1 transfer-domain.pl

Move a virtual server to another system.

This command copies or moves a virtual server to another system, which
must also run Virtualmin. The server to move is specified with the C<--domain>
flag, and if a top-level server is given all sub-servers will be moved along
with it.

The target system is set with the C<--host> flag follow by the hostname or
IP of a system that is reachable via SSH. If the C<root> user requires a
password to login, the C<--pass> flag must also be given.

By default the domain is simply copied to the target system using Virtualmin's
backup and restore functions. However, if the C<--delete> flag is given it
will be remove from this system after being copied. Alternately, the 
C<--disable> flag can be used to disable the domain on the source system without
completely removing it.

If the C<--overwrite> flag is not given, this command will fail if the domain
already exists on the destination system. If you do expect it to exist, the
C<--delete-missing-files> flag will cause the restore to remove from the
destination domain any files that are not included in the backup.

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
		($desthostname) = split(/:/, $desthost);
		&to_ipaddress($desthostname) || &to_ip6address($desthostname) ||
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
	elsif ($a eq "--overwrite") {
		$overwrite = 1;
		}
	elsif ($a eq "--delete-missing-files") {
		$deletemissing = 1;
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
$err = &validate_transfer_host($d, $desthost, $destpass, $overwrite);
&usage($err) if ($err);

# Call the transfer function
my @subs = ( &get_domain_by("parent", $d->{'id'}),
	     &get_domain_by("alias", $d->{'id'}) );
&$first_print(&text(@subs ? 'transfer_doing2' : 'transfer_doing',
		    $d->{'dom'}, $desthost, scalar(@subs)));
&$indent_print();
$ok = &transfer_virtual_server($d, $desthost, $destpass,
			       $delete ? 2 : $disable ? 1 : 0,
			       $deletemissing);
&$outdent_print();
if ($ok) {
	&$second_print($text{'setup_done'});
	&run_post_actions();
	&virtualmin_api_log(\@OLDARGV, $d);
	}
else {
	&$second_print($text{'transfer_failed'});
	}

sub usage
{
print $_[0],"\n\n" if ($_[0]);
print "Move a virtual server to another system.\n";
print "\n";
print "virtualmin transfer-domain --domain domain.name\n";
print "                           --host hostname\n";
print "                          [--pass password]\n";
print "                          [--disable | --delete]\n";
print "                          [--overwrite]\n";
print "                          [--delete-missing-files]\n";
exit(1);
}


