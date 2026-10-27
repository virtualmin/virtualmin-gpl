#!/usr/local/bin/perl
# List dedicated API accounts.

# Check the administrator role before rendering.
require './virtual-server-lib.pl';
&ReadParse();
&master_admin() || &error($text{'apiaccess_ecannot'});
&ui_print_header(undef, $text{'apiaccess_title'}, '', 'api_access');
print &ui_page_start();
@users = &list_api_access_users();

if (!@users) {
	# Give the first account a clear starting point instead of an empty table.
	print &ui_empty_state({ 'icon' => 'key',
		'title' => $text{'apiaccess_empty'},
		'desc' => $text{'apiaccess_emptydesc'},
		'actions' => &ui_link_button('edit_api_access.cgi?new=1',
			$text{'apiaccess_add'}) });
	print &ui_page_end();
	&ui_print_footer('', $text{'index_return'});
	return;
	}
# Show account status without exposing credentials or password hashes.
print &ui_p($text{'apiaccess_intro'});
my @catalog = &list_api_access_commands();
# Omit the description column when every account leaves it blank.
my $show_desc = grep { $_->{'real'} =~ /\S/ } @users;
foreach my $user (sort { $a->{'name'} cmp $b->{'name'} } @users) {
	my $p = $user->{'policy'};
	# Count grants whose provider and edition still allow the command.
	my %grants = map { ($_, 1) } split(/\s+/, $p->{'api_commands'});
	my @allowed = sort { $a->{'name'} cmp $b->{'name'} }
		grep { $grants{$_->{'key'}} &&
			!&api_account_pro_message($_->{'name'}) } @catalog;
	# Leave zero as plain text when no commands can be expanded.
	my $commands = scalar(@allowed);
	if (@allowed) {
		# Expand the count to show each allowed command on its own line.
		$commands = &ui_details({ 'title' => scalar(@allowed),
			'class' => 'inline inlined', 'html' => 1,
			'content' => join('<br>', map {
				'<tt>'.&html_escape($_->{'name'}).'</tt>' } @allowed) });
		}
	# Match row cells to the optional description heading.
	push(@rows, [
		{ 'type' => 'checkbox', 'name' => 'd',
		  'value' => $p->{'api_id'} },
		&ui_link('edit_api_access.cgi?user='.&urlize($user->{'name'}),
			&html_escape($user->{'name'})),
		$show_desc ? ( &html_escape($user->{'real'}) ) : ( ),
		$text{$p->{'api_disabled'} ? 'apiaccess_disabled' :
			'apiaccess_enabled'},
		# Sort by the count, without the expanded command names.
		{ 'type' => 'string', 'value' => $commands,
		  'td' => "data-order='".scalar(@allowed)."'" } ]);
	}
# Submit immutable IDs so stale selections cannot delete replacement logins.
print &ui_form_columns_table('save_api_access.cgi',
	[ [ 'delete', $text{'apiaccess_delete'} ] ], 1,
	[ [ 'edit_api_access.cgi?new=1', $text{'apiaccess_add'} ] ],
	[ [ 'bulk', 1 ] ],
	[ '', $text{'apiaccess_user'},
	  $show_desc ? ( $text{'apiaccess_desc'} ) : ( ),
	  $text{'apiaccess_status'},
	  $text{'apiaccess_commands'} ], 100, \@rows,
	undef, 0, undef, undef, 0, 1);
print &ui_page_end();
&ui_print_footer('', $text{'index_return'});
