# frozen_string_literal: true

require 'spec_helper'
require_relative '../../tasks/inventory_targets.rb'

describe AzureInventory do
  def with_env(key, val)
    old_val = ENV[key]
    ENV[key] = val
    yield
  ensure
    ENV[key] = old_val
  end

  def fixture(name)
    JSON.parse(File.read(File.join(__dir__, "../fixtures/responses/#{name}.json")))
  end

  let(:tenant_id) { SecureRandom.uuid }
  let(:client_id) { SecureRandom.uuid }
  let(:client_secret) { SecureRandom.uuid }
  let(:subscription_id) { SecureRandom.uuid }
  let(:opts) do
    { tenant_id: tenant_id,
      client_id: client_id,
      client_secret: client_secret,
      subscription_id: subscription_id }
  end

  before :each do
    # Make sure we don't make any HTTP requests
    allow(subject).to receive(:request).and_return(nil)
  end

  describe "#inventory_targets" do
    before :each do
      allow(subject).to receive(:vms).and_return(fixture('vms'))
      allow(subject).to receive(:ip_addresses).and_return(fixture('ip_addresses'))
      allow(subject).to receive(:nics).and_return(fixture('nics'))
    end

    it 'generates a list of targets with ip addresses' do
      allow(subject).to receive(:token).and_return({})

      targets = [
        { "name" => "rgtest-1", "uri" => "52.160.41.155" },
        { "name" => "test-instance-1", "uri" => "40.118.207.76" }
      ]
      expect(subject.inventory_targets(opts)).to eq(targets)
    end
  end

  describe "#credentials" do
    it 'reads credentials from the supplied options' do
      expect(subject.credentials(opts)).to eq(
        'tenant_id' => tenant_id,
        'client_id' => client_id,
        'client_secret' => client_secret,
        'subscription_id' => subscription_id
      )
    end

    %i[tenant_id client_id client_secret subscription_id].each do |key|
      it "accepts #{key} from the environment" do
        env_key = "AZURE_#{key.upcase}"
        val = opts.delete(key)

        with_env(env_key, val) do
          expect(subject.credentials(opts)).to eq(
            'tenant_id' => tenant_id,
            'client_id' => client_id,
            'client_secret' => client_secret,
            'subscription_id' => subscription_id
          )
        end
      end

      it "fails if #{key} is unset" do
        opts.delete(key)
        expect { subject.credentials(opts) }.to raise_error(TaskHelper::Error, /#{key} must be specified/)
      end
    end
  end

  describe "#get_all_results" do
    let(:token) { { 'token_type' => 'foo', 'access_token' => 'bar' } }

    it 'loops through each page of results' do
      [1,2,3].each do |i|
        uri = URI.parse("https://example.com/page/#{i}")
        response = { 'value' => ["#{i}a", "#{i}b", "#{i}c"],
                     'nextLink' => "https://example.com/page/#{i+1}" }
        allow(subject).to receive(:request).with(:Get, uri, nil, anything).and_return(response)
      end
      uri = URI.parse("https://example.com/page/4")
      response = { 'value' => ["4a", "4b", "4c"] }
      allow(subject).to receive(:request).with(:Get, uri, nil, anything).and_return(response)

      results = subject.get_all_results("https://example.com/page/1", token)
      expect(results).to eq(%w[1a 1b 1c 2a 2b 2c 3a 3b 3c 4a 4b 4c])
    end
  end

  describe "#task" do
    it 'fails if scale_set is requested without resource_group' do
      result = subject.task(scale_set: 'something')
      expect(result).to have_key(:_error)
      expect(result[:_error]['msg']).to match(/resource_group must be specified in order to filter by scale_set/)
    end

    it 'returns the list of targets' do
      targets = [
        { "uri": "1.2.3.4", "name": "my-instance" },
        { "uri": "1.2.3.5", "name": "my-other-instance" }
      ]
      allow(subject).to receive(:inventory_targets).and_return(targets)

      result = subject.task(opts)
      expect(result).to have_key(:targets)
      expect(result[:targets]).to eq(targets)
    end

    it 'returns an error if one is raised' do
      allow(subject).to receive(:inventory_targets).and_raise(TaskHelper::Error.new('something went wrong', 'bolt.test/error'))
      result = subject.task({})

      expect(result).to have_key(:_error)
      expect(result[:_error]['msg']).to match(/something went wrong/)
    end
  end
end
