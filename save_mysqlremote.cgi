#!/usr/local/bin/perl
# Show all MySQL and PostgreSQL databases owned by this domain

require './virtual-server-lib.pl';
&ReadParse();
$d = &get_domain($in{'dom'});
&can_edit_domain($d) || &error($text{'edit_ecannot'});
&can_edit_databases($d) || &error($text{'databases_ecannot'});
&can_edit_templates() || &error($text{'databases_ecannot'});

# Get the new module
my @mymods = &list_remote_mysql_modules();
my ($mymod) = grep { ($d->{'mysql_module'} || 'mysql') eq
		     $_->{'minfo'}->{'dir'} } @mymods;
my ($newmod) = grep { $in{'mymod'} eq $_->{'minfo'}->{'dir'} } @mymods;
if ($mymod->{'minfo'}->{'dir'} eq $newmod->{'minfo'}->{'dir'}) {
	# Nothing to do, bail out
	&redirect("list_databases.cgi?dom=$in{'dom'}&databasemode=remote");
	return;
	}

# Do the move
&ui_print_unbuffered_header(&domain_in($d), $text{'databases_title'}, "");

print "<b>",&text('databases_moving',
		  $mymod->{'desc'}, $newmod->{'desc'}),"</b><p>\n";

&move_mysql_server($d, $newmod->{'minfo'}->{'dir'});
&webmin_log("mysqlremote", "domain", $d->{'dom'}, $d);

&ui_print_footer("list_databases.cgi?dom=$in{'dom'}", $text{'databases_return'});
