
do 'virtual-server-lib.pl';

sub status_monitor_list
{
return ( [ "validate", $text{'monitor_validate'} ] );
}

sub status_monitor_status
{
my ($type, $serv, $fromui) = @_;

# Get the domains to check
my @doms;
if ($serv->{'doms'}) {
	foreach my $id (split(/\s+/, $serv->{'doms'})) {
		my $d = &get_domain($id);
		push(@doms, $d) if ($d);
		}
	}
else {
	@doms = &list_visible_domains();
	}
@doms || return { 'up' => -1,
		  'desc' => $text{'monitor_nodoms'} };

# Get features to check
my @feats;
if ($serv->{'feats'}) {
	@feats = split(/\s+/, $serv->{'feats'});
	}
else {
	@feats = ( @validate_features, &list_feature_plugins() );
	}
@feats || return { 'up' => -1,
		   'desc' => $text{'monitor_nofeats'} };

# Do all the domains and features
my @allerrs;
my $count = 0;
foreach my $d (@doms) {
	my @errs;
	foreach $f (@feats) {
		next if (!$d->{$f});
		if (&indexof($f, &list_feature_plugins()) < 0) {
			# Core feature
			next if (!$config{$f});
			$vfunc = "validate_$f";
			$err = &$vfunc($d);
			$name = $text{'feature_'.$f};
			}
		else {
			# Plugin feature
			$err = &plugin_call($f, "feature_validate", $d);
			$name = &plugin_call($f, "feature_name");
			}
		push(@errs, "$name : $err") if ($err);
		}
	if (@errs) {
		$count += scalar(@errs);
		push(@allerrs, &show_domain_name($d)." - ".join(", ", @errs));
		}
	}
if (@allerrs) {
	return { 'up' => 0,
		 'value' => $count,
		 'desc' => join(" ", @allerrs),
	       },
	}
else {
	return { 'up' => 1,
		 'value' => $count,
		 'desc' => &text('monitor_done', scalar(@doms), scalar(@feats)),
	       };
	}
}

sub status_monitor_dialog
{
my ($type, $serv) = @_;
my $rv = "";

# Domains to check
my @doms = &list_visible_domains();
$rv .= &ui_table_row($text{'monitor_doms'},
    &ui_radio("servers_def", $serv->{'doms'} ? 0 : 1,
	[ [ 1, $text{'newips_all'} ],
	  [ 0, $text{'newips_sel'} ] ])."<br>\n".
    &servers_input("servers", [ split(/\s+/, $serv->{'doms'}) ], \@doms, 0, 1));

# Features to check
my @fopts = &validation_select_features();
$rv .= &ui_table_row($text{'monitor_feats'},
    &ui_radio("features_def", $serv->{'feats'} ? 0 : 1,
	[ [ 1, $text{'newvalidate_all'} ],
	  [ 0, $text{'newvalidate_sel'} ] ])."<br>\n".
    &ui_select("features", [ split(/\s+/, $serv->{'feats'}) ],
	       \@fopts, 10, 1));

return $rv;
}

# status_monitor_parse(&type, &monitor, &in)
sub status_monitor_parse
{
my ($type, $serv, $in) = @_;

if ($in->{'servers_def'}) {
	delete($serv->{'doms'});
	}
else {
	$in->{'servers'} || &error($text{'monitor_edoms'});
	$serv->{'doms'} = join(" ", split(/\s+/, $in->{'servers'}));
	}

if ($in->{'features_def'}) {
	delete($serv->{'feats'});
	}
else {
	$in->{'features'} || &error($text{'monitor_edoms'});
	$serv->{'feats'} = join(" ", split(/\0/, $in->{'features'}));
	}
}
