"""
    generate_assets.jl

Write the figures `docs/src/assets` holds.

    julia --project=docs/generate_assets docs/generate_assets/generate_assets.jl

Everything drawn here comes from the committed tables, so this needs no archive and no
network. Run it when a table is regenerated.
"""

using CairoMakie: CairoMakie as MK
using Dates: Dates
using MOSAiCAYiL: MOSAiCAYiL as MA

const ASSETS = joinpath(dirname(@__DIR__), "src", "assets")

"Month-boundary tick positions and `yyyy-mm` labels for the 190-day catalog."
function month_ticks(dates)
    months = map(d -> (Dates.year(d), Dates.month(d)), dates)
    at = [i for i in eachindex(months) if i == 1 || months[i] != months[i - 1]]
    return (at, [Dates.format(dates[i], "yyyy-mm") for i in at])
end

function vertical_grid_figure()
    faces = Float64.(MA.LES_FACES)
    dz = diff(faces)
    centres = (faces[1:(end - 1)] .+ faces[2:end]) ./ 2

    fig = MK.Figure(size = (900, 380))
    ax1 = MK.Axis(
        fig[1, 1];
        xlabel = "cell thickness Δz [m]", ylabel = "height [m]",
        title = "DALES vertical grid ($(length(faces)) faces)",
        yscale = log10,
    )
    MK.lines!(ax1, dz, centres; color = :black)
    MK.scatter!(ax1, dz, centres; color = :black, markersize = 3)
    MK.ylims!(ax1, 5, 1.3e4)

    ax2 = MK.Axis(
        fig[1, 2];
        xlabel = "level index", ylabel = "height [m]",
        title = "face heights",
    )
    MK.lines!(ax2, eachindex(faces), faces; color = :black)
    MK.hlines!(ax2, [1220.0, 7139.301]; color = :grey, linestyle = :dash)
    MK.text!(ax2, 10, 1600; text = "uniform 10 m below 1220 m", fontsize = 10)
    MK.text!(ax2, 10, 8200; text = "uniform ≈185 m above 7139 m", fontsize = 10)

    MK.save(joinpath(ASSETS, "vertical_grid.png"), fig; px_per_unit = 2)
    return nothing
end

function catalog_figure()
    dates = collect(MA.MOSAiCAYiL_dates)
    idx = eachindex(dates)
    at, labels = month_ticks(dates)

    inversion = collect(MA.DAY_METADATA.inversion_height)
    levels = collect(MA.DAY_METADATA.n_levels)
    top_i = [i for i in idx if haskey(MA.CLOUD_TOP_M, MA.date_string(dates[i]))]
    tops = [MA.CLOUD_TOP_M[MA.date_string(dates[i])] for i in top_i]

    fig = MK.Figure(size = (900, 620))
    ax1 = MK.Axis(
        fig[1, 1];
        ylabel = "height [m]",
        title = "Inversion height and cloud top over the MOSAiC drift",
        xticks = (at, labels), xticklabelrotation = π / 4,
    )
    MK.lines!(ax1, idx, inversion; color = :black, label = "inversion height")
    MK.scatter!(ax1, top_i, tops; color = :firebrick, markersize = 7, label = "cloud top")
    MK.axislegend(ax1; position = :lt, framevisible = false)

    ax2 = MK.Axis(
        fig[2, 1];
        ylabel = "scm_in full levels", xlabel = "AYiL day",
        xticks = (at, labels), xticklabelrotation = π / 4,
    )
    MK.scatter!(ax2, idx, levels; color = :black, markersize = 5)
    MK.ylims!(ax2, minimum(levels) - 1, maximum(levels) + 1)

    MK.linkxaxes!(ax1, ax2)
    MK.save(joinpath(ASSETS, "catalog.png"), fig; px_per_unit = 2)
    return nothing
end

function saturation_figure()
    b = MA.DefaultThermodynamicsBackend()
    T = 220.0:0.5:290.0
    fig = MK.Figure(size = (900, 380))

    ax1 = MK.Axis(
        fig[1, 1];
        xlabel = "temperature [K]", ylabel = "saturation vapour pressure [Pa]",
        title = "Saturation vapour pressure", yscale = log10,
    )
    MK.lines!(ax1, T, MA.saturation_vapor_pressure_liq.(b, T); label = "Murphy–Koop liquid")
    MK.lines!(ax1, T, MA.saturation_vapor_pressure_ice.(b, T); label = "Murphy–Koop ice")
    MK.lines!(
        ax1, T, MA.tetens_saturation_vapor_pressure.(b, T);
        linestyle = :dash, label = "Tetens liquid (surface)",
    )
    MK.axislegend(ax1; position = :lt, framevisible = false)

    ax2 = MK.Axis(
        fig[1, 2];
        xlabel = "temperature [K]", ylabel = "Tetens / Murphy–Koop − 1 [%]",
        title = "Tetens relative to Murphy–Koop, over liquid",
    )
    ratio = @. 100 * (
        MA.tetens_saturation_vapor_pressure(b, T) /
        MA.saturation_vapor_pressure_liq(b, T) - 1
    )
    MK.lines!(ax2, T, ratio; color = :black)
    MK.hlines!(ax2, [0.0]; color = :grey, linestyle = :dash)

    MK.save(joinpath(ASSETS, "saturation.png"), fig; px_per_unit = 2)
    return nothing
end

function generate_assets()
    mkpath(ASSETS)
    vertical_grid_figure()
    catalog_figure()
    saturation_figure()
    println("wrote ", join(sort(readdir(ASSETS)), ", "), " to $ASSETS")
    return nothing
end
