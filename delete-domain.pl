#!/usr/local/bin/perl

=head1 delete-domain.pl

Delete one virtual server

To delete a server (and all of its sub-servers and alias domains) from the
system, use this program. Its only required parameter is C<--domain> , which must
be followed by the domain name of the server to remove. The C<--only> option can
be used to not actually delete the server, but instead simply remove it from
the control of Virtualmin.

Be careful with this program, as unlike the server deletion function in the
Virtualmin web interface, it will NOT prompt for confirmation!

=cut

package virtual_server;
if (!$module_name) {
	$main::no_acl_check++;
	$ENV{'WEBMIN_CONFIG'} ||= "/etc/webmin";
	$ENV{'WEBMIN_VAR'} ||= "/var/webmin";
	if ($0 =~ /^(.*\/)[^\/]+$/) {
		chdir($1);
		}
	chop($pwd = `pwd`);
	$0 = "$pwd/delete-domain.pl";
	require './virtual-server-lib.pl';
	$< == 0 || die "delete-domain.pl must be run as root";
	}
@OLDARGV = @ARGV;

&set_all_text_print();

# Parse command-line args
while(@ARGV > 0) {
	local $a = shift(@ARGV);
	if ($a eq "--domain") {
		$domain = lc(shift(@ARGV));
		}
	elsif ($a eq "--only") {
		$only = 1;
		}
	elsif ($a eq "--pre-command") {
		$precommand = shift(@ARGV);
		}
	elsif ($a eq "--post-command") {
		$postcommand = shift(@ARGV);
		}
	else {
		&usage("Unknown option $a");
		}
	}

# Find the domain
$domain || usage();
$dom = &get_domain_by("dom", $domain);
$dom || &usage("Virtual server $domain does not exist");

# Kill it!
print "Deleting virtual server $domain ..\n\n";
$config{'pre_command'} = $precommand if ($precommand);
$config{'post_command'} = $postcommand if ($postcommand);
$err = &delete_virtual_server($dom, $only);
if ($err) {
	print "$err\n";
	exit 1;
	}
&virtualmin_api_log(\@OLDARGV, $dom);
print "All done!\n";

sub usage
{
print $_[0],"\n\n" if ($_[0]);
print "Deletes an existing Virtualmin virtual server and all sub-servers,\n";
print "mailboxes and alias domains.\n";
print "\n";
print "usage: delete-domain.pl  --domain domain.name\n";
print "                         [--only]\n";
exit(1);
}


