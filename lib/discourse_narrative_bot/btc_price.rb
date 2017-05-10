require 'excon'

module DiscourseNarrativeBot
  class BitcoinPrice
    MAX_RANGE_VALUE = 10000000
    
    API_ENDPOINT_TICKER = 'https://blockchain.info/ticker'.freeze
    API_ENDPOINT_TOBTC  = 'https://blockchain.info/tobtc'.freeze

    def self.tobtc(value)
      if value < 1 || value > MAX_RANGE_VALUE
	return I18n.t('discourse_narrative_bot.bitcoinprice.invalid')
      end
      
      output = ''
      connection = Excon.new("#{API_ENDPOINT_TOBTC}?currency=USD&value=#{value}")
      response = connection.request(expects: [200, 201], method: :Get)
      btc = response.body.strip

      output << I18n.t('discourse_narrative_bot.bitcoinprice.results', btc: btc)
    end
  end
end
