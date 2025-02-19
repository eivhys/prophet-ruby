require_relative "test_helper"

class ProphetTest < Minitest::Test
  def setup
    return unless defined?(RubyProf)
    RubyProf.start
  end

  def teardown
    return unless defined?(RubyProf)
    result = RubyProf.stop
    printer = RubyProf::FlatPrinter.new(result)
    printer.print(STDOUT)
  end

  def test_linear
    df = load_example

    m = Prophet.new
    m.fit(df, seed: 123)

    if mac?
      assert_in_delta 8004.75, m.params["lp__"][0], 1
      assert_in_delta -0.359494, m.params["k"][0], 0.01
      assert_in_delta 0.626234, m.params["m"][0]
    end

    future = m.make_future_dataframe(periods: 365)
    assert_times ["2017-01-18 00:00:00 UTC", "2017-01-19 00:00:00 UTC"], future["ds"].tail(2)

    forecast = m.predict(future)
    assert_times ["2017-01-18 00:00:00 UTC", "2017-01-19 00:00:00 UTC"], forecast["ds"].tail(2)
    assert_elements_in_delta [8.243210, 8.261121], forecast["yhat"].tail(2)
    assert_elements_in_delta [7.498851, 7.552077], forecast["yhat_lower"].tail(2)
    assert_elements_in_delta [9.000535, 9.030622], forecast["yhat_upper"].tail(2)

    future = m.make_future_dataframe(periods: 365, include_history: false)
    assert_times ["2016-01-21 00:00:00 UTC", "2016-01-22 00:00:00 UTC"], future["ds"].head(2)

    plot(m, forecast, "linear")
  end

  def test_logistic
    df = Rover.read_csv("examples/example_wp_log_R.csv")
    df["cap"] = 8.5

    m = Prophet.new(growth: "logistic")
    m.fit(df, seed: 123)

    if mac?
      assert_in_delta 9019.8, m.params["lp__"][0], 1
      assert_in_delta 2.07112, m.params["k"][0], 0.1
      assert_in_delta -0.361439, m.params["m"][0], 0.01
    end

    future = m.make_future_dataframe(periods: 365)
    future["cap"] = 8.5

    forecast = m.predict(future)
    assert_times ["2016-12-29 00:00:00 UTC", "2016-12-30 00:00:00 UTC"], forecast["ds"].tail(2)
    assert_elements_in_delta [7.796425, 7.714560], forecast["yhat"].tail(2)
    assert_elements_in_delta [7.503935, 7.398324], forecast["yhat_lower"].tail(2)
    assert_elements_in_delta [8.099635, 7.997564], forecast["yhat_upper"].tail(2)

    plot(m, forecast, "logistic")
  end

  def test_flat
    df = load_example

    m = Prophet.new(growth: "flat")
    m.fit(df, seed: 123)

    if mac?
      assert_in_delta 7494.87, m.params["lp__"][0], 1
      assert_in_delta 0, m.params["k"][0], 0.01
      assert_in_delta 0.63273591, m.params["m"][0]
    end

    future = m.make_future_dataframe(periods: 365)
    assert_times ["2017-01-18 00:00:00 UTC", "2017-01-19 00:00:00 UTC"], future["ds"].tail(2)

    forecast = m.predict(future)
    assert_times ["2017-01-18 00:00:00 UTC", "2017-01-19 00:00:00 UTC"], forecast["ds"].tail(2)
    assert_elements_in_delta [9.086030, 9.103180], forecast["yhat"].tail(2)
    assert_elements_in_delta [8.285740, 8.416043], forecast["yhat_lower"].tail(2)
    assert_elements_in_delta [9.859524, 9.877022], forecast["yhat_upper"].tail(2)

    future = m.make_future_dataframe(periods: 365, include_history: false)
    assert_times ["2016-01-21 00:00:00 UTC", "2016-01-22 00:00:00 UTC"], future["ds"].head(2)

    plot(m, forecast, "flat")
  end

  def test_changepoints
    df = load_example

    m = Prophet.new(changepoints: ["2014-01-01"])
    m.fit(df, seed: 123)
    future = m.make_future_dataframe(periods: 365)
    forecast = m.predict(future)

    plot(m, forecast, "changepoints")
  end

  def test_holidays
    df = load_example

    m = Prophet.new
    m.add_country_holidays("US")
    m.fit(df, seed: 123)

    if mac?
      assert_in_delta 8040.81, m.params["lp__"][0], 1
      assert_in_delta -0.36428, m.params["k"][0], 0.01
      assert_in_delta 0.626888, m.params["m"][0]
    end

    assert m.train_holiday_names

    future = m.make_future_dataframe(periods: 365)
    assert_times ["2017-01-18 00:00:00 UTC", "2017-01-19 00:00:00 UTC"], future["ds"].tail(2)

    forecast = m.predict(future)
    assert_times ["2017-01-18 00:00:00 UTC", "2017-01-19 00:00:00 UTC"], forecast["ds"].tail(2)
    assert_elements_in_delta [8.093708, 8.111485], forecast["yhat"].tail(2)
    assert_elements_in_delta [7.400929, 7.389584], forecast["yhat_lower"].tail(2)
    assert_elements_in_delta [8.863748, 8.867099], forecast["yhat_upper"].tail(2)

    plot(m, forecast, "holidays")
  end

  def test_mcmc_samples
    df = load_example

    m = Prophet.new(mcmc_samples: 3)
    m.fit(df, seed: 123)

    assert_elements_in_delta [963.497, 1006.49], m.params["lp__"][0..1].to_a
    assert_elements_in_delta [7.84723, 7.84723], m.params["stepsize__"][0..1].to_a

    future = m.make_future_dataframe(periods: 365)
    forecast = m.predict(future)

    plot(m, forecast, "mcmc_samples")
  end

  def test_custom_seasonality
    df = load_example

    m = Prophet.new(weekly_seasonality: false)
    m.add_seasonality(name: "monthly", period: 30.5, fourier_order: 5)
    m.fit(df, seed: 123)

    future = m.make_future_dataframe(periods: 365)
    forecast = m.predict(future)

    plot(m, forecast, "custom_seasonality")
  end

  def test_regressors
    df = load_example

    nfl_sunday = lambda do |ds|
      date = ds.respond_to?(:to_date) ? ds.to_date : Date.parse(ds)
      date.wday == 0 && (date.month > 8 || date.month < 2) ? 1 : 0
    end

    df["nfl_sunday"] = df["ds"].map(&nfl_sunday)

    m = Prophet.new
    m.add_regressor("nfl_sunday")
    m.fit(df, seed: 123)

    future = m.make_future_dataframe(periods: 365)
    future["nfl_sunday"] = future["ds"].map(&nfl_sunday)

    forecast = m.predict(future)

    plot(m, forecast, "regressors")
  end

  def test_multiplicative_seasonality
    df = Rover.read_csv("examples/example_air_passengers.csv")
    m = Prophet.new(seasonality_mode: "multiplicative")
    m.fit(df, seed: 123)
    future = m.make_future_dataframe(periods: 50, freq: "MS")
    forecast = m.predict(future)

    assert_times ["1965-01-01 00:00:00 UTC", "1965-02-01 00:00:00 UTC"], forecast["ds"].tail(2)
    assert_elements_in_delta [606.099342, 580.144827], forecast["yhat"].tail(2), 3

    plot(m, forecast, "multiplicative_seasonality")
  end

  def test_subdaily
    df = Rover.read_csv("examples/example_yosemite_temps.csv")
    df["y"][df["y"] == "NaN"] = nil

    m = Prophet.new(changepoint_prior_scale: 0.01)
    m.fit(df, seed: 123)
    # different t_change sampling produces different params

    future = m.make_future_dataframe(periods: 300, freq: "H")
    assert_times ["2017-07-17 11:00:00 UTC", "2017-07-17 12:00:00 UTC"], future["ds"].tail(2)

    forecast = m.predict(future)
    assert_elements_in_delta [7.755761, 7.388094], forecast["yhat"].tail(2), 1
    assert_elements_in_delta [-8.481951, -8.933871], forecast["yhat_lower"].tail(2), 5
    assert_elements_in_delta [22.990261, 23.190911], forecast["yhat_upper"].tail(2), 5

    plot(m, forecast, "subdaily")
  end

  def test_no_changepoints
    df = load_example

    m = Prophet.new(changepoints: [])
    m.fit(df, seed: 123)
    future = m.make_future_dataframe(periods: 365)
    forecast = m.predict(future)
  end

  def test_daru
    df = Daru::DataFrame.from_csv("examples/example_wp_log_peyton_manning.csv")

    m = Prophet.new
    m.fit(df, seed: 123)

    if mac?
      assert_in_delta 8004.75, m.params["lp__"][0], 1
      assert_in_delta -0.359494, m.params["k"][0], 0.01
      assert_in_delta 0.626234, m.params["m"][0]
    end

    future = m.make_future_dataframe(periods: 365)
    assert_times ["2017-01-18 00:00:00 UTC", "2017-01-19 00:00:00 UTC"], future["ds"].tail(2)

    forecast = m.predict(future)
    assert_times ["2017-01-18 00:00:00 UTC", "2017-01-19 00:00:00 UTC"], forecast["ds"].tail(2)
    assert_elements_in_delta [8.243210, 8.261121], forecast["yhat"].tail(2)
    assert_elements_in_delta [7.498851, 7.552077], forecast["yhat_lower"].tail(2)
    assert_elements_in_delta [9.000535, 9.030622], forecast["yhat_upper"].tail(2)

    future = m.make_future_dataframe(periods: 365, include_history: false)
    assert_times ["2016-01-21 00:00:00 UTC", "2016-01-22 00:00:00 UTC"], future["ds"].head(2)
  end

  def test_infinity
    df = load_example
    df["y"][0] = Float::INFINITY
    m = Prophet.new
    error = assert_raises(ArgumentError) do
      m.fit(df)
    end
    assert_equal "Found infinity in column y.", error.message
  end

  private

  def load_example
    Rover.read_csv("examples/example_wp_log_peyton_manning.csv")
  end

  def plot(m, forecast, name)
    fig = m.plot(forecast)
    fig.savefig("/tmp/#{name}.png")
    m.add_changepoints_to_plot(fig.gca, forecast)
    fig.savefig("/tmp/#{name}2.png")
    m.plot_components(forecast).savefig("/tmp/#{name}3.png")
  end

  def mac?
    RbConfig::CONFIG["host_os"] =~ /darwin/i
  end
end
