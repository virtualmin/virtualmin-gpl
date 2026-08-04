# Btrfs subvolume quota helpers for Virtualmin

# has_btrfs_quotas()
# Returns 1 when the home quota backend uses Btrfs qgroups.
sub has_btrfs_quotas
{
return $config{'btrfs_quotas'} ? 1 : 0;
}

# btrfs_format_path(path)
# Formats a filesystem path as literal text for web output and leaves CLI
# output unchanged.
sub btrfs_format_path
{
my ($path) = @_;
return $path if ($main::webmin_script_type ne 'web');
my $display_path = &ui_tag("tt", &html_escape($path));
chomp($display_path);
return $display_path;
}

# btrfs_quota_domain(&domain)
# Returns the top-level domain whose qgroup owns a mailbox home.
sub btrfs_quota_domain
{
my ($d) = @_;
my %seen;
# Walk through sub-server ownership while protecting against corrupt cycles.
while($d && $d->{'parent'}) {
	return undef if ($seen{$d->{'id'}}++);
	$d = &get_domain($d->{'parent'});
	}
return $d && !$d->{'alias'} ? $d : undef;
}

# list_btrfs_domain_tree(&top-domain)
# Returns every non-alias server whose mailbox homes belong to one aggregate.
sub list_btrfs_domain_tree
{
my ($d) = @_;
return ( ) if (!$d || $d->{'parent'} || $d->{'alias'});
my (@rv, @pending, %seen);
push(@pending, $d);
# Traverse recursively because Virtualmin permits sub-servers below sub-servers.
while(my $current = shift(@pending)) {
	next if (!$current->{'id'} || $seen{$current->{'id'}}++);
	push(@rv, $current) if (!$current->{'alias'});
	push(@pending, &get_domain_by("parent", $current->{'id'}));
	}
return @rv;
}

# btrfs_quota_api_error()
# Returns an error if the required Webmin quota APIs are unavailable.
sub btrfs_quota_api_error
{
&require_useradmin();
# Check the entire API surface up front so lifecycle operations fail clearly.
foreach my $f (qw(is_btrfs_fs btrfs_quota_status list_btrfs_qgroups
		  btrfs_subvolume_id set_btrfs_qgroup_limit
		  create_btrfs_qgroup delete_btrfs_qgroup
		  assign_btrfs_qgroup unassign_btrfs_qgroup
		  rescan_btrfs_quotas run_btrfs_command)) {
	return &text('btrfs_eapi', $f)
		if (!defined(&{"quota::$f"}));
	}
return undef;
}

# btrfs_quota_parent_id(&domain, [&error])
# Returns the collision-free level-1 qgroup used to aggregate a top-level
# domain. Btrfs qgroup object IDs are only 48 bits wide, so Virtualmin's longer
# domain IDs cannot be used. The domain home subvolume ID is filesystem-local,
# stable and already constrained to the correct range.
sub btrfs_quota_parent_id
{
my ($d, $errref) = @_;
return undef if (!$d || $d->{'parent'} || $d->{'alias'} || !$d->{'home'});
my $cached = $main::btrfs_qgroups_by_path_cache &&
	     $main::btrfs_qgroups_by_path_cache->{$d->{'home'}};
# Prefer the qgroup cache populated for quota listings to avoid another command.
if ($cached && $cached->{'id'} =~ /^0\/(\d+)$/) {
	$$errref = undef if ($errref);
	return "1/$1";
	}
my $id = &quota::btrfs_subvolume_id($d->{'home'}, $errref);
return undef if (!defined($id));
$$errref = undef if ($errref);
return "1/$id";
}

# btrfs_quota_blocks_to_bytes(blocks)
# Virtualmin stores quota limits in 1 KiB blocks on Linux.
sub btrfs_quota_blocks_to_bytes
{
my ($blocks) = @_;
return undef if (!$blocks);
return int($blocks) * 1024;
}

# btrfs_quota_bytes_to_blocks(bytes)
# Round usage up so a partial block is not hidden from quota reporting.
sub btrfs_quota_bytes_to_blocks
{
my ($bytes) = @_;
return 0 if (!$bytes);
return int((int($bytes) + 1023) / 1024);
}

# decode_btrfs_mount_path(path)
# Decode the octal escapes used by /proc/self/mountinfo.
sub decode_btrfs_mount_path
{
my ($path) = @_;
$path =~ s/\\([0-7]{3})/chr(oct($1))/eg;
return $path;
}

