#!/usr/local/bin/perl

=head1 run-api-command.pl

Executes another API command over multiple servers.

Some Virtualmin API commands can only run on a single domain at a time, so this
command exists as a wrapper to loop over multiple domains easily. It can be
run like : C<virtualmin run-api-command --user foo modify-web --mode cgi>

Flags to select the domains to operate on must be given before the command
to run. All flags after the command will be passed to each invocation of it.
You can see the final commands without running them by adding the C<--test>
flag.

By default it will operate on all virtual servers, but you can choose specific
servers with the C<--domain> flag which can be given multiple times. Or
to limit the domains to those owned by a single user, the C<--user> parameter
can be given, following by a domain owner's name. You can also limit it to
particular server types with the C<--alias>, C<--no-alias>, C<--subserver>,
C<--toplevel> and C<--subdomain> parameters.

To only show domains with a particular feature
active, use the C<--with-feature> parameter followed by a feature code like
C<dns> or C<web>. Alternately, C<--without-feature> can be used to show
only domains without some feature enabled. The similar C<--with-web> and
C<--with-ssl> flags can be used to show domains with any kind of website
(Apache or Nginx).

To limit the list to virtual servers on some plan, use the C<--plan> flag
followed by a plan name or ID. Similarly, you can select only virtual servers
created using some template with the C<--template> flag, followed by an ID
or name.

To show only domains owned by some reseller, use the C<--reseller> flag followed
by a reseller name. Or to list those not owned by any reseller, use the
C<--no-reseller> flag. Finally, to list domains owned by any reseller, you
can use the C<--any-reseller> option.

To show only domains that are enabled, use the C<--enabled> flag. To show
only disabled domains, use C<--disabled> instead.

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
	$0 = "$pwd/run-api-command.pl";
	require './virtual-server-lib.pl';
	$< == 0 || die "run-api-command.pl must be run as root";
	}
&require_mail();

# Parse command-line args
$owner = 1;
@allplans = &list_plans();
while(@ARGV > 0) {
	local $a = shift(@ARGV);
	if ($a eq "--domain") {
		push(@domains, shift(@ARGV));
		}
	elsif ($a eq "--user") {
		push(@users, shift(@ARGV));
		}
	elsif ($a eq "--mail-user") {
		push(@mailusers, shift(@ARGV));
		}
	elsif ($a eq "--id") {
		push(@ids, shift(@ARGV));
		}
	elsif ($a eq "--with-feature") {
		$with = shift(@ARGV);
		}
	elsif ($a eq "--without-feature") {
		$without = shift(@ARGV);
		}
	elsif ($a eq "--with-web") {
		$withweb = 1;
		}
	elsif ($a eq "--with-ssl") {
		$withssl = 1;
		}
	elsif ($a eq "--alias") {
		$must_alias = 1;
		if (@ARGV && $ARGV[0] !~ /^-/) {
			$aliasof = shift(@ARGV);
			}
		}
	elsif ($a eq "--no-alias") {
		$must_noalias = 1;
		}
	elsif ($a eq "--toplevel") {
		$must_toplevel = 1;
		}
	elsif ($a eq "--subserver") {
		$must_subserver = 1;
		}
	elsif ($a eq "--subdomain") {
		$must_subdomain = 1;
		}
	elsif ($a eq "--parent") {
		$parentof = shift(@ARGV);
		}
	elsif ($a eq "--plan") {
		$planname = shift(@ARGV);
		($plan) = grep { lc($_->{'name'}) eq lc($planname) ||
				 $_->{'id'} eq $planname } @allplans;
		$plan || &usage("No plan with name or ID $planname found");
		push(@plans, $plan);
		}
	elsif ($a eq "--template") {
		$tmplid = shift(@ARGV);
		$must_tmpl = &get_template($tmplid);
		if (!$must_tmpl) {
			($must_tmpl) = grep { $_->{'name'} eq $tmplid }
					    &list_templates();
			}
		$must_tmpl ||
			&usage("No template with ID or name $planid was found");
		}
	elsif ($a eq "--reseller") {
		$resel = shift(@ARGV);
		}
	elsif ($a eq "--no-reseller") {
		$no_resel = 1;
		}
	elsif ($a eq "--any-reseller") {
		$any_resel = 1;
		}
	elsif ($a eq "--disabled") { $disabled = 1; }
	elsif ($a eq "--enabled") { $disabled = 0; }
	elsif ($a eq "--test") {
		$testmode = 1;
		}
	elsif ($a !~ /^-/) {
		# Found the command - stop parsing
		$apicmd = $a;
		last;
		}
	elsif ($a eq "--help") {
		&usage();
		}
	else {
		&usage("Unknown parameter $a");
		}
	}
$apicmd || &usage("Missing command to run");

