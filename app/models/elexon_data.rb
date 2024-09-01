# https://bmrs.elexon.co.uk/generation-by-fuel-type

class ElexonData
  include CarbonIntensity

  attr_reader :time

  FUELS = %w[
    BIOMASS
    CCGT
    COAL
    INTELEC
    INTEW
    INTFR
    INTIFA2
    INTIRL
    INTNED
    INTNEM
    INTNSL
    NPSHYD
    NUCLEAR
    OCGT
    OIL
    OTHER
    PS
    WIND
  ].freeze

  def self.aggregated(data)
    {
      bio: data["BIOMASS"],
      gas: data["CCGT"] + data["OCGT"],
      coal: data["COAL"],
      oil: data["OIL"],
      storage: data["PS"],
      hydro: data["NPSHYD"],
      nuclear: data["NUCLEAR"],
      other: data["OTHER"],
      wind: data["WIND"],
    }.reject { |_k, v| v == 0 }
  end

  def refresh
    url = "https://data.elexon.co.uk/bmrs/api/v1/generation/outturn/FUELINSTHHCUR?format=json"
    res = Rails.cache.fetch("geonde:elexon:uk:1", expires_in: 30.minutes) do
      Rails.logger.debug { "Fetching \"#{url}\"" }
      RestClient.get(url).body
    end
    @data = JSON.parse(res)
    @time = Time.zone.now
    self
  rescue RestClient::ServiceUnavailable
    self
  end

  def empty?
    @data.nil?
  end

  def last
    raise ActiveRecord::RecordNotFound if empty?

    res = {}
    FUELS.each { |fuel| res[fuel] ||= 0 }
    @data.each do |d|
      k = d["fuelType"]
      v = d["currentUsage"].to_i
      res[k] = v
    end
    res
  end
end
