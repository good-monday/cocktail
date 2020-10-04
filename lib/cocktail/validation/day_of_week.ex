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

  # Algorithm:
  #
  # For each nth_occurence number, positive as well as negative, we can define a range
  # of days the specific weekday have to be within.
  # If we're within one of these days and that actual weekday is correct, we're good. 
  #
  # For positive numbers:
  # The beginning of the range is (N-1)*7+1 and the end of the range is 
  # min(beginning + 6, last_day_of_month) 
  #
  # For negative number:
  # The end of the range is last_day_of_month + (N+1)*7 and the beginning of the range is 
  # max(1, end - 6)
  #
  # If we're not there we need to either 
  # - Shift to the next higher weekday within the same day range
  # - Shift to the beginning of the next day range
  #
  # Each day range has a bunch of beginnings - we need to shift the first beginning 
  # greater than the current day (maybe that's what next_gte() does).
  #
  # If there are no beginnings left, we shift to first beginning in next month - or just 
  # the first day of the next month
  #
  # Another algorithm could be based on the fact, that once we have the weekday of the first
  # day of the month, we can actually calculate all days. Which means we should be able to 
  # calculate the next in one step
  # 
  # To find the first weekday: goal_weekday - today_weekday + 7 |> mod 7
  # The we multiply with the positive week no.
  #
  # To find the last weekday: 
  # - last weekday of month: first_weekday_of_month + last_day_of_month -1 |> mod(7)
  # - Displacement: last_weekday_of_month - goal_weekday + 7 |> mod(7)
  # - goal: last_day_of_month - displacement
  #
  # displacement: (first_weekday_of_month + last_day_of_month - 1) - goal_weekday |> mod(7)
  #
  # For each day_of_week entry, we can caclulate a list of days. The we can put them together
  # (flatmap) and sort them
  @spec next_time(t, Cocktail.time(), Cocktail.time()) :: Cocktail.Validation.Shift.result()
  def next_time(%__MODULE__{days_of_week: days_of_week}, time, _) do
    first_weekday_of_month = time |> Timex.set(day: 1) |> Timex.weekday()
    last_day_of_month = Timex.days_in_month(time)
    days = day_list(days_of_week, first_weekday_of_month, last_day_of_month)
    diff =
      case next_gte(days, time.day) do
        nil ->
          last_day_of_month - time.day + 1
        
        next_day ->
          next_day - time.day
      end

    shift_by(diff, :days, time, :beginning_of_day)
  end

  defp day_list(days_of_week, first_weekday_of_month, last_day_of_month) do
    days_of_week
    |> Enum.flat_map(&(day_list_entry(&1, first_weekday_of_month, last_day_of_month)))
    |> Enum.sort
  end

  defp day_list_entry({day, nth_occurences}, first_weekday_of_month, last_day_of_month) do
    first_day = (day - first_weekday_of_month + 7) |> mod(7)
    last_day = last_day_of_month - (first_weekday_of_month + last_day_of_month - 1 - day |> mod(7))
    (nth_occurences
    |> Enum.filter(&(&1 > 0))
    |> Enum.map(&((&1-1) * 7 + 1 + first_day)))
    ++
    (nth_occurences
    |> Enum.filter(&(&1 < 0))
    |> Enum.map(&(last_day + (&1+1) * 7)))
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