if (@ids) {
	# Get domains by IDs
	foreach $id (@ids) {
		$d = &get_domain($id);
		$d || &usage("No virtual server with ID $id exists");
		push(@doms, $d);
		}
	}
elsif (@domains || @users || @plans) {
	# Just showing listed domains or domains owned by some user
	@doms = &get_domains_by_names_users(\@domains, \@users, \&usage,
					    \@plans);
	}
elsif (@mailusers) {
	# Get domains by mailboxes in them
	my %done;
	foreach my $u (@mailusers) {
		$d = &get_user_domain($u);
		if ($d && !$done{$d->{'id'}}++) {
			push(@doms, $d);
			}
		}
	}
else {
	# Doing all domains, with some limits
	@doms = &list_domains();
	}

# Get alias/parent domains
if ($aliasof) {
	$aliasofdom = &get_domain_by("dom", $aliasof);
	$aliasofdom || &usage("No alias target named $aliasof found");
	}
if ($parentof) {
	$parentofdom = &get_domain_by("dom", $parentof);
	$parentofdom || &usage("No parent named $parentof found");
	}

@doms = grep { $_->{'alias'} } @doms if ($must_alias);
@doms = grep { !$_->{'alias'} } @doms if ($must_noalias);
@doms = grep { $_->{'parent'} } @doms if ($must_subserver);
@doms = grep { !$_->{'parent'} } @doms if ($must_toplevel);
@doms = grep { $_->{'subdom'} } @doms if ($must_subdomain);
@doms = sort { $a->{'user'} cmp $b->{'user'} ||
	       $a->{'created'} <=> $b->{'created'} } @doms;
if ($aliasofdom) {
	@doms = grep { $_->{'alias'} eq $aliasofdom->{'id'} } @doms;
	}
if ($parentofdom) {
	@doms = grep { $_->{'parent'} eq $parentofdom->{'id'} } @doms;
	}

# Limit to those with/without some feature
if ($with) {
	@doms = grep { $_->{$with} } @doms;
	}
if ($withweb) {
	@doms = grep { &domain_has_website($_) } @doms;
	}
if ($withssl) {
	@doms = grep { &domain_has_ssl($_) } @doms;
	}
if ($without) {
	@doms = grep { !$_->{$without} } @doms;
	}

# Limit to those on some template
if ($must_tmpl) {
	@doms = grep { $_->{'template'} eq $must_tmpl->{'id'} } @doms;
	}

# Limit by reseller
if ($resel) {
	@doms = grep { &indexof($resel, split(/\s+/, $_->{'reseller'})) >= 0 }
		     @doms;
	}
elsif ($no_resel) {
	@doms = grep { !$_->{'reseller'} } @doms;
	}
elsif ($any_resel) {
	@doms = grep { $_->{'reseller'} } @doms;
	}

# Limit by enabled status
if ($disabled eq '1') {
	@doms = grep { $_->{'disabled'} } @doms;
	}
elsif ($disabled eq '0') {
	@doms = grep { !$_->{'disabled'} } @doms;
	}

# Run the command
@doms || &usage("No matching virtual servers found");
foreach my $d (@doms) {
	$cmd = "virtualmin ".$apicmd." --domain $d->{'dom'} ".
	       join(" ", map { &quotameta_ifneeded($_) } @ARGV);
	if ($testmode) {
		print "Would run $cmd ..\n";
		}
	else {
		print "Running $cmd ..\n";
		&open_execute_command(OUT, $cmd, 1);
		while(<OUT>) {
			print $_;
			}
		$ok = close(OUT);
		$ok = 0 if ($?);
		print !$ok ? ".. failed!\n" : ".. done\n";
		print "\n";
		}
	}

sub usage
{
print "$_[0]\n\n" if ($_[0]);
print "Executes another API command over multiple servers.\n";
print "\n";
print "virtualmin run-api-command [--domain name]*\n";
print "                           [--user name]*\n";
print "                           [--id number]*\n";
print "                           [--with-feature feature]\n";
print "                           [--without-feature feature]\n";
print "                           [--with-web] [--with-ssl]\n";
print "                           [--alias domain | --no-alias]\n";
print "                           [--subserver | --toplevel | --subdomain]\n";
print "                           [--parent domain]\n";
print "                           [--plan ID|name]\n";
print "                           [--template ID|name]\n";
print "                           [--disabled | --enabled]\n";
if ($virtualmin_pro) {
	print "                           [--reseller name | --no-reseller |\n";
	print "                            --any-reseller]\n";
	}
print "                           [--test]\n";
print "                           command [flags]\n";
exit(1);
}

sub quotameta_ifneeded
{
my ($cmd) = @_;
return $cmd =~ /[ \t;&<>()]/ ? quotemeta($cmd) : $cmd;
}
