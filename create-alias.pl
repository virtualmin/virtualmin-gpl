#!/usr/local/bin/perl

=head1 create-alias.pl

Create a new mail alias

This command can be used to add a new email alias to a
virtual server. It takes three mandatory parameters : C<--domain> followed by the
domain name, C<--from> followed by the name of the alias within that domain, and
C<--to> followed by a destination address. For example, to create an alias for
sales@foo.com that delivers mail to the user joe, you could run :

  virtualmin create-alias --domain foo.com --from sales --to joe@foo.com

The C<--to> option can be given multiple times, to create more than one
destination for the alias. To create an alias for all addresses in the domain
that are not matched by another alias or mail user, use the option C<--from "*">
.

Aliases can have short descriptions associated with them, to explain
what the alias is for. To set one when creating, you can use the --desc
option followed by a one-line description.

To more easily create aliases with autoresponders, you should use the 
C<create-simple-alias> command, which is analagous to the simple alias
creation form in Virtualmin's web UI.

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
	$0 = "$pwd/create-alias.pl";
	require './virtual-server-lib.pl';
	$< == 0 || die "create-alias.pl must be run as root";
	}
@OLDARGV = @ARGV;

# Parse command-line args
&require_mail();
while(@ARGV > 0) {
	local $a = shift(@ARGV);
	if ($a eq "--domain") {
		$domain = shift(@ARGV);
		}
	elsif ($a eq "--from") {
		$from = shift(@ARGV);
		}
	elsif ($a eq "--to") {
		push(@to, shift(@ARGV));
		}
	elsif ($a eq "--desc") {
		$can_alias_comments ||
		  usage("Your mail server does not support alias descriptions");
		$cmt = shift(@ARGV);
		}
	elsif ($a eq "--multiline") {
		$multiline = 1;
		}
	else {
		&usage();
		}
	}
$from || &usage();
@to || &usage();

$d = &get_domain_by("dom", $domain);
$d || usage("Virtual server $domain does not exist");
$d->{'mail'} || usage("Virtual server $domain does not have email enabled");
$from =~ /\@/ && &usage("No domain name is needed in the --from parameter");
$d->{'aliascopy'} && &usage("Aliases cannot be edited in alias domains in copy mode");

# Check for clash
&obtain_lock_mail($d);
@aliases = &list_domain_aliases($d);
$email = $from eq "*" ? "\@$domain" : "$from\@$domain";
($clash) = grep { $_->{'from'} eq $email } @aliases;
$clash && &usage("An alias for the same email address already exists");

# Create it
$virt = { 'from' => $email,
	  'to' => \@to,
	  'cmt' => $cmt };
&create_virtuser($virt);
&sync_alias_virtuals($d);
&release_lock_mail($d);
&virtualmin_api_log(\@OLDARGV, $d);
&run_post_actions_silently();
print "Alias for $email created successfully\n";

sub usage
{
print "$_[0]\n\n" if ($_[0]);
print "Adds a mail alias to a virtual server.\n";
print "\n";
print "virtualmin create-alias --domain domain.name\n";
print "                        --from mailbox|\"*\"\n";
print "                       <--to address>+\n";
if ($can_alias_comments) {
	print "                        [--desc \"Comment text\"]\n";
	}
exit(1);
}

