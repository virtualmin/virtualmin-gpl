#!/usr/local/bin/perl
# List dedicated API accounts and edit their command and resource policies.

# Check the administrator role and required Webmin support before rendering.
require './virtual-server-lib.pl';
&ReadParse();
&master_admin() || &error($text{'apiaccess_ecannot'});
defined(&webmin_user_api_only) && defined(&ui_multi_select_list) &&
	defined(&ui_form_grouped_buttons) ||
	&error($text{'apiaccess_ewebmin'});
# Show overview help on the account list; forms have field-specific help.
&ui_print_header(undef, $text{'apiaccess_title'}, '',
	!$in{'new'} && !defined($in{'user'}) ? 'api_access' : undef);
# Load widget assets and provide their shared colors and spacing on every view.
print &ui_page_start();
@users = &list_api_access_users();

if (!$in{'new'} && !defined($in{'user'})) {
	# Requests without an account selection show the account list.
	if (!@users) {
		# Give the first account a clear starting point instead of an empty table.
		print &ui_empty_state({ 'icon' => 'key',
			'title' => $text{'apiaccess_empty'},
			'desc' => $text{'apiaccess_emptydesc'},
			'actions' => &ui_link_button('api_access.cgi?new=1',
				$text{'apiaccess_add'}) });
		print &ui_page_end();
		&ui_print_footer('', $text{'index_return'});
		exit;
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
			&ui_link('api_access.cgi?user='.&urlize($user->{'name'}),
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
		[ [ 'api_access.cgi?new=1', $text{'apiaccess_add'} ] ],
		[ [ 'bulk', 1 ] ],
		[ '', $text{'apiaccess_user'},
		  $show_desc ? ( $text{'apiaccess_desc'} ) : ( ),
		  $text{'apiaccess_status'},
		  $text{'apiaccess_commands'} ], 100, \@rows,
		undef, 0, undef, undef, 0, 1);
	print &ui_page_end();
	&ui_print_footer('', $text{'index_return'});
	exit;
	}

if (!$in{'new'}) {
	# This page edits dedicated API accounts, not other Webmin users.
	($user) = grep { $_->{'name'} eq $in{'user'} } @users;
	$user || &error($text{'apiaccess_egone'});
	$p = $user->{'policy'};
	}
else {
	# Use the server's creation defaults; commands still need explicit grants.
	$p = &default_api_access_policy();
	}

# Carry the account ID so saving cannot overwrite a replacement login.
print &ui_form_start('save_api_access.cgi', 'post');
print &ui_hidden('new', $in{'new'} ? 1 : 0);
print &ui_hidden('old', $user->{'name'});
print &ui_hidden('id', $p->{'api_id'});
print &ui_table_start($text{'apiaccess_account'}, undef, 2);
# Use the theme's green on-state and red off-state without extra JavaScript.
my $enabled = &ui_field($text{'apiaccess_enabled'},
	&ui_tag('span', &ui_toggle({ 'name' => 'enabled', 'value' => 1,
		'checked' => !$p->{'api_disabled'}, 'state' => 'success', 'outline' => 1,
		'attrs' => { 'aria-label' => $text{'apiaccess_enabled'} } }),
		{ 'style' => '--ui-toggle-bg:var(--ui-danger)' }),
	{ 'for' => 'enabled_1' });
# Keep the status toggle below the username within the same table row.
print &ui_table_row(&hlink($text{'apiaccess_user'}, 'api_access_user'),
	&ui_stack([ $in{'new'} ? &ui_textbox('name', '', 30) :
		&html_escape($user->{'name'}), $enabled ]));
# Share the description with Webmin's user editor through its real-name field.
print &ui_table_row(&hlink($text{'apiaccess_desc'}, 'api_access_desc'),
	&ui_textbox('desc', $user->{'real'}, 40));
# Make password changes explicit on edit; never send stored credentials.
print &ui_table_row(&hlink($text{'apiaccess_password'}, 'api_access_password'),
	$in{'new'} ?
	&ui_password('password', '', 40, undef, undef, 'autocomplete=new-password') :
	&ui_opt_textbox('password', undef, 40, $text{'edit_lv'}, $text{'edit_set'},
		undef, undef, undef, 'autocomplete=new-password', 'password'));
print &ui_table_end();

# All selection modes save a fixed list of commands and their providers.
# Newly added commands and different providers need a separate grant.
@catalog = &list_api_access_commands();
# Show module titles on badges; keep provider IDs in permission values.
my %provider_labels;
foreach my $provider (&unique(map { $_->{'provider'} } @catalog)) {
	# Pro scripts use the parent module's title with a separate Pro suffix.
	my $pro = $provider eq "$module_name/pro";
	my $mod = $pro ? $module_name : $provider;
	my %info = &get_module_info($mod);
	$provider_labels{$provider} =
		($info{'shortdesc'} || $info{'desc'} || $mod).($pro ? ' Pro' : '');
	}
# Group commands by scope, with descriptions available as tooltips.
# Keep Pro entries visible but disabled on GPL, with a badge explaining why.
@command_options = map { {
	'value' => $_->{'key'}, 'label' => $_->{'name'},
	'tag' => $provider_labels{$_->{'provider'}},
	'badges' => $_->{'pro'} ? [ [ 'Pro', 'warning' ] ] : [],
	'disabled' => $_->{'pro'} && !$virtualmin_pro,
	'attrs' => { 'title' => $_->{'desc'} },
	'group' => { 'label' => $text{$_->{'scoped'} ? 'apiaccess_scoped' :
		'apiaccess_system'}, 'state' => $_->{'scoped'} ? 'info' : 'warning',
		'icon' => $_->{'scoped'} ? 'shield' : 'server' }
	} } sort { $b->{'scoped'} <=> $a->{'scoped'} ||
		$a->{'name'} cmp $b->{'name'} } @catalog;
# Keep command permissions collapsible and open by default.
print &ui_hidden_table_start($text{'apiaccess_permissions'}, 'width=100%', 2,
	'permissions', 1);
# The widget's hidden field preserves checked, disabled grants on form saves.
print &ui_table_row(&hlink($text{'apiaccess_commands'}, 'api_access_commands'),
	&ui_multi_select_list('commands', [ split(/\s+/, $p->{'api_commands'}) ],
		\@command_options, { 'height' => '305px', 'search' => 1,
		'modes' => { 'name' => 'command_mode', 'value' => 'include',
			'options' => [ [ 'include', $text{'apiaccess_include'} ],
				[ 'exclude', $text{'apiaccess_exclude'} ],
				[ 'all', $text{'apiaccess_allcommands'} ] ],
			'hide' => [ 'all' ] } }),
	undef, undef, undef, 1);
print &ui_hidden_table_end();
# Resource restrictions have their own initially open section.
print &ui_hidden_table_start($text{'apiaccess_resources'}, 'width=100%', 2,
	'resources', 1);

# Offer existing servers and separate access to servers this account creates.
@domain_options = map { [ $_->{'id'}, $_->{'dom'} ] }
	sort { $a->{'dom'} cmp $b->{'dom'} } &list_api_access_resources('domain');
%domain_modes = ( 'name' => 'domain_mode',
	'value' => $p->{'api_domains'} eq '*' ? 'all' : 'selected',
	'options' => [ [ 'selected', $text{'apiaccess_selected'} ],
		[ 'all', $text{'apiaccess_all'} ] ], 'hide' => [ 'all' ] );
# All is a mode, not a selectable ID. Keep it editable on an empty server too.
$domain_input = @domain_options ?
	&ui_multi_select_list('domains', $p->{'api_domains'} eq '*' ? [] :
		[ split(/\s+/, $p->{'api_domains'}) ], \@domain_options,
		{ 'modes' => \%domain_modes }) :
	&ui_select('domain_mode', $domain_modes{'value'}, $domain_modes{'options'}).
		&ui_hidden('domains', '');
print &ui_table_row(&hlink($text{'apiaccess_domains'}, 'api_access_scope'),
	&ui_stack([ $domain_input,
	&ui_toggle({ 'name' => 'created', 'value' => 1,
		'label_html' => &hlink($text{'apiaccess_created'}, 'api_access_created'),
		'checked' => $p->{'api_created'},
		'state' => 'primary', 'outline' => 1 }) ]),
	undef, undef, undef, 1);

# Template and plan selections allow use; editing them needs separate grants.
foreach my $kind ('template', 'plan') {
	my @items = &list_api_access_resources($kind);
	my @options = map { [ $_->{'id'}, $_->{'name'} ] } @items;
	print &ui_table_row(&hlink($text{"apiaccess_${kind}s"}, "api_access_${kind}s"),
		&ui_multi_select_list($kind.'s',
			$p->{"api_${kind}s"} eq '*' ? [] :
			[ split(/\s+/, $p->{"api_${kind}s"}) ], \@options,
			{ 'modes' => { 'name' => $kind.'_mode',
			'value' => $p->{"api_${kind}s"} eq '*' ? 'all' : 'selected',
			'options' => [ [ 'selected', $text{'apiaccess_selected'} ],
				[ 'all', $text{'apiaccess_all'} ] ],
			'hide' => [ 'all' ] } }));
	# Give each creation default a separate row below its allowed choices.
	print &ui_table_row(&hlink($text{'apiaccess_default'.$kind},
		'api_access_default'.$kind),
		&ui_select($kind, $p->{'api_'.$kind}, \@options));
	}
print &ui_hidden_table_end();
# Deleting an API account leaves its virtual servers in place.
@buttons = ( [ 'save', $text{'save'} ] );
@delete_buttons = $in{'new'} ? ( ) : ( [ 'delete', $text{'delete'} ] );
print &ui_form_grouped_buttons([ \@buttons, \@delete_buttons ]);
print &ui_form_end();
print &ui_page_end();
&ui_print_footer('api_access.cgi', $text{'apiaccess_return'});
