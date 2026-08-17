#!/usr/local/bin/perl

=head1 unalias-domain.pl

Convert an alias domain into a sub-server.

This command can be used to convert an alias server into a sub-server, so
that it can have its own separate web pages, mailboxes and mail aliases.
Once it is run, the former alias domain will no longer serve the same web
pages as the target virtual server, and will no longer forward email.

This command takes only one parameter, which is C<--domain> followed by the
domain name of the sub-domain to convert.

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
	$0 = "$pwd/unalias-domain.pl";
	require './virtual-server-lib.pl';
	$< == 0 || die "unalias-domain.pl must be run as root";
	}
@OLDARGV = @ARGV;

&set_all_text_print();

# Parse command-line args
while(@ARGV > 0) {
	my $a = shift(@ARGV);
	if ($a eq "--domain") {
		$domain = lc(shift(@ARGV));
		}
	elsif ($a eq "--multiline") {
		$multiline = 1;
		}
	elsif ($a eq "--help") {
		&usage();
		}
	else {
		&usage("Unknown parameter $a");
		}
	}

# Find the domain
$domain || usage("No domain specified");
$d = &get_remote_api_domain("dom", $domain);
$d || usage("Virtual server $domain does not exist.");
$d->{'alias'} || &usage("The given virtual server is not an alias");
$d->{'parent'} || &master_admin() ||
	&usage("Only a sub-server alias can be converted");

# An alias becomes a real sub-server, so it counts against that limit
if (!&master_admin()) {
	my ($dleft, $dreason, $dmax) = &count_domains("realdoms");
	$dleft == 0 && &usage("You have reached the maximum of $dmax ".
			      "virtual servers that can be created");
	}

# Call the move function
&$first_print(&text('unalias_doing', "<tt>$d->{'dom'}</tt>"));
&$indent_print();
$ok = &unalias_virtual_server($d);
&$outdent_print();
&run_post_actions_silently();
if ($ok) {
	&$second_print($text{'setup_done'});
	&virtualmin_api_log(\@OLDARGV, $d);
	}
else {
	&$second_print($text{'unalias_failed'});
	}

sub usage
{
print $_[0],"\n\n" if ($_[0]);
print "Converts an alias virtual server into a sub-server.\n";
print "\n";
print "virtualmin unalias-domain --domain domain.name\n";
exit(1);
}


