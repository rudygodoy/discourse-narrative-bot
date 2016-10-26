require 'rails_helper'

describe DiscourseNarrativeBot::Store do
  describe '.set' do
    it 'should set the right value in the plugin store' do
      described_class.set(10, 'yay')
      plugin_store_row = PluginStoreRow.last

      expect(plugin_store_row.value).to eq('yay')
      expect(plugin_store_row.plugin_name).to eq(DiscourseNarrativeBot::PLUGIN_NAME)
      expect(plugin_store_row.key).to eq(described_class.key(10))
    end
  end

  describe '.get' do
    it 'should get the right value from the plugin store' do
      PluginStoreRow.create!(
        plugin_name: DiscourseNarrativeBot::PLUGIN_NAME,
        key: described_class.key(10),
        value: 'yay',
        type_name: 'string'
      )

      expect(described_class.get(10)).to eq('yay')
    end
  end
end
