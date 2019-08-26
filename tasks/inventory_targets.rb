#!/usr/bin/env ruby
# frozen_string_literal: true

require_relative '../../ruby_task_helper/files/task_helper.rb'
require 'net/http'
require 'openssl'

class AzureInventory < TaskHelper
  def inventory_targets(opts)
    creds = credentials(opts)
    token = token(creds)
    vms = nics = ips = nil
    threads = []
    threads << Thread.start { vms = vms(token, creds, opts) }
    threads << Thread.start { nics = index_by_id(nics(token, creds, opts)) }
    threads << Thread.start { ips = index_by_id(ip_addresses(token, creds, opts)) }
    threads.each(&:join)

    vms.map do |vm|
      interfaces = vm.dig('properties', 'networkProfile', 'networkInterfaces')
      nic_ids = interfaces.partition { |nic| nic['primary'] }.flatten.map { |nic| nic['id'] }
      vm_nics = nics.values_at(*nic_ids)

      ip_configs = vm_nics.flat_map do |nic|
        nic.dig('properties', 'ipConfigurations') || nic.dig('properties', 'ipConfiguration')
      end
      ip_ids = ip_configs.map { |ip| ip.dig('properties', 'publicIPAddress', 'id') }
      vm_ips = ips.values_at(*ip_ids)

      ip = vm_ips.compact.first
      if ip
        {
          'name' => ip.dig('properties', 'dnsSettings', 'fqdn') || vm['name'],
          'uri' => ip.dig('properties', 'ipAddress')
        }.compact
      end
    end.compact
  end

  # Hash of required credentials for authorizing with the Azure REST API
  # These values can be set in 2 locations - inventory config or environment variables
  def credentials(opts)
    creds = {
      'tenant_id' => (opts[:tenant_id] || ENV['AZURE_TENANT_ID']),
      'client_id' => (opts[:client_id] || ENV['AZURE_CLIENT_ID']),
      'client_secret' => (opts[:client_secret] || ENV['AZURE_CLIENT_SECRET']),
      'subscription_id' => (opts[:subscription_id] || ENV['AZURE_SUBSCRIPTION_ID'])
    }

    missing_keys = creds.select { |k,v| v.nil? }.keys
    if missing_keys.any?
      msg = "Parameters #{missing_keys.join(', ')} must be specified or set as environment variables"
      raise TaskHelper::Error.new(msg, 'bolt-plugin/validation-error')
    end

    creds
  end

  def get_all_results(url, token)
    header = {
      'Authorization' => "#{token['token_type']} #{token['access_token']}"
    }

    instances = []

    while url do
      # Update the URI and make the next request
      uri = URI.parse(url)
      result = request(:Get, uri, nil, header)

      # Add the VMs to the list of instances
      instances.concat(result['value'])

      # Continue making requests until there is no longer a nextLink
      url = result['nextLink']
    end

    instances
  end

  # Requests for VMs and scale sets are on a per-subscription basis
  # You can also request VMs by a specific resource group
  # Scale sets are always requested by resource group and scale set name
  #
  # Since each request only returns up to 1,000 results, requests will continue to be
  # sent until there is no longer a nextLink token in the result set
  def ip_addresses(token, creds, opts)
    # XXX What happens if I have multiple IP addresses for a single host?
    url = if opts[:resource_group]
            if opts[:scale_set]
              "https://management.azure.com/subscriptions/#{creds['subscription_id']}/" \
              "resourceGroups/#{opts[:resource_group]}/providers/Microsoft.Compute/" \
              "virtualMachineScaleSets/#{opts[:scale_set]}/" \
              "publicIPAddresses?api-version=2017-03-30"
            else
              "https://management.azure.com/subscriptions/#{creds['subscription_id']}/" \
              "resourceGroups/#{opts[:resource_group]}/providers/Microsoft.Network/" \
              "publicIPAddresses?api-version=2019-07-01"
            end
          else
            "https://management.azure.com/subscriptions/#{creds['subscription_id']}/" \
            "providers/Microsoft.Network/publicIPAddresses?api-version=2019-07-01"
          end

    get_all_results(url, token)
  end

  def vms(token, creds, opts)
    url = if opts[:resource_group]
            if opts[:scale_set]
              "https://management.azure.com/subscriptions/#{creds['subscription_id']}/" \
              "resourceGroups/#{opts[:resource_group]}/providers/Microsoft.Compute/" \
              "virtualMachineScaleSets/#{opts[:scale_set]}/" \
              "virtualmachines?api-version=2017-03-30"
            else
              "https://management.azure.com/subscriptions/#{creds['subscription_id']}/" \
              "resourceGroups/#{opts[:resource_group]}/providers/Microsoft.Compute/" \
              "virtualmachines?api-version=2019-07-01"
            end
          else
            "https://management.azure.com/subscriptions/#{creds['subscription_id']}/" \
            "providers/Microsoft.Compute/virtualmachines?api-version=2019-07-01"
          end

    vms = get_all_results(url, token)

    # Filter by location
    if opts[:location]
      vms.select! { |vm| vm['location'] == opts[:location] }
    end

    # Filter by tags - tags are ANDed
    if opts[:tags]
      # Tag names are case insensitive, values are case sensitive
      expected_tags = opts[:tags].map { |name, value| [name.to_s.downcase, value] }.to_h

      vms.select! do |vm|
        present_tags = vm.fetch('tags', {}).map { |name,value| [name.downcase, value] }.to_h
        # Hash <= checks whether the lhs is a subset of the rhs
        expected_tags <= present_tags
      end
    end

    vms
  end

  def nics(token, creds, opts)
    url = if opts[:resource_group]
            if opts[:scale_set]
              "https://management.azure.com/subscriptions/#{creds['subscription_id']}/" \
              "resourceGroups/#{opts[:resource_group]}/providers/Microsoft.Compute/" \
              "virtualMachineScaleSets/#{opts[:scale_set]}/" \
              "networkinterfaces?api-version=2017-03-30"
            else
              "https://management.azure.com/subscriptions/#{creds['subscription_id']}/" \
              "resourceGroups/#{opts[:resource_group]}/providers/Microsoft.Network/" \
              "networkInterfaces?api-version=2019-07-01"
            end
          else
            "https://management.azure.com/subscriptions/#{creds['subscription_id']}/" \
            "providers/Microsoft.Network/networkInterfaces?api-version=2019-07-01"
          end

    get_all_results(url, token)
  end

  def index_by_id(objects)
    objects.each_with_object({}) do |obj, acc|
      acc[obj['id']] = obj
    end
  end

  # Uses the client credentials grant flow
  # https://docs.microsoft.com/en-us/azure/active-directory/develop/v1-oauth2-client-creds-grant-flow
  def token(creds)
    data = {
      grant_type: 'client_credentials',
      client_id: creds['client_id'],
      client_secret: creds['client_secret'],
      resource: 'https://management.azure.com'
    }

    uri = URI.parse("https://login.microsoftonline.com/#{creds['tenant_id']}/oauth2/token")

    request(:Post, uri, data)
  end

  def request(verb, uri, data, header = {})
    # Create the client
    client = Net::HTTP.new(uri.host, uri.port)

    # Azure REST API always uses SSL
    client.use_ssl = true
    client.verify_mode = OpenSSL::SSL::VERIFY_PEER

    # Build the request
    request = Net::HTTP.const_get(verb).new(uri.request_uri, header)

    # Build the query if there's data to send
    query = URI.encode_www_form(data) if data

    # Send the request
    begin
      response = client.request(request, query)
    rescue StandardError => e
      raise TaskHelper::Error.new(
        "Failed to connect to #{uri}: #{e.message}",
        'bolt.plugin/azure-http-error'
      )
    end

    case response
    when Net::HTTPOK
      JSON.parse(response.body)
    else
      result = JSON.parse(response.body)
      # Some responses have an error_description string and others have an
      # error object with a message string embedded.
      if result.key?('error_description')
        err = result['error_description']
      elsif result['error'].is_a?(Hash) && result['error'].key?('message')
        err = result['error']['message']
      else
        err = "Unknown error"
      end
      m = String.new("#{response.code} \"#{response.msg}\"")
      m += ": #{err}" if err
      raise TaskHelper::Error.new(m, 'bolt.plugin/azure-http-error')
    end
  end

  def task(opts)
    if opts[:scale_set] && !opts[:resource_group]
      msg = "resource_group must be specified in order to filter by scale_set"
      raise TaskHelper::Error.new(msg, 'bolt.plugin/validation-error')
    end

    targets = inventory_targets(opts)
    return { targets: targets }
  rescue TaskHelper::Error => e
    # ruby_task_helper doesn't print errors under the _error key, so we have to
    # handle that ourselves
    return {_error: e.to_h}
  end
end

if __FILE__ == $0
  AzureInventory.run
end
