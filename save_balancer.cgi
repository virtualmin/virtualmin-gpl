#!/usr/local/bin/perl
# Create, update or delete a proxy balancer

$0 =~ /^(.*)\/pro\// && chdir($1);
require './virtual-server-lib.pl';
&ReadParse();
$d = &get_domain($in{'dom'});
&can_edit_domain($d) && &can_edit_forward() ||
	&error($text{'balancers_ecannot'});
$has = &has_proxy_balancer($d);
$has || &error($text{'balancers_esupport'});
&error_setup($text{'balancer_err'});
if (!$in{'new'}) {
	($b) = grep { $_->{'path'} eq $in{'old'} } &list_proxy_balancers($d);
	$b || &error($text{'balancer_egone'});
	$oldb = { %$b };
	}
&obtain_lock_web($d);

if ($in{'delete'}) {
	# Just delete it
	$err = &delete_proxy_balancer($d, $b);
	&error($err) if ($err);
	}
else {
	# Validate inputs
	$in{'path'} =~ /^\/\S*$/ || &error($text{'balancer_epath'});
	if ($in{'new'}) {
		if ($has == 1) {
			# Doesn't support balancers
			$b = { };
			}
		elsif ($in{'none'}) {
			# In no-proxy mode, we don't need balancing
			$b = { };
			}
		elsif ($in{'balancer_def'}) {
			# Choose name automatically
			$in{'path'} =~ /^\/(\S*)$/;
			$b = { 'balancer' => $1 || "root" };
			}
		else {
			# Use entered name
			$in{'balancer'} =~ /^[a-z0-9\_]+$/i ||
				&error($text{'balancer_ebalancer'});
			$b = { 'balancer' => $in{'balancer'} };
			}
		}
	$b->{'path'} = $in{'path'};
	if ($in{'none'}) {
		# Not proxying anywhere
		$b->{'none'} = 1;
		}
	elsif ($in{'new'} && $has == 2 || !$in{'new'} && $b->{'balancer'}) {
		# Many URLs
		@urls = grep { /\S/ } split(/\r?\n/, $in{'urls'});
		foreach my $u (@urls) {
			$u =~ /^(http|https):\/\/(\S+)$/ ||
				&error(&text('balancer_eurl', $u));
			}
		@urls || &error($text{'balancer_eurls'});
		$b->{'urls'} = \@urls;
		$b->{'none'} = 0;
		}
	else {
		# One URL
		$in{'urls'} =~ /^(http|https):\/\/(\S+)$/ ||
			&error($text{'balancer_eurl2'});
		$b->{'urls'} = [ $in{'urls'} ];
		$b->{'none'} = 0;
		}

	# Create or update
	if ($in{'new'}) {
		$err = &create_proxy_balancer($d, $b);
		}
	else {
		$err = &modify_proxy_balancer($d, $b, $oldb);
		}
	&error($err) if ($err);
	}

# Restart Apache and log
&release_lock_web($d);
&set_all_null_print();
&run_post_actions();
&webmin_log($in{'new'} ? 'create' : $in{'delete'} ? 'delete' : 'modify',
	    "balancer", $b->{'path'}, { 'dom' => $d->{'dom'} });

&redirect("list_balancers.cgi?dom=$in{'dom'}");

