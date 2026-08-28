"""
    Cases

The 190 AYiL calendar days and the case type keyed on a date.
"""
module Cases

export AbstractMOSAiCAYiLCase,
    MOSAiCAYiLCase,
    MOSAiCAYiL_dates,
    n_cases,
    date_string,
    parse_MOSAiCAYiL_date,
    is_MOSAiCAYiL_date,
    case,
    case_name,
    date_index

using Dates: Dates

abstract type AbstractMOSAiCAYiLCase end

"""The 190 published AYiL dates, ascending (2019-10-16 … 2020-09-11)."""
const MOSAiCAYiL_dates = map(Base.Fix2(Dates.Date, Dates.DateFormat("yyyymmdd")),(
    "20191016", "20191022","20191024", "20191025", "20191026", 
    "20191027", "20191028", "20191029", "20191030", "20191031", 
    "20191101", "20191102", "20191103", "20191105", "20191106", 
    "20191107", "20191108", "20191109", "20191110", "20191111",
    "20191112", "20191113", "20191114", "20191115", "20191125", 
    "20191126", "20191129", "20191130", "20191201", "20191203", 
    "20191204", "20191205", "20191206", "20191209", "20191210", 
    "20191211", "20191212", "20191213", "20191214", "20191215", 
    "20191217", "20191218", "20191219", "20191221", "20191222", 
    "20191223", "20191225", "20191227", "20191229", "20191230", 
    "20191231", "20200101", "20200102", "20200103", "20200105", 
    "20200106", "20200109", "20200110", "20200111", "20200112", 
    "20200114", "20200115", "20200116", "20200117", "20200118", 
    "20200119", "20200120", "20200121", "20200122", "20200123", 
    "20200124", "20200126", "20200127", "20200128", "20200130", 
    "20200131", "20200202", "20200203", "20200204", "20200205", 
    "20200206", "20200207", "20200208", "20200209", "20200210", 
    "20200211", "20200212", "20200214", "20200215", "20200216", 
    "20200217", "20200218", "20200219", "20200220", "20200221", 
    "20200222", "20200223", "20200224", "20200225", "20200226", 
    "20200227", "20200228", "20200301", "20200302", "20200303", 
    "20200304", "20200305", "20200306", "20200307", "20200308", 
    "20200310", "20200311", "20200316", "20200317", "20200318", 
    "20200319", "20200321", "20200323", "20200324", "20200325", 
    "20200326", "20200327", "20200329", "20200330", "20200402", 
    "20200403", "20200404", "20200405", "20200406", "20200407", 
    "20200408", "20200409", "20200410", "20200411", "20200412", 
    "20200413", "20200414", "20200415", "20200416", "20200417", 
    "20200418", "20200419", "20200420", "20200422", "20200423", 
    "20200424", "20200425", "20200426", "20200427", "20200429", 
    "20200430", "20200501", "20200502", "20200503", "20200504", 
    "20200505", "20200506", "20200701", "20200702", "20200706", 
    "20200707", "20200708", "20200709", "20200710", "20200713", 
    "20200714", "20200715", "20200717", "20200720", "20200721", 
    "20200722", "20200723", "20200724", "20200725", "20200726", 
    "20200826", "20200827", "20200828", "20200829", "20200830", 
    "20200831", "20200901", "20200902", "20200903", "20200905", 
    "20200906", "20200907", "20200909", "20200910", "20200911"
))
const MOSAiCAYiL_dates_set = Set(MOSAiCAYiL_dates)

"""Number of published AYiL days."""
n_cases() = 190 #length(MOSAiCAYiL_dates)



date_string(d::Dates.Date) = Dates.format(d, "yyyymmdd")

function parse_MOSAiCAYiL_date(date::AbstractString)
    (length(date) == 8 && all(isdigit, date)) ||
        error("An AYiL date is `yyyymmdd`; got `$date`.")
    return Dates.Date(date, Dates.dateformat"yyyymmdd")
end

parse_MOSAiCAYiL_date(d::Dates.Date) = d

@inline is_MOSAiCAYiL_date(d::Dates.Date) = (d ∈ MOSAiCAYiL_dates_set)

is_MOSAiCAYiL_date(date::AbstractString) = is_MOSAiCAYiL_date(parse_MOSAiCAYiL_date(date))

function _require_MOSAiCAYiL_date(d::Dates.Date)
    is_MOSAiCAYiL_date(d) || error(
        "`$d` is not one of the $(n_cases()) published AYiL days \
         ($(first(MOSAiCAYiL_dates)) … $(last(MOSAiCAYiL_dates))).",
    )
    return d
end

"""
    MOSAiCAYiLCase(date)

One AYiL day, identified by its calendar date.

Accepts a `Date` or a `yyyymmdd` string. The date must be one of the 190 published
days; invalid dates error rather than being silently dropped.
"""
struct MOSAiCAYiLCase <: AbstractMOSAiCAYiLCase
    date::Dates.Date
    function MOSAiCAYiLCase(d::Dates.Date)
        return new(_require_MOSAiCAYiL_date(d))
    end
end

MOSAiCAYiLCase(date::AbstractString) = MOSAiCAYiLCase(parse_MOSAiCAYiL_date(date))

date_string(c::MOSAiCAYiLCase) = date_string(c.date)
parse_MOSAiCAYiL_date(c::MOSAiCAYiLCase) = c.date
is_MOSAiCAYiL_date(c::MOSAiCAYiLCase) = true

Base.show(io::IO, c::MOSAiCAYiLCase) = print(io, "MOSAiCAYiLCase(", date_string(c), ")")

Dates.Date(c::MOSAiCAYiLCase) = c.date

case_name(c::MOSAiCAYiLCase) = "AYiL_$(date_string(c))"

"""
    case(date)

The AYiL case for `date`, given as `yyyymmdd` or a `Date`.
"""
case(date::AbstractString) = MOSAiCAYiLCase(date)
case(date::Dates.Date) = MOSAiCAYiLCase(date)
case(c::MOSAiCAYiLCase) = c

"""Catalog index of `date` in [`MOSAiCAYiL_dates`](@ref), 1-based."""
function date_index(d::Dates.Date)
    i = findfirst(isequal(d), MOSAiCAYiL_dates)
    isnothing(i) && error(
        "`$d` is not one of the $(n_cases()) published AYiL days.",
    )
    return i
end

date_index(c::MOSAiCAYiLCase) = date_index(c.date)
date_index(date::AbstractString) = date_index(parse_MOSAiCAYiL_date(date))

end # module
