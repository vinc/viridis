# https://transparency.entsoe.eu/content/static_content/Static%20content/web%20api/Guide.html#_processtype
#
# 400 requests max per minute

class EntsoeData
  include CarbonIntensity

  attr_reader :time

  INTERVALS = {
    "PT60M" => 60.minutes,
    "PT30M" => 30.minutes,
    "PT15M" => 15.minutes,
  }.freeze

  DOMAINS = {
    "at" => "10YAT-APG------L",
    "be" => "10YBE----------2",
    "bg" => "10YCA-BULGARIA-R",
    "ch" => "10YCH-SWISSGRIDZ",
    "cy" => "10YCY-1001A0003J",
    "cz" => "10YCZ-CEPS-----N",
    "de" => "10Y1001A1001A83F",
    "dk" => "10Y1001A1001A65H",
    "ee" => "10Y1001A1001A39I",
    "es" => "10YES-REE------0",
    "fi" => "10YFI-1--------U",
    "fr" => "10YFR-RTE------C",
    "gr" => "10YGR-HTSO-----Y",
    "hr" => "10YHR-HEP------M",
    "hu" => "10YHU-MAVIR----U",
    "ie" => "10YIE-1001A00010",
    "it" => "10YIT-GRTN-----B",
    "lt" => "10YLT-1001A0008Q",
    "lu" => "10YLU-CEGEDEL-NQ",
    "lv" => "10YLV-1001A00074",
    "mt" => "10Y1001A1001A93C",
    "nl" => "10YNL----------L",
    "no" => "10YNO-0--------C",
    "po" => "10YPL-AREA-----S",
    "pt" => "10YPT-REN------W",
    "ro" => "10YRO-TEL------P",
    "se" => "10YSE-1--------K",
    "si" => "10YSI-ELES-----O",
    "so" => "10YSK-SEPS-----K",
    "uk" => "10Y1001A1001A92E",
  }.freeze

  FUELS = {
    "B01" => "Biomass",
    "B02" => "Fossil Brown coal/Lignite",
    "B03" => "Fossil Coal-derived gas",
    "B04" => "Fossil Gas",
    "B05" => "Fossil Hard coal",
    "B06" => "Fossil Oil",
    "B07" => "Fossil Oil shale",
    "B08" => "Fossil Peat",
    "B09" => "Geothermal",
    "B10" => "Hydro Pumped Storage",
    "B11" => "Hydro Run-of-river and poundage",
    "B12" => "Hydro Water Reservoir",
    "B13" => "Marine",
    "B14" => "Nuclear",
    "B15" => "Other renewable",
    "B16" => "Solar",
    "B17" => "Waste",
    "B18" => "Wind Offshore",
    "B19" => "Wind Onshore",
    "B20" => "Other",
  }.freeze

  def self.countries
    DOMAINS.keys
  end

  def self.aggregated(data)
    {
      bio: data["B01"] + data["B17"],
      gas: data["B04"] + data["B03"],
      coal: data["B02"] + data["B05"],
      oil: data["B06"] + data["B07"],
      peat: data["B08"],
      geo: data["B09"],
      storage: data["B10"],
      hydro: data["B11"] + data["B12"],
      marine: data["B13"],
      nuclear: data["B14"],
      other: data["B15"] + data["B20"],
      solar: data["B16"],
      wind: data["B18"] + data["B19"],
    }.reject { |_, v| v == 0 }
  end

  def initialize(country)
    @country = country
  end

  def refresh
    t1 = Time.now.utc.beginning_of_day
    t2 = t1 + 1.day
    fmt = "%Y%m%d%H%M"
    params = {
      "documentType" => "A75",
      "processType" => "A16",
      "in_Domain" => DOMAINS[@country],
      "periodStart" => t1.strftime(fmt),
      "periodEnd" => t2.strftime(fmt),
      "securityToken" => ENV.fetch("ENTSOE_TOKEN", nil),
    }
    url = "https://web-api.tp.entsoe.eu/api?#{params.to_query}"
    res = Rails.cache.fetch("geonde:entsoe:#{@country}:2", expires_in: 30.minutes) do
      Rails.logger.debug { "Fetching \"#{url}\"" }
      RestClient.get(url).body
    end

    @data = Nokogiri::XML(res)
    @time = @data.css("timeInterval end").
      map { |d| Time.zone.parse(d.content) }.
      group_by(&:itself).transform_values(&:size).
      max_by { |item, count| [count, item] }&.first

    self
  rescue RestClient::ServiceUnavailable
    self
  end

  def empty?
    @data.nil? || @data.css("Point").count == 0
  end

  def last
    raise ActiveRecord::RecordNotFound if empty?

    res = {}
    FUELS.each_key { |fuel| res[fuel] ||= 0 }
    @data.css("TimeSeries").each do |ts|
      interval = INTERVALS[ts.css("resolution").first.content]
      fuel = ts.css("psrType").first.content
      start = Time.zone.parse(ts.css("timeInterval start").first.content)
      is_negative = ts.css("[codingScheme]").first.name.start_with?("out")
      i = 0
      v = 0
      ts.css("quantity").each do |q|
        i += 1
        v = q.content.to_i * (is_negative ? -1 : 1)
        d = start + (interval * i)
        res[fuel] += v if d == @time
      end
    end
    res
  end
end
