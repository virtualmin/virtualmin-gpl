#!/usr/local/bin/perl
# Create or edit an API account and its command and resource permissions.

# Check the administrator role before rendering.
require './virtual-server-lib.pl';
&ReadParse();
&master_admin() || &error($text{'apiaccess_ecannot'});
&ui_print_header(undef, $text{'apiaccess_title'}, '');
print &ui_page_start();

if (!$in{'new'}) {
	# This page edits dedicated API accounts, not other Webmin users.
	($user) = &list_api_access_users($in{'user'});
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
	'badges' => $_->{'pro'} && !$virtualmin_pro ? [ [ 'Pro', 'warning' ] ] : [],
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

# Load existing servers and their saved manual selections.
@domains = sort { $a->{'dom'} cmp $b->{'dom'} }
	&list_api_access_resources('domain');
my %manual = map { $_ => 1 } split(/\s+/, $p->{'api_domains'});
my %automatic;
if ($p->{'api_id'}) {
	# Use the access check to find this account's creations and descendants.
	# Ignore manual grants and disabled settings when finding these servers.
	local %access = ( %$p, 'api_domains' => '', 'api_created' => 1,
		'api_disabled' => 0 );
	%automatic = map { $_->{'id'} => 1 }
		grep { &api_access_can_domain($_) } @domains;
	}
# Lock automatic selections while the switch is on; manual grants stay editable.
# Mark eligible rows so the browser can update them when the switch changes.
@domain_options = map { {
	'value' => $_->{'id'}, 'label' => $_->{'dom'},
	'disabled' => $p->{'api_created'} && $automatic{$_->{'id'}} &&
		!$manual{$_->{'id'}},
	'attrs' => { 'data-api-created' => $automatic{$_->{'id'}} ? 1 : 0 },
	'badges' => $automatic{$_->{'id'}} ?
		[ [ $text{'apiaccess_automatic'}, 'info',
			{ 'class' => 'api_access_auto_badge', 'small' => 1,
			  'title' => $text{'apiaccess_automaticdesc'} } ] ] : []
	} } @domains;
# Include automatic checks only while enabled; '*' belongs to the mode selector.
my @domain_values = grep { $_ ne '*' } keys %manual;
push(@domain_values, keys %automatic) if ($p->{'api_created'});
# The displayed selection includes automatic grants; submit only manual ones.
my $domain_field = %automatic ? 'domains_display' : 'domains';
%domain_modes = ( 'name' => 'domain_mode',
	'value' => $p->{'api_domains'} eq '*' ? 'all' : 'selected',
	'options' => [ [ 'selected', $text{'apiaccess_selected'} ],
		[ 'all', $text{'apiaccess_all'} ] ], 'hide' => [ 'all' ] );
# All is a mode, not a selectable ID. Keep it editable on an empty server too.
$domain_input = @domain_options ?
	&ui_multi_select_list($domain_field, \@domain_values, \@domain_options,
		{ 'modes' => \%domain_modes }) :
	&ui_select('domain_mode', $domain_modes{'value'}, $domain_modes{'options'}).
		&ui_hidden('domains', '');
# With automatic rows, submit manual grants through a separate hidden field.
$domain_input .= &ui_hidden('domains', join("\n", grep { $_ ne '*' } keys %manual))
	if (%automatic);
# Hide the switch in All mode without clearing it. Show the Automatic badge only
# on locked rows, not on manual selections or while automatic access is off.
print &ui_tag('style',
	'.api_access_domains:has(select[name="domain_mode"] option[value="all"]:checked) '.
	'.api_access_created { display: none; } '.
	'.api_access_domains .ui_multi_item:not(.ui_multi_disabled) '.
	'.api_access_auto_badge { display: none; }');
print &ui_table_row(&hlink($text{'apiaccess_domains'}, 'api_access_scope'),
	&ui_stack([ $domain_input,
	&ui_toggle({ 'name' => 'created', 'value' => 1,
		'label_html' => &hlink($text{'apiaccess_created'}, 'api_access_created'),
		'checked' => $p->{'api_created'},
		'state' => 'primary', 'outline' => 1,
		'class' => 'api_access_created' }) ],
		{ 'class' => 'api_access_domains' }),
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
# Only accounts with automatic rows need this sync between displayed and saved
# choices. The shared widget still handles selection, filtering and counts.
if (%automatic) {
print <<'EOF';
<script>
// Initialize the automatic-selection controls in this private scope.
(function () {
	const list = document.getElementById('ui_multi_domains_display');
	const form = list.closest('form');
	const created = form.elements.created;
	const manual = form.elements.domains;
	const rows = list.querySelectorAll('.ui_multi_item');
	// sync(): update automatic checks without changing manual permissions.
	function sync() {
		const selected = [];
		// For each row, keep manual choices and apply the switch.
		rows.forEach(function (row) {
			const input = row.querySelector('input[type="checkbox"]');
			// Disabled checks are automatic; never copy them into manual grants.
			const explicit = !input.disabled && input.checked;
			input.disabled = created.checked && row.dataset.apiCreated === '1' && !explicit;
			input.checked = input.disabled || explicit;
			row.classList.toggle('ui_multi_disabled', input.disabled);
			// Save only manual grants.
			if (explicit) selected.push(input.value);
		});
		// Update the submitted grants and refresh the widget's display.
		manual.value = selected.join('\n');
		list.dispatchEvent(new Event('change', { bubbles: true }));
	}
	// For each event type, listen for widget actions and switch changes.
	['click', 'change'].forEach(function (type) {
		// Handle each event after the widget's bulk or Shift actions.
		form.addEventListener(type, function (event) {
			// Skip our own change event and unrelated fields.
			if (event.target !== list && (list.contains(event.target) || event.target === created)) {
				setTimeout(sync, 0);
			}
		});
	});
	// Sync before submission, even if a deferred update is pending.
	form.addEventListener('submit', sync);
	// Apply the saved switch state when the form first opens.
	sync();
}());
</script>
EOF
}
print &ui_page_end();
&ui_print_footer('api_access.cgi', $text{'apiaccess_return'});
