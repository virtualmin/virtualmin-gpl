# Functions for managing plans, which are sets of limits separate from templates

# list_plans()
# Returns a list of all plans, each of which is a hash ref
sub list_plans
{
}

# save_plan(&plan)
# Updates or creates a plan on disk
sub save_plan
{
}

# delete_plan(&plan)
# Deletes an existing plan.
sub delete_plan
{
# XXX what if in use?
}

# convert_plans()
# Converts all templates that have owner limits into plans, and updates virtual
# servers to refer to the converted plan. Only designed to be called once at
# installation time, to handle upgrades.
sub convert_plans
{
}

1;

