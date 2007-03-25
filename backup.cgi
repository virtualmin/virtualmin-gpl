#!/usr/local/bin/perl
# Do an immediate virtual server backup

require './virtual-server-lib.pl';
&ReadParse();

# Validate inputs
&error_setup($text{'backup_err'});
if ($in{'all'} == 1) {
	@doms = &list_domains();
	}
elsif ($in{'all'} == 2) {
	%exc = map { $_, 1 } split(/\0/, $in{'doms'});
	@doms = grep { !$exc{$_->{'id'}} } &list_domains();
	}
else {
	foreach $d (split(/\0/, $in{'doms'})) {
		push(@doms, &get_domain($d));
		}
	}
if (@doms) {
	foreach my $bd (@doms) {
		$cbmode ||= &can_backup_domain($bd);
		}
	$cbmode || &error($text{'backup_ecannot'});
	}
else {
	$cbmode = &can_backup_domain();
	}

if ($in{'feature_all'}) {
	@do_features = ( &get_available_backup_features(), @backup_plugins );
	}
else {
	@do_features = split(/\0/, $in{'feature'});
	}
@do_features || &error($text{'backup_efeatures'});
$dest = &parse_backup_destination("dest", \%in, $cbmode == 2, $doms[0]);
$origdest = $dest;
$dest = &backup_strftime($dest) if ($in{'strftime'});
if ($in{'onebyone'}) {
	$in{'dest_mode'} > 0 || &error($text{'backup_eonebyone1'});
	$in{'fmt'} == 2 || &error($text{'backup_eonebyone2'});
	}

# Parse option inputs
foreach $f (@do_features) {
	local $ofunc = "parse_backup_$f";
	if (&indexof($f, @backup_plugins) < 0 &&
	    defined(&$ofunc)) {
		$options{$f} = &$ofunc(\%in);
		}
	elsif (&indexof($f, @backup_plugins) >= 0 &&
	       &plugin_defined($f, "feature_backup_parse")) {
		$options{$f} = &plugin_call($f, "feature_backup_parse", \%in);
		}
	}

# Parse Virtualmin feature inputs
if (&can_backup_virtualmin()) {
	@vbs = split(/\0/, $in{'virtualmin'});
	}
else {
	@vbs = ( );
	}
@doms || @vbs || &error($text{'backup_edoms'});

if (defined($in{'dom'})) {
	# Save domain-specific backup options
	$d = &get_domain($in{'dom'});
	$d->{'backup_dest'} = $origdest;
	$d->{'backup_fmt'} = $in{'fmt'};
	$d->{'backup_mkdir'} = $in{'mkdir'};
	$d->{'backup_errors'} = $in{'backup_errors'};
	$d->{'backup_strftime'} = $in{'backup_strftime'};
	$d->{'backup_onebyone'} = $in{'backup_onebyone'};
	&save_domain($d);

	# Create virtualmin-backup directory
	$homebk = "$d->{'home'}/virtualmin-backup";
	if ($in{'dest_mode'} == 0 && &can_backup_domain($d) == 2 &&
	    $d->{'dir'} && !-d $homebk) {
		&make_dir($homebk, 0700);
		&set_ownership_permissions($d->{'uid'}, $d->{'ugid'}, 0700,
					   $homebk);
		}
	}

&ui_print_unbuffered_header(undef, $text{'backup_title'}, "");

$nice = &nice_backup_url($dest);
if (@doms) {
	print &text('backup_doing', scalar(@doms), $nice),"<p>\n";
	}
else {
	print &text('backup_doing2', scalar(@vbs), $nice),"<p>\n";
	}
($ok, $size) = &backup_domains($dest, \@doms, \@do_features,
			       $in{'fmt'}, $in{'errors'}, \%options,
			       $in{'fmt'} == 2, \@vbs, $in{'mkdir'},
			       $in{'onebyone'}, $cbmode == 2);
&run_post_actions();
if (!$ok) {
	#&unlink_file($dest);
	print "<p>",$text{'backup_failed'},"<p>\n";
	}
else {
	print "<p>",&text('backup_done', &nice_size($size)),"<p>\n";
	&webmin_log("backup", $dest, undef,
		    { 'doms' => [ map { $_->{'dom'} } @doms ] });
	}

if (defined($in{'dom'})) {
	# Link is back to view/edit form
	&ui_print_footer(&domain_footer_link(&get_domain($in{'dom'})));
	}
else {
	&ui_print_footer("", $text{'index_return'});
	}


