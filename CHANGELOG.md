## Release 0.4.0

### New features

* **Add debugging statements to task errors**
  ([#9](https://github.com/puppetlabs/puppetlabs-azure_inventory/pull/9))

  Error objects returned from the `resolve_reference` task now includes
  debugging statements that describe the steps the task is taking under
  the `details` key.

### Bug fixes

* **Add missing dependency to module metadata**
  ([#10](https://github.com/puppetlabs/puppetlabs-azure_inventory/pull/9))

  The module metadata now includes `ruby_plugin_helper` and `ruby_task_helper`
  as dependencies.

## Release 0.3.0

### New features

* **Set `resolve_reference` task to private** ([#6](https://github.com/puppetlabs/puppetlabs-azure_inventory/pull/6))

    The `resolve_reference` task has been set to `private` so it no longer appears in UI lists.

## Release 0.2.0

**Changes**

This converts the module to a Bolt plugin, which includes renaming the `inventory_targets` task to `resolve_references`.

## Release 0.1.0

This is the initial release.
