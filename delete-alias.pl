#!/usr/local/bin/perl

=head1 delete-alias.pl

Delete a mail alias

This program simply removes a single mail alias from a virtual server. It
takes only two parameters, C<--domain> to specify the server domain name, and
C<--from> to specify the part of the alias before the @. Be careful using it, as
it does not prompt for confirmation before deleting. To delete the catchall
alias for a domain, use the option C<--from "*">.

No program exists for updating existing aliases, but the same thing can be
achieved by using the C<delete-alias> and C<create-alias> commands to remove
and re-create an alias with new settings.

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
	$0 = "$pwd/delete-alias.pl";
	require './virtual-server-lib.pl';
	$< == 0 || die "delete-alias.pl must be run as root";
	}
@OLDARGV = @ARGV;

# Parse command-line args
while(@ARGV > 0) {
	local $a = shift(@ARGV);
	if ($a eq "--domain") {
		$domain = shift(@ARGV);
		}
	elsif ($a eq "--from") {
		$from = shift(@ARGV);
		}
	elsif ($a eq "--multiline") {
		$multiline = 1;
		}
	else {
		&usage();
		}
	}
$from || &usage();

$d = &get_domain_by("dom", $domain);
$d || usage("Virtual server $domain does not exist");
$d->{'aliascopy'} && &usage("Aliases cannot be edited in alias domains in copy mode");

# Find the alias
&obtain_lock_mail($d);
@aliases = &list_domain_aliases($d);
$email = $from eq "*" ? "\@$domain" : "$from\@$domain";
($virt) = grep { $_->{'from'} eq $email } @aliases;
$virt || &usage("No alias for the email address $email exists");

# Delete it
if (defined(&get_simple_alias)) {
	$simple = &get_simple_alias($d, $virt);
	&delete_simple_autoreply($d, $simple) if ($simple);
	}
&delete_virtuser($virt);
&sync_alias_virtuals($d);
&release_lock_mail($d);
&virtualmin_api_log(\@OLDARGV, $d);
&run_post_actions_silently();
print "Alias for $email deleted successfully\n";

sub usage
{
print "$_[0]\n\n" if ($_[0]);
print "Deletes a mail alias from a virtual server.\n";
print "\n";
print "virtualmin delete-alias --domain domain.name\n";
print "                        --from mailbox|\"*\"\n";
exit(1);
}

