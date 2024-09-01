# https://bmrs.elexon.co.uk/generation-by-fuel-type

class EirgridData
  attr_reader :time

  def self.aggregated(data)
    {}
  end

  def refresh
    t1 = Time.now.in_time_zone("Europe/Dublin").beginning_of_day
    t2 = Time.now.in_time_zone("Europe/Dublin").end_of_day
    fmt = "%d-%h-%Y+%H:%M"
    api = "https://www.smartgriddashboard.com/DashboardService.svc/data"
    url = "#{api}?area=co2intensity&region=ALL&datefrom=#{t1.strftime(fmt)}&dateto=#{t2.strftime(fmt)}"
    res = Rails.cache.fetch("geonde:eirgrid:ei:1", expires_in: 15.minutes) do
      Rails.logger.debug { "Fetching \"#{url}\"" }
      RestClient.get(url).body
    end
    @data = JSON.parse(res)
    @time = @data["LastUpdated"].in_time_zone("Europe/Dublin")
    self
  rescue RestClient::ServiceUnavailable
    self
  end

  def empty?
    @data.nil?
  end

  def last
    raise ActiveRecord::RecordNotFound if empty?
  end

  def official_carbon_intensity
    @data["Rows"].pluck("Value").compact.last.to_f
  end

  def self.carbon_intensity(data, factors = "nrel")
  end
end
