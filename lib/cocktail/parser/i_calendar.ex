defmodule Cocktail.Parser.ICalendar do
  @moduledoc """
  Create schedules from iCalendar format.

  TODO: write long description
  """

  alias Cocktail.{Rule, Schedule}

  @time_regex ~r/^:?;?(?:TZID=(.+?):)?(.*?)(Z)?$/
  @datetime_format "{YYYY}{0M}{0D}T{h24}{m}{s}"
  @time_format "{h24}{m}{s}"

  @doc ~S"""
  Parses a string in iCalendar format into a `t:Cocktail.Schedule.t/0`.

  ## Examples

      iex> {:ok, schedule} = parse("DTSTART;TZID=America/Los_Angeles:20170810T160000\nRRULE:FREQ=DAILY;INTERVAL=2")
      ...> schedule
      #Cocktail.Schedule<Every 2 days>

      iex> {:ok, schedule} = parse("DTSTART;TZID=America/Los_Angeles:20170810T160000\nRRULE:FREQ=WEEKLY")
      ...> schedule
      #Cocktail.Schedule<Weekly>

      iex> {:ok, schedule} = parse("DTSTART;TZID=America/Los_Angeles:20170810T160000\nRRULE:FREQ=WEEKLY;BYDAY=MO,WE,FR")
      ...> schedule
      #Cocktail.Schedule<Weekly on Mondays, Wednesdays and Fridays>

      iex> {:ok, schedule} = parse("DTSTART;TZID=America/Los_Angeles:20170810T160000\nRRULE:FREQ=WEEKLY;INTERVAL=2;BYDAY=MO,WE,FR;BYHOUR=10,12,14")
      ...> schedule
      #Cocktail.Schedule<Every 2 weeks on Mondays, Wednesdays and Fridays on the 10th, 12th and 14th hours of the day>
  """
  @spec parse(String.t()) :: {:ok, Schedule.t()} | {:error, term}
  def parse(i_calendar_string) when is_binary(i_calendar_string) do
    i_calendar_string
    |> String.trim()
    |> String.split("\n")
    |> Enum.map(&String.trim/1)
    |> parse_lines(Schedule.new(Timex.now()), 0)
  end

  @spec parse_lines([String.t()], Schedule.t(), non_neg_integer) :: {:ok, Schedule.t()} | {:error, term}
  defp parse_lines([], schedule, _), do: {:ok, schedule}

  defp parse_lines([line | rest], schedule, index) do
    with {:ok, schedule} <- parse_line(line, schedule, index) do
      parse_lines(rest, schedule, index + 1)
    end
  end

  @spec parse_line(String.t(), Schedule.t(), non_neg_integer) :: {:ok, Schedule.t()} | {:error, term}
  defp parse_line("DTSTART" <> time_string, schedule, index), do: parse_dtstart(time_string, schedule, index)
  defp parse_line("DTEND" <> time_string, schedule, index), do: parse_dtend(time_string, schedule, index)
  defp parse_line("RRULE:" <> options_string, schedule, index), do: parse_rrule(options_string, schedule, index)
  defp parse_line("RDATE" <> time_string, schedule, index), do: parse_rdate(time_string, schedule, index)
  defp parse_line("EXDATE" <> time_string, schedule, index), do: parse_exdate(time_string, schedule, index)
  defp parse_line(_, _, index), do: {:error, {:unknown_eventprop, index}}

  @spec parse_dtstart(String.t(), Schedule.t(), non_neg_integer) :: {:ok, Schedule.t()} | {:error, term}
  defp parse_dtstart(time_string, schedule, index) do
    case parse_datetime(time_string) do
      {:ok, datetime} -> {:ok, Schedule.set_start_time(schedule, datetime)}
      {:error, term} -> {:error, {term, index}}
    end
  end

  @spec parse_dtend(String.t(), Schedule.t(), non_neg_integer) :: {:ok, Schedule.t()} | {:error, term}
  defp parse_dtend(time_string, schedule, index) do
    case parse_datetime(time_string) do
      {:ok, datetime} -> {:ok, Schedule.set_end_time(schedule, datetime)}
      {:error, term} -> {:error, {term, index}}
    end
  end

  @spec parse_rrule(String.t(), Schedule.t(), non_neg_integer) :: {:ok, Schedule.t()} | {:error, term}
  defp parse_rrule(options_string, schedule, index) do
    case parse_rrule_options_string(options_string) do
      {:ok, options} ->
        rule = Rule.new(options)
        schedule = Schedule.add_recurrence_rule(schedule, rule)
        {:ok, schedule}

      {:error, term} ->
        {:error, {term, index}}
    end
  end

  @spec parse_datetime(String.t()) :: {:ok, Cocktail.time()} | {:error, term}
  defp parse_datetime(time_string) do
    case Regex.run(@time_regex, time_string) do
      [_, "", time_string] ->
        parse_naive_datetime(time_string)

      [_, "", time_string, "Z"] ->
        parse_utc_datetime(time_string)

      [_, tzid, time_string] ->
        parse_zoned_datetime(time_string, tzid)

      _ ->
        {:error, :invalid_time_format}
    end
  end

  @spec parse_naive_datetime(String.t()) :: {:ok, NaiveDateTime.t()} | {:error, term}
  defp parse_naive_datetime(time_string), do: Timex.parse(time_string, @datetime_format)

  @spec parse_utc_datetime(String.t()) :: {:ok, DateTime.t()} | {:error, term}
  defp parse_utc_datetime(time_string), do: parse_zoned_datetime(time_string, "UTC")

  @spec parse_zoned_datetime(String.t(), String.t()) :: {:ok, DateTime.t()} | {:error, term}
  defp parse_zoned_datetime(time_string, zone) do
    with {:ok, naive_datetime} <- Timex.parse(time_string, @datetime_format),
         %DateTime{} = datetime <- Timex.to_datetime(naive_datetime, zone) do
      {:ok, datetime}
    end
  end

  @spec parse_rrule_options_string(String.t()) :: {:ok, Cocktail.rule_options()} | {:error, term}
  defp parse_rrule_options_string(options_string) do
    options_string
    |> String.split(";")
    |> parse_rrule_options([])
  end

  @spec parse_rrule_options([String.t()], Cocktail.rule_options()) :: {:ok, Cocktail.rule_options()} | {:error, term}
  defp parse_rrule_options([], options), do: {:ok, options}

  defp parse_rrule_options([option_string | rest], options) do
    with {:ok, option} <- parse_rrule_option(option_string) do
      parse_rrule_options(rest, [option | options])
    end
  end

  @spec parse_rrule_option(String.t()) :: {:ok, Cocktail.rule_option()} | {:error, term}
  defp parse_rrule_option("FREQ=" <> frequency_string) do
    with {:ok, frequency} <- parse_frequency(frequency_string) do
      {:ok, {:frequency, frequency}}
    end
  end

  defp parse_rrule_option("INTERVAL=" <> interval_string) do
    with {:ok, interval} <- parse_interval(interval_string) do
      {:ok, {:interval, interval}}
    end
  end

  defp parse_rrule_option("COUNT=" <> count_string) do
    with {:ok, count} <- parse_count(count_string) do
      {:ok, {:count, count}}
    end
  end

  defp parse_rrule_option("UNTIL=" <> until_string) do
    with {:ok, until} <- parse_datetime(until_string) do
      {:ok, {:until, until}}
    end
  end

  defp parse_rrule_option("BYDAY=" <> days_string) do
    if String.first(days_string) in ["+", "-", "0", "1", "2", "3", "4", "5", "6", "7", "8", "9"] do
      with {:ok, days_of_week} <- parse_days_of_week_string(days_string) do
        {:ok, {:days_of_week, days_of_week |> Enum.reverse()}}
      end
    else
      with {:ok, days} <- parse_days_string(days_string) do
        {:ok, {:days, days |> Enum.reverse()}}
      end
    end
  end

  defp parse_rrule_option("BYHOUR=" <> hours_string) do
    with {:ok, hours} <- parse_hours_string(hours_string) do
      {:ok, {:hours, hours |> Enum.reverse()}}
    end
  end

  defp parse_rrule_option("BYMINUTE=" <> minutes_string) do
    with {:ok, minutes} <- parse_minutes_string(minutes_string) do
      {:ok, {:minutes, minutes |> Enum.reverse()}}
    end
  end

  defp parse_rrule_option("BYSECOND=" <> seconds_string) do
    with {:ok, seconds} <- parse_seconds_string(seconds_string) do
      {:ok, {:seconds, seconds |> Enum.reverse()}}
    end
  end

  # backwards compatible parsing for schedules generated pre-0.8
  defp parse_rrule_option("BYTIME=" <> times_string), do: parse_rrule_option("X-BYTIME=" <> times_string)

  defp parse_rrule_option("X-BYTIME=" <> times_string) do
    with {:ok, times} <- parse_times_string(times_string) do
      {:ok, {:times, times |> Enum.reverse()}}
    end
  end

  defp parse_rrule_option("X-BYRANGE=" <> range_string) do
    with {:ok, time_range} <- parse_range_string(range_string) do
      {:ok, {:time_range, time_range}}
    end
  end

  defp parse_rrule_option(_), do: {:error, :unknown_rrulparam}

  @type parse_result :: ({:ok, any()} | {:error, atom()})
  @type parse_fun :: (any() -> parse_result())
  @spec parse_bind(parse_result(), parse_fun()) :: parse_result()
  defp parse_bind(val, fun) do
    case val do
      {:ok, value} -> fun.(value)
      {:error, reason} -> {:error, reason}
    end
  end

  @spec parse_error_reduce([parse_result()]) :: [any()] | {:error, atom()}
  defp parse_error_reduce(list) do
    list
    |> Enum.reduce({:ok, []}, fn (val, acc) ->
      parse_bind(acc, fn (list) -> parse_bind(val, &({:ok,[&1 | list]})) end) 
    end)
  end

  @spec parse_frequency(String.t()) :: {:ok, Cocktail.frequency()} | {:error, :invalid_frequency}
  defp parse_frequency("MONTHLY"), do: {:ok, :monthly}
  defp parse_frequency("WEEKLY"), do: {:ok, :weekly}
  defp parse_frequency("DAILY"), do: {:ok, :daily}
  defp parse_frequency("HOURLY"), do: {:ok, :hourly}
  defp parse_frequency("MINUTELY"), do: {:ok, :minutely}
  defp parse_frequency("SECONDLY"), do: {:ok, :secondly}
  defp parse_frequency(_), do: {:error, :invalid_frequency}

  @spec parse_interval(String.t()) :: {:ok, pos_integer} | {:error, :invalid_interval}
  defp parse_interval(interval_string) do
    with {integer, _} <- Integer.parse(interval_string),
         {:ok, interval} <- validate_positive(integer) do
      {:ok, interval}
    else
      :error -> {:error, :invalid_interval}
    end
  end

  @spec parse_count(String.t()) :: {:ok, pos_integer} | {:error, :invalid_count}
  defp parse_count(count_string) do
    with {integer, _} <- Integer.parse(count_string),
         {:ok, count} <- validate_positive(integer) do
      {:ok, count}
    else
      :error -> {:error, :invalid_count}
    end
  end

  @spec validate_positive(integer) :: {:ok, pos_integer} | :error
  defp validate_positive(n) when n > 0, do: {:ok, n}
  defp validate_positive(_), do: :error

  @spec parse_days_string(String.t()) :: {:ok, [Cocktail.day_atom()]} | {:error, :invalid_days}
  defp parse_days_string(""), do: {:error, :invalid_days}

  defp parse_days_string(days_string) do
    days_string
    |> String.split(",")
    |> parse_days([])
  end

  @spec parse_days([String.t()], [Cocktail.day_atom()]) :: {:ok, [Cocktail.day_atom()]}
  defp parse_days([], days), do: {:ok, days}

  defp parse_days([day_string | rest], days) do
    with {:ok, day} <- parse_day(day_string) do
      parse_days(rest, [day | days])
    end
  end

  @spec parse_day(String.t()) :: {:ok, Cocktail.day_atom()} | {:error, :invalid_day}
  defp parse_day("SU"), do: {:ok, :sunday}
  defp parse_day("MO"), do: {:ok, :monday}
  defp parse_day("TU"), do: {:ok, :tuesday}
  defp parse_day("WE"), do: {:ok, :wednesday}
  defp parse_day("TH"), do: {:ok, :thursday}
  defp parse_day("FR"), do: {:ok, :friday}
  defp parse_day("SA"), do: {:ok, :saturday}
  defp parse_day(_), do: {:error, :invalid_day}

  @spec parse_days_of_week_string(String.t()) :: {:ok, [Cocktail.day_of_week()]} 
                                               | {:error, :invalid_day | :invalid_nth_occurence} 
  defp parse_days_of_week_string(days_of_week_string) do
    days_of_week_string
    |> String.split(",")
    |> Enum.map(&parse_day_of_week_string/1)
    |> parse_error_reduce
    |> parse_bind(fn l -> {:ok, Enum.group_by(l, &(elem(&1, 0)))} end)
    |> parse_bind(fn l -> {:ok, Enum.map(l, fn {day_atom, list} -> {day_atom, Enum.map(list, &(elem(&1, 1)))} end)} end)
  end

  @spec parse_day_of_week_string(String.t()) :: {:ok, {Cocktail.day_atom(), [integer()]}} 
                                              | {:error, :invalid_day | :invalid_nth_occurence} 
  defp parse_day_of_week_string(days_of_week_string) do
    {num, day} = String.split_at(days_of_week_string, -2)
    parse_day(day)
    |> parse_bind(fn (day_atom) -> 
      parse_nth_occurence(num) |> parse_bind(&({:ok, {day_atom, &1}})) 
    end)
  end

  @spec parse_nth_occurence(String.t()) :: {:ok, Cocktail.nth_occurence()} | {:error, :invalid_nth_occurence}
  defp parse_nth_occurence(nth_occurence_string) do
    with {integer, _} <- Integer.parse(nth_occurence_string),
         {:ok, nth_occurence} <- validate_nth_occurence(integer) do
      {:ok, nth_occurence}
    else
      :error -> {:error, :invalid_nth_occurence}
    end
  end

  @spec validate_nth_occurence(integer) :: {:ok, Cocktail.nth_occurence()} | :error
  defp validate_nth_occurence(n) when (n >= 1 and n <= 5) or (n <= -1 and n >= -5), do: {:ok, n}
  defp validate_nth_occurence(_), do: :error

  # hour of day

  @spec parse_hours_string(String.t()) :: {:ok, [Cocktail.hour_number()]} | {:error, :invalid_hours}
  defp parse_hours_string(""), do: {:error, :invalid_hours}

  defp parse_hours_string(hours_string) do
    hours_string
    |> String.split(",")
    |> parse_hours([])
  end

  @spec parse_hours([String.t()], [Cocktail.hour_number()]) :: {:ok, [Cocktail.hour_number()]}
  defp parse_hours([], hours), do: {:ok, hours}

  defp parse_hours([hour_string | rest], hours) do
    with {:ok, hour} <- parse_hour(hour_string) do
      parse_hours(rest, [hour | hours])
    end
  end

  @spec parse_hour(String.t()) :: {:ok, Cocktail.hour_number()} | {:error, :invalid_hour}
  defp parse_hour(hour_string) do
    with {integer, _} <- Integer.parse(hour_string),
         {:ok, hour} <- validate_hour(integer) do
      {:ok, hour}
    else
      :error -> {:error, :invalid_hour}
    end
  end

  @spec validate_hour(integer) :: {:ok, Cocktail.hour_number()} | :error
  defp validate_hour(n) when n >= 0 and n < 24, do: {:ok, n}
  defp validate_hour(_), do: :error

  # minute of hour

  @spec parse_minutes_string(String.t()) :: {:ok, [Cocktail.minute_number()]} | {:error, :invalid_minutes}
  defp parse_minutes_string(""), do: {:error, :invalid_minutes}

  defp parse_minutes_string(minutes_string) do
    minutes_string
    |> String.split(",")
    |> parse_minutes([])
  end

  @spec parse_minutes([String.t()], [Cocktail.minute_number()]) :: {:ok, [Cocktail.minute_number()]}
  defp parse_minutes([], minutes), do: {:ok, minutes}

  defp parse_minutes([minute_string | rest], minutes) do
    with {:ok, minute} <- parse_minute(minute_string) do
      parse_minutes(rest, [minute | minutes])
    end
  end

  @spec parse_minute(String.t()) :: {:ok, Cocktail.minute_number()} | {:error, :invalid_minute}
  defp parse_minute(minute_string) do
    with {integer, _} <- Integer.parse(minute_string),
         {:ok, minute} <- validate_minute(integer) do
      {:ok, minute}
    else
      :error -> {:error, :invalid_minute}
    end
  end

  @spec validate_minute(integer) :: {:ok, Cocktail.minute_number()} | :error
  defp validate_minute(n) when n >= 0 and n < 60, do: {:ok, n}
  defp validate_minute(_), do: :error

  # second of minute

  @spec parse_seconds_string(String.t()) :: {:ok, [Cocktail.second_number()]} | {:error, :invalid_seconds}
  defp parse_seconds_string(""), do: {:error, :invalid_seconds}

  defp parse_seconds_string(seconds_string) do
    seconds_string
    |> String.split(",")
    |> parse_seconds([])
  end

  @spec parse_seconds([String.t()], [Cocktail.second_number()]) :: {:ok, [Cocktail.second_number()]}
  defp parse_seconds([], seconds), do: {:ok, seconds}

  defp parse_seconds([second_string | rest], seconds) do
    with {:ok, second} <- parse_second(second_string) do
      parse_seconds(rest, [second | seconds])
    end
  end

  @spec parse_second(String.t()) :: {:ok, Cocktail.second_number()} | {:error, :invalid_second}
  defp parse_second(second_string) do
    with {integer, _} <- Integer.parse(second_string),
         {:ok, second} <- validate_second(integer) do
      {:ok, second}
    else
      :error -> {:error, :invalid_second}
    end
  end

  @spec validate_second(integer) :: {:ok, Cocktail.second_number()} | :error
  defp validate_second(n) when n >= 0 and n < 60, do: {:ok, n}
  defp validate_second(_), do: :error

  # time of day

  @spec parse_times_string(String.t()) :: {:ok, [Time.t()]} | {:error, :invalid_times}
  defp parse_times_string(""), do: {:error, :invalid_times}

  defp parse_times_string(times_string) do
    times_string
    |> String.split(",")
    |> parse_times([])
  end

  @spec parse_times([String.t()], [Time.t()]) :: {:ok, [Time.t()]} | {:error, :invalid_time_format}
  defp parse_times([], times), do: {:ok, times}

  defp parse_times([time_string | rest], times) do
    with {:ok, time} <- parse_time(time_string) do
      parse_times(rest, [time | times])
    end
  end

  @spec parse_time(String.t()) :: {:ok, Time.t()} | {:error, :invalid_time_format}
  defp parse_time(time_string) do
    case Timex.parse(time_string, @time_format) do
      {:ok, datetime} -> {:ok, NaiveDateTime.to_time(datetime)}
      _error -> {:error, :invalid_time_format}
    end
  end

  # time range

  @spec parse_range_string(String.t()) :: {:ok, Cocktail.time_range()} | {:error, :invalid_time_range}
  defp parse_range_string(""), do: {:error, :invalid_time_range}

  defp parse_range_string(range_string) do
    range_string
    |> String.split(",")
    |> parse_range()
  end

  @spec parse_range([String.t()]) :: {:ok, Cocktail.time_range()}
  defp parse_range([start_time_string, end_time_string, interval_seconds_string]) do
    with {:ok, start_time} <- parse_time(start_time_string),
         {:ok, end_time} <- parse_time(end_time_string),
         {interval_seconds, _} <- Integer.parse(interval_seconds_string) do
      time_range = %{
        start_time: start_time,
        end_time: end_time,
        interval_seconds: interval_seconds
      }

      {:ok, time_range}
    else
      _ ->
        {:error, :invalid_time_range}
    end
  end

  defp parse_range(_), do: {:error, :invalid_time_range}

  # rdates and exdates

  @spec parse_rdate(String.t(), Schedule.t(), non_neg_integer) :: {:ok, Schedule.t()} | {:error, term}
  defp parse_rdate(time_string, schedule, index) do
    case parse_datetime(time_string) do
      {:ok, datetime} -> {:ok, Schedule.add_recurrence_time(schedule, datetime)}
      {:error, term} -> {:error, {term, index}}
    end
  end

  @spec parse_exdate(String.t(), Schedule.t(), non_neg_integer) :: {:ok, Schedule.t()} | {:error, term}
  defp parse_exdate(time_string, schedule, index) do
    case parse_datetime(time_string) do
      {:ok, datetime} -> {:ok, Schedule.add_exception_time(schedule, datetime)}
      {:error, term} -> {:error, {term, index}}
    end
  end
end
