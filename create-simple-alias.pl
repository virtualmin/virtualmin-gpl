#!/usr/local/bin/perl

=head1 create-simple-alias.pl

Adds a mail alias to some domain, with simple parameters

This command allows aliases using autoresponders or other more complex
destination types to be created more easily. You must supply at least the
C<--domain> and C<--from> parameters, followed by a domain name and alias
name (without the @) respectively. The optional C<--desc> parameter can be
used to set a comment or description for the alias. To create an alias that
matches all email in the domain, use the option C<--from "*">.

To just forward email to some other address, the C<--forward> parameter can
be used. It can be given multiple times, and each instance must be followed by an email address.

To deliver directly to the inbox of some user (bypassing other forwarding),
use the C<--local> parameter, followed by a full username like C<jamie.somedomain>.

To bouce mail back to the sender, use the C<--bounce> flag. This is useful if you have a catchall address setup for the domain.

To setup an autoresponder, use the C<--autoreply> parameter followed by the text of the automatic reply message. The from address for automatica replies can be set with the optional (but highly recommended) C<--autoreply-from> flag, and the interval in hours between replies to the same address with the C<--autoreply-period> flag. For example :

  virtualmin create-simple-alias --domain something.com --from jamie --autoreply "Gone fishing" --autoreply-from jamie@something.com --autoreply-period 24

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
	$0 = "$pwd/create-simple-alias.pl";
	require './virtual-server-lib.pl';
	$< == 0 || die "create-simple-alias.pl must be run as root";
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
	elsif ($a eq "--forward") {
		$forward = shift(@ARGV);
		$forward =~ /^\S+\@\S+$/ ||
			&usage("Invalid email address for --forward");
		push(@forward, $forward);
		}
	elsif ($a eq "--bounce") {
		$bounce = 1;
		}
	elsif ($a eq "--local") {
		$local = shift(@ARGV);
		defined(getpwnam($local)) ||
			&usage("Missing or invalid local user for --local");
		}
	elsif ($a eq "--everyone") {
		$everyone = 1;
		}
	elsif ($a eq "--autoreply") {
		$autotext = shift(@ARGV);
		$autotext || &usage("Missing parameter for --autoreply");
		}
	elsif ($a eq "--autoreply-period") {
		$period = shift(@ARGV);
		$period =~ /^\d+$/ || &usage("Invalid parameter for --period");
		}
	elsif ($a eq "--autoreply-from") {
		$autofrom = shift(@ARGV);
		$autofrom =~ /^\S+\@\S+$/ ||
			&usage("Invalid email address for --autoreply-from");
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
		&usage("Unknown parameter $a");
		}
	}
$bounce || $local || @forward || $autotext || $everyone ||
	&usage("No destination specified");

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

# Create the simple object
$simple = { };
$simple->{'bounce'} = 1 if ($bounce);
$simple->{'everyone'} = 1 if ($everyone);
$simple->{'local'} = $local if ($local);
$simple->{'forward'} = \@forward;
if ($autotext) {
	$simple->{'auto'} = 1;
	$simple->{'autotext'} = $autotext;
	if ($period) {
		$simple->{'replies'} =
			&convert_autoreply_file($d, "replies-$from");
		$simple->{'period'} = $period;
		}
	if ($autofrom) {
		$simple->{'from'} = $autofrom;
		}
	}

# Create it
$virt = { 'from' => $email,
	  'cmt' => $cmt };
&save_simple_alias($d, $virt, $simple);
&create_virtuser($virt);
&sync_alias_virtuals($d);
&release_lock_mail($d);
&write_simple_autoreply($d, $simple);
&run_post_actions_silently();
&virtualmin_api_log(\@OLDARGV, $d);
print "Alias for $email created successfully\n";

sub usage
{
print "$_[0]\n\n" if ($_[0]);
print "Adds a simple mail alias to a virtual server.\n";
print "\n";
print "virtualmin create-simple-alias --domain domain.name\n";
print "                               --from mailbox|\"*\"\n";
print "                              [--forward user\@domain]*\n";
print "                              [--local local-user]\n";
print "                              [--bounce]\n";
print "                              [--everyone]\n";
print "                              [--autoreply \"some message\"]\n";
print "                              [--autoreply-period hours]\n";
print "                              [--autoreply-from user\@domain]\n";
if ($can_alias_comments) {
	print "                              [--desc \"Comment text\"]\n";
	}
exit(1);
}

