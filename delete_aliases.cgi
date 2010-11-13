#!/usr/local/bin/perl
# Delete server aliases from a virtual server

require './virtual-server-lib.pl';
&ReadParse();
&error_setup($text{'aliases_derr'});
$d = &get_domain($in{'dom'});
&can_edit_domain($d) || &error($text{'aliases_ecannot'});
@del = split(/\0/, $in{'d'});
@del || &error($text{'aliases_ednone'});

&obtain_lock_mail($d);
@aliases = &list_domain_aliases($d);

# Do the deletion
foreach $a (@del) {
	($alias) = grep { $_->{'from'} eq $a } @aliases;
	if ($alias) {
		&delete_virtuser($alias);
		if (defined(&get_simple_alias)) {
			$simple = &get_simple_alias($d, $alias);
			&delete_simple_autoreply($d, $simple) if ($simple);
			}
		}
	}
&sync_alias_virtuals($d);
&release_lock_mail($d);
&webmin_log("delete", "aliases", scalar(@del),
	    { 'dom' => $d->{'dom'} });
&redirect("list_aliases.cgi?dom=$in{'dom'}&show=$in{'show'}");

