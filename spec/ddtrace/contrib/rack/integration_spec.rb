require 'ddtrace/contrib/support/spec_helper'

require 'ddtrace/contrib/rack/integration'

RSpec.describe Datadog::Contrib::Rack::Integration do
  extend ConfigurationHelpers

  let(:integration) { described_class.new(:rack) }

  describe '.version' do
    subject(:version) { described_class.version }

    context 'when the "rack" gem is loaded' do
      include_context 'loaded gems', rack: described_class::MINIMUM_VERSION
      it { is_expected.to be_a_kind_of(Gem::Version) }
    end

    context 'when "rack" gem is not loaded' do
      include_context 'loaded gems', rack: nil
      it { is_expected.to be nil }
    end
  end

  describe '.loaded?' do
    subject(:loaded?) { described_class.loaded? }

    context 'when Rack is defined' do
      before { stub_const('Rack', Class.new) }
      it { is_expected.to be true }
    end

    context 'when Rack is not defined' do
      before { hide_const('Rack') }
      it { is_expected.to be false }
    end
  end

  describe '.compatible?' do
    subject(:compatible?) { described_class.compatible? }

    context 'when "rack" gem is loaded with a version' do
      context 'that is less than the minimum' do
        include_context 'loaded gems', rack: decrement_gem_version(described_class::MINIMUM_VERSION)
        it { is_expected.to be false }
      end

      context 'that meets the minimum version' do
        include_context 'loaded gems', rack: described_class::MINIMUM_VERSION
        it { is_expected.to be true }
      end
    end

    context 'when gem is not loaded' do
      include_context 'loaded gems', rack: nil
      it { is_expected.to be false }
    end
  end

  describe '#auto_instrument?' do
    subject(:auto_instrument?) { integration.auto_instrument? }

    context 'outside of a rails application' do
      before do
        allow(Datadog::Utils::Rails).to receive(:railtie_supported?).and_return(false)
      end

      it { is_expected.to be(true) }
    end

    context 'when within a rails application' do
      before do
        allow(Datadog::Utils::Rails).to receive(:railtie_supported?).and_return(true)
      end

      it { is_expected.to be(false) }
    end
  end

  describe '#default_configuration' do
    subject(:default_configuration) { integration.default_configuration }
    it { is_expected.to be_a_kind_of(Datadog::Contrib::Rack::Configuration::Settings) }
  end

  describe '#patcher' do
    subject(:patcher) { integration.patcher }
    it { is_expected.to be Datadog::Contrib::Rack::Patcher }
  end
end
