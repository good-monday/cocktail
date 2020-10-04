defmodule Cocktail.Validation.DayOfWeek do
  @moduledoc false

  import Cocktail.Validation.Shift
  import Cocktail.Util, only: [next_gte: 2]
  import Integer, only: [mod: 2]

  @type t :: %__MODULE__{days_of_week: [Cocktail.day_of_week()]}

  @enforce_keys [:days_of_week]
  defstruct days_of_week: []

  @spec new([Cocktail.day_of_week()]) :: t
  def new(days_of_week), do: %__MODULE__{days_of_week: days_of_week |> Enum.map(&day_of_week/1) |> Enum.sort()}

  @spec next_time(t, Cocktail.time(), Cocktail.time()) :: Cocktail.Validation.Shift.result()
  def next_time(%__MODULE__{days_of_week: days_of_week}, time, _) do
    days = Enum.map(days_of_week, &(elem(&1,0)))
    IO.puts "days: #{inspect days}"
    current_day = Timex.weekday(time)
    day = next_gte(days, current_day) || hd(days)
    diff = (day - current_day) |> mod(7)

    shift_by(diff, :days, time, :beginning_of_day)
  end

  @spec day_of_week(Cocktail.day_of_week()) :: {Cocktail.day_number, [Cocktail.nth_occurence]}
  defp day_of_week({day, nth_occurences}), do: {day_number(day), nth_occurences}

  @spec day_number(Cocktail.day()) :: Cocktail.day_number()
  defp day_number(:sunday), do: 0
  defp day_number(:monday), do: 1
  defp day_number(:tuesday), do: 2
  defp day_number(:wednesday), do: 3
  defp day_number(:thursday), do: 4
  defp day_number(:friday), do: 5
  defp day_number(:saturday), do: 6
  defp day_number(day) when is_integer(day), do: day
end
