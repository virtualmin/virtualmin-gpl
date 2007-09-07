# Functions for migrating a plesk backup. These appear to be in MIME format,
# with each part (home dir, settings, etc) in a separate 'attachment'

# migration_plesk_validate(file, domain, username, [&parent], [prefix])
# Make sure the given file is a Plesk backup, and contains the domain
sub migration_plesk_validate
{
local ($file, $dom, $user, $parent, $prefix) = @_;
local $root = &extract_plesk_dir($file);
$root || return "Not a Plesk MIME-format backup file";
-r "$root/dump.xml" || return "Not a Plesk backup file - missing dump.xml";

# Check the domain
local $dump = &read_plesk_xml("$root/dump.xml");
ref($dump) || return $dump;
local $realdom = $dump->{'domain'}->{'name'};
$realdom eq $dom ||
	return "Backup is for domain $realdom, not $dom";

# Check for clashes
$prefix ||= &compute_prefix($dom, undef, $parent);
local $pclash = &get_domain_by("prefix", $prefix);
$pclash && return "A virtual server using the prefix $prefix already exists";

return undef;
}

# migration_plesk_migrate(file, domain, username, create-webmin, template-id,
#			   ip-address, virtmode, pass, [&parent], [prefix],
#			   virt-already, [email])
# Actually extract the given Plesk backup, and return the list of domains
# created.
sub migration_plesk_migrate
{
local ($file, $dom, $user, $webmin, $template, $ip, $virt, $pass, $parent,
       $prefix, $virtalready, $email) = @_;

# Work out user and group
local $group = $user;
local $ugroup = $group;
local $root = &extract_plesk_dir($file);
local $dump = &read_plesk_xml("$root/dump.xml");

# First work out what features we have
&$first_print("Checking for Plesk features ..");
local @got = ( "dir", $parent ? () : ("unix"), "web" );
push(@got, "webmin") if ($webmin && !$parent);
if ($dump->{'domain'}->{'dns-zone'}) {
	push(@got, "dns");
	}
if ($dump->{'domain'}->{'www'} eq 'true') {
	push(@got, "web");
	}
if ($dump->{'domain'}->{'ip'}->{'ip-type'} eq 'exclusive') {
	push(@got, "ssl");
	}
if ($dump->{'domain'}->{'phosting'}->{'logrotation'}->{'enabled'} eq 'true') {
	push(@got, "logrotate");
	}
if ($dump->{'domain'}->{'phosting'}->{'webalizer'}) {
	push(@got, "webalizer");
	}
# XXX DB
# XXX check if any mailusers have spam or virus

# Tell the user what we have got
local %pconfig = map { $_, 1 } @feature_plugins;
@got = grep { $config{$_} || $pconfig{$_} } @got;
&$second_print(".. found ".
	       join(", ", map { $text{'feature_'.$_} ||
				&plugin_call($_, "feature_name") } @got).".");
local %got = map { $_, 1 } @got;

# Work out user and group IDs
local (%gtaken, %ggtaken, %taken, %utaken);
&build_group_taken(\%gtaken, \%ggtaken);
&build_taken(\%taken, \%utaken);
local ($gid, $ugid, $uid, $duser);
if ($parent) {
	# UID and GID come from parent
	$gid = $parent->{'gid'};
	$ugid = $parent->{'ugid'};
	$uid = $parent->{'uid'};
	$duser = $parent->{'user'};
	$group = $parent->{'group'};
	$ugroup = $parent->{'ugroup'};
	}
else {
	# Allocate new IDs
	$gid = &allocate_gid(\%gtaken);
	$ugid = $gid;
	$uid = &allocate_uid(\%taken);
	$duser = $user;
	}

# XXX how to get quota?

# Create the virtual server object
local %dom;
$prefix ||= &compute_prefix($dom, $group, $parent);
%dom = ( 'id', &domain_id(),
	 'dom', $dom,
         'user', $duser,
         'group', $group,
         'ugroup', $ugroup,
         'uid', $uid,
         'gid', $gid,
         'ugid', $ugid,
         'owner', "Migrated cPanel server $dom",
         'email', $email ? $email : $parent ? $parent->{'email'} : undef,
         'name', !$virt,
         'ip', $ip,
	 'dns_ip', $virt || $config{'all_namevirtual'} ? undef :
		$config{'dns_ip'},
         'virt', $virt,
         'virtalready', $virtalready,
	 $parent ? ( 'pass', $parent->{'pass'} )
		 : ( 'pass', $pass ),
	 'source', 'migrate.cgi',
	 'template', $template,
	 'parent', undef,
	 'prefix', $prefix,
	 'no_tmpl_aliases', 1,
	 'no_mysql_db', $got{'mysql'} ? 1 : 0,
	 'parent', $parent ? $parent->{'id'} : undef,
        );
if (!$parent) {
	&set_limits_from_template(\%dom, $tmpl);
	$dom{'quota'} = $quota;
	$dom{'uquota'} = $quota;
	&set_capabilities_from_template(\%dom, $tmpl);
	}
$dom{'db'} = $db || &database_name(\%dom);
$dom{'emailto'} = $dom{'email'} ||
		  $dom{'user'}.'@'.&get_system_hostname();
foreach my $f (@features, @feature_plugins) {
	$dom{$f} = $got{$f} ? 1 : 0;
	}
&set_featurelimits_from_template(\%dom, $tmpl);
$dom{'home'} = &server_home_directory(\%dom, $parent);
&complete_domain(\%dom);

# Check for various clashes
&$first_print("Checking for clashes and dependencies ..");
$derr = &virtual_server_depends(\%dom);
if ($derr) {
	&$second_print($derr);
	return ( );
	}
$cerr = &virtual_server_clashes(\%dom);
if ($cerr) {
	&$second_print($cerr);
	return ( );
	}
&$second_print(".. all OK");

# Create the initial server
&$first_print("Creating initial virtual server ..");
&$indent_print();
local $err = &create_virtual_server(\%dom, $parent,
				    $parent ? $parent->{'user'} : undef);
&$outdent_print();
if ($err) {
	&$second_print($err);
	return ( );
	}
else {
	&$second_print(".. done");
	}

# Copy web files
&$first_print("Copying web pages ..");
local $htdocs = "$root/$dom.httpdocs";
if (-r $htdocs) {
	local $hdir = &public_html_dir(\%dom);
	local $err = &extract_compressed_file($htdocs, $hdir);
	if ($err) {
		&$second_print(".. failed : $err");
		}
	else {
		&set_home_ownership(\%dom);
		&$second_print(".. done");
		}
	}
else {
	&$second_print(".. not found in Plesk backup");
	}

# Re-create DNS records
# XXX

# Re-create mail users and copy mail files
# XXX

return (\%dom);
}

