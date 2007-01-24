#!/usr/local/bin/perl
# Show disk usage for one virtual server, broken down by directory

require './virtual-server-lib.pl';
&ReadParse();

$d=&get_domain($in{'dom'});
&can_edit_domain($d) || &error($text{'newbw_ecannot'});

$subh = &domain_in($d);
&ui_print_header($subh, $text{'usage_title'}, "", "usage");

# Show quota usage
if (&has_home_quotas()) {
	$homesize = &quota_bsize("home");
	$mailsize = &quota_bsize("mail");
	print &ui_table_start($text{'usage_quota'}, undef, 4);

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
	print "<hr>\n";
	}

print "<table width=100%><tr>\n";

# Show usage by each sub-directory under home
opendir(DIR, $d->{'home'});
foreach $dir (readdir(DIR)) {
	next if ($dir eq "..");
	local $path = "$d->{'home'}/$dir";
	local $levels = $dir eq "domains" || $dir eq "homes" ||
			$dir eq "." ? 0 : undef;
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
print "<td valign=top width=25%>\n";
&usage_table(\@dirusage, $text{'usage_dir'}, 0, $text{'usage_dirheader'},
	     $text{'usage_sizegid'});
print "</td>\n";

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
		     [ &remove_userdom($u->{'user'}, $sd), $sd->{'dom'},
		       $uusage ]);
		}
	}
print "<td valign=top width=25%>\n";
&usage_table(\@userusage, $text{'usage_user'}, 10, $text{'usage_userheader'},
	     $text{'usage_dom'});
print "</td>\n";

# Show usage by sub-servers
@subs = &get_domain_by("parent", $d->{'id'});
foreach $sd (@subs) {
	next if (!$sd->{'dir'});
	($susage) = &recursive_disk_usage_mtime($sd->{'home'});
	push(@subusage, [ $sd->{'dom'}, $susage ]);
	}
print "<td valign=top width=25%>\n";
&usage_table(\@subusage, $text{'usage_sub'}, 10, $text{'usage_subheader'});
print "</td>\n";

# Show usage by databases
$dbtotal = 0;
foreach $sd ($d, @subs) {
	foreach $db (&domain_databases($sd)) {
		($dbu, $dbq) = &get_one_database_usage($sd, $db);
		push(@dbusage, [ $db->{'name'}, $sd->{'dom'}, $dbu ]);
		$dbtotal += $dbu;
		}
	}
if ($dbtotal) {
	print "<td valign=top width=25%>\n";
	&usage_table(\@dbusage, $text{'usage_db'}, 10, $text{'usage_dbheader'},
		     $text{'usage_dom'});
	print "</td>\n";
	}

print "</table>\n";

&ui_print_footer(&domain_footer_link($d));

sub usage_table
{
local ($list, $type, $max, $title, $type2) = @_;
print "<b>$title</b><br>\n";
if (@$list) {
	print &ui_columns_start([ $type,
				  $type2 ? ( $type2 ) : ( ),
				  $text{'usage_size'} ]);
	my $i = 0;
	my $total = 0;
	foreach my $l (sort { $b->[@$b-1] <=> $a->[@$a-1] } @$list) {
		local @rest = @$l;
		local $sz = pop(@rest);
		print &ui_columns_row([ @rest, &nice_size($sz) ]);
		$i++;
		last if ($max && $i > $max);
		}
	foreach my $l (@$list) {
		$total += $l->[@$l-1];
		}
	print &ui_columns_row([ "<b>$text{'usage_total'}</b>",
				$type2 ? ( "" ) : ( ),
				"<b>".&nice_size($total)."</b>" ]);
	print &ui_columns_end();
	if ($max && @$list > $max) {
		print "<i>",&text('usage_max', $max),"</i><br>\n";
		}
	}
else {
	print "<i>$text{'usage_none'}</i><br>\n";
	}
}