# parse_btrfs_mountinfo(text, path)
# Returns the deepest Btrfs mount point containing path and its filesystem root.
sub parse_btrfs_mountinfo
{
my ($text, $path) = @_;
my ($best_mount, $best_root);
# Parse only Btrfs mountinfo records that can contain the requested path.
foreach my $line (split(/\r?\n/, $text)) {
	my ($left, $right) = split(/\s+-\s+/, $line, 2);
	next if (!defined($right));
	my @right = split(/\s+/, $right);
	next if ($right[0] ne 'btrfs');
	my @left = split(/\s+/, $left);
	next if (@left < 5);
	my $root = &decode_btrfs_mount_path($left[3]);
	my $mount = &decode_btrfs_mount_path($left[4]);
	next if (!&is_under_directory($mount, $path));
	# Prefer the deepest match when nested Btrfs subvolumes are mounted.
	if (!defined($best_mount) || length($mount) > length($best_mount)) {
		$best_mount = $mount;
		$best_root = $root;
		}
	}
return defined($best_mount) ? ($best_mount, $best_root) : ( );
}

# btrfs_mountinfo(path)
# Reads Linux mountinfo and returns the visible mount point and filesystem root.
sub btrfs_mountinfo
{
my ($path) = @_;
open(my $fh, "<", "/proc/self/mountinfo") || return ( );
local $/ = undef;
my $text = <$fh>;
close($fh);
return &parse_btrfs_mountinfo($text, $path);
}

