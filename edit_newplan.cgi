#!/usr/local/bin/perl
# Show a list of all plans the current user owns

require './virtual-server-lib.pl';
$canplans = &can_edit_plans();
$canplans || &error($text{'plans_ecannot'});
&ui_print_header(undef, $text{'plans_title'}, "", "plans");

# Get plans and make the table
$bsize = &quota_bsize("home");
@plans = &list_editable_plans();
@table = ( );
foreach $plan (@plans) {
	local @cols;
	push(@cols, { 'type' => 'checkbox', 'name' => 'd',
		      'value' => $plan->{'id'} });
	push(@cols, &html_escape($plan->{'name'}));
	push(@cols, $plan->{'quota'} ? &nice_size($plan->{'quota'}*$bsize)
				     : $text{'form_unlimit'});
	push(@cols, $plan->{'bw'} ? &nice_size($plan->{'bw'})
				  : $text{'form_unlimit'});
	push(@cols, $plan->{'domslimit'} eq '' ? text{'form_unlimit'}
					       : $plan->{'domslimit'});
	push(@cols, $plan->{'mailboxlimit'} eq '' ? text{'form_unlimit'}
					          : $plan->{'mailboxlimit'});
	push(@cols, $plan->{'aliaslimit'} eq '' ? text{'form_unlimit'}
					        : $plan->{'aliaslimit'});
	push(@table, \@cols);
	}

# Show the table
print &ui_form_columns_table(
	"delete_plans.cgi",
	[ [ "delete", $text{'plans_delete'} ] ],
	1,
	[ [ "edit_plan.cgi?new=1", $text{'plans_add'} ] ],
	undef,
	[ "", $text{'plans_name'}, $text{'plans_quota'}, $text{'plans_bw'},
	  $text{'plans_doms'}, $text{'plans_mailboxes'},
	  $text{'plans_aliases'} ],
	100,
	\@table,
	undef,
	0,
	undef,
	$canplans == 2 ? $text{'plans_none'} : $text{'plans_none2'});

&ui_print_footer("", $text{'index_return'});
