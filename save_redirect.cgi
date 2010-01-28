#!/usr/local/bin/perl
# Create, update or delete a website redirect

require './virtual-server-lib.pl';
&ReadParse();
$d = &get_domain($in{'dom'});
&can_edit_domain($d) || &error($text{'redirects_ecannot'});
$d->{'web'} || &error($text{'redirects_eweb'});
&error_setup($text{'redirect_err'});
if (!$in{'new'}) {
	($r) = grep { $_->{'path'} eq $in{'path'} } &list_redirects($d);
	$r || &error($text{'redirect_egone'});
	$oldr = { %$r };
	}
&obtain_lock_web($d);

if ($in{'delete'}) {
	# Just delete it
	$err = &delete_redirect($d, $r);
	&error($err) if ($err);
	}
else {
	# Validate inputs
	$in{'path'} =~ /^\/\S*$/ || &error($text{'redirect_epath'});
	$r->{'path'} = $in{'path'};
	if ($in{'mode'} == 0) {
		$in{'url'} =~ /^(http|https):\/\/\S+$/ ||
			&error($text{'redirect_eurl'});
		$r->{'dest'} = $in{'url'};
		}
	else {
		$in{'dir'} =~ /^\/\S+$/ && -d $in{'dir'} ||
			&error($text{'redirect_edir'});
		if ($in{'new'} || $r->{'dest'} ne $in{'dir'}) {
			$rroot = &get_redirect_root($d);
			&is_under_directory($rroot, $in{'dir'}) ||
				&error(&text('redirect_edir2', $rroot));
			}
		$r->{'dest'} = $in{'dir'};
		}
	$r->{'regexp'} = $in{'regexp'};

	# Create or update
	if ($in{'new'}) {
		$err = &create_redirect($d, $r);
		}
	else {
		$err = &modify_redirect($d, $r, $oldr);
		}
	&error($err) if ($err);
	}

# Restart Apache and log
&release_lock_web($d);
&set_all_null_print();
&run_post_actions();
&webmin_log($in{'new'} ? 'create' : $in{'delete'} ? 'delete' : 'modify',
	    "redirect", $r->{'path'}, { 'dom' => $d->{'dom'} });

&redirect("list_redirects.cgi?dom=$in{'dom'}");