# extract_plesk_dir(file)
# Extracts all attachments from a plesk backup in MIME format to a temp
# directory, and returns the path.
sub extract_plesk_dir
{
local ($file) = @_;
local $dir = &transname();
&make_dir($dir, 0700);

# Is this compressed?
local $cf = &compression_format($file);
if ($cf != 0 && $cf != 1) {
	return undef;
	}

# Read in the backup as a fake mail object
&foreign_require("mailboxes", "mailboxes-lib.pl");
local $mail = { };
if ($cf == 0) {
	open(FILE, $file) || return undef;
	}
else {
	open(FILE, "gunzip -c ".quotemeta($file)." |") || return undef;
	}
while(<FILE>) {
	s/\r|\n//g;
	if (/^(\S+):\s+(.*)/) {
		$mail->{'header'}->{lc($1)} = $2;
		push(@{$mail->{'headers'}}, [ $1, $2 ]);
		}
	else {
		last;	# End of 'headers'
		}
	}
while(read(FILE, $buf, 1024) > 0) {
	$mail->{'body'} .= $buf;
	}
close(FILE);

# Parse out the attachments and save each one off
&mailboxes::parse_mail($mail);
local $count = 0;
foreach my $a (@{$mail->{'attach'}}) {
	if ($a->{'filename'}) {
		open(ATTACH, ">$dir/$a->{'filename'}");
		print ATTACH $a->{'data'};
		close(ATTACH);
		$count++;
		}
	}
return undef if (!$count);	# No attachments!

return $dir;
}

# read_plesk_xml(file)
# Use XML::Simple to read a Plesk XML file. Returns the object on success, or
# an error message on failure.
sub read_plesk_xml
{
local ($file) = @_;
eval "use XML::Simple";
if ($@) {
	return "XML::Simple Perl module is not installed";
	}
local $ref;
eval {
	local $xs = XML::Simple->new();
	$ref = $xs->XMLin($file);
	};
$ref || return "Failed to read XML file : $@";
return $ref;
}

1;

