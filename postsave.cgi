#!/usr/local/bin/perl
# Display some useful info after a domain is saved

require './virtual-server-lib.pl';
&ReadParse();
$d = &get_domain($in{'dom'});
$d || &error($text{'edit_egone'});
&can_edit_domain($d) || &error($text{'edit_ecannot'});

&ui_print_header(&domain_in($d), $text{'postsave_title'}, "");

# Show OK message and useful links
print &text('postsave_done', "<tt>$d->{'dom'}</tt>"),"<p>\n";

print "<ul>\n";

# View/edit domain
if (&can_config_domain($d)) {
	print "<li><a href='edit_domain.cgi?dom=$d->{'id'}'>",
	      "$text{'postsave_edit'}</a><p>\n";
	}
else {
	print "<li><a href='view_domain.cgi?dom=$d->{'id'}'>",
	      "$text{'postsave_view'}</a><p>\n";
	}

# Mailboxes / aliases / DBs
if (&can_edit_users()) {
	print "<li><a href='list_users.cgi?dom=$d->{'id'}'>",
	      "$text{'postsave_users'}</a><p>\n";
	}
if (&can_edit_aliases()) {
	print "<li><a href='list_aliases.cgi?dom=$d->{'id'}'>",
	      "$text{'postsave_aliases'}</a><p>\n";
	}
if (&can_edit_databases()) {
	print "<li><a href='list_databases.cgi?dom=$d->{'id'}'>",
	      "$text{'postsave_databases'}</a><p>\n";
	}

# Return to list of domains
print "<li><a href='index.cgi'>$text{'postsave_index'}</a><p>\n";

print "</ul>\n";

if ($in{'refresh'} && defined(&theme_post_save_domain)) {
	&theme_post_save_domain($d, 'modify');
	}

&ui_print_footer();