# btrfs_qgroup_absolute_path(mount, fs-root, qgroup-path)
# Convert the path reported by `btrfs qgroup show` to a visible absolute path.
sub btrfs_qgroup_absolute_path
{
my ($mount, $root, $path) = @_;
return undef if (!defined($path) || $path eq '' || $path =~ /^</);
$root ||= "/";
$root =~ s/^\/+//;
$root =~ s/\/+\z//;
$path =~ s/^\/+//;
# Strip the mounted subvolume root from the filesystem-relative qgroup path.
if ($root ne '') {
	return undef if ($path ne $root && index($path, "$root/") != 0);
	$path = substr($path, length($root));
	$path =~ s/^\/+//;
	}
$mount =~ s/\/+\z// if ($mount ne "/");
my $absolute = $path eq '' ? ($mount || "/") :
		       ($mount eq "/" ? "/$path" : "$mount/$path");
$absolute =~ s{//+}{/}g;
return $absolute;
}

# clear_btrfs_quota_cache()
# Invalidates all indexes after a qgroup or subvolume mutation.
sub clear_btrfs_quota_cache
{
undef($main::btrfs_qgroups_cache);
undef($main::btrfs_qgroups_by_id_cache);
undef($main::btrfs_qgroups_by_path_cache);
}

# list_btrfs_qgroups([sync], [&error])
# Returns qgroups and builds request-local ID and absolute-path indexes.
sub list_btrfs_qgroups
{
my ($sync, $errref) = @_;
my $apierr = &btrfs_quota_api_error();
# Report missing Webmin support before consulting potentially stale state.
if ($apierr) {
	$$errref = $apierr if ($errref);
	return undef;
	}
# Reuse a request-local snapshot unless the caller explicitly requests a sync.
if (!$sync && $main::btrfs_qgroups_cache) {
	$$errref = undef if ($errref);
	return $main::btrfs_qgroups_cache;
	}
my $fs = $config{'home_quotas'} || $home_base;
my $qgroups = &quota::list_btrfs_qgroups($fs, $sync, $errref);
return undef if (!$qgroups);
my %byid = map { $_->{'id'}, $_ } @$qgroups;
my %bypath;
my ($mount, $root) = &btrfs_mountinfo($fs);
# Build absolute-path indexes only when the visible Btrfs mount can be resolved.
if (defined($mount)) {
	foreach my $q (@$qgroups) {
		my $path = &btrfs_qgroup_absolute_path(
			$mount, $root, $q->{'path'});
		# Special or out-of-mount qgroup paths intentionally remain ID-only.
		if (defined($path)) {
			$q->{'virtualmin_path'} = $path;
			$bypath{$path} = $q;
			}
		}
	}
$main::btrfs_qgroups_cache = $qgroups;
$main::btrfs_qgroups_by_id_cache = \%byid;
$main::btrfs_qgroups_by_path_cache = \%bypath;
$$errref = undef if ($errref);
return $qgroups;
}

# get_btrfs_qgroup_by_path(path, [sync], [&error])
# Returns the level-0 qgroup for an absolute visible subvolume path.
sub get_btrfs_qgroup_by_path
{
my ($path, $sync, $errref) = @_;
my $qgroups = &list_btrfs_qgroups($sync, $errref);
return undef if (!$qgroups);
my $q = $main::btrfs_qgroups_by_path_cache->{$path};
return $q if ($q);

# Fall back to an ID lookup for unusual mount layouts.
my $id = &quota::btrfs_subvolume_id($path, $errref);
return undef if (!defined($id));
$q = $main::btrfs_qgroups_by_id_cache->{"0/$id"};
$$errref = &text('btrfs_enoqgroup', $id) if (!$q && $errref);
return $q;
}

# ensure_btrfs_parent_qgroup(&domain)
# Creates the domain aggregate qgroup or validates the existing one.
sub ensure_btrfs_parent_qgroup
{
my ($d) = @_;
my $err;
my $parent = &btrfs_quota_parent_id($d, \$err);
return $err || $text{'btrfs_edomainhome'} if (!$parent);
my $qgroups = &list_btrfs_qgroups(0, \$err);
return $err if (!$qgroups);
my $existing = $main::btrfs_qgroups_by_id_cache->{$parent};
if ($existing) {
	# A higher-level qgroup ID is normally arbitrary. Refuse to adopt an
	# unexpected pre-existing group even though using the domain subvolume ID
	# makes such a collision very unlikely.
	my $home = $d->{'home'};
	$home =~ s/\/+\z//;
	# Every existing child must resolve to the domain home or below it.
	foreach my $child (@{$existing->{'children'} || [ ]}) {
		my $child_qgroup =
			$main::btrfs_qgroups_by_id_cache->{$child};
		my $child_path = $child_qgroup &&
			$child_qgroup->{'virtualmin_path'};
		return &text('btrfs_eqgroupoutside', $parent,
				&btrfs_format_path($home))
			if (!defined($child_path) ||
			    ($child_path ne $home &&
			     index($child_path, "$home/") != 0));
		}
	return undef;
	}
my $fs = $config{'home_quotas'} || $home_base;
$err = &quota::create_btrfs_qgroup($fs, $parent);
# Treat an already-created matching qgroup as a successful concurrent result.
if ($err) {
	# A concurrent creator may have won the race.
	&clear_btrfs_quota_cache();
	$qgroups = &list_btrfs_qgroups(0, undef);
	return undef if ($qgroups &&
			$main::btrfs_qgroups_by_id_cache->{$parent});
	return $err;
	}
&clear_btrfs_quota_cache();
return undef;
}

# btrfs_directory_is_empty(path)
# Returns 1 only when a directory has no entries other than dot entries.
sub btrfs_directory_is_empty
{
my ($path) = @_;
opendir(my $dh, $path) || return 0;
my @entries = grep { $_ ne '.' && $_ ne '..' } readdir($dh);
closedir($dh);
return @entries ? 0 : 1;
}

# assign_btrfs_subvolume_to_parent(path, &domain, id)
# Ensures the level-0 qgroup belongs to the domain aggregate and is consistent.
sub assign_btrfs_subvolume_to_parent
{
my ($path, $d, $id) = @_;
my $err = &ensure_btrfs_parent_qgroup($d);
return $err if ($err);
my $parent = &btrfs_quota_parent_id($d, \$err);
return $err || $text{'btrfs_edomainhome'} if (!$parent);
my $q = &get_btrfs_qgroup_by_path($path, 0, \$err);
return $err if (!$q);
# Add only missing relationships so repeated setup and repair remain idempotent.
if (!grep { $_ eq $parent } @{$q->{'parents'} || [ ]}) {
	$err = &quota::assign_btrfs_qgroup(
		$config{'home_quotas'} || $home_base,
		"0/$id", $parent);
	return $err if ($err);
	# Assigning a populated subvolume can make all qgroup limits
	# temporarily unenforceable. Wait for the rescan started by the
	# assignment before returning control to Virtualmin.
	$err = &quota::rescan_btrfs_quotas(
		$config{'home_quotas'} || $home_base, 1);
	return $err if ($err);
	&clear_btrfs_quota_cache();
	}
return undef;
}

# ensure_btrfs_subvolume(path, &domain)
# Returns error and a created flag. Existing non-empty directories are never
# converted automatically because doing so would require a disruptive move.
sub ensure_btrfs_subvolume
{
my ($path, $d) = @_;
my $apierr = &btrfs_quota_api_error();
return wantarray ? ($apierr, 0) : $apierr if ($apierr);
return wantarray ? ($text{'btrfs_ehomepath'}, 0) :
		   $text{'btrfs_ehomepath'}
	if (!defined($path) || $path !~ /^\// || $path =~ /[\r\n\0]/);
return wantarray ? ($text{'btrfs_etopdomain'}, 0) :
		   $text{'btrfs_etopdomain'}
	if (!$d || $d->{'parent'} || $d->{'alias'} || !$d->{'home'});
my $is_domain_home = $path eq $d->{'home'};
my $err = &repair_btrfs_quota_accounting();
return wantarray ? ($err, 0) : $err if ($err);

my $id = &quota::btrfs_subvolume_id($path, undef);
# Existing subvolumes are preserved and only have their membership repaired.
if (defined($id)) {
	$err = &assign_btrfs_subvolume_to_parent($path, $d, $id);
	return wantarray ? ($err, 0) : $err if ($err);
	return wantarray ? (undef, 0) : undef;
	}

# Replace only an empty ordinary directory; populated homes require migration.
if (-e $path) {
	if (!-d $path || -l $path || !&btrfs_directory_is_empty($path)) {
		my $display_path = &btrfs_format_path($path);
		my $message = &text('btrfs_eexistinghome', $display_path);
		return wantarray ? ($message, 0) : $message;
		}
	my $display_path = &btrfs_format_path($path);
	rmdir($path) || return wantarray ?
		(&text('btrfs_ereplaceempty', $display_path, $!), 0) :
		&text('btrfs_ereplaceempty', $display_path, $!);
	}
my @create_args = ( "subvolume", "create" );
# Mailbox homes can inherit the known domain qgroup during atomic creation.
if (!$is_domain_home) {
	$err = &ensure_btrfs_parent_qgroup($d);
	return wantarray ? ($err, 0) : $err if ($err);
	my $parent = &btrfs_quota_parent_id($d, \$err);
	return wantarray ?
		($err || $text{'btrfs_edomainhome'}, 0) :
		($err || $text{'btrfs_edomainhome'})
		if (!$parent);
	push(@create_args, "-i", $parent);
	}
push(@create_args, $path);
my ($out, $cmderr) = &quota::run_btrfs_command(1, @create_args);
return wantarray ? ($cmderr, 0) : $cmderr if ($cmderr);
&clear_btrfs_quota_cache();
# A new domain home must reveal its subvolume ID before its parent can exist.
if ($is_domain_home) {
	$id = &quota::btrfs_subvolume_id($path, \$err);
	if (!defined($id)) {
		$err ||= $text{'btrfs_enewhomeid'};
		return wantarray ? ($err, 1) : $err;
		}
	$err = &assign_btrfs_subvolume_to_parent($path, $d, $id);
	return wantarray ? ($err, 1) : $err if ($err);
	}
return wantarray ? (undef, 1) : undef;
}

# ensure_btrfs_domain_home(&domain)
# Creates or repairs a top-level domain home when Btrfs quotas are active.
sub ensure_btrfs_domain_home
{
my ($d) = @_;
return wantarray ? (undef, 0) : undef
	if (!&has_btrfs_quotas() || $d->{'parent'} || $d->{'alias'});
return &ensure_btrfs_subvolume($d->{'home'}, $d);
}

# ensure_btrfs_user_home(&user, &domain)
# Creates or repairs a mailbox home under its top-level domain qgroup.
sub ensure_btrfs_user_home
{
my ($user, $d) = @_;
return wantarray ? (undef, 0) : undef
	if (!&has_btrfs_quotas() || !$d || !$user->{'home'} ||
	    $user->{'nocreatehome'} ||
	    $user->{'webowner'});
$d = &btrfs_quota_domain($d);
return wantarray ? ($text{'btrfs_enotopdomain'}, 0) :
		   $text{'btrfs_enotopdomain'} if (!$d);
return wantarray ? (undef, 0) : undef if ($user->{'home'} eq $d->{'home'});
return &ensure_btrfs_subvolume($user->{'home'}, $d);
}

# convert_btrfs_restored_user_home(&user, &domain)
# Converts a populated mailbox directory extracted by restore_dir into a
# subvolume without exposing this disruptive behavior to normal user creation.
sub convert_btrfs_restored_user_home
{
my ($user, $d) = @_;
return undef if (!&has_btrfs_quotas() || !$d || !$user->{'home'} ||
		 $user->{'nocreatehome'} || $user->{'webowner'});
my $apierr = &btrfs_quota_api_error();
return $apierr if ($apierr);
$d = &btrfs_quota_domain($d);
return $text{'btrfs_enotopdomain'} if (!$d);
my $path = $user->{'home'};
return undef if ($path eq $d->{'home'} || !-e $path);

# Restore may migrate only a real mailbox directory below this domain home.
# This prevents backup metadata from turning arbitrary legacy paths into
# subvolumes, while external homes retain the existing explicit behavior.
my $domain_home = $d->{'home'};
$domain_home =~ s{/+\z}{};
return &text('btrfs_erestorehome', &btrfs_format_path($path))
	if ($path !~ /^\Q$domain_home\E\/.+/ || $path =~ /(?:^|\/)\.\.(?:\/|$)/ ||
	    $path =~ /[\r\n\0]/ || !-d $path || -l $path ||
	    defined(&is_under_directory) &&
	    !&is_under_directory($domain_home, $path));

# Existing subvolumes and empty directories need no data migration. The
# standard helper repairs membership or replaces the empty directory safely.
my $id = &quota::btrfs_subvolume_id($path, undef);
if (defined($id) || &btrfs_directory_is_empty($path)) {
	my ($err) = &ensure_btrfs_user_home($user, $d);
	return $err;
	}

# Park the extracted directory beside its final path. The rename is atomic and
# keeps the complete original available until the cross-subvolume copy ends.
my $holding = $path.".virtualmin-btrfs-restore-$$";
my $sequence = 0;
while(-e $holding) {
	$holding = $path.".virtualmin-btrfs-restore-$$-".(++$sequence);
	}
rename($path, $holding) ||
	return &text('btrfs_estagehome', &btrfs_format_path($path), $!);

my ($err, $created) = &ensure_btrfs_user_home($user, $d);
if ($err || !$created) {
	# Creation failures happen before data is copied. Remove only a subvolume
	# created by this attempt, then put the untouched directory back in place.
	if ($created && -d $path) {
		my $delete_err = &delete_btrfs_user_home($user, $d);
		$err = &text('btrfs_erollback', $err, $delete_err)
			if ($delete_err);
		}
	if (!-e $path && !rename($holding, $path)) {
		$err = &text('btrfs_erestoreoriginal', $err, $!);
		}
	return $err || &text('btrfs_enewmailhome',
				 &btrfs_format_path($path));
	}

# A direct rename across Btrfs subvolume boundaries returns EXDEV. A mandatory
# reflink preserves metadata without briefly charging a second physical copy
# of a large restored mailbox to the domain aggregate. Both paths are newly
# created on the same Btrfs filesystem, so a reflink failure is a hard error.
my $copy_status = &system_logged("cp -a --reflink=always -- ".
				 quotemeta($holding."/.")." ".
				 quotemeta($path."/"));
if ($copy_status) {
	my $copy_err = &text('btrfs_ecopyhome', &btrfs_format_path($path));
	my $delete_err = &delete_btrfs_user_home($user, $d);
	$copy_err = &text('btrfs_erollback', $copy_err, $delete_err)
		if ($delete_err);
	if (!-e $path && !rename($holding, $path)) {
		$copy_err = &text('btrfs_erestoreoriginal', $copy_err, $!);
		}
	return $copy_err;
	}

# Delete the parked copy only after cp reports a complete successful transfer.
my ($removed, $remove_err) = &unlink_file($holding);
return &text('btrfs_eremovestage', &btrfs_format_path($holding),
		     $remove_err || $!) if (!$removed);
return undef;
}

# set_btrfs_qgroup_limit(path, [qgroup], blocks)
# Converts Virtualmin blocks and applies a referenced-byte qgroup limit.
sub set_btrfs_qgroup_limit
{
my ($path, $qgroup, $blocks) = @_;
# Never change a limit while Btrfs reports globally inconsistent accounting.
my $err = &repair_btrfs_quota_accounting();
return $err if ($err);
my $bytes = &btrfs_quota_blocks_to_bytes($blocks);
$err = &quota::set_btrfs_qgroup_limit(
	$path, $qgroup, $bytes, 0);
&clear_btrfs_quota_cache() if (!$err);
return $err;
}

# btrfs_simple_quota_error(filesystem)
# Returns a plain error for CLI callers and links authorized UI callers directly
# to the Disk Quotas module configuration.
sub btrfs_simple_quota_error
{
my ($fs) = @_;
my $display_fs = &btrfs_format_path($fs);
my $quota_module = $text{'btrfs_quotamodule'};
# Format the path for HTML and link only to configuration the user can access.
if ($main::webmin_script_type eq 'web') {
	if (&foreign_available("quota")) {
		my %quota_access = &get_module_acl(undef, "quota");
		if (!$quota_access{'noconfig'}) {
			my $url = &get_webprefix()."/config.cgi?module=quota";
			$quota_module = &ui_link($url, $quota_module);
			}
		}
	}
return &text('btrfs_esquota', $display_fs, $quota_module);
}

# repair_btrfs_quota_accounting([path], [cleanup])
# Validates full qgroup mode and waits for inconsistent accounting to repair.
sub repair_btrfs_quota_accounting
{
my ($path, $cleanup) = @_;
my $fs = $path || $config{'home_quotas'} || $home_base;
my $status = &quota::btrfs_quota_status($fs);
# Propagate status failures and rescan only when the kernel marks it necessary.
my $display_fs = &btrfs_format_path($fs);
return &text('btrfs_equotastatus', $display_fs) if (!$status);
return $status->{'error'} if ($status->{'error'});
return &text('btrfs_equotasdisabled', $display_fs)
	if (!$status->{'enabled'});
# Simple quotas cannot represent Virtualmin's parent domain aggregates. During
# deletion they need no repair, but every quota mutation must fail clearly.
if (($status->{'mode'} || '') eq 'squota') {
	return undef if ($cleanup);
	return &btrfs_simple_quota_error($fs);
	}
return undef if (!$status->{'inconsistent'});
return &quota::rescan_btrfs_quotas($fs, 1);
}

# set_btrfs_home_quota(path, blocks, [&domain], [deleting])
# Applies a quota to a known domain-owner or mailbox home path. New mailbox
# homes use this before their Unix passwd entry exists.
sub set_btrfs_home_quota
{
my ($home, $blocks, $d, $deleting) = @_;
return undef if (!$home || !-e $home);  # Creation applies it after mkdir.
my $apierr = &btrfs_quota_api_error();
return $apierr if ($apierr);
# Resolve sub-server users to the top-level domain that owns their aggregate.
if ($d) {
	$d = &btrfs_quota_domain($d);
	return $text{'btrfs_enotopdomain'} if (!$d);
	}
# Deletion clears quotas before removing a mailbox. An ordinary legacy or
# partially restored home has no qgroup limit to clear and must remain
# deletable instead of entering the subvolume-creation path.
my $id = &quota::btrfs_subvolume_id($home, undef);
return undef if ($deleting && !defined($id));
# Mailbox homes must be subvolumes and members of the domain parent qgroup.
if ($d && $home ne $d->{'home'}) {
	my ($layout_err) = &ensure_btrfs_subvolume($home, $d);
	return $layout_err if ($layout_err);
	}
$id = &quota::btrfs_subvolume_id($home, undef) if (!defined($id));
return &text('btrfs_ehomesubvolume', &btrfs_format_path($home))
	if (!defined($id));
return &set_btrfs_qgroup_limit($home, undef, $blocks);
}

# set_btrfs_user_quota(username, blocks, &domain, [deleting])
# Resolves an existing Unix account before applying its home subvolume limit.
sub set_btrfs_user_quota
{
my ($username, $blocks, $d, $deleting) = @_;
my @pw = getpwnam($username);
return &text('btrfs_enouser', $username) if (!@pw);
return &set_btrfs_home_quota($pw[7], $blocks, $d, $deleting);
}

# set_btrfs_server_quotas(&domain, user-blocks, server-blocks)
# Applies administrator and aggregate limits after repairing mailbox membership.
sub set_btrfs_server_quotas
{
my ($d, $uquota, $quota) = @_;
my ($err) = &ensure_btrfs_domain_home($d);
return $err if ($err);
return undef if ($d->{'parent'} || $d->{'alias'});

# Rebuild mailbox membership and limits if quotas were disabled and re-enabled,
# because that operation removes every higher-level relationship and limit.
my @user_domains = &list_btrfs_domain_tree($d);
foreach my $user_domain (@user_domains) {
	foreach my $user (&list_domain_users($user_domain, 1, 1, 1, 1)) {
		next if (!$user->{'home'} || !-e $user->{'home'} ||
			 $user->{'home'} eq $d->{'home'} ||
			 $user->{'nocreatehome'} || $user->{'webowner'} ||
			 $user->{'noquota'});
		my ($layout_err) =
			&ensure_btrfs_user_home($user, $user_domain);
		return $layout_err if ($layout_err);
		# The cache retains the configured limit even when the filesystem's
		# qgroup configuration has been lost.
		my $blocks = defined($user->{'quota_cache'}) ?
			$user->{'quota_cache'} : $user->{'quota'};
		if (defined($blocks)) {
			my $limit_err = &set_btrfs_qgroup_limit(
				$user->{'home'}, undef, $blocks);
			return $limit_err if ($limit_err);
			}
		}
	}
my $parent_err;
my $parent = &btrfs_quota_parent_id($d, \$parent_err);
return $parent_err || $text{'btrfs_edomainhome'}
	if (!$parent);
# Apply the administrator limit to the root and the server limit to its tree.
$err = &set_btrfs_qgroup_limit($d->{'home'}, undef, $uquota);
return $err if ($err);
return &set_btrfs_qgroup_limit(
	$config{'home_quotas'} || $home_base, $parent, $quota);
}

# apply_btrfs_quota(&user-or-group, &qgroup)
# Copies Btrfs byte usage and limits into Virtualmin's block-based fields.
sub apply_btrfs_quota
{
my ($object, $qgroup) = @_;
my $used = $qgroup ?
	&btrfs_quota_bytes_to_blocks($qgroup->{'referenced'}) : 0;
my $limit = $qgroup ?
	&btrfs_quota_bytes_to_blocks($qgroup->{'max_referenced'}) : 0;
$object->{'softquota'} = $limit;
$object->{'hardquota'} = $limit;
$object->{'uquota'} = $used;
$object->{'ufquota'} = 0;
}

# populate_btrfs_user_quotas(&users)
# Populates quota fields for Unix users from their home qgroups.
sub populate_btrfs_user_quotas
{
my ($users) = @_;
my $err;
my $qgroups = &list_btrfs_qgroups(1, \$err);
return $err if (!$qgroups);
my $quota_root = $config{'home_quotas'} || $home_base;
# Attach usage and limits by home path because Btrfs quotas are not UID-based.
foreach my $u (@$users) {
	my $q = $u->{'home'} ?
		$main::btrfs_qgroups_by_path_cache->{$u->{'home'}} : undef;
	# Limit fallback commands to homes governed by this quota backend. System
	# accounts elsewhere cannot have a relevant Btrfs home qgroup.
	if (!$q && $u->{'home'} && -e $u->{'home'} &&
	    &is_under_directory($quota_root, $u->{'home'})) {
		$q = &get_btrfs_qgroup_by_path(
			$u->{'home'}, 0, undef);
		}
	&apply_btrfs_quota($u, $q);
	}
return undef;
}

# populate_btrfs_group_quotas(&groups)
# Populates quota fields for domain groups from aggregate qgroups.
sub populate_btrfs_group_quotas
{
my ($groups) = @_;
my $err;
my $qgroups = &list_btrfs_qgroups(1, \$err);
return $err if (!$qgroups);
my %domain_by_group = map { $_->{'group'}, $_ }
	grep { !$_->{'parent'} && $_->{'group'} } &list_domains();
# Represent each Virtualmin group by its top-level aggregate qgroup.
foreach my $g (@$groups) {
	my $d = $domain_by_group{$g->{'group'}};
	my $parent = $d ? &btrfs_quota_parent_id($d) : undef;
	my $q = $parent ?
		$main::btrfs_qgroups_by_id_cache->{$parent} : undef;
	&apply_btrfs_quota($g, $q);
	}
return undef;
}

# delete_btrfs_subvolume(path, [subvolume-id])
# Deletes one subvolume, removes its stale qgroup, and repairs accounting.
sub delete_btrfs_subvolume
{
my ($path, $id) = @_;
my $repair_path = $config{'home_quotas'};
# When quota editing is disabled, use the still-existing parent directory.
if (!$repair_path) {
	$repair_path = $path;
	$repair_path =~ s{/+\z}{};
	$repair_path =~ s{/[^/]+\z}{};
	$repair_path ||= "/";
	}
my ($out, $err) = &quota::run_btrfs_command(
	1, "subvolume", "delete", $path);
# Older kernels can retain the level-0 qgroup after deleting its subvolume.
# Synchronize first so newer kernels can finish their automatic cleanup, then
# destroy only a qgroup that remains.
if (!$err && defined($id) && $id =~ /^\d+$/) {
	my $qgroup = "0/$id";
	my $list_err;
	my $qgroups = &quota::list_btrfs_qgroups(
		$repair_path, 1, \$list_err);
	if (!$qgroups) {
		$err = $list_err || $text{'btrfs_elistqgroups'};
		}
	elsif (grep { $_->{'id'} eq $qgroup } @$qgroups) {
		my $delete_err = &quota::delete_btrfs_qgroup(
			$repair_path, $qgroup);
		if ($delete_err) {
			$qgroups = &quota::list_btrfs_qgroups(
				$repair_path, 1, \$list_err);
			my $still_exists = $qgroups &&
				grep { $_->{'id'} eq $qgroup } @$qgroups;
			$err = $delete_err if (!$qgroups || $still_exists);
			}
		}
	&clear_btrfs_quota_cache();
	}
# Repair global accounting after cleanup before other limits are trusted.
if (!$err) {
	&clear_btrfs_quota_cache();
	$err = &repair_btrfs_quota_accounting($repair_path, 1);
	}
return $err;
}

# delete_btrfs_user_home(&user, &domain)
# Detaches and deletes a mailbox subvolume while preserving domain accounting.
sub delete_btrfs_user_home
{
my ($user, $d) = @_;
return undef if (!$user->{'home'});
$d = &btrfs_quota_domain($d);
return $text{'btrfs_enotopdomain'} if (!$d);
return undef if ($user->{'home'} eq $d->{'home'});
# Mailbox cleanup runs on every filesystem. Load Webmin's quota module when
# available, but preserve the ordinary-directory path for external backends.
&require_useradmin();
return undef if (!defined(&quota::btrfs_subvolume_id));
my $id = &quota::btrfs_subvolume_id($user->{'home'}, undef);
return undef if (!defined($id));
my $apierr = &btrfs_quota_api_error();
return $apierr if ($apierr);
my $fs = $config{'home_quotas'} || $user->{'home'};
my $status = &quota::btrfs_quota_status($fs);
return &text('btrfs_equotastatus', &btrfs_format_path($fs)) if (!$status);
return $status->{'error'} if ($status->{'error'});
# Remove the relationship explicitly to prevent a stale child during teardown.
if ($status->{'enabled'}) {
	my $parent = &btrfs_quota_parent_id($d);
	my $err;
	my $q = &get_btrfs_qgroup_by_path(
		$user->{'home'}, 1, \$err);
	return $err if (!$q);
	if ($parent && grep { $_ eq $parent } @{$q->{'parents'} || [ ]}) {
		$err = &quota::unassign_btrfs_qgroup(
			$fs, "0/$id", $parent);
		return $err if ($err);
		&clear_btrfs_quota_cache();
		}
	}
return &delete_btrfs_subvolume(
	$user->{'home'}, $status->{'enabled'} ? $id : undef);
}

# delete_btrfs_domain_home(&domain)
# Validates nested membership, removes the parent qgroup, and deletes the root.
sub delete_btrfs_domain_home
{
my ($d) = @_;
return undef if ($d->{'parent'} || $d->{'alias'});
my $apierr = &btrfs_quota_api_error();
return $apierr if ($apierr);
my $id = &quota::btrfs_subvolume_id($d->{'home'}, undef);
return undef if (!defined($id));
my $parent = "1/$id";
my $fs = $config{'home_quotas'} || $d->{'home'};
my $status = &quota::btrfs_quota_status($fs);
return &text('btrfs_equotastatus', &btrfs_format_path($fs)) if (!$status);
return $status->{'error'} if ($status->{'error'});
# With qgroups disabled there is no hierarchy to validate or remove.
return &delete_btrfs_subvolume($d->{'home'})
	if (!$status->{'enabled'});
my $list_err;
my $qgroups = &list_btrfs_qgroups(1, \$list_err);
return $list_err || $text{'btrfs_elistqgroups'} if (!$qgroups);
my $parent_qgroup = $main::btrfs_qgroups_by_id_cache->{$parent};
if ($parent_qgroup) {
	# Remove all relationships explicitly. This makes deletion of the
	# Virtualmin-created parent qgroup deterministic instead of depending
	# on asynchronous subvolume cleanup.
	my @children = @{$parent_qgroup->{'children'} || [ ]};
	my @nested = grep { $_ ne "0/$id" } @children;
	return &text('btrfs_edeletenested',
		     &btrfs_format_path($d->{'home'}))
		if (@nested);
	foreach my $child (@children) {
		my $unassign_err = &quota::unassign_btrfs_qgroup(
			$fs, $child, $parent);
		return $unassign_err if ($unassign_err);
		}
	&clear_btrfs_quota_cache();
	}
my $err;
if ($parent_qgroup) {
	# Delete the now-empty parent first. If this fails, the home still
	# exists and a retry can complete both cleanup steps.
	$err = &quota::delete_btrfs_qgroup($fs, $parent);
	return $err if ($err);
	&clear_btrfs_quota_cache();
	}
return &delete_btrfs_subvolume($d->{'home'}, $id);
}

# list_invalid_btrfs_homes([&error])
# Returns existing domain and mailbox homes that are not subvolumes.
sub list_invalid_btrfs_homes
{
my ($errref) = @_;
return ( ) if (!&has_btrfs_quotas());
my $qgroups = &list_btrfs_qgroups(0, $errref);
return ( ) if (!$qgroups);
my @invalid;
# Scan each complete domain tree so deeply nested sub-server users are covered.
foreach my $d (grep { !$_->{'parent'} && !$_->{'alias'} } &list_domains()) {
	if (-d $d->{'home'} &&
	    !$main::btrfs_qgroups_by_path_cache->{$d->{'home'}}) {
		push(@invalid, $d->{'home'});
		}
	foreach my $user_domain (&list_btrfs_domain_tree($d)) {
		foreach my $u (&list_domain_users(
				$user_domain, 1, 1, 1, 1)) {
			next if (!$u->{'home'} || $u->{'nocreatehome'} ||
				 $u->{'webowner'});
			if (-d $u->{'home'} &&
			    !$main::btrfs_qgroups_by_path_cache->{$u->{'home'}}) {
				push(@invalid, $u->{'home'});
				}
			}
		}
	}
$$errref = undef if ($errref);
return &unique(@invalid);
}

1;
