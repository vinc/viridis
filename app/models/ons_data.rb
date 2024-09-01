# https://www.ons.org.br/paginas/energia-agora/carga-e-geracao/

class OnsData
  include CarbonIntensity

  attr_reader :time

  FUELS = %w[
    hidraulica
    termica
    eolica
    nuclear
    solar
  ].freeze

  def self.aggregated(data)
    {
      thermal: data["termica"],
      hydro: data["hidraulica"],
      nuclear: data["nuclear"],
      solar: data["solar"],
      wind: data["eolica"],
    }.reject { |_, v| v == 0 }
  end

  def refresh
    url = "http://tr.ons.org.br/Content/GetBalancoEnergetico/null"
    res = Rails.cache.fetch("geonde:ons:br:1", expires_in: 15.minutes) do
      Rails.logger.debug { "Fetching \"#{url}\"" }
      RestClient.get(url).body
    end
    @data = JSON.parse(res)
    @time = Time.zone.parse(@data["Data"])
    self
  rescue RestClient::ServiceUnavailable
    self
  end

  def empty?
    @data.nil?
  end

  def last
    raise ActiveRecord::RecordNotFound if empty?

    #res = {}
    res = Hash.new { |h, k| h[k] = 0 }
    @data.each_value do |region|
      d = region["geracao"]
      next unless d

      FUELS.each do |k|
        #(res[k] ||= 0) += d[k].to_f
        res[k] += d[k].to_i
      end
    end

    raise ActiveRecord::RecordNotFound if res.empty?

    res
  end
end
