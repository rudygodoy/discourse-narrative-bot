require 'excon'

module DiscourseNarrativeBot
  class BitcoinPrice
    MAX_RANGE_VALUE = 10000000
    
    #API_ENDPOINT_TICKER = 'https://blockchain.info/ticker'.freeze
    #API_ENDPOINT_TOBTC  = 'https://blockchain.info/tobtc'.freeze

    API_ENDPOINT_CDBPI  = 'http://api.coindesk.com/v1/bpi/currentprice'.freeze

    CURRENCY_CODES      = {
      "PEN" => I18n.t('discourse_narrative_bot.bitcoinprice.codes.pen'),
      "USD" => I18n.t('discourse_narrative_bot.bitcoinprice.codes.usd'),
      "EUR" => I18n.t('discourse_narrative_bot.bitcoinprice.codes.eur')
    }
    
    def self.tobtc(value, currency="USD")
      if value < 1 || value > MAX_RANGE_VALUE
	return I18n.t('discourse_narrative_bot.bitcoinprice.invalid')
      end

      if CURRENCY_CODES[currency].nil?
	return I18n.t('discourse_narrative_bot.bitcoinprice.invalid')
      end
      
      connection = Excon.new("#{API_ENDPOINT_CBPI}/#{currency}.json")
      response = connection.request(expects: [200, 201], method: :Get)
      results = JSON.parse(response.body)

      price = results["bpi"][currency]["rate_float"]
      btc = price / value
      
      I18n.t('discourse_narrative_bot.bitcoinprice.results', value: value, btc: btc, currency: CURRENCY_CODES[currency])
    end

    def self.price(currency)
      if currency 
    end
  end
end
