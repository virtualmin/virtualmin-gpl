#!/usr/local/bin/perl
# Show disk usage for one virtual server, broken down by directory

require './virtual-server-lib.pl';
&ReadParse();
$d = &get_domain($in{'dom'});
&can_edit_domain($d) || &error($text{'newbw_ecannot'});

$subh = &domain_in($d);
&ui_print_header($subh, $text{'usage_title'}, "", "usage");

# First work out what tabs we have
@tabs = ( );
$prog = "usage.cgi?dom=$in{'dom'}&mode=";
if (&has_home_quotas()) {
	push(@tabs, [ "summary", $text{'usage_tabsummary'}, $prog."summary" ]);
	}
push(@tabs, [ "homes", $text{'usage_tabhomes'}, $prog."homes" ]);
push(@tabs, [ "users", $text{'usage_tabusers'}, $prog."users" ]);
push(@tabs, [ "subs", $text{'usage_tabsubs'}, $prog."subs" ]);
push(@tabs, [ "dbs", $text{'usage_tabdbs'}, $prog."dbs" ]);
print &ui_tabs_start(\@tabs, "mode", $in{'mode'} || $tabs[0]->[0], 1);

# Show quota usage
if (&has_home_quotas()) {
	print &ui_tabs_start_tab("mode", "summary");
	print $text{'usage_summaryheader'},"<p>\n";
	$homesize = &quota_bsize("home");
	$mailsize = &quota_bsize("mail");
	print &ui_table_start(undef, undef, 4);

	print &ui_table_row($text{'usage_squota'},
			    &quota_show($d->{'quota'}));

	($home, $mail, $db) = &get_domain_quota($d, 1);
	$usage = $home*$homesize + $mail*$mailsize;
	print &ui_table_row($text{'usage_susage'},
			    &nice_size($usage));

	print &ui_table_row($text{'usage_sdb'},
			    &nice_size($db));

	if ($d->{'quota'}) {
		$pc = 100*($usage + $db) / ($d->{'quota'}*$homesize);
		$pc = int($pc)."%";
		print &ui_table_row($text{'usage_spercent'},
			   $pc >= 100 ? "<font color=#ff0000>$pc</font>" : $pc);
		}

	print &ui_table_end();
	print &ui_tabs_end_tab();
	}

# Show usage by each sub-directory under home, and sub-dirs under public_html
opendir(DIR, $d->{'home'});
@dirs = grep { $_ ne ".." } readdir(DIR);
closedir(DIR);
$phd = &public_html_dir($d, 1);
if (-r "$d->{'home'}/$phd") {
	opendir(DIR, "$d->{'home'}/$phd");
	push(@dirs, map { "$phd/$_" }
			grep { $_ ne ".." && $_ ne "." } readdir(DIR));
	closedir(DIR);
	}
@dirs = sort { $a cmp $b } @dirs;
foreach $dir (@dirs) {
	local $path = "$d->{'home'}/$dir";
	local $levels = $dir eq "domains" || $dir eq "homes" ||
			$dir eq "." || $dir eq $phd ? 0 : undef;
	($dirusage) = &recursive_disk_usage_mtime($path, undef, $levels);
	($dirgid) = &recursive_disk_usage_mtime($path, $d->{'gid'}, $levels);
	if (-d $path && $dir ne ".") {
		push(@dirusage, [ $dir, &nice_size($dirgid), $dirusage ]);
		}
	else {
		$others += $dirusage;
		$othersgid += $dirgid;
		}
	}
push(@dirusage, [ "<i>$text{'usage_others'}</i>", &nice_size($othersgid), $others ]);
closedir(DIR);
print &ui_tabs_start_tab("mode", "homes");
&usage_table(\@dirusage, $text{'usage_dir'}, 0, $text{'usage_dirheader'},
	     $text{'usage_sizegid'});
print &ui_tabs_end_tab();

# Show usage by top 10 mail users, in all domains
foreach $sd ($d, &get_domain_by("parent", $d->{'id'})) {
	@users = &list_domain_users($sd, 0, 1, 0, 1);
	foreach my $u (@users) {
		next if ($u->{'webowner'});
		if ($u->{'domainowner'}) {
			# Only show mail for domain owner
			($uusage) = &mail_file_size($u);
			}
		elsif (&has_home_quotas()) {
			$uusage = $u->{'uquota'}*$homesize +
				  $u->{'umquota'}*$mailsize;
			}
		else {
			($uusage) = &recursive_disk_usage_mtime($u->{'home'});
			if (!&mail_under_home()) {
				($umail) = &mail_file_size($u);
				$uusage += $umail;
				}
			}
		push(@userusage,
		     [ &remove_userdom($u->{'user'}, $sd),
		       &show_domain_name($sd),
		       $uusage ]);
		}
	}
print &ui_tabs_start_tab("mode", "users");
&usage_table(\@userusage, $text{'usage_user'}, $in{'all'} ? 0 : 10,
	     $text{'usage_userheader'}, $text{'usage_dom'});
print &ui_tabs_end_tab();

# Show usage by sub-servers
@subs = &get_domain_by("parent", $d->{'id'});
foreach $sd (@subs) {
	next if (!$sd->{'dir'});
	($susage) = &recursive_disk_usage_mtime($sd->{'home'});
	push(@subusage, [ &show_domain_name($sd), $susage ]);
	}
print &ui_tabs_start_tab("mode", "subs");
&usage_table(\@subusage, $text{'usage_sub'}, $in{'all'} ? 0 : 10,
	     $text{'usage_subheader'});
print &ui_tabs_end_tab();

# Show usage by databases
$dbtotal = 0;
foreach $sd ($d, @subs) {
	foreach $db (&domain_databases($sd)) {
		($dbu, $dbq) = &get_one_database_usage($sd, $db);
		push(@dbusage, [ $db->{'name'}, &show_domain_name($sd), $dbu ]);
		$dbtotal += $dbu;
		}
	}
print &ui_tabs_start_tab("mode", "dbs");
&usage_table(\@dbusage, $text{'usage_db'}, $in{'all'} ? 0 : 10,
	     $text{'usage_dbheader'}, $text{'usage_dom'});
print &ui_tabs_end_tab();

print &ui_tabs_end(1);

&ui_print_footer(&domain_footer_link($d));

sub usage_table
{
local ($list, $type, $max, $title, $type2) = @_;
local @table;

# Make the data
my $i = 0;
my $total = 0;
foreach my $l (sort { $b->[@$b-1] <=> $a->[@$a-1] } @$list) {
	local @rest = @$l;
	local $sz = pop(@rest);
	push(@table, [ @rest, &nice_size($sz) ]);
	$i++;
	last if ($max && $i > $max);
	}
foreach my $l (@$list) {
	$total += $l->[@$l-1];
	}
push(@table, [ "<b>$text{'usage_total'}</b>",
		$type2 ? ( "" ) : ( ),
		"<b>".&nice_size($total)."</b>" ]);

# Show the table
print $title,"<p>\n";
print &ui_columns_table(
	[ $type, $type2 ? ( $type2 ) : ( ), $text{'usage_size'} ],
	undef,
	\@table,
	undef,
	0,
	undef,
	$text{'usage_none'},
	);
if ($max && @$list > $max) {
	print "<i>",&text('usage_max', $max)," ",
	      "<a href='usage.cgi?dom=$in{'dom'}&all=1'>",
	      $text{'usage_showall'},"</a></i><br>\n";
	}
}

